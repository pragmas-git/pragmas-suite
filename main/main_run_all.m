%MAIN_RUN_ALL End-to-end run (scaffold).
% Orchestrates: data -> features -> (model stubs) -> (signals) -> (portfolio) -> (backtest)

clear; clc;

% Add project paths
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(projectRoot));

cfg = config();
rng(cfg.seed);

% --- Phase 1: Data ---
pricesTT = load_data(cfg);
retsTT = compute_returns(pricesTT, cfg);
retsTT = clean_returns(retsTT, cfg);

% --- Phase 2: Features ---
feat = build_features(retsTT, cfg);

% Placeholder: pick a single-asset pipeline first for TFG clarity
asset = cfg.assetsList{1};

% --- Phase 3-9: Hybrid model -> signal -> backtest (univariate scaffold) ---
ret1 = retsTT(:,asset);

modelOut = garch_kde_model(ret1, cfg);
sigTT = signal_prob_up(modelOut.probUp, cfg); % 0/1 weights for 1-asset case

bt = run_backtest(ret1, sigTT, cfg);

fprintf('Sharpe: %.3f | MaxDD: %.3f | Turnover: %.3f\n', bt.metrics.sharpe, bt.metrics.maxDrawdown, bt.metrics.turnover);

% --- Logging (results/) ---
results = struct();
results.meta = struct('timestamp', datetime('now'), 'entrypoint', 'main_run_all', 'seed', cfg.seed);
results.cfg = cfg;
results.models = struct('parametric', struct(), 'nonparametric', struct(), 'hybrid', struct());
results.models.hybrid.garchKde = modelOut;
results.signals = struct();
results.signals.probUp = sigTT;
results.backtest = bt;

% Basic evaluation from hybrid VaR forecast
results.evaluation = struct();
try
	results.evaluation.varBacktest = var_backtest(ret1.Variables, modelOut.var.Variables, cfg.alpha);
catch
	results.evaluation.varBacktest = struct('error', 'var_backtest failed');
end

try
	outPath = save_results(results, cfg, "run");
	fprintf('Saved results: %s\n', outPath);
catch
	fprintf('Warning: could not save results to results/.\n');
end

fprintf('Scaffold OK. Data rows: %d | Feature rows: %d\n', height(retsTT), height(feat.X));
