function gain_trace = regenerateProjectorGain(preTime, stimTime, tailTime, stepDurations_arr, gainValues_arr, upperLimit, lowerLimit, sampleRate)

    n_epochs = length(stepDurations_arr);
    
    duration = preTime + stimTime + tailTime;

    gain_trace = zeros(n_epochs, duration);

    for i = 1:n_epochs  
        stepDur_epoch = cell2mat(stepDurations_arr(i));
        gainVal_epoch = cell2mat(gainValues_arr(i));
        gain_trace(i,:) = addGainValues(preTime, stimTime, tailTime, stepDur_epoch, gainVal_epoch, upperLimit, lowerLimit, sampleRate);
    end

        function data = addGainValues(preTime, stimTime, tailTime, stepDurations, gainValues, upperLimit, lowerLimit, sampleRate)
            timeToPts = @(t)(round(t / 1e3 * sampleRate));
        
            prePts = timeToPts(preTime);
            stimPts = timeToPts(stimTime);
            tailPts = timeToPts(tailTime);
            stepPts = timeToPts(stepDurations); 
        
            stepPts = round(stepPts);
            
            % Set the gain values.
            data = ones(1, prePts + stimPts + tailPts);
            for ii = 1 : length(gainValues)
                if ii == 1
                    idx = 1 : stepPts(1);
                else
                    idx = sum(stepPts(1:ii-1)) + (1:stepPts(ii)); 
                end
                data(idx) = gainValues( ii );
            end
        
            data = data(1 : prePts + stimPts + tailPts);
            % Force the gain device to go high at beginning and end for the frame monitor.
            data(1 : round(33/1000.0*sampleRate)) = upperLimit;
            data(end)=upperLimit;
            
            % Clip signal to upper and lower limit.
            data(data > upperLimit) = upperLimit;
            data(data < lowerLimit) = lowerLimit;
        end

end