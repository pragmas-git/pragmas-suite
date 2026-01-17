function fc = forecast_garch(model, retTT, horizon)
%FORECAST_GARCH Produce 1-step or multi-step forecasts.
%   fc = FORECAST_GARCH(model, retTT, horizon)
%   fc has fields: mu, sigma

arguments
    model (1,1) struct
    retTT timetable
    horizon (1,1) double {mustBeInteger, mustBePositive} = 1
end

r = retTT.Variables;
r = r(:);

fc = struct();

if isfield(model, 'toolboxUsed') && model.toolboxUsed && isfield(model, 'estMdl') && exist('forecast', 'file') == 2
    try
        v = forecast(model.estMdl, horizon, 'Y0', r);
        fc.mu = repmat(model.mu, horizon, 1);
        fc.sigma = sqrt(v(:));
        return;
    catch
        % fall back
    end
end

% Fallback: constant mean/vol
fc.mu = repmat(model.mu, horizon, 1);
fc.sigma = repmat(model.sigma, horizon, 1);

end
