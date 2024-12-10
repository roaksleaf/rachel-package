classdef FlickeringBarSplitField < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp
        uniqueTime = 160000                % Duration of unique noise sequence (ms)
        repeatTime = 20000                 % Repeat phase duration (ms)
        frameDwell = 1                     % Number of frames each unique frame is displayed
        contrast = 0.6                     % Contrast of flickering bars
        baseMean = 0.5                     % mean of total stimulus
        meanOffset = 0.2                   % low mean = base - offset, high mean = base + offset
        barWidth = uint16(76)                      % Width of each bar (pixels)
        preTime = 250                      % Pre-stimulus time (ms)
        tailTime = 250                     % Post-stimulus time (ms)
        swapIntervals = [200 5000 10000]   % Possible swap intervals (ms)
        numberOfAverages = uint16(20)     % Number of epochs
        noiseClass = 'Gaussian'             % Draw luminance values using binary, gaussian, uniform distribution
        orientationMode = 'Vertical'        %Direction of split field
        backgroundIntensity = 0.5
        xOffset = -57
        yOffset = 0
    end

    properties (Dependent)
        stimTime
    end
    
    properties (Hidden)
        ampType
        noiseClassType = symphonyui.core.PropertyType('char', 'row', {'Gaussian', 'Uniform', 'Binary'})
        orientationModeType = symphonyui.core.PropertyType('char', 'row', {'Vertical', 'Horizontal'})
%         barWidthType = symphonyui.core.PropertyType('uint16', 'row', {1, 2, 4, 6, 8, 12, 24, 38, 76, 114, 228})
        currentFrame                        % Current frame being displayed
%         numBars                             % Total number of bars in stimulus
%         leftOffset                          % Calculated offset for left half
%         rightOffset                         % Calculated offset for right half
%         intervalStream                       % Random number stream for reproducibility
%         intervalStreamRep
%         noiseStream
%         noiseStreamRep
        seed
        imageMatrix
%         nextSwapInterval
% %         nextSwapFrame
%         numFrames
%         pre_frames
        unique_frames
        repeat_frames
%         offset_vec_unique
%         offset_vec_rep
%         offset_vec
        time_multiple
        imgSize
%         displayWidth
%         displayHeight
%         leftHalf
%         rightHalf
%         imgMat
        backgroundFrame
    end

    methods
        function didSetRig(obj)
            disp('to set rig')
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
            disp('did set rig')
        end

        function prepareRun(obj)
            disp('to prepare run')
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            obj.unique_frames = floor(obj.uniqueTime * 1e-3 * obj.frameRate);
            obj.repeat_frames = floor(obj.repeatTime * 1e-3 * obj.frameRate);
%             obj.preFrames = floor(obj.preTime * 1e-3 * obj.frameRate);
%             obj.tailFrames = floor(obj.tailTime * 1e-3 * obj.frameRate);
            
            try
                obj.time_multiple = obj.rig.getDevice('Stage').getExpectedRefreshRate() / obj.rig.getDevice('Stage').getMonitorRefreshRate();
            catch
                obj.time_multiple = 1.0;
            end

        end
        
        function p = createPresentation(obj)
            disp('create Pres called')
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3 * obj.time_multiple);
            p.setBackgroundColor(obj.backgroundIntensity);

            disp('pre builtin.Image')
            bars = stage.builtin.stimuli.Image(obj.imageMatrix(:, :, 1));
            disp('post builtin.Image')
            bars.size = [size(obj.imageMatrix,1) size(obj.imageMatrix,2)];
            bars.position = obj.canvasSize/2;
            bars.position = bars.position + [obj.xOffset obj.yOffset];

            bars.setMinFunction(GL.NEAREST);
            bars.setMagFunction(GL.NEAREST);

            p.addStimulus(bars);
            disp('add bars')
            
            barsVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
%             p.addController(barsVisible);  %%%Adding either controller
%             causes both stage and symphony to crash on run
%             
            preF = floor(obj.preTime/1000 * obj.frameRate);
            stimF = floor(obj.stimTime/1000 * obj.frameRate);
%                        
            disp('pre frame controller')
            barsController = stage.builtin.controllers.PropertyController(bars,...
                'imageMatrix', @(state)getNewBars(obj, state.frame - preF, stimF));
%             p.addController(barsController); %%%Adding either controller
%             causes both stage and symphony to crash on run
            disp('frame controller added')
%             
            function i = getNewBars(obj, frame, stimFrames)
                if frame > 0 && frame <= stimFrames
                    i = obj.imageMatrix(:, :, frame);
                else
                    i = obj.imageMatrix(:, :, 1);
                end
            end
        end
        

        function prepareEpoch(obj, epoch)
            disp('to prepare epoch')
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
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

            if obj.numEpochsCompleted == 0
                obj.seed = RandStream.shuffleSeed;
            else
                obj.seed = obj.seed +1;
            end
            
            disp('pre util function')
%             obj.imageMatrix = util.getFlickeringBarsFrame(obj.seed, obj.baseMean, obj.meanOffset, obj.barWidth, obj.contrast, obj.unique_frames, obj.repeat_frames, obj.frameRate, obj.swapIntervals, obj.canvasSize, obj.frameDwell, obj.preTime, obj.tailTime, obj.noiseClass, obj.orientationMode);
            disp('post util function')
            obj.imageMatrix = ones(obj.canvasSize(2)*2, obj.canvasSize(1)*2, (obj.repeat_frames + obj.unique_frames));
            obj.imageMatrix = uint8(255 .* obj.baseMean .* obj.imageMatrix);


            % Save all parameters for this epoch
            epoch.addParameter('uniqueTime', obj.uniqueTime);
            epoch.addParameter('repeatTime', obj.repeatTime);
            epoch.addParameter('frameDwell', obj.frameDwell);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('baseMean', obj.baseMean);
            epoch.addParameter('meanOffset', obj.meanOffset);
            epoch.addParameter('barWidth', obj.barWidth);
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('repeating_seed', 1);
%             epoch.addParameter('numFrames', obj.numFrames);
            epoch.addParameter('unique_frames', obj.unique_frames);
            epoch.addParameter('repeat_frames', obj.repeat_frames);
            epoch.addParameter('orientationMode', obj.orientationMode);
            epoch.addParameter('swapIntervals', obj.swapIntervals);
            epoch.addParameter('numberOfAverages', obj.numberOfAverages);
%             epoch.addParameter('numClipped', obj.numClipped);
            epoch.addParameter('xOffset', obj.xOffset);
            epoch.addParameter('yoffSet', obj.yOffset);
%             if strcmp(obj.noiseClass, 'Gaussian')
% %                 epoch.addParameter('numClippedGauss', obj.numClippedGauss);
%             end
            disp('prepare epoch')
        end

% 
%         function a = get.amp2(obj)
%             amps = obj.rig.getDeviceNames('Amp');
%             if numel(amps) < 2
%                 a = '(None)';
%             else
%                 i = find(~ismember(amps, obj.amp), 1);
%                 a = amps{i};
%             end
%         end
        
        function stimTime = get.stimTime(obj)
            disp('1')
            stimTime = obj.uniqueTime + obj.repeatTime;
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            disp('2')
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
            disp('should continue')
        end
        
        function tf = shouldContinueRun(obj)
            disp('3')
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
        
        function completeRun(obj)
            completeRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
        end

    end
end
