% Plays 1D noise + doves fixation image, for many fixations of the image.
classdef DovesPerturbation < manookinlab.protocols.ManookinLabStageProtocol
    
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
        manualMagnification = 0         % Override DOVES magnification by setting this >1
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
            obj.numChecksX = round(obj.canvasSize(1) / obj.stixelSizePix);
            obj.gridSizePix = obj.rig.getDevice('Stage').um2pix(obj.gridSize);
            obj.stepsPerStixel = max(round(obj.stixelSizePix / obj.gridSizePix), 1);
            obj.stixelShiftPix = round(obj.stixelSizePix / obj.stepsPerStixel);

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

         function computeDovesMovieMatrix(obj)
            % Unique xTraj, yTraj
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

            disp(['Number of fixations: ', num2str(num_fix)]);
            scene_size = [size(obj.dovesMatrix,1) size(obj.dovesMatrix,2)]*obj.magnificationFactor;
            % Upscale dovesMatrix to scene size
            obj.dovesMatrix = imresize(obj.dovesMatrix, scene_size, 'bilinear');
            screen_size = obj.rig.getDevice('Stage').getCanvasSize();
            p0 = scene_size/2;
            y_vals = -screen_size(2)/2+1:screen_size(2)/2;
            x_vals = -screen_size(1)/2+1:screen_size(1)/2;
            dovesMovieMatrix = zeros(num_fix+1, screen_size(1), screen_size(2));
            % First frame is background intensity.
            dovesMovieMatrix(1,:,:) = obj.backgroundIntensity * ones(screen_size);
            for i = 1:num_fix
                % Get the current fixation.
                xFix = -u_xTraj(i);
                yFix = u_yTraj(i);
                p = p0 + [yFix, xFix];
                x_idx = round(p(2) + x_vals);
                y_idx = round(p(1) + y_vals);
                x_good = (x_idx > 0) & (x_idx <= scene_size(2));
                y_good = (y_idx > 0) & (y_idx <= scene_size(1));
                % Get the image matrix.
                dovesMovieMatrix(i+1, x_good, y_good) = obj.dovesMatrix(y_idx(y_good), x_idx(x_good))';
            end
            obj.dovesMovieMatrix = permute(dovesMovieMatrix, [1,3,2]);
            obj.num_fixations = num_fix+1;
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
            obj.dovesMatrix = obj.img;

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
            
            % Load the fixations for the image.
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
            
            % Generate dovesMovieMatrix
            obj.computeDovesMovieMatrix();
            disp('Generate dovesMovieMatrix');

            

            % generate lineMatrix
            % disp('pre lineMatcall')
            obj.lineMatrix = util.getCheckerboardProjectLines(obj.noiseSeed, obj.numChecksX, obj.preTime, obj.stimTime, obj.tailTime, obj.backgroundIntensity,...
                obj.frameDwell, obj.binaryNoise, 1, 0, 1, obj.pairedBars);
            disp('Generated lineMatrix of size:')
            disp(size(obj.lineMatrix));
            % Upscale lineMatrix from (numChecksX, frames) to (canvasSize(1), frames)
            obj.lineMatrix = imresize(obj.lineMatrix, [obj.canvasSize(1), size(obj.lineMatrix, 2)], 'nearest');
            disp('post upscale. Line matrix size:')
            disp(size(obj.lineMatrix));
            % Rescale lineMatrix from (0,1) to (-noiseStdv,noiseStdv)*backgroundIntensity
            obj.lineMatrix = obj.lineMatrix * (2*obj.noiseStdv) - obj.noiseStdv;
            obj.lineMatrix = obj.lineMatrix * obj.backgroundIntensity;

            % Set position stream and apply shifts
            obj.positionStream = RandStream('mt19937ar', 'Seed', obj.noiseSeed);
            n_frames = size(obj.lineMatrix, 2);
            % Generate shifts of length frames
            x_shifts = obj.stixelShiftPix * round((obj.stepsPerStixel-1) * (obj.positionStream.rand(1, n_frames)));
            % Apply x_shifts to lineMatrix
            for frame = 1:n_frames
                obj.lineMatrix(:, frame) = circshift(obj.lineMatrix(:, frame), x_shifts(frame));
            end
            
            % Add epoch parameters.
            epoch.addParameter('noiseSeed', obj.noiseSeed);
            epoch.addParameter('useFixedSeed', obj.useFixedSeed);
            epoch.addParameter('stixelSize', obj.stixelSize);
            epoch.addParameter('gridSize', obj.gridSize);
            epoch.addParameter('numChecksX', obj.numChecksX);
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
            fprintf(1, 'start create presentation\n');
            p = stage.core.Presentation((obj.preTime + obj.stimTime + obj.tailTime) * 1e-3); %create presentation of specified duration
            p.setBackgroundColor(obj.backgroundIntensity); % Set background intensity

            %convert from microns to pixels...
            apertureDiameterPix = obj.rig.getDevice('Stage').um2pix(obj.apertureDiameter);

            % Create checkerboard
            obj.initMatrix = uint8(255.*(obj.backgroundIntensity .* ones(obj.canvasSize(2),obj.canvasSize(1))));
            board = stage.builtin.stimuli.Image(obj.initMatrix);
            board.size = obj.canvasSize;
            board.position = obj.canvasSize/2;
            board.setMinFunction(GL.NEAREST); %don't interpolate to scale up board
            board.setMagFunction(GL.NEAREST);
            p.addStimulus(board);


            pre_frames = round(60 * (obj.preTime/1e3));
            stim_frames = round(60 * (obj.stimTime/1e3));
            % state.frame is 0-indexed, so add 1 to get the first frame
            checkerboardController = stage.builtin.controllers.PropertyController(board, 'imageMatrix',...
                @(state)getNewCheckerboard(state.frame+1, obj.lineMatrix(:, state.frame+1), ...
                                            obj.dovesMovieMatrix(obj.all_fix_indices(state.frame+1), :, :), ...
                                            pre_frames, stim_frames, obj.canvasSize(2)));
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
          
            disp('post board visible')

            function i = getNewCheckerboard(frame, line, doves_frame, pre_frames, stim_frames, canvas_size_y)
                % CHECK ME
                if (frame >= pre_frames) && (frame < pre_frames + stim_frames)
%                     disp(['frame: ', num2str(frame-pre_frames+1)]);
                    % disp(['Number of frames per fixation: ', num2str(n_frames_per_fix)]);
                    % fixation_index = obj.all_fix_indices(frame - pre_frames+1);
%                     disp(['Fixation index size: ', num2str(size(all_fix_indices,2))]);
%                     disp(['Fixation_index: ', num2str(fixation_index)]);
                    
                    % line = obj.lineMatrix(:, frame);
                    % i = repmat(line', canvas_size_y, 1);
                    i = line' * ones(1, canvas_size_y);
                    % if fixation_index > obj.num_fixations
                    %     fixation_index = obj.num_fixations;
                    % end
                    % if fixation_index >= 1
                    %     doves_frame = obj.dovesMovieMatrix(fixation_index, :, :);
                    %     i = i + squeeze(doves_frame);
                    % end
                    i = i + squeeze(doves_frame);
                    i = uint8(255 * i);
%                     disp(['Min i: ', num2str(min(i(:)))]);
%                     disp(['Max i: ', num2str(max(i(:)))]);
                else
                    i = obj.initMatrix;
                end
               
                
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
