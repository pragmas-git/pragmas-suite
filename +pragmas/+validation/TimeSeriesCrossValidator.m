classdef TimeSeriesCrossValidator
    % TimeSeriesCrossValidator: Purged K-Fold with Dynamic Embargo based on PACF
    %
    % Implements rigorous time-series cross-validation avoiding look-ahead bias:
    %   1. Computes dynamic embargo from PACF (max lag where significant)
    %   2. Purged K-Fold: excludes data within embargo of test boundary
    %   3. Walk-forward: always train on past, test on future
    %   4. No overlap: training and test folds are strictly disjoint
    %
    % Reference: López de Prado (2018), Ch. 7; Hastie et al. (2009), Ch. 7
    
    properties
        Series              % Time series data (T x 1)
        N                   % Length of series
        NumFolds            % Number of CV folds
        EmbargoSize         % Computed from PACF (samples to exclude near boundary)
        EmbargoPACFThreshold  % Significance threshold for PACF (default 0.05)
        TrainIndices        % Cell array: train indices for each fold
        TestIndices         % Cell array: test indices for each fold
        FoldSizes           % Size of each fold
        PACFLags            % Computed PACF values
        MaxSignificantLag    % Max lag where PACF significant (determines embargo)
    end
    
    methods
        function obj = TimeSeriesCrossValidator(series, num_folds, pacf_threshold)
            % Constructor
            % Inputs:
            %   series: Time series data (T x 1)
            %   num_folds: Number of CV folds (default: 5)
            %   pacf_threshold: Significance level for PACF (default: 0.05)
            
            if nargin < 2
                num_folds = 5;
            end
            if nargin < 3
                pacf_threshold = 0.05;
            end
            
            obj.Series = series(:);
            obj.N = length(obj.Series);
            obj.NumFolds = num_folds;
            obj.EmbargoPACFThreshold = pacf_threshold;
            
            % Compute embargo based on PACF
            obj = obj.computeDynamicEmbargo();
            
            % Generate purged K-fold indices
            obj = obj.generatePurgedKFold();
        end
        
        function obj = computeDynamicEmbargo(obj)
            % Compute embargo size from PACF of the series
            % Embargo = max lag where |PACF(lag)| > threshold
            %
            % This ensures that test samples are separated from training
            % by at least the maximum autocorrelation persistence
            
            % Compute PACF (up to 20% of series length)
            max_lag = min(floor(obj.N * 0.2), 40);
            
            try
                % Use autocorr function to get PACF
                [~, ~, pacf_vals] = autocorr(obj.Series, 'NumLags', max_lag);
                obj.PACFLags = pacf_vals;
                
                % Find 95% confidence interval for white noise
                % CI = ±1.96 / sqrt(N)
                ci_bound = 1.96 / sqrt(obj.N);
                
                % Find maximum lag where |PACF| > CI
                significant_lags = find(abs(obj.PACFLags) > ci_bound);
                if ~isempty(significant_lags)
                    obj.MaxSignificantLag = max(significant_lags);
                else
                    obj.MaxSignificantLag = 1;
                end
                
                obj.EmbargoSize = obj.MaxSignificantLag;
                
            catch
                % Fallback if autocorr not available
                % Use simple heuristic: embargo = 5% of fold size
                obj.EmbargoSize = max(5, floor(obj.N / (obj.NumFolds * 20)));
                obj.MaxSignificantLag = obj.EmbargoSize;
            end
        end
        
        function obj = generatePurgedKFold(obj)
            % Generate purged K-fold indices
            % Key: test folds are excluded from training, plus embargo zone
            
            obj.TrainIndices = cell(obj.NumFolds, 1);
            obj.TestIndices = cell(obj.NumFolds, 1);
            obj.FoldSizes = zeros(obj.NumFolds, 1);
            
            fold_size = floor(obj.N / obj.NumFolds);
            
            for fold = 1:obj.NumFolds
                % Define test fold boundaries
                test_start = (fold - 1) * fold_size + 1;
                test_end = min(fold * fold_size, obj.N);
                
                if fold == obj.NumFolds
                    test_end = obj.N;  % Last fold gets remaining samples
                end
                
                % Define embargo zone around test fold
                embargo_start = max(1, test_start - obj.EmbargoSize);
                embargo_end = min(obj.N, test_end + obj.EmbargoSize);
                
                % Test indices: strictly within fold
                test_idx = test_start:test_end;
                
                % Train indices: all except test + embargo
                all_idx = 1:obj.N;
                embargo_idx = embargo_start:embargo_end;
                train_idx = setdiff(all_idx, embargo_idx);
                
                % CONSTRAINT: In walk-forward, we can only use PAST data
                % So: train on indices < test_start (strict)
                train_idx = train_idx(train_idx < test_start);
                
                obj.TrainIndices{fold} = train_idx(:);
                obj.TestIndices{fold} = test_idx(:);
                obj.FoldSizes(fold) = length(test_idx);
            end
        end
        
        function folds = getFolds(obj)
            % Return structure with fold information
            folds = struct();
            for fold = 1:obj.NumFolds
                folds(fold).fold_id = fold;
                folds(fold).train_idx = obj.TrainIndices{fold};
                folds(fold).test_idx = obj.TestIndices{fold};
                folds(fold).n_train = length(obj.TrainIndices{fold});
                folds(fold).n_test = length(obj.TestIndices{fold});
            end
        end
        
        function [train_data, test_data] = getFoldData(obj, fold_id, data)
            % Get train/test data for specific fold
            % Inputs:
            %   fold_id: Fold number (1 to NumFolds)
            %   data: Data matrix (T x P)
            % Outputs:
            %   train_data: Training data
            %   test_data: Test data
            
            if fold_id < 1 || fold_id > obj.NumFolds
                error('Fold ID out of range [1, %d]', obj.NumFolds);
            end
            
            train_idx = obj.TrainIndices{fold_id};
            test_idx = obj.TestIndices{fold_id};
            
            train_data = data(train_idx, :);
            test_data = data(test_idx, :);
        end
        
        function results = walkForwardBacktest(obj, model_cell, data, varargin)
            % Execute walk-forward backtest
            % Inputs:
            %   model_cell: Cell array of models (each has .fit() and .predict())
            %   data: Data matrix or timetable (T x P)
            %   Optional:
            %     'verbose': true/false (default: false)
            %     'parallel': true/false (default: false)
            %
            % Outputs:
            %   results: Struct with predictions, actuals, and metrics
            
            p = inputParser();
            addParameter(p, 'verbose', false, @islogical);
            addParameter(p, 'parallel', false, @islogical);
            parse(p, varargin{:});
            
            verbose = p.Results.verbose;
            parallel_flag = p.Results.parallel;
            
            if istimetable(data)
                data_values = table2array(data);
            else
                data_values = data;
            end
            
            num_models = length(model_cell);
            
            % Initialize results
            results = struct();
            results.model_names = cell(num_models, 1);
            results.predictions = cell(num_models, 1);
            results.actuals = cell(num_models, 1);
            results.errors = cell(num_models, 1);
            
            for m = 1:num_models
                results.model_names{m} = model_cell{m}.name;
                results.predictions{m} = [];
                results.actuals{m} = [];
                results.errors{m} = [];
            end
            
            if verbose
                fprintf('Starting walk-forward backtest with %d folds, %d models\n', ...
                    obj.NumFolds, num_models);
                fprintf('Embargo size: %d lags (from PACF max lag = %d)\n', ...
                    obj.EmbargoSize, obj.MaxSignificantLag);
            end
            
            % Walk-forward loop
            if parallel_flag && obj.NumFolds > 1
                % Parallel loop (if Parallel Computing Toolbox available)
                parfor fold = 1:obj.NumFolds
                    [train_data, test_data] = obj.getFoldData(fold, data_values);
                    fold_results = process_fold(fold, model_cell, train_data, test_data);
                    results_by_fold{fold} = fold_results;
                end
                
                % Aggregate results
                for fold = 1:obj.NumFolds
                    fold_res = results_by_fold{fold};
                    for m = 1:num_models
                        results.predictions{m} = [results.predictions{m}; ...
                            fold_res.predictions{m}];
                        results.actuals{m} = [results.actuals{m}; ...
                            fold_res.actuals{m}];
                        results.errors{m} = [results.errors{m}; ...
                            fold_res.errors{m}];
                    end
                end
            else
                % Sequential loop
                for fold = 1:obj.NumFolds
                    [train_data, test_data] = obj.getFoldData(fold, data_values);
                    
                    if verbose
                        fprintf('  Fold %d/%d: train [%d samples], test [%d samples]\n', ...
                            fold, obj.NumFolds, size(train_data, 1), size(test_data, 1));
                    end
                    
                    % Process each model
                    for m = 1:num_models
                        model = model_cell{m};
                        
                        % Train on in-sample
                        try
                            model.fit(train_data);
                        catch ME
                            warning('Model %s failed to train on fold %d: %s', ...
                                model.name, fold, ME.message);
                            continue;
                        end
                        
                        % Predict on out-of-sample
                        try
                            pred_fold = model.predict(test_data);
                        catch ME
                            warning('Model %s failed to predict on fold %d: %s', ...
                                model.name, fold, ME.message);
                            continue;
                        end
                        
                        % Get actuals (last column assumed to be target)
                        actuals_fold = test_data(:, end);
                        
                        % Accumulate
                        results.predictions{m} = [results.predictions{m}; pred_fold];
                        results.actuals{m} = [results.actuals{m}; actuals_fold];
                        results.errors{m} = [results.errors{m}; pred_fold - actuals_fold];
                    end
                end
            end
            
            % Compute OOS metrics
            results.oos_metrics = struct();
            for m = 1:num_models
                model_name = results.model_names{m};
                pred = results.predictions{m};
                actual = results.actuals{m};
                err = results.errors{m};
                
                if ~isempty(pred)
                    % RMSE
                    results.oos_metrics.(matlab.lang.makeValidName(model_name)).rmse = ...
                        sqrt(mean(err.^2));
                    
                    % MAE
                    results.oos_metrics.(matlab.lang.makeValidName(model_name)).mae = ...
                        mean(abs(err));
                    
                    % Directional Accuracy
                    if length(actual) > 1
                        direction_actual = sign(diff(actual));
                        direction_pred = sign(diff(pred));
                        hit_rate = mean(direction_actual == direction_pred);
                        results.oos_metrics.(matlab.lang.makeValidName(model_name)).hit_rate = hit_rate;
                    end
                    
                    % Sharpe Ratio (assuming returns)
                    if std(actual) > 0
                        sharpe = mean(actual) / std(actual) * sqrt(252);
                        results.oos_metrics.(matlab.lang.makeValidName(model_name)).sharpe = sharpe;
                    end
                end
            end
            
            if verbose
                fprintf('\nWalk-forward backtest completed.\n');
            end
        end
        
        function plot_embargo_info(obj)
            % Visualize embargo size and PACF
            figure('Name', 'Time Series CV: Embargo & PACF', 'NumberTitle', 'off');
            
            % Subplot 1: PACF
            subplot(1, 2, 1);
            if ~isempty(obj.PACFLags)
                stem(obj.PACFLags, 'filled');
                hold on;
                ci_bound = 1.96 / sqrt(obj.N);
                yline(ci_bound, 'r--', 'LineWidth', 1.5);
                yline(-ci_bound, 'r--', 'LineWidth', 1.5);
                yline(0, 'k-', 'LineWidth', 0.5);
                xlabel('Lag');
                ylabel('PACF');
                title(sprintf('Partial ACF (Max Significant Lag: %d)', obj.MaxSignificantLag));
                grid on;
            end
            
            % Subplot 2: Fold structure with embargo
            subplot(1, 2, 2);
            fold_size = floor(obj.N / obj.NumFolds);
            colors = jet(obj.NumFolds);
            
            for fold = 1:obj.NumFolds
                test_idx = obj.TestIndices{fold};
                train_idx = obj.TrainIndices{fold};
                
                % Plot test fold
                scatter(test_idx, fold * ones(size(test_idx)), 50, colors(fold, :), 'filled');
                hold on;
                
                % Plot embargo zone
                test_start = min(test_idx);
                embargo_start = max(1, test_start - obj.EmbargoSize);
                embargo_idx = embargo_start:(test_start-1);
                scatter(embargo_idx, fold * ones(size(embargo_idx)), 20, ...
                    colors(fold, :) * 0.5, 'x', 'LineWidth', 2);
            end
            
            xlabel('Time Index');
            ylabel('Fold Number');
            title(sprintf('Purged K-Fold Structure (Embargo: %d samples)', obj.EmbargoSize));
            ylim([0.5, obj.NumFolds + 0.5]);
            grid on;
        end
    end
    
    methods (Static)
        function fold_results = process_fold(fold, model_cell, train_data, test_data)
            % Process single fold for all models (helper for parallel processing)
            num_models = length(model_cell);
            fold_results = struct();
            fold_results.predictions = cell(num_models, 1);
            fold_results.actuals = cell(num_models, 1);
            fold_results.errors = cell(num_models, 1);
            
            for m = 1:num_models
                model = model_cell{m};
                model.fit(train_data);
                pred_fold = model.predict(test_data);
                actuals_fold = test_data(:, end);
                
                fold_results.predictions{m} = pred_fold;
                fold_results.actuals{m} = actuals_fold;
                fold_results.errors{m} = pred_fold - actuals_fold;
            end
        end
    end
end
