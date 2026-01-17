function idx = get_rolling_indices(numObs, cfg)
%GET_ROLLING_INDICES Generate rolling window indices.
%   idx = GET_ROLLING_INDICES(numObs, cfg) returns a struct array with fields:
%       .trainIdx, .testIdx, .rebalanceTimeIndex

arguments
    numObs (1,1) double {mustBeInteger, mustBePositive}
    cfg (1,1) struct
end

if isfield(cfg, 'rolling') && isstruct(cfg.rolling)
    wTrain = cfg.rolling.train;
    wTest  = cfg.rolling.test;
    step   = cfg.rolling.step;
else
    wTrain = cfg.windowTrain;
    wTest  = cfg.windowTest;
    step   = cfg.rebalance;
end

starts = 1:step:(numObs - (wTrain + wTest) + 1);

idx = repmat(struct('trainIdx',[], 'testIdx',[], 'rebalanceTimeIndex',[]), 0, 1);
for s = starts
    trainIdx = s:(s+wTrain-1);
    testIdx  = (s+wTrain):(s+wTrain+wTest-1);
    one = struct('trainIdx', trainIdx, 'testIdx', testIdx, 'rebalanceTimeIndex', s+wTrain);
    idx(end+1,1) = one;
end

end
