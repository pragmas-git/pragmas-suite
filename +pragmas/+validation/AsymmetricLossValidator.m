classdef AsymmetricLossValidator
    % AsymmetricLossValidator: Directional prediction metrics
    %
    % Implements loss functions that account for asymmetric economic costs:
    % - Pinball Loss (quantile regression): Penalizes over/under-prediction asymmetrically
    % - Directional Accuracy: % correct direction predictions
    % - Mean Directional Error (MDE): Average direction sign agreement
    % - Utility-aware Loss: Penalizes wrong direction more than magnitude errors
    %
    % Financial Reality: Missing upside (false negative) costs more than overshooting
    % References: Koenker (2005), Quantile Regression; Christoffersen (2011)
    
    properties
        quantiles = [0.05, 0.25, 0.5, 0.75, 0.95];  % Default quantiles
        loss_function = 'pinball';                   % Loss function type
        confidence_level = 0.95;
    end
    
    methods
        function obj = AsymmetricLossValidator(varargin)
            p = inputParser();
            addParameter(p, 'quantiles', [0.05, 0.25, 0.5, 0.75, 0.95], @isvector);
            addParameter(p, 'loss_function', 'pinball', @ischar);
            addParameter(p, 'confidence_level', 0.95, @isnumeric);
            parse(p, varargin{:});
            
            obj.quantiles = p.Results.quantiles;
            obj.loss_function = p.Results.loss_function;
            obj.confidence_level = p.Results.confidence_level;
        end
        
        function loss_val = pinballLoss(obj, actuals, forecasts, varargin)
            % Pinball Loss (Quantile Loss)
            % L_τ(y, q) = (y - q) * (τ - I{y < q})
            %
            % Inputs:
            %   actuals: Actual values (T x 1)
            %   forecasts: Point forecasts (T x 1) OR quantile forecasts (T x nq)
            % Outputs:
            %   loss_val: Scalar loss value (mean pinball loss)
            
            p = inputParser();
            addParameter(p, 'quantile', 0.5, @isnumeric);  % Which quantile to evaluate
            parse(p, varargin{:});
            
            tau = p.Results.quantile;
            
            % If forecasts has multiple columns (quantiles), select the one closest to tau
            if size(forecasts, 2) > 1
                [~, idx] = min(abs(obj.quantiles - tau));
                forecast = forecasts(:, idx);
            else
                forecast = forecasts;
            end
            
            % Pinball loss
            errors = actuals - forecast;
            loss_val = mean(max(tau * errors, (tau - 1) * errors));
        end
        
        function loss_struct = pinballLossMultiQuantile(obj, actuals, forecasts)
            % Evaluate pinball loss for multiple quantiles
            % Inputs:
            %   actuals: Actual values (T x 1)
            %   forecasts: Quantile forecasts (T x nq) where nq = length(obj.quantiles)
            % Outputs:
            %   loss_struct: Struct with loss for each quantile + mean
            
            nq = size(forecasts, 2);
            
            loss_struct = struct();
            losses = zeros(nq, 1);
            
            for q = 1:nq
                tau = obj.quantiles(q);
                errors = actuals - forecasts(:, q);
                losses(q) = mean(max(tau * errors, (tau - 1) * errors));
                
                loss_struct.(sprintf('q%02d', round(tau * 100))) = losses(q);
            end
            
            loss_struct.mean = mean(losses);
            loss_struct.weighted = sum(losses .* abs(obj.quantiles - 0.5)) / sum(abs(obj.quantiles - 0.5));
        end
        
        function dir_acc = directionalAccuracy(obj, actuals, forecasts)
            % Directional Accuracy
            % Ratio: P(sign(y_t) = sign(ŷ_t))
            %
            % Perfect predictor would achieve >50% on stationary returns
            % Null hypothesis: 50% (random guessing)
            
            T = length(actuals);
            
            % Handle multi-column forecasts (take mean column)
            if size(forecasts, 2) > 1
                forecasts = mean(forecasts, 2);
            end
            
            % Signs
            sign_actual = sign(actuals);
            sign_forecast = sign(forecasts);
            
            % Count matches
            matches = (sign_actual == sign_forecast);
            dir_acc = sum(matches) / T;
        end
        
        function mde = meanDirectionalError(obj, actuals, forecasts)
            % Mean Directional Error (MDE)
            % Average of direction sign agreement weighted by magnitude
            %
            % Formula: MDE = mean(sign(y_t) * sign(ŷ_t))
            % Range: [-1, 1]
            %   +1: Perfect agreement on direction
            %    0: Random directions
            %   -1: Perfect disagreement
            
            T = length(actuals);
            
            if size(forecasts, 2) > 1
                forecasts = mean(forecasts, 2);
            end
            
            % Normalized errors
            y_norm = actuals / (max(abs(actuals)) + eps);
            yhat_norm = forecasts / (max(abs(forecasts)) + eps);
            
            % Product of signs
            mde = mean(sign(y_norm) .* sign(yhat_norm));
        end
        
        function loss_val = asymmetricMAPE(obj, actuals, forecasts, varargin)
            % Asymmetric MAPE: Penalize misses (false negatives) more
            % L = mean(max(α|e_t|, (1-α)|e_t|)) where e_t in (-1, +1)
            %
            % If α > 0.5: Penalize overestimation more
            % If α < 0.5: Penalize underestimation more
            
            p = inputParser();
            addParameter(p, 'alpha', 0.7, @isnumeric);  % Asymmetry parameter
            parse(p, varargin{:});
            
            alpha = p.Results.alpha;
            
            if size(forecasts, 2) > 1
                forecasts = mean(forecasts, 2);
            end
            
            % Normalized errors: scale to [-1, 1]
            max_range = max(abs([actuals; forecasts]));
            errors_norm = (actuals - forecasts) / (max_range + eps);
            
            % Asymmetric loss
            loss_val = mean(max(alpha * abs(errors_norm), (1 - alpha) * abs(errors_norm)));
        end
        
        function [loss_summary, ci] = quantileCoverageTest(obj, actuals, quantile_forecasts)
            % Test if empirical coverage matches predicted quantiles
            % For proper calibration: empirical_coverage ≈ nominal_coverage
            %
            % Inputs:
            %   actuals: Actual values (T x 1)
            %   quantile_forecasts: Quantile forecasts (T x nq)
            % Outputs:
            %   loss_summary: Coverage rates for each quantile
            %   ci: 95% confidence intervals for coverage rates
            
            nq = size(quantile_forecasts, 2);
            T = length(actuals);
            
            coverage_rates = zeros(nq, 1);
            ci_lower = zeros(nq, 1);
            ci_upper = zeros(nq, 1);
            
            for q = 1:nq
                tau = obj.quantiles(q);
                coverage = mean(actuals <= quantile_forecasts(:, q));
                coverage_rates(q) = coverage;
                
                % Binomial CI
                z = norminv((1 + obj.confidence_level) / 2);
                se = sqrt(coverage * (1 - coverage) / T);
                ci_lower(q) = coverage - z * se;
                ci_upper(q) = coverage + z * se;
            end
            
            % Summary struct
            loss_summary = struct();
            for q = 1:nq
                tau = obj.quantiles(q);
                loss_summary.(sprintf('q%02d', round(tau * 100))) = struct(...
                    'nominal', tau, ...
                    'empirical', coverage_rates(q), ...
                    'ci_lower', ci_lower(q), ...
                    'ci_upper', ci_upper(q), ...
                    'miscalibration', abs(coverage_rates(q) - tau));
            end
            
            ci = table(obj.quantiles(:), coverage_rates, ci_lower, ci_upper, ...
                'VariableNames', {'Quantile', 'Empirical_Coverage', 'CI_Lower', 'CI_Upper'});
        end
        
        function plot_quantile_intervals(obj, actuals, quantile_forecasts, varargin)
            % Visualize quantile predictions vs actuals
            % Shows 5%, 25%, 50%, 75%, 95% intervals
            
            p = inputParser();
            addParameter(p, 'window_size', min(500, length(actuals)), @isnumeric);
            parse(p, varargin{:});
            
            window = p.Results.window_size;
            
            figure('Position', [100, 100, 1200, 600]);
            
            % Time indices
            t = 1:window;
            
            % Plot actuals
            plot(t, actuals(1:window), 'k-', 'LineWidth', 2, 'DisplayName', 'Actual');
            hold on;
            
            % Plot quantiles
            colors = parula(size(quantile_forecasts, 2));
            for q = 1:size(quantile_forecasts, 2)
                plot(t, quantile_forecasts(1:window, q), '--', 'Color', colors(q, :), ...
                    'DisplayName', sprintf('q=%.0f%%', obj.quantiles(q)*100));
            end
            
            % Fill confidence band (5%-95%)
            fill([t, fliplr(t)], [quantile_forecasts(1:window, 1)', fliplr(quantile_forecasts(1:window, end)')], ...
                'cyan', 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', '90% Band');
            
            xlabel('Time (t)');
            ylabel('Value');
            title('Quantile Interval Forecasts');
            legend('Location', 'best');
            grid on;
            hold off;
        end
        
        function metrics = comprehensiveEvaluation(obj, actuals, forecasts_struct)
            % All-in-one evaluation combining multiple loss functions
            % Inputs:
            %   actuals: Actual values (T x 1)
            %   forecasts_struct: Struct with fields:
            %       - point: Point forecasts (T x 1)
            %       - quantiles: Quantile forecasts (T x nq)
            %
            % Outputs:
            %   metrics: Comprehensive struct with all metrics
            
            metrics = struct();
            
            % Directional metrics (work with point or mean forecast)
            if isfield(forecasts_struct, 'point')
                forecast_point = forecasts_struct.point;
            else
                forecast_point = mean(forecasts_struct.quantiles, 2);
            end
            
            metrics.directional_accuracy = obj.directionalAccuracy(actuals, forecast_point);
            metrics.mean_directional_error = obj.meanDirectionalError(actuals, forecast_point);
            
            % Quantile metrics
            if isfield(forecasts_struct, 'quantiles')
                pinball_loss = obj.pinballLossMultiQuantile(actuals, forecasts_struct.quantiles);
                metrics.pinball_loss = pinball_loss;
                
                [coverage, ci_table] = obj.quantileCoverageTest(actuals, forecasts_struct.quantiles);
                metrics.coverage = coverage;
                metrics.coverage_ci = ci_table;
            end
            
            % Standard loss functions (for comparison)
            metrics.rmse = sqrt(mean((actuals - forecast_point).^2));
            metrics.mae = mean(abs(actuals - forecast_point));
            metrics.mape = mean(abs((actuals - forecast_point) ./ (abs(actuals) + eps)));
        end
    end
end
