classdef FlickeringBarStimulus < edu.washington.manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        uniqueTime = 160000                % Duration of unique noise sequence (ms)
        repeatTime = 20000                 % Repeat phase duration (ms)
        frameDwell = 1                     % Number of frames each unique frame is displayed
        contrast = 0.6                     % Contrast of flickering bars
        baseMean = 0.5                     % mean of total stimulus
        meanOffset = 0.2                   % low mean = base - offset, high mean = base + offset
        barWidth = 20                      % Width of each bar (pixels)
        frameRate = 60                     % Frame rate of the display (Hz)
        preTime = 250                      % Pre-stimulus time (ms)
        tailTime = 250                     % Post-stimulus time (ms)
        swapIntervals = [200 5000 10000]   % Possible swap intervals (ms)
        numberOfAvereages = uint16(20)     % Number of epochs
        noiseClass = 'Gaussian'             % Draw luminance values using binary, gaussian, uniform distribution
        orientationMode = 'Vertical'        %Direction of split field
        backgroundIntensity = 0.5
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
        noiseStream
        seed
        canvasSize
        imageMatrix
        nextSwapInterval
        nextSwapFrame
    end

    methods
        function didSetRig(obj)
            didSetRig@manookinlab.protocols.ManookinLabStageProtocol(obj);

            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            % Calculate the offsets for the left and right halves
            obj.leftOffset = -1 * obj.meanOffset;
            obj.rightOffset = obj.meanOffset;
            
            % Calculate total number of bars in the display width
            obj.canvasSize = obj.rig.getDevice('Stage').getCanvasSize;
            displayWidth = 2*obj.canvasSize(1);
            obj.numBars = floor(displayWidth / obj.barWidth);

            obj.numFrames = floor(obj.stimTime * 1e-3 * obj.frameRate)+15;
            obj.pre_frames = round(obj.preTime * 1e-3 * 60.0);
            obj.unique_frames = round(obj.uniqueTime * 1e-3 * 60.0);
            obj.repeat_frames = round(obj.repeatTime * 1e-3 * 60.0);

        end

        function prepareEpoch(obj, epoch)

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
            obj.positionStreamRep = RandStream('mt19937ar', 'Seed', 1);

            obj.nextSwapInterval = obj.intervalStream.randsample(obj.swapIntervals,1);
            obj.nextSwapFrame = round(obj.nextSwapInteval * obj.frameRate);

            % Save all parameters for this epoch
            epoch.addParameter('uniqueTime', obj.uniqueTime);
            epoch.addParameter('repeatTime', obj.repeatTime);
            epoch.addParameter('frameDwell', obj.frameDwell);
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParamter('baseMean', obj.baseMean);
            epoch.addParameter('meanOffset', obj.meanOffset);
            epoch.addParameter('barWidth', obj.barWidth);
            epoch.addParameter('seed', obj.seed);
            epoch.addParameter('repeating_seed', 1);
            epoch.addParameter('numFrames', obj.numFrames);
            epoch.addParameter('unique_frames', obj.unique_frames);
            epoch.addParameter('repeat_frames', obj.repeat_frames);
        end

        function p = createPresentation(obj)
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3 * obj.time_multiple);
            p.setBackgroundColor(obj.backgroundIntensity);

            obj.imageMatrix = obj.backgroundIntensity * ones(2*obj.canvasSize(1), 2*obj.canvasSize(2));
            bars = stage.builtin.stimuli.Image(uint8(obj.imageMatrix));
            bars.position = obj.canvasSize/2;

            p.addStimulus(bars);

            barsVisible = stage.builtin.controllers.PropertyController(bars, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3 * 1.011);
            p.addController(barsVisible);

            preF = floor(obj.preTime/1000 * 60);

            imgController = stage.builtin.controllers.PropertyController(bars, 'imageMatrix',...
                    @(state)generateFlickeringBars(obj, state.frame - preF));

            % Add the stimulus to the presentation
            p.addController(imgController);

            function frame = generateFlickeringBars(obj, frame)
                if frame > 0
                    if mod(frame,obj.frameDwell) == 0
                        frame = obj.baseMean * ones(2*obj.canvasSize(1), 2*obj.canvasSize(2));
                        if frame <= obj.unique_frames
                            if frame >= obj.nextSwapFrame
                                [obj.leftOffset, obj.rightOffset] = deal(obj.rightOffset, obj.leftOffset); % swap offsets
                                obj.nextSwapInterval = obj.intervalStream.randsample(obj.swapIntervals, 1); % pick a new interval
                                obj.nextSwapFrame = frameIdx + round(obj.nextSwapInterval * obj.frameRate); % next swap frame
                            end

                            % Iterate in pairs and generate random luminance for each
                            for i = 1:2:obj.numBars 
                                if strcmp(obj.noiseClass, 'Binary')
                                    variation = obj.contrast * (obj.noiseStream.rand > 0.5) - (obj.baseMean - obj.meanOffset);
                                elseif strcmp(obj.noiseClass, 'Gaussian')
                                    ct = 0.3*obj.noiseStream.randn;
                                    ct(ct<-1) = -1;
                                    ct(ct>1) = 1;
                                    variation = ct*obj.baseMean;
                                elseif strcmp(obj.noiseClass, 'Uniform')
                                    variation = obj.noiseStream.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean);
                                end

                                luminance1 = obj.baseMean - variation;
                                luminance2 = obj.baseMean + variation;

                                xStart1 = (i - 1) * obj.barWidth + 1;
                                xEnd1 = i * obj.barWidth;
                                xStart2 = i * obj.barWidth + 1;
                                xEnd2 = (i + 1) * obj.barWidth;
                               
                                frame(:, xStart1:xEnd1) = luminance1; 
                                frame(:, xStart2:xEnd2) = luminance2;
                            end

                        else
                            if frame >= obj.nextSwapFrame
                                [obj.leftOffset, obj.rightOffset] = deal(obj.rightOffset, obj.leftOffset); % swap offsets
                                obj.nextSwapInterval = obj.intervalStreamRep.randsample(obj.swapIntervals, 1); % pick a new interval
                                obj.nextSwapFrame = frameIdx + round(obj.nextSwapInterval * obj.frameRate); % next swap frame
                            end

                            % Iterate in pairs and generate random luminance for each
                            for i = 1:2:obj.numBars 
                                if strcmp(obj.noiseClass, 'Binary')
                                    variation = obj.contrast * (obj.noiseStreamRep.rand > 0.5) - (obj.baseMean - obj.meanOffset);
                                elseif strcmp(obj.noiseClass, 'Gaussian')
                                    ct = 0.3*obj.noiseStreamRep.randn;
                                    ct(ct<-1) = -1;
                                    ct(ct>1) = 1;
                                    variation = ct*obj.baseMean;
                                elseif strcmp(obj.noiseClass, 'Uniform')
                                    variation = obj.noiseStreamRep.unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean);
                                end
                            end
                        end

                        luminance1 = obj.baseMean - variation;
                        luminance2 = obj.baseMean + variation;

                        xStart1 = (i - 1) * obj.barWidth + 1;
                        xEnd1 = i * obj.barWidth;
                        xStart2 = i * obj.barWidth + 1;
                        xEnd2 = (i + 1) * obj.barWidth;
                       
                        frame(:, xStart1:xEnd1) = luminance1; 
                        frame(:, xStart2:xEnd2) = luminance2;
                
                        if strcmp(obj.orientationMode, 'Vertical')
                            frame(:, 1:width/2) = frame(:, 1:width/2) + obj.leftOffset;
                            frame(:, width/2+1:end) = frame(:, width/2+1:end) + obj.rightOffset;
                        elseif strcmp(obj.orientationMode, 'Horizontal')
                            frame(1:height/2, :) = frame(1:height/2) + obj.leftOffset;
                            frame(height/2+1:end, :) = frame(height/2+1:end, :) + obj.rightOffset;
                        end

                        % Clamp frame values
                        frame = max(0, min(1, frame));
                        frame = uint8(255*frame);
                    end
                end
            end
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
        
        function stimTime = get.stimTime(obj)
            stimTime = obj.uniqueTime + obj.repeatTime;
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
