classdef HybridValidator < handle
    % HYBRIDVALIDATOR Validación de modelos vía MCS y backtesting.
    %
    % Implementa Model Confidence Set (Hansen et al., 2011) para comparación
    % rigurosa de modelos. Calcula métricas financieras (Sharpe, Sortino, MDD)
    % y genera reportes de performance.
    %
    % Uso típico:
    %   models = {{'ARIMA-GARCH', preds_ag, actuals}; ...
    %             {'LSTM', preds_lstm, actuals}; ...
    %             {'CNN', preds_cnn, actuals}};
    %   validator = pragmas.validation.HybridValidator(models);
    %   validator.computeMCS(0.05);
    %   validator.computeMetrics();
    %   results = validator.getSummary();
    %   validator.plotComparison();
    %
    % Nota: MCS simplificado; para full Hansen+bootstrap ver literatura.
    
    properties
        % Datos de validación
        Models                  % Cell array: {name, predictions, actuals}
        ModelNames              % Cell array de nombres de modelos
        Predictions             % Matriz (numObs x numModels)
        Actuals                 % Vector de actuals
        
        % Losses y criterios
        Losses                  % Matriz de losses (MSE, MAE, etc.)
        LossType                % Tipo de loss: 'MSE' (default), 'MAE', 'MAPE'
        
        % MCS Results
        MCSSet                  % Celda de nombres en MCS al alpha
        MCSIndices              % Índices de modelos en MCS
        Alpha                   % Nivel de significancia MCS (default: 0.05)
        PValues                 % P-values de superiority tests
        
        % Métricas financieras
        Metrics                 % Struct array con Sharpe, Sortino, MDD, etc.
        
        % Backtesting
        CumulativeReturns       % Retornos acumulados por modelo
        MaxDD                   % Maximum Drawdown por modelo
        SharpeRatios            % Sharpe ratio por modelo
    end
    
    methods
        %% Constructor
        function obj = HybridValidator(models, lossType)
            % HYBRIDVALIDATOR Inicializa validador.
            %
            % Input:
            %   models: Cell array {name, preds, actuals} para cada modelo
            %   lossType: 'MSE' (default), 'MAE', 'MAPE'
            
            if nargin < 2
                lossType = 'MSE';
            end
            
            obj.LossType = lossType;
            obj.Alpha = 0.05;
            obj.Models = models;
            
            % Extraer componentes
            numModels = size(models, 1);
            obj.ModelNames = cell(numModels, 1);
            
            maxLen = 0;
            for m = 1:numModels
                obj.ModelNames{m} = models{m, 1};
                maxLen = max(maxLen, length(models{m, 2}));
            end
            
            % Inicializar matrices alineadas
            obj.Predictions = zeros(maxLen, numModels);
            obj.Actuals = zeros(maxLen, 1);
            
            for m = 1:numModels
                preds = models{m, 2}(:);
                actuals = models{m, 3}(:);
                
                % Alinear longitudes (rellenar últimas con NaN si necesario)
                nP = length(preds);
                nA = length(actuals);
                nCommon = min(nP, nA);
                
                obj.Predictions(1:nCommon, m) = preds(1:nCommon);
                if m == 1
                    obj.Actuals(1:nCommon) = actuals(1:nCommon);
                end
            end
            
            % Truncar a observaciones comunes
            validIdx = ~any(isnan(obj.Predictions), 2) & ~isnan(obj.Actuals);
            obj.Predictions = obj.Predictions(validIdx, :);
            obj.Actuals = obj.Actuals(validIdx);
            
            fprintf('HybridValidator inicializado con %d modelos, %d observaciones comunes\n', ...
                numModels, length(obj.Actuals));
        end
        
        %% Cálculo de Losses
        function computeLosses(obj)
            % COMPUTELOSSES Calcula losses (MSE, MAE, MAPE).
            
            numObs = length(obj.Actuals);
            numModels = size(obj.Predictions, 2);
            
            obj.Losses = zeros(numObs, numModels);
            
            switch obj.LossType
                case 'MSE'
                    obj.Losses = (obj.Predictions - obj.Actuals).^2;
                case 'MAE'
                    obj.Losses = abs(obj.Predictions - obj.Actuals);
                case 'MAPE'
                    % MAPE: Mean Absolute Percentage Error (evita división por cero)
                    epsilon = 1e-8;
                    obj.Losses = abs((obj.Predictions - obj.Actuals) ./ (abs(obj.Actuals) + epsilon));
                otherwise
                    error('Loss type no soportada.');
            end
        end
        
        %% Model Confidence Set (Hansen et al., 2011)
        function computeMCS(obj, alpha)
            % COMPUTEMCS Calcula Model Confidence Set simplificado.
            %
            % Nota: Implementación simplificada. Full MCS requiere:
            %   - Bootstrap de pérdidas
            %   - Test de superioridad (t-max statistic)
            %   - Procedimiento iterativo de eliminación
            % Esta versión usa diferencia de medias + filtrado conservador.
            
            if nargin < 2
                alpha = obj.Alpha;
            else
                obj.Alpha = alpha;
            end
            
            obj.computeLosses();  % Asegurar que losses estén calculados
            
            numModels = size(obj.Predictions, 2);
            meanLosses = mean(obj.Losses, 1);  % Media de loss por modelo
            
            % Calcular p-values simplificados (t-test respecto al mejor)
            [bestLoss, bestIdx] = min(meanLosses);
            bestLossVec = obj.Losses(:, bestIdx);
            obj.PValues = ones(numModels, 1);
            
            for m = 1:numModels
                if m ~= bestIdx
                    lossVec = obj.Losses(:, m);
                    diff = lossVec - bestLossVec;
                    tstat = mean(diff) / (std(diff) / sqrt(length(diff)) + eps);
                    % P-value aproximado (one-sided)
                    obj.PValues(m) = 1 - normcdf(tstat);
                end
            end
            
            % MCS: modelos con p-value > alpha (no significativamente peor que el mejor)
            obj.MCSIndices = find(obj.PValues >= (1 - alpha));
            obj.MCSSet = obj.ModelNames(obj.MCSIndices);
            
            fprintf('\n========== Model Confidence Set (α=%.2f) ==========\n', alpha);
            fprintf('Modelos en MCS (no significativamente inferiores):\n');
            for i = 1:length(obj.MCSSet)
                idx = obj.MCSIndices(i);
                fprintf('  %s: mean %s=%.6f, p-value=%.4f\n', ...
                    obj.MCSSet{i}, obj.LossType, meanLosses(idx), obj.PValues(idx));
            end
            fprintf('Modelos excluidos de MCS:\n');
            excludedIdx = setdiff(1:numModels, obj.MCSIndices);
            for i = 1:length(excludedIdx)
                idx = excludedIdx(i);
                fprintf('  %s: mean %s=%.6f, p-value=%.4f\n', ...
                    obj.ModelNames{idx}, obj.LossType, meanLosses(idx), obj.PValues(idx));
            end
            fprintf('==================================================\n\n');
        end
        
        %% Métricas Financieras
        function computeMetrics(obj)
            % COMPUTEMETRICS Calcula métricas de riesgo/retorno.
            
            numModels = size(obj.Predictions, 2);
            obj.Metrics = struct();
            
            for m = 1:numModels
                preds = obj.Predictions(:, m);
                actuals = obj.Actuals;
                
                % Suasar NaNs si existen
                validIdx = ~isnan(preds) & ~isnan(actuals);
                preds = preds(validIdx);
                actuals = actuals(validIdx);
                
                % Errores
                errors = preds - actuals;
                
                % RMSE y MAE
                rmse = sqrt(mean(errors.^2));
                mae = mean(abs(errors));
                
                % Directionalidad (accuracy)
                correctDir = sign(preds) == sign(actuals);
                hitRate = mean(correctDir);
                
                % Retornos (asumir preds/actuals son retornos)
                cumRet = cumprod(1 + actuals) - 1;  % Retorno acumulado
                totalRet = cumRet(end);
                
                % Volatilidad anualizada (252 días/año)
                annualVol = std(actuals) * sqrt(252);
                
                % Sharpe Ratio (asume rf=0)
                sharpe = mean(actuals) / (std(actuals) + eps) * sqrt(252);
                
                % Sortino Ratio (solo downside volatility)
                downReturnsSigma = std(actuals(actuals < 0));
                sortino = mean(actuals) / (downReturnsSigma + eps) * sqrt(252);
                
                % Maximum Drawdown
                cumRetPreds = cumprod(1 + preds) - 1;
                runningMax = cummax(cumRetPreds);
                drawdown = (cumRetPreds - runningMax) ./ (runningMax + eps);
                maxDD = min(drawdown);
                
                % Calmar Ratio
                calmar = totalRet / abs(maxDD + eps);
                
                % Guardar en struct
                obj.Metrics(m).Name = obj.ModelNames{m};
                obj.Metrics(m).RMSE = rmse;
                obj.Metrics(m).MAE = mae;
                obj.Metrics(m).HitRate = hitRate;
                obj.Metrics(m).TotalReturn = totalRet;
                obj.Metrics(m).AnnualVol = annualVol;
                obj.Metrics(m).SharpeRatio = sharpe;
                obj.Metrics(m).SortinoRatio = sortino;
                obj.Metrics(m).MaxDD = maxDD;
                obj.Metrics(m).CalmarRatio = calmar;
            end
            
            obj.SharpeRatios = [obj.Metrics.SharpeRatio]';
            obj.MaxDD = [obj.Metrics.MaxDD]';
            obj.CumulativeReturns = [obj.Metrics.TotalReturn]';
        end
        
        %% Resumen de Resultados
        function results = getSummary(obj)
            % GETSUMMARY Retorna tabla con métricas principales.
            
            if isempty(obj.Metrics)
                obj.computeMetrics();
            end
            
            numModels = length(obj.Metrics);
            results = table(...
                obj.ModelNames, ...
                [obj.Metrics.RMSE]', ...
                [obj.Metrics.MAE]', ...
                [obj.Metrics.HitRate]', ...
                [obj.Metrics.SharpeRatio]', ...
                [obj.Metrics.SortinoRatio]', ...
                [obj.Metrics.MaxDD]', ...
                [obj.Metrics.CalmarRatio]', ...
                'VariableNames', ...
                {'Model', 'RMSE', 'MAE', 'HitRate', 'Sharpe', 'Sortino', 'MaxDD', 'Calmar'});
        end
        
        %% Visualización
        function plotComparison(obj)
            % PLOTCOMPARISON Visualiza comparación de modelos.
            
            if isempty(obj.Metrics)
                obj.computeMetrics();
            end
            
            numModels = length(obj.Metrics);
            
            figure('Name', 'Hybrid Validator: Model Comparison', 'NumberTitle', 'off', ...
                'Position', [100, 100, 1400, 800]);
            
            % Subplot 1: Pronósticos vs Actuals
            subplot(2, 3, 1);
            hold on;
            plot(obj.Actuals, 'k-', 'LineWidth', 2, 'DisplayName', 'Actual');
            colors = lines(numModels);
            for m = 1:numModels
                plot(obj.Predictions(:, m), '--', 'Color', colors(m, :), ...
                    'DisplayName', obj.ModelNames{m});
            end
            title('Pronósticos vs Actuals', 'FontWeight', 'bold');
            xlabel('Tiempo');
            ylabel('Valor');
            legend('Location', 'best', 'FontSize', 9);
            grid on;
            hold off;
            
            % Subplot 2: Errores en tiempo
            subplot(2, 3, 2);
            errors = obj.Predictions - obj.Actuals;
            hold on;
            for m = 1:numModels
                plot(errors(:, m), 'Color', colors(m, :), 'DisplayName', obj.ModelNames{m});
            end
            yline(0, 'k--', 'LineWidth', 1);
            title('Errores de Predicción', 'FontWeight', 'bold');
            xlabel('Tiempo');
            ylabel('Error');
            legend('Location', 'best', 'FontSize', 9);
            grid on;
            hold off;
            
            % Subplot 3: RMSE comparison
            subplot(2, 3, 3);
            rmses = [obj.Metrics.RMSE];
            [~, bestRMSE] = min(rmses);
            bars = bar(1:numModels, rmses, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'black');
            bars(bestRMSE).FaceColor = [0.2 0.8 0.2];
            set(gca, 'XTickLabel', obj.ModelNames);
            title('RMSE por Modelo', 'FontWeight', 'bold');
            ylabel('RMSE');
            grid on;
            
            % Subplot 4: Sharpe Ratio
            subplot(2, 3, 4);
            sharpes = [obj.Metrics.SharpeRatio];
            [~, bestSharpe] = max(sharpes);
            bars = bar(1:numModels, sharpes, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'black');
            bars(bestSharpe).FaceColor = [0.2 0.8 0.2];
            set(gca, 'XTickLabel', obj.ModelNames);
            title('Sharpe Ratio por Modelo', 'FontWeight', 'bold');
            ylabel('Sharpe Ratio');
            yline(0, 'k--', 'LineWidth', 1);
            grid on;
            
            % Subplot 5: Maximum Drawdown
            subplot(2, 3, 5);
            mdds = [obj.Metrics.MaxDD];
            [~, bestMDD] = max(mdds);  % Menos negativo es mejor
            bars = bar(1:numModels, mdds, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'black');
            bars(bestMDD).FaceColor = [0.2 0.8 0.2];
            set(gca, 'XTickLabel', obj.ModelNames);
            title('Maximum Drawdown', 'FontWeight', 'bold');
            ylabel('Max DD');
            yline(0, 'k--', 'LineWidth', 1);
            grid on;
            
            % Subplot 6: MCS visualization
            subplot(2, 3, 6);
            if ~isempty(obj.MCSIndices)
                inMCS = ismember(1:numModels, obj.MCSIndices);
                colors_mcs = zeros(numModels, 3);
                colors_mcs(inMCS, :) = repmat([0.2 0.8 0.2], sum(inMCS), 1);  % Verde
                colors_mcs(~inMCS, :) = repmat([0.8 0.2 0.2], sum(~inMCS), 1);  % Rojo
            else
                colors_mcs = repmat([0.3 0.6 0.9], numModels, 1);
            end
            
            meanLosses = mean(obj.Losses, 1);
            bars = bar(1:numModels, meanLosses, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'black');
            for m = 1:numModels
                bars(m).FaceColor = colors_mcs(m, :);
            end
            set(gca, 'XTickLabel', obj.ModelNames);
            title(sprintf('Mean %s (MCS en verde)', obj.LossType), 'FontWeight', 'bold');
            ylabel(sprintf('Mean %s', obj.LossType));
            grid on;
            
            sgtitle('pragmas-suite Phase 3: Hybrid Validator', 'FontSize', 14, 'FontWeight', 'bold');
        end
        
        %% Información
        function disp(obj)
            % DISP Muestra resumen del validador.
            
            fprintf('\n========== HybridValidator Summary ==========\n');
            fprintf('Modelos a validar:\n');
            for m = 1:length(obj.ModelNames)
                fprintf('  %d. %s\n', m, obj.ModelNames{m});
            end
            fprintf('\nObservaciones: %d (comunes a todos los modelos)\n', length(obj.Actuals));
            fprintf('Tipo de loss: %s\n', obj.LossType);
            fprintf('Nivel MCS (α): %.2f\n', obj.Alpha);
            
            if ~isempty(obj.Metrics)
                fprintf('\nMétricas calculadas: Sí\n');
            else
                fprintf('\nMétricas calculadas: No (ejecuta computeMetrics primero)\n');
            end
            
            if ~isempty(obj.MCSSet)
                fprintf('MCS Set: %s\n', strjoin(obj.MCSSet, ', '));
            else
                fprintf('MCS Set: No calculado (ejecuta computeMCS primero)\n');
            end
            fprintf('==========================================\n\n');
        end
    end
end
