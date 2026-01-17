function pricesTT = load_data(cfg)
%LOAD_DATA Load prices data from data/raw or generate synthetic.
%   pricesTT = LOAD_DATA(cfg) returns a timetable with RowTimes and one
%   variable per asset.
%
%   Supported raw formats:
%   (1) Single wide CSV: data/raw/prices.csv with columns: Date, ASSET1, ASSET2, ...
%   (2) FX per-asset CSVs: data/raw/EURUSD.csv, USDJPY.csv, ... with columns: Date, Close

arguments
    cfg (1,1) struct
end

rawFile = fullfile(cfg.dataRawDir, 'prices.csv');

if exist(rawFile, 'file')
    T = readtable(rawFile);
    if ~any(strcmpi(T.Properties.VariableNames, 'Date'))
        error('load_data:MissingDate', 'prices.csv must include a Date column.');
    end
    dt = datetime(T.Date);
    T.Date = [];
    pricesTT = table2timetable(T, 'RowTimes', dt);
    pricesTT = sortrows(pricesTT);
    % Optional date filter
    if isfield(cfg, 'startDate') && isfield(cfg, 'endDate')
        pricesTT = pricesTT(timerange(cfg.startDate, cfg.endDate, 'closed'), :);
    end
    return;
end

% FX mode: per-asset CSVs (Stooq/Yahoo style) OR Dukascopy parquet folders
assets = [];
if isfield(cfg, 'assets') && isstruct(cfg.assets) && isfield(cfg.assets, 'fx')
    assets = cfg.assets.fx;
elseif isfield(cfg, 'assetsList')
    assets = string(cfg.assetsList);
elseif isfield(cfg, 'assets') && iscell(cfg.assets)
    assets = string(cfg.assets);
end

isFx = false;
if isfield(cfg, 'market')
    isFx = (string(cfg.market) == "FX");
end

if isFx && ~isempty(assets)
    % Prefer processed daily close if available
    fxMat = fullfile(cfg.dataProcessedDir, 'fx_daily_close.mat');
    if exist(fxMat, 'file')
        S = load(fxMat);
        if isfield(S, 'pricesTT')
            pricesTT = S.pricesTT;
            return;
        end
    end

    % If parquet folders exist, build processed daily close
    folder0 = fullfile(cfg.dataRawDir, lower(assets(1)));
    if exist(folder0, 'dir') && ~isempty(dir(fullfile(folder0, '*_m1.parquet')))
        [pricesTT, rep] = build_fx_daily_close_from_parquet(cfg);
        try
            if isfield(rep, 'dataQualitySummary')
                disp('Data quality summary (per asset):');
                disp(rep.dataQualitySummary(:, {'Asset','DailyCloses','MissingPct','SpreadMean','SpreadP95','SpreadBpsMean','SpreadBpsP95','AskLtBidCount'}));
                if isfield(rep, 'reportCsvPath')
                    fprintf('Saved data-quality report: %s\n', rep.reportCsvPath);
                end
            end
        catch
        end
        return;
    end

    perAssetTT = cell(numel(assets), 1);
    for k = 1:numel(assets)
        a = string(assets(k));
        f = fullfile(cfg.dataRawDir, a + ".csv");
        if ~exist(f, 'file')
            error('load_data:MissingFxFile', 'Missing FX CSV: %s', f);
        end

        T = readtable(f);
        if ~any(strcmpi(T.Properties.VariableNames, 'Date'))
            error('load_data:MissingDate', '%s must include a Date column.', f);
        end
        if ~any(strcmpi(T.Properties.VariableNames, 'Close'))
            error('load_data:MissingClose', '%s must include a Close column.', f);
        end

        dt = datetime(T.Date);
        closeCol = T{:, strcmpi(T.Properties.VariableNames, 'Close')};
        tt = timetable(dt, closeCol, 'VariableNames', {char(a)});
        tt = sortrows(tt);
        perAssetTT{k} = tt;
    end

    pricesTT = perAssetTT{1};
    for k = 2:numel(perAssetTT)
        pricesTT = synchronize(pricesTT, perAssetTT{k}, 'intersection');
    end

    if isfield(cfg, 'startDate') && isfield(cfg, 'endDate')
        pricesTT = pricesTT(timerange(cfg.startDate, cfg.endDate, 'closed'), :);
    end

    return;
end

if ~cfg.allowSyntheticData
    error('load_data:NoRawData', 'No raw data found at %s', rawFile);
end

% Synthetic geometric random walk (for scaffolding / dev only)
rng(cfg.seed);
numObs = cfg.synthetic.numObs;
if isfield(cfg, 'assetsList')
    assets = string(cfg.assetsList);
elseif isfield(cfg, 'assets') && iscell(cfg.assets)
    assets = string(cfg.assets);
else
    assets = ["ASSET1","ASSET2"];
end
numAssets = numel(assets);

startDate = cfg.synthetic.startDate;
dates = startDate + caldays(0:numObs-1);

mu = 0.05/252;
sigma = 0.20/sqrt(252);

prices = nan(numObs, numAssets);
prices(1,:) = 100;
for t = 2:numObs
    eps = randn(1, numAssets);
    ret = mu + sigma.*eps;
    prices(t,:) = prices(t-1,:) .* exp(ret);
end

pricesTbl = array2table(prices, 'VariableNames', cellstr(assets));
pricesTT = table2timetable(pricesTbl, 'RowTimes', dates);

end
