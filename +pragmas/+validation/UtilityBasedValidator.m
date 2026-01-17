classdef UtilityBasedValidator
    % UtilityBasedValidator: Risk-adjusted performance evaluation
    %
    % Evaluates forecasts by their ability to maximize trader utility
    % rather than just minimize forecast errors.
    %
    % Utility Function: U(w) = w - (λ/2) * w²
    %   w: Portfolio return
    %   λ: Risk aversion coefficient (found via VaR constraint)
    %
    % Key Insight: A model with poor MSE might be an excellent directional
    % predictor, allowing optimal leverage decisions that beat MSE-optimal models.
    %
    % References: Christoffersen & Diebold (2004), "How Relevant is Volatility";
    % Hansen & Jagannathan (1997), "Assessing Specification Errors"
    
    properties
        var_confidence = 0.95;          % VaR constraint (default 95%)
        target_volatility = 0.15;       % Target annual volatility
        leverage_constraint = 3.0;      % Max leverage allowed
        rebalance_frequency = 21;       % Trading days (monthly)
    end
    
    methods
        function obj = UtilityBasedValidator(varargin)
            p = inputParser();
            addParameter(p, 'var_confidence', 0.95, @isnumeric);
            addParameter(p, 'target_volatility', 0.15, @isnumeric);
            addParameter(p, 'leverage_constraint', 3.0, @isnumeric);
            addParameter(p, 'rebalance_frequency', 21, @isnumeric);
            parse(p, varargin{:});
            
            obj.var_confidence = p.Results.var_confidence;
            obj.target_volatility = p.Results.target_volatility;
            obj.leverage_constraint = p.Results.leverage_constraint;
            obj.rebalance_frequency = p.Results.rebalance_frequency;
        end
        
        function [utility, wealth, leverage_path] = quadraticUtility(obj, actuals, forecasts, varargin)
            % Compute utility-maximizing strategy with optimal leverage
            %
            % Inputs:
            %   actuals: Realized log-returns (T x 1), daily
            %   forecasts: Forecasted direction/magnitude (T x 1)
            %              Can be continuous or binary (-1,0,+1)
            % Outputs:
            %   utility: Time series of utility (T x 1)
            %   wealth: Cumulative wealth from strategy
            %   leverage_path: Optimal leverage over time
            
            p = inputParser();
            addParameter(p, 'initial_wealth', 1.0, @isnumeric);
            addParameter(p, 'rebalance', true, @islogical);
            parse(p, varargin{:});
            
            T = length(actuals);
            initial_wealth = p.Results.initial_wealth;
            rebalance = p.Results.rebalance;
            
            % 1. Normalize forecasts to probability (0, 1)
            if range(forecasts) > 0
                forecast_prob = (forecasts - min(forecasts)) / range(forecasts);
            else
                forecast_prob = 0.5 * ones(size(forecasts));
            end
            
            % 2. Estimate rolling volatility
            window = 20;
            rolling_vol = zeros(T, 1);
            for t = window:T
                rolling_vol(t) = std(actuals(t-window+1:t));
            end
            rolling_vol(rolling_vol == 0) = mean(actuals);
            
            % 3. Determine optimal leverage at each time
            leverage_path = zeros(T, 1);
            
            for t = 1:T
                if t < window
                    vol = rolling_vol(window);
                else
                    vol = rolling_vol(t);
                end
                
                % VaR-constrained leverage
                % VaR_95% ≈ -1.645 * σ
                % If we want |L * ret| ≤ VaR_limit with 95% confidence:
                % L ≤ VaR_limit / (1.645 * σ)
                
                var_limit = -norminv(1 - obj.var_confidence);  % e.g., 1.645 for 95%
                max_leverage = obj.leverage_constraint;
                
                if vol > 0
                    leverage_var = obj.target_volatility / (var_limit * vol);
                else
                    leverage_var = max_leverage;
                end
                
                % Apply leverage cap
                leverage_path(t) = min(leverage_var, max_leverage);
            end
            
            % 4. Compute portfolio returns with optimal leverage
            % Take position based on forecast direction AND adjust for confidence
            position_signal = 2 * forecast_prob - 1;  % Map [0,1] to [-1, +1]
            
            if rebalance && obj.rebalance_frequency > 0
                % Rebalance every N days
                for t = 1:obj.rebalance_frequency:T
                    idx_range = t:min(t + obj.rebalance_frequency - 1, T);
                    position_signal(idx_range) = mean(position_signal(idx_range));
                end
            end
            
            % Portfolio return = leverage * position * actual return
            portfolio_returns = leverage_path .* position_signal .* actuals;
            
            % 5. Compute utility from returns
            % U(w) = w - (λ/2) * w²
            % Where λ estimated from historical data
            
            % Estimate risk aversion from historical variance
            hist_variance = var(portfolio_returns);
            hist_mean = mean(portfolio_returns);
            
            if hist_variance > 0
                lambda_est = 2 * hist_mean / hist_variance;
            else
                lambda_est = 1.0;
            end
            
            utility = portfolio_returns - (lambda_est / 2) * portfolio_returns.^2;
            
            % 6. Compute cumulative wealth
            wealth = initial_wealth * cumprod(1 + portfolio_returns);
            
        end
        
        function sharpe = sharpeRatio(obj, returns)
            % Sharpe Ratio: E[R] / σ[R] * √252 (annualized)
            
            if length(returns) < 2 || std(returns) == 0
                sharpe = 0;
            else
                sharpe = (mean(returns) / std(returns)) * sqrt(252);
            end
        end
        
        function sortino = sortinoRatio(obj, returns)
            % Sortino Ratio: E[R] / σ_down * √252
            % Only penalizes downside volatility (negative returns)
            
            downside = returns(returns < 0);
            
            if length(downside) < 2 || std(downside) == 0
                sortino = 0;
            else
                downside_vol = std(downside);
                sortino = (mean(returns) / downside_vol) * sqrt(252);
            end
        end
        
        function cvar = conditionalValueAtRisk(obj, returns, confidence)
            % CVaR (Expected Shortfall)
            % Expected loss given that loss exceeds VaR
            
            if nargin < 3
                confidence = obj.var_confidence;
            end
            
            var_level = quantile(returns, 1 - confidence);
            worst_returns = returns(returns <= var_level);
            cvar = mean(worst_returns);
        end
        
        function mdd = maxDrawdown(obj, wealth)
            % Maximum Drawdown from peak
            
            cummax_wealth = cummax(wealth);
            drawdown = (wealth - cummax_wealth) ./ cummax_wealth;
            mdd = min(drawdown);
        end
        
        function [metrics, table_result] = evaluateStrategy(obj, actuals, forecasts, varargin)
            % Comprehensive strategy evaluation
            % Outputs all performance metrics
            
            p = inputParser();
            addParameter(p, 'initial_wealth', 1.0, @isnumeric);
            parse(p, varargin{:});
            
            % Compute strategy results
            [utility, wealth, leverage] = obj.quadraticUtility(actuals, forecasts, ...
                'initial_wealth', p.Results.initial_wealth);
            
            % Compute portfolio returns
            position_signal = 2 * ((forecasts - min(forecasts)) / (range(forecasts) + eps)) - 1;
            portfolio_returns = leverage .* position_signal .* actuals;
            
            % Metrics
            metrics = struct();
            metrics.final_wealth = wealth(end);
            metrics.total_return = (wealth(end) - p.Results.initial_wealth) / p.Results.initial_wealth;
            metrics.mean_utility = mean(utility);
            metrics.std_utility = std(utility);
            metrics.sharpe = obj.sharpeRatio(portfolio_returns);
            metrics.sortino = obj.sortinoRatio(portfolio_returns);
            metrics.mdd = obj.maxDrawdown(wealth);
            metrics.cvar = obj.conditionalValueAtRisk(portfolio_returns);
            metrics.avg_leverage = mean(leverage);
            metrics.max_leverage = max(leverage);
            metrics.turnover = mean(abs(diff(leverage)));
            
            % Summary table
            table_result = table(...
                {'Final Wealth'; 'Total Return'; 'Mean Utility'; 'Std Utility'; ...
                 'Sharpe Ratio'; 'Sortino Ratio'; 'Max Drawdown'; 'CVaR'; ...
                 'Avg Leverage'; 'Max Leverage'; 'Turnover'}, ...
                [metrics.final_wealth; metrics.total_return; metrics.mean_utility; ...
                 metrics.std_utility; metrics.sharpe; metrics.sortino; metrics.mdd; ...
                 metrics.cvar; metrics.avg_leverage; metrics.max_leverage; metrics.turnover], ...
                'VariableNames', {'Metric', 'Value'});
        end
        
        function plot_strategy(obj, actuals, wealth, leverage_path, varargin)
            % Visualize strategy performance
            
            p = inputParser();
            addParameter(p, 'window', min(500, length(actuals)), @isnumeric);
            parse(p, varargin{:});
            
            window = p.Results.window;
            t = 1:window;
            
            fig = figure('Position', [100, 100, 1400, 800]);
            
            % Subplot 1: Wealth
            subplot(3, 1, 1);
            plot(t, wealth(1:window), 'LineWidth', 2);
            ylabel('Cumulative Wealth');
            title('Strategy Wealth Evolution');
            grid on;
            
            % Subplot 2: Leverage
            subplot(3, 1, 2);
            plot(t, leverage_path(1:window), 'LineWidth', 1.5);
            ylabel('Leverage');
            title('Optimal Leverage Path');
            grid on;
            hold on;
            yline(obj.leverage_constraint, '--r', 'Max Constraint');
            
            % Subplot 3: Returns
            subplot(3, 1, 3);
            position_signal = 2 * ((actuals - min(actuals)) / (range(actuals) + eps)) - 1;
            returns = leverage_path .* position_signal .* actuals;
            bar(t, returns(1:window), 'FaceColor', [0.5, 0.7, 1.0]);
            ylabel('Portfolio Return');
            xlabel('Time (t)');
            title('Daily Strategy Returns');
            grid on;
            
            sgtitle(sprintf('Utility-Based Strategy (Sharpe=%.2f, MDD=%.2f%%)', ...
                obj.sharpeRatio(returns), obj.maxDrawdown(wealth)*100));
        end
    end
end
