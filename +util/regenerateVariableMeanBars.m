function [stimulus, line_mat] = regenerateVariableMeanBars(b_lines_only, exp_name, noiseSeeds, numChecksXs, preTime, stimTime, tailTime, ...
    backgroundIntensity, frameDwell, binaryNoise, noiseType, noiseStdv, lowMeans, highMeans, backgroundFrameDwells, pairedBars, startDims, trackEnds, trackFrames,...
    numChecksYs)
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

    for i=1:num_epochs
        seed = noiseSeeds(i);
        numChecksX = numChecksXs(i);
        backgroundFrameDwell = backgroundFrameDwells(i);
        lowMean = lowMeans(i);
        highMean = highMeans(i);
        startDim = startDims(i);
        trackEnd = trackEnds(i);
    
        numChecksY = numChecksYs(i);
        % Before 20261012 use archive regen function
        if exp_name < 20261012
            disp(['Using archived protocol for ', num2str(exp_name), ' as before 20261012'])
            line_mat(:,:, i) = util.getVariableMeanBars20261012(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
            noiseType, noiseStdv, lowMean, highMean, backgroundFrameDwell, pairedBars, startDim, trackEnd, trackFrames);
      
        else
            disp(['Using default protocol for ', num2str(exp_name), ' for centered uniform dist'])
            line_mat(:,:, i) = util.getVariableMeanBars(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
            noiseType, noiseStdv, lowMean, highMean, backgroundFrameDwell, pairedBars, startDim, trackEnd, trackFrames);
        end
        
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
