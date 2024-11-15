classdef FlickeringBarSplitField < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp
        uniqueTime = 160000                % Duration of unique noise sequence (ms)
        repeatTime = 20000                 % Repeat phase duration (ms)
        frameDwell = 1                     % Number of frames each unique frame is displayed
        contrast = 0.6                     % Contrast of flickering bars
        baseMean = 0.5                     % mean of total stimulus
        meanOffset = 0.2                   % low mean = base - offset, high mean = base + offset
        barWidth = 20                      % Width of each bar (pixels)
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
        time_multiple
        imgSize
        displayWidth
        displayHeight
        numClipped
        numClippedGauss
        calcBottomMean
        calcTopMean
        calcLeftMean
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
            
            % Calculate the offsets for the left and right halves
            obj.leftOffset = -1 * obj.meanOffset;
            obj.rightOffset = obj.meanOffset;
            
            obj.displayWidth = obj.canvasSize(1)*2;
            obj.displayHeight = obj.canvasSize(2)*2;

            if strcmp(obj.orientationMode, 'Vertical')
                obj.numBars = ceil(obj.displayWidth / obj.barWidth);
            elseif strcmp(obj.orientationMode, 'Horizontal')
                obj.numBars = ceil(obj.displayHeight / obj.barWidth);
            end

            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            obj.pre_frames = round(obj.preTime * 1e-3 * 60.0);
            obj.unique_frames = round(obj.uniqueTime * 1e-3 * 60.0);
            obj.repeat_frames = round(obj.repeatTime * 1e-3 * 60.0);
            
            try
                obj.time_multiple = obj.rig.getDevice('Stage').getExpectedRefreshRate() / obj.rig.getDevice('Stage').getMonitorRefreshRate();
            catch
                obj.time_multiple = 1.0;
            end
            
%             obj.barMask1 = zeros(obj.canvasSize(2)*2, obj.canvasSize(1)*2);
%              for i=1:2:obj.numBars
%                 xStart1 = (i-1) * 20 + 1;
%                 xEnd1 = i * 20;
%                 if strcmp(obj.orientationMode, 'Vertical')
%                     obj.barMask1(:, xStart1:xEnd1) = 1;
%                 elseif strcmp(obj.orientationMode, 'Horizontal')
%                     obj.barMask1(xStart1:xEnd1, :) = 1;
%                 end
%              end
%             obj.barMask1 = logical(obj.barMask1);
%             
%             ct = 0.3*obj.noiseStream.randn(1,ceil(obj.numBars/2));
%             ct(ct<-1) = -1;
%             ct(ct>1) = 1;
% 
%             variation = ct .* obj.baseMean;
%             luminances1 = obj.baseMean - variation;
% 
%             luminances1 = repelem(luminances1, obj.canvasSize(2)*2, obj.barWidth);
%             fprintf('lum: %d %d \n', size(luminances1, 1), size(luminances1,2));
%             fprintf('bars: %d \n', obj.numBars);
%             fprintf('bw: %d \n', obj.barWidth);
        end
        
        function p = createPresentation(obj)

            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3 * obj.time_multiple);
            p.setBackgroundColor(obj.backgroundIntensity);

            obj.imageMatrix = obj.backgroundIntensity * ones(obj.canvasSize(2)*2, obj.canvasSize(1)*2);
            bars = stage.builtin.stimuli.Image(uint8(obj.imageMatrix));
%             bars.position = [((obj.canvasSize(2)/2) + obj.xOffset) ((obj.canvasSize(1)/2)+obj.yOffset)];
            bars.position = obj.canvasSize/2;
            bars.position = bars.position + [obj.xOffset obj.yOffset];
