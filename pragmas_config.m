% PRAGMAS_CONFIG Configuración global para pragmas-suite.
% Ejecuta este script al inicio de cualquier sesión.

% Paths y toolboxes
addpath(genpath(fileparts(mfilename('fullpath'))));  % Agrega toda la suite al path

% Configuraciones de datos
global PRAGMAS_DATA_SOURCES;
PRAGMAS_DATA_SOURCES.yahoo = 'https://query1.finance.yahoo.com';  % Base URL Yahoo
PRAGMAS_DATA_SOURCES.crypto = 'https://api.coingecko.com/api/v3';  % CoinGecko (gratuita)

% API Keys (si usas Alpha Vantage para más datos; obtén gratis en alphavantage.co)
global PRAGMAS_API_KEYS;
PRAGMAS_API_KEYS.alpha_vantage = '';  % Inserta tu key aquí si la usas

% Configuraciones asíncronas
global PRAGMAS_PARPOOL_SIZE;
PRAGMAS_PARPOOL_SIZE = 4;  % Tamaño del pool paralelo (ajusta a tu máquina)

% Opciones de logging
global PRAGMAS_LOG_LEVEL;
PRAGMAS_LOG_LEVEL = 'info';  % 'debug', 'info', 'warn', 'error'

% Configuraciones de Deep Learning (Phase 3)
global PRAGMAS_DEEPENGINE_OPTIONS;
PRAGMAS_DEEPENGINE_OPTIONS.SequenceLength = 20;    % Longitud de ventana temporal
PRAGMAS_DEEPENGINE_OPTIONS.EpochsLSTM = 50;        % Épocas para LSTM
PRAGMAS_DEEPENGINE_OPTIONS.EpochsCNN = 50;         % Épocas para CNN
PRAGMAS_DEEPENGINE_OPTIONS.BatchSize = 16;         % Tamaño de batch
PRAGMAS_DEEPENGINE_OPTIONS.ValidationSplit = 0.2;  % Fracción para validación
PRAGMAS_DEEPENGINE_OPTIONS.LearningRate = 0.001;   % Learning rate (Adam)
PRAGMAS_DEEPENGINE_OPTIONS.Dropout = 0.2;          % Regularización
PRAGMAS_DEEPENGINE_OPTIONS.ModelTypes = {'LSTM', 'CNN'};  % Arquitecturas disponibles

% Configuraciones de Validación (Phase 3)
global PRAGMAS_VALIDATOR_OPTIONS;
PRAGMAS_VALIDATOR_OPTIONS.LossType = 'MSE';         % 'MSE', 'MAE', 'MAPE'
PRAGMAS_VALIDATOR_OPTIONS.MCSDelta = 0.05;          % Nivel de significancia (α)
PRAGMAS_VALIDATOR_OPTIONS.IncludeEnsemble = true;   % Agregar promedio como baseline
PRAGMAS_VALIDATOR_OPTIONS.BootstrapResamples = 1000; % Para análisis de estabilidad (futuro)

disp('pragmas-suite configurada correctamente.');
