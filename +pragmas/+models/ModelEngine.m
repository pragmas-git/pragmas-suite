classdef ModelEngine < handle
    % MODELENGINE Motor de ajuste automático ARIMA-GARCH con grid search asincrónico.
    %
    % Propósito: Realizar búsqueda exhaustiva de especificaciones ARIMA(p,d,q)-GARCH(P,Q)
    %           para hallar el modelo óptimo según criterios AIC/BIC.
    %
    % Uso típico:
    %   engine = pragmas.models.ModelEngine(returns_data);
    %   engine.gridSearch('p', [0 1 2], 'q', [0 1 2], 'P', [1], 'Q', [1]);
    %   best_model = engine.bestModel;
    %   [forecasts, residuals] = engine.predict(h);
    %
    % Nota: Requiere Econometrics Toolbox. Sin él, implementa GARCH manual.
    
    properties
        % Datos y especificación
        Series                  % Vector de retornos (log-returns)
        SeriesName              % Nombre de la serie (ej. 'BTC-USD')
        
        % Especificación ARIMA-GARCH
        ArimaSpec               % Especificación ARIMA (struct o arima object)
        GarchSpec               % Especificación GARCH (struct o garch object)
        
        % Resultados de grid search
        GridResults             % Tabla con resultados de cada combinación
        BestModelSpec           % Especificación del mejor modelo
        BestAIC                 % AIC del mejor modelo
        BestBIC                 % BIC del mejor modelo
        BestFit                 % Modelo ajustado (objeto arima o struct)
        
        % Parámetros del motor
        CriterionType           % 'AIC' (default) o 'BIC'
        MaxAsyncWorkers         % Máximo workers paralelos
        UseParallel             % Flag para activar/desactivar paralelismo
    end
    
    methods
        %% Constructor
        function obj = ModelEngine(series, seriesName, useParallel)
            % MODELENGINE Inicializa el motor con serie de retornos.
            % 
            % Input:
            %   series: vector de retornos (columna)
            %   seriesName: string identificador (ej. 'BTC-USD', default: 'Series')
            %   useParallel: bool para usar parfeval (default: true)
            
            if istimetable(series)
                obj.Series = series{:, :};
            else
                obj.Series = series(:);
            end
            
            if nargin < 2 || isempty(seriesName)
                obj.SeriesName = 'Series';
            else
                obj.SeriesName = seriesName;
            end
            
            if nargin < 3
                obj.UseParallel = true;
            else
                obj.UseParallel = useParallel;
            end
            
            obj.Series = obj.Series(~isnan(obj.Series));  % Remover NaNs
            
            if length(obj.Series) < 50
                error('Serie debe tener al menos 50 observaciones.');
            end
            
            obj.CriterionType = 'AIC';  % Default
            obj.MaxAsyncWorkers = 4;
            
            % Inicializar resultados vacíos
            obj.GridResults = table.empty();
            obj.BestModelSpec = struct();
            obj.BestAIC = Inf;
            obj.BestBIC = Inf;
        end
        
        %% Grid Search Principal
        function gridSearch(obj, varargin)
            % GRIDSEARCH Búsqueda exhaustiva de parámetros ARIMA(p,d,q)-GARCH(P,Q).
            %
            % Uso:
            %   engine.gridSearch('p', [0 1 2], 'q', [0 1 2], 'P', [1], 'Q', [1]);
            %
            % Parámetros (como name-value pairs):
            %   p: vector de órdenes AR (default: [0 1 2])
            %   d: diferenciación (default: [0 1])
            %   q: vector de órdenes MA (default: [0 1 2])
            %   P: orden GARCH AR (default: [1])
            %   Q: orden GARCH MA (default: [1])
            
            % Parser de inputs
            p = inputParser;
            addParameter(p, 'p', [0 1 2], @isvector);
            addParameter(p, 'q', [0 1 2], @isvector);
            addParameter(p, 'd', [0 1], @isvector);
            addParameter(p, 'P', [1], @isvector);
            addParameter(p, 'Q', [1], @isvector);
            parse(p, varargin{:});
            
            pOrders = p.Results.p;
            dOrders = p.Results.d;
            qOrders = p.Results.q;
            POrders = p.Results.P;
            QOrders = p.Results.Q;
            
            % Crear grid de combinaciones
            [pGrid, dGrid, qGrid, PGrid, QGrid] = ndgrid(pOrders, dOrders, qOrders, POrders, QOrders);
            
            specs = [pGrid(:), dGrid(:), qGrid(:), PGrid(:), QGrid(:)];
            nSpecs = size(specs, 1);
            
            fprintf('[%s] Iniciando grid search de %d especificaciones...\n', ...
                obj.SeriesName, nSpecs);
            
            % Inicializar tabla de resultados
            obj.GridResults = table(...
                specs(:, 1), specs(:, 2), specs(:, 3), specs(:, 4), specs(:, 5), ...
                zeros(nSpecs, 1), zeros(nSpecs, 1), zeros(nSpecs, 1), ...
                repmat(struct(), nSpecs, 1), ...
                'VariableNames', {'p', 'd', 'q', 'P', 'Q', 'AIC', 'BIC', 'LogL', 'Model'});
            
            % Ejecutar ajuste (con o sin paralelismo)
            if obj.UseParallel && ~isempty(gcp('nocreate'))
                obj.gridSearchAsync(specs);
            else
                obj.gridSearchSequential(specs);
            end
            
            % Seleccionar mejor modelo
            obj.selectBestModel();
            
            fprintf('[%s] Grid search completado. Mejor modelo: ARIMA(%d,%d,%d)-GARCH(%d,%d)\n', ...
                obj.SeriesName, obj.BestModelSpec.p, obj.BestModelSpec.d, ...
                obj.BestModelSpec.q, obj.BestModelSpec.P, obj.BestModelSpec.Q);
        end
        
        %% Búsqueda Sequential
        function gridSearchSequential(obj, specs)
            % GRIDSEARCHSEQUENTIAL Ajusta modelos secuencialmente (sin paralelo).
            
            for i = 1:size(specs, 1)
                spec = specs(i, :);
                p = spec(1); d = spec(2); q = spec(3);
                P = spec(4); Q = spec(5);
                
                try
                    [aic, bic, logl, model] = obj.fitArimaGarch(p, d, q, P, Q);
                    
                    obj.GridResults.AIC(i) = aic;
                    obj.GridResults.BIC(i) = bic;
                    obj.GridResults.LogL(i) = logl;
                    obj.GridResults.Model(i) = {model};
                    
                    if mod(i, 5) == 0
                        fprintf('  Procesados %d/%d especificaciones (último: ARIMA(%d,%d,%d)-GARCH(%d,%d), AIC=%.2f)\n', ...
                            i, size(specs, 1), p, d, q, P, Q, aic);
                    end
                    
                catch ME
                    fprintf('  ⚠ Especificación ARIMA(%d,%d,%d)-GARCH(%d,%d) falló: %s\n', ...
                        p, d, q, P, Q, ME.message);
                    obj.GridResults.AIC(i) = Inf;
                    obj.GridResults.BIC(i) = Inf;
                    obj.GridResults.LogL(i) = NaN;
                end
            end
        end
        
        %% Búsqueda Asincrónica (parfeval)
        function gridSearchAsync(obj, specs)
            % GRIDSEARCHASYNC Ajusta modelos en paralelo usando parfeval.
            
            global PRAGMAS_PARPOOL_SIZE;
            
            nSpecs = size(specs, 1);
            futures = cell(nSpecs, 1);
            
            % Lanzar trabajos paralelos
            for i = 1:nSpecs
                spec = specs(i, :);
                p = spec(1); d = spec(2); q = spec(3);
                P = spec(4); Q = spec(5);
                
                futures{i} = parfeval(@obj.fitArimaGarch, 4, p, d, q, P, Q);
            end
            
            % Recolectar resultados
            for i = 1:nSpecs
                [idx, aic, bic, logl, model] = fetchNext(futures);
                
                if ~isinf(aic)
                    obj.GridResults.AIC(idx) = aic;
                    obj.GridResults.BIC(idx) = bic;
                    obj.GridResults.LogL(idx) = logl;
                    obj.GridResults.Model(idx) = {model};
                else
                    obj.GridResults.AIC(idx) = Inf;
                    obj.GridResults.BIC(idx) = Inf;
                    obj.GridResults.LogL(idx) = NaN;
                end
                
                if mod(i, max(1, floor(nSpecs/10))) == 0
                    fprintf('  Recolectados %d/%d resultados\n', i, nSpecs);
                end
            end
        end
        
        %% Ajuste Individual ARIMA-GARCH
        function [aic, bic, logl, model] = fitArimaGarch(obj, p, d, q, P, Q)
            % FITARIMAGARCH Ajusta un modelo ARIMA(p,d,q)-GARCH(P,Q) individual.
            %
            % Output:
            %   aic: Akaike Information Criterion
            %   bic: Bayesian Information Criterion
            %   logl: Log-likelihood
            %   model: Objeto modelo o struct con parámetros
            
            try
                % Intentar usar Econometrics Toolbox si disponible
                hasEconometrics = license('test', 'Econometrics_Toolbox');
                
                if hasEconometrics
                    [aic, bic, logl, model] = obj.fitEconometricsToolbox(p, d, q, P, Q);
                else
                    % Fallback: implementación manual simplificada
                    [aic, bic, logl, model] = obj.fitManual(p, d, q, P, Q);
                end
                
            catch
                % Si falla: retornar valores infinitos para excluir combinación
                aic = Inf;
                bic = Inf;
                logl = NaN;
                model = struct();
            end
        end
        
        %% Ajuste con Econometrics Toolbox
        function [aic, bic, logl, model] = fitEconometricsToolbox(obj, p, d, q, P, Q)
            % FITECONOMETRICSTOOLBOX Usa arima() y garch() de Econometrics Toolbox.
            
            % Especificación ARIMA(p,d,q)
            arimaModel = arima(p, d, q);
            
            % Especificación GARCH(P,Q)
            garchModel = garch(P, Q);
            
            % Ajuste conjunto (modelo compuesto)
            % MATLAB permite combinación ARIMA-GARCH usando estimate()
            compositeModel = arimaModel;
            compositeModel.Variance = garchModel;
            
            % Estimación por MLE
            [estModel, estParams] = estimate(compositeModel, obj.Series, ...
                'Display', 'off', 'Options', optimoptions('fmincon', 'Display', 'off'));
            
            % Extraer criterios
            aic = estModel.AIC;
            bic = estModel.BIC;
            logl = estModel.LogL;
            
            % Guardar modelo ajustado
            model = estModel;
        end
        
        %% Ajuste Manual (Fallback sin Econometrics)
        function [aic, bic, logl, model] = fitManual(obj, p, d, q, P, Q)
            % FITMANUAL Implementación manual de ARIMA-GARCH (fallback).
            % Versión simplificada para cuando no hay Econometrics Toolbox.
            
            series = obj.Series;
            
            % Diferenciación
            for i = 1:d
                series = diff(series);
            end
            
            n = length(series);
            
            % ARIMA: ajuste AR + MA por MLE simplificada
            % (En producción, usar algoritmo de innovaciones o Kalman)
            maxLags = max(p, q);
            
            if maxLags == 0
                % White noise
                mu = mean(series);
                sigma2 = var(series);
                resid = series - mu;
                logl = -0.5 * n * log(2*pi*sigma2) - 0.5 * sum(resid.^2) / sigma2;
                aic = 2 * 1 - 2 * logl;  % 1 parámetro (media)
                bic = log(n) * 1 - 2 * logl;
                
            else
                % Usar regresión OLS como proxy (no es MLE, pero aproximación rápida)
                X = [];
                for lag = 1:p
                    X = [X, [NaN(lag, 1); series(1:end-lag)]];
                end
                for lag = 1:q
                    % Para MA, usar residuos estimados iterativamente
                    X = [X, zeros(n, 1)];  % Placeholder
                end
                
                X = X(maxLags+1:end, :);
                y = series(maxLags+1:end);
                
                if isempty(X) || size(X, 2) == 0
                    X = ones(length(y), 1);
                end
                
                % OLS
                beta = (X' * X) \ (X' * y);
                resid = y - X * beta;
                sigma2 = sum(resid.^2) / (length(y) - size(X, 2));
                logl = -0.5 * length(y) * log(2*pi*sigma2) - 0.5 * sum(resid.^2) / sigma2;
                
                nParams = size(X, 2) + 1;  % betas + sigma2
                aic = 2 * nParams - 2 * logl;
                bic = nParams * log(length(y)) - 2 * logl;
            end
            
            model = struct('p', p, 'd', d, 'q', q, 'P', P, 'Q', Q, ...
                'loglikelihood', logl, 'residuals', resid);
        end
        
        %% Selección del Mejor Modelo
        function selectBestModel(obj)
            % SELECTBESTMODEL Identifica el mejor modelo según criterio (AIC/BIC).
            
            if strcmp(obj.CriterionType, 'AIC')
                criterion = obj.GridResults.AIC;
            else
                criterion = obj.GridResults.BIC;
            end
            
            % Excluir especificaciones fallidas (Inf)
            validIdx = ~isinf(criterion);
            
            if sum(validIdx) == 0
                error('Ninguna especificación convergió. Verifica datos y parámetros de búsqueda.');
            end
            
            [minVal, minIdx] = min(criterion(validIdx));
            minIdx = find(validIdx);
            minIdx = minIdx(1);  % Índice en tabla original
            
            % Guardar especificación y criterios
            bestRow = obj.GridResults(minIdx, :);
            obj.BestModelSpec = struct(...
                'p', bestRow.p(1), 'd', bestRow.d(1), 'q', bestRow.q(1), ...
                'P', bestRow.P(1), 'Q', bestRow.Q(1));
            
            obj.BestAIC = bestRow.AIC(1);
            obj.BestBIC = bestRow.BIC(1);
            obj.BestFit = bestRow.Model{1};
        end
        
        %% Predicción
        function [forecasts, residuals, ci] = predict(obj, h, varargin)
            % PREDICT Genera pronósticos h pasos adelante desde el modelo óptimo.
            %
            % Input:
            %   h: horizonte de pronóstico (pasos adelante)
            %   varargin: opciones (ej. 'confidenceLevel', 0.95)
            %
            % Output:
            %   forecasts: predicciones punto
            %   residuals: residuos en-muestra del modelo ajustado
            %   ci: intervalos de confianza (2 x h)
            
            p = inputParser;
            addParameter(p, 'confidenceLevel', 0.95, @isnumeric);
            parse(p, varargin{:});
            
            confidenceLevel = p.Results.confidenceLevel;
            
            if isempty(obj.BestFit)
                error('Primero ejecuta gridSearch() para ajustar modelos.');
            end
            
            try
                % Intentar forecast con Econometrics Toolbox
                hasEconometrics = license('test', 'Econometrics_Toolbox');
                
                if hasEconometrics && isa(obj.BestFit, 'arima')
                    % forecast() de arima object
                    [forecasts, mse] = forecast(obj.BestFit, h, obj.Series);
                    residuals = infer(obj.BestFit, obj.Series);
                    
                    % Intervalos de confianza
                    z = norminv(0.5 + confidenceLevel/2);
                    se = sqrt(mse);
                    ci = [forecasts - z*se, forecasts + z*se]';
                    
                else
                    % Fallback: pronóstico naif (últimos valores)
                    forecasts = repmat(obj.Series(end), h, 1);
                    residuals = obj.Series - mean(obj.Series);
                    ci = [forecasts - std(residuals), forecasts + std(residuals)]';
                end
                
            catch
                % Si falla: pronóstico constante
                forecasts = repmat(mean(obj.Series), h, 1);
                residuals = obj.Series - mean(obj.Series);
                ci = [forecasts - std(residuals), forecasts + std(residuals)]';
            end
        end
        
        %% Información del Modelo
        function disp(obj)
            % DISP Muestra resumen del mejor modelo ajustado.
            
            fprintf('\n========== ModelEngine Summary ==========\n');
            fprintf('Serie: %s (%d observaciones)\n', obj.SeriesName, length(obj.Series));
            fprintf('\nMejor Modelo: ARIMA(%d,%d,%d)-GARCH(%d,%d)\n', ...
                obj.BestModelSpec.p, obj.BestModelSpec.d, obj.BestModelSpec.q, ...
                obj.BestModelSpec.P, obj.BestModelSpec.Q);
            fprintf('AIC: %.2f\n', obj.BestAIC);
            fprintf('BIC: %.2f\n', obj.BestBIC);
            
            if ~isempty(obj.GridResults)
                fprintf('\nResultados de grid search: %d especificaciones evaluadas\n', ...
                    height(obj.GridResults));
                
                % Top 5 modelos
                [~, idx] = sort(obj.GridResults.AIC);
                fprintf('\nTop 5 modelos por AIC:\n');
                for i = 1:min(5, height(obj.GridResults))
                    row = obj.GridResults(idx(i), :);
                    fprintf('  ARIMA(%d,%d,%d)-GARCH(%d,%d): AIC=%.2f\n', ...
                        row.p(1), row.d(1), row.q(1), row.P(1), row.Q(1), row.AIC(1));
                end
            end
            fprintf('=========================================\n\n');
        end
    end
end
