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
        numBars                             % Total number of bars in stimulus
        leftOffset                          % Calculated offset for left half
        rightOffset                         % Calculated offset for right half
        intervalStream                       % Random number stream for reproducibility
        intervalStreamRep
        noiseStream
        noiseStreamRep
        seed
        imageMatrix
        nextSwapInterval
        nextSwapFrame
        numFrames
        pre_frames
        unique_frames
        repeat_frames
        offset_vec_unique
        offset_vec_rep
        offset_vec
        time_multiple
        imgSize
        displayWidth
        displayHeight
        numClipped
        numClippedGauss
        calcBottomMean
        calcTopMean
        calcLeftMean
        leftHalf
        rightHalf
        imgMat
        backgroundFrame
%         calcRightMean
%         barMask1
%         barMask2
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
            
            obj.displayWidth = obj.canvasSize(1)*2;
            obj.displayHeight = obj.canvasSize(2)*2;

            if strcmp(obj.orientationMode, 'Vertical')
                obj.numBars = ceil(obj.displayWidth / obj.barWidth);
            elseif strcmp(obj.orientationMode, 'Horizontal')
                obj.numBars = ceil(obj.displayHeight / obj.barWidth);
            end
            
            obj.leftHalf = zeros(obj.displayWidth, obj.displayHeight);
            obj.rightHalf = zeros(obj.displayWidth, obj.displayHeight);
            
            
            if strcmp(obj.orientationMode, 'Vertical')
                obj.leftHalf(:, 1:floor(obj.displayWidth/2)) = 1;
                obj.rightHalf(:, floor(obj.displayWidth/2)+1:end) = 1;
            elseif strcmp(obj.orientationMode, 'Horizontal')
                obj.leftHalf(1:floor(obj.displayHeight/2), :) = 1;
                obj.rightHalf(floor(obj.displayHeight/2)+1:end, :) = 1;
            end
            
            obj.leftHalf = logical(obj.leftHalf);
            obj.rightHalf = logical(obj.rightHalf);
            

%             obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate);
            obj.pre_frames = round(obj.preTime * 1e-3 * 60.0);
            obj.unique_frames = round(obj.uniqueTime * 1e-3 * 60.0);
            obj.repeat_frames = round(obj.repeatTime * 1e-3 * 60.0);
            
            try
                obj.time_multiple = obj.rig.getDevice('Stage').getExpectedRefreshRate() / obj.rig.getDevice('Stage').getMonitorRefreshRate();
            catch
                obj.time_multiple = 1.0;
            end

        end
        
        function p = createPresentation(obj)
            disp('create Pres called')
            fprintf('mat size: %d %d %d \n',size(obj.imgMat,1), size(obj.imgMat,2), size(obj.imgMat,3));
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3 * obj.time_multiple);
            p.setBackgroundColor(obj.backgroundIntensity);

            obj.imageMatrix = obj.backgroundIntensity * ones(obj.canvasSize(2)*2, obj.canvasSize(1)*2);
            bars = stage.builtin.stimuli.Image(uint8(obj.imageMatrix));
%             bars.position = [((obj.canvasSize(2)/2) + obj.xOffset) ((obj.canvasSize(1)/2)+obj.yOffset)];
            bars.position = obj.canvasSize/2;
            bars.position = bars.position + [obj.xOffset obj.yOffset];
            fprintf('CS: %d %d \n', obj.canvasSize(1), obj.canvasSize(2));
            
            bars.size = [size(obj.imageMatrix,1) size(obj.imageMatrix,2)];
            
            bars.setMinFunction(GL.NEAREST);
            bars.setMagFunction(GL.NEAREST);

            p.addStimulus(bars);
            
            
            barsVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barsVisible);
            
            preF = floor(obj.preTime/1000 * 60);
            imgController = stage.builtin.controllers.PropertyController(bars,...
                'imageMatrix', @(state)getBarsFrame(obj, state.frame - preF));
            % Add the frame controller.
            p.addController(imgController);
            disp('frame controller added')

            function stimdisplay = getBarsFrame(obj, frame)
                persistent M
                if frame > 0
                    M = obj.imgMat(:, :, frame);
                else 
                    M = obj.imageMatrix;
                end
                M = max(0, min(1,M));
                stimdisplay=uint8(255*M);
            end


%             

%             imgController = stage.builtin.controllers.PropertyController(bars, 'imageMatrix',...
%                     @(state)generateFlickeringBars(obj, state.frame - preF));

            % Add the stimulus to the presentation
