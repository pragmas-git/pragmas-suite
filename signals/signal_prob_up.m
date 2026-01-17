function sigTT = signal_prob_up(probUpTT, cfg)
%SIGNAL_PROB_UP Long signal when P(r>0) exceeds threshold.

arguments
    probUpTT timetable
    cfg (1,1) struct
end

thr = cfg.signals.probUpThreshold;
S = probUpTT.Variables > thr;
sigTT = array2timetable(double(S), 'RowTimes', probUpTT.Time, 'VariableNames', probUpTT.Properties.VariableNames);

end
