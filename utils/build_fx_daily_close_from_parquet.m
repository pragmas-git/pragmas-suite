function [pricesTT, report] = build_fx_daily_close_from_parquet(cfg)
%BUILD_FX_DAILY_CLOSE_FROM_PARQUET Build canonical FX daily close from intraday parquet.
%   [pricesTT, report] = BUILD_FX_DAILY_CLOSE_FROM_PARQUET(cfg)
%
%   Canonical definition:
%     For each NY calendar day D, take the last mid-price 0.5*(ask+bid)
%     observed strictly before 17:00 America/New_York (DST-aware).
%
%   Input data layout (Dukascopy-style):
%     data/raw/<assetlower>/<assetlower>_YYYY-MM-DD_YYYY-MM-DD_m1.parquet
%   with columns: timestamp (UTC), ask, bid, ask_volume, bid_volume.
%
%   Output:
%     pricesTT: timetable indexed by close timestamp (UTC) with one variable per asset.
%     report: struct with QC statistics and data-quality summaries.

arguments
    cfg (1,1) struct
end

if ~isfield(cfg, 'seed')
    error('build_fx_daily_close_from_parquet:MissingSeed', 'cfg.seed is required for reproducible QC sampling.');
end

if exist('parquetread', 'file') ~= 2
    error('build_fx_daily_close_from_parquet:MissingDependency', 'parquetread is required to ingest parquet files.');
end

if ~isfield(cfg, 'assetsList')
    error('build_fx_daily_close_from_parquet:MissingAssets', 'cfg.assetsList is required.');
end

assets = string(cfg.assetsList);
rawDir = cfg.dataRawDir;

% Use a local RNG stream for deterministic QC sampling without perturbing global rng.
qcStream = RandStream('mt19937ar', 'Seed', double(cfg.seed));

sampleMax = 2e6;
samplePerFile = 1e5;
if isfield(cfg, 'fx')
    if isfield(cfg.fx, 'qcSampleMax'); sampleMax = double(cfg.fx.qcSampleMax); end
    if isfield(cfg.fx, 'qcSamplePerFile'); samplePerFile = double(cfg.fx.qcSamplePerFile); end
end

nyTz = "America/New_York";
closeHour = 17;
if isfield(cfg, 'fx')
    if isfield(cfg.fx, 'timezone'); nyTz = string(cfg.fx.timezone); end
    if isfield(cfg.fx, 'closeHourNY'); closeHour = double(cfg.fx.closeHourNY); end
end

% Collect per-asset daily closes
assetDaily = cell(numel(assets), 1);
assetQc = cell(numel(assets), 1);
assetDailyCounts = cell(numel(assets), 1);

