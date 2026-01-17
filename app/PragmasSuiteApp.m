classdef PragmasSuiteApp < matlab.apps.AppBase
    %PRAGMASSUITEAPP Interactive control for pragmas-suite FX research.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        Grid matlab.ui.container.GridLayout

        LeftPanel matlab.ui.container.Panel
        RightPanel matlab.ui.container.Panel

        Tabs matlab.ui.container.TabGroup
        TabData matlab.ui.container.Tab
        TabModels matlab.ui.container.Tab
        TabRun matlab.ui.container.Tab
        TabExport matlab.ui.container.Tab

        % Data/QC UI
        BtnLoadProcessed matlab.ui.control.Button
        BtnBuildQC matlab.ui.control.Button
        BtnRefreshQC matlab.ui.control.Button
        QCTable matlab.ui.control.Table
        QCStatus matlab.ui.control.Label

        % Model UI
        DropBaseline matlab.ui.control.DropDown
        DropHybrid matlab.ui.control.DropDown
        ModelStatus matlab.ui.control.Label

        % Params UI
        SeedField matlab.ui.control.NumericEditField
        AlphaField matlab.ui.control.NumericEditField
        TrainField matlab.ui.control.NumericEditField
        TestField matlab.ui.control.NumericEditField
        StepField matlab.ui.control.NumericEditField

        % Run UI
        BtnRunExperiment matlab.ui.control.Button
        SummaryTable matlab.ui.control.Table
        RunStatus matlab.ui.control.Label
        AssetDrop matlab.ui.control.DropDown

        % Viz
        VizTabs matlab.ui.container.TabGroup
        TabQCPlots matlab.ui.container.Tab
        TabCRPS matlab.ui.container.Tab
        TabVaR matlab.ui.container.Tab
        AxQC matlab.ui.control.UIAxes
        AxCRPS matlab.ui.control.UIAxes
        AxVaR matlab.ui.control.UIAxes

        % Export UI
        BtnExportLatex matlab.ui.control.Button
        ExportStatus matlab.ui.control.Label
        CompilePdfCheck matlab.ui.control.CheckBox
    end

    properties (Access = private)
        cfg struct
        pricesTT timetable
        qcReport struct
        results struct
        lastReportOut struct
    end

    methods (Access = private)
        function startup(app)
            app.cfg = config();
            app.syncCfgToUI();
            app.refreshQcTableFromDisk();
            app.ModelStatus.Text = 'Model selection: only GARCH + GARCH+KDE are wired right now.';
            app.RunStatus.Text = 'Ready.';
        end

        function syncCfgToUI(app)
            app.SeedField.Value = double(app.cfg.seed);
            app.AlphaField.Value = double(app.cfg.alpha);
            app.TrainField.Value = double(app.cfg.rolling.train);
            app.TestField.Value = double(app.cfg.rolling.test);
            app.StepField.Value = double(app.cfg.rolling.step);
        end

        function syncUIToCfg(app)
            app.cfg.seed = double(app.SeedField.Value);
            app.cfg.alpha = double(app.AlphaField.Value);
            app.cfg.rolling.train = double(app.TrainField.Value);
            app.cfg.rolling.test = double(app.TestField.Value);
            app.cfg.rolling.step = double(app.StepField.Value);

            % keep backward-compat aliases used elsewhere
            app.cfg.windowTrain = app.cfg.rolling.train;
            app.cfg.windowTest = app.cfg.rolling.test;
            app.cfg.rebalance = app.cfg.rolling.step;
        end

        function refreshQcTableFromDisk(app)
            try
                report = load_data_quality_report(app.cfg);
                if isfield(report, 'dataQualitySummary') && istable(report.dataQualitySummary)
                    app.qcReport = report;
                    app.QCTable.Data = report.dataQualitySummary;
                    app.QCStatus.Text = 'Loaded QC report from disk.';
                else
                    app.QCStatus.Text = 'No QC report found yet. Click Build QC.';
                end
            catch ME
                app.QCStatus.Text = string(ME.message);
            end
        end

        function plotQc(app)
            cla(app.AxQC);
            if isempty(app.qcReport) || ~isfield(app.qcReport, 'qc')
                title(app.AxQC, 'No QC loaded');
                return;
            end

            % Quick plot: spread bps boxplot using stored samples (first panel only)
            spreads = [];
            groups = strings(0,1);
            try
                qcs = app.qcReport.qc;
                for a = 1:numel(qcs)
                    qc = qcs{a};
                    if isfield(qc, 'spreadBpsSample')
                        sp = qc.spreadBpsSample;
                    else
                        sp = [];
                    end
                    sp = sp(:);
                    sp = sp(isfinite(sp) & sp >= 0);
                    if isempty(sp)
                        continue;
                    end
                    spreads = [spreads; sp]; %#ok<AGROW>
                    groups = [groups; repmat(string(qc.asset), numel(sp), 1)]; %#ok<AGROW>
                end
            catch
            end

            if isempty(spreads)
                title(app.AxQC, 'QC loaded, but no spread samples to plot.');
                return;
            end

            boxchart(app.AxQC, categorical(groups), spreads);
            ylabel(app.AxQC, 'Spread (bps)');
            title(app.AxQC, 'Spread (bps) by asset (sampled)');
            grid(app.AxQC, 'on');
        end

        function plotCrpsAndVar(app)
            if isempty(app.results)
                return;
            end
            asset = string(app.AssetDrop.Value);
            if ~isfield(app.results.series, char(asset))
                return;
            end

            s = app.results.series.(char(asset));

            cla(app.AxCRPS);
            plot(app.AxCRPS, s.crps.Time, s.crps.CRPS_Parametric, 'DisplayName','Parametric'); hold(app.AxCRPS, 'on');
            plot(app.AxCRPS, s.crps.Time, s.crps.CRPS_Hybrid, 'DisplayName','Hybrid');
            hold(app.AxCRPS, 'off');
            legend(app.AxCRPS, 'Location','best');
            grid(app.AxCRPS, 'on');
            title(app.AxCRPS, sprintf('CRPS: %s', asset));

            cla(app.AxVaR);
            plot(app.AxVaR, s.var.Time, s.var.VaR_Parametric, 'DisplayName','VaR Parametric'); hold(app.AxVaR, 'on');
            plot(app.AxVaR, s.var.Time, s.var.VaR_Hybrid, 'DisplayName','VaR Hybrid');
            hold(app.AxVaR, 'off');
            legend(app.AxVaR, 'Location','best');
            grid(app.AxVaR, 'on');
            title(app.AxVaR, sprintf('VaR: %s (alpha=%.2f)', asset, app.cfg.alpha));
        end

        % --- Callbacks ---
        function onLoadProcessed(app, ~, ~)
            app.syncUIToCfg();
            app.QCStatus.Text = 'Loading processed data...';
            drawnow;
            try
                app.pricesTT = load_data(app.cfg);
                app.QCStatus.Text = 'Loaded daily close data.';
            catch ME
                app.QCStatus.Text = string(ME.message);
            end
        end

        function onBuildQC(app, ~, ~)
            app.syncUIToCfg();
            app.QCStatus.Text = 'Building daily close + QC from parquet...';
            drawnow;
            try
                [app.pricesTT, app.qcReport] = build_fx_daily_close_from_parquet(app.cfg);
                if isfield(app.qcReport, 'dataQualitySummary')
                    app.QCTable.Data = app.qcReport.dataQualitySummary;
                end
                app.QCStatus.Text = 'QC build complete. Reports saved to results/.';
                app.plotQc();
            catch ME
                app.QCStatus.Text = string(ME.message);
            end
        end

        function onRefreshQC(app, ~, ~)
            app.syncUIToCfg();
            app.refreshQcTableFromDisk();
            app.plotQc();
        end

        function onRunExperiment(app, ~, ~)
            app.syncUIToCfg();

            % Model dropdowns are future-proofed; current pipeline uses fixed models.
            app.RunStatus.Text = 'Running experiment (VaR+CRPS)...';
            drawnow;
            try
                [app.results, ~] = run_experiment_var_crps(app.cfg, 'doPlots', false, 'nSamp', 800);
                app.SummaryTable.Data = app.results.evaluation.summary;

                assets = string(app.results.evaluation.summary.Asset);
                app.AssetDrop.Items = cellstr(assets);
                app.AssetDrop.Value = char(assets(1));

                app.RunStatus.Text = 'Experiment finished and saved to results/.';
                app.plotCrpsAndVar();
            catch ME
                app.RunStatus.Text = string(ME.message);
            end
        end

        function onAssetChanged(app, ~, ~)
            app.plotCrpsAndVar();
        end

        function onExportLatex(app, ~, ~)
            app.syncUIToCfg();
            if isempty(app.results)
                app.ExportStatus.Text = 'Run an experiment first.';
                return;
            end

            app.ExportStatus.Text = 'Generating LaTeX report...';
            drawnow;
            try
                out = generate_latex_report(app.results, app.cfg, 'outputDir', string(app.cfg.resultsDir), 'compile', logical(app.CompilePdfCheck.Value));
                app.lastReportOut = out;
                if isfield(out, 'compiled') && out.compiled
                    app.ExportStatus.Text = "Report compiled: " + string(out.pdfPath);
                else
                    app.ExportStatus.Text = "LaTeX written: " + string(out.texPath);
                end
            catch ME
                app.ExportStatus.Text = string(ME.message);
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'Pragmas Suite FX Research', 'Position', [100 100 1200 700]);
            app.Grid = uigridlayout(app.UIFigure, [1 2]);
            app.Grid.ColumnWidth = {'0.38x', '0.62x'};

            app.LeftPanel = uipanel(app.Grid, 'Title', 'Controls');
            app.RightPanel = uipanel(app.Grid, 'Title', 'Visualizations');

            app.Tabs = uitabgroup(app.LeftPanel);
            app.Tabs.Position = [10 10 440 640];

            app.TabData = uitab(app.Tabs, 'Title', 'Load & QC');
            app.TabModels = uitab(app.Tabs, 'Title', 'Models');
            app.TabRun = uitab(app.Tabs, 'Title', 'Run');
            app.TabExport = uitab(app.Tabs, 'Title', 'Export');

            % --- Data tab ---
            app.BtnLoadProcessed = uibutton(app.TabData, 'Text', 'Load Processed Data', 'Position', [10 590 200 30], ...
                'ButtonPushedFcn', @(s,e) app.onLoadProcessed(s,e));
            app.BtnBuildQC = uibutton(app.TabData, 'Text', 'Build Daily Close + QC', 'Position', [220 590 200 30], ...
                'ButtonPushedFcn', @(s,e) app.onBuildQC(s,e));
            app.BtnRefreshQC = uibutton(app.TabData, 'Text', 'Refresh QC from Disk', 'Position', [10 555 200 30], ...
                'ButtonPushedFcn', @(s,e) app.onRefreshQC(s,e));

            app.QCStatus = uilabel(app.TabData, 'Position', [10 525 410 22], 'Text', '');
            app.QCTable = uitable(app.TabData, 'Position', [10 10 410 510]);

            % --- Models tab ---
            uilabel(app.TabModels, 'Position', [10 595 120 22], 'Text', 'Baseline:');
            app.DropBaseline = uidropdown(app.TabModels, 'Position', [140 595 280 22], 'Items', {'GARCH'}, 'Value', 'GARCH');
            uilabel(app.TabModels, 'Position', [10 560 120 22], 'Text', 'Hybrid:');
            app.DropHybrid = uidropdown(app.TabModels, 'Position', [140 560 280 22], 'Items', {'GARCH+KDE'}, 'Value', 'GARCH+KDE');
            app.ModelStatus = uilabel(app.TabModels, 'Position', [10 520 410 40], 'Text', '');

            % --- Run tab ---
            uilabel(app.TabRun, 'Position', [10 595 120 22], 'Text', 'Seed');
            app.SeedField = uieditfield(app.TabRun, 'numeric', 'Position', [140 595 100 22]);
            uilabel(app.TabRun, 'Position', [260 595 120 22], 'Text', 'Alpha');
            app.AlphaField = uieditfield(app.TabRun, 'numeric', 'Position', [320 595 100 22], 'Limits', [0.0001 0.9999]);

            uilabel(app.TabRun, 'Position', [10 560 120 22], 'Text', 'Train');
            app.TrainField = uieditfield(app.TabRun, 'numeric', 'Position', [140 560 100 22], 'Limits', [10 Inf], 'RoundFractionalValues', 'on');
            uilabel(app.TabRun, 'Position', [260 560 120 22], 'Text', 'Test');
            app.TestField = uieditfield(app.TabRun, 'numeric', 'Position', [320 560 100 22], 'Limits', [1 Inf], 'RoundFractionalValues', 'on');
            uilabel(app.TabRun, 'Position', [10 525 120 22], 'Text', 'Step');
            app.StepField = uieditfield(app.TabRun, 'numeric', 'Position', [140 525 100 22], 'Limits', [1 Inf], 'RoundFractionalValues', 'on');

            app.BtnRunExperiment = uibutton(app.TabRun, 'Text', 'Run Experiment (VaR+CRPS)', 'Position', [10 480 210 30], ...
                'ButtonPushedFcn', @(s,e) app.onRunExperiment(s,e));

            app.RunStatus = uilabel(app.TabRun, 'Position', [10 450 410 22], 'Text', '');

            uilabel(app.TabRun, 'Position', [10 420 120 22], 'Text', 'Asset');
            app.AssetDrop = uidropdown(app.TabRun, 'Position', [140 420 280 22], 'Items', {}, 'ValueChangedFcn', @(s,e) app.onAssetChanged(s,e));

            app.SummaryTable = uitable(app.TabRun, 'Position', [10 10 410 400]);

            % --- Export tab ---
            app.CompilePdfCheck = uicheckbox(app.TabExport, 'Text', 'Compile PDF (pdflatex)', 'Value', true, 'Position', [10 595 200 22]);
            app.BtnExportLatex = uibutton(app.TabExport, 'Text', 'Generate LaTeX Report', 'Position', [10 560 200 30], ...
                'ButtonPushedFcn', @(s,e) app.onExportLatex(s,e));
            app.ExportStatus = uilabel(app.TabExport, 'Position', [10 520 410 40], 'Text', '');

            % --- Right panel: visualizations ---
            app.VizTabs = uitabgroup(app.RightPanel);
            app.VizTabs.Position = [10 10 720 640];

            app.TabQCPlots = uitab(app.VizTabs, 'Title', 'QC');
            app.TabCRPS = uitab(app.VizTabs, 'Title', 'CRPS');
            app.TabVaR = uitab(app.VizTabs, 'Title', 'VaR');

            app.AxQC = uiaxes(app.TabQCPlots, 'Position', [10 10 690 600]);
            app.AxCRPS = uiaxes(app.TabCRPS, 'Position', [10 10 690 600]);
            app.AxVaR = uiaxes(app.TabVaR, 'Position', [10 10 690 600]);
        end
    end

    methods (Access = public)
        function app = PragmasSuiteApp()
            createComponents(app);
            registerApp(app, app.UIFigure);
            startup(app);
        end

        function delete(app)
            try
                delete(app.UIFigure);
            catch
            end
        end
    end
end
