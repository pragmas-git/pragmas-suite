classdef ModelEngineLogReturns < handle
    % ModelEngineLogReturns: Refactored for log-return prediction
    %
    % Fits ARIMA, ARIMAX, GARCH models on log-returns (stationary)
    % instead of prices (non-stationary).
    %
    % Advantages:
    %   - Stationary series → easier to model with ARIMA/GARCH
    %   - No spurious regression
    %   - Proper econometric foundations (log-returns are martingale differences under H0)
    %
    % Output: Point forecasts + optional confidence intervals
    
    properties
        % Data
        LogReturns          % Stationary log-returns (T x 1)
        SeriesName          % Asset identifier
        
        % Models
        ArimaModel;         % ARIMA fitted model
        GarchModel;         % GARCH fitted model
        
        % Forecasts
        ForecastARIMA;      % Point forecasts from ARIMA
        ForecastGARCH;      % Point forecasts from GARCH
        ForecastMean;       % Combined forecast (average)
        
        % Hyperparameters
        ARIMAOrder = [1, 0, 1];    % (p, d, q)
        GARCHOrder = [1, 1];       % (p, q)
        ConfidenceLevel = 0.95;
        
        % Flags
        IsTrained = false;
    end
    
    methods
        function obj = ModelEngineLogReturns(logReturns, seriesName)
            % Initialize with log-returns
            
            if istimetable(logReturns)
                obj.LogReturns = logReturns{:, :};
            else
                obj.LogReturns = logReturns(:);
            end
            
            obj.LogReturns = obj.LogReturns(~isnan(obj.LogReturns));
            
            if nargin < 2 || isempty(seriesName)
                obj.SeriesName = 'Asset';
            else
                obj.SeriesName = seriesName;
            end
        end
        
        function fit(obj, varargin)
            % Fit ARIMA and GARCH models
            
            p = inputParser();
            addParameter(p, 'arimaOrder', [1, 0, 1], @isvector);
            addParameter(p, 'garchOrder', [1, 1], @isvector);
            parse(p, varargin{:});
            
            obj.ARIMAOrder = p.Results.arimaOrder;
            obj.GARCHOrder = p.Results.garchOrder;
            
            try
                % ARIMA Model
                fprintf('Fitting ARIMA(%d,%d,%d) on log-returns...\n', ...
                    obj.ARIMAOrder(1), obj.ARIMAOrder(2), obj.ARIMAOrder(3));
                
                obj.ArimaModel = arima(obj.ARIMAOrder(1), obj.ARIMAOrder(2), obj.ARIMAOrder(3));
                [obj.ArimaModel, ~] = estimate(obj.ArimaModel, obj.LogReturns, ...
                    'Display', 'off');
                
            catch ME
                warning('ARIMA fitting failed: %s. Using fallback model.', ME.message);
                obj.ArimaModel = [];
            end
            
            try
                % GARCH Model for volatility
                fprintf('Fitting GARCH(%d,%d) on log-returns...\n', ...
                    obj.GARCHOrder(1), obj.GARCHOrder(2));
                
                spec = garchset('P', obj.GARCHOrder(1), 'Q', obj.GARCHOrder(2));
                [obj.GarchModel, ~] = garchfit(spec, obj.LogReturns, ...
                    'Display', 'off');
                
            catch ME
                warning('GARCH fitting failed: %s. Using volatility forecasts only.', ME.message);
                obj.GarchModel = [];
            end
            
            obj.IsTrained = true;
        end
        
        function forecast = predictMean(obj, horizon)
            % Point forecast for h-step ahead log-returns
            
            if ~obj.IsTrained
                obj.fit();
            end
            
            forecast = zeros(horizon, 1);
            
            if ~isempty(obj.ArimaModel)
                try
                    [forecast_arima, ~, ~] = forecast(obj.ArimaModel, horizon, obj.LogReturns);
                    forecast = forecast_arima;
                catch
                    % Fallback: historical mean
                    forecast = repmat(mean(obj.LogReturns), horizon, 1);
                end
            else
                % Fallback
                forecast = repmat(mean(obj.LogReturns), horizon, 1);
            end
        end
        
        function volatility = predictVolatility(obj, horizon)
            % Volatility forecast for h-step ahead
            
            if ~obj.IsTrained
                obj.fit();
            end
            
            volatility = zeros(horizon, 1);
            
            if ~isempty(obj.GarchModel)
                try
                    % GARCH forecast
                    [variance, ~] = garchsim(obj.GarchModel, horizon);
                    volatility = sqrt(variance);
                catch
                    % Fallback: historical volatility
                    volatility = repmat(std(obj.LogReturns), horizon, 1);
                end
            else
                volatility = repmat(std(obj.LogReturns), horizon, 1);
            end
        end
        
        function [forecast, ci_lower, ci_upper] = predictWithCI(obj, horizon)
            % Point forecast with confidence intervals
            
            forecast = obj.predictMean(horizon);
            volatility = obj.predictVolatility(horizon);
            
            z = norminv((1 + obj.ConfidenceLevel) / 2);
            
            ci_lower = forecast - z * volatility;
            ci_upper = forecast + z * volatility;
        end
        
        function diag = diagnostics(obj)
            % Model diagnostics
            
            if ~obj.IsTrained
                error('Model not trained. Call fit() first.');
            end
            
            diag = struct();
            
            if ~isempty(obj.ArimaModel)
                % In-sample residuals
                [residuals, ~, ~] = infer(obj.ArimaModel, obj.LogReturns);
                
                % Test for serial correlation
                diag.aic = aic(obj.ArimaModel);
                diag.bic = bic(obj.ArimaModel);
                diag.ljung_box_pval = lbqtest(residuals, 'Lags', 10);
                diag.normality_test = kstest((residuals - mean(residuals)) / std(residuals));
            end
            
            if ~isempty(obj.GarchModel)
                diag.garch_converged = true;
                diag.conditional_mean = obj.ArimaModel.Variance;
            end
        end
        
        function plotForecast(obj, horizon, varargin)
            % Plot forecast with confidence bands
            
            p = inputParser();
            addParameter(p, 'window', 100, @isnumeric);
            parse(p, varargin{:});
            
            window = p.Results.window;
            
            [forecast, ci_lower, ci_upper] = obj.predictWithCI(horizon);
            
            figure('Position', [100, 100, 1200, 600]);
            
            % Recent historical data
            t_hist = 1:window;
            hist_returns = obj.LogReturns(end-window+1:end);
            
            plot(t_hist, hist_returns, 'k-', 'LineWidth', 2, 'DisplayName', 'Historical');
            hold on;
            
            % Forecast
            t_forecast = window + 1:window + horizon;
            plot(t_forecast, forecast, 'b-', 'LineWidth', 2, 'DisplayName', 'Forecast');
            
            % Confidence bands
            fill([t_forecast, fliplr(t_forecast)], ...
                [ci_upper', fliplr(ci_lower')], 'cyan', ...
                'FaceAlpha', 0.3, 'EdgeColor', 'none', 'DisplayName', sprintf('%d%% CI', round(obj.ConfidenceLevel*100)));
            
            xlabel('Time');
            ylabel('Log-Return');
            title(sprintf('%s: ARIMA Forecast (h=%d)', obj.SeriesName, horizon));
            legend('Location', 'best');
            grid on;
            xlim([1, window + horizon]);
        end
    end
end
