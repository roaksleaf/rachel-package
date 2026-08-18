classdef GratingMeasurementsOld < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 500                   % Grating leading duration (ms)
        moveTime = 5000                 % Grating duration (ms)
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
        trueFrameRate = 60;                         % Actual measured device frame rate

%         numberOfAverages=324
        verbose = true;                            % Print debug statements to console?

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
        barWidthsPix
        contrast
        temporalFrequency
        widths
        contrastSeq
        temporalFreqSeq
        phaseShift
        allCombos
        spatialPhaseRad
        rawImage
    end

    properties (Dependent)
        numberOfAverages
        stimTime
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            % 
            if ~strcmp(obj.onlineAnalysis, 'none')
                obj.showFigure('manookinlab.figures.sMTFFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'preTime', obj.preTime, 'stimTime', obj.stimTime, ...
                    'temporalType', obj.temporalClass, 'spatialType', 'spot', ...
                    'xName', 'barWidth', 'xaxis', unique(obj.barWidths), ...
                    'temporalFrequency', obj.temporalFrequency);
            end
            rawPix = obj.rig.getDevice('Stage').um2pix(obj.barWidths);
            obj.barWidthsPix = 2 * max(round(rawPix / 2), 1);
            
            if obj.verbose
                disp('Bar Withs in pixels:')
                disp(obj.barWidthsPix)
                disp(obj.stageClass)
            end
            
            % Calculate the spatial phase in radians.
            obj.spatialPhaseRad = obj.spatialPhase / 180 * pi;

            device = obj.rig.getDevice('Stage');
            % Organize stimulus and analysis parameters.
            obj.organizeParameters();
        end
        
        function p = createPresentation(obj)
            if obj.verbose
                fprintf('\nCreating presentation\n');
            end
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * (obj.trueFrameRate/obj.frameRate) * 1e-3); % Create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            % Create the grating
            grate = stage.builtin.stimuli.Image(uint8(0 * obj.rawImage));
            grate.position = obj.canvasSize / 2;
            grate.size = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2))*ones(1,2);
            grate.orientation = obj.orientation;

            grate.setMinFunction(GL.NEAREST);
            grate.setMagFunction(GL.NEAREST);
            
            p.addStimulus(grate);
            
            % Make the grating visible only during the stimulus time.
            grateVisible = stage.builtin.controllers.PropertyController(grate, 'visible', ...
                @(state)state.frame >= obj.preFrames && state.frame < (obj.preFrames + obj.stimFrames));

            p.addController(grateVisible);
            
            
            % Generate the grating.
            if strcmp(obj.temporalClass, 'drifting')
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setDriftingGrating(obj, state.time - obj.preTime * 1e-3));
            else
                imgController = stage.builtin.controllers.PropertyController(grate, 'imageMatrix',...
                    @(state)setReversingGrating(obj, state.time - obj.preTime * 1e-3));
            end
            p.addController(imgController);
            
                     % Set the drifting grating.
            function g = setDriftingGrating(obj, time)
                if time >= 0
                    phase = obj.temporalFrequency * time * 2 * pi;
                else
                    phase = 0;
                end
                
                g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                
                if strcmp(obj.spatialClass, 'squarewave')
                    g = sign(g);
                end
                
                g = obj.contrast * g;
                
                % Deal with chromatic gratings.
                if ~strcmp(obj.stageClass,'LightCrafter')
                    for m = 1 : 3
                        g(:,:,m) = obj.backgroundMeans(m) * obj.colorWeights(m) * g(:,:,m) + obj.backgroundMeans(m);
                    end
                    g = uint8(255*(g));
                else
                    g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
                end
            end
            
            % Set the reversing grating
            function g = setReversingGrating(obj, frame)
                if frame >= 0
                    phase = round(0.5 * sin(frame * 2 * pi * obj.temporalFrequencyFrames) + 0.5) * pi;
                else
                    phase = 0;
                end
                                
                if strcmp(obj.spatialClass, 'squarewave')
                    phaseBars = (obj.spatialPhaseRad + phase) / pi;
                    g = 1-2 * mod(obj.rawImage + round(phaseBars), 2);
                else
                    g = cos(obj.spatialPhaseRad + phase + obj.rawImage);
                end
                
                g = obj.contrast * g;
                
                % Deal with chromatic gratings.
