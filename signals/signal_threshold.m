function sigTT = signal_threshold(xTT, threshold)
%SIGNAL_THRESHOLD Generic threshold signal.
%   sig = x > threshold

arguments
    xTT timetable
    threshold (1,1) double
end

sigTT = array2timetable(double(xTT.Variables > threshold), 'RowTimes', xTT.Time, 'VariableNames', xTT.Properties.VariableNames);

end
