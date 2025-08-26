function [lineMatrix, contrast_trace] = getVariableIntervalLines(seed, numChecksX, preTime, preInterval, tailInterval, tailTime, backgroundIntensity, frameDwell, binaryNoise,...
    noiseStdv, backgroundRatio, pairedBars, contrastJumps, increment)

    dimBackground = 0;
    noiseStream = RandStream('mt19937ar', 'Seed', seed);
    preFrames = round(60 * (preTime/1e3));
    tailFrames = round(60 * (tailTime/1e3));
    preIntervalFrames = round(60 * (preInterval/1e3));
    tailIntervalFrames = round(60 * (tailInterval/1e3));
    stmFrames = preIntervalFrames+tailIntervalFrames;
    
    lineMatrix = zeros(numChecksX,preFrames+stmFrames+tailFrames);
    unedited_mat = zeros(numChecksX,preFrames+stmFrames+tailFrames);
    for frame = 1:preFrames + stmFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
    

    % Random contrast switching setup
    minInterval = 30;
    maxInterval = 120;

    contrastStream = RandStream('mt19937ar', 'Seed', seed + 1); % different from noiseStream
    if contrastJumps == 1
        contrastLevels = [0.2, 0.5, 0.7, 1.0]; % example set of contrast multipliers
    else
        contrastLevels = [1.0,1.0]; 
    end

    % Build contrast change frames
    contrastChangeFrames = [];
    nextContrastFrame = preFrames + randi(contrastStream, [minInterval, maxInterval]);
    while nextContrastFrame <= preFrames + stmFrames
        contrastChangeFrames = [contrastChangeFrames, nextContrastFrame];
        nextContrastFrame = nextContrastFrame + randi(contrastStream, [minInterval, maxInterval]);
    end

    % Initialize contrast
    contrast_trace = zeros(1,preFrames+stmFrames+tailFrames);

    if contrastJumps
        currentContrast = noiseStdv * contrastLevels(randi(contrastStream, [1, length(contrastLevels)]));
        contrastPointer = 1;
    else
        currentContrast=noiseStdv;
    end

    % Calcuate background adjustment
    % maxVar is maximum possible variation around the backgroundIntensity, scaled down by backgroundRatio
    maxVar = min([backgroundIntensity, 1 - backgroundIntensity]) * backgroundRatio;
    % backgroundAdjust applies the context based on backgroundRatio.
    backgroundAdjust = min([backgroundIntensity, 1 - backgroundIntensity]) - maxVar;
    disp(backgroundAdjust)
    % eg-if backgroundIntensity = 0.7, backgroundRatio = 0.8, then
    % maxVar = 0.3 * 0.8 = 0.24 and backgroundAdjust = 0.3 - 0.24 = 0.06

    for frame = preFrames+1:preFrames+stmFrames

        % Check for contrast change
        if contrastJumps
            if contrastPointer <= length(contrastChangeFrames) && frame == contrastChangeFrames(contrastPointer)
                currentContrast = noiseStdv * contrastLevels(randi(contrastStream, [1, length(contrastLevels)]));
                contrastPointer = contrastPointer + 1;
            end
        end

        contrast_trace(1,frame) = currentContrast;

        if mod(frame-preFrames, frameDwell) == 0 %noise update
            if binaryNoise == 1
                variation = 2 * maxVar * ...
                    (noiseStream.rand(numChecksX, 1) > 0.5) - (maxVar);
                lineMatrix(:, frame) = backgroundIntensity + variation*currentContrast;
                unedited_mat(:,frame) = lineMatrix(:,frame);
            else
                lineMatrix(:, frame) = backgroundIntensity + ...
                    currentContrast * backgroundIntensity * ...
                    noiseStream.randn(numChecksX, 1);
                unedited_mat(:,frame) = lineMatrix(:,frame);
            end
            
            % For paired bars, make every 2nd bar the opposite of the previous one.
            % eg-[0.9,0.9] becomes [0.9,0.1]
            if pairedBars == 1
                Indices = [1:floor(numChecksX/2)]*2;
                unedited_mat(Indices, frame) = -(unedited_mat(Indices-1, frame)-backgroundIntensity)+ ...
                    backgroundIntensity;
            end
        else
            unedited_mat(:, frame) = unedited_mat(:, frame-1);
        end

    end
    
    for frame=preFrames:preFrames+preIntervalFrames
        if increment
            lineMatrix(:, frame) = unedited_mat(:, frame) - backgroundAdjust;
        else
            lineMatrix(:, frame) = unedited_mat(:, frame) + backgroundAdjust;
        end
    end
    
    for frame=preFrames+preIntervalFrames+1:preFrames+preIntervalFrames+1+tailIntervalFrames
        if increment
            lineMatrix(:, frame) = unedited_mat(:, frame) + backgroundAdjust;
        else
            lineMatrix(:, frame) = unedited_mat(:, frame) - backgroundAdjust;
        end
    end     
    
    for frame = preFrames + stmFrames + 1:preFrames + stmFrames + tailFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
end