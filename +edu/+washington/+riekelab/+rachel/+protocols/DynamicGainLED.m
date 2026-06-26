classdef DynamicGainLED < edu.washington.riekelab.protocols.RiekeLabProtocol
    % Presents dynamically varying LED noise stimulus, accompanies the DynamicGain protocol in Rachel-Package.  
    
    %   The 'mode' property selects the experiment variant:
    %     'base'     - one interval per epoch; mean alternates low/high across
    %                  repeated steps of length stepDuration; random seed each epoch.
    %     'repeated' - frozen seed every epoch; each interval length is shown under
    %                  three starting-mean conditions (low/high/end); the mean trace
    %                  alternates low/high but the final tracking window is endmean.
    %     'oneStep'  - like 'base', but the mean holds the initial value for almost
    %                  the whole stimulus, makes a SINGLE step, then the tracking
    %                  window: [stimTime - trackDur - stepDuration, stepDuration, trackDur].


    properties
        led                             % Output LED
        stimTime = 120000               % Noise duration (ms)
        stepDurations = [60000 20000 2000] %duration of stepwise noise changes (ms)
        trackDur = 60000                % duration of tracking period following final mean change (ms)
        frequencyCutoff = 60            % Noise frequency cutoff for smoothing (Hz)
        numberOfFilters = 4             % Number of filters in cascade for noise smoothing
        contrast = 0.6                  % Noise contrast
        epochOrder = 'interleaved'      %interleaved or randomized
        mode = 'repeated'               
        useFixedSeed = True             % Use a random seed for each standard deviation multiple?
        fixedSeedValue = 1
        sequentialMeans = true          % go through means in sequence or randomly
        lowMean = 0.01                  % LED background mean (low) (V or norm. [0-1] depending on LED units)
        highMean = 1                   % LED background mean (high) (V or norm. [0-1] depending on LED units)
        endMean = 0.1                   %LED Background mean (end)
        amp                             % Input amplifier
    end
    
    properties (Dependent, SetAccess = private)
        amp2                            % Secondary amplifier
    end
    
    properties
        numberOfAverages = uint16(5)    % Number of families
        interpulseInterval = 0          % Duration between noise stimuli (s)
    end
    
    properties (Hidden)
        ledType
        ampType
        durationsPerEpoch
        meansPerEpoch
        stepDuration
        initmean
        polarityType
        epochStepDurations
        epochMeans
        % lightMeanSequence
        % lightContrastSequence
    end
    
    methods
                
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            [obj.led, obj.ledType] = obj.createDeviceNamesProperty('LED');
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function d = getPropertyDescriptor(obj, name)
            d = getPropertyDescriptor@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, name);
            
            if strncmp(name, 'amp2', 4) && numel(obj.rig.getDeviceNames('Amp')) < 2
                d.isHidden = true;
            end
        end
        
        %when is this function called? 
        function p = getPreview(obj, panel)
            p = symphonyui.builtin.previews.StimuliPreview(panel, @()createPreviewStimuli(obj));
            function s = createPreviewStimuli(obj)
                s = cell(1, obj.numberOfAverages);
                for i = 1:numel(s)
                    if obj.useFixedSeed
                        seed = obj.fixedSeedValue;
                    else
                        seed = RandStream.shuffleSeed;
                    end
                    s{i} = obj.createLedStimulus(obj.contrast, obj.epochMeans, obj.epochStepDurations, seed);
                end
            end
        end
        
        function prepareRun(obj)
            prepareRun@edu.washington.riekelab.protocols.RiekeLabProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                obj.showFigure('symphonyui.builtin.figures.MeanResponseFigure', obj.rig.getDevice(obj.amp), ...
                    'groupBy', {'stdv'});
                obj.showFigure('symphonyui.builtin.figures.ResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, ...
                    'baselineRegion', [0 obj.stimTime], ...
                    'measurementRegion', [0 obj.stimTime]);
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2), ...
                    'groupBy1', {'stdv'}, ...
                    'groupBy2', {'stdv'}); %should this be group by step duration? 
                obj.showFigure('edu.washington.riekelab.figures.DualResponseStatisticsFigure', obj.rig.getDevice(obj.amp), {@mean, @var}, obj.rig.getDevice(obj.amp2), {@mean, @var}, ...
                    'baselineRegion1', [0 obj.stimTime], ...
                    'measurementRegion1', [0 obj.stimTime], ...
                    'baselineRegion2', [0 obj.stimTime], ...
                    'measurementRegion2', [0 obj.stimTime]);
            end
            
            device = obj.rig.getDevice(obj.led);
            %ok to set to 0.5? 
            device.background = symphonyui.core.Measurement(0.5, device.background.displayUnits);
            if obj.useFixedSeed
                rng('default'); %not sure what this line does
            end

            [durs, means] = obj.buildEpochSchedule();
            n = numel(durs);
            if strcmp(obj.epochOrder, 'randomized')
                order = randperm(n);
                durs  = durs(order);
                means = means(order);
            end

            obj.durationsPerEpoch = durs;
            obj.meansPerEpoch     = means;

        end

        function [durations, means] = buildEpochSchedule(obj)
            % Per-epoch (interval, starting-mean) lists, before ordering.
            base = obj.interleaveDurations(obj.stepDurations, obj.durRepEpochs);
            if strcmp(obj.mode, 'repeated')
                % Each interval shown under low/high/end starting means.
                durations = repelem(base, 3);
                means     = repmat([obj.lowmean, obj.highmean, obj.endmean], 1, numel(base));
            else
                % One alternating low/high mean per interval.
                durations = base;
                n = numel(base);
                cycle = repmat([obj.lowmean, obj.highmean], 1, ceil(n / 2));
                means = cycle(1:n);
            end
        end

        function durations = interleaveDurations(~, stepDurations, repCounts)
            % One entry per epoch, interleaved across the requested interval lengths.
            % Honors unequal per-duration repeat counts (extras appended at the end).
            minRep    = min(repCounts);
            durations = repmat(stepDurations, 1, minRep);
            extra     = repCounts - minRep;
            while any(extra)
                for i = 1:numel(repCounts)
                    if extra(i) >= 1
                        durations = [durations, stepDurations(i)]; %#ok<AGROW>
                        extra(i)  = extra(i) - 1;
                    end
                end
            end
        end

        function stepDurs = buildStepDurations(obj, stepDuration)
            % Step layout of the stimulus portion (before pre/tail padding).
            if strcmp(obj.mode, 'oneStep')
                % One long hold, a single step, then the tracking window.
                stimDur  = obj.stimTime - obj.trackDur;
                initDur  = ceil(stimDur - stepDuration);
                stepDurs = [initDur, stepDuration, obj.trackDur];
            else
                % Repeat the interval across the stimulus, then the tracking window.
                numSteps = ceil((obj.stimTime - obj.trackDur) / stepDuration);
                stepDurs = [repmat(stepDuration, 1, numSteps), obj.trackDur];
            end
        end

        function means = assignmeans(obj, stepDurs, initMean)
            % Alternate low/high from initmean. If initmean is neither low nor high
            % (e.g. endmean), the trace stays constant at initmean.
            means  = zeros(1, numel(stepDurs));
            target = initMean;
            for k = 1:numel(stepDurs)
                means(k) = target;
                if target == obj.lowMean
                    target = obj.highMean;
                elseif target == obj.highMean
                    target = obj.lowMean;
                end
            end

            % 'repeated' mode: force the tracking window to endmean and record polarity.
            if strcmp(obj.mode, 'repeated')
                means(end) = obj.endMean;
                if initMean == obj.endMean
                    means(:) = obj.endMean;
                end
                if means(end-1) == obj.lowMean
                    obj.polarityType = 'increment';
                elseif means(end-1) == obj.highMean
                    obj.polarityType = 'decrement';
                else
                    obj.polarityType = 'none';
                end
            else
                if means(end) == obj.highMean
                    obj.polarityType = 'increment';
                elseif means(end) == obj.lowMean
                    obj.polarityType = 'decrement';
                end

            end

            
        end

        
        function [stim] = createLedStimulus(obj, contrast, mean_values, step_durations, seed)
            gen = edu.washington.riekelab.stimuli.DynamicNoiseGenerator();
            
            gen.preTime = 0;
            gen.stimTime = obj.stimTime;
            gen.tailTime = 0;
            gen.contrast = contrast;
            gen.freqCutoff = obj.frequencyCutoff;
            gen.numFilters = obj.numberOfFilters;
            gen.meanValues = mean_values;
            gen.stepDurations = step_durations;
            gen.seed = seed;
            gen.sampleRate = obj.sampleRate;
            gen.units = obj.rig.getDevice(obj.led).background.displayUnits;
            if strcmp(gen.units, symphonyui.core.Measurement.NORMALIZED)
                gen.upperLimit = 1;
                gen.lowerLimit = 0;
            else
                gen.upperLimit = 10.239;
                gen.lowerLimit = -10.24;
            end
            
            stim = gen.generate();
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, epoch);
            
            persistent seed;
            if obj.useFixedSeed
                % seed = obj.numEpochsPrepared;
                seed = obj.fixedSeedValue;
            else
                % seed = RandStream.shuffleSeed;
                seed = randi(2^32 - 1);
            end
            
            idx = mod(obj.numEpochsCompleted, numel(obj.durationsPerEpoch)) + 1;

            obj.stepDuration = obj.durationsPerEpoch(idx);
            obj.initMean     = obj.meansPerEpoch(idx);
            obj.stepFrames   = round(obj.stepDuration * 1e-3 * 60.0);
            obj.polarityType = 'none';

            stimSteps = obj.buildStepDurations(obj.stepDuration);
            stimMeans = obj.assignMeans(stimSteps, obj.initMeans);
            obj.epochStepDurations = stimSteps;
            obj.epochMeans     = stimMeans;
            
            [stim] = obj.createLedStimulus(obj.contrast, obj.epochMeans, obj.epochStepDurations, seed);
            
            epoch.addParameter('contrast', obj.contrast);
            epoch.addParameter('epochStepDurations', obj.epochStepDurations)
            epoch.addParameter('epochMeans', obj.epochMeans)
            epoch.addParameter('polarityType', obj.polarityType)
            epoch.addParameter('seed', seed);
            epoch.addStimulus(obj.rig.getDevice(obj.led), stim);
            epoch.addResponse(obj.rig.getDevice(obj.amp));
            
            if numel(obj.rig.getDeviceNames('Amp')) >= 2
                epoch.addResponse(obj.rig.getDevice(obj.amp2));
            end
        end
        
        function prepareInterval(obj, interval)
            prepareInterval@edu.washington.riekelab.protocols.RiekeLabProtocol(obj, interval);
            
            device = obj.rig.getDevice(obj.led);
            interval.addDirectCurrentStimulus(device, device.background, obj.interpulseInterval, obj.sampleRate);
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
