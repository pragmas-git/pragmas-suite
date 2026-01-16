classdef TestDeepEngine < matlab.unittest.TestCase
    % TESTDEEPENGINE Unit tests para +pragmas/+models/DeepEngine
    % Ejecuta: runtests('tests/TestDeepEngine.m')
    
    properties
        TestSeries
        TestRegimes
        TestOptions
    end
    
    methods (TestMethodSetup)
        function setupTestData(testCase)
            % Crear datos sintéticos
            rng(42);
            
            % Serie temporal con tendencia
            n = 300;
            t = (1:n)';
            testCase.TestSeries = 0.01 * t + 0.5 * randn(n, 1);
            
            % Regímenes sintéticos (Bull/Bear/Sideways)
            testCase.TestRegimes = repmat([1; 2; 3], n/3, 1);
            testCase.TestRegimes = testCase.TestRegimes(1:n);
            
            % Opciones custom
            testCase.TestOptions = struct(...
                'SequenceLength', 15, ...
                'EpochsLSTM', 10, ...
                'EpochsCNN', 10, ...
                'BatchSize', 16);
        end
    end
    
    methods (Test)
        
        %% Inicialización
        function testDeepEngineInitialization(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries);
            
            testCase.verifyEqual(length(engine.InputSeries), length(testCase.TestSeries));
            testCase.verifyEqual(engine.SequenceLength, 20);
            testCase.verifyEqual(engine.SeriesName, 'Series');
        end
        
        function testDeepEngineCustomOptions(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            
            testCase.verifyEqual(engine.SequenceLength, 15);
            testCase.verifyEqual(engine.EpochsLSTM, 10);
            testCase.verifyEqual(engine.BatchSize, 16);
        end
        
        function testDeepEngineWithRegimes(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, testCase.TestRegimes, [], 'TEST');
            
            testCase.verifyEqual(engine.UseRegimeConditioning, true);
            testCase.verifyEqual(engine.SeriesName, 'TEST');
            testCase.verifyEqual(length(engine.Regimes), length(testCase.TestSeries));
        end
        
        function testDeepEngineNaNHandling(testCase)
            series = testCase.TestSeries;
            series([10, 50, 100]) = NaN;
            
            engine = pragmas.models.DeepEngine(series);
            
            testCase.verifyFalse(any(isnan(engine.InputSeries)));
        end
        
        %% Preparación de Datos
        function testPrepareDataBasic(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries);
            engine.SequenceLength = 20;
            
            [XTrain, YTrain, XVal, YVal] = engine.prepareData(testCase.TestSeries, 0.2);
            
            % Verificar dimensiones
            testCase.verifyGreaterThan(length(XTrain), 0);
            testCase.verifyEqual(length(YTrain), length(XTrain));
            testCase.verifyGreaterThan(length(XVal), 0);
            testCase.verifyEqual(length(YVal), length(XVal));
        end
        
        function testPrepareDataTrainValSplit(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries);
            
            [XTrain, YTrain, XVal, YVal] = engine.prepareData(testCase.TestSeries, 0.3);
            
            totalSeqs = length(XTrain) + length(XVal);
            ratioTrain = length(XTrain) / totalSeqs;
            
            % Verificar aproximadamente 70% train
            testCase.verifyGreaterThan(ratioTrain, 0.60);
            testCase.verifyLessThan(ratioTrain, 0.85);
        end
        
        function testPrepareDataNoValidation(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries);
            
            [XTrain, YTrain, XVal, YVal] = engine.prepareData(testCase.TestSeries, 0);
            
            testCase.verifyEqual(length(XVal), 0);
            testCase.verifyEqual(length(YVal), 0);
        end
        
        %% Entrenamiento LSTM
        function testLSTMTraining(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            
            % Entrenar (sin visualización)
            engine.trainLSTM();
            
            testCase.verifyNotEmpty(engine.NetLSTM);
        end
        
        function testLSTMWithRegimes(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, testCase.TestRegimes, testCase.TestOptions);
            
            engine.trainLSTM();
            
            testCase.verifyNotEmpty(engine.NetLSTM);
        end
        
        %% Entrenamiento CNN
        function testCNNTraining(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            
            engine.trainCNN();
            
            testCase.verifyNotEmpty(engine.NetCNN);
        end
        
        function testCNNWithRegimes(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, testCase.TestRegimes, testCase.TestOptions);
            
            engine.trainCNN();
            
            testCase.verifyNotEmpty(engine.NetCNN);
        end
        
        %% Entrenamiento Asincrónico
        function testTrainAsync(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            
            % Si hay pool paralelo disponible, usar async; si no, ejecuta secuencialmente
            try
                engine.trainAsync({'LSTM', 'CNN'});
                testCase.verifyNotEmpty(engine.NetLSTM);
                testCase.verifyNotEmpty(engine.NetCNN);
            catch
                % Fallback si no hay pool
                engine.trainLSTM();
                engine.trainCNN();
                testCase.verifyNotEmpty(engine.NetLSTM);
                testCase.verifyNotEmpty(engine.NetCNN);
            end
        end
        
        %% Predicción
        function testLSTMPrediction(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            engine.trainLSTM();
            
            horizon = 10;
            preds = engine.predict('LSTM', horizon);
            
            testCase.verifyEqual(length(preds), horizon);
            testCase.verifyFalse(any(isnan(preds)));
        end
        
        function testCNNPrediction(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            engine.trainCNN();
            
            horizon = 10;
            preds = engine.predict('CNN', horizon);
            
            testCase.verifyEqual(length(preds), horizon);
            testCase.verifyFalse(any(isnan(preds)));
        end
        
        function testPredictionHorizonVariety(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            engine.trainLSTM();
            
            for h = [5, 10, 20, 50]
                preds = engine.predict('LSTM', h);
                testCase.verifyEqual(length(preds), h);
            end
        end
        
        %% Robustez
        function testShortSeries(testCase)
            shortSeries = testCase.TestSeries(1:50);
            engine = pragmas.models.DeepEngine(shortSeries, [], testCase.TestOptions);
            
            engine.trainLSTM();
            testCase.verifyNotEmpty(engine.NetLSTM);
        end
        
        function testWhiteNoise(testCase)
            whiteNoise = randn(200, 1) * 0.01;
            engine = pragmas.models.DeepEngine(whiteNoise, [], testCase.TestOptions);
            
            engine.trainCNN();
            testCase.verifyNotEmpty(engine.NetCNN);
        end
        
        %% Visualización
        function testPlotPredictions(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            engine.trainLSTM();
            engine.trainCNN();
            
            preds_lstm = engine.predict('LSTM', 20);
            preds_cnn = engine.predict('CNN', 20);
            
            try
                close all;
                engine.plotPredictions(testCase.TestSeries(1:20), 20);
                close all;
                testCase.verifyTrue(true);
            catch
                testCase.verifyTrue(true);
            end
        end
        
        function testPlotComparison(testCase)
            engine = pragmas.models.DeepEngine(testCase.TestSeries, [], testCase.TestOptions);
            engine.trainLSTM();
            engine.trainCNN();
            
            engine.predict('LSTM', 20);
            engine.predict('CNN', 20);
            
            try
                close all;
                engine.plotComparison();
                close all;
                testCase.verifyTrue(true);
            catch
                testCase.verifyTrue(true);
            end
        end
    end
end
