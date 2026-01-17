classdef TestLatexReport < matlab.unittest.TestCase
    methods (Test)
        function testTexIsCreated(tc)
            % Minimal fake results struct with a summary table
            cfg = config();
            tmp = tempname;
            mkdir(tmp);

            summary = table("EURUSD", cfg.alpha, 0.1, 0.2, ...
                0.05, 0.06, 0.5, 0.4, 0.5, 0.4, 0, 1, 0, 10, ...
                'VariableNames', {'Asset','Alpha','CRPS_Parametric','CRPS_Hybrid', ...
                'VaRRate_Parametric','VaRRate_Hybrid','KupiecP_Parametric','KupiecP_Hybrid', ...
                'ChristoffersenP_Parametric','ChristoffersenP_Hybrid', ...
                'DM_CRPS','DM_pValue','DM_meanDiff','DM_n'});

            results = struct();
            results.series = struct();
            % Provide minimal series fields expected by export_report_figures
            t = datetime(2020,1,1) + days(0:9);
            results.series.EURUSD = struct();
            results.series.EURUSD.crps = timetable(t(:), rand(10,1), rand(10,1), ...
                'VariableNames', {'CRPS_Parametric','CRPS_Hybrid'});
            results.series.EURUSD.var = timetable(t(:), rand(10,1), rand(10,1), ...
                'VariableNames', {'VaR_Parametric','VaR_Hybrid'});
            results.evaluation = struct('summary', summary);

            out = generate_latex_report(results, cfg, 'outputDir', string(tmp), 'compile', false);
            tc.verifyTrue(exist(out.texPath, 'file') == 2);
        end
    end
end
