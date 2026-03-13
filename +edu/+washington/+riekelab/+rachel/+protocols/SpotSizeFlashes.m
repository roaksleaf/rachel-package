classdef SpotSizeFlashes < manookinlab.protocols.ManookinLabStageProtocol
    % Presents a set of single spot stimuli to a Stage canvas and records from the specified amplifier.
    
    properties
        amp                             % Output amplifier
        preTime = 2000                  % Spot leading duration (ms)
        stimTime = 50                   % Spot duration (ms)
        tailTime = 2000                 % Spot trailing duration (ms)
        incrementIntensity = 1.0        % increment light intensity (0-1) 
        backgroundIntensity = 0.5       % Background intensity (0-1) 
        decrementIntensity = 0            %Intensity of decrements 
        spotDiameters = [300 600 900 1200]              % Spot diameter sizes (um)
        psth=true
        repsPerCondition = 20           % How many times to repeat each condition? (int)
        %numberOfAverages = uint16(320)    % Number of epochs (len(spotDiameters)) * (2) * (2) * (repsPerCond)
        interpulseInterval = 0.5          % Duration between spots (s)
        
    end
    
    properties (Hidden)
        ampType
        numberOfAverages
        uniqueConditions
        epochOrder
        currentCondition
        spotDiamaterUm
        spotDiamaterPix
        annulusBool
        incrementBool
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function p = getPreview(obj, panel)
            if isempty(obj.rig.getDevices('Stage'))
                p = [];
                return;
            end
            p = io.github.stage_vss.previews.StagePreview(panel, @()obj.createPresentation(), ...
                'windowSize', obj.rig.getDevice('Stage').getCanvasSize());
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            
            % % Show the progress bar.
            % obj.showFigure('manookinlab.figures.ProgressFigure', obj.numberOfAverages);
            % 
            % obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            % obj.showFigure('edu.washington.riekelab.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp), 'psth',obj.psth);
            % obj.showFigure('edu.washington. riekelab.figures.FrameTimingFigure', obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));

            %condition label = spotSize_annulus_increment (so 300um, yes
            %annulus, decrement = 300_1_0
            obj.uniqueConditions = {};
            for s = obj.spotDiameters
                for annulus = [0,1]
                    for increment = [0,1]
                        obj.uniqueConditions{end+1} = sprintf('%d_%d_%d', s, annulus, increment);
                    end
                end
            end

            repeated = repmat(obj.unique_conditions, 1, obj.repsPerCondition);
            obj.epochOrder = repeated(randperm(length(repeated)));
            
            obj.numberOfAverages = length(obj.epochOrder);
            obj.showFigure('manookinlab.figures.ProgressFigure', obj.numberOfAverages);


        end
        
        function p = createPresentation(obj)
            device = obj.rig.getDevice('Stage');
            canvasSize = device.getCanvasSize();
            
            % spotDiameterPix = device.um2pix(obj.spotDiameter);
            
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            if obj.incrementBool == 1
                spotInt = obj.incrementIntensity;
                annulusInt = obj.decrementIntensity;
            else
                spotInt = obj.decrementIntensity;
                annulusInt = obj.incrementIntensity;
            end

            if obj.annulusBool == 0
                annulusInt = obj.backgroundIntensity;
            end
            
            spot = stage.builtin.stimuli.Ellipse();
            spot.color = spotInt;
            spot.radiusX = obj.spotDiameterPix/2;
            spot.radiusY = obj.spotDiameterPix/2;
            spot.position = canvasSize/2;

            annulus = stage.builtin.stimuli.Ellipse();
            annulus.color = annulusInt;
            annulus.radiusX = spot.radiusX * 2;
            annulus.radiusY = spot.radiusY * 2;
            annulus.position = spot.position;

            p.addStimulus(annulus);
            p.addStimulus(spot);
            
            spotVisible = stage.builtin.controllers.PropertyController(spot, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(spotVisible);
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            obj.currentCondition = obj.epochOrder(epoch);

            
            condition_parts = strsplit(obj.currentCondition, '_'); %spot size, annulus bool, increment bool

            obj.spotDiameterUm = str2double(condition_parts{1});
            obj.spotDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.spotDiameter);
            obj.annulusBool = str2double(condition_parts{2});
            obj.incrementBool = str2double(condition_parts{3});

            epoch.addParameter('currentCondition', obj.currentCondition);
            epoch.addParameter('uniqueConditions', obj.uniqueConditions);
            epoch.addParameter('epochOrder', obj.epochOrder);
            epoch.addParameter('spotDiameterUm', obj.spotDiameterUm);
            epoch.addParameter('spotDiameterPix', obj.spotDiameterPix);
            epoch.addParameter('annulusBool', obj.annulusBool);
            epoch.addParameter('incrementBool', obj.incrementBool);
            
            % device = obj.rig.getDevice(obj.amp);
            % duration = (obj.preTime + obj.stimTime + obj.tailTime) / 1e3;
            % epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            % epoch.addResponse(device);
        end
        
        % function prepareInterval(obj, interval)
        %     prepareInterval@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj, interval);
        % 
        %     device = obj.rig.getDevice(obj.amp);
        %     interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
        % end
        % 
        % function controllerDidStartHardware(obj)
        %     controllerDidStartHardware@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
        %     if obj.numEpochsPrepared == 1
        %         obj.rig.getDevice('Stage').play(obj.createPresentation());
        %     else
        %         obj.rig.getDevice('Stage').replay();
        %     end
        % end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end

        function completeRun(obj)
            completeRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
        end
    end
        
end
    
