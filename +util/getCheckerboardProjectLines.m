function [lineMatrix, variation] = getCheckerboardProjectLines(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise,...
    noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars, noSplitField, contrastJumps)

    dimBackground = 0;
    noiseStream = RandStream('mt19937ar', 'Seed', seed);
    preFrames = round(60 * (preTime/1e3));
    stmFrames = round(60 * (stimTime/1e3));
    tailFrames = round(60 * (tailTime/1e3));
    
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

    if contrastJumps
        currentContrast = noiseStdv * contrastLevels(randi(contrastStream, [1, length(contrastLevels)]));
        contrastPointer = 1;
    else
        currentContrast=noiseStdv;
    end

    %% Calcuate background adjustment
    % maxVar is maximum possible variation around the backgroundIntensity, scaled down by backgroundRatio
    maxVar = min([backgroundIntensity, 1 - backgroundIntensity]) * backgroundRatio;
    % backgroundAdjust applies the context based on backgroundRatio.
    backgroundAdjust = min([backgroundIntensity, 1 - backgroundIntensity]) - maxVar;
    disp(backgroundAdjust)
    % eg-if backgroundIntensity = 0.7, backgroundRatio = 0.8, then
    % maxVar = 0.3 * 0.8 = 0.24 and backgroundAdjust = 0.3 - 0.24 = 0.06

    for frame = preFrames+1:preFrames+stmFrames

        if mod(frame-preFrames, backgroundFrameDwell) == 0
            if (dimBackground == 0)
                dimBackground = 1;
            else
                dimBackground = 0;
            end
        end
        % Check for contrast change
        if contrastJumps
            if contrastPointer <= length(contrastChangeFrames) && frame == contrastChangeFrames(contrastPointer)
                currentContrast = noiseStdv * contrastLevels(randi(contrastStream, [1, length(contrastLevels)]));
                contrastPointer = contrastPointer + 1;
            end
        end
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

        Indices1 = [1:floor(numChecksX/2)];
        Indices2 = [floor(numChecksX/2)+1:numChecksX];
        if dimBackground == 0
            if noSplitField == 1
                lineMatrix(Indices1, frame) = unedited_mat(Indices1, frame) - backgroundAdjust;
                lineMatrix(Indices2, frame) = unedited_mat(Indices2, frame) - backgroundAdjust;
            else
                lineMatrix(Indices1, frame) = unedited_mat(Indices1, frame) - backgroundAdjust;
                lineMatrix(Indices2, frame) = unedited_mat(Indices2, frame) + backgroundAdjust;
            end
        else
            if noSplitField == 1
                lineMatrix(Indices1, frame) = unedited_mat(Indices1, frame) + backgroundAdjust;
                lineMatrix(Indices2, frame) = unedited_mat(Indices2, frame) + backgroundAdjust;
            else
                lineMatrix(Indices1, frame) = unedited_mat(Indices1, frame) + backgroundAdjust;
                lineMatrix(Indices2, frame) = unedited_mat(Indices2, frame) - backgroundAdjust;
            end
        end

%         % For paired bars, make every 2nd bar the opposite of the previous one.
%         % eg-[0.9,0.9] becomes [0.9,0.1]
%         if pairedBars == 1
%             Indices = [1:floor(numChecksX/2)]*2;
%             lineMatrix(Indices, frame) = -(lineMatrix(Indices-1, frame)-backgroundIntensity)+ ...
%                 backgroundIntensity;
%         end
% 
%         if mod(frame-preFrames, backgroundFrameDwell) == 0
%             if (dimBackground == 0)
%                 dimBackground = 1;
%             else
%                 dimBackground = 0;
%             end
%         end
%         Indices1 = [1:floor(numChecksX/2)];
%         Indices2 = [floor(numChecksX/2)+1:numChecksX];
%         if dimBackground == 0
%             if noSplitField == 1
%                 lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) - backgroundAdjust;
%                 lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) - backgroundAdjust;
%             else
%                 lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) - backgroundAdjust;
%                 lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) + backgroundAdjust;
%             end
%         else
%             if noSplitField == 1
%                 lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) + backgroundAdjust;
%                 lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) + backgroundAdjust;
%             else
%                 lineMatrix(Indices1, frame) = lineMatrix(Indices1, frame) + backgroundAdjust;
%                 lineMatrix(Indices2, frame) = lineMatrix(Indices2, frame) - backgroundAdjust;
%             end
%         end
    end
    for frame = preFrames + stmFrames + 1:preFrames + stmFrames + tailFrames
        lineMatrix(:, frame) = backgroundIntensity;
    end
end
