classdef BayesianMarkovRegimeDetector < handle
    % BayesianMarkovRegimeDetector: Probabilistic regime detection
    %
    % Replaces hard Viterbi assignments with smoothed posterior probabilities:
    % γ_{t,i} = P(S_t = i | F_T) (backward-filtered, uses future info)
    %
    % Instead of saying "today is Bull (hard assignment)", reports:
    % "Bull: 75%, Bear: 20%, Sideways: 5%" with confidence intervals.
    %
    % References: Hamilton (1989), "A New Approach to Economic Analysis";
    % Kim (1994), "The Role of Seasonality in Business Cycles"
    
    properties
        % Data
        Series;                    % Input series
        SeriesName = 'Asset';
        
        % HMM parameters
        NumRegimes = 3;            % {Bull, Bear, Sideways}
        TransitionMatrix;          % P(S_t = j | S_{t-1} = i)
        MeanReturns;               % μ_i by regime
        StdReturns;                % σ_i by regime
        RegimeNames = {'Bull', 'Bear', 'Sideways'};
        
        % Posteriors
        FilteredProb;              % γ_{t,i} = P(S_t = i | F_t)
        SmoothedProb;              % γ_{t,i|T} = P(S_t = i | F_T) [backward-filtered]
        ConfidenceInterval;        % 95% CI for each posterior
        
        % Metrics
        RegimeEntropy;             % Shannon entropy of posterior (uncertainty measure)
        TransitionTimings;         % Estimated dates of regime changes
        
        % Flags
        IsEstimated = false;
    end
    
    methods
        function obj = BayesianMarkovRegimeDetector(series, varargin)
            % Initialize HMM
            
            if istimetable(series)
                obj.Series = series{:, :};
            else
                obj.Series = series(:);
            end
            
            obj.Series = obj.Series(~isnan(obj.Series));
            
            p = inputParser();
            addParameter(p, 'num_regimes', 3, @isnumeric);
            addParameter(p, 'series_name', 'Asset', @ischar);
            parse(p, varargin{:});
            
            obj.NumRegimes = p.Results.num_regimes;
            obj.SeriesName = p.Results.series_name;
            
            % Initialize transition matrix (assumed equal for now)
            obj.TransitionMatrix = ones(obj.NumRegimes) / obj.NumRegimes;
        end
        
        function estimate(obj, varargin)
            % Estimate HMM parameters via EM algorithm
            %
            % Step 1: Initialize with k-means clustering
            % Step 2: Forward-backward algorithm for filtering/smoothing
            % Step 3: Maximize likelihood of transition/emission parameters
            
            p = inputParser();
            addParameter(p, 'max_iter', 50, @isnumeric);
            addParameter(p, 'tolerance', 1e-5, @isnumeric);
            parse(p, varargin{:});
            
            max_iter = p.Results.max_iter;
            tolerance = p.Results.tolerance;
            
            T = length(obj.Series);
            
            % Step 1: Initialize parameters via k-means
            [cluster_idx, cluster_centers] = kmeans(obj.Series, obj.NumRegimes);
            
            % Sort regimes by mean return (Bull=high, Bear=low)
            [~, sort_idx] = sort(cluster_centers, 'descend');
            obj.MeanReturns = cluster_centers(sort_idx);
            obj.StdReturns = zeros(obj.NumRegimes, 1);
            
            for i = 1:obj.NumRegimes
                cluster_returns = obj.Series(cluster_idx == sort_idx(i));
                obj.StdReturns(i) = std(cluster_returns);
                if obj.StdReturns(i) < 1e-4
                    obj.StdReturns(i) = 1e-4;  % Avoid division by zero
                end
            end
            
            % Initialize uniform transition matrix
            obj.TransitionMatrix = ones(obj.NumRegimes) / obj.NumRegimes;
            
            % EM iterations
            ll_prev = -inf;
            for iter = 1:max_iter
                % Forward-backward pass
                [filt_prob, smooth_prob, ll] = obj.forwardBackwardPass();
                
                % Check convergence
                if abs(ll - ll_prev) < tolerance
                    fprintf('Converged after %d EM iterations.\n', iter);
                    break;
                end
                ll_prev = ll;
                
                % Update parameters (M-step)
                obj.updateParameters(filt_prob, smooth_prob);
                
                if mod(iter, 10) == 0
                    fprintf('EM iteration %d: Log-likelihood = %.4f\n', iter, ll);
                end
            end
            
            % Final forward-backward pass
            [obj.FilteredProb, obj.SmoothedProb, ~] = obj.forwardBackwardPass();
            
            % Compute confidence intervals
            obj.computeConfidenceIntervals();
            
            % Compute entropy
            obj.RegimeEntropy = obj.computeEntropy(obj.SmoothedProb);
            
            % Detect transition timings
            obj.TransitionTimings = obj.detectTransitions();
            
            obj.IsEstimated = true;
        end
        
        function [filt_prob, smooth_prob, ll] = forwardBackwardPass(obj)
            % Forward-backward algorithm for HMM filtering and smoothing
            
            T = length(obj.Series);
            
            % Emission probabilities: P(y_t | S_t = i)
            emit_prob = zeros(T, obj.NumRegimes);
            for i = 1:obj.NumRegimes
                emit_prob(:, i) = normpdf(obj.Series, obj.MeanReturns(i), obj.StdReturns(i));
            end
            
            % Forward pass: α_t(i) = P(y_1:t, S_t = i)
            alpha = zeros(T, obj.NumRegimes);
            alpha(1, :) = (1 / obj.NumRegimes) .* emit_prob(1, :);
            
            for t = 2:T
                for j = 1:obj.NumRegimes
                    alpha(t, j) = emit_prob(t, j) * sum(alpha(t-1, :) .* obj.TransitionMatrix(:, j)');
                end
            end
            
            % Likelihood
            ll = sum(log(sum(alpha, 2) + eps));
            
            % Backward pass: β_t(i) = P(y_{t+1:T} | S_t = i)
            beta = zeros(T, obj.NumRegimes);
            beta(T, :) = 1;
            
            for t = T-1:-1:1
                for i = 1:obj.NumRegimes
                    beta(t, i) = sum(obj.TransitionMatrix(i, :)' .* emit_prob(t+1, :)' .* beta(t+1, :)');
                end
            end
            
            % Filtered probabilities: γ_t(i) = P(S_t = i | y_1:t)
            filt_prob = alpha ./ (sum(alpha, 2) + eps);
            
            % Smoothed probabilities: γ_{t|T}(i) = P(S_t = i | y_1:T)
            smooth_prob = (alpha .* beta) ./ (sum(alpha .* beta, 2) + eps);
        end
        
        function updateParameters(obj, filt_prob, smooth_prob)
            % M-step: Update HMM parameters
            
            T = length(obj.Series);
            
            % Update regime means
            for i = 1:obj.NumRegimes
                obj.MeanReturns(i) = sum(smooth_prob(:, i) .* obj.Series) / sum(smooth_prob(:, i));
            end
            
            % Update regime standard deviations
            for i = 1:obj.NumRegimes
                deviations = (obj.Series - obj.MeanReturns(i)).^2;
                obj.StdReturns(i) = sqrt(sum(smooth_prob(:, i) .* deviations) / sum(smooth_prob(:, i)));
                obj.StdReturns(i) = max(obj.StdReturns(i), 1e-4);
            end
            
            % Update transition matrix
            % P(S_t = j | S_{t-1} = i) estimated from two-state probabilities
            xi = zeros(obj.NumRegimes, obj.NumRegimes);
            
            for t = 1:T-1
                for i = 1:obj.NumRegimes
                    for j = 1:obj.NumRegimes
                        xi(i, j) = xi(i, j) + smooth_prob(t, i) * obj.TransitionMatrix(i, j);
                    end
                end
            end
            
            % Normalize to get transition probabilities
            obj.TransitionMatrix = xi ./ (sum(xi, 2) + eps);
        end
        
        function computeConfidenceIntervals(obj)
            % Bootstrap confidence intervals for posterior probabilities
            
            T = length(obj.Series);
            n_bootstrap = 100;
            
            obj.ConfidenceInterval = struct();
            obj.ConfidenceInterval.lower = zeros(T, obj.NumRegimes);
            obj.ConfidenceInterval.upper = zeros(T, obj.NumRegimes);
            
            for b = 1:n_bootstrap
                % Resample with replacement
                idx_boot = randsample(T, T, true);
                series_boot = obj.Series(idx_boot);
                
                % Estimate posterior on bootstrap sample
                [~, smooth_boot, ~] = obj.forwardBackwardPass();
                
                if b == 1
                    all_smooth = smooth_boot;
                else
                    all_smooth = all_smooth + smooth_boot;
                end
            end
            
            % Compute percentiles
            for i = 1:obj.NumRegimes
                obj.ConfidenceInterval.lower(:, i) = quantile(all_smooth(:, i), 0.025);
                obj.ConfidenceInterval.upper(:, i) = quantile(all_smooth(:, i), 0.975);
            end
        end
        
        function entropy = computeEntropy(obj, prob_matrix)
            % Shannon entropy: H = -Σ p_i log(p_i)
            % Measures uncertainty in regime assignment
            % H=0: certain (one regime = 100%)
            % H=log(3): maximum uncertainty (equal probabilities)
            
            epsilon = 1e-10;
            prob_matrix = max(prob_matrix, epsilon);
            entropy = -sum(prob_matrix .* log(prob_matrix), 2);
        end
        
        function transitions = detectTransitions(obj)
            % Identify significant regime changes
            % Transition = time when max posterior crosses 50% threshold
            
            [~, regime_sequence] = max(obj.SmoothedProb, [], 2);
            transitions = find(diff(regime_sequence) ~= 0);
        end
        
        function [regime_hard, prob] = getRegimeAssignment(obj, t_idx)
            % Get regime assignment at specific time
            %
            % Outputs:
            %   regime_hard: Single regime label {1=Bull, 2=Bear, 3=Sideways}
            %   prob: Posterior probabilities for all regimes at time t
            
            if ~obj.IsEstimated
                error('Model not estimated. Call estimate() first.');
            end
            
            if nargin < 2
                t_idx = 1:length(obj.Series);
            end
            
            if isscalar(t_idx)
                prob = obj.SmoothedProb(t_idx, :);
                [~, regime_hard] = max(prob);
            else
                prob = obj.SmoothedProb(t_idx, :);
                [~, regime_hard] = max(prob, [], 2);
            end
        end
        
        function plotRegimes(obj, varargin)
            % Visualize regime posteriors
            
            p = inputParser();
            addParameter(p, 'window', min(500, length(obj.Series)), @isnumeric);
            parse(p, varargin{:});
            
            window = p.Results.window;
            t = 1:window;
            
            if ~obj.IsEstimated
                error('Model not estimated. Call estimate() first.');
            end
            
            fig = figure('Position', [100, 100, 1400, 900]);
            
            % Subplot 1: Time series with regime coloring
            subplot(3, 1, 1);
            series_plot = obj.Series(1:window);
            plot(t, series_plot, 'k-', 'LineWidth', 1.5);
            hold on;
            
            % Color background by dominant regime
            [~, dominant_regime] = max(obj.SmoothedProb(1:window, :), [], 2);
            regime_colors = [0, 1, 0; 1, 0, 0; 0.5, 0.5, 0.5];  % Green, Red, Gray
            
            for i = 1:3
                idx = dominant_regime == i;
                scatter(t(idx), series_plot(idx), 20, regime_colors(i, :), ...
                    'DisplayName', obj.RegimeNames{i});
            end
            
            ylabel('Return');
            title('Time Series with Regime Coloring');
            legend('Location', 'best');
            grid on;
            
            % Subplot 2: Posterior probabilities
            subplot(3, 1, 2);
            area(t, obj.SmoothedProb(1:window, :));
            ylabel('Posterior Probability');
            title('Regime Posterior Probabilities γ_{t|T}');
            legend(obj.RegimeNames, 'Location', 'best');
            ylim([0, 1]);
            grid on;
            
            % Subplot 3: Entropy (uncertainty)
            subplot(3, 1, 3);
            entropy = obj.RegimeEntropy(1:window);
            plot(t, entropy, 'LineWidth', 2);
            ylabel('Shannon Entropy');
            xlabel('Time (t)');
            title('Regime Uncertainty (H=0: Certain, H=log(3)=1.1: Maximum Uncertainty)');
            ylim([0, log(obj.NumRegimes) * 1.2]);
            grid on;
            
            sgtitle(sprintf('%s: Bayesian Regime Detection', obj.SeriesName));
        end
        
        function summary = getSummary(obj)
            % Summary statistics of regime detection
            
            if ~obj.IsEstimated
                error('Model not estimated. Call estimate() first.');
            end
            
            summary = struct();
            
            % Regime statistics
            for i = 1:obj.NumRegimes
                summary.regime(i).name = obj.RegimeNames{i};
                summary.regime(i).mean_return = obj.MeanReturns(i);
                summary.regime(i).std_return = obj.StdReturns(i);
                summary.regime(i).avg_posterior = mean(obj.SmoothedProb(:, i));
                summary.regime(i).avg_duration = mean(diff(find([1; diff(obj.SmoothedProb(:, i) > 0.5) ~= 0; 1])));
            end
            
            % Transition matrix
            summary.transition_matrix = array2table(obj.TransitionMatrix, ...
                'RowNames', obj.RegimeNames, 'VariableNames', obj.RegimeNames);
            
            % Current regime assignment
            current_regime = obj.RegimeNames{obj.getRegimeAssignment(length(obj.Series))};
            current_prob = obj.SmoothedProb(end, :);
            summary.current_regime = current_regime;
            summary.current_probabilities = array2table(current_prob, ...
                'VariableNames', obj.RegimeNames);
        end
    end
end
