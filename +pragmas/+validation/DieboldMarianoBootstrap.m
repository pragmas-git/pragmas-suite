classdef DieboldMarianoBootstrap
    % DieboldMarianoBootstrap: Robust DM test using Moving Block Bootstrap
    %
    % Implements Diebold-Mariano test with robustness to non-normality:
    %   1. Original DM test (asymptotic normal distribution)
    %   2. Moving Block Bootstrap (MBB) for heavy tails
    %   3. Automatic block size selection (Andrews, 1991)
    %   4. P-values robust to leptocurtosis (fat tails in financial data)
    %
    % References:
    %   - Diebold & Mariano (1995): "Comparing Predictive Accuracy"
    %   - Künsch (1989): "The jackknife and the bootstrap for general stationary observations"
    %   - Andrews (1991): "Heteroskedasticity and autocorrelation consistent covariance matrix"

    properties
        Error1              % Forecast errors from model 1
        Error2              % Forecast errors from model 2
        LossFunc            % Loss function: 'mse', 'mae', 'ape', 'custom'
        H                   % Forecast horizon (for HAC adjustment)
        BootstrapReps       % Number of bootstrap replications
        BlockSize           % MBB block size (computed automatically)
        DMStatistic         % DM test statistic
        PValueAsymptotic    % Asymptotic p-value (normal)
        PValueBootstrap     % Bootstrap p-value (robust)
        BootstrapStats      % Bootstrap distribution of DM statistic
        ConfidenceLevel     % CI confidence (default 0.95)
    end
    
    methods
        function obj = DieboldMarianoBootstrap(error1, error2, varargin)
            % Constructor
            % Inputs:
            %   error1, error2: Forecast error vectors (T x 1)
            %   Optional:
            %     'loss': 'mse', 'mae', 'ape' (default: 'mse')
            %     'horizon': Forecast horizon h (default: 1)
            %     'bootstrap_reps': Number of replications (default: 10000)
            %     'confidence': CI level (default: 0.95)
            
            p = inputParser();
            addParameter(p, 'loss', 'mse', @ischar);
            addParameter(p, 'horizon', 1, @isnumeric);
            addParameter(p, 'bootstrap_reps', 10000, @isnumeric);
            addParameter(p, 'confidence', 0.95, @isnumeric);
            parse(p, varargin{:});
            
            obj.Error1 = error1(:);
            obj.Error2 = error2(:);
            obj.LossFunc = p.Results.loss;
            obj.H = p.Results.horizon;
            obj.BootstrapReps = p.Results.bootstrap_reps;
            obj.ConfidenceLevel = p.Results.confidence;
            
            % Validate
            if length(obj.Error1) ~= length(obj.Error2)
                error('Error vectors must have same length');
            end
            
            % Compute block size
            obj = obj.computeBlockSize();
        end
        
        function obj = computeBlockSize(obj)
            % Automatic block size selection for MBB
            % Method: Andrews (1991) for HAC covariance estimation
            
            T = length(obj.Error1);
            
            % Compute loss differentials
            loss1 = obj.computeLoss(obj.Error1);
            loss2 = obj.computeLoss(obj.Error2);
            d = loss1 - loss2;  % Loss differential
            
            % Estimate optimal block size
            % Rule of thumb: b = 1.3 * (T^(1/3)) * lambda
            % where lambda = sqrt(LRV / variance)
            
            % Long-run variance (LRV) estimation
            lags = floor(4 * (T / 100)^(2/9));  % Newey-West lag selection
            
            % AR(1) approximation for LRV
            if lags > 0
                rho = corr(d(1:end-1), d(2:end));  % AR(1) coefficient
            else
                rho = 0;
            end
            
            var_d = var(d);
            lrv = var_d * (1 + rho) / (1 - rho);  % LRV under AR(1)
            
            lambda = sqrt(lrv / var_d);
            obj.BlockSize = max(1, round(1.3 * (T^(1/3)) * lambda));
            
            % Cap at T/2 to avoid trivial blocks
            obj.BlockSize = min(obj.BlockSize, floor(T / 2));
        end
        
        function loss = computeLoss(obj, errors)
            % Compute loss according to loss function
            switch lower(obj.LossFunc)
                case 'mse'
                    loss = errors.^2;
                case 'mae'
                    loss = abs(errors);
                case 'ape'  % Absolute Percentage Error
                    loss = abs(errors) ./ (abs(errors) + eps);
                otherwise
                    loss = errors.^2;  % Default
            end
        end
        
        function obj = test(obj)
            % Run DM test: asymptotic and bootstrap
            
            % Compute loss differentials
            loss1 = obj.computeLoss(obj.Error1);
            loss2 = obj.computeLoss(obj.Error2);
            d = loss1 - loss2;  % Loss differential d_t = L1_t - L2_t
            
            T = length(d);
            
            % Mean loss differential
            d_bar = mean(d);
            
            % Variance with HAC adjustment (Newey-West)
            % DM test statistic: DM = sqrt(T) * d_bar / sqrt(LRV)
            lrv = obj.estimateLongRunVariance(d);
            
            % DM statistic
            if lrv > 0
                obj.DMStatistic = sqrt(T) * d_bar / sqrt(lrv);
            else
                obj.DMStatistic = 0;
            end
            
            % Asymptotic p-value (normal distribution)
            obj.PValueAsymptotic = 2 * (1 - normcdf(abs(obj.DMStatistic)));
            
            % Bootstrap p-value (robust to non-normality)
            obj = obj.bootstrapTest(d);
        end
        
        function obj = bootstrapTest(obj, d)
            % Moving Block Bootstrap for DM test
            % Robust to heavy tails and autocorrelation
            
            T = length(d);
            b = obj.BlockSize;
            
            % Number of blocks
            num_blocks = ceil(T / b);
            
            % Bootstrap replications
            dm_boot = zeros(obj.BootstrapReps, 1);
            
            for rep = 1:obj.BootstrapReps
                % Random block indices
                block_starts = randi(T - b + 1, num_blocks, 1);
                
                % Construct bootstrap sample
                d_boot = [];
                for k = 1:num_blocks
                    start_idx = block_starts(k);
                    end_idx = min(start_idx + b - 1, T);
                    d_boot = [d_boot; d(start_idx:end_idx)];
                end
                
                % Trim to original length
                d_boot = d_boot(1:T);
                
                % Compute DM for bootstrap sample
                d_boot_bar = mean(d_boot);
                lrv_boot = obj.estimateLongRunVariance(d_boot);
                
                if lrv_boot > 0
                    dm_boot(rep) = sqrt(T) * d_boot_bar / sqrt(lrv_boot);
                else
                    dm_boot(rep) = 0;
                end
            end
            
            obj.BootstrapStats = dm_boot;
            
            % Bootstrap p-value: P(|DM_boot| >= |DM_observed|)
            obj.PValueBootstrap = mean(abs(dm_boot) >= abs(obj.DMStatistic));
        end
        
        function lrv = estimateLongRunVariance(obj, x)
            % Estimate long-run variance using Newey-West HAC
            % Robust to heteroskedasticity and autocorrelation
            
            T = length(x);
            
            % Newey-West lag selection (Andrews, 1991)
            lags = floor(4 * (T / 100)^(2/9));
            
            % Autocovariance at lag 0
            gamma_0 = var(x);
            
            % Weighted sum of autocovariances
            lrv = gamma_0;
            
            for lag = 1:lags
                % Autocovariance at this lag
                if lag < T
                    gamma_lag = mean(x(1:T-lag) .* x(1+lag:T));
                    
                    % Newey-West weights (triangular kernel)
                    weight = 1 - lag / (lags + 1);
                    
                    lrv = lrv + 2 * weight * gamma_lag;
                end
            end
            
            lrv = max(lrv, 1e-10);  % Ensure positive
        end
        
        function [p_value, test_stat] = getResults(obj)
            % Return test results
            % p_value: Use bootstrap (robust), but report both
            % test_stat: DM statistic
            
            p_value = obj.PValueBootstrap;
            test_stat = obj.DMStatistic;
        end
        
        function summary = getSummary(obj)
            % Return summary of test results
            summary = struct();
            summary.dm_statistic = obj.DMStatistic;
            summary.p_value_asymptotic = obj.PValueAsymptotic;
            summary.p_value_bootstrap = obj.PValueBootstrap;
            summary.block_size = obj.BlockSize;
            summary.bootstrap_reps = obj.BootstrapReps;
            summary.conclusion = '';
            
            % Interpretation
            alpha = 1 - obj.ConfidenceLevel;
            if obj.PValueBootstrap < alpha
                summary.conclusion = sprintf(...
                    'REJECT H0: Models have significantly different predictive accuracy (p=%.4f)', ...
                    obj.PValueBootstrap);
            else
                summary.conclusion = sprintf(...
                    'FAIL TO REJECT H0: No significant difference in accuracy (p=%.4f)', ...
                    obj.PValueBootstrap);
            end
        end
        
        function plot_bootstrap_distribution(obj)
            % Visualize bootstrap distribution and DM statistic
            
            if isempty(obj.BootstrapStats)
                warning('Run test() first');
                return;
            end
            
            figure('Name', 'Diebold-Mariano Bootstrap Test', 'NumberTitle', 'off');
            
            % Histogram of bootstrap statistics
            histogram(obj.BootstrapStats, 50, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'black');
            hold on;
            
            % Overlay normal distribution
            x_range = linspace(min(obj.BootstrapStats), max(obj.BootstrapStats), 100);
            pdf_normal = normpdf(x_range, mean(obj.BootstrapStats), std(obj.BootstrapStats));
            pdf_normal = pdf_normal * length(obj.BootstrapStats) * ...
                (max(obj.BootstrapStats) - min(obj.BootstrapStats)) / 50;
            plot(x_range, pdf_normal, 'r-', 'LineWidth', 2, 'DisplayName', 'Normal Fit');
            
            % Mark observed DM statistic
            xline(obj.DMStatistic, 'g-', 'LineWidth', 2.5, 'DisplayName', ...
                sprintf('Observed DM=%.3f', obj.DMStatistic));
            
            % Mark critical values
            alpha = 1 - obj.ConfidenceLevel;
            crit_val = quantile(obj.BootstrapStats, [alpha/2, 1-alpha/2]);
            xline(crit_val(1), 'k--', 'LineWidth', 1, 'DisplayName', 'Critical Values');
            xline(crit_val(2), 'k--', 'LineWidth', 1);
            
            xlabel('DM Statistic');
            ylabel('Frequency');
            title(sprintf('Moving Block Bootstrap: Diebold-Mariano Test\nBlock Size = %d, Bootstrap Reps = %d', ...
                obj.BlockSize, obj.BootstrapReps));
            legend('Location', 'best');
            grid on;
        end
    end
end
