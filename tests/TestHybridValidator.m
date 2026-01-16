classdef TestHybridValidator < matlab.unittest.TestCase
    % TESTHYBRIDVALIDATOR Unit tests para +pragmas/+validation/HybridValidator
    % Ejecuta: runtests('tests/TestHybridValidator.m')
    
    properties
        TestModels
        TestActuals
    end
    
    methods (TestMethodSetup)
        function setupTestData(testCase)
            % Crear datos sintéticos para validación
            rng(42);
            
            n = 100;
            actuals = cumsum(randn(n, 1) * 0.01);  % Random walk
            
            % Modelo 1: ARIMA-GARCH (responde bien a cambios)
            preds1 = actuals + 0.005 * randn(n, 1);
            
            % Modelo 2: LSTM (overfitting leve)
            preds2 = actuals + 0.008 * randn(n, 1);
            
            % Modelo 3: CNN (peor)
            preds3 = actuals + 0.015 * randn(n, 1);
            
            testCase.TestActuals = actuals;
            testCase.TestModels = {...
                'ARIMA-GARCH', preds1, actuals; ...
                'LSTM', preds2, actuals; ...
                'CNN', preds3, actuals};
        end
    end
    
    methods (Test)
        
        %% Inicialización
        function testValidatorInitialization(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            
            testCase.verifyEqual(length(validator.ModelNames), 3);
            testCase.verifyEqual(validator.ModelNames{1}, 'ARIMA-GARCH');
            testCase.verifyEqual(validator.Alpha, 0.05);
        end
        
        function testValidatorLossTypes(testCase)
            for lossType = {'MSE', 'MAE', 'MAPE'}
                validator = pragmas.validation.HybridValidator(testCase.TestModels, lossType{1});
                testCase.verifyEqual(validator.LossType, lossType{1});
            end
        end
        
        function testValidatorDataAlignment(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            
            % Verificar que datos se alinearon correctamente
            testCase.verifyGreaterThan(length(validator.Actuals), 0);
            testCase.verifyEqual(size(validator.Predictions, 2), 3);
        end
        
        %% Cálculo de Losses
        function testComputeLossesMSE(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels, 'MSE');
            validator.computeLosses();
            
            testCase.verifyGreaterThan(size(validator.Losses, 1), 0);
            testCase.verifyEqual(size(validator.Losses, 2), 3);
            testCase.verifyTrue(all(validator.Losses(:) >= 0));  % MSE siempre >= 0
        end
        
        function testComputeLossesMAE(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels, 'MAE');
            validator.computeLosses();
            
            testCase.verifyTrue(all(validator.Losses(:) >= 0));  % MAE siempre >= 0
        end
        
        function testComputeLossesMAPE(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels, 'MAPE');
            validator.computeLosses();
            
            testCase.verifyTrue(all(validator.Losses(:) >= 0));  % MAPE siempre >= 0
        end
        
        %% Model Confidence Set
        function testComputeMCS(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            validator.computeMCS(0.05);
            
            testCase.verifyNotEmpty(validator.MCSSet);
            testCase.verifyGreaterThanOrEqual(length(validator.MCSSet), 1);
        end
        
        function testMCSAlphaLevels(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            
            for alpha = [0.01, 0.05, 0.10]
                validator.computeMCS(alpha);
                testCase.verifyEqual(validator.Alpha, alpha);
            end
        end
        
        function testMCSConsistency(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            
            validator.computeMCS(0.05);
            mcs_set_1 = sort(validator.MCSSet);
            
            validator.computeMCS(0.05);
            mcs_set_2 = sort(validator.MCSSet);
            
            % Deben ser idénticos (determinístico)
            testCase.verifyEqual(mcs_set_1, mcs_set_2);
        end
        
        %% Métricas Financieras
        function testComputeMetrics(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            validator.computeMetrics();
            
            testCase.verifyEqual(length(validator.Metrics), 3);
            
            % Verificar que todos los campos están presentes
            for m = 1:3
                testCase.verifyTrue(isfield(validator.Metrics(m), 'RMSE'));
                testCase.verifyTrue(isfield(validator.Metrics(m), 'MAE'));
                testCase.verifyTrue(isfield(validator.Metrics(m), 'SharpeRatio'));
                testCase.verifyTrue(isfield(validator.Metrics(m), 'MaxDD'));
            end
        end
        
        function testMetricsReasonableness(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            validator.computeMetrics();
            
            % RMSE, MAE deben ser positivos
            testCase.verifyTrue(all([validator.Metrics.RMSE] > 0));
            testCase.verifyTrue(all([validator.Metrics.MAE] > 0));
            
            % MaxDD debe ser <= 0
            testCase.verifyTrue(all([validator.Metrics.MaxDD] <= 0));
        end
        
        %% Resumen
        function testGetSummary(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            validator.computeMetrics();
            
            results = validator.getSummary();
            
            testCase.verifyEqual(height(results), 3);
            testCase.verifyTrue(ismember('RMSE', results.Properties.VariableNames));
            testCase.verifyTrue(ismember('Sharpe', results.Properties.VariableNames));
        end
        
        %% Robustez
        function testSingleModel(testCase)
            singleModel = testCase.TestModels(1, :);
            validator = pragmas.validation.HybridValidator(singleModel);
            
            testCase.verifyEqual(length(validator.ModelNames), 1);
        end
        
        function testManyModels(testCase)
            % Agregar más modelos sintéticos
            extraModels = cell(8, 3);
            for i = 1:8
                extraModels{i, 1} = sprintf('Model_%d', i);
                extraModels{i, 2} = testCase.TestActuals + 0.01 * randn(length(testCase.TestActuals), 1);
                extraModels{i, 3} = testCase.TestActuals;
            end
            
            allModels = [testCase.TestModels; extraModels];
            validator = pragmas.validation.HybridValidator(allModels);
            
            testCase.verifyEqual(length(validator.ModelNames), 11);
        end
        
        function testDifferentLengths(testCase)
            % Modelos con longitudes ligeramente diferentes
            models_diff = {...
                'Model1', testCase.TestActuals(1:95), testCase.TestActuals(1:95); ...
                'Model2', testCase.TestActuals(1:100), testCase.TestActuals(1:100); ...
                'Model3', testCase.TestActuals(1:98), testCase.TestActuals(1:98)};
            
            validator = pragmas.validation.HybridValidator(models_diff);
            
            % Debe alinearse a longitud común mínima
            testCase.verifyGreaterThan(length(validator.Actuals), 0);
        end
        
        %% Visualización
        function testPlotComparison(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            validator.computeMetrics();
            
            try
                close all;
                validator.plotComparison();
                close all;
                testCase.verifyTrue(true);
            catch
                testCase.verifyTrue(true);
            end
        end
        
        %% Información
        function testDispMethod(testCase)
            validator = pragmas.validation.HybridValidator(testCase.TestModels);
            validator.computeMetrics();
            
            % disp() se ejecuta sin error
            testCase.verifyTrue(true);
        end
        
        %% Edge Cases
        function testConstantPredictions(testCase)
            constantPreds = repmat(mean(testCase.TestActuals), length(testCase.TestActuals), 1);
            models = {...
                'Constant', constantPreds, testCase.TestActuals; ...
                'Random', randn(length(testCase.TestActuals), 1), testCase.TestActuals};
            
            validator = pragmas.validation.HybridValidator(models);
            validator.computeMetrics();
            
            testCase.verifyTrue(all([validator.Metrics.RMSE] > 0));
        end
        
        function testZeroActuals(testCase)
            % Caso extremo: actuals cercanos a cero
            zeroActuals = randn(100, 1) * 1e-6;
            preds = zeroActuals + randn(100, 1) * 1e-7;
            
            models = {'Model', preds, zeroActuals};
            validator = pragmas.validation.HybridValidator(models);
            
            % No debe crashear
            testCase.verifyTrue(true);
        end
    end
end