for a = 1:numel(assets)
    asset = assets(a);
    folder = fullfile(rawDir, lower(asset));
    if ~exist(folder, 'dir')
        error('build_fx_daily_close_from_parquet:MissingFolder', 'Missing folder: %s', folder);
    end

    files = dir(fullfile(folder, '*_m1.parquet'));
    if isempty(files)
        error('build_fx_daily_close_from_parquet:NoParquet', 'No parquet files found in %s', folder);
    end

    % Sort by name (contains date ranges)
    [~, ord] = sort({files.name});
    files = files(ord);

    dayCloseMap = containers.Map('KeyType','char','ValueType','any');

    dayObsMap = containers.Map('KeyType','char','ValueType','double');

    spreadSum = 0;
    spreadCount = 0;
    spreadSample = zeros(0,1);
    spreadMax = -inf;

    spreadBpsSum = 0;
    spreadBpsCount = 0;
    spreadBpsSample = zeros(0,1);

    spreadsBad = 0;
    rowsTotal = 0;

    for k = 1:numel(files)
        fpath = fullfile(files(k).folder, files(k).name);
        T = parquetread(fpath);

        % Expect columns
        vars = string(T.Properties.VariableNames);
        if ~any(vars == "timestamp") || ~any(vars == "ask") || ~any(vars == "bid")
            error('build_fx_daily_close_from_parquet:SchemaMismatch', 'Unexpected schema in %s', fpath);
        end

        ts = T.timestamp;
        ask = T.ask;
        bid = T.bid;

        rowsTotal = rowsTotal + numel(ask);

        % Basic QC
        spreadSigned = ask - bid;
        spreadsBad = spreadsBad + sum(spreadSigned < 0);
        spreadAbs = abs(spreadSigned);
        validSpread = isfinite(spreadAbs);
        if any(validSpread)
            sv = spreadAbs(validSpread);
            spreadSum = spreadSum + sum(sv);
            spreadCount = spreadCount + numel(sv);
            spreadMax = max(spreadMax, max(sv));
            spreadSample = append_sample(spreadSample, sv, sampleMax, samplePerFile, qcStream);
        end

        % Normalized spread (bps): 1e4 * |ask-bid| / mid
        midAll = 0.5 * (ask + bid);
        spreadBps = 1e4 * spreadAbs ./ midAll;
        validBps = isfinite(spreadBps) & isfinite(midAll) & (midAll > 0);
        if any(validBps)
            sb = spreadBps(validBps);
            spreadBpsSum = spreadBpsSum + sum(sb);
            spreadBpsCount = spreadBpsCount + numel(sb);
            spreadBpsSample = append_sample(spreadBpsSample, sb, sampleMax, samplePerFile, qcStream);
        end

        % Ensure datetime and timezone
        if ~isdatetime(ts)
            ts = datetime(ts);
        end
        if isempty(ts.TimeZone)
            ts.TimeZone = 'UTC';
        end

        % Convert to NY time (DST-aware)
        tsNY = ts;
        tsNY.TimeZone = char(nyTz);

        mid = 0.5 * (ask + bid);

        % Remove NaNs and sort
        good = isfinite(mid) & isfinite(posixtime(tsNY));
        tsNY = tsNY(good);
        mid = mid(good);

        [tsNY, sidx] = sort(tsNY);
        mid = mid(sidx);

        % Drop duplicate timestamps by keeping last
        [~, lastIdx] = unique(tsNY, 'last');
        tsNY = tsNY(lastIdx);
        mid = mid(lastIdx);

        % Filter by date range (in NY calendar terms)
        if isfield(cfg, 'startDate') && isfield(cfg, 'endDate')
            % Compare in NY tz
            startNY = cfg.startDate; startNY.TimeZone = char(nyTz);
            endNY = cfg.endDate; endNY.TimeZone = char(nyTz);
            inRange = (tsNY >= startNY) & (tsNY <= (endNY + days(1)));
            tsNY = tsNY(inRange);
            mid = mid(inRange);
        end

        if isempty(tsNY)
            continue;
        end

        % Observations per NY day (all ticks, after de-dup + date filter)
        dayAll = dateshift(tsNY, 'start', 'day');
        [GAll, dayKeysAll] = findgroups(dayAll);
        nAll = splitapply(@numel, tsNY, GAll);
        for d = 1:numel(dayKeysAll)
            key = datestr(dayKeysAll(d), 'yyyy-mm-dd');
            if isKey(dayObsMap, key)
                dayObsMap(key) = dayObsMap(key) + nAll(d);
            else
                dayObsMap(key) = nAll(d);
            end
        end

        dayStart = dateshift(tsNY, 'start', 'day');
        cut = dayStart + hours(closeHour);
        beforeClose = tsNY < cut;

        dayStart = dayStart(beforeClose);
        tsNY2 = tsNY(beforeClose);
        mid2 = mid(beforeClose);

        if isempty(tsNY2)
            continue;
        end

        % Group by day and take last timestamp (hence last mid)
        [G, dayKeys] = findgroups(dayStart);
        [tsLast, midLast] = splitapply(@groupLast, tsNY2, mid2, G);

        % Store per day (key=yyyy-mm-dd)
        for d = 1:numel(dayKeys)
            key = datestr(dayKeys(d), 'yyyy-mm-dd');
            val = {tsLast(d), midLast(d)};
            % If repeated (overlapping files), keep the later timestamp
            if isKey(dayCloseMap, key)
                prev = dayCloseMap(key);
                if val{1} > prev{1}
                    dayCloseMap(key) = val;
                end
            else
                dayCloseMap(key) = val;
            end
        end
    end

    % Convert map to timetable
    keys = dayCloseMap.keys;
    keys = sort(keys);

    closeNY = NaT(numel(keys),1,'TimeZone',char(nyTz));
    closeMid = nan(numel(keys),1);
    obsTsNY = NaT(numel(keys),1,'TimeZone',char(nyTz));

    for i = 1:numel(keys)
        key = keys{i};
        day = datetime(key, 'InputFormat','yyyy-MM-dd', 'TimeZone', char(nyTz));
        closeNY(i) = day + hours(closeHour);
        val = dayCloseMap(key);
        obsTsNY(i) = val{1};
        closeMid(i) = val{2};
    end

    closeUTC = closeNY;
    closeUTC.TimeZone = 'UTC';

    tt = timetable(closeUTC, closeMid, 'VariableNames', {char(asset)});

    % Enforce weekday-only daily closes (Mon–Fri) in NY calendar
    rtNY = tt.Properties.RowTimes;
    rtNY.TimeZone = char(nyTz);
    dayNY = dateshift(rtNY, 'start', 'day');
    wk = weekday(dayNY);
    keep = ~ismember(wk, [1 7]); % exclude Sun(1),Sat(7)
    tt = tt(keep, :);

    qc = struct();
    qc.asset = asset;
    qc.rowsTotal = rowsTotal;
    qc.askLtBidCount = spreadsBad;
    qc.badSpreadCount = spreadsBad; % backward-compatible alias
    qc.spreadMean = spreadSum / max(spreadCount, 1);
    qc.spreadP95 = percentile_from_sample(spreadSample, 95);
    qc.spreadMax = spreadMax;
    qc.spreadSample = spreadSample; % bounded sample for plots/QC (not full dataset)
    qc.spreadBpsMean = spreadBpsSum / max(spreadBpsCount, 1);
    qc.spreadBpsP95 = percentile_from_sample(spreadBpsSample, 95);
    qc.spreadBpsSample = spreadBpsSample;
    qc.numDailyCloses = height(tt);
    qc.coverageStart = closeUTC(1);
    qc.coverageEnd = closeUTC(end);

    assetDaily{a} = tt;
    assetQc{a} = qc;

    % Daily observation counts table
    ok = dayObsMap.keys;
    ok = sort(ok);
    dayDt = datetime(ok, 'InputFormat','yyyy-MM-dd', 'TimeZone', char(nyTz));
    dayDt = dayDt(:);
    obsCount = zeros(numel(ok), 1);
    for i = 1:numel(ok)
        obsCount(i) = dayObsMap(ok{i});
    end
    assetDailyCounts{a} = table(dayDt, obsCount, 'VariableNames', {'DayNY','ObsCount'});
