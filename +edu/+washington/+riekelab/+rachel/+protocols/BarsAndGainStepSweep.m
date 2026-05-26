classdef BarsAndGainStepSweep < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        preTime = 200                     % ms
        stimTime = 120000               % ms
        tailTime = 200                    % ms
        stixelSize = 60                 % um
        binaryNoise = false
        pairedBars = false
        noiseStdv = 0.6                 % contrast
        noiseMean = 0.5                 % pixel mean of noise stimulus
        frameDwell = 3                  % frames per noise update
        stepDuration = 5000             % ms, duration of each gain step
        numStepsPerCondition = [3 6 9]  % number of gain steps per condition (before rest-of-stim hold)
        numRepeatsPerCondition = [4 4 4]% number of repeats for each condition
        lowGain = 0.1                   % projector gain low
        highGain = 1.0                  % projector gain high
        alternateFixedSeed = false
        interleave = true
        backgroundIntensity = 0.5      % (0-1)
        numberOfAverages = uint16(12)  % number of epochs to queue
        apertureDiameter = 0           % um
        onlineAnalysis = 'none'
        amp                            % Output amplifier
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        noiseSeed
        noiseStream
        numChecksX
        numChecksY
        imageMatrix
        lineMatrix
        useFixedSeed = false
        startDim = true
        conditionOrder          % full interleaved/blocked sequence of condition indices
        currentConditionIdx     % index into numStepsPerCondition for this epoch
        projStepDurations       % step duration array for ProjectorGainGenerator
        projGainMeans           % gain value array for ProjectorGainGenerator
        projector_gain_device
        lowMean
        highMean
        backgroundFrameDwell
        numFrames
        preFrames
        trackFrames
        trackDur_ms
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
         
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            % Canvas size and checker dimensions
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();
            stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.numChecksX = round(canvasSize(1) / stixelSizePix);
            obj.numChecksY = round(canvasSize(2) / stixelSizePix);

            % Build the full epoch condition sequence (interleaved or blocked)
            % conditionOrder is a 1 x totalEpochs array of condition indices (into numStepsPerCondition)
            numConditions = length(obj.numStepsPerCondition);
            if obj.interleave
                % Interleave conditions, respecting per-condition repeat counts
                minRep = min(obj.numRepeatsPerCondition);
                deltareps = obj.numRepeatsPerCondition - minRep;
                % Start with minRep full rounds of all conditions
                obj.conditionOrder = repmat(1:numConditions, [1, minRep]);
                % Append extra repeats one at a time across conditions
                while any(deltareps)
                    for i = 1:numConditions
                        if deltareps(i) >= 1
                            obj.conditionOrder = [obj.conditionOrder, i]; %#ok<AGROW>
                            deltareps(i) = deltareps(i) - 1;
                        end
                    end
                end
            else
                % Blocked: all repeats of condition 1, then condition 2, etc.
                obj.conditionOrder = repelem(1:numConditions, obj.numRepeatsPerCondition);
            end
            disp('Condition order:');
            disp(obj.conditionOrder);

            % Precompute frame counts
            obj.numFrames   = floor(obj.stimTime * 1e-3 * obj.frameRate) + 15;
            obj.preFrames   = round(obj.preTime * 1e-3 * 60.0);

            % Shared with util function (mirrors BarsAndGain convention)
            obj.lowMean  = obj.noiseMean;
            obj.highMean = obj.noiseMean;
            obj.backgroundFrameDwell = 1000;

            % Detect projector gain device
            projector_gain = obj.rig.getDevices('Projector Gain');
            if ~isempty(projector_gain)
                obj.projector_gain_device = true;
            else
                obj.projector_gain_device = false;
            end
        end
        
        function prepareEpoch(obj, epoch)
            fprintf(1, 'start prepare epoch\n');
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);

            % --- Noise seed ---
            if obj.useFixedSeed
                obj.noiseSeed = 1;
            else
                obj.noiseSeed = randi(2^32 - 1);
            end
            if ~obj.alternateFixedSeed
                obj.useFixedSeed = false;
            else
                obj.useFixedSeed = ~obj.useFixedSeed;
            end

            % --- Alternate startDim each epoch ---
            obj.startDim = ~obj.startDim;

            % --- Select condition for this epoch ---
            epochIdx = mod(obj.numEpochsCompleted, length(obj.conditionOrder)) + 1;
            obj.currentConditionIdx = obj.conditionOrder(epochIdx);
            nSteps = obj.numStepsPerCondition(obj.currentConditionIdx);

            % --- Build projector gain trace ---
            % Structure: [nSteps x stepDuration_ms] then [rest of stim at last gain]
            % The alternating gain starts from startDim:
            %   startDim=true  -> first step = lowGain
            %   startDim=false -> first step = highGain

            stepDur_ms = obj.stepDuration;  % ms per step

            % Build gain sequence for the nSteps alternating steps
            gainSeq = zeros(1, nSteps);
            if obj.startDim
                startGain = obj.lowGain;
            else
                startGain = obj.highGain;
            end
            currentGain = startGain;
            for k = 1:nSteps
                gainSeq(k) = currentGain;
                if currentGain == obj.lowGain
                    currentGain = obj.highGain;
                else
                    currentGain = obj.lowGain;
                end
            end

            % Last gain value after the alternating steps
