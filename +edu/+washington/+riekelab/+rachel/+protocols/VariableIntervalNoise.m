classdef VariableIntervalNoise < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        preTime = 500 % ms
        preInterval = 1000 %ms preceding mean change
        tailInterval = 60000 %ms following mean change
        tailTime = 500 % ms
        stixelSize = 60 % um
        binaryNoise = false %binary checkers - overrides noiseStdv
        pairedBars = true
        noiseStdv = 0.5 %contrast, as fraction of mean (if contrast jumps, multiplied by contrast multipliers)
        frameDwell = 4 % Frames per noise update
        backgroundRatio = 0.4
        backgroundIntensity = 0.5 % (0-1)
        contrastJumps = 0 %randomly add contrast jumps across whole stimulus
        useFixedSeed = false
        startDim = true %first epoch is increment
        alternatePolarity = true %increment and decrement alternate epochs
        onlineAnalysis = 'none'
        numberOfAverages = uint16(60) % number of epochs to queue
        amp % Output amplifier
        apertureDiameter = 0 % um

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
        increment
    end
    
    properties (Dependent)
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
            %get number of checkers...
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            %convert from microns to pixels...
            stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.numChecksX = round(canvasSize(1) / stixelSizePix);
            obj.numChecksY = round(canvasSize(2) / stixelSizePix);
         end
        
        function prepareEpoch(obj, epoch)
            fprintf(1, 'start prepare epoch\n');
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Alternating seed for each epoch
            if obj.useFixedSeed
                obj.noiseSeed = 1;
            else
                obj.noiseSeed = randi(2^32 - 1);
            end
            
            if obj.startDim
                obj.increment = true;
            else
                obj.increment = false;
            end
            
            if obj.alternatePolarity
                obj.startDim = ~obj.startDim;
            end

%             obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);
            
            %at start of epoch, set random stream
%             obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);
            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('numChecksX', obj.numChecksX);
            epoch.addParameter('numChecksY', obj.numChecksY);
            epoch.addParameter('backgroundRatio', obj.backgroundRatio)
            epoch.addParameter('increment', obj.increment);
            fprintf(1, 'end prepare epoch\n');
         end

         function p = createPresentation(obj)
            fprintf(1, 'start create presentation\n');
            p = stage.core.Presentation((obj.preTime + obj.preInterval + obj.tailInterval + obj.tailTime) * 1e-3); %create presentation of specified duration
            fprintf(1, 'p initialized\n');
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            fprintf(1, 'presentation created\n');
            %convert from microns to pixels...
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            fprintf(1, 'canvasSize created\n');   
            % Create checkerboard
            initMatrix = uint8(255.*(obj.backgroundIntensity .* ones(obj.numChecksY,obj.numChecksX)));
            board = stage.builtin.stimuli.Image(initMatrix);
            board.size = canvasSize;
            board.position = canvasSize/2;
            fprintf(1, 'board position\n');
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);

            disp('pre lineMatcall')
            obj.lineMatrix = util.getVariableIntervalLines(obj.noiseSeed, obj.numChecksX, obj.preTime, obj.preInterval, obj.tailInterval, obj.tailTime, obj.backgroundIntensity,...
                obj.frameDwell, obj.binaryNoise, obj.noiseStdv, obj.backgroundRatio, obj.pairedBars, obj.contrastJumps, obj.increment); 
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
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.preInterval + obj.tailInterval) * 1e-3);
            p.addController(boardVisible); 
          
            disp('post board visible')

            function i = getNewCheckerboard(obj, frame)
                line = obj.lineMatrix(:, frame);
                i = uint8(255 * repmat(line', obj.numChecksY, 1));
                size(i)
            end
            
         end
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.preInterval + obj.tailInterval;
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