%             p.addController(imgController);
% %             
%             function stimdisplay = generateFlickeringBars(obj, frame)
%                 persistent M
% %                 if frame == obj.nextSwapFrame
% %                     [obj.leftOffset, obj.rightOffset] = deal(obj.rightOffset, obj.leftOffset); % swap offsets
% %                     
% %                     if frame < obj.unique_frames
% %                         chooseSwap = obj.intervalStream.rand;
% %                     else 
% %                         chooseSwap = obj.intervalStreamRep.rand;
% %                     end
% %                     
% %                     if chooseSwap > 0.66666
% %                         obj.nextSwapInterval = obj.swapIntervals(3);
% %                     elseif (.33333 <= chooseSwap) && (chooseSwap <= .66666)
% %                         obj.nextSwapInterval = obj.swapIntervals(2);
% %                     else 
% %                         obj.nextSwapInterval = obj.swapIntervals(1);
% %                     end
% %                     obj.nextSwapFrame = obj.nextSwapFrame + ceil(obj.nextSwapInterval/1000 * obj.frameRate);
% %                 end
%                 
%                 if frame > 0
% %                     M = obj.baseMean * ones(obj.canvasSize(2)*2, obj.canvasSize(1)*2); %even this line with no other computation is low frame rate
% %                     if mod(frame, obj.frameDwell) == 0
% %                         M = obj.baseMean * ones(obj.canvasSize(2)*2, obj.canvasSize(1)*2); 
% %                         
% %                         if strcmp(obj.noiseClass, 'Gaussian')
% %                             
% %                             if frame < obj.unique_frames
% %                                 ct = 0.3*obj.noiseStream.randn(1,ceil(obj.numBars/2));
% %                             else 
% %                                 ct = 0.3*obj.noiseStreamRep.randn(1,ceil(obj.numBars/2));
% %                             end
% % % 
% %                             ct(ct<-1) = -1;
% %                             ct(ct>1) = 1;
% %                             variation = ct .* obj.baseMean;
% %                             
% %                         elseif strcmp(obj.noiseClass, 'Binary')
% %                             
% %                             if frame < obj.unique_frames
% %                                 variation = obj.contrast * (obj.noiseStream.rand(1,ceil(obj.numBars/2)) > 0.5) - (obj.baseMean - obj.meanOffset);
% %                             else
% %                                 variation = obj.contrast * (obj.noiseStreamRep.rand(1,ceil(obj.numBars/2)) > 0.5) - (obj.baseMean - obj.meanOffset);
% %                             end
% %                             
% %                         elseif strcmp(obj.noiseClass, 'Uniform') %for some reason this condition doesn't work with noiseStream
% %                             sz = [1 ceil(obj.numBars/2)];
% %                             if frame < obj.unique_frames
% %                                 
% %                                 variation = obj.noiseStream.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, sz);
% % %                                 variation = unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, sz);
% %                             else
% %                                 variation = obj.noiseStreamRep.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, sz);
% %                                 
% %                             end
% %                         end
%                         
% %                         luminances1 = obj.baseMean + variation;
% %                         luminances2 = obj.baseMean - variation;
% % 
% %                         allLum = [luminances1;luminances2];
% %                         allLum = allLum(:)';
% 
%                         
% %                     if strcmp(obj.orientationMode, 'Vertical')
% %                         M = repelem(obj.imgMat(:, frame), obj.canvasSize(2)*2, obj.barWidth);
% %                     else
% %                         M = repelem(obj.imgMat(:, frame), obj.barWidth, obj.canvasSize(1)*2);
% %                     end
% % 
% %                     M(obj.leftHalf) = M(obj.leftHalf) + obj.offset_vec(1, frame);
% %                     M(obj.rightHalf) = M(obj.rightHalf) + obj.offset_vec(2, frame);
% 
%                 else
%                     M = obj.imageMatrix;
%                 end
%                 M = max(0, min(1,M));
%                 
%                 stimdisplay = uint8(255*M);
%             end
% 
%             disp('create presentation')
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

            obj.noiseStream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.intervalStream = RandStream('mt19937ar', 'Seed', obj.seed);
            obj.noiseStreamRep = RandStream('mt19937ar', 'Seed', 1);
            obj.intervalStreamRep = RandStream('mt19937ar', 'Seed', 1);

            % Calculate the offsets for the left and right halves
            obj.leftOffset = -1 * obj.meanOffset;
            obj.rightOffset = obj.meanOffset;