end

% Synchronize all assets on intersection of available daily closes
pricesTT = assetDaily{1};
for a = 2:numel(assetDaily)
    pricesTT = synchronize(pricesTT, assetDaily{a}, 'intersection');
end

% Build report
report = struct('timestamp', datetime('now'), ...
    'assets', assets, ...
    'qc', {assetQc}, ...
    'dailyObsCounts', {assetDailyCounts}, ...
    'numRows', [], ...
    'start', [], ...
    'end', [], ...
    'dataQualitySummary', [], ...
    'missingDaysNY', [], ...
    'savedPath', '', ...
    'reportMatPath', '', ...
    'reportCsvPath', '', ...
    'dailyObsCsvPath', '', ...
    'plotObsPerDayPath', '', ...
    'plotSpreadBoxplotPath', '', ...
    'plotSpreadBpsBoxplotPath', '');

% Missing-day report (approx): compare against expected NY business days not enforced.
report.numRows = height(pricesTT);
rt = pricesTT.Properties.RowTimes;
report.start = rt(1);
report.end = rt(end);

% Data-quality summary table (for thesis chapter / appendices)
summary = table('Size',[numel(assets) 15], ...
    'VariableTypes', ["string","double","double","double","double","double","double","double","double","double","double","double","double","double","double"], ...
    'VariableNames', ["Asset","RowsTotal","ExpectedDays","DailyCloses","MissingDays","MissingPct","ObsPerDayMean","ObsPerDayMedian","ObsPerDayP05","ObsPerDayP95","SpreadMean","SpreadP95","SpreadBpsMean","SpreadBpsP95","AskLtBidCount"]);

