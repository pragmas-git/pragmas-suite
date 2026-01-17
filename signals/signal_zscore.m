function sigTT = signal_zscore(retTT, muTT, sigmaTT, cfg)
%SIGNAL_ZSCORE Signal based on forecast z-score.
%   z_t = (r_t - mu_t)/sigma_t
%   Long if z < -thr (mean reversion example), short if allowed and z > thr.

arguments
    retTT timetable
    muTT timetable
    sigmaTT timetable
    cfg (1,1) struct
end

thr = cfg.signals.zscoreThreshold;

z = (retTT.Variables - muTT.Variables) ./ sigmaTT.Variables;

if cfg.portfolio.allowShort
    s = zeros(size(z));
    s(z < -thr) = 1;
    s(z > thr) = -1;
else
    s = double(z < -thr);
end

sigTT = array2timetable(s, 'RowTimes', retTT.Time, 'VariableNames', retTT.Properties.VariableNames);

end
