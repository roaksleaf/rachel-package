function [lineMatrix] = getVariableMeanBars(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise,...
    noiseStdv, lowMean, highMean, backgroundFrameDwell, pairedBars, startDim, trackEnd, trackFrames)

    dimBackground = startDim;
    if startDim
        targetMean = lowMean;
    else
        targetMean = highMean;
    end
    noiseStream = RandStream('mt19937ar', 'Seed', seed);
    preFrames = round(60 * (preTime/1e3));
    stmFrames = round(60 * (stimTime/1e3));
    tailFrames = round(60 * (tailTime/1e3));
    
    lineMatrix = zeros(numChecksX,preFrames+stmFrames+tailFrames);
    for frame = 1:preFrames + stmFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
    
    if trackEnd
        targetFrames = preFrames+stmFrames-trackFrames;
    else
        targetFrames = preFrames+stmFrames;
    end

    for frame = preFrames+1:preFrames+stmFrames
        if mod(frame-preFrames, backgroundFrameDwell) == 0
            if frame <= targetFrames
                if dimBackground
                    dimBackground = false;
                    targetMean = highMean;
                else
                    dimBackground = true;
                    targetMean = lowMean;
                end
            end
        end

        if (mod(frame-preFrames+1, frameDwell) == 0)  || (frame==preFrames+1) %noise update
            if binaryNoise == 1
                lineMatrix(:,frame) = targetMean * (1 + noiseStdv * (2*(rand(numChecksX,1) > 0.5) - 1));
            else
                lineMatrix(:, frame) = targetMean + (noiseStream.randn(numChecksX, 1) * targetMean * noiseStdv);
            end
            
            % For paired bars, make every 2nd bar the opposite of the previous one.
            % eg-[0.9,0.9] becomes [0.9,0.1]
            if pairedBars == 1
                Indices = [1:floor(numChecksX/2)]*2;
                lineMatrix(Indices, frame) = -(lineMatrix(Indices-1, frame)-targetMean)+ ...
                    targetMean;
            end
        else
            lineMatrix(:, frame) = lineMatrix(:, frame-1);
        end
    end

    for frame = preFrames + stmFrames + 1:preFrames + stmFrames + tailFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
end
