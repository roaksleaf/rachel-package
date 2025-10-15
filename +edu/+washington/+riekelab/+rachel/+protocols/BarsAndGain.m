classdef BarsAndGain < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        preTime = 0 % ms
        stimTime = 120000 % ms
        trackDur = 60000 %on last repeat, don't do interval for this long (ms)
        tailTime = 0 % ms
        stixelSize = 60 % um
        binaryNoise = false 
        pairedBars = false
        noiseStdv = 0.6 %contrast
        noiseMean = 0.5 %pixel mean of noise stimulus
        frameDwell = 3 % Frames per noise update
        stepDurations = [30000 10000 5000] % ms
        durRepEpochs = [4 4 4] %repeats for each interval length
        lowGain = 0.2 %projector gain low
        highGain = 1.0 %projector gain high
        alternateFixedSeed = false
        trackEndAll = true
        interleave = true 
        backgroundIntensity = 0.5 % (0-1)
        numberOfAverages = uint16(12) % number of epochs to queue
        apertureDiameter = 0 % um
        onlineAnalysis = 'none'
        amp % Output amplifier
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        projectionTypeType = symphonyui.core.PropertyType('char', 'row', {'none', 'linear filter'})
        noiseSeed
        noiseStream
        numChecksX
        numChecksY
        imageMatrix
        lineMatrix
        dimBackground
        useFixedSeed = false        % Toggle between fixed and random seeds if alternateFixedSeed = true else always false
        stepDuration
        stepDurationsFull
        startDim = true
        trackEnd = false
        lowMean
        highMean
        backgroundFrameDwell
        numFrames
        preFrames
        stepFrames
        step_duration_ms
        trackFrames
        trackDur_ms
        projStepDurations
        projGainMeans
        projector_gain_device
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
         
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            %get number of checkers...
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            %convert from microns to pixels...
            stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.numChecksX = round(canvasSize(1) / stixelSizePix);
            obj.numChecksY = round(canvasSize(2) / stixelSizePix);
          
            if obj.interleave
                deltareps = zeros(size(obj.durRepEpochs));
                minrep = min(obj.durRepEpochs);
                for i=1:length(obj.durRepEpochs)
                    deltareps(i) = obj.durRepEpochs(i)-minrep;
                end
                obj.stepDurationsFull = repmat(obj.stepDurations, [1, minrep]);
                while any(deltareps)
                    for i=1:length(obj.durRepEpochs)
                        if deltareps(i)>=1
                            obj.stepDurationsFull = cat(2, obj.stepDurationsFull, obj.stepDurations(i));
                            deltareps(i) = deltareps(i)-1;
                        end
                    end
                end
                        
            else
                obj.stepDurationsFull = repelem(obj.stepDurations, obj.durRepEpochs);
            end
            disp(obj.stepDurationsFull);

            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            obj.preFrames = round(obj.preTime * 1e-3 * 60.0);
            obj.stepFrames = round(obj.stepDuration * 1e-3 * 60.0);
            obj.step_duration_ms = obj.stepFrames * 59.94;
            
            obj.trackFrames = round(obj.trackDur * 1e-3 * 60.0);
            obj.trackDur_ms = obj.trackFrames * 59.94;


            projector_gain = obj.rig.getDevices('Projector Gain');
            if ~isempty(projector_gain)
                obj.projector_gain_device = true;
            else
                obj.projector_gain_device = false;
                obj.projGainMeans = ones(size(obj.lowMean));
                obj.projStepDurations = ones(size(obj.lowMean));
            end
        end
        
        
        function prepareEpoch(obj, epoch)
            fprintf(1, 'start prepare epoc\n');
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Alternating seed for each epoch
            if obj.useFixedSeed
                obj.noiseSeed = 1;
            else
                obj.noiseSeed = randi(2^32 - 1);
            end
%             obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);
            
            % Toggle the seed usage for the next epoch
            if ~obj.alternateFixedSeed
                obj.useFixedSeed = false;
            else
                obj.useFixedSeed = ~obj.useFixedSeed;
            end
            
            obj.startDim = ~obj.startDim;
            
            %Choose next background frame dwell 
            obj.stepDuration = obj.stepDurationsFull(mod(obj.numEpochsCompleted,length(obj.stepDurationsFull))+1);
            nextStepDur = obj.stepDurationsFull(mod(obj.numEpochsCompleted+1,length(obj.stepDurationsFull))+1);
            if obj.trackEndAll
                obj.trackEnd=true;
            else
                if obj.stepDuration ~= nextStepDur 
                    obj.trackEnd=true;
                else
                    obj.trackEnd=false;
                end
            end
            disp(obj.stepDuration)

            %util function needs these, shared with other protocol
