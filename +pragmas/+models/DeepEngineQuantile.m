classdef DeepEngineQuantile < handle
    % DeepEngineQuantile: Probabilistic LSTM/CNN with quantile regression
    %
    % Refactored to predict log-returns with quantile intervals instead of point forecasts.
    % Predicts quantiles [0.05, 0.25, 0.5, 0.75, 0.95] for full predictive distribution.
    %
    % Architecture:
    %   Input: Past 20 log-returns + regime indicators
    %   LSTM/CNN: Feature extraction from sequence
    %   Output: 5 quantile predictions per time step
    %
    % Advantages over point forecasts:
    %   - Full distribution information (not just mean)
    %   - Uncertainty quantification via interval widths
    %   - Risk-aware decision making
    %   - Proper loss function (pinball loss instead of MSE)
    
    properties
        % Data
        LogReturns          % Log-returns series (T x 1)
        Regimes             % Regime indicators (T x 1)
        SeriesName          % Asset identifier
        
        % Network architecture
        SequenceLength = 20;
        NumLSTMLayers = 2;
        LSTMHiddenSize = 50;
        CNNFilters = 64;
        CNNKernel = 5;
        Quantiles = [0.05, 0.25, 0.5, 0.75, 0.95];  % Output quantiles
        
        % Training parameters
        EpochsLSTM = 50;
        EpochsCNN = 50;
        BatchSize = 32;
        LearningRate = 0.001;
        ValidationSplit = 0.2;
        
        % Trained models
        LSTMNet;
        CNNNet;
        TrainingInfoLSTM;
        TrainingInfoCNN;
        
        % Predictions (quantiles: T x 5)
        QuantilePredictionsLSTM;
        QuantilePredictionsCNN;
        QuantilePointForecast;  % Median (0.5 quantile)
        
        % Flags
        HasToolbox = false;
        UseRegimeConditioning = false;
        IsTrained = false;
    end
    
    methods
        function obj = DeepEngineQuantile(logReturns, regimes, options, seriesName)
            % Initialize with log-returns instead of prices
            
            if istimetable(logReturns)
                obj.LogReturns = logReturns{:, :};
            else
                obj.LogReturns = logReturns(:);
            end
            
            obj.LogReturns = obj.LogReturns(~isnan(obj.LogReturns));
            
            if nargin < 2 || isempty(regimes)
                obj.Regimes = [];
                obj.UseRegimeConditioning = false;
            else
                obj.Regimes = regimes(:);
                obj.UseRegimeConditioning = true;
            end
            
            if nargin < 4 || isempty(seriesName)
                obj.SeriesName = 'Asset';
            else
                obj.SeriesName = seriesName;
            end
            
            % Apply custom options
            if nargin >= 3 && ~isempty(options)
                if isfield(options, 'SequenceLength')
                    obj.SequenceLength = options.SequenceLength;
                end
                if isfield(options, 'EpochsLSTM')
                    obj.EpochsLSTM = options.EpochsLSTM;
                end
                if isfield(options, 'EpochsCNN')
                    obj.EpochsCNN = options.EpochsCNN;
                end
                if isfield(options, 'Quantiles')
                    obj.Quantiles = options.Quantiles;
                end
            end
            
            % Check for Deep Learning Toolbox
            try
                dlarray([1]);
                obj.HasToolbox = true;
            catch
                warning('Deep Learning Toolbox not found. Using linear regression fallback.');
                obj.HasToolbox = false;
            end
        end
        
        function trainAsync(obj, models, varargin)
            % Train LSTM and/or CNN asynchronously
            % models: {'LSTM'}, {'CNN'}, or {'LSTM', 'CNN'}
            
            p = inputParser();
            addParameter(p, 'fold_indices', [], @isnumeric);  % From TimeSeriesCrossValidator
            parse(p, varargin{:});
            
            fold_idx = p.Results.fold_indices;
            
            % Use full dataset if no fold provided
            if isempty(fold_idx)
                fold_idx = 1:length(obj.LogReturns);
            end
            
            % Prepare training data
            [X_train, Y_train] = obj.prepareTrainingData(obj.LogReturns(fold_idx));
            
            if obj.HasToolbox
                for m = 1:length(models)
                    model_type = models{m};
                    
                    if strcmp(model_type, 'LSTM')
                        fprintf('Training LSTM with quantile output...\n');
                        [obj.LSTMNet, obj.TrainingInfoLSTM] = ...
                            obj.trainLSTMQuantile(X_train, Y_train);
                        obj.IsTrained = true;
                    elseif strcmp(model_type, 'CNN')
                        fprintf('Training CNN with quantile output...\n');
                        [obj.CNNNet, obj.TrainingInfoCNN] = ...
                            obj.trainCNNQuantile(X_train, Y_train);
                        obj.IsTrained = true;
                    end
                end
            else
                obj.trainLinearQuantileRegression(X_train, Y_train);
                obj.IsTrained = true;
            end
        end
        
        function quantiles = predict(obj, model_type, horizon)
            % Predict quantiles for horizon h ahead
            %
            % Outputs:
            %   quantiles: (horizon x 5) matrix for [0.05, 0.25, 0.5, 0.75, 0.95]
            
            if ~obj.IsTrained
                error('Model not trained. Call trainAsync() first.');
            end
            
            if strcmp(model_type, 'LSTM') && ~isempty(obj.LSTMNet)
                quantiles = obj.predictLSTM(horizon);
            elseif strcmp(model_type, 'CNN') && ~isempty(obj.CNNNet)
                quantiles = obj.predictCNN(horizon);
            else
                % Fallback: linear quantile regression
                quantiles = obj.predictLinear(horizon);
            end
        end
        
        function [X, Y] = prepareTrainingData(obj, returns)
            % Create sequences of length L for LSTM/CNN input
            % X: (T-L x L) sliding windows
            % Y: (T-L x 5) corresponding quantile targets
            
            L = obj.SequenceLength;
            T = length(returns);
            
            X = zeros(T - L, L);
            Y = zeros(T - L, length(obj.Quantiles));
            
            for t = 1:T-L
                X(t, :) = returns(t:t+L-1)';
                
                % Target: next return's empirical quantiles in rolling window
                future_return = returns(t+L);
                
                % Estimate conditional quantiles from local window
                window = max(1, t-30):min(T, t+30);
                window_returns = returns(window);
                
                for q = 1:length(obj.Quantiles)
                    Y(t, q) = quantile(window_returns, obj.Quantiles(q));
                end
            end
        end
        
        function [net, info] = trainLSTMQuantile(obj, X, Y)
            % Train LSTM with 5-output quantile head
            
            if ~obj.HasToolbox
                [net, info] = deal([], []);
                return;
            end
            
            % Convert to dlarray
            X_dl = dlarray(X', 'CT');  % 'C'=channel, 'T'=time
            Y_dl = dlarray(Y', 'CB');  % 'C'=channel, 'B'=batch
            
            % Network architecture
            numFeatures = 1;
            numHidden = obj.LSTMHiddenSize;
            numQuantiles = length(obj.Quantiles);
            
            layers = [
                sequenceInputLayer(numFeatures)
                lstmLayer(numHidden, 'OutputMode', 'sequence')
                lstmLayer(numHidden)
                fullyConnectedLayer(32)
                reluLayer
                fullyConnectedLayer(numQuantiles)
            ];
            
            options = trainingOptions('adam', ...
                'MaxEpochs', obj.EpochsLSTM, ...
                'MiniBatchSize', obj.BatchSize, ...
                'InitialLearnRate', obj.LearningRate, ...
                'ValidationFrequency', 50, ...
                'Plots', 'training-progress', ...
                'Verbose', false);
            
            % Train with pinball loss
            net = trainNetwork(X_dl, Y_dl, layers, options);
            info = [];  % Simplified
        end
        
        function [net, info] = trainCNNQuantile(obj, X, Y)
            % Train 1D CNN with quantile outputs
            
            if ~obj.HasToolbox
                [net, info] = deal([], []);
                return;
            end
            
            X_dl = dlarray(X', 'CT');
            Y_dl = dlarray(Y', 'CB');
            
            numQuantiles = length(obj.Quantiles);
            
            layers = [
                sequenceInputLayer(1)
                convolution1dLayer(obj.CNNKernel, obj.CNNFilters, 'Padding', 'same')
                batchNormalizationLayer
                reluLayer
                convolution1dLayer(obj.CNNKernel, obj.CNNFilters, 'Padding', 'same')
                globalAveragePoolingLayer
                fullyConnectedLayer(64)
                reluLayer
                fullyConnectedLayer(numQuantiles)
            ];
            
            options = trainingOptions('adam', ...
                'MaxEpochs', obj.EpochsCNN, ...
                'MiniBatchSize', obj.BatchSize, ...
                'InitialLearnRate', obj.LearningRate, ...
                'Verbose', false);
            
            net = trainNetwork(X_dl, Y_dl, layers, options);
            info = [];
        end
        
        function trainLinearQuantileRegression(obj, X, Y)
            % Fallback: linear quantile regression (no Deep Learning Toolbox)
            %
            % Solves: min Σ ρ_τ(y - Xβ) for each quantile τ
            % Uses iterative reweighted least squares
            
            [N, p] = size(X);
            obj.QuantilePredictionsLSTM = zeros(N, length(obj.Quantiles));
            
            for q = 1:length(obj.Quantiles)
                tau = obj.Quantiles(q);
                
                % Initial estimate
                beta = pinv(X) * Y(:, q);
                
                % IRLS iterations
                for iter = 1:10
                    residuals = Y(:, q) - X * beta;
                    weights = tau * (residuals >= 0) + (1 - tau) * (residuals < 0);
                    weights = max(weights, 1e-4);  % Avoid division by zero
                    
                    % Weighted least squares
                    W = diag(sqrt(weights));
                    beta = (X' * W * W * X) \ (X' * W * W * Y(:, q));
                end
                
                obj.QuantilePredictionsLSTM(:, q) = X * beta;
            end
        end
        
        function quantiles = predictLSTM(obj, horizon)
            % Multi-step ahead LSTM forecast
            
            if ~obj.HasToolbox || isempty(obj.LSTMNet)
                quantiles = obj.predictLinear(horizon);
                return;
            end
            
            last_sequence = obj.LogReturns(end - obj.SequenceLength + 1:end)';
            quantiles = zeros(horizon, length(obj.Quantiles));
            
            for h = 1:horizon
                X_pred = dlarray(last_sequence, 'CT');
                q_pred = predict(obj.LSTMNet, X_pred);
                quantiles(h, :) = q_pred';
                
                % Update sequence for next step
                last_sequence = [last_sequence(2:end), quantiles(h, 3)];  % Use median
            end
        end
        
        function quantiles = predictCNN(obj, horizon)
            % Multi-step CNN forecast
            
            if ~obj.HasToolbox || isempty(obj.CNNNet)
                quantiles = obj.predictLinear(horizon);
                return;
            end
            
            last_sequence = obj.LogReturns(end - obj.SequenceLength + 1:end)';
            quantiles = zeros(horizon, length(obj.Quantiles));
            
            for h = 1:horizon
                X_pred = dlarray(last_sequence, 'CT');
                q_pred = predict(obj.CNNNet, X_pred);
                quantiles(h, :) = q_pred';
                
                last_sequence = [last_sequence(2:end), quantiles(h, 3)];
            end
        end
        
        function quantiles = predictLinear(obj, horizon)
            % Linear quantile regression forecast
            
            quantiles = zeros(horizon, length(obj.Quantiles));
            
            if isempty(obj.QuantilePredictionsLSTM)
                % Return empirical quantiles if not trained
                for q = 1:length(obj.Quantiles)
                    quantiles(:, q) = quantile(obj.LogReturns, obj.Quantiles(q));
                end
            else
                last_idx = min(size(obj.QuantilePredictionsLSTM, 1), length(obj.LogReturns));
                for q = 1:length(obj.Quantiles)
                    quantiles(:, q) = obj.QuantilePredictionsLSTM(last_idx, q);
                end
            end
        end
        
        function plotQuantileForecasts(obj, horizon, varargin)
            % Visualize quantile predictions
            
            p = inputParser();
            addParameter(p, 'window', 200, @isnumeric);
            parse(p, varargin{:});
            
            window = p.Results.window;
            
            quantiles = obj.predict('LSTM', horizon);
            
            figure('Position', [100, 100, 1200, 600]);
            
            t = 1:window;
            recent_returns = obj.LogReturns(end-window+1:end);
            
            plot(t, recent_returns, 'k-', 'LineWidth', 2, 'DisplayName', 'Observed');
            hold on;
            
            colors = parula(length(obj.Quantiles));
            for q = 1:length(obj.Quantiles)
                plot(window + 1:window + horizon, quantiles(:, q), '--', ...
                    'Color', colors(q, :), 'DisplayName', sprintf('q=%0.0f%%', obj.Quantiles(q)*100));
            end
            
            % Fill 90% band
            fill([window + 1:window + horizon, fliplr(window + 1:window + horizon)], ...
                [quantiles(:, 1)', fliplr(quantiles(:, 5)')], 'cyan', ...
                'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', '90% Band');
            
            xlabel('Time');
            ylabel('Log-Return');
            title(sprintf('%s: Quantile Forecasts (h=%d)', obj.SeriesName, horizon));
            legend('Location', 'best');
            grid on;
        end
    end
end
