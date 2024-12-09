function frameValues = getFlickeringBarsFrame(seed, baseMean, meanOffset, barWidth, contrast, unique_frames, repeat_frames, frameRate, swapIntervals, canvasSize, frameDwell, preTime, tailTime, noiseClass, orientationMode)
    %seed RNG
    noiseStream = RandStream('mt19937ar', 'Seed', seed);
    intervalStream = RandStream('mt19937ar', 'Seed', seed);
    noiseStreamRep = RandStream('mt19937ar', 'Seed', 1);
    intervalStreamRep = RandStream('mt19937ar', 'Seed', 1);

    %calculate left and right offsets
    leftOffset = -1*meanOffset;
    rightOffset = meanOffset;
    
    offset_vec_unique = zeros(2, unique_frames);
    offset_vec_rep = zeros(2, repeat_frames);
    
    origLeft = leftOffset;
    origRight = rightOffset;
    
    swaps = [];
    nIntervals = numel(swapIntervals);
    nextSwapFrame = 0;
    while nextSwapFrame < unique_frames
        choice = ceil((swapIntervals(ceil(intervalStream.rand*nIntervals))/1000)) * frameRate;
        nextSwapFrame = nextSwapFrame + choice;
        swaps(end+1) = nextSwapFrame;
    end
    rep_swaps = [];
    nextSwapFrame = 0;
    while nextSwapFrame < repeat_frames
        choice = ceil((swapIntervals(ceil(intervalStreamRep.rand*nIntervals))/1000)) * frameRate;
        nextSwapFrame = nextSwapFrame + choice;
        rep_swaps(end + 1) = nextSwapFrame;
    end

    offset_vec_unique(1, 1:swaps(1)) = leftOffset;
    offset_vec_unique(2, 1:swaps(1)) = rightOffset;
    for i = 2:numel(swaps)
        [leftOffset, rightOffset] = deal(rightOffset, leftOffset); % swap offsets
        if swaps(i) <= unique_frames
            offset_vec_unique(1, swaps(i-1):swaps(i)) = leftOffset;
            offset_vec_unique(2, swaps(i-1):swaps(i)) = rightOffset;
        else 
            offset_vec_unique(1, swaps(i-1):end) = leftOffset;
            offset_vec_unique(2, swaps(i-1):end) = rightOffset;
            break
        end
    end
    
    obj.leftOffset = origLeft;
            obj.rightOffset = origRight;

    offset_vec_rep(1, 1:rep_swaps(1)) = leftOffset;
    offset_vec_rep(2, 1:rep_swaps(1)) = rightOffset;
    for i = 2:numel(rep_swaps)
        [leftOffset, rightOffset] = deal(rightOffset, leftOffset); % swap offsets
        if rep_swaps(i) <= repeat_frames
            offset_vec_rep(1, rep_swaps(i-1):rep_swaps(i)) = leftOffset;
            offset_vec_rep(2, rep_swaps(i-1):rep_swaps(i)) = rightOffset;
        else
            offset_vec_rep(1, rep_swaps(i-1):end) = leftOffset;
            offset_vec_rep(2, rep_swaps(i-1):end) = rightOffset;
            break
        end
    end

    offset_vec = [offset_vec_unique offset_vec_rep];
    
    numFrames = unique_frames + repeat_frames;
    displayWidth = canvasSize(1)*2;
    displayHeight = canvasSize(2)*2;

    if strcmp(orientationMode, 'Vertical')
        numBars = ceil(displayWidth / barWidth);
    elseif strcmp(orientationMode, 'Horizontal')
        numBars = ceil(displayHeight / barWidth);
    end

    leftHalf = zeros(displayWidth, displayHeight);
    rightHalf = zeros(displayWidth, displayHeight);


    if strcmp(orientationMode, 'Vertical')
        leftHalf(:, 1:floor(displayWidth/2)) = 1;
        rightHalf(:, floor(displayWidth/2)+1:end) = 1;
    elseif strcmp(orientationMode, 'Horizontal')
        leftHalf(1:floor(displayHeight/2), :) = 1;
        rightHalf(floor(displayHeight/2)+1:end, :) = 1;
    end

    leftHalf = logical(leftHalf);
    rightHalf = logical(rightHalf);
    
    imgMat = zeros(canvasSize(2)*2, canvasSize(1)*2, numFrames);
    for f = 1:numFrames
        if mod(f, frameDwell) == 0
            if strcmp(noiseClass, 'Gaussian')
                if f < unique_frames
                    ct = 0.3*noiseStream.randn(1,ceil(numBars/2));
                else 
                    ct = 0.3*noiseStreamRep.randn(1,ceil(numBars/2));
                end
% 
                ct(ct<-1) = -1;
                ct(ct>1) = 1;
                variation = ct .* baseMean;

            elseif strcmp(noiseClass, 'Binary')

                if f < unique_frames
                    variation = contrast * (noiseStream.rand(1,ceil(numBars/2)) > 0.5) - (baseMean - meanOffset);
                else
                    variation = contrast * (noiseStreamRep.rand(1,ceil(numBars/2)) > 0.5) - (baseMean - meanOffset);
                end

            elseif strcmp(noiseClass, 'Uniform') %for some reason this condition doesn't work with noiseStream
                sz = [1 ceil(numBars/2)];
                if f < unique_frames

                    variation = noiseStream.unifrnd(-1*contrast*baseMean, contrast*baseMean, sz);
%                                 variation = unifrnd(-1*obj.contrast*obj.baseMean, obj.contrast*obj.baseMean, sz);
                else
                    variation = noiseStreamRep.unifrnd(-1*contrast*baseMean, contrast*baseMean, sz);

                end
            end

            luminances1 = baseMean + variation;
            luminances2 = baseMean - variation;

            allLum = [luminances1;luminances2];
            allLum = allLum(:)';

            if strcmp(orientationMode, 'Vertical')
                fullmat = repelem(allLum, canvasSize(2)*2, barWidth);
            else
                fullmat = repelem(allLum, barWidth, canvasSize(1)*2);
            end

            fullmat(leftHalf) = fullmat(leftHalf) + offset_vec(1, f);
            fullmat(rightHalf) = fullmat(rightHalf) + offset_vec(2, f);

            imgMat(:, :, f) = fullmat;
        else 
            imgMat(:, :, f) = obj.imgMat(:,:, f-1);
        end
    end
    
    num_preFrames = floor(preTime * 1e-3 * frameRate);
    num_tailFrames = floor(tailTime * 1e-3 * frameRate);
    
    preFrames = baseMean .* ones(canvasSize(2)*2, canvasSize(1)*2, num_preFrames);
    tailFrames = baseMean .* ones(canvasSize(2)*2, canvasSize(1)*2, num_tailFrames);
    
    frameValues = cat(3, preFrames, imgMat, tailFrames);

end