for a = 1:numel(assets)
    asset = assets(a);
    qc = assetQc{a};
    dailyCloseTT = assetDaily{a};
    countsTbl = assetDailyCounts{a};

    startNY = cfg.startDate; startNY.TimeZone = char(nyTz);
    endNY = cfg.endDate; endNY.TimeZone = char(nyTz);
    allDays = (dateshift(startNY, 'start', 'day'):caldays(1):dateshift(endNY, 'start', 'day'))';
    wk = weekday(allDays);
    expected = allDays(~ismember(wk, [1 7])); % exclude Sun(1),Sat(7)
    expectedN = numel(expected);

    closeNY = dailyCloseTT.Properties.RowTimes;
    closeNY.TimeZone = char(nyTz);
    closeDays = dateshift(closeNY, 'start', 'day');
    closeDays = unique(closeDays);

    missingN = max(expectedN - numel(intersect(expected, closeDays)), 0);
    missingPct = missingN / max(expectedN, 1);

    obs = countsTbl.ObsCount;
    obsMean = mean(obs);
    obsMed = median(obs);
    obsP05 = percentile_from_sample(obs, 5);
    obsP95 = percentile_from_sample(obs, 95);

    summary.Asset(a) = asset;
    summary.RowsTotal(a) = qc.rowsTotal;
    summary.ExpectedDays(a) = expectedN;
    summary.DailyCloses(a) = qc.numDailyCloses;
    summary.MissingDays(a) = missingN;
    summary.MissingPct(a) = missingPct;
    summary.ObsPerDayMean(a) = obsMean;
    summary.ObsPerDayMedian(a) = obsMed;
    summary.ObsPerDayP05(a) = obsP05;
    summary.ObsPerDayP95(a) = obsP95;
    summary.SpreadMean(a) = qc.spreadMean;
    summary.SpreadP95(a) = qc.spreadP95;
    if isfield(qc, 'spreadBpsMean')
        summary.SpreadBpsMean(a) = qc.spreadBpsMean;
        summary.SpreadBpsP95(a) = qc.spreadBpsP95;
    else
        summary.SpreadBpsMean(a) = NaN;
        summary.SpreadBpsP95(a) = NaN;
    end
    if isfield(qc, 'askLtBidCount')
        summary.AskLtBidCount(a) = qc.askLtBidCount;
    else
        summary.AskLtBidCount(a) = qc.badSpreadCount;
    end
end

report.dataQualitySummary = summary;

% Store missing-day lists (NY calendar) for auditing
missingDaysNY = cell(numel(assets), 1);
for a = 1:numel(assets)
    asset = assets(a); %#ok<NASGU>
    dailyCloseTT = assetDaily{a};

    startNY = cfg.startDate; startNY.TimeZone = char(nyTz);
    endNY = cfg.endDate; endNY.TimeZone = char(nyTz);
    allDays = (dateshift(startNY, 'start', 'day'):caldays(1):dateshift(endNY, 'start', 'day'))';
    wk = weekday(allDays);
    expected = allDays(~ismember(wk, [1 7]));

    closeNY = dailyCloseTT.Properties.RowTimes;
    closeNY.TimeZone = char(nyTz);
    closeDays = dateshift(closeNY, 'start', 'day');
    closeDays = unique(closeDays);

    missingDaysNY{a} = setdiff(expected, closeDays);
end
report.missingDaysNY = missingDaysNY;

% Persist to data/processed
try
    outFile = fullfile(cfg.dataProcessedDir, 'fx_daily_close.mat');
    if ~exist(cfg.dataProcessedDir, 'dir'); mkdir(cfg.dataProcessedDir); end
    save(outFile, 'pricesTT', 'report');
    report.savedPath = outFile;
catch
end

% Persist report to results (MAT + CSV)
try
    if ~exist(cfg.resultsDir, 'dir'); mkdir(cfg.resultsDir); end
    reportMat = fullfile(cfg.resultsDir, 'data_quality_report.mat');
    reportCsv = fullfile(cfg.resultsDir, 'data_quality_report.csv');
    dataQualitySummary = summary; %#ok<NASGU>
    save(reportMat, 'dataQualitySummary', 'report');
    writetable(summary, reportCsv);

    % Optional: daily obs counts (long format)
    dailyFile = fullfile(cfg.resultsDir, 'data_quality_daily_obs_counts.csv');
    dailyLongCells = cell(numel(assets), 1);
    for a = 1:numel(assets)
        t = assetDailyCounts{a};
        t.Asset = repmat(assets(a), height(t), 1);
        dailyLongCells{a} = t;
    end
    dailyLong = vertcat(dailyLongCells{:});
    writetable(dailyLong, dailyFile);

    report.reportMatPath = reportMat;
    report.reportCsvPath = reportCsv;
    report.dailyObsCsvPath = dailyFile;
catch
end

