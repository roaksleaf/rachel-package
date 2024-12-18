classdef CheckerboardNoiseProjectRachel < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        preTime = 500 % ms
        stimTime = 20000 % ms
        tailTime = 500 % ms
        stixelSize = 60 % um
        binaryNoise = true %binary checkers - overrides noiseStdv
        pairedBars = true
        noiseStdv = 0.3 %contrast, as fraction of mean
        frameDwell = 1 % Frames per noise update
        backgroundFrameDwells = [30 120 750] % Frames per noise update
        backgroundRatios = [0.3 0.3]
        apertureDiameter = 0 % um
        backgroundIntensity = 0.5 % (0-1)
        onlineAnalysis = 'none'
        numberOfAverages = uint16(60) % number of epochs to queue
        amp % Output amplifier
        xOffset = -58 %offset of image to move split field, in pixels, default is equal sides with frame monitor for vert bars
        yOffset = 0 %offset of image to move split field, in pixels
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
        loadedFilter            % Loaded linear filter from .mat file
        useFixedSeed = true     % Toggle between fixed and random seeds
        backgroundFrameDwell
        backgroundRatio
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
            obj.useFixedSeed = ~obj.useFixedSeed;
            
            %Choose next background frame dwell 
            obj.backgroundFrameDwell = obj.backgroundFrameDwells(mod(obj.numEpochsCompleted,length(obj.backgroundFrameDwells))+1);

            %Choose next background ratio
            obj.backgroundRatio = obj.backgroundRatios(mod(obj.numEpochsCompleted, length(obj.backgroundRatios))+1);
            
            %at start of epoch, set random stream
%             obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);
            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('numChecksX', obj.numChecksX);
            epoch.addParameter('numChecksY', obj.numChecksY);
            epoch.addParameter('backgroundFrameDwell', obj.backgroundFrameDwell);
            epoch.addParameter('backgroundRatio', obj.backgroundRatio)
            fprintf(1, 'end prepare epoc\n');
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
            board.position = board.position + [obj.xOffset obj.yOffset];
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);

            disp('pre lineMatcall')
            obj.lineMatrix = util.getCheckerboardProjectLines(obj.noiseSeed, obj.numChecksX, obj.preTime, obj.stimTime, obj.tailTime, obj.backgroundIntensity,...
                obj.frameDwell, obj.binaryNoise, obj.noiseStdv, obj.backgroundRatio, obj.backgroundFrameDwell, 1);
            disp('post line mat call')
            
            checkerboardController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewCheckerboard(obj, state.frame+1));
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

            function i = getNewCheckerboard(obj, frame)
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