%                 if ~strcmp(obj.chromaticClass, 'achromatic')
%                     for m = 1 : 3
%                         g(:,:,m) = obj.colorWeights(m) * g(:,:,m);
%                     end
%                 end
                g = uint8(255*(obj.backgroundIntensity * g + obj.backgroundIntensity));
            end

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
            if obj.verbose
                fprintf('\nCreated presentation\n');
            end
        end
        
        function setRawImage(obj)

            sz = ceil(sqrt(obj.canvasSize(1)^2 + obj.canvasSize(2)^2));
            rotRads = obj.orientation / 180 * pi;
            
            offsetAlongAxis = obj.centerOffset(1)*cos(rotRads) + obj.centerOffset(2)*sin(rotRads);
            x = linspace(-sz/2 + 0.5, sz/2 - 0.5, sz) - offsetAlongAxis;
            
            if strcmp(obj.spatialClass, 'squarewave')
                w = min(obj.canvasSize)/(2*obj.spatialFrequency);
                obj.rawImage = floor(x/w);
            else
                obj.rawImage = x/min(obj.canvasSize) * 2 * pi * obj.spatialFrequency;
            end
            
%             if ~strcmp(obj.chromaticClass, 'achromatic')
%                 obj.rawImage = repmat(obj.rawImage, [1 1 3]);
%             end
            
            if obj.verbose
                w = min(obj.canvasSize) / (2*obj.spatialFrequency);
                if strcmp(obj.spatialClass, 'squarewave')
                    g0 = 1 - 2*mod(obj.rawImage, 2);
                    gP = 1 - 2*mod(obj.rawImage + 1, 2);
                else
                    g0 = sign(cos(obj.spatialPhaseRad + obj.rawImage));
                    gP = sign(cos(obj.spatialPhaseRad + pi + obj.rawImage));
                end
                r0 = diff(find([true, diff(g0(:)') ~= 0, true]));
                rP = diff(find([true, diff(gP(:)') ~= 0, true]));
                fprintf('w=%.2f | phase0 widths=[%s] | phasePi widths=[%s]\n', ...
                    w, num2str(unique(r0)), num2str(unique(rP)));
                fprintf('  counts  phase0: +%d -%d | phasePi: +%d -%d\n', ...
                    sum(g0(:)>0), sum(g0(:)<0), sum(gP(:)>0), sum(gP(:)<0));
            end

        end


        
        % This is a method of organizing stimulus parameters.
        function organizeParameters(obj)
            % Full factorial of barWidths x contrasts x temporalFrequencies.
            
            [W, C, T] = meshgrid(obj.barWidthsPix, obj.contrasts, obj.temporalFrequencies);
            combos = [W(:), C(:), T(:)];
            disp('Size of combos:')
            disp(size(combos,1))
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
            disp(obj.temporalFreqSeq)
        
        end


        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            if obj.verbose
                fprintf('\nPreparing Epoch %d\n', obj.numEpochsPrepared);
            end
            % Remove the Amp responses if it's an MEA rig.
            if obj.isMeaRig
                amps = obj.rig.getDevices('Amp');
                for ii = 1:numel(amps)
                    if epoch.hasResponse(amps{ii})
                        epoch.removeResponse(amps{ii});
                    end
                    if epoch.hasStimulus(amps{ii})
                        epoch.removeStimulus(amps{ii});
                    end
                end
            end
            idx = obj.numEpochsCompleted + 1;
        
            % Set the current epoch parameters.
            obj.barWidth           = obj.widths(idx);
            obj.contrast           = obj.contrastSeq(idx);
            obj.temporalFrequency  = obj.temporalFreqSeq(idx);
        
            % Derived spatial frequency.
            obj.spatialFrequency = 1 / (2 * obj.barWidth);
            disp('in prepare epoch')
            
            % Set up the raw image.
            obj.setRawImage();
        
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
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.waitTime + obj.moveTime;
        end
        
        function numberOfAverages = get.numberOfAverages(obj)
            numberOfAverages = uint16(size(obj.allCombos, 1));
        end
        
        
        function completeRun(obj)
            completeRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
        end
    end
end 