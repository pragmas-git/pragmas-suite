function out = xgboost_model(feat, cfg)
%XGBOOST_MODEL Nonparametric model placeholder using fitrensemble.
%   out = XGBOOST_MODEL(feat, cfg)
%
%   Expected input:
%     feat.X timetable of features
%     feat.y timetable of targets (next returns)
%
%   Output (standardized):
%     out.pred timetable
%     out.predStd timetable (optional)
%     out.model trained model object

arguments
    feat (1,1) struct
    cfg (1,1) struct
end

if isfield(cfg, 'seed')
    rng(cfg.seed);
end

if ~isfield(feat, 'X') || ~isfield(feat, 'y')
    error('xgboost_model:InvalidInput', 'feat must contain feat.X and feat.y');
end

% This is intentionally a scaffold; for rolling training, wrap it in a pipeline.
if exist('fitrensemble', 'file') ~= 2
    error('xgboost_model:MissingToolbox', 'Requires Statistics and Machine Learning Toolbox (fitrensemble).');
end

X = feat.X.Variables;
% Start univariate target by default
assetNames = feat.y.Properties.VariableNames;
y = feat.y.(assetNames{1});

mdl = fitrensemble(X, y, 'Method', 'LSBoost');

pred = predict(mdl, X);
out = struct();
out.model = mdl;
out.pred = array2timetable(pred, 'RowTimes', feat.X.Time, 'VariableNames', {assetNames{1}});
out.predStd = timetable(); % optional: add bootstrap/quantile regression

end