%             lastGain = gainSeq(end);
            if gainSeq(end) == obj.lowGain
                lastGain = obj.highGain;
            elseif gainSeq(end) == obj.highGain
                lastGain = obj.lowGain;
            end

            % Rest-of-stim duration
            stepsTotalDur_ms = nSteps * stepDur_ms;
            restDur_ms = obj.stimTime - stepsTotalDur_ms;

            if restDur_ms <= 0
                % Edge case: steps fill or exceed stimTime — no rest period
                warning('BarsAndGainSteps: nSteps * stepDuration >= stimTime. No rest period will be appended.');
                obj.projStepDurations = repmat(stepDur_ms, 1, nSteps);
                obj.projGainMeans     = gainSeq;
            else
                obj.projStepDurations = [repmat(stepDur_ms, 1, nSteps), restDur_ms];
                obj.projGainMeans     = [gainSeq, lastGain];
            end

            disp('Condition (num steps):');
            disp(nSteps);
            disp('projStepDurations:');
            disp(obj.projStepDurations);
            disp('projGainMeans:');
            disp(obj.projGainMeans);

            % --- Add gain stimulus to epoch ---
            if obj.projector_gain_device
                epoch.addStimulus(obj.rig.getDevice('Projector Gain'), ...
                    obj.createGainStimulus(obj.projGainMeans, obj.projStepDurations));
            end

            % --- Log epoch parameters ---
            epoch.addParameter('noiseSeed',             obj.noiseSeed);
            epoch.addParameter('numChecksX',            obj.numChecksX);
            epoch.addParameter('numChecksY',            obj.numChecksY);
            epoch.addParameter('startDim',              obj.startDim);
            epoch.addParameter('currentConditionIdx',   obj.currentConditionIdx);
            epoch.addParameter('numSteps',              nSteps);
            epoch.addParameter('stepDuration',          stepDur_ms);
            epoch.addParameter('projStepDurations',     obj.projStepDurations);
            epoch.addParameter('projGainMeans',         obj.projGainMeans);
            epoch.addParameter('lowMean',               obj.lowMean);
            epoch.addParameter('highMean',              obj.highMean);
            epoch.addParameter('preFrames',             obj.preFrames);
            epoch.addParameter('backgroundFrameDwell',  obj.backgroundFrameDwell);

            if obj.projector_gain_device
                units = obj.rig.getDevice('Projector Gain').background.displayUnits;
                epoch.addParameter('projUnits', units);
            end

            fprintf(1, 'end prepare epoch\n');
        end

        function stim = createGainStimulus(obj, gain_values, step_durations)
            gen = edu.washington.riekelab.stimuli.ProjectorGainGenerator();
            gen.preTime       = obj.preTime;
            gen.stimTime      = obj.stimTime;
            gen.tailTime      = obj.tailTime;
            gen.stepDurations = step_durations;
            gen.gainValues    = gain_values;
            gen.sampleRate    = obj.sampleRate;
            gen.units         = obj.rig.getDevice('Projector Gain').background.displayUnits;
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
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
            p.setBackgroundColor(obj.backgroundIntensity);

            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);
            canvasSize = obj.rig.getDevice('Stage').getCanvasSize();

            % Create bar stimulus image
            initMatrix = uint8(255 .* (obj.backgroundIntensity .* ones(obj.numChecksY, obj.numChecksX)));
            board = stage.builtin.stimuli.Image(initMatrix);
            board.size     = canvasSize;
            board.position = canvasSize / 2;
            board.setMinFunction(GL.NEAREST);
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);

            % Generate bar noise matrix via util function (same as BarsAndGain)
            % trackEnd=false, trackFrames=0 since this protocol has no track period
            obj.lineMatrix = util.getVariableMeanBars( ...
                obj.noiseSeed, obj.numChecksX, obj.preTime, obj.stimTime, obj.tailTime, ...
                obj.backgroundIntensity, obj.frameDwell, obj.binaryNoise, obj.noiseStdv, ...
                obj.lowMean, obj.highMean, obj.backgroundFrameDwell, obj.pairedBars, ...
                obj.startDim, false, 0);

            checkerboardController = stage.builtin.controllers.PropertyController(board, 'imageMatrix', ...
                @(state)getNewBoard(obj, state.frame + 1));
            p.addController(checkerboardController);

            % Optional circular aperture
            if obj.apertureDiameter > 0
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = canvasSize / 2;
                aperture.color    = obj.backgroundIntensity;
                aperture.size     = [max(canvasSize) max(canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix / max(canvasSize), 1024);
                aperture.setMask(mask);
                p.addStimulus(aperture);
            end

            % Hide board during pre and tail
            boardVisible = stage.builtin.controllers.PropertyController(board, 'visible', ...
                @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            p.addController(boardVisible);

            function i = getNewBoard(obj, frame)
                line = obj.lineMatrix(:, frame);
                i = uint8(255 * repmat(line', obj.numChecksY, 1));
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