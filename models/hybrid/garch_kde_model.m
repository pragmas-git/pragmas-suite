function out = garch_kde_model(retTT, cfg)
%GARCH_KDE_MODEL Hybrid model: GARCH sigma + KDE residuals.
%   out = GARCH_KDE_MODEL(retTT, cfg)
%
%   Steps:
%     1) Fit rolling parametric model to get sigma_t
%     2) Compute standardized residuals z_t = (r_t - mu_t)/sigma_t
%     3) Fit KDE on z_t (rolling)
%     4) Reconstruct distribution for r_{t+1}
%
%   Output fields (standardized):
%     out.mu, out.sigma (timetables)
%     out.probUp (timetable)
%     out.var, out.cvar (timetables) for return distribution

arguments
    retTT timetable
    cfg (1,1) struct
end

if width(retTT) ~= 1
    error('garch_kde_model:UnivariateOnly', 'Start univariate; extend later to multi-asset.');
end

if isfield(cfg, 'horizon') && cfg.horizon ~= 1
    warning('garch_kde_model:HorizonNotImplemented', ...
        'cfg.horizon=%d is not yet implemented in hybrid reconstruction; using 1-step interpretation.', cfg.horizon);
end

% First get rolling mu/sigma
par = parametric_pipeline(retTT, cfg);
mu = par.mu.Variables;
sig = par.sigma.Variables;
r = retTT.Variables;

% Standardized residuals (skip NaNs)
z = (r - mu) ./ sig;

idx = get_rolling_indices(height(retTT), cfg);

probUp = nan(height(retTT),1);
varR = nan(height(retTT),1);
cvarR = nan(height(retTT),1);

for i = 1:numel(idx)
    trainIdx = idx(i).trainIdx;
    testIdx  = idx(i).testIdx;

    zTrain = z(trainIdx);
    zTrain = zTrain(isfinite(zTrain));
    if numel(zTrain) < 100
        continue;
    end

    kde = kde_distribution(zTrain, cfg.alpha, cfg.kde.bandwidth);

    % For each test point t: r ~ mu_t + sigma_t * Z
    for j = testIdx
        if ~isfinite(mu(j)) || ~isfinite(sig(j)) || sig(j) <= 0
            continue;
        end

        % P(r>0) = P(Z > -mu/sigma) = 1 - F_Z(-mu/sigma)
        thresh = -mu(j)/sig(j);
        Fth = interp1(kde.grid, kde.cdf, thresh, 'linear', 'extrap');
        Fth = min(max(Fth, 0), 1);
        probUp(j) = 1 - Fth;

        % VaR/CVaR of r at alpha
        varR(j) = mu(j) + sig(j) * kde.var;
        cvarR(j) = mu(j) + sig(j) * kde.cvar;
    end
end

assetName = retTT.Properties.VariableNames{1};

out = struct();
out.name = "HybridGARCHKDE";
out.mu = par.mu;
out.sigma = par.sigma;
if isfield(par, 'loglik')
    out.loglik = par.loglik;
end
out.probUp = array2timetable(probUp, 'RowTimes', retTT.Time, 'VariableNames', {assetName});
out.var = array2timetable(varR, 'RowTimes', retTT.Time, 'VariableNames', {assetName});
out.cvar = array2timetable(cvarR, 'RowTimes', retTT.Time, 'VariableNames', {assetName});
out.dist = struct('name','HybridGARCHKDE','notes','Return distribution via mu+sigma*Z with KDE(Z).');
out.horizon = cfg.horizon;

end
