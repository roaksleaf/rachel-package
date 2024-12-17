function i = getNewCheckerboard(frame, lineMatrix, numChecksY)
    line = lineMatrix(:, frame);
    i = uint8(255 * repmat(line', numChecksY, 1));
    size(i)
end