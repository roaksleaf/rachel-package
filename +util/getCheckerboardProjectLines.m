function [lineMatrix, variation] = getCheckerboardProjectLines(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise,...
    noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars, noSplitField, contrastJumps)

    dimBackground = 0;
    noiseStream = RandStream('mt19937ar', 'Seed', seed);
    preFrames = round(60 * (preTime/1e3));
    stmFrames = round(60 * (stimTime/1e3));
    tailFrames = round(60 * (tailTime/1e3));
    
    lineMatrix = zeros(numChecksX,preFrames+stmFrames+tailFrames);
    for frame = 1:preFrames + stmFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
    Indices = [1:floor(numChecksX/2)]*2;

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

    currentContrast = noiseStdv * contrastLevels(randi(contrastStream, [1, length(contrastLevels)]));
    contrastPointer = 1;

    for frame = preFrames+1:preFrames+stmFrames
        % Check for contrast change
        if contrastPointer <= length(contrastChangeFrames) && frame == contrastChangeFrames(contrastPointer)
            currentContrast = noiseStdv * contrastLevels(randi(contrastStream, [1, length(contrastLevels)]));
            contrastPointer = contrastPointer + 1;
        end
        if mod(frame-preFrames, frameDwell) == 0 %noise update
            if binaryNoise == 1
                maxVar = (1-backgroundRatio) - backgroundIntensity; %changed from 0.8
                variation = 2 * maxVar * ...
                    (noiseStream.rand(numChecksX, 1) > 0.5) - (maxVar);
                lineMatrix(:, frame) = 0.5 + variation*currentContrast;
            else
                lineMatrix(:, frame) = backgroundIntensity + ...
                    currentContrast * backgroundIntensity * ...
                    noiseStream.randn(numChecksX, 1);
            end
        else
            lineMatrix(:, frame) = lineMatrix(:, frame-1);
        end

        if pairedBars == 1
            lineMatrix(Indices, frame) = -(lineMatrix(Indices-1, frame)-backgroundIntensity)+ ...
                backgroundIntensity;
        end

        if mod(frame-preFrames, backgroundFrameDwell) == 0
            if (dimBackground == 0)
                dimBackground = 1;
            else
                dimBackground = 0;
            end
        end
        Indices1 = [1:floor(numChecksX/2)];
        Indices2 = [floor(numChecksX/2)+1:numChecksX];
        if dimBackground == 0
            if noSplitField == 1
                lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) - backgroundRatio;
                lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) - backgroundRatio;
            else
                lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) - backgroundRatio;
                lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) + backgroundRatio;
            end
        else
            if noSplitField == 1
                lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) + backgroundRatio;
                lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) + backgroundRatio;
            else
                lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) + backgroundRatio;
                lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) - backgroundRatio;
            end
        end
    end
    for frame = preFrames + stmFrames + 1:preFrames + stmFrames + tailFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
end