% Generate basic thesis-ready plots
try
    if ~exist(cfg.resultsDir, 'dir'); mkdir(cfg.resultsDir); end

    % Initialize optional plot paths (so callers can safely access fields)
    report.plotObsPerDayPath = '';
    report.plotSpreadBoxplotPath = '';
    report.plotSpreadBpsBoxplotPath = '';

    % 1) Histogram: observations per day (per asset)
    fig1 = figure('Visible','off');
    tiledlayout(fig1, numel(assets), 1, 'Padding','compact', 'TileSpacing','compact');
    for a = 1:numel(assets)
        nexttile;
        obs = assetDailyCounts{a}.ObsCount;
        histogram(obs, 50);
        title(sprintf('%s: observations per NY day', assets(a)));
        xlabel('Obs count');
        ylabel('Days');
        grid on;
    end
    p1 = fullfile(cfg.resultsDir, 'data_quality_obs_per_day_hist.png');
    save_figure_png(fig1, p1);
    close(fig1);

    % 2) Boxplot: spreads per asset (absolute)
    fig2 = figure('Visible','off');
    spreadCells = cell(numel(assets), 1);
    groupCells = cell(numel(assets), 1);
    for a = 1:numel(assets)
        qc = assetQc{a};
        sp = qc.spreadSample;
        if isempty(sp)
            continue;
        end
        spreadCells{a} = sp(:);
        groupCells{a} = repmat(assets(a), numel(sp), 1);
    end
    spreadAll = vertcat(spreadCells{:});
    groupAll = vertcat(groupCells{:});
    if ~isempty(spreadAll)
        boxplot(spreadAll, groupAll);
        title('Dukascopy intraday spreads (absolute, sampled)');
        ylabel('|ask - bid|');
        grid on;
    else
        text(0.1, 0.5, 'No spread samples available to plot.');
        axis off;
    end
    p2 = fullfile(cfg.resultsDir, 'data_quality_spread_boxplot.png');
    save_figure_png(fig2, p2);
    close(fig2);

    report.plotObsPerDayPath = p1;
    report.plotSpreadBoxplotPath = p2;

    % 3) Boxplot: normalized spreads (bps)
    try
        fig3 = figure('Visible','off');
        spreadBpsCells = cell(numel(assets), 1);
        groupBpsCells = cell(numel(assets), 1);
        for a = 1:numel(assets)
            qc = assetQc{a};
            if isfield(qc, 'spreadBpsSample')
                sp = qc.spreadBpsSample;
            else
                sp = [];
            end
            if isempty(sp)
                continue;
            end
            sp = sp(:);
            sp = sp(isfinite(sp) & sp >= 0);
            if isempty(sp)
                continue;
            end
            spreadBpsCells{a} = sp;
            groupBpsCells{a} = repmat(assets(a), numel(sp), 1);
        end
        spreadBpsAll = vertcat(spreadBpsCells{:});
        groupBpsAll = vertcat(groupBpsCells{:});
        if ~isempty(spreadBpsAll)
            grp = categorical(cellstr(groupBpsAll));
            boxplot(spreadBpsAll, grp);
            title('Dukascopy intraday spreads (normalized, bps, sampled)');
            ylabel('Spread (bps)');
            grid on;
        else
            text(0.1, 0.5, 'No spread bps samples available to plot.');
            axis off;
        end
        p3 = fullfile(cfg.resultsDir, 'data_quality_spread_bps_boxplot.png');
        save_figure_png(fig3, p3);
        close(fig3);
        report.plotSpreadBpsBoxplotPath = p3;
    catch
        try
            close(fig3);
        catch
        end
    end
catch
end

end

function [tLast, midLast] = groupLast(t, mid)
% Return last observation in a group based on max timestamp.
[~, i] = max(t);
tLast = t(i);
midLast = mid(i);
end

function sample = append_sample(sample, values, maxN, perFileN, stream)
% Append values to sample with simple downsampling to bound memory.
values = values(:);
if ~isempty(perFileN) && isfinite(perFileN) && numel(values) > perFileN
    idx = randperm(stream, numel(values), perFileN);
    values = values(idx);
end

sample = [sample; values]; %#ok<AGROW>
if numel(sample) > maxN
    idx = randperm(stream, numel(sample), maxN);
    sample = sample(idx);
end
end

function p = percentile_from_sample(x, pct)
% Toolbox-free percentile for vector x.
x = x(isfinite(x));
if isempty(x)
    p = NaN;
    return;
end
x = sort(x(:));
n = numel(x);
k = max(1, min(n, ceil((pct/100) * n)));
p = x(k);
end

function save_figure_png(fig, pathOut)
% Save figure as PNG (headless-safe across MATLAB versions).
try
    exportgraphics(fig, pathOut, 'Resolution', 150);
catch
    try
        print(fig, pathOut, '-dpng', '-r150');
    catch
        saveas(fig, pathOut);
    end
end
end
