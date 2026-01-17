classdef PragmasDashboard < matlab.apps.AppBase

    % PRAGMAS-SUITE INTERACTIVE DASHBOARD
    % 
    % Purpose: Provides interactive GUI for Phase 4 rigorous validation
    % Solves: Batch script inefficiency, parameter tracking, reproducibility
    %
    % Usage:
    %   app = PragmasDashboard;
    %   or: appdesigner PragmasDashboard.mlapp
    %
    % Features:
    %   - Interactive phase execution (no manual script editing)
    %   - Parameter input via UI (symbol, horizon, risk aversion, etc.)
    %   - Automatic logging of all runs (CSV + parameters JSON)
    %   - Real-time plots (cumulative returns, drawdown, regimes)
    %   - Results table (DM test, Sharpe, MDD, coverage)
    %   - Error handling + progress tracking
    %
    % MVC Architecture:
    %   Model: pragmas engines (DataFetcher, DeepEngineQuantile, etc.)
    %   View: UIAxes, UITable, EditFields, Buttons
    %   Controller: Callbacks that orchestrate model + view

    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        MainGridLayout              matlab.ui.container.GridLayout
    end

    properties (Access = private)
        % LEFT PANEL: Controls
        ControlPanel                matlab.ui.container.Panel
        ControlGridLayout           matlab.ui.container.GridLayout
        
        % Data Input Section
        DataInputLabel              matlab.ui.control.Label
        SymbolLabel                 matlab.ui.control.Label
        SymbolEditField             matlab.ui.control.EditField
        StartDateLabel              matlab.ui.control.Label
        StartDatePicker             matlab.ui.control.DatePicker
        EndDateLabel                matlab.ui.control.Label
        EndDatePicker               matlab.ui.control.DatePicker
        AssetTypeLabel              matlab.ui.control.Label
        AssetTypeDropdown           matlab.ui.control.DropDown
        
        % Validation Parameters Section
        ValidationLabel             matlab.ui.control.Label
        FoldsLabel                  matlab.ui.control.Label
        FoldsSpinner                matlab.ui.control.Spinner
        PacfThresholdLabel          matlab.ui.control.Label
        PacfThresholdSlider         matlab.ui.control.Slider
        HorizonLabel                matlab.ui.control.Label
        HorizonSpinner              matlab.ui.control.Spinner
        
        % Model Parameters Section
        ModelLabel                  matlab.ui.control.Label
        RiskAversionLabel           matlab.ui.control.Label
        RiskAversionSlider          matlab.ui.control.Slider
        VarLevelLabel               matlab.ui.control.Label
        VarLevelSlider              matlab.ui.control.Slider
        LeverageCapLabel            matlab.ui.control.Label
        LeverageCapSlider           matlab.ui.control.Slider
        
        % Buttons Section
        ExecutePhase1Button         matlab.ui.control.Button
        ExecutePhase2Button         matlab.ui.control.Button
        ExecutePhase3Button         matlab.ui.control.Button
        ExecuteFullPipelineButton   matlab.ui.control.Button
        ExportResultsButton         matlab.ui.control.Button
        ClearButton                 matlab.ui.control.Button
        
        % RIGHT PANEL: Results
        ResultPanel                 matlab.ui.container.Panel
        ResultGridLayout            matlab.ui.container.GridLayout
        
        % Tabbed Interface
        TabGroup                    matlab.ui.container.TabGroup
        PlotsTab                    matlab.ui.container.Tab
        ResultsTab                  matlab.ui.container.Tab
        LogsTab                     matlab.ui.container.Tab
        
        % Plots Tab Components
        PlotGridLayout              matlab.ui.container.GridLayout
        PlotAxes1                   matlab.ui.control.UIAxes
        PlotAxes2                   matlab.ui.control.UIAxes
        PlotAxes3                   matlab.ui.control.UIAxes
        PlotAxes4                   matlab.ui.control.UIAxes
        
        % Results Tab Components
        ResultsTable                matlab.ui.control.Table
        MetricsPanel                matlab.ui.container.Panel
        MetricsGridLayout           matlab.ui.container.GridLayout
        
        % Status/Progress
        StatusLabel                 matlab.ui.control.Label
        ProgressBar                 matlab.ui.control.ProgressGauge
        
        % Internal State (Model Data)
        CurrentData                 struct
        CurrentResults              struct
        RunLog                      struct
    end

    methods (Access = public)
        function app = PragmasDashboard()
            createComponents(app);
            registerCallbacks(app);
            
            % Initialize pragmas config
            try
                pragmas_config;
            catch
                uialert(app.UIFigure, 'Warning: pragmas_config not found', 'Startup');
            end
            
            % Initialize internal state
            app.CurrentData = struct();
            app.CurrentResults = struct();
            app.RunLog = struct('runs', {{}},'timestamps', {},'parameters', {});
        end

        function delete(app)
            % Cleanup
        end
    end

    methods (Access = private)
        
        function createComponents(app)
            % UIFigure
            app.UIFigure = uifigure('Name', 'PRAGMAS-SUITE: Phase 4 Rigorous Validation Dashboard', ...
                'NumberTitle', 'off', 'WindowStyle', 'normal');
            app.UIFigure.Position = [100, 50, 1600, 1000];
            app.UIFigure.Color = [0.94, 0.94, 0.94];
            
            % Main Grid: Left (Controls) + Right (Results)
            app.MainGridLayout = uigridlayout(app.UIFigure);
            app.MainGridLayout.ColumnWidth = {400, '1x'};
            app.MainGridLayout.RowHeight = {'1x'};
            app.MainGridLayout.Padding = [10, 10, 10, 10];
            app.MainGridLayout.ColumnSpacing = 10;
            
            % ============= LEFT PANEL: CONTROLS =============
            app.ControlPanel = uipanel(app.MainGridLayout, 'Title', 'CONTROLS & PARAMETERS', ...
                'BackgroundColor', 'white', 'BorderType', 'line');
            app.ControlPanel.Layout.Row = 1;
            app.ControlPanel.Layout.Column = 1;
            
            app.ControlGridLayout = uigridlayout(app.ControlPanel);
            app.ControlGridLayout.ColumnWidth = {'1x'};
            app.ControlGridLayout.RowHeight = repmat({'auto'}, 1, 40);
            app.ControlGridLayout.Padding = [10, 10, 10, 10];
            app.ControlGridLayout.RowSpacing = 5;
            
            % Data Input Section
            row = 1;
            app.DataInputLabel = uilabel(app.ControlGridLayout, 'Text', '📊 DATA INPUT', ...
                'FontWeight', 'bold', 'FontSize', 12, 'FontColor', [0.2, 0.2, 0.8]);
            app.DataInputLabel.Layout.Row = row;
            app.DataInputLabel.Layout.Column = 1;
            
            row = row + 1;
            app.SymbolLabel = uilabel(app.ControlGridLayout, 'Text', 'Symbol:');
            app.SymbolLabel.Layout.Row = row;
            app.SymbolLabel.Layout.Column = 1;
            app.SymbolEditField = uieditfield(app.ControlGridLayout, 'text', 'Value', 'BTC-USD');
            app.SymbolEditField.Layout.Row = row;
            app.SymbolEditField.Layout.Column = 1;
            app.SymbolEditField.HorizontalAlignment = 'right';
            
            row = row + 1;
            app.AssetTypeLabel = uilabel(app.ControlGridLayout, 'Text', 'Asset Type:');
            app.AssetTypeLabel.Layout.Row = row;
            app.AssetTypeLabel.Layout.Column = 1;
            app.AssetTypeDropdown = uidropdown(app.ControlGridLayout, ...
                'Items', {'crypto', 'forex', 'stock', 'futures'}, 'Value', 'crypto');
            app.AssetTypeDropdown.Layout.Row = row;
            app.AssetTypeDropdown.Layout.Column = 1;
            
            row = row + 1;
            app.StartDateLabel = uilabel(app.ControlGridLayout, 'Text', 'Start Date:');
            app.StartDateLabel.Layout.Row = row;
            app.StartDateLabel.Layout.Column = 1;
            app.StartDatePicker = uidatepicker(app.ControlGridLayout, 'Value', datetime(2020, 1, 1));
            app.StartDatePicker.Layout.Row = row;
            app.StartDatePicker.Layout.Column = 1;
            
            row = row + 1;
            app.EndDateLabel = uilabel(app.ControlGridLayout, 'Text', 'End Date:');
            app.EndDateLabel.Layout.Row = row;
            app.EndDateLabel.Layout.Column = 1;
            app.EndDatePicker = uidatepicker(app.ControlGridLayout, 'Value', datetime('now'));
            app.EndDatePicker.Layout.Row = row;
            app.EndDatePicker.Layout.Column = 1;
            
            % Validation Parameters Section
            row = row + 2;
            app.ValidationLabel = uilabel(app.ControlGridLayout, 'Text', '🔍 VALIDATION PARAMETERS', ...
                'FontWeight', 'bold', 'FontSize', 12, 'FontColor', [0.2, 0.2, 0.8]);
            app.ValidationLabel.Layout.Row = row;
            app.ValidationLabel.Layout.Column = 1;
            
            row = row + 1;
            app.FoldsLabel = uilabel(app.ControlGridLayout, 'Text', 'Purged K-Folds:');
            app.FoldsLabel.Layout.Row = row;
            app.FoldsLabel.Layout.Column = 1;
            app.FoldsSpinner = uispinner(app.ControlGridLayout, 'Value', 5, 'Limits', [2, 10]);
            app.FoldsSpinner.Layout.Row = row;
            app.FoldsSpinner.Layout.Column = 1;
            
            row = row + 1;
            app.PacfThresholdLabel = uilabel(app.ControlGridLayout, ...
                'Text', sprintf('PACF Embargo Threshold: 0.05'));
            app.PacfThresholdLabel.Layout.Row = row;
            app.PacfThresholdLabel.Layout.Column = 1;
            app.PacfThresholdSlider = uislider(app.ControlGridLayout, 'Value', 0.05, ...
                'Limits', [0.01, 0.20], 'MajorTicks', 0.01:0.04:0.20);
            app.PacfThresholdSlider.Layout.Row = row;
            app.PacfThresholdSlider.Layout.Column = 1;
            
            row = row + 1;
            app.HorizonLabel = uilabel(app.ControlGridLayout, 'Text', 'Forecast Horizon (days):');
            app.HorizonLabel.Layout.Row = row;
            app.HorizonLabel.Layout.Column = 1;
            app.HorizonSpinner = uispinner(app.ControlGridLayout, 'Value', 20, 'Limits', [1, 100]);
            app.HorizonSpinner.Layout.Row = row;
            app.HorizonSpinner.Layout.Column = 1;
            
            % Model Parameters Section
            row = row + 2;
            app.ModelLabel = uilabel(app.ControlGridLayout, 'Text', '⚙️ MODEL PARAMETERS', ...
                'FontWeight', 'bold', 'FontSize', 12, 'FontColor', [0.2, 0.2, 0.8]);
            app.ModelLabel.Layout.Row = row;
            app.ModelLabel.Layout.Column = 1;
            
            row = row + 1;
            app.RiskAversionLabel = uilabel(app.ControlGridLayout, 'Text', 'Risk Aversion (λ): 2.0');
            app.RiskAversionLabel.Layout.Row = row;
            app.RiskAversionLabel.Layout.Column = 1;
            app.RiskAversionSlider = uislider(app.ControlGridLayout, 'Value', 2.0, ...
                'Limits', [0.5, 5.0], 'MajorTicks', 0.5:0.5:5.0);
            app.RiskAversionSlider.Layout.Row = row;
            app.RiskAversionSlider.Layout.Column = 1;
            
            row = row + 1;
            app.VarLevelLabel = uilabel(app.ControlGridLayout, 'Text', 'VaR Confidence: 0.95');
            app.VarLevelLabel.Layout.Row = row;
            app.VarLevelLabel.Layout.Column = 1;
            app.VarLevelSlider = uislider(app.ControlGridLayout, 'Value', 0.95, ...
                'Limits', [0.90, 0.99], 'MajorTicks', 0.90:0.02:0.99);
            app.VarLevelSlider.Layout.Row = row;
            app.VarLevelSlider.Layout.Column = 1;
            
            row = row + 1;
            app.LeverageCapLabel = uilabel(app.ControlGridLayout, 'Text', 'Leverage Cap: 2.0');
            app.LeverageCapLabel.Layout.Row = row;
            app.LeverageCapLabel.Layout.Column = 1;
            app.LeverageCapSlider = uislider(app.ControlGridLayout, 'Value', 2.0, ...
                'Limits', [1.0, 5.0], 'MajorTicks', 1.0:0.5:5.0);
            app.LeverageCapSlider.Layout.Row = row;
            app.LeverageCapSlider.Layout.Column = 1;
            
            % Execution Buttons
            row = row + 2;
            app.ExecutePhase1Button = uibutton(app.ControlGridLayout, 'push', 'Text', '▶ Phase 1: Data Fetch');
            app.ExecutePhase1Button.Layout.Row = row;
            app.ExecutePhase1Button.Layout.Column = 1;
            app.ExecutePhase1Button.BackgroundColor = [0.2, 0.6, 0.9];
            app.ExecutePhase1Button.FontColor = 'white';
            
            row = row + 1;
            app.ExecutePhase2Button = uibutton(app.ControlGridLayout, 'push', 'Text', '▶ Phase 2: Model Fit');
            app.ExecutePhase2Button.Layout.Row = row;
            app.ExecutePhase2Button.Layout.Column = 1;
            app.ExecutePhase2Button.BackgroundColor = [0.2, 0.6, 0.9];
            app.ExecutePhase2Button.FontColor = 'white';
            
            row = row + 1;
            app.ExecutePhase3Button = uibutton(app.ControlGridLayout, 'push', 'Text', '▶ Phase 3: Validation');
            app.ExecutePhase3Button.Layout.Row = row;
            app.ExecutePhase3Button.Layout.Column = 1;
            app.ExecutePhase3Button.BackgroundColor = [0.2, 0.6, 0.9];
            app.ExecutePhase3Button.FontColor = 'white';
            
            row = row + 1;
            app.ExecuteFullPipelineButton = uibutton(app.ControlGridLayout, 'push', 'Text', '▶▶ FULL PIPELINE');
            app.ExecuteFullPipelineButton.Layout.Row = row;
            app.ExecuteFullPipelineButton.Layout.Column = 1;
            app.ExecuteFullPipelineButton.BackgroundColor = [0.0, 0.7, 0.0];
            app.ExecuteFullPipelineButton.FontColor = 'white';
            app.ExecuteFullPipelineButton.FontWeight = 'bold';
            
            row = row + 1;
            app.ExportResultsButton = uibutton(app.ControlGridLayout, 'push', 'Text', '💾 Export Results');
            app.ExportResultsButton.Layout.Row = row;
            app.ExportResultsButton.Layout.Column = 1;
            app.ExportResultsButton.BackgroundColor = [0.8, 0.6, 0.2];
            
            row = row + 1;
            app.ClearButton = uibutton(app.ControlGridLayout, 'push', 'Text', '🗑️ Clear All');
            app.ClearButton.Layout.Row = row;
            app.ClearButton.Layout.Column = 1;
            app.ClearButton.BackgroundColor = [0.9, 0.3, 0.3];
            app.ClearButton.FontColor = 'white';
            
            % Status
            row = row + 1;
            app.StatusLabel = uilabel(app.ControlGridLayout, 'Text', '⏳ Ready to start...', ...
                'FontColor', [0.4, 0.4, 0.4]);
            app.StatusLabel.Layout.Row = row;
            app.StatusLabel.Layout.Column = 1;
            
            row = row + 1;
            app.ProgressBar = uigauge(app.ControlGridLayout, 'linear', 'Value', 0, 'Limits', [0, 100]);
            app.ProgressBar.Layout.Row = row;
            app.ProgressBar.Layout.Column = 1;
            
            % ============= RIGHT PANEL: RESULTS =============
            app.ResultPanel = uipanel(app.MainGridLayout, 'Title', 'RESULTS & VISUALIZATION', ...
                'BackgroundColor', 'white', 'BorderType', 'line');
            app.ResultPanel.Layout.Row = 1;
            app.ResultPanel.Layout.Column = 2;
            
            % Tab Group
            app.TabGroup = uitabgroup(app.ResultPanel);
            
            % Plots Tab
            app.PlotsTab = uitab(app.TabGroup, 'Title', 'Plots');
            app.PlotGridLayout = uigridlayout(app.PlotsTab);
            app.PlotGridLayout.ColumnWidth = {'1x', '1x'};
            app.PlotGridLayout.RowHeight = {'1x', '1x'};
            app.PlotGridLayout.Padding = [5, 5, 5, 5];
            
            app.PlotAxes1 = uiaxes(app.PlotGridLayout);
            app.PlotAxes1.Layout.Row = 1;
            app.PlotAxes1.Layout.Column = 1;
            app.PlotAxes1.Title.String = 'Cumulative Returns (OOS)';
            
            app.PlotAxes2 = uiaxes(app.PlotGridLayout);
            app.PlotAxes2.Layout.Row = 1;
            app.PlotAxes2.Layout.Column = 2;
            app.PlotAxes2.Title.String = 'Drawdown Path (%)';
            
            app.PlotAxes3 = uiaxes(app.PlotGridLayout);
            app.PlotAxes3.Layout.Row = 2;
            app.PlotAxes3.Layout.Column = 1;
            app.PlotAxes3.Title.String = 'Regime Posteriors';
            
            app.PlotAxes4 = uiaxes(app.PlotGridLayout);
            app.PlotAxes4.Layout.Row = 2;
            app.PlotAxes4.Layout.Column = 2;
            app.PlotAxes4.Title.String = 'Quantile Predictions';
            
            % Results Tab
            app.ResultsTab = uitab(app.TabGroup, 'Title', 'Results Table');
            app.ResultsTable = uitable(app.ResultsTab);
            app.ResultsTable.Position = [0, 0, app.ResultsTab.Position(3), app.ResultsTab.Position(4)];
            app.ResultsTable.ColumnName = {'Metric', 'Value'};
            app.ResultsTable.ColumnWidth = {200, '1x'};
            
            % Logs Tab
            app.LogsTab = uitab(app.TabGroup, 'Title', 'Execution Log');
        end
        
        function registerCallbacks(app)
            % Register all button callbacks
            app.ExecutePhase1Button.ButtonPushedFcn = createCallbackFcn(app, @executePhase1, true);
            app.ExecutePhase2Button.ButtonPushedFcn = createCallbackFcn(app, @executePhase2, true);
            app.ExecutePhase3Button.ButtonPushedFcn = createCallbackFcn(app, @executePhase3, true);
            app.ExecuteFullPipelineButton.ButtonPushedFcn = createCallbackFcn(app, @executeFullPipeline, true);
            app.ExportResultsButton.ButtonPushedFcn = createCallbackFcn(app, @exportResults, true);
            app.ClearButton.ButtonPushedFcn = createCallbackFcn(app, @clearAll, true);
            
            % Register slider callbacks for label updates
            app.PacfThresholdSlider.ValueChangedFcn = createCallbackFcn(app, @updatePacfLabel, true);
            app.RiskAversionSlider.ValueChangedFcn = createCallbackFcn(app, @updateRiskLabel, true);
            app.VarLevelSlider.ValueChangedFcn = createCallbackFcn(app, @updateVarLabel, true);
            app.LeverageCapSlider.ValueChangedFcn = createCallbackFcn(app, @updateLeverageLabel, true);
        end
        
        function updatePacfLabel(app, ~)
            val = app.PacfThresholdSlider.Value;
            app.PacfThresholdLabel.Text = sprintf('PACF Embargo Threshold: %.2f', val);
        end
        
        function updateRiskLabel(app, ~)
            val = app.RiskAversionSlider.Value;
            app.RiskAversionLabel.Text = sprintf('Risk Aversion (λ): %.2f', val);
        end
        
        function updateVarLabel(app, ~)
            val = app.VarLevelSlider.Value;
            app.VarLevelLabel.Text = sprintf('VaR Confidence: %.2f', val);
        end
        
        function updateLeverageLabel(app, ~)
            val = app.LeverageCapSlider.Value;
            app.LeverageCapLabel.Text = sprintf('Leverage Cap: %.2f', val);
        end
        
        function executePhase1(app, ~)
            % Phase 1: Data Fetch
            updateStatus(app, '▶ Executing Phase 1: Data Fetch...');
            updateProgress(app, 20);
            
            try
                symbol = app.SymbolEditField.Value;
                startDate = app.StartDatePicker.Value;
                endDate = app.EndDatePicker.Value;
                assetType = app.AssetTypeDropdown.Value;
                
                % Data fetching
                fetcher = pragmas.data.DataFetcher(symbol, startDate, endDate, assetType);
                fetcher.fetchAsync();
                data = fetcher.DataTables{1};
                
                % Store results
                app.CurrentData.prices = data;
                app.CurrentData.logReturns = diff(log(data.Close));
                app.CurrentData.hurst = pragmas.data.computeHurst(app.CurrentData.logReturns);
                
                % Plot
                plot(app.PlotAxes1, data.Date, data.Close, 'k-', 'LineWidth', 1.5);
                app.PlotAxes1.Title.String = sprintf('%s Price History', symbol);
                xlabel(app.PlotAxes1, 'Date');
                ylabel(app.PlotAxes1, 'Price');
                grid(app.PlotAxes1, 'on');
                
                % Log
                logRun(app, 'Phase 1: Data Fetch', struct(...
                    'symbol', symbol, ...
                    'startDate', startDate, ...
                    'endDate', endDate, ...
                    'assetType', assetType, ...
                    'nObservations', length(app.CurrentData.logReturns), ...
                    'hurst', app.CurrentData.hurst));
                
                updateStatus(app, '✓ Phase 1 complete. Fetched ' + string(length(app.CurrentData.logReturns)) + ' observations.');
                updateProgress(app, 100);
                
            catch ME
                uialert(app.UIFigure, ME.message, 'Phase 1 Error');
                updateStatus(app, '✗ Phase 1 failed: ' + string(ME.message));
            end
        end
        
        function executePhase2(app, ~)
            % Phase 2: Model Fitting
            updateStatus(app, '▶ Executing Phase 2: Model Fit...');
            updateProgress(app, 40);
            
            try
                if isempty(app.CurrentData.logReturns)
                    uialert(app.UIFigure, 'Run Phase 1 first to fetch data', 'Missing Data');
                    return;
                end
                
                logRet = app.CurrentData.logReturns;
                
                % ARIMA Model
                paramEngine = pragmas.models.ModelEngineLogReturns(logRet, 'Asset');
                paramEngine.fit();
                [forecast_arima, ci_lower, ci_upper] = paramEngine.predictWithCI(20);
                
                % Bayesian HMM
                bayesDetector = pragmas.regimes.BayesianMarkovRegimeDetector(logRet, 'num_regimes', 3);
                bayesDetector.estimate('max_iter', 20);
                
                % Store
                app.CurrentData.paramEngine = paramEngine;
                app.CurrentData.bayesDetector = bayesDetector;
                
                % Plot regimes
                [~, regime_seq] = max(bayesDetector.SmoothedProb, [], 2);
                plot(app.PlotAxes3, regime_seq, 'o-', 'LineWidth', 1);
                app.PlotAxes3.Title.String = 'Dominant Regime Over Time';
                ylabel(app.PlotAxes3, 'Regime (1=Bull, 2=Bear, 3=Sideways)');
                grid(app.PlotAxes3, 'on');
                
                % Log
                logRun(app, 'Phase 2: Model Fit', struct(...
                    'arimaOrder', paramEngine.ARIMAOrder, ...
                    'numRegimes', bayesDetector.NumRegimes, ...
                    'meanRegimeEntropy', mean(bayesDetector.RegimeEntropy)));
                
                updateStatus(app, '✓ Phase 2 complete. Models fitted.');
                updateProgress(app, 100);
                
            catch ME
                uialert(app.UIFigure, ME.message, 'Phase 2 Error');
                updateStatus(app, '✗ Phase 2 failed: ' + string(ME.message));
            end
        end
        
        function executePhase3(app, ~)
            % Phase 3: Walk-Forward Validation
            updateStatus(app, '▶ Executing Phase 3: Validation...');
            updateProgress(app, 60);
            
            try
                if isempty(app.CurrentData.logReturns) || isempty(app.CurrentData.paramEngine)
                    uialert(app.UIFigure, 'Run Phases 1 & 2 first', 'Missing Data');
                    return;
                end
                
                logRet = app.CurrentData.logReturns;
                nFolds = app.FoldsSpinner.Value;
                pacfThreshold = app.PacfThresholdSlider.Value;
                
                % TimeSeriesCrossValidator
                cv = pragmas.validation.TimeSeriesCrossValidator(logRet, nFolds, pacfThreshold);
                
                % Diebold-Mariano Test
                null_forecast = pragmas.benchmarks.NullBenchmarks.randomWalkWithDrift(logRet, 100);
                dm_test = pragmas.validation.DieboldMarianoBootstrap(...
                    logRet(1:100), null_forecast, 'loss', 'mse');
                dm_test.test('n_bootstrap', 1000);
                
                % AsymmetricLossValidator
                asym_val = pragmas.validation.AsymmetricLossValidator();
                
                % UtilityBasedValidator
                util_val = pragmas.validation.UtilityBasedValidator(...
                    'var_confidence', app.VarLevelSlider.Value, ...
                    'leverage_constraint', app.LeverageCapSlider.Value);
                
                % Store
                app.CurrentData.cv = cv;
                app.CurrentData.dm_test = dm_test;
                
                % Plot drawdown (example)
                cumReturns = cumprod(1 + logRet(end-99:end));
                maxDD = (cumReturns - cummax(cumReturns)) ./ cummax(cumReturns);
                fill(app.PlotAxes2, 1:length(maxDD), maxDD*100, 'r', 'FaceAlpha', 0.3);
                yline(app.PlotAxes2, -20, 'r--', 'Limit (-20%)');
                app.PlotAxes2.Title.String = 'Maximum Drawdown (%)';
                ylabel(app.PlotAxes2, 'Drawdown (%)');
                grid(app.PlotAxes2, 'on');
                
                % Results Table
                results_data = {
                    'Embargo Size (lags)', cv.embargo_size;
                    'DM Statistic', dm_test.dm_statistic;
                    'DM p-value (asymptotic)', dm_test.p_asymptotic;
                    'DM p-value (bootstrap)', dm_test.p_bootstrap;
                    'Market Efficiency?', 'Check if p > 0.05'
                };
                app.ResultsTable.Data = results_data;
                
                % Log
                logRun(app, 'Phase 3: Validation', struct(...
                    'nFolds', nFolds, ...
                    'pacfThreshold', pacfThreshold, ...
                    'embargo_size', cv.embargo_size, ...
                    'dm_pvalue', dm_test.p_asymptotic));
                
                updateStatus(app, sprintf('✓ Phase 3 complete. DM p-value: %.4f', dm_test.p_asymptotic));
                updateProgress(app, 100);
                
            catch ME
                uialert(app.UIFigure, ME.message, 'Phase 3 Error');
                updateStatus(app, '✗ Phase 3 failed: ' + string(ME.message));
            end
        end
        
        function executeFullPipeline(app, ~)
            % Full Pipeline: Phase 1 + 2 + 3
            updateStatus(app, '▶▶ FULL PIPELINE EXECUTING...');
            updateProgress(app, 0);
            
            executePhase1(app);
            updateProgress(app, 33);
            pause(0.5);
            
            executePhase2(app);
            updateProgress(app, 66);
            pause(0.5);
            
            executePhase3(app);
            updateProgress(app, 100);
            
            updateStatus(app, '✓✓ FULL PIPELINE COMPLETE');
        end
        
        function exportResults(app, ~)
            % Export results to CSV + JSON
            try
                if isempty(app.CurrentResults)
                    uialert(app.UIFigure, 'No results to export. Run pipeline first.', 'No Results');
                    return;
                end
                
                % Save to current directory
                timestamp = datetime('now', 'Format', 'yyyyMMdd_HHmmss');
                
                % Results table
                if ~isempty(app.ResultsTable.Data)
                    writetable(array2table(app.ResultsTable.Data), ...
                        sprintf('pragmas_results_%s.csv', timestamp));
                end
                
                % Parameters JSON
                params = struct(...
                    'symbol', app.SymbolEditField.Value, ...
                    'nFolds', app.FoldsSpinner.Value, ...
                    'pacfThreshold', app.PacfThresholdSlider.Value, ...
                    'horizon', app.HorizonSpinner.Value, ...
                    'riskAversion', app.RiskAversionSlider.Value, ...
                    'varConfidence', app.VarLevelSlider.Value, ...
                    'leverageCap', app.LeverageCapSlider.Value, ...
                    'timestamp', string(timestamp));
                
                json_str = jsonencode(params);
                fid = fopen(sprintf('pragmas_params_%s.json', timestamp), 'w');
                fprintf(fid, '%s', json_str);
                fclose(fid);
                
                updateStatus(app, sprintf('✓ Results exported (%s)', timestamp));
                
            catch ME
                uialert(app.UIFigure, ME.message, 'Export Error');
            end
        end
        
        function clearAll(app, ~)
            % Clear all results and state
            response = uiconfirm(app.UIFigure, 'Clear all results and restart?', 'Confirm Clear');
            if strcmp(response, 'OK')
                app.CurrentData = struct();
                app.CurrentResults = struct();
                
                cla(app.PlotAxes1);
                cla(app.PlotAxes2);
                cla(app.PlotAxes3);
                cla(app.PlotAxes4);
                
                app.ResultsTable.Data = {};
                updateStatus(app, '✓ All data cleared. Ready to start fresh.');
                updateProgress(app, 0);
            end
        end
        
        function updateStatus(app, msg)
            app.StatusLabel.Text = msg;
            drawnow;
        end
        
        function updateProgress(app, val)
            app.ProgressBar.Value = val;
            drawnow;
        end
        
        function logRun(app, phase, params)
            % Log execution for reproducibility
            if ~isfield(app.RunLog, 'runs') || isempty(app.RunLog.runs)
                app.RunLog.runs = {struct()};
                app.RunLog.timestamps = datetime('now');
                app.RunLog.parameters = {params};
            else
                app.RunLog.runs{end+1} = struct('phase', phase);
                app.RunLog.timestamps(end+1) = datetime('now');
                app.RunLog.parameters{end+1} = params;
            end
        end
    end

    methods (Static)
        function app = launch()
            % Static method to launch app
            app = PragmasDashboard();
        end
    end
end
