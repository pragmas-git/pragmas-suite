function retsTT = clean_returns(retsTT, cfg)
%CLEAN_RETURNS Basic returns cleaning.
%   - Removes rows with any NaNs
%   - Optional winsorization (can be extended)

arguments
    retsTT timetable
    cfg (1,1) struct
end

% cfg reserved for future cleaning options
if isfield(cfg, 'seed'); end

% Drop NaNs/infs
X = retsTT.Variables;
bad = any(~isfinite(X), 2);
retsTT(bad,:) = [];

% Placeholder for future: winsorize / outlier filtering

end