%             obj.lowMean = obj.backgroundIntensity;
%             obj.highMean = obj.backgroundIntensity;
            obj.lowMean = obj.noiseMean;
            obj.highMean =  obj.noiseMean;
            obj.backgroundFrameDwell = 1000;

            if obj.projector_gain_device
                %need to deal with gain values and step duration values
                if obj.trackEnd
                    stimDur = obj.stimTime - obj.trackDur;
                    numSteps = ceil(stimDur/obj.stepDuration);
                    obj.projStepDurations = [repmat(obj.stepDuration, 1, numSteps) obj.trackDur];
                else 
                    numSteps = ceil(obj.stimTime/obj.stepDuration);
                    obj.projStepDurations = [repmat(obj.stepDuration, 1, numSteps)];
                end
    
                obj.projGainMeans = [];
                if obj.startDim
                    target = obj.lowGain;
                else
                    target = obj.highGain;
                end
    
                while length(obj.projGainMeans) < length(obj.projStepDurations)
                    obj.projGainMeans = [obj.projGainMeans target];
                    if target == obj.lowGain
                        target = obj.highGain;
                    else
                        target = obj.lowGain;
                    end
                end
            end
            disp('projector steps:');
            disp(obj.projStepDurations);
            disp('projector gains: ') 
            disp(obj.projGainMeans);

            if obj.projector_gain_device
                epoch.addStimulus(obj.rig.getDevice('Projector Gain'), obj.createGainStimulus(obj.projGainMeans, obj.projStepDurations));
            end

            %at start of epoch, set random stream
%             obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);
            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('numChecksX', obj.numChecksX);
            epoch.addParameter('numChecksY', obj.numChecksY);
            epoch.addParameter('stepDuration', obj.stepDuration);
            epoch.addParameter('startDim', obj.startDim);
            epoch.addParameter('trackEnd', obj.trackEnd);
            epoch.addParameter('lowMean', obj.lowMean);
            epoch.addParameter('highMean', obj.highMean);
            epoch.addParameter('preFrames', obj.preFrames);
            epoch.addParameter('stepFrames', obj.stepFrames);
            epoch.addParameter('trackFrames', obj.trackFrames)
            epoch.addParameter('backgroundFrameDwell', obj.backgroundFrameDwell);
            epoch.addParameter('projStepDurations', obj.projStepDurations);
            epoch.addParameter('projGainMeans', obj.projGainMeans)
            fprintf(1, 'end prepare epoc\n');
        end

        function stim = createGainStimulus(obj, gain_values, step_durations)
            gen = edu.washington.riekelab.stimuli.ProjectorGainGenerator();
            
            gen.preTime = obj.preTime;
            gen.stimTime = obj.stimTime;
            gen.tailTime = obj.tailTime;
            gen.stepDurations = step_durations;
            gen.gainValues = gain_values;
            gen.stepDurations = step_durations;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice( 'Projector Gain' ).background.displayUnits;
            if strcmp(gen.units, symphonyui.core.Measurement.NORMALIZED)
                gen.upperLimit = 1;
                gen.lowerLimit = 0;
            else
                gen.upperLimit = 1.8;
                gen.lowerLimit = -1.8;
            end
            
            stim = gen.generate();
        end

         function p = createPresentation(obj)
            fprintf(1, 'start create presentation\n');
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity

            %convert from microns to pixels...
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();

            % Create checkerboard
            initMatrix = uint8(255.*(obj.backgroundIntensity .* ones(obj.numChecksY,obj.numChecksX)));
            board = stage.builtin.stimuli.Image(initMatrix);
            board.size = canvasSize;
            board.position = canvasSize/2;
            board.position = board.position;
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);

            disp('pre lineMatcall')
            disp(obj.trackEnd)
            disp(obj.trackFrames)
            obj.lineMatrix = util.getVariableMeanBars(obj.noiseSeed, obj.numChecksX, obj.preTime, obj.stimTime, obj.tailTime, obj.backgroundIntensity,...
                obj.frameDwell, obj.binaryNoise, obj.noiseStdv, obj.lowMean, obj.highMean, obj.backgroundFrameDwell, obj.pairedBars, obj.startDim, obj.trackEnd, obj.trackFrames); %last argument used to be a 1 pre 5/14/25
            disp('post line mat call')
            
            checkerboardController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewBoard(obj, state.frame+1));
            p.addController(checkerboardController); %add the controller
            
            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            
            % hide during pre & post
            boardVisible = stage.builtin.controllers.PropertyController(board, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(boardVisible); 
          
            disp('post board visible')

            function i = getNewBoard(obj, frame)
                line = obj.lineMatrix(:, frame);
                i = uint8(255 * repmat(line', obj.numChecksY, 1));
                size(i)
            end
            
        end

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