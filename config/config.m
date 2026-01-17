function cfg = config()
%CONFIG Project-wide configuration defaults.
%   cfg = CONFIG() returns a struct with all global parameters.
%
%   Design goals:
%   - Reproducible runs (rng seed)
%   - Rolling-window backtesting by construction
%   - Centralized settings for data, models, signals, portfolios
%
%   You can override any field in scripts, e.g.:
%       cfg = config();
%       cfg.assets = {"SPY","QQQ"};

cfg = struct();

% --- Market / experiment definition (TFG-locked defaults) ---
cfg.market = "FX";

% --- Project / data ---
cfg.projectRoot = fileparts(fileparts(mfilename('fullpath')));
cfg.dataRawDir = fullfile(cfg.projectRoot, 'data', 'raw');
cfg.dataProcessedDir = fullfile(cfg.projectRoot, 'data', 'processed');
cfg.dataFeaturesDir = fullfile(cfg.projectRoot, 'data', 'features');
cfg.resultsDir = fullfile(cfg.projectRoot, 'results');

% FX universe (majors vs USD)
% NOTE: based on currently available Dukascopy parquet folders.
cfg.assets = struct();
cfg.assets.fx = ["EURUSD","USDJPY","GBPUSD","AUDUSD"];

% Backward-compatible alias used by existing code (cellstr)
cfg.assetsList = cellstr(cfg.assets.fx);

cfg.frequency = "daily";   % daily NY close
cfg.startDate = datetime(2015,1,1);
cfg.endDate   = datetime(2025,12,31);

% If no raw data exists, the pipeline can generate synthetic prices.
cfg.allowSyntheticData = true;
cfg.synthetic = struct();
cfg.synthetic.numObs = 3000;
cfg.synthetic.startDate = datetime(2010,1,1);

% --- Rolling windows (TFG-locked) ---
% Train: 1000 obs, Test: 1 obs, Step: 1 day
cfg.rolling = struct();
cfg.rolling.train = 1000;
cfg.rolling.test  = 1;
cfg.rolling.step  = 1;

% Backward-compatible aliases used by existing code
cfg.windowTrain = cfg.rolling.train;
cfg.windowTest  = cfg.rolling.test;
cfg.rebalance   = cfg.rolling.step;

% --- Forecast horizon ---
% All models target the distribution of r_{t+h}.
cfg.horizon = 1;

% --- FX conventions ---
cfg.fx = struct();
cfg.fx.baseCurrency = "USD";
% For USD/XXX quotes, invert returns so r>0 means appreciation of non-USD currency.
cfg.fx.invertUSDpairs = ["USDJPY"];

% Daily close definition for FX (NY close)
cfg.fx.timezone = "America/New_York";
cfg.fx.closeHourNY = 17;

% --- Risk / evaluation ---
cfg.alpha = 0.05;       % VaR/CVaR level
cfg.confLevel = 0.95;   % general confidence level

% --- Reproducibility ---
cfg.seed = 42;

% --- Signals ---
cfg.signals = struct();
cfg.signals.probUpThreshold = 0.55;
cfg.signals.zscoreThreshold = 1.0;

% --- Portfolio (Markowitz) ---
cfg.portfolio = struct();
cfg.portfolio.allowShort = false;
cfg.portfolio.maxWeight = 1.0;
cfg.portfolio.riskAversion = 1.0; % lambda
cfg.portfolio.fallbackEqualWeight = true;

% --- GARCH (parametric) ---
cfg.garch = struct();
cfg.garch.p = 1;
cfg.garch.q = 1;

% --- KDE (nonparametric) ---
cfg.kde = struct();
cfg.kde.bandwidth = []; % [] means auto

end
