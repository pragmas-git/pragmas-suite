classdef DeepEngine < handle
    % DEEPENGINE Motor de entrenamiento de modelos DL (LSTM/CNN) para series temporales.
    %
    % Entrena redes LSTM y CNN-1D en residuos ARIMA-GARCH o series procesadas,
    % opcionalmente condicionadas por regímenes HMM. Soporta training asincrónico
    % con parfeval para múltiples modelos/regímenes en paralelo.
    %
    % Uso típico:
    %   dlEngine = pragmas.models.DeepEngine(residuals, regimes, options);
    %   dlEngine.trainAsync({'LSTM', 'CNN'});
    %   preds = dlEngine.predict('LSTM', h);
    %   dlEngine.plotTrainingHistory();
    %
    % Nota: Requiere Deep Learning Toolbox. Sin él, implementa fallback con regresión.
    
    properties
        % Datos
        InputSeries             % Vector de residuos o series procesadas
        Regimes                 % Vector de etiquetas de régimen (1=Bull, 2=Bear, 3=Sideways)
        SeriesName              % Identificador de serie
        
        % Redes entrenadas
        NetLSTM                 % Red LSTM entrenada
        NetCNN                  % Red CNN-1D entrenada
        TrainingHistoryLSTM     % Historial de training LSTM
        TrainingHistoryCNN      % Historial de training CNN
        
        % Hiperparámetros
        SequenceLength          % Longitud de lag/ventana (default: 20)
        NumLSTMLayers           % Número de capas LSTM (default: 2)
        LSTMHiddenSize          % Unidades por capa LSTM (default: 50)
        CNNFilters              % Filtros en CNN (default: 64)
        CNNKernel               % Kernel size en CNN (default: 5)
        EpochsLSTM              % Épocas entrenamiento LSTM (default: 50)
        EpochsCNN               % Épocas entrenamiento CNN (default: 50)
        BatchSize               % Batch size (default: 32)
        LearningRate            % Learning rate (default: 0.001)
        
        % Predicciones
        PredictionsLSTM         % Pronósticos del modelo LSTM
        PredictionsCNN          % Pronósticos del modelo CNN
        
        % Flags
        UseToolbox              % Flag si Deep Learning Toolbox disponible
        UseRegimeConditioning   % Flag para entrenar por régimen
    end
    
    methods
        %% Constructor
        function obj = DeepEngine(inputSeries, regimes, options, seriesName)
            % DEEPENGINE Inicializa motor DL.
            %
            % Input:
            %   inputSeries: vector de residuos/series procesadas
            %   regimes: vector de etiquetas de régimen (opcional)
            %   options: struct con hiperparámetros (opcional)
            %   seriesName: identificador (default: 'Series')
            
            if istimetable(inputSeries)
                obj.InputSeries = inputSeries{:, :};
            else
                obj.InputSeries = inputSeries(:);
            end
            
            obj.InputSeries = obj.InputSeries(~isnan(obj.InputSeries));
            
            if nargin < 2 || isempty(regimes)
                obj.Regimes = [];
                obj.UseRegimeConditioning = false;
            else
                obj.Regimes = regimes(:);
                obj.UseRegimeConditioning = ~isempty(regimes);
            end
            
            if nargin < 4 || isempty(seriesName)
                obj.SeriesName = 'Series';
            else
                obj.SeriesName = seriesName;
            end
            
            % Hiperparámetros por defecto
            obj.SequenceLength = 20;
            obj.NumLSTMLayers = 2;
            obj.LSTMHiddenSize = 50;
            obj.CNNFilters = 64;
            obj.CNNKernel = 5;
            obj.EpochsLSTM = 50;
            obj.EpochsCNN = 50;
            obj.BatchSize = 32;
            obj.LearningRate = 0.001;
            
            % Sobrescribir con opciones custom si se proporcionan
            if nargin >= 3 && ~isempty(options)
                if isfield(options, 'SequenceLength')
                    obj.SequenceLength = options.SequenceLength;
                end
                if isfield(options, 'EpochsLSTM')
                    obj.EpochsLSTM = options.EpochsLSTM;
                end
                if isfield(options, 'EpochsCNN')
                    obj.EpochsCNN = options.EpochsCNN;
                end
                if isfield(options, 'BatchSize')
                    obj.BatchSize = options.BatchSize;
                end
                if isfield(options, 'LearningRate')
                    obj.LearningRate = options.LearningRate;
                end
            end
            
            obj.UseToolbox = license('test', 'Deep_Learning_Toolbox');
            
            if ~obj.UseToolbox
                warning('Deep Learning Toolbox no disponible; usando fallback (regresión simple).');
            end
        end
        
        %% Preparación de Datos
        function [XTrain, YTrain, XVal, YVal] = prepareData(obj, data, valSplit)
            % PREPAREDATA Crea secuencias lagged para DL.
            %
            % Output:
            %   XTrain: cell array de secuencias de training
            %   YTrain: targets de training
            %   XVal, YVal: validación (si valSplit > 0)
            
            if nargin < 3
                valSplit = 0.2;  % 80% train, 20% val
            end
            
            data = data(~isnan(data));  % Asegura sin NaNs
            window = obj.SequenceLength;
            numObs = length(data) - window;
            
            if numObs <= 0
                error('Insuficientes observaciones para crear secuencias con window=%d', window);
            end
            
            % Crear secuencias
            X = cell(numObs, 1);
            Y = zeros(numObs, 1);
            
            for i = 1:numObs
                X{i} = data(i:i+window-1)';  % Secuencia como fila
                Y(i) = data(i+window);        % Target: siguiente obs
            end
            
            % Split train/val
            numTrain = ceil(numObs * (1 - valSplit));
            
            XTrain = X(1:numTrain);
            YTrain = Y(1:numTrain);
            
            if valSplit > 0
                XVal = X(numTrain+1:end);
                YVal = Y(numTrain+1:end);
            else
                XVal = cell(0, 1);
                YVal = [];
            end
        end
        
        %% Entrenamiento LSTM
        function trainLSTM(obj)
            % TRAINLSTM Entrena modelo LSTM.
            
            fprintf('[%s] Entrenando LSTM...\n', obj.SeriesName);
            
            if obj.UseRegimeConditioning && ~isempty(obj.Regimes)
                % Entrenar LSTM condicional por régimen (ejemplo: Bull)
                bullIdx = obj.Regimes == 1;
                data = obj.InputSeries(bullIdx);
                fprintf('  Usando datos Bull regime (%d obs)\n', sum(bullIdx));
            else
                data = obj.InputSeries;
            end
            
            [XTrain, YTrain, XVal, YVal] = obj.prepareData(data);
            
            if obj.UseToolbox
                obj.trainLSTMWithToolbox(XTrain, YTrain, XVal, YVal);
            else
                obj.trainLSTMFallback(XTrain, YTrain);
            end
        end
        
        function trainLSTMWithToolbox(obj, XTrain, YTrain, XVal, YVal)
            % TRAINLSTMWITHTOOLBOX Usa Deep Learning Toolbox.
            
            try
                % Arquitectura LSTM
                layers = [
                    sequenceInputLayer(1, 'Name', 'input')];
                
                % Agregar capas LSTM
                for i = 1:obj.NumLSTMLayers
                    if i < obj.NumLSTMLayers
                        layers = [layers
                            lstmLayer(obj.LSTMHiddenSize, 'OutputMode', 'sequence', ...
                            'Name', sprintf('lstm_%d', i))
                            dropoutLayer(0.2)];
                    else
                        layers = [layers
                            lstmLayer(obj.LSTMHiddenSize, 'OutputMode', 'last', ...
                            'Name', sprintf('lstm_%d', i))];
                    end
                end
                
                % Capas densas finales
                layers = [layers
                    fullyConnectedLayer(20, 'Name', 'fc1')
                    reluLayer('Name', 'relu')
                    dropoutLayer(0.2)
                    fullyConnectedLayer(1, 'Name', 'output')
                    regressionLayer('Name', 'loss')];
                
                % Opciones de training
                options = trainingOptions('adam', ...
                    'MaxEpochs', obj.EpochsLSTM, ...
                    'MiniBatchSize', obj.BatchSize, ...
                    'InitialLearnRate', obj.LearningRate, ...
                    'LearnRateSchedule', 'piecewise', ...
                    'LearnRateDropFactor', 0.5, ...
                    'LearnRateDropPeriod', 20, ...
                    'Shuffle', 'every-epoch', ...
                    'Verbose', 0, ...
                    'Plots', 'none');
                
                % Training
                obj.NetLSTM = trainNetwork(XTrain, YTrain, layers, options);
                
                fprintf('  ✓ LSTM entrenada exitosamente\n');
                
            catch ME
                warning('Error en trainLSTM con toolbox: %s\nUsando fallback.', ME.message);
                obj.trainLSTMFallback(XTrain, YTrain);
            end
        end
        
        function trainLSTMFallback(obj, XTrain, YTrain)
            % TRAINLSTMFALLBACK Fallback: regresión simple sin toolbox.
            
            % Extraer matriz de features (último valor de cada secuencia)
            X = cellfun(@(x) x(end), XTrain);  % Últimos valores
            
            % Regresión OLS simple
            X = [ones(length(X), 1), X(:)];
            beta = (X' * X) \ (X' * YTrain);
            
            % Guardar modelo simple
            obj.NetLSTM = struct('beta', beta, 'type', 'linear');
            
            fprintf('  ✓ LSTM fallback (regresión lineal) entrenada\n');
        end
        
        %% Entrenamiento CNN
        function trainCNN(obj)
            % TRAINCNN Entrena modelo CNN-1D.
            
            fprintf('[%s] Entrenando CNN...\n', obj.SeriesName);
            
            if obj.UseRegimeConditioning && ~isempty(obj.Regimes)
                % Entrenar CNN condicional por régimen (ejemplo: Bear)
                bearIdx = obj.Regimes == 2;
                data = obj.InputSeries(bearIdx);
                fprintf('  Usando datos Bear regime (%d obs)\n', sum(bearIdx));
            else
                data = obj.InputSeries;
            end
            
            [XTrain, YTrain, XVal, YVal] = obj.prepareData(data);
            
            if obj.UseToolbox
                obj.trainCNNWithToolbox(XTrain, YTrain, XVal, YVal);
            else
                obj.trainCNNFallback(XTrain, YTrain);
            end
        end
        
        function trainCNNWithToolbox(obj, XTrain, YTrain, XVal, YVal)
            % TRAINCONWITHTOOLBOX Usa Deep Learning Toolbox para CNN-1D.
            
            try
                % Arquitectura CNN-1D
                layers = [
                    sequenceInputLayer(1, 'Name', 'input')
                    convolution1dLayer(obj.CNNKernel, obj.CNNFilters, ...
                    'Padding', 'same', 'Name', 'conv1')
                    batchNormalizationLayer('Name', 'bn1')
                    reluLayer('Name', 'relu1')
                    maxPooling1dLayer(2, 'Stride', 2, 'Name', 'pool1')
                    convolution1dLayer(3, obj.CNNFilters*2, ...
                    'Padding', 'same', 'Name', 'conv2')
                    batchNormalizationLayer('Name', 'bn2')
                    reluLayer('Name', 'relu2')
                    globalAveragePooling1dLayer('Name', 'gap')
                    fullyConnectedLayer(32, 'Name', 'fc1')
                    reluLayer('Name', 'relu3')
                    dropoutLayer(0.3)
                    fullyConnectedLayer(1, 'Name', 'output')
                    regressionLayer('Name', 'loss')];
                
                % Opciones de training
                options = trainingOptions('adam', ...
                    'MaxEpochs', obj.EpochsCNN, ...
                    'MiniBatchSize', obj.BatchSize, ...
                    'InitialLearnRate', obj.LearningRate, ...
                    'LearnRateSchedule', 'piecewise', ...
                    'Shuffle', 'every-epoch', ...
                    'Verbose', 0, ...
                    'Plots', 'none');
                
                % Training
                obj.NetCNN = trainNetwork(XTrain, YTrain, layers, options);
                
                fprintf('  ✓ CNN entrenada exitosamente\n');
                
            catch ME
                warning('Error en trainCNN con toolbox: %s\nUsando fallback.', ME.message);
                obj.trainCNNFallback(XTrain, YTrain);
            end
        end
        
        function trainCNNFallback(obj, XTrain, YTrain)
            % TRAINCNNFALLBACK Fallback: promedio móvil ponderado.
            
            % Usar media de la ventana con pesos (simula convolución simple)
            X = cellfun(@(x) mean(x), XTrain);
            
            X = [ones(length(X), 1), X(:)];
            beta = (X' * X) \ (X' * YTrain);
            
            obj.NetCNN = struct('beta', beta, 'type', 'linear');
            
            fprintf('  ✓ CNN fallback (media móvil) entrenada\n');
        end
        
        %% Entrenamiento Asincrónico
        function trainAsync(obj, modelTypes)
            % TRAINASYNC Entrena múltiples modelos en paralelo.
            %
            % Input:
            %   modelTypes: cell array de strings {'LSTM', 'CNN'} o subset
            
            global PRAGMAS_PARPOOL_SIZE;
            
            p = gcp('nocreate');
            if isempty(p)
                if ~isempty(PRAGMAS_PARPOOL_SIZE)
                    parpool(PRAGMAS_PARPOOL_SIZE);
                else
                    parpool(4);
                end
            end
            
            fprintf('[%s] Training asincrónico (%s)...\n', obj.SeriesName, strjoin(modelTypes, ', '));
            
            futures = cell(size(modelTypes));
            for i = 1:length(modelTypes)
                modelType = modelTypes{i};
                if strcmp(modelType, 'LSTM')
                    futures{i} = parfeval(@obj.trainLSTM, 0);
                elseif strcmp(modelType, 'CNN')
                    futures{i} = parfeval(@obj.trainCNN, 0);
                end
            end
            
            % Esperar convergencia
            wait(futures);
            fprintf('[%s] Training completado\n', obj.SeriesName);
        end
        
        %% Predicción
        function preds = predict(obj, modelType, horizon)
            % PREDICT Genera pronósticos h pasos adelante.
            %
            % Input:
            %   modelType: 'LSTM' o 'CNN'
            %   horizon: pasos adelante
            %
            % Output:
            %   preds: vector de pronósticos (horizon x 1)
            
            if strcmp(modelType, 'LSTM')
                if isempty(obj.NetLSTM)
                    error('LSTM no entrenada; ejecuta trainLSTM primero.');
                end
                net = obj.NetLSTM;
            elseif strcmp(modelType, 'CNN')
                if isempty(obj.NetCNN)
                    error('CNN no entrenada; ejecuta trainCNN primero.');
                end
                net = obj.NetCNN;
            else
                error('Modelo no soportado.');
            end
            
            preds = zeros(horizon, 1);
            
            % Inicializar con las últimas observaciones
            lastSeq = obj.InputSeries(end-obj.SequenceLength+1:end);
            
            for h = 1:horizon
                if isstruct(net) && strcmp(net.type, 'linear')
                    % Fallback lineal
                    X = [1, lastSeq(end)];
                    pred = X * net.beta;
                else
                    % Deep Learning Toolbox
                    lastSeq_input = lastSeq';
                    pred = predict(net, lastSeq_input);
                end
                
                preds(h) = pred;
                
                % Actualizar ventana (desplazar)
                lastSeq = [lastSeq(2:end); pred];
            end
            
            % Guardar predicciones
            if strcmp(modelType, 'LSTM')
                obj.PredictionsLSTM = preds;
            else
                obj.PredictionsCNN = preds;
            end
        end
        
        %% Visualización
        function plotPredictions(obj, actual, horizon)
            % PLOTPREDICTIONS Visualiza predicciones vs actuals.
            %
            % Input:
            %   actual: series actual para comparar
            %   horizon: longitud de pronóstico (para alineación)
            
            if nargin < 3
                horizon = length(obj.PredictionsLSTM);
            end
            
            figure('Name', sprintf('DL Predictions: %s', obj.SeriesName), 'NumberTitle', 'off');
            
            % Subplot 1: LSTM
            subplot(1, 2, 1);
            hold on;
            timeAxis = (1:horizon)';
            plot(timeAxis, obj.PredictionsLSTM, 'b-', 'LineWidth', 2, 'DisplayName', 'LSTM Forecast');
            if nargin >= 2 && ~isempty(actual)
                plot(timeAxis, actual(1:min(length(actual), horizon)), 'k--', 'LineWidth', 1.5, 'DisplayName', 'Actual');
            end
            title('LSTM Pronóstico', 'FontWeight', 'bold');
            xlabel('Horizonte (pasos)');
            ylabel('Predicción');
            legend('Location', 'best');
            grid on;
            hold off;
            
            % Subplot 2: CNN
            subplot(1, 2, 2);
            hold on;
            plot(timeAxis, obj.PredictionsCNN, 'r-', 'LineWidth', 2, 'DisplayName', 'CNN Forecast');
            if nargin >= 2 && ~isempty(actual)
                plot(timeAxis, actual(1:min(length(actual), horizon)), 'k--', 'LineWidth', 1.5, 'DisplayName', 'Actual');
            end
            title('CNN Pronóstico', 'FontWeight', 'bold');
            xlabel('Horizonte (pasos)');
            ylabel('Predicción');
            legend('Location', 'best');
            grid on;
            hold off;
        end
        
        function plotComparison(obj)
            % PLOTCOMPARISON Compara LSTM vs CNN.
            
            figure('Name', sprintf('Model Comparison: %s', obj.SeriesName), 'NumberTitle', 'off');
            
            if isempty(obj.PredictionsLSTM) || isempty(obj.PredictionsCNN)
                warning('No predictions available; ejecuta predict primero.');
                return;
            end
            
            horizon = min(length(obj.PredictionsLSTM), length(obj.PredictionsCNN));
            timeAxis = (1:horizon)';
            
            hold on;
            plot(timeAxis, obj.PredictionsLSTM(1:horizon), 'b-', 'LineWidth', 2.5, 'DisplayName', 'LSTM');
            plot(timeAxis, obj.PredictionsCNN(1:horizon), 'r-', 'LineWidth', 2.5, 'DisplayName', 'CNN');
            title(sprintf('LSTM vs CNN: %s', obj.SeriesName), 'FontWeight', 'bold');
            xlabel('Horizonte');
            ylabel('Predicción');
            legend('Location', 'best');
            grid on;
            hold off;
        end
        
        %% Información
        function disp(obj)
            % DISP Muestra resumen del motor DL.
            
            fprintf('\n========== DeepEngine Summary ==========\n');
            fprintf('Serie: %s (%d observaciones)\n', obj.SeriesName, length(obj.InputSeries));
            fprintf('Configuración:\n');
            fprintf('  - Sequence length: %d\n', obj.SequenceLength);
            fprintf('  - LSTM layers: %d × %d unidades\n', obj.NumLSTMLayers, obj.LSTMHiddenSize);
            fprintf('  - CNN: %d filtros, kernel=%d\n', obj.CNNFilters, obj.CNNKernel);
            fprintf('  - Epochs: LSTM=%d, CNN=%d\n', obj.EpochsLSTM, obj.EpochsCNN);
            fprintf('  - Batch size: %d\n', obj.BatchSize);
            fprintf('  - Learning rate: %.4f\n', obj.LearningRate);
            
            if obj.UseRegimeConditioning && ~isempty(obj.Regimes)
                fprintf('  - Regime conditioning: YES\n');
            else
                fprintf('  - Regime conditioning: NO\n');
            end
            
            fprintf('\nModelos entrenados:\n');
            if ~isempty(obj.NetLSTM)
                fprintf('  ✓ LSTM\n');
            else
                fprintf('  ✗ LSTM (no entrenada)\n');
            end
            if ~isempty(obj.NetCNN)
                fprintf('  ✓ CNN\n');
            else
                fprintf('  ✗ CNN (no entrenada)\n');
            end
            fprintf('========================================\n\n');
        end
    end
end
