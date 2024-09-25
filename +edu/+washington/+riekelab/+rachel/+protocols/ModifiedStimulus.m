% Plays movies...
% Note: Requires movies in .mp4 format.
classdef ModifiedStimulus < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        amp                             % Output amplifier
        preTime = 250                   %Stimulus leading duration (ms)
        stimTime = 7033                % Stimulus duration (ms) %7033 for doves, 7000 for noise
        tailTime = 250                  % Stimulus trailing duration (ms)
        stimulusSet = 'DovesMod';          % The current movie stimulus set %DovesMod, NoiseMod
        onlineAnalysis = 'none'; % Type of online analysis
        numberOfAverages = uint16(10)   % Number of epochs %9 stimuli (mod and unmod), 10 repeats = 2*9*10
        singleCellFlag = false;              %0 for MEA, 1 for single cell mode
        maxPixelVal = double(1);          %what does pixel value of 1 equal in isomerizations/sec at current light level
        condition = 'linear_30';         %'linear_30', 'linear_10', 'linear_3', 'speed_3to10', 'slow_30to10'
        randomize = true;
        
    end
    
    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'spikes_CClamp', 'subthresh_CClamp', 'analog'})
        imageMatrix
        backgroundFrame
        backgroundIntensity
        magnificationFactor
        imagePaths
        sequence
        movie_name
        directory
        seed
        totalRuns
        pixelIndex 
    end

    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end

        function prepareRun(obj)

            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);

            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            obj.directory = sprintf('C:\\Users\\Public\\Documents\\GitRepos\\Symphony2\\rachel-package\\+edu\\+washington\\+riekelab\\+rachel\\+%s\\+%s',obj.stimulusSet, obj.condition);

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
            
            % Get the magnification factor. Exps were done with each pixel
            % = 1 arcmin == 1/60 degree; 200 um/degree...
            obj.magnificationFactor = round(2/60*200/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'));
            
        end

        
        function p = createPresentation(obj)
                % Stage presets
                canvasSize = obj.rig.getDevice('Stage').getCanvasSize();  
                p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3);
                p.setBackgroundColor(obj.backgroundIntensity)   % Set background intensity
                
                %Prepare scene
                scene = stage.builtin.stimuli.Image(obj.imageMatrix(:, :, 1));
                scene.size = [size(obj.imageMatrix,2) size(obj.imageMatrix,1)]*obj.magnificationFactor;
                scene.position = canvasSize/2;

                scene.setMinFunction(GL.NEAREST);
                scene.setMagFunction(GL.NEAREST);
                
                % Add stimulus to presentation
                p.addStimulus(scene);
                
                %Add controller
                sceneFrame = stage.builtin.controllers.PropertyController(scene,...
                    'imageMatrix', @(state)getSceneFrame(obj, state.time - obj.preTime*1e-3));
                % Add the frame controller.
                p.addController(sceneFrame);

                function p = getSceneFrame(obj, time)
                    if time > 0 && time <= obj.stimTime*1e-3
                        fr = round(time*60)+1;
                        p = obj.imageMatrix(:,:,fr);
                    else 
                        p = obj.backgroundFrame;
                    end
                end
                
                %Add visibility controller
                sceneVisible = stage.builtin.controllers.PropertyController(scene, 'visible', ...
                    @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
                p.addController(sceneVisible);
                
        end
        
        function prepareEpoch(obj, epoch)
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            mov_name = obj.sequence(mod(obj.numEpochsCompleted,length(obj.sequence)) + 1);
            obj.movie_name = obj.imagePaths{mov_name,1};

            % load file
            disp(obj.directory)
            disp(obj.movie_name)
            fileLocation = fullfile(obj.directory, obj.movie_name);
            temp = load(char(fileLocation), 'frames');

            matrix = temp.frames;
            matrix = matrix ./ obj.maxPixelVal; %scale image from isomerizations/sec to pixel values
        
            % Prep to display movie
            if obj.singleCellFlag
                varmat = var(matrix, 0, 3);
                pixel = max(varmat(:)); % find pixel with highest variance over time
                [x, y] = find(varmat == pixel);
                obj.pixelIndex = [x, y];
                fullPixel = zeros(size(matrix));
                matrixSize = size(matrix);
                for i = 1:matrixSize(3)
                    fullPixel(:, :, i) = repelem(matrix(x, y, i), matrixSize(1), matrixSize(2));
                end
                fullPixel = uint8(255*fullPixel);
                obj.imageMatrix = fullPixel;
            else
                matrix = uint8(255*matrix);
                obj.imageMatrix = matrix;
                disp('imageMatrix')
            end
            
            obj.backgroundIntensity = mean(double(obj.imageMatrix(:))/255);
            obj.backgroundFrame = uint8(obj.backgroundIntensity*ones(240, 320));
            disp('background')
           
            epoch.addParameter('movieName',obj.imagePaths{mov_name,1});
            epoch.addParameter('stimulusSet', obj.stimulusSet);
            epoch.addParameter('condition', obj.condition);
            epoch.addParameter('preTime', obj.preTime);
            epoch.addParameter('stimTime', obj.stimTime);
            epoch.addParameter('tailTime', obj.tailTime);   
            epoch.addParameter('magnificationFactor', obj.magnificationFactor);
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