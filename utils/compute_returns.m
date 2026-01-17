function retsTT = compute_returns(pricesTT, cfg)
%COMPUTE_RETURNS Compute log-returns from a prices timetable.
%   retsTT = COMPUTE_RETURNS(pricesTT, cfg)

arguments
    pricesTT timetable
    cfg (1,1) struct
end

% cfg reserved for future options (frequency, calendar, etc.)
if isfield(cfg, 'frequency'); end

assetNames = pricesTT.Properties.VariableNames;
P = pricesTT.Variables;

% log returns
R = diff(log(P));

% FX sign convention: invert USD/XXX so r>0 means appreciation of non-USD currency
if isfield(cfg, 'fx') && isstruct(cfg.fx) && isfield(cfg.fx, 'invertUSDpairs')
    invList = string(cfg.fx.invertUSDpairs);
    for j = 1:numel(assetNames)
        if any(invList == string(assetNames{j}))
            R(:,j) = -R(:,j);
        end
    end
end

rt = pricesTT.Properties.RowTimes;
retsTT = array2timetable(R, 'RowTimes', rt(2:end), 'VariableNames', assetNames);

end
