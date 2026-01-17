function out = lstm_model(feat, cfg)
%LSTM_MODEL Deep Learning placeholder.
%   This file is a scaffold. Implement rolling training + uncertainty later.

arguments
    feat (1,1) struct
    cfg (1,1) struct
end

out = struct();
out.name = "LSTM";
out.horizon = cfg.horizon;

% Touch inputs so MATLAB Analyzer doesn't flag them as unused.
if isfield(feat, 'X'); end

if exist('trainNetwork', 'file') ~= 2
    error('lstm_model:MissingToolbox', 'Requires Deep Learning Toolbox (trainNetwork).');
end

error('lstm_model:NotImplemented', 'LSTM scaffold: implement architecture + rolling retraining + uncertainty.');

end
