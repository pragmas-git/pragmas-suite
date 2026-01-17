function out = parametric_pipeline(retTT, cfg)
%PARAMETRIC_PIPELINE Rolling parametric model pipeline.
%   out = PARAMETRIC_PIPELINE(retTT, cfg)
%
%   Standard output fields:
%       out.mu    timetable
%       out.sigma timetable
%       out.dist  struct describing the conditional distribution

arguments
    retTT timetable
    cfg (1,1) struct
end

if width(retTT) ~= 1
    error('parametric_pipeline:UnivariateOnly', 'Use one asset at a time initially.');
end

idx = get_rolling_indices(height(retTT), cfg);
assetName = retTT.Properties.VariableNames{1};

muVals = nan(height(retTT), 1);
sigVals = nan(height(retTT), 1);
loglikVals = nan(height(retTT), 1);

for i = 1:numel(idx)
    tr = retTT(idx(i).trainIdx,:);
    te = retTT(idx(i).testIdx,:);

    m = fit_garch(tr, cfg);
    fc = forecast_garch(m, tr, height(te));

    muVals(idx(i).testIdx) = fc.mu;
    sigVals(idx(i).testIdx) = fc.sigma;

    % Store log-likelihood at rebalance point (diagnostics)
    if isfield(m, 'loglik')
        loglikVals(idx(i).rebalanceTimeIndex) = m.loglik;
    end
end

out = struct();
out.name = "Parametric";
out.mu = array2timetable(muVals, 'RowTimes', retTT.Time, 'VariableNames', {assetName});
out.sigma = array2timetable(sigVals, 'RowTimes', retTT.Time, 'VariableNames', {assetName});
out.dist = struct('name','Normal','notes','Parametric placeholder: Normal(mu,sigma)');
out.loglik = array2timetable(loglikVals, 'RowTimes', retTT.Time, 'VariableNames', {assetName});
out.horizon = cfg.horizon;

end