%             
            obj.offset_vec_unique = zeros(2, obj.unique_frames);
            obj.offset_vec_rep = zeros(2, obj.repeat_frames);
            origLeft = obj.leftOffset;
            origRight = obj.rightOffset;
            
            swaps = [];
            nIntervals = numel(obj.swapIntervals);
            obj.nextSwapFrame = 0;
            while obj.nextSwapFrame < obj.unique_frames
                choice = ceil((obj.swapIntervals(ceil(obj.intervalStream.rand*nIntervals))/1000)) * obj.frameRate;
                obj.nextSwapFrame = obj.nextSwapFrame + choice;
                swaps(end+1) = obj.nextSwapFrame;
            end
            rep_swaps = [];
            obj.nextSwapFrame = 0;
            while obj.nextSwapFrame < obj.repeat_frames
                choice = ceil((obj.swapIntervals(ceil(obj.intervalStreamRep.rand*nIntervals))/1000)) * obj.frameRate;
                obj.nextSwapFrame = obj.nextSwapFrame + choice;
                rep_swaps(end + 1) = obj.nextSwapFrame;
            end

            obj.offset_vec_unique(1, 1:swaps(1)) = obj.leftOffset;
            obj.offset_vec_unique(2, 1:swaps(1)) = obj.rightOffset;
            for i = 2:numel(swaps)
                [obj.leftOffset, obj.rightOffset] = deal(obj.rightOffset, obj.leftOffset); % swap offsets
                if swaps(i) <= obj.unique_frames
                    obj.offset_vec_unique(1, swaps(i-1):swaps(i)) = obj.leftOffset;
                    obj.offset_vec_unique(2, swaps(i-1):swaps(i)) = obj.rightOffset;
                else 
                    obj.offset_vec_unique(1, swaps(i-1):end) = obj.leftOffset;
                    obj.offset_vec_unique(2, swaps(i-1):end) = obj.rightOffset;
                    break
                end
            end

            obj.leftOffset = origLeft;
            obj.rightOffset = origRight;

            obj.offset_vec_rep(1, 1:rep_swaps(1)) = obj.leftOffset;
            obj.offset_vec_rep(2, 1:rep_swaps(1)) = obj.rightOffset;
            for i = 2:numel(rep_swaps)
                [obj.leftOffset, obj.rightOffset] = deal(obj.rightOffset, obj.leftOffset); % swap offsets
                if rep_swaps(i) <= obj.repeat_frames
                    obj.offset_vec_rep(1, rep_swaps(i-1):rep_swaps(i)) = obj.leftOffset;
                    obj.offset_vec_rep(2, rep_swaps(i-1):rep_swaps(i)) = obj.rightOffset;
                else
                    obj.offset_vec_rep(1, rep_swaps(i-1):end) = obj.leftOffset;
                    obj.offset_vec_rep(2, rep_swaps(i-1):end) = obj.rightOffset;
                    break
                end
            end

            obj.offset_vec = [obj.offset_vec_unique obj.offset_vec_rep];
            
            obj.imgMat = zeros(obj.canvasSize(2)*2, obj.canvasSize(1)*2, obj.numFrames);
            for f = 1:obj.numFrames
                if mod(f, obj.frameDwell) == 0
                    if strcmp(obj.noiseClass, 'Gaussian')
                        if f < obj.unique_frames
                            ct = 0.3*obj.noiseStream.randn(1,ceil(obj.numBars/2));
                        else 
                            ct = 0.3*obj.noiseStreamRep.randn(1,ceil(obj.numBars/2));
                        end
        % 
                        ct(ct<-1) = -1;
                        ct(ct>1) = 1;
                        variation = ct .* obj.baseMean;

                    elseif strcmp(obj.noiseClass, 'Binary')

                        if f < obj.unique_frames
                            variation = obj.contrast * (obj.noiseStream.rand(1,ceil(obj.numBars/2)) > 0.5) - (obj.baseMean - obj.meanOffset);
                        else
                            variation = obj.contrast * (obj.noiseStreamRep.rand(1,ceil(obj.numBars/2)) > 0.5) - (obj.baseMean - obj.meanOffset);
                        end

                    elseif strcmp(obj.noiseClass, 'Uniform') %for some reason this condition doesn't work with noiseStream
                        sz = [1 ceil(obj.numBars/2)];
                        if f < obj.unique_frames

                            variation = obj.noiseStream.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, sz);
        %                                 variation = unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, sz);
                        else
                            variation = obj.noiseStreamRep.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, sz);

                        end
                    end
                    
                    luminances1 = obj.baseMean + variation;
                    luminances2 = obj.baseMean - variation;

                    allLum = [luminances1;luminances2];
                    allLum = allLum(:)';

                    if strcmp(obj.orientationMode, 'Vertical')
                        fullmat = repelem(allLum, obj.canvasSize(2)*2, obj.barWidth);
                    else
                        fullmat = repelem(allLum, obj.barWidth, obj.canvasSize(1)*2);
                    end

                    fullmat(obj.leftHalf) = fullmat(obj.leftHalf) + obj.offset_vec(1, f);
                    fullmat(obj.rightHalf) = fullmat(obj.rightHalf) + obj.offset_vec(2, f);

                    obj.imgMat(:, :, f) = fullmat;
                else 
                    obj.imgMat(:, :, f) = obj.imgMat(:,:, f-1);
                end
            end
            
            matrixSize = size(obj.imgMat);
            
            obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(matrixSize(1), matrixSize(2)));


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
            epoch.addParameter('numFrames', obj.numFrames);
            epoch.addParameter('unique_frames', obj.unique_frames);
            epoch.addParameter('repeat_frames', obj.repeat_frames);
            epoch.addParameter('orientationMode', obj.orientationMode);
            epoch.addParameter('swapIntervals', obj.swapIntervals);
            epoch.addParameter('numberOfAverages', obj.numberOfAverages);
            epoch.addParameter('numClipped', obj.numClipped);
            epoch.addParameter('xOffset', obj.xOffset);
            epoch.addParameter('yoffSet', obj.yOffset);
            if strcmp(obj.noiseClass, 'Gaussian')
                epoch.addParameter('numClippedGauss', obj.numClippedGauss);
            end
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
