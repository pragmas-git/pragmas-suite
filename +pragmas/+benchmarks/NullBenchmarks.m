classdef NullBenchmarks
    % NullBenchmarks: Null models for rigorous hypothesis testing
    %
    % Implements baseline models to test H0: "Model = Random Walk"
    % If pragmas-suite cannot beat these null models out-of-sample,
    % then the null hypothesis (market efficiency) cannot be rejected.
    %
    % Models:
    %   1. RandomWalk: P_t = P_{t-1}
    %   2. RandomWalkDrift: P_t = P_{t-1} + mean(ΔP)
    %   3. SeasonalNaive: P_t = P_{t-s} (s=252 for daily data)
    %   4. ExponentialSmoothing: Holt-Winters
    %
    % Reference: Diebold (2015), "Comparing Predictive Accuracy"; Fama (1970)
    
    properties (Constant)
        DAILY_SEASONALITY = 252;    % Trading days per year
        WEEKLY_SEASONALITY = 52;    % Weeks per year
    end
    
    methods (Static)
        function forecast = randomWalk(series, horizon, varargin)
            % Random Walk: P_{t+h} = P_t
            % Inputs:
            %   series: Time series data (T x 1)
            %   horizon: Forecast horizon h
            % Outputs:
            %   forecast: Forecasts (h x 1)
            
            last_value = series(end);
            forecast = repmat(last_value, horizon, 1);
        end
        
        function forecast = randomWalkWithDrift(series, horizon, varargin)
            % Random Walk with Drift: P_{t+h} = P_t + h * drift
            % Inputs:
            %   series: Time series data (T x 1)
            %   horizon: Forecast horizon h
            % Outputs:
            %   forecast: Forecasts (h x 1)
            
            % Estimate drift
            if length(series) < 2
                drift = 0;
            else
                drift = mean(diff(series));
            end
            
            last_value = series(end);
            h_steps = 1:horizon;
            forecast = last_value + drift * h_steps(:);
        end
        
        function forecast = seasonalNaive(series, horizon, varargin)
            % Seasonal Naive: P_{t+h} = P_{t+h-s}
            % where s = seasonality (default: 252 for daily data)
            %
            % Useful benchmark for assets with strong yearly seasonality
            % (e.g., agricultural commodities, crypto)
            
            p = inputParser();
            addParameter(p, 'seasonality', 252, @isnumeric);
            parse(p, varargin{:});
            
            s = p.Results.seasonality;
            T = length(series);
            
            forecast = zeros(horizon, 1);
            
            for h = 1:horizon
                lag_idx = T - s + h;
                if lag_idx > 0 && lag_idx <= T
                    forecast(h) = series(lag_idx);
                else
                    % Fallback: use last available seasonal value
                    fallback_idx = max(1, T - s);
                    forecast(h) = series(fallback_idx);
                end
            end
        end
        
        function forecast = exponentialSmoothing(series, horizon, varargin)
            % Simple Exponential Smoothing (SES)
            % Optimal for data without trend or seasonality
            % Formula: y_{t+h|t} = α * y_t + (1-α) * y_{t+h-1|t}
            
            p = inputParser();
            addParameter(p, 'alpha', [], @(x) isempty(x) || (x > 0 && x < 1));
            parse(p, varargin{:});
            
            alpha = p.Results.alpha;
            T = length(series);
            
            % Estimate alpha by MLE if not provided
            if isempty(alpha)
                alpha = NullBenchmarks.optimize_ses_alpha(series);
            end
            
            % SES forecast
            forecast = zeros(horizon, 1);
            level = series(end);
            
            for h = 1:horizon
                forecast(h) = level;  % SES forecasts are constant
            end
        end
        
        function forecast = naiveMean(series, horizon, varargin)
            % Naive Mean: P_{t+h} = mean(P)
            % Constant forecast equal to historical mean
            % Baseline for testing stationarity
            
            mean_val = mean(series);
            forecast = repmat(mean_val, horizon, 1);
        end
        
        function [forecast_rw, forecast_rwdrift, forecast_sn, forecast_es] = ...
                compareAllNulls(series, horizon, varargin)
            % Compare all null models side-by-side
            % Outputs: All null forecasts for ensemble comparison
            
            forecast_rw = NullBenchmarks.randomWalk(series, horizon);
            forecast_rwdrift = NullBenchmarks.randomWalkWithDrift(series, horizon);
            forecast_sn = NullBenchmarks.seasonalNaive(series, horizon, varargin{:});
            forecast_es = NullBenchmarks.exponentialSmoothing(series, horizon, varargin{:});
        end
        
        function metrics = evaluateNullModels(actuals, forecasts_cell, model_names)
            % Evaluate all null models
            % Inputs:
            %   actuals: Actual values (T x 1)
            %   forecasts_cell: Cell of forecasts {forecast1, forecast2, ...}
            %   model_names: Cell of model names
            % Outputs:
            %   metrics: Struct with RMSE, MAE, Sharpe for each model
            
            num_models = length(forecasts_cell);
            metrics = struct();
            
            for m = 1:num_models
                forecast = forecasts_cell{m};
                name = model_names{m};
                
                % Align lengths
                T = length(actuals);
                if length(forecast) > T
                    forecast = forecast(1:T);
                elseif length(forecast) < T
                    forecast = [forecast; repmat(forecast(end), T - length(forecast), 1)];
                end
                
                % Errors
                errors = forecast - actuals;
                
                % RMSE
                rmse = sqrt(mean(errors.^2));
                
                % MAE
                mae = mean(abs(errors));
                
                % Directional Accuracy
                if T > 1
                    direction_actual = sign(diff(actuals));
                    direction_pred = sign(diff(forecast));
                    hit_rate = mean(direction_actual == direction_pred);
                else
                    hit_rate = NaN;
                end
                
                % Sharpe Ratio (if viewing forecast as strategy returns)
                if std(errors) > 0
                    sharpe = mean(-errors) / std(-errors) * sqrt(252);
                else
                    sharpe = NaN;
                end
                
                % Store in struct
                metrics.(matlab.lang.makeValidName(name)) = struct(...
                    'rmse', rmse, ...
                    'mae', mae, ...
                    'hit_rate', hit_rate, ...
                    'sharpe', sharpe);
            end
        end
    end
    
    methods (Static, Access = private)
        function alpha_opt = optimize_ses_alpha(series)
            % Find optimal alpha for SES via grid search
            alphas = 0.01:0.01:0.99;
            errors = zeros(size(alphas));
            
            for a_idx = 1:length(alphas)
                alpha = alphas(a_idx);
                level = series(1);
                
                for t = 2:length(series)
                    level = alpha * series(t) + (1 - alpha) * level;
                    errors(a_idx) = errors(a_idx) + (series(t) - level)^2;
                end
            end
            
            [~, min_idx] = min(errors);
            alpha_opt = alphas(min_idx);
        end
    end
end
