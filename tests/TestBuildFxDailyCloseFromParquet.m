classdef TestBuildFxDailyCloseFromParquet < matlab.unittest.TestCase
    methods (Test)
        function testWeekendExclusionAndSavedFile(tc)
            if exist('parquetwrite','file') ~= 2 || exist('parquetread','file') ~= 2
                tc.assumeFail('parquetread/parquetwrite not available in this MATLAB.');
            end

            tmp = tempname;
            mkdir(tmp);
            rawDir = fullfile(tmp, 'raw');
            procDir = fullfile(tmp, 'processed');
            resDir = fullfile(tmp, 'results');

            asset = "EURUSD";
            assetDir = fullfile(rawDir, lower(asset));
            mkdir(assetDir);

            % Create timestamps that include a Saturday in NY calendar.
            % We'll write UTC-naive datetimes and let the builder set TimeZone='UTC'.
            % Fri 2020-01-03 and Sat 2020-01-04 (NY) around 16:59.
            ts = [datetime(2020,1,3,21,58,0);  % ~16:58 NY (UTC-5)
                  datetime(2020,1,3,21,59,0);
                  datetime(2020,1,4,21,59,0)]; % Saturday
            bid = [1.1000; 1.1005; 1.1010];
            ask = bid + 0.0002;

            T = table(ts, ask, bid, 'VariableNames', {'timestamp','ask','bid'});
            fpath = fullfile(assetDir, sprintf('%s_2020-01-01_2020-01-10_m1.parquet', lower(asset)));
            parquetwrite(fpath, T);

            cfg = config();
            cfg.assetsList = {char(asset)};
            cfg.dataRawDir = rawDir;
            cfg.dataProcessedDir = procDir;
            cfg.resultsDir = resDir;
            cfg.startDate = datetime(2020,1,1);
            cfg.endDate = datetime(2020,1,10);
            cfg.seed = 7;
            cfg.fx.timezone = "America/New_York";
            cfg.fx.closeHourNY = 17;

            [pricesTT, report] = build_fx_daily_close_from_parquet(cfg);

            tc.verifyTrue(istimetable(pricesTT));
            tc.verifyEqual(pricesTT.Properties.VariableNames, {char(asset)});

            % Ensure no weekend rows.
            rtNY = pricesTT.Properties.RowTimes;
            rtNY.TimeZone = 'America/New_York';
            dayNY = dateshift(rtNY, 'start', 'day');
            wk = weekday(dayNY);
            tc.verifyFalse(any(ismember(wk, [1 7])));

            savedPath = fullfile(procDir, 'fx_daily_close.mat');
            tc.verifyTrue(exist(savedPath, 'file') == 2);
            tc.verifyTrue(isfield(report, 'dataQualitySummary'));
        end
    end
end
