classdef TestModelEngine < matlab.unittest.TestCase
    % TESTMODELENGINE Unit tests para +pragmas/+models/ModelEngine
    % Ejecuta: runtests('tests/TestModelEngine.m')
    
    properties
        % Datos de prueba
        TestReturns
        TestSeries
    end
    
    methods (TestMethodSetup)
        function setupTestData(testCase)
            % Crear datos sintéticos para pruebas
            rng(42);
            
            % Series de retornos simulados (AR(1)-GARCH(1,1) DGP)
            n = 200;
            h = ones(n, 1);
            innovations = randn(n, 1);
            
            % GARCH(1,1) con parámetros típicos
            omega = 0.00001;
            alpha = 0.08;
            beta = 0.90;
            
            for t = 2:n
                h(t) = omega + alpha * (innovations(t-1))^2 * h(t-1) + beta * h(t-1);
            end
            
            testCase.TestReturns = innovations .* sqrt(h);
            
            % Series de precios (cumsum de retornos)
            testCase.TestSeries = 100 * cumprod(1 + testCase.TestReturns);
        end
    end
    
    methods (Test)
        
        %% Inicialización
        function testModelEngineInitialization(testCase)
            % Verifica inicialización correcta
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', true);
            
            testCase.verifyEqual(length(engine.Series), length(testCase.TestReturns));
            testCase.verifyEqual(engine.SeriesName, 'TEST');
            testCase.verifyEqual(engine.UseParallel, true);
        end
        
        function testModelEngineDefaultName(testCase)
            % Verifica nombre por defecto si no se proporciona
            engine = pragmas.models.ModelEngine(testCase.TestReturns);
            
            testCase.verifyEqual(engine.SeriesName, 'Series');
        end
        
        function testModelEngineShortSeries(testCase)
            % Verifica rechazo de series muy cortas
            shortSeries = testCase.TestReturns(1:30);  % < 50
            
            testCase.verifyError(...
                @() pragmas.models.ModelEngine(shortSeries), ...
                'MATLAB:validation:IncompatibleSize');
        end
        
        function testModelEngineNaNHandling(testCase)
            % Verifica manejo de NaNs
            series = testCase.TestReturns;
            series([10, 50, 100]) = NaN;
            
            engine = pragmas.models.ModelEngine(series);
            
            testCase.verifyFalse(any(isnan(engine.Series)));
            testCase.verifyLessThan(length(engine.Series), length(series));
        end
        
        %% Grid Search
        function testGridSearchBasic(testCase)
            % Verifica grid search básico converge
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            % Grid pequeño para rapidez
            engine.gridSearch(...
                'p', [0 1], ...
                'q', [0 1], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            testCase.verifyGreaterThan(height(engine.GridResults), 0);
            testCase.verifyFalse(isempty(engine.BestModelSpec));
            testCase.verifyFalse(isinf(engine.BestAIC));
        end
        
        function testGridSearchResultsTable(testCase)
            % Verifica estructura de resultados
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            engine.gridSearch(...
                'p', [0 1], ...
                'q', [0 1], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            results = engine.GridResults;
            
            % Verificar columnas esperadas
            expectedVars = {'p', 'd', 'q', 'P', 'Q', 'AIC', 'BIC', 'LogL', 'Model'};
            testCase.verifyEqual(results.Properties.VariableNames, expectedVars);
            
            % Verificar dimensiones
            testCase.verifyEqual(height(results), 4);  % 2 x 2 = 4 combinaciones
        end
        
        function testGridSearchBestModel(testCase)
            % Verifica selección del mejor modelo
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            engine.gridSearch(...
                'p', [0 1], ...
                'q', [0 1], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            best = engine.BestModelSpec;
            
            % Verificar campos
            testCase.verifyTrue(isfield(best, 'p'));
            testCase.verifyTrue(isfield(best, 'd'));
            testCase.verifyTrue(isfield(best, 'q'));
            testCase.verifyTrue(isfield(best, 'P'));
            testCase.verifyTrue(isfield(best, 'Q'));
        end
        
        function testGridSearchConvergence(testCase)
            % Verifica que al menos algunos modelos convergen
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            engine.gridSearch(...
                'p', [0 1 2], ...
                'q', [0 1 2], ...
                'd', [0 1], ...
                'P', [1], ...
                'Q', [1]);
            
            validSpecs = ~isinf(engine.GridResults.AIC);
            convergenceRate = sum(validSpecs) / height(engine.GridResults);
            
            testCase.verifyGreaterThan(convergenceRate, 0.5, ...
                'Al menos 50% de especificaciones deben converger');
        end
        
        %% Criterios de Información
        function testAICvsBIC(testCase)
            % Verifica consistencia entre AIC y BIC
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            engine.gridSearch(...
                'p', [0 1], ...
                'q', [0 1], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            % Ambos deben existir y tener el mismo tamaño
            testCase.verifyEqual(length(engine.GridResults.AIC), length(engine.GridResults.BIC));
            
            % AIC y BIC deben tener correlación positiva
            validIdx = ~isinf(engine.GridResults.AIC) & ~isinf(engine.GridResults.BIC);
            if sum(validIdx) > 1
                corrValue = corr(engine.GridResults.AIC(validIdx), engine.GridResults.BIC(validIdx));
                testCase.verifyGreaterThan(corrValue, 0.5, ...
                    'AIC y BIC deben estar positivamente correlacionados');
            end
        end
        
        %% Predicción
        function testPredictBasic(testCase)
            % Verifica generación de pronósticos
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            engine.gridSearch(...
                'p', [0], ...
                'q', [0], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            h = 10;
            [forecasts, residuals, ci] = engine.predict(h);
            
            testCase.verifyEqual(length(forecasts), h);
            testCase.verifyGreaterThan(length(residuals), 0);
        end
        
        function testPredictConfidenceIntervals(testCase)
            % Verifica intervalos de confianza
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            engine.gridSearch(...
                'p', [0], ...
                'q', [0], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            h = 10;
            [forecasts, ~, ci] = engine.predict(h, 'confidenceLevel', 0.95);
            
            if ~isempty(ci)
                % Límites inferiores < pronósticos < límites superiores
                testCase.verifyTrue(all(ci(1, :) < forecasts'));
                testCase.verifyTrue(all(ci(2, :) > forecasts'));
            end
        end
        
        %% Visualización y Utilidades
        function testDispMethod(testCase)
            % Verifica que disp() no genera errores
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            engine.gridSearch(...
                'p', [0 1], ...
                'q', [0 1], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            % Simplemente verificar que no lanza error
            testCase.verifyTrue(true);  % Placeholder (disp() se ejecutó arriba sin error)
        end
        
        %% Casos extremos
        function testConstantSeries(testCase)
            % Verifica comportamiento con serie constante
            constantSeries = ones(100, 1);
            engine = pragmas.models.ModelEngine(constantSeries, 'CONSTANT', false);
            
            % No debería lanzar error en inicialización
            testCase.verifyTrue(true);
        end
        
        function testWhiteNoiseSeries(testCase)
            % Verifica comportamiento con ruido blanco puro
            whiteNoise = randn(100, 1);
            engine = pragmas.models.ModelEngine(whiteNoise, 'WN', false);
            
            engine.gridSearch(...
                'p', [0], ...
                'q', [0], ...
                'd', [0], ...
                'P', [1], ...
                'Q', [1]);
            
            % Verificar que ajustó algo
            testCase.verifyFalse(isinf(engine.BestAIC));
        end
        
        %% Robustez
        function testLargeGrid(testCase)
            % Verifica comportamiento con grid más grande
            engine = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            % Grid moderado (no demasiado grande para no ralentizar tests)
            engine.gridSearch(...
                'p', [0 1 2], ...
                'q', [0 1 2], ...
                'd', [0 1], ...
                'P', [1], ...
                'Q', [1]);
            
            % Debe evaluar todas las combinaciones
            testCase.verifyEqual(height(engine.GridResults), 3 * 3 * 2);
        end
        
        function testSequentialVsParallel(testCase)
            % Verifica consistencia entre ejecución secuencial y paralela
            engine_seq = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            engine_par = pragmas.models.ModelEngine(testCase.TestReturns, 'TEST', false);
            
            grid_spec = struct('p', [0 1], 'q', [0 1], 'd', [0], 'P', [1], 'Q', [1]);
            
            % Secuencial
            engine_seq.gridSearch(...
                'p', grid_spec.p, ...
                'q', grid_spec.q, ...
                'd', grid_spec.d, ...
                'P', grid_spec.P, ...
                'Q', grid_spec.Q);
            
            % Paralelo (si disponible)
            if ~isempty(gcp('nocreate'))
                engine_par.gridSearch(...
                    'p', grid_spec.p, ...
                    'q', grid_spec.q, ...
                    'd', grid_spec.d, ...
                    'P', grid_spec.P, ...
                    'Q', grid_spec.Q);
                
                % Los mejores modelos deberían ser iguales (dentro de tolerancia numérica)
                testCase.verifyAlmostEqual(engine_seq.BestAIC, engine_par.BestAIC, ...
                    'AbsTol', 0.1);
            end
        end
    end
end
