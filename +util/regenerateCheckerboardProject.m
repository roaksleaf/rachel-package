function [stimulus, line_mat, contrast_mat] = regenerateCheckerboardProject(b_noise_only, exp_name, preTime, tailTime, stimTime, noiseSeeds, numChecksXs, ...
    backgroundIntensity, frameDwell, binaryNoise, noiseStdv, backgroundRatios, backgroundFrameDwells, pairedBars, noSplitField,...
    contrastJumps, numChecksYs)
    num_epochs = length(noiseSeeds);
    
    x = numChecksXs(1);
    y = numChecksYs(1);
    
    pre_frames = round(60 * (preTime/1e3));
    tail_frames = round(60 * (tailTime/1e3));
    stim_frames = round(60 * (stimTime/1e3));
    num_frames = pre_frames + stim_frames + tail_frames;
    
    if ~b_noise_only
        stimulus = zeros(y, x, num_frames, num_epochs);
    end
    line_mat = zeros(x, num_frames, num_epochs);
    contrast_mat = zeros(num_frames, num_epochs);

    for i=1:num_epochs
        seed = noiseSeeds(i);
        numChecksX = numChecksXs(i);
        backgroundRatio = backgroundRatios(i);
        backgroundFrameDwell = backgroundFrameDwells(i);
    
        numChecksY = numChecksYs(i);
        if exp_name > 20250806
            [line_mat(:,:, i), contrast_mat(:,i)] = util.getCheckerboardProjectLines(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
               noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars, noSplitField, contrastJumps);
        elseif (20250527 < exp_name) && (exp_name <= 20250806)
                line_mat(:,:, i) = archive.getCheckerboardProjectLines_Aug62025(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
               noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars, noSplitField, contrastJumps);
                contrast_mat = 0;
        elseif (20250514 < exp_name) && (exp_name <= 20250527)
                line_mat(:,:, i) = archive.getCheckerboardProjectLines_May272025(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
               noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars, noSplitField, contrastJumps);
                contrast_mat = 0;
        elseif exp_name <= 20250514
                line_mat(:,:, i) = archive.getCheckerboardProjectLines_May272025(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
               noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars, noSplitField, contrastJumps);
                contrast_mat = 0;
        end
        
        if b_noise_only
            for ii=1:num_frames
                line = line_mat(:, ii, i);
                frame = uint8(255 * repmat(line', numChecksY, 1));
                stimulus(:, :, ii, i) = frame;
            end
        else
            stimulus = NaN;
        end
    
    end
end