%             fprintf('CS: %d %d \n', obj.canvasSize(1), obj.canvasSize(2));
%             fprintf('IM: %d %d \n', size(obj.imageMatrix,1), size(obj.imageMatrix,2));
%             fprintf('BM1: %d %d \n', size(obj.barMask1,1), size(obj.barMask1,2));
            
            bars.size = [size(obj.imageMatrix,1) size(obj.imageMatrix,2)];
            
            bars.setMinFunction(GL.NEAREST);
            bars.setMagFunction(GL.NEAREST);

            p.addStimulus(bars);

            barsVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(barsVisible);

            preF = floor(obj.preTime/1000 * 60);

            imgController = stage.builtin.controllers.PropertyController(bars, 'imageMatrix',...
                    @(state)generateFlickeringBars(obj, state.frame - preF));

            % Add the stimulus to the presentation
            p.addController(imgController);
            
            function stimdisplay = generateFlickeringBars(obj, frame)
                persistent M
                if frame == obj.nextSwapFrame
                    [obj.leftOffset, obj.rightOffset] = deal(obj.rightOffset, obj.leftOffset); % swap offsets
                    
                    if frame < obj.unique_frames
                        chooseSwap = obj.intervalStream.rand;
                    else 
                        chooseSwap = obj.intervalStreamRep.rand;
                    end
                    
                    if chooseSwap > 0.66666
                        obj.nextSwapInterval = obj.swapIntervals(3);
                    elseif (.33333 <= chooseSwap) && (chooseSwap <= .66666)
                        obj.nextSwapInterval = obj.swapIntervals(2);
                    else 
                        obj.nextSwapInterval = obj.swapIntervals(1);
                    end
                    obj.nextSwapFrame = obj.nextSwapFrame + ceil(obj.nextSwapInterval/1000 * obj.frameRate);
                end
                
                if frame > 0
                    if mod(frame, obj.frameDwell) == 0
                        M = obj.baseMean * ones(obj.canvasSize(2)*2, obj.canvasSize(1)*2); 
                        
                        if strcmp(obj.orientationMode, 'Gaussian')
                            if frames < obj.unique_frames
                                ct = 0.3*obj.noiseStream.randn(1,ceil(obj.numBars/2));
                            else 
                                ct = 0.3*obj.noiseStreamRep.randn(1,ceil(obj.numBars/2));
                            end

                            ct(ct<-1) = -1;
                            ct(ct>1) = 1;
                            variation = ct .* obj.baseMean;

                        elseif strcmp(obj.orientationMode, 'Binary')
                            if frames < obj.unique_frames
                                variation = obj.contrast * (obj.noiseStream.rand(1,ceil(obj.numBars/2)) > 0.5) - (obj.baseMean - obj.meanOffset);
                            else
                                variation = obj.contrast * (obj.noiseStreamRep.rand(1,ceil(obj.numBars/2)) > 0.5) - (obj.baseMean - obj.meanOffset);
                            end
                        elseif strcmp(obj.noiseClass, 'Uniform')
                            if frames < obj.unique_frames
                                variation = obj.noiseStream.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, 1, ceil(obj.numBars/2));
                            else
                                variation = obj.noiseStreamRep.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, 1, ceil(obj.numBars/2));
                        end

                        luminances1 = obj.baseMean - variation;
                        luminances2 = obj.baseMean + variation;
%                         
%                         for i = 1:2:obj.numBars
%                             xStart1 = (i - 1) * obj.barWidth + 1;
%                             xEnd1 = i * obj.barWidth;
%                             xStart2 = i * obj.barWidth + 1;
%                             xEnd2 = (i + 1) * obj.barWidth;
% %                             if strcmp(obj.orientationMode, 'Vertical')
% %                                 M(:, xStart1:xEnd1) = luminances1(i); 
% %                                 M(:, xStart2:xEnd2) = luminances2(i);
% %                             elseif strcmp(obj.orientationMode, 'Horizontal')
% %                                 M(xStart1:xEnd1, :) = luminances1(i); 
% %                                 M(xStart2:xEnd2, :) = luminances2(i);
% %                             end
%                         end

                        allLum = [luminances1;luminances2];
                        allLum = allLum(:)';
                        
                        allLum = repelem(allLum, obj.canvasSize(2)*2, obj.barWidth);
                        
                        M = allLum;

%                         luminances1 = repelem(luminances1, obj.canvasSize(2)*2, obj.barWidth);
%                         luminances2 = repelem(luminances2, obj.canvasSize(2)*2, obj.barWidth);
%                         
%                         M(obj.barMask1) = luminances1;
%                         M(~obj.barMask1) = luminances2;
% 
%                         M(:, 1:100) = luminances1(1,1);
%                         M(:, 200:300) = luminances2(1,1);
                        
