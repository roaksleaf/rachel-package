classdef ModifiedStimuli < manookinlab.protocols.ManookinLabStageProtocol
    properties
        amp                             % Output amplifier
        preTime = 250                   % Stimulus leading duration (ms)
        stimTime = 7033                % Stimulus duration (ms) %7033 for doves, 7000 for noise
        tailTime = 250                  % Stimulus trailing duration (ms)
        stimulusSet = 'DovesMod'          % The current movie stimulus set %DovesMod, NoiseMod
        onlineAnalysis = 'extracellular' % Type of online analysis
        numberOfAverages = uint16(180)   % Number of epochs %9 stimuli (mod and unmod), 10 repeats = 2*9*10
        singleCellFlag = 0              %0 for MEA, 1 for single cell mode
        maxPixelVal = uint16(30)          %what does pixel value of 1 equal in isomerizations/sec at current light level
        condition = symphonyui.core.PropertyType('char', 'row', {'linear_30', 'linear_10', 'linear_3', 'speed_3to10', 'slow_30to10'})
        fileFolder = 'modStimuli'
        backgroundIntensity = 0.5       % Background light intensity (0-1)
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        apertureDiametersType = symphonyui.core.PropertyType('denserealdouble','matrix')
        imageMatrix
        backgroundFrame
        movieName
        magnificationFactor
        currentStimSet
        stimulusIndex
        pkgDir
        im
        apertureDiameter
        apertureDiameterPix     
        pixelIndex                  %if singleCellFlag=1, location of dynamic pixel
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
        
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            
            if numel(obj.rig.getDeviceNames('Amp')) < 2
                obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));
                colors = zeros(length(obj.apertureDiameters),3);
                colors(1,:) = [0.8,0,0];
                obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
                    obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
                    'sweepColor',colors,...
                    'groupBy',{'apertureDiameter'});
            else
                obj.showFigure('edu.washington.riekelab.figures.DualResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
                obj.showFigure('edu.washington.riekelab.figures.DualMeanResponseFigure', obj.rig.getDevice(obj.amp), obj.rig.getDevice(obj.amp2));
            end
            
%             if ~strcmp(obj.onlineAnalysis, 'none')
%                 colors = zeros(length(obj.apertureDiameters),3);
%                 colors(1,:) = [0.8,0,0];
%                 obj.showFigure('manookinlab.figures.MeanResponseFigure', ...
%                     obj.rig.getDevice(obj.amp),'recordingType',obj.onlineAnalysis,...
%                     'sweepColor',colors,...
%                     'groupBy',{'apertureDiameter'});
%             end

            obj.directory = fprintf('C:\Users\Public\Documents\GitRepos\Symphony2\rachel-package\+edu\+washington\+riekelab\+rachel\+%s\+%s\',obj.stimulusSet, obj.condition);
            D = dir(obj.directory);
            
            obj.imagePaths = cell(size(D,1),1);
            for a = 1:length(D)
                if sum(strfind(D(a).name,'.mat')) > 0
                    obj.imagePaths{a,1} = D(a).name;
                end
            end
            obj.imagePaths = obj.imagePaths(~cellfun(@isempty, obj.imagePaths(:,1)), :);
            
            num_reps = ceil(double(obj.numberOfAverages)/size(obj.imagePaths,1));

            if obj.randomize
                obj.sequence = zeros(1,obj.numberOfAverages);
                seq = (1:size(obj.imagePaths,1));
                for ii = 1 : num_reps
                    seq = randperm(size(obj.imagePaths,1));
                    obj.sequence((ii-1)*length(seq)+(1:length(seq))) = seq;
                end
                obj.sequence = obj.sequence(1:obj.numberOfAverages);
            else
                obj.sequence = (1:size(obj.imagePaths,1))' * ones(1,num_reps);
                obj.sequence = obj.sequence(:);
            end
        end
        
        function p = createPresentation(obj)
            if obj.singleCellFlag == 0
                % Stage presets
                canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
                p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
                
                p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
                
                % Prep to display movie
                scene = stage.builtin.stimuli.Movie(fullfile(obj.directory,obj.movie_name));
                scene = scene ./ obj.maxPixelVal; %scale image such that pixel val of 1 = max isomerizations/sec for projector (original stim in isomerizations per sec)
                scene.size = [canvasSize(1),canvasSize(2)];
                scene.position = canvasSize/2;
                scene.setPlaybackSpeed(PlaybackSpeed.FRAME_BY_FRAME); % Make sure playback is one frame at a time.
                
                % Use linear interpolation when scaling the image
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);
    
                % Only allow image to be visible during specific time
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);

            elseif obj.singleCellFlag == 1 %for photoreceptor recordings, choose one dynamic pixel and display as full field movie

                canvasSize = obj.rig.getDevice('Stage').getCanvasSize();     
                p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
                
                p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity

                matrix = fullfile(obj.directory,obj.movie_name);
                [pixel, obj.pixelIndex] = max(var(matrix, 0, 3), 'all'); % find pixel with highest variance over time

                scene = stage.builtin.stimuli.Movie(pixel);
                scene = scene ./ obj.maxPixelVal; %scale image such that pixel val of 1 = max isomerizations/sec for projector (original stim in isomerizations per sec)
                scene.size = [canvasSize(1),canvasSize(2)];
                scene.position = canvasSize/2;
                scene.setPlaybackSpeed(PlaybackSpeed.FRAME_BY_FRAME); % Make sure playback is one frame at a time.
                
                % Use linear interpolation when scaling the image
                scene.setMinFunction(GL.LINEAR);
                scene.setMagFunction(GL.LINEAR);
    
                % Only allow image to be visible during specific time
                p.addStimulus(scene);
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
            end
                
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            mov_name = obj.sequence(mod(obj.numEpochsCompleted,length(obj.sequence)) + 1);
            obj.movie_name = obj.imagePaths{mov_name,1};
            
            epoch.addParameter('movieName',obj.imagePaths{mov_name,1});
            epoch.addParameter('stimulusSet', obj.stimulusSet);
            epoch.addParameter('condition', obj.condition);
            epoch.addParameter('preTime', obj.preTime);
            epoch.addParameter('stimTime', obj.stimTime);
            epoch.addParamter('tailTime', obj.tailTime);

            if obj.randomize
                epoch.addParameter('seed',obj.seed);
            end
           
            if obj.singleCellFlag == 1
                epoch.addParameter('pixelIndex', obj.pixelIndex)
            end
        end
        
        function tf = shouldContinuePreparingEpochs(obj)
            tf = obj.numEpochsPrepared < obj.numberOfAverages;
        end
        
        function tf = shouldContinueRun(obj)
            tf = obj.numEpochsCompleted < obj.numberOfAverages;
        end
    end
end