classdef NaturalImageFlashPlusNoiseMEAVersion < manookinlab.protocols.ManookinLabStageProtocol

    properties
        preTime = 200 % ms
        flashTime = 200 % ms
        tailTime = 200 % ms
        
        apertureDiameter = 200 % um
        noiseFilterSD = 2 % pixels
        noiseContrast = 1;
        numNoiseRepeats = 5;
        numberOfAverages = uint16(180) % number of epochs to queue
    end
    
    properties (Hidden)
        %saved out to each epoch...
        stimulusTag
        imagePatchIndex
        currentPatchLocation
        temporalMask
        noiseSeed
        noiseStream
    end
   
    properties (Dependent) 
        stimTime
    end
    

    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end

    methods
        
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
            obj.showFigure('edu.washington.riekelab.turner.figures.MeanResponseFigure',...
                obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis);
            obj.showFigure('edu.washington.riekelab.turner.figures.FrameTimingFigure',...
                obj.rig.getDevice('Stage'), obj.rig.getDevice('Frame Monitor'));
        
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            device = obj.rig.getDevice(obj.amp);
            duration = (obj.preTime + obj.flashTime + obj.tailTime) * obj.numNoiseRepeats / 1e3;
            epoch.addDirectCurrentStimulus(device, device.background, duration, obj.sampleRate);
            epoch.addResponse(device);
         
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
                        
            %pull patch location:
            obj.imagePatchIndex = mod(floor(obj.numEpochsCompleted),obj.noPatches) + 1;
            obj.currentPatchLocation(1) = obj.patchLocations(1,obj.imagePatchIndex); %in VH pixels
            obj.currentPatchLocation(2) = obj.patchLocations(2,obj.imagePatchIndex);
            
            obj.imagePatchMatrix = ...
                edu.washington.riekelab.turner.protocols.NaturalImageFlashProtocol.getImagePatchMatrix(...
                obj, obj.currentPatchLocation);
            
            obj.noiseSeed = RandStream.shuffleSeed;
            
            obj.noiseSeed = 1;
            %at start of epoch, set random stream
            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);

            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('imagePatchIndex', obj.imagePatchIndex);
            epoch.addParameter('currentPatchLocation', obj.currentPatchLocation);
        end
        
        function p = createPresentation(obj)            
            p = stage.core.Presentation((obj.preTime + obj.flashTime + obj.tailTime) * obj.numNoiseRepeats * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity
            
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            
            % Create image
            initMatrix = uint8(255.*(obj.backgroundIntensity .* ones(size(obj.imagePatchMatrix))));
            board = stage.builtin.stimuli.Image(initMatrix);
            board.size = canvasSize;
            board.position = canvasSize/2;
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);
            preFrames = round(60 * (obj.preTime/1e3));
            flashDurFrames = round(60 * ((obj.preTime + obj.flashTime + obj.tailTime))/1e3);
            imageController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewImage(obj, state.frame, preFrames, flashDurFrames));
            p.addController(imageController); %add the controller
            
            function i = getNewImage(obj, frame, preFrames, flashDurFrames)
                persistent boardMatrix;
                curFrame = rem(frame, flashDurFrames);
                if curFrame == preFrames
                    noiseMatrix = imgaussfilt(obj.noiseStream.randn(size(obj.imagePatchMatrix)), obj.noiseFilterSD);
                    noiseMatrix = noiseMatrix / std(noiseMatrix(:));
                    boardMatrix = obj.imagePatchMatrix + uint8(255 * noiseMatrix * obj.backgroundIntensity * obj.noiseContrast);
                end
                if curFrame == 0
                    boardMatrix = 255 * obj.backgroundIntensity .* ones(size(obj.imagePatchMatrix));
                end
                if curFrame == (flashDurFrames-1)
                    boardMatrix = 255 * obj.backgroundIntensity .* ones(size(obj.imagePatchMatrix));
                end
                i = uint8(boardMatrix);
            end

            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
        end
    
        function stimTime = get.stimTime(obj)
            stimTime = (obj.preTime + obj.flashTime + obj.tailTime) * double(obj.numNoiseRepeats) - obj.preTime - obj.tailTime;
        end

        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        function a = get.amp2(obj)
            amps = obj.rig.getDeviceNames('Amp');
            if numel(amps) < 2
                a = '(None)';
            else
                i = find(~ismember(amps, obj.amp), 1);
                a = amps{i};
            end
        end

    end
    
end