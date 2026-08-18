classdef GratingMeasurements < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Grating leading duration (ms)
        stimTime = 5000                 % Grating duration (ms)
        tailTime = 500                  % Grating trailing duration (ms)
        waitTime = 0                    % Grating wait duration (ms)
        contrasts = [0.25 .5 1.0]                  % Grating contrasts (0-1)
        orientation = 0.0               % Grating orientation (deg)
        barWidths = [10 20 40 80 90 100 200 400 800 1000 2000] % Bar widths (microns)
        numReps = 4                     %number of epochs per condition
        temporalFrequencies = [0.5 1 2.0]         % Temporal frequencies (Hz)
        spatialPhase = 0.0              % Spatial phase of grating (deg)
        backgroundIntensity = 0.5       % Background light intensity (0-1)
        centerOffset = [0,0]            % Center offset in pixels (x,y)
        apertureRadius = 0              % Aperture radius in pixels.
        apertureClass = 'spot'          % Spot or annulus?       
        spatialClass = 'squarewave'       % Spatial type (sinewave or squarewave)
        temporalClass = 'drifting'      % Temporal type (drifting or reversing)      
        onlineAnalysis = 'none'         % Type of online analysis
    end
    
    properties (Hidden)
        ampType
        apertureClassType = symphonyui.core.PropertyType('char', 'row', {'spot', 'annulus'})
        spatialClassType = symphonyui.core.PropertyType('char', 'row', {'sinewave', 'squarewave'})
        temporalClassType = symphonyui.core.PropertyType('char', 'row', {'drifting', 'reversing'})
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        barWidthsType = symphonyui.core.PropertyType('denserealdouble','matrix')
        spatialFrequency
        barWidth
        contrast
        temporalFrequency
        widths
        contrastSeq
        temporalFreqSeq
        phaseShift
        allCombos
    end

    properties (Dependent)
        numberOfAverages
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            % obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            % 
            % if ~strcmp(obj.onlineAnalysis, 'none')
            %     obj.showFigure('manookinlab.figures.sMTFFigure', ...
            %         obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
            %         'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
            %         'temporalType', obj.temporalClass, 'spatialType', 'spot', ...
            %         'xName', 'barWidth', 'xaxis', unique(obj.barWidths), ...
            %         'temporalFrequency', obj.temporalFrequency);
            % end
            
            % Organize stimulus and analysis parameters.
            obj.organizeParameters();
        end
        
        function p = createPresentation(obj)
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            barWidthPix = obj.rig.getDevice('Stage').um2pix(obj.barWidth);
            % Create the grating.
            switch obj.spatialClass
                case 'sinewave'
                    grate = stage.builtin.stimuli.Grating('sine');
                otherwise % Square-wave grating
                    grate = stage.builtin.stimuli.Grating('square'); 
            end
            grate.orientation = obj.orientation;
            if obj.apertureRadius > 0 && obj.apertureRadius < max(obj.canvasSize/2) && strcmpi(obj.apertureClass, 'spot')
                grate.size = 2*obj.apertureRadius*ones(1,2);
            else
                grate.size = max(obj.canvasSize) * ones(1,2);
            end
            grate.position = obj.canvasSize/2 + obj.centerOffset;
            grate.spatialFreq = 1/(2*barWidthPix); %convert from bar width to spatial freq
            grate.contrast = obj.contrast;
            grate.color = 2*obj.backgroundIntensity;
            
            %calc to apply phase shift s.t. a contrast-reversing boundary
            %is in the center regardless of spatial frequency. Arbitrarily
            %say boundary should be positve to right and negative to left
            %crosses x axis from neg to pos every period from 0
            zeroCrossings = 0:(grate.spatialFreq^-1):grate.size(1); 
            offsets = zeroCrossings-grate.size(1)/2; %difference between each zero crossing and center of texture, pixels
            [~, minIdx] = min(abs(offsets));
            shiftPix = offsets(minIdx);
            
            
            % [shiftPix, ~] = min(offsets); % min(offsets(offsets>0)); %positive shift in pixels
            phaseShift_rad = (shiftPix/(grate.spatialFreq^-1))*(2*pi); %phaseshift in radians
            obj.phaseShift = 360*(phaseShift_rad)/(2*pi); %phaseshift in degrees
            grate.phase = obj.phaseShift + obj.spatialPhase; %keep contrast reversing boundary in center
            
            % Add the grating.
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(grateVisible);
            
            %--------------------------------------------------------------
            % Control the grating phase.
            if strcmp(obj.temporalClass, 'drifting')
                imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                    @(state)setDriftingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'phase',...
                    @(state)setReversingGrating(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
            end
            p.addController(imgController);
            
            % Set the drifting grating.
            function phase = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                phase = phase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
            % Set the reversing grating
            function phase = setReversingGrating(obj, time)
                if time >= 0
                    phase = round(0.5 * sin(time * 2 * pi * obj.temporalFrequency) + 0.5) * pi;
                else
                    phase = 0;
                end
                
                phase = phase*180/pi + obj.phaseShift + obj.spatialPhase;
            end
            
%             if (obj.temporalFrequency > 0) 
%                 grateContrast = stage.builtin.controllers.PropertyController(grate, 'contrast',...
%                     @(state)getGrateContrast(obj, state.time - (obj.preTime + obj.waitTime) * 1e-3));
%                 p.addController(grateContrast); %add the controller
%             end
%             function c = getGrateContrast(obj, time)
%                 if time > 0
%                     c = obj.contrast.*sin(2 * pi * obj.temporalFrequency * time);
%                 else
%                     c = 0;
%                 end
%             end

            if obj.apertureRadius > 0
                if strcmpi(obj.apertureClass, 'spot')
                    aperture = stage.builtin.stimuli.Rectangle();
                    aperture.position = obj.canvasSize/2 + obj.centerOffset;
                    aperture.color = obj.backgroundIntensity;
                    aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
                    mask = stage.core.Mask.createCircularAperture(obj.apertureRadius*2/max(obj.canvasSize), 1024);
                    aperture.setMask(mask);
                    p.addStimulus(aperture);
                else
                    mask = stage.builtin.stimuli.Ellipse();
                    mask.color = obj.backgroundIntensity;
                    mask.radiusX = obj.apertureRadius;
                    mask.radiusY = obj.apertureRadius;
                    mask.position = obj.canvasSize / 2 + obj.centerOffset;
                    p.addStimulus(mask);
                end
            end
        end
        
        % This is a method of organizing stimulus parameters.
        function organizeParameters(obj)
            % Full factorial of barWidths x contrasts x temporalFrequencies.
            [W, C, T] = meshgrid(obj.barWidths, obj.contrasts, obj.temporalFrequencies);
            combos = [W(:), C(:), T(:)];
            disp('Size of combos:', size(combos,1))
            nConditions = size(combos, 1);
        
            % Build numReps shuffled blocks — each block contains every
            % condition once in random order, so repeats are interleaved.
            obj.allCombos = zeros(nConditions * obj.numReps, 3);
            for r = 1:obj.numReps
                idx = randperm(nConditions);
                rows = (r-1)*nConditions + (1:nConditions);
                obj.allCombos(rows, :) = combos(idx, :);
            end
        
            % Store the sequences.
            obj.widths          = obj.allCombos(:, 1)';
            disp('Widths:')
            disp(obj.widths)

            obj.contrastSeq     = obj.allCombos(:, 2)';
            disp('Contrasts:')
            disp(obj.contrastSeq)

            obj.temporalFreqSeq = obj.allCombos(:, 3)';
            disp('Temporal Frequencies:')
            disp(obj.temporalFrequencies)
        
        end

       function numberOfAverages = get.numberOfAverages(obj)
            numberOfAverages = uint16(size(obj.allCombos, 1));
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
        
            idx = obj.numEpochsCompleted + 1;
        
            % Set the current epoch parameters.
            obj.barWidth           = obj.widths(idx);
            obj.contrast           = obj.contrastSeq(idx);
            obj.temporalFrequency  = obj.temporalFreqSeq(idx);
        
            % Derived spatial frequency.
            obj.spatialFrequency = 1 / (2 * obj.barWidth);
        
            % Save parameters to the epoch.
            epoch.addParameter('barWidth', obj.barWidth);
            epoch.addParameter('spatialFrequency', obj.spatialFrequency);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('temporalFrequency', obj.temporalFrequency);
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end 