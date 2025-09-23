function [stimulus, line_mat] = regenerateVariableMeanBars(b_lines_only, exp_name, preTime, tailTime, stimTime, noiseSeeds, numChecksXs, ...
    backgroundIntensity, frameDwell, binaryNoise, noiseStdv, backgroundRatios, backgroundFrameDwells, pairedBars, noSplitField,...
    contrastJumps, numChecksYs)
    num_epochs = length(noiseSeeds);
    
    x = numChecksXs(1);
    y = numChecksYs(1);
    
    pre_frames = round(60 * (preTime/1e3));
    tail_frames = round(60 * (tailTime/1e3));
    stim_frames = round(60 * (stimTime/1e3));
    num_frames = pre_frames + stim_frames + tail_frames;
    
    if ~b_lines_only
        stimulus = zeros(y, x, num_frames, num_epochs);
    end
    line_mat = zeros(x, num_frames, num_epochs);
    contrast_mat = zeros(num_frames, num_epochs);

    for i=1:num_epochs
        seed = noiseSeeds(i);
        numChecksX = numChecksXs(i);
        backgroundFrameDwell = backgroundFrameDwells(i);
    
        numChecksY = numChecksYs(i);
        line_mat(:,:, i) = util.getVariableMeanBars(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
           noiseStdv, lowMean, highMean, backgroundFrameDwell, pairedBars;
      
        if ~b_lines_only
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
