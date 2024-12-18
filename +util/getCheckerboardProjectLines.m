function [lineMatrix, variation] = getCheckerboardProjectLines(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise,...
    noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars)

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
    for frame = preFrames+1:preFrames+stmFrames
        if mod(frame-preFrames, frameDwell) == 0 %noise update
            if binaryNoise == 1
                maxVar = (1-backgroundRatio) - backgroundIntensity; %changed from 0.8
                variation = 2 * maxVar * ...
                    (noiseStream.rand(numChecksX, 1) > 0.5) - (maxVar);
                lineMatrix(:, frame) = 0.5 + variation;
            else
                lineMatrix(:, frame) = backgroundIntensity + ...
                    noiseStdv * backgroundIntensity * ...
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
        Indices2 = [floor(numChecksX/2):numChecksX];
        if dimBackground == 0
            lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) - backgroundRatio;
            lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) + backgroundRatio;
        else
            lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) + backgroundRatio;
            lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) - backgroundRatio;
        end
    end
    for frame = preFrames + stmFrames + 1:preFrames + stmFrames + tailFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
end
