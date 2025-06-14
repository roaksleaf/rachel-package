% Plays 1D noise + doves fixation image, for many fixations of the image.
classdef DovesPerturbationAlpha < manookinlab.protocols.ManookinLabStageProtocol
    
    properties
        preTime = 500 % ms
        stimTime = 6000 % ms
        tailTime = 500 % ms
        stixelSize = 60 % um
        gridSize = 30 % um
        stimulusIndices = [2, 10]         % Stimulus number (1:161)
        numMaxFixations = 10 % Maximum number of fixations
        binaryNoise = true %binary checkers
        pairedBars = true
        noiseStdv = 0.3 %contrast, as fraction of mean
        frameDwell = 1 % Frames per noise update
        apertureDiameter = 0 % um
        manualMagnification = 1.5         % Override DOVES magnification by setting this >1
        onlineAnalysis = 'none'
        numberOfAverages = uint16(60) % number of epochs to queue
        amp % Output amplifier
    end

    properties (Hidden)
        ampType
        onlineAnalysisType = symphonyui.core.PropertyType('char', 'row', {'none', 'extracellular', 'exc', 'inh'})
        projectionTypeType = symphonyui.core.PropertyType('char', 'row', {'none', 'linear filter'})
        noiseSeed
        positionStream
        gridSizePix
        stixelSizePix
        stixelShiftPix
        stepsPerStixel
        numChecksX
        numChecksY
        initMatrix
        imageMatrix
        dovesMatrix
        dovesMovieMatrix
        num_fixations
        all_fix_indices
        lineMatrix
        dimBackground
        useFixedSeed = true     % Toggle between fixed and random seeds
        imgContrastReduction
        im % All image data
        img % Current image (0-pad,1+pad)
        pkgDir
        currentStimSet
        stimulusIndex
        freezeFEMs = true
        xTraj
        yTraj
        u_xTraj
        u_yTraj
        timeTraj
        magnificationFactor
        imageName
        subjectName
        backgroundIntensity
    end
    
    methods
        
        function didSetRig(obj)
            didSetRig@edu.washington.riekelab.protocols.RiekeLabStageProtocol(obj);
            [obj.amp, obj.ampType] = obj.createDeviceNamesProperty('Amp');
        end
         
        function prepareRun(obj)
            prepareRun@manookinlab.protocols.ManookinLabStageProtocol(obj);
            obj.showFigure('symphonyui.builtin.figures.ResponseFigure', obj.rig.getDevice(obj.amp));

            obj.canvasSize = obj.rig.getDevice('Stage').getCanvasSize();

            % Convert from microns to pixels...
            obj.stixelSizePix = obj.rig.getDevice('Stage').um2pix(obj.stixelSize);
            obj.numChecksX = round(obj.canvasSize(1) / obj.stixelSizePix) + 2;
            obj.numChecksY = round(obj.canvasSize(2) / obj.stixelSizePix);
            obj.gridSizePix = obj.rig.getDevice('Stage').um2pix(obj.gridSize);
            obj.stepsPerStixel = max(round(obj.stixelSizePix / obj.gridSizePix), 1);
            obj.stixelShiftPix = round(obj.stixelSizePix / obj.stepsPerStixel);
            disp(['stixelSizePix: ', num2str(obj.stixelSizePix)]);
            disp(['gridSizePix: ', num2str(obj.gridSizePix)]);
            disp(['stepsPerStixel: ', num2str(obj.stepsPerStixel)]);
            disp(['stixelShiftPix: ', num2str(obj.stixelShiftPix)]);

            % Get the resources directory.
            obj.pkgDir = manookinlab.Package.getResourcePath();
            
            obj.currentStimSet = 'dovesFEMstims20160826.mat';

            % Load the current stimulus set.
            obj.im = load([obj.pkgDir,'\',obj.currentStimSet]);
            % Get the image and subject names.
            if length(unique(obj.stimulusIndices)) == 1
                obj.stimulusIndex = unique(obj.stimulusIndices);
                obj.getImageSubject();
            end
         end
        
         function getImageSubject(obj)
            % Get the image name.
            obj.imageName = obj.im.FEMdata(obj.stimulusIndex).ImageName;
            
            % Load the image.
            fileId = fopen([obj.pkgDir,'\doves\images\', obj.imageName],'rb','ieee-be');
            img = fread(fileId, [1536 1024], 'uint16');
            fclose(fileId);
            
            img = double(img');
            img = (img./max(img(:))); %rescale s.t. brightest point is maximum monitor level
            % Display min and max of img
            disp(['min img: ', num2str(min(obj.img(:)))]);
            disp(['max img: ', num2str(max(obj.img(:)))]);
            obj.backgroundIntensity = mean(img(:));%set the mean to the mean over the image
            % Calculate imgContrastReduction
            obj.imgContrastReduction = obj.backgroundIntensity * obj.noiseStdv;
            
            % Scale from (0,1) to (0-obj.imageContrastReduction, 1+obj.imageContrastReduction)
            obj.img = img * (1-2*obj.imgContrastReduction) + obj.imgContrastReduction;
            % Display min and max of img
            disp('Image contrast reduction');
            disp(['min img: ', num2str(min(obj.img(:)))]);
            disp(['max img: ', num2str(max(obj.img(:)))]);
            % obj.dovesMatrix = obj.img;
            obj.dovesMatrix = uint8(255 * obj.img);

            %get appropriate eye trajectories, at 200Hz
            if (obj.freezeFEMs) %freeze FEMs, hang on fixations
                obj.xTraj = obj.im.FEMdata(obj.stimulusIndex).frozenX;
                obj.yTraj = obj.im.FEMdata(obj.stimulusIndex).frozenY;
            else %full FEM trajectories during fixations
                obj.xTraj = obj.im.FEMdata(obj.stimulusIndex).eyeX;
                obj.yTraj = obj.im.FEMdata(obj.stimulusIndex).eyeY;
            end
            obj.timeTraj = (0:(length(obj.xTraj)-1)) ./ 200; %sec
           
            %need to make eye trajectories for PRESENTATION relative to the center of the image and
            %flip them across the x axis: to shift scene right, move
            %position left, same for y axis - but y axis definition is
            %flipped for DOVES data (uses MATLAB image convention) and
            %stage (uses positive Y UP/negative Y DOWN), so flips cancel in
            %Y direction
            obj.xTraj = -(obj.xTraj - 1536/2); %units=VH pixels
            obj.yTraj = (obj.yTraj - 1024/2);
            
            %also scale them to canvas pixels. 1 VH pixel = 1 arcmin = 3.3
            %um on monkey retina
            %canvasPix = (VHpix) * (um/VHpix)/(um/canvasPix)
            obj.xTraj = obj.xTraj .* 3.3/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');
            obj.yTraj = obj.yTraj .* 3.3/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel');

            % Round to nearest integer
            obj.xTraj = round(obj.xTraj);
            obj.yTraj = round(obj.yTraj);

            u_xTraj = unique(obj.xTraj);
            u_yTraj = unique(obj.yTraj);
            num_fix = length(u_xTraj);
            % If > numMaxFixations, keep evenly spaced fixations = numMaxFixations
            if num_fix > obj.numMaxFixations
                % Get the indices of the fixations.
                n_traj = size(obj.xTraj, 2);
                fix_indices = round(linspace(1, n_traj, obj.numMaxFixations));
                u_xTraj = obj.xTraj(fix_indices);
                u_yTraj = obj.yTraj(fix_indices);
                num_fix = length(u_xTraj);
            end
            obj.u_xTraj = u_xTraj;
            obj.u_yTraj = u_yTraj;
            obj.num_fixations = num_fix+1;
            disp(['Number of fixations: ', num2str(num_fix)]);

            % Compute all_fix_indices
            pre_frames = round(60 * (obj.preTime/1e3));
            stim_frames = round(60 * (obj.stimTime/1e3));
            tail_frames = round(60 * (obj.tailTime/1e3));
            all_fix_indices = 1:obj.num_fixations;
            n_frames_per_fix = ceil(stim_frames / obj.num_fixations);
            all_fix_indices = repelem(all_fix_indices, n_frames_per_fix);
            % Set max to num_fixations
            all_fix_indices(all_fix_indices > obj.num_fixations) = obj.num_fixations;
            % Set min to 1
            all_fix_indices(all_fix_indices < 1) = 1;
            % Prepend pre_frames of ones
            all_fix_indices = [ones(1, pre_frames), all_fix_indices];
            % Append tail_frames of ones
            all_fix_indices = [all_fix_indices, ones(1, tail_frames)];
            all_fix_indices = squeeze(all_fix_indices);
            obj.all_fix_indices = all_fix_indices;
            disp(['Number of frames per fixation: ', num2str(n_frames_per_fix)]);
            disp(['Fixation index size: ', num2str(size(all_fix_indices,2))]);
            
            % Load the subjectName for the image.
            f = load([obj.pkgDir,'\doves\fixations\', obj.imageName, '.mat']);
            obj.subjectName = f.subj_names_list{obj.im.FEMdata(obj.stimulusIndex).SubjectIndex};
            
            % Get the magnification factor. Exps were done with each pixel
            % = 1 arcmin == 1/60 degree; 200 um/degree...
            if obj.manualMagnification > 1
                obj.magnificationFactor = obj.manualMagnification;
            else
                obj.magnificationFactor = round(1/60*200/obj.rig.getDevice('Stage').getConfigurationSetting('micronsPerPixel'));
            end
        end
        
        function prepareEpoch(obj, epoch)
            fprintf(1, 'start prepare epoc\n');
            prepareEpoch@manookinlab.protocols.ManookinLabStageProtocol(obj, epoch);
            
            % Alternating seed for each epoch
            if obj.useFixedSeed
                obj.noiseSeed = 1;
            else
                obj.noiseSeed = randi(2^32 - 1);
            end
            
            % Toggle the seed usage for the next epoch
            obj.useFixedSeed = ~obj.useFixedSeed;

            if length(unique(obj.stimulusIndices)) > 1
                % Set the current stimulus trajectory.
                obj.stimulusIndex = obj.stimulusIndices(mod(obj.numEpochsCompleted,...
                    length(obj.stimulusIndices)) + 1);
                obj.getImageSubject();
            end

            % generate lineMatrix
            obj.lineMatrix = util.getCheckerboardProjectLines(obj.noiseSeed, obj.numChecksX, obj.preTime, obj.stimTime, obj.tailTime, obj.backgroundIntensity,...
                obj.frameDwell, obj.binaryNoise, 1, 0, 1, obj.pairedBars, 0,0);
            disp('Generated lineMatrix of size:')
            disp(size(obj.lineMatrix));
            

            % Set position stream for applying shifts
            obj.positionStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);
            
            % Add epoch parameters.
            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('useFixedSeed', obj.useFixedSeed);
            epoch.addParameter('stixelSize', obj.stixelSize);
            epoch.addParameter('gridSize', obj.gridSize);
            epoch.addParameter('numChecksX', obj.numChecksX);
            epoch.addParameter('numChecksY', obj.numChecksY);
            epoch.addParameter('stimulusIndex', obj.stimulusIndex);
            epoch.addParameter('imageName', obj.imageName);
            epoch.addParameter('subjectName', obj.subjectName);
            epoch.addParameter('imgContrastReduction', obj.imgContrastReduction);
            epoch.addParameter('noiseStdv', obj.noiseStdv);
            epoch.addParameter('backgroundIntensity', obj.backgroundIntensity);
            epoch.addParameter('num_fixations', obj.num_fixations);
            fprintf(1, 'end prepare epoch\n');
         end

         function p = createPresentation(obj)
            pre_frames = round(60 * (obj.preTime/1e3));
            stim_frames = round(60 * (obj.stimTime/1e3));
            tail_frames = round(60 * (obj.tailTime/1e3));

            fprintf(1, 'start create presentation\n');
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity

            %convert from microns to pixels...
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);

            %% DOVES scene
            doves = stage.builtin.stimuli.Image(obj.dovesMatrix);
            doves.size = [size(obj.dovesMatrix, 2), size(obj.dovesMatrix, 1)]*obj.magnificationFactor;
            p0 = obj.canvasSize/2;
            doves.position = p0;
            doves.setMinFunction(GL.NEAREST);
            doves.setMagFunction(GL.NEAREST);
            p.addStimulus(doves);

            % Apply eye trajectories
            dovesPosition = stage.builtin.controllers.PropertyController(doves, 'position',...
                @(state)getDovesPosition(obj.all_fix_indices(state.frame+1), obj.u_xTraj, obj.u_yTraj, p0));
            p.addController(dovesPosition); %add the controller
            function dovesPos = getDovesPosition(fix_index, u_xTraj, u_yTraj, p0)
                % Get the current position.
                if fix_index == 1
                    % Move totally off screen
                    dovesPos = p0*10;
                else
                    fix_index = fix_index - 1;
                    dovesPos = p0 + [u_yTraj(fix_index), u_xTraj(fix_index)];
                end
            end


            % Hide during pre & post
            dovesVisible = stage.builtin.controllers.PropertyController(doves, 'visible', ...
                @(state)state.frame > pre_frames && state.frame < (pre_frames + stim_frames));
            p.addController(dovesVisible);

            
            
            %% Noise scene
            obj.initMatrix = uint8(255.*(obj.backgroundIntensity .* ones(obj.numChecksY,obj.numChecksX)));
            board = stage.builtin.stimuli.Image(obj.initMatrix);
            board.size = [obj.numChecksX, obj.numChecksY]*obj.stixelSizePix;
            %board.size = obj.canvasSize;
            board.position = obj.canvasSize/2;
            board.opacity = obj.noiseStdv;
            board.setMinFunction(GL.NEAREST);
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);
            
            % state.frame is 0-indexed, so add 1 to get the first frame
            checkerboardController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewCheckerboard(state.frame+1, obj.lineMatrix(:, state.frame+1), ...
                                            pre_frames, stim_frames, obj.numChecksY));
            p.addController(checkerboardController); %add the controller
            
            if (obj.apertureDiameter > 0) %% Create aperture
                aperture = stage.builtin.stimuli.Rectangle();
                aperture.position = obj.canvasSize/2;
                aperture.color = obj.backgroundIntensity;
                aperture.size = [max(obj.canvasSize) max(obj.canvasSize)];
                mask = stage.core.Mask.createCircularAperture(apertureDiameterPix/max(obj.canvasSize), 1024); %circular aperture
                aperture.setMask(mask);
                p.addStimulus(aperture); %add aperture
            end
            
            % hide during pre & post
            % boardVisible = stage.builtin.controllers.PropertyController(board, 'visible', ...
            %     @(state)state.time >= obj.preTime * 1e-3 && state.time < (obj.preTime + obj.stimTime) * 1e-3);
            % p.addController(boardVisible); 
          
            

            function i = getNewCheckerboard(frame, line, pre_frames, stim_frames, num_checks_y)
                % CHECK ME
                if (frame >= pre_frames) && (frame < pre_frames + stim_frames)
                    i = repmat(line', num_checks_y, 1);
                    i = uint8(255 * i);
                else
                    i = obj.initMatrix;
                end
               
                
            end

            % Add position controller for jitter
            if obj.stepsPerStixel > 1
                % Get the current position.
                % Create the position controller.
                posController = stage.builtin.controllers.PropertyController(board, 'position',...
                    @(state)getNewPosition(obj, state.frame+1));
                p.addController(posController);
            end
            function p = getNewPosition(obj, frame)
                persistent pos
                if frame == 1
                    pos = obj.canvasSize/2;
                else
                    if mod(frame, obj.frameDwell) == 0
                        % Get the current position.
                        xPos = round(obj.positionStream.rand() * (obj.stepsPerStixel-1)) * obj.stixelShiftPix;
                        % Get the new position.
                        pos = [xPos, 0] + obj.canvasSize/2;
                    end
                end
                p = pos;
            end
            disp('At end of create presentation');
            
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
