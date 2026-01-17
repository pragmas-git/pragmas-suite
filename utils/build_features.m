function feat = build_features(retsTT, cfg)
%BUILD_FEATURES Build ML features from returns.
%   feat = BUILD_FEATURES(retsTT, cfg) returns a struct with:
%       feat.X : timetable of features
%       feat.y : timetable of next-period returns (per asset)
%
%   Current features (per asset):
%   - Lags of returns
%   - Realized volatility (rolling std)
%   - Momentum (rolling mean)
%
%   Extend here with skew/kurtosis, cross-asset features, etc.

arguments
    retsTT timetable
    cfg (1,1) struct
end

lags = 5;
volWindow = 21;
momWindow = 63;

assetNames = retsTT.Properties.VariableNames;

Xtbl = timetable(retsTT.Time);
Xtbl.Properties.DimensionNames{1} = 'Time';

R = retsTT.Variables;

for a = 1:numel(assetNames)
    name = assetNames{a};
    r = R(:,a);

    % Lags
    for k = 1:lags
        x = [nan(k,1); r(1:end-k)];
        Xtbl.(sprintf('%s_lag%d', name, k)) = x;
    end

    % Realized volatility
    Xtbl.(sprintf('%s_rvol%d', name, volWindow)) = movstd(r, [volWindow-1 0], 'omitnan');

    % Momentum
    Xtbl.(sprintf('%s_mom%d', name, momWindow)) = movmean(r, [momWindow-1 0], 'omitnan');
end

% Target: next-period returns
Y = [R(2:end,:); nan(1, size(R,2))];
yTT = array2timetable(Y, 'RowTimes', retsTT.Time, 'VariableNames', assetNames);

% Align & drop initial NaN rows from lags/windows
valid = all(isfinite(Xtbl.Variables), 2) & all(isfinite(yTT.Variables), 2);
feat = struct();
feat.X = Xtbl(valid,:);
feat.y = yTT(valid,:);

% Optional persistence
if isfield(cfg, 'dataFeaturesDir')
    try
        save(fullfile(cfg.dataFeaturesDir, 'features.mat'), 'feat');
    catch
        % ignore save failures (permissions, etc.)
    end
end

end
