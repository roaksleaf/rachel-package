%% regenerate mean jump noise stimulus from data 005 20250527C

stim_params = struct(load('/Users/racheloaks-leaf/Desktop/20250527C/stimParams_meanjump_data005_20250527C.mat'));

addpath('/Users/racheloaks-leaf/Desktop/rachel-package/')
addpath('/Users/racheloaks-leaf/Desktop/get_new_checkerboard_archive/')

%%
num_epochs = length(stim_params.stim_struct.noiseSeed);

num_frames = 1260;
x = stim_params.stim_struct.numChecksX(1);
y = stim_params.stim_struct.numChecksY(1);

stimulus = zeros(y, x, num_frames, num_epochs);


for i=1:num_epochs
    seed = stim_params.stim_struct.noiseSeed(i);
    numChecksX = stim_params.stim_struct.numChecksX(i);
    preTime = stim_params.stim_struct.preTime(i);
    stimTime = stim_params.stim_struct.stimTime(i);
    tailTime = stim_params.stim_struct.tailTime(i);
    backgroundIntensity = stim_params.stim_struct.backgroundIntensity(i);
    frameDwell = stim_params.stim_struct.frameDwell(i);
    binaryNoise = stim_params.stim_struct.binaryNoise(i);
    noiseStdv = stim_params.stim_struct.noiseStdv(i);
    backgroundRatio = stim_params.stim_struct.backgroundRatio(i);
    backgroundFrameDwell = stim_params.stim_struct.backgroundFrameDwell(i);
    pairedBars = stim_params.stim_struct.pairedBars(i);
    noSplitField = stim_params.stim_struct.noSplitField(i);

    numChecksY = stim_params.stim_struct.numChecksY(i);

    line_mat = getCheckerboardProjectLines_May272025(seed, numChecksX, preTime, stimTime, tailTime, backgroundIntensity, frameDwell, binaryNoise, ...
       noiseStdv, backgroundRatio, backgroundFrameDwell, pairedBars, noSplitField);

    num_frames = size(line_mat, 2);

    for ii=1:num_frames
        line = line_mat(:, ii);
        frame = uint8(255 * repmat(line', numChecksY, 1));
        stimulus(:, :, ii, i) = frame;
    end

end
%%
save('/Users/racheloaks-leaf/Desktop/20250527C/stimulus005_20250527C.mat', 'stimulus', '-v7.3')