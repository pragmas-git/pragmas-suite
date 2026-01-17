function model = fit_garch(retTT, cfg)
%FIT_GARCH Fit a (G)ARCH model on a univariate return series.
%   model = FIT_GARCH(retTT, cfg)
%
%   Returns a struct with at least:
%       model.mu
%       model.sigma
%       model.modelType
%       model.toolboxUsed

arguments
    retTT timetable
    cfg (1,1) struct
end

if width(retTT) ~= 1
    error('fit_garch:UnivariateOnly', 'fit_garch expects a univariate timetable.');
end

r = retTT.Variables;
r = r(:);

model = struct();
model.modelType = 'GARCH';
model.toolboxUsed = false;
model.logL = NaN;
model.loglik = NaN;

% Econometrics Toolbox path (preferred)
if exist('garch', 'file') == 2 && exist('estimate', 'file') == 2
    try
        mdl = garch(cfg.garch.p, cfg.garch.q);
        [estMdl, ~, logL] = estimate(mdl, r, 'Display', 'off');
        model.toolboxUsed = true;
        model.estMdl = estMdl;
        model.logL = logL;
        model.loglik = logL;
        % Conditional mean is not explicitly modeled here; keep sample mean
        model.mu = mean(r, 'omitnan');
        model.sigma = sqrt(var(r, 'omitnan'));
        return;
    catch
        % fall through to simple fallback
    end
end

% Fallback (no toolbox / estimation failed)
model.modelType = 'SimpleMeanVar';
model.mu = mean(r, 'omitnan');
model.sigma = sqrt(var(r, 'omitnan'));
model.logL = NaN;
model.loglik = NaN;

end
