function lineMatrix = getBars(seed, numChecksX, preTime, stimTime, tailTime, ...
    backgroundIntensity, frameDwell, binaryNoise, noiseStdv, noiseMean, pairedBars)
%GETVARIABLEMEANBARS  Frame-by-frame matrix of flickering vertical bars.
%
%   lineMatrix = getVariableMeanBars(seed, numChecksX, preTime, stimTime, tailTime, ...
%       backgroundIntensity, frameDwell, binaryNoise, noiseStdv, noiseMean, pairedBars)
%
%   Returns an [numChecksX x nFrames] matrix (60 Hz frame basis) where each column
%   is one display frame and each row is one vertical bar. During the stimulus the
%   bars flicker around a CONSTANT mean (noiseMean) with contrast noiseStdv; the
%   pre- and tail-time frames are held at backgroundIntensity. All luminance / mean
%   changes are handled separately by the projector-gain device, so the mean is
%   fixed here.
%
%   Pass preTime = tailTime = 0 to get just a bare stimulus segment (useful for
%   tiling a short repeated segment).
%
%   Inputs
%     seed                - RNG seed (mt19937ar) for reproducible Gaussian noise
%     numChecksX          - number of vertical bars
%     preTime/stimTime/tailTime - segment durations (ms)
%     backgroundIntensity - intensity held during pre/tail (0-1)
%     frameDwell          - frames between noise updates
%     binaryNoise         - true: binary contrast; false: Gaussian
%     noiseStdv           - noise contrast
%     noiseMean           - mean intensity of the flicker (0-1)
%     pairedBars          - true: every 2nd bar mirrors its neighbour about the mean

    noiseStream = RandStream('mt19937ar', 'Seed', seed);

    preFrames  = round(60 * (preTime  / 1e3));
    stimFrames = round(60 * (stimTime / 1e3));
    tailFrames = round(60 * (tailTime / 1e3));

    % Pre/tail frames are already at background; stimulus frames get overwritten.
    lineMatrix = backgroundIntensity * ones(numChecksX, preFrames + stimFrames + tailFrames);

    evenBars = (1:floor(numChecksX/2)) * 2;   % paired-bar partner indices

    for frame = preFrames + 1 : preFrames + stimFrames
        isUpdate = (mod(frame - preFrames + 1, frameDwell) == 0) || (frame == preFrames + 1);

        if ~isUpdate
            lineMatrix(:, frame) = lineMatrix(:, frame - 1);   % hold previous frame
            continue
        end

        if binaryNoise
            lineMatrix(:, frame) = noiseMean * (1 + noiseStdv * (2 * (rand(numChecksX, 1) > 0.5) - 1));
        else
            lineMatrix(:, frame) = noiseMean + noiseStream.randn(numChecksX, 1) * noiseMean * noiseStdv;
        end

        % Paired bars: every 2nd bar is the mirror of its neighbour about the mean,
        % e.g. [0.9 0.9] -> [0.9 0.1].
        if pairedBars
            lineMatrix(evenBars, frame) = noiseMean - (lineMatrix(evenBars - 1, frame) - noiseMean);
        end
    end
end