%                         for i = 1:2:obj.numBars 
%                             if strcmp(obj.noiseClass, 'Binary')
%                                 if frame < obj.unique_frames
%                                     variation = obj.contrast * (obj.noiseStream.rand > 0.5) - (obj.baseMean - obj.meanOffset);
%                                 else 
%                                     variation = obj.contrast * (obj.noiseStreamRep.rand > 0.5) - (obj.baseMean - obj.meanOffset);
%                                 end
%                             elseif strcmp(obj.noiseClass, 'Gaussian')
%                                 if frame < obj.unique_frames
%                                     ct = 0.3*obj.noiseStream.randn;
%                                 else 
%                                      ct = 0.3*obj.noiseStreamRep.randn;
%                                 end
% %                                 obj.numClippedGauss = sum(ct(ct<-1, 'all')) + sum(ct(ct>-1, 'all'));
%                                 ct(ct<-1) = -1;
%                                 ct(ct>1) = 1;
%                                 variation = ct*obj.baseMean;
%                             elseif strcmp(obj.noiseClass, 'Uniform')
%                                 if frame < obj.unique_frames
%                                     variation = obj.noiseStream.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean);
%                                 else 
%                                     variation = obj.noiseStream.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean);
%                                 end
%                             end
% 
%                             luminance1 = obj.baseMean - variation;
%                             luminance2 = obj.baseMean + variation;
% 
%                             xStart1 = (i - 1) * obj.barWidth + 1;
%                             xEnd1 = i * obj.barWidth;
%                             xStart2 = i * obj.barWidth + 1;
%                             xEnd2 = (i + 1) * obj.barWidth;
% 
%                             if strcmp(obj.orientationMode, 'Vertical')
%                                 M(:, xStart1:xEnd1) = luminance1; 
%                                 M(:, xStart2:xEnd2) = luminance2;
%                             elseif strcmp(obj.orientationMode, 'Horizontal')
%                                 M(xStart1:xEnd1, :) = luminance1; 
%                                 M(xStart2:xEnd2, :) = luminance2;
%                             end
%                         end
                    end
                else
                    M = obj.imageMatrix;
                end
                
                if strcmp(obj.orientationMode, 'Vertical')
                    width = obj.canvasSize(1)*2;
                    M(:, 1:floor(width/2)) =  M(:, 1:floor(width/2)) + obj.leftOffset;
%                     obj.calcLeftMean = mean(M(:, 1:floor(width/2)), 'all');
                    M(:, floor(width/2)+1:end) = M(:, floor(width/2)+1:end) + obj.rightOffset;
%                     obj.calcRightMean = mean(M(:, floor(width/2)+1:end), 'all');

                elseif strcmp(obj.orientationMode, 'Horizontal')
                    height = obj.canvasSize(2)*2;
                    M(1:floor(height/2), :) = M(1:floor(height/2), :) + obj.leftOffset;
%                     obj.calcBottomMean = mean(M(1:floor(height/2), :), 'all');
                    M(floor(height/2)+1:end, :) = M(floor(height/2)+1:end, :) + obj.rightOffset;
%                     obj.calcTopMean = mean(M(floor(height/2)+1:end, :), 'all');
                end
                
%                 obj.numClipped = sum(M(M<0), 'all') + sum(M(M>1),'all');
                
                M = max(0, min(1,M));
                
                stimdisplay = uint8(255*M);
            end

            disp('create presentation')
%             fprintf('numClipped: %d', obj.numClipped)
%             if strcmp(obj.orientationMode, 'Vertical')
%                 fprintf('left mean: %d', obj.calcLeftMean)
%                 fprintf('right mean: %d', obj.calcRightMean)
%             else 
%                 height = obj.canvasSize(2)*2;
%                 fprintf('bottom mean: %d', obj.calcBottomMean)
%                 fprintf('top mean: %d', obj.calcTopMean)
%             end
%             if strcmp(obj.noiseClass, 'Gaussian')
%                 fprintf('numClippedGaus: %d', obj.numClippedGauss)
%             end
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
            
            chooseSwap = obj.intervalStream.rand;
            if chooseSwap > .66666
                obj.nextSwapInterval = obj.swapIntervals(3);
            elseif (.33333 <= chooseSwap) && (chooseSwap <= .66666)
                obj.nextSwapInterval = obj.swapIntervals(2);
            else 
                obj.nextSwapInterval = obj.swapIntervals(1);
            end
            obj.nextSwapFrame = ceil(obj.nextSwapInterval/1000 * obj.frameRate);

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
