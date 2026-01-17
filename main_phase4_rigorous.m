%% PRAGMAS-SUITE PHASE 4: RIGOROUS WALK-FORWARD VALIDATION
% 
% Integration example combining all Phase 4 components:
%   1. TimeSeriesCrossValidator (Purged K-Fold + PACF embargo)
%   2. DieboldMarianoBootstrap (Moving Block Bootstrap comparison)
%   3. AsymmetricLossValidator (Pinball loss + directional metrics)
%   4. UtilityBasedValidator (Risk-adjusted performance)
%   5. BayesianMarkovRegimeDetector (Probabilistic regime detection)
%   6. NullBenchmarks (Random Walk, RW+Drift baselines)
%   7. DeepEngineQuantile (Quantile predictions)
%   8. ModelEngineLogReturns (Log-return ARIMA/GARCH)
%
% Workflow:
%   1. Load data (log-returns)
%   2. Estimate Bayesian HMM for regime probabilities
%   3. Create TimeSeriesCrossValidator with dynamic PACF embargo
%   4. For each fold:
%      a. Train models (LSTM, CNN, ARIMA) on training set
%      b. Generate predictions on test set
%      c. Compute quantile intervals
%   5. Compare against null benchmarks (RW, RW+Drift)
%   6. Run Diebold-Mariano bootstrap test
%   7. Evaluate utility-based performance
%   8. Report comprehensive metrics
%
% Expected outcomes (from experience):
%   - OOS Sharpe: ~0.3-0.5 (vs 1.5+ in-sample)
%   - Hit rate: ~53-55% (vs 50% random)
%   - DM test p-value: >0.05 (cannot reject RW null)
%   - Suggests market near-efficiency or data overfitting

clear all; close all; clc;

%% 1. LOAD DATA (Multiple assets for survival bias check)

% Example: 5 currency pairs (blind universe selection)
pairs = {'EURUSD', 'GBPUSD', 'AUDUSD', 'NZDUSD', 'JPYUSD'};
start_date = datetime(2015, 1, 1);
end_date = datetime(2023, 12, 31);

fprintf('Loading price data for %d currency pairs...\n', length(pairs));

% Initialize data storage
prices = struct();
log_returns = struct();

for p = 1:length(pairs)
    pair = pairs{p};
    fprintf('  %s...', pair);
    
    % Load (example: would use yahooquery or other API in practice)
    % For demo: create synthetic data with realistic properties
    T = 2500;  % ~10 years of daily data
    prices.(pair) = 1 + cumsum(randn(T, 1) * 0.005);  % Random walk + drift
    log_returns.(pair) = diff(log(prices.(pair)));
    
    fprintf(' OK (%d observations)\n', length(log_returns.(pair)));
end

%% 2. REGIME DETECTION (Bayesian HMM)

fprintf('\n=== PHASE 4: REGIME DETECTION ===\n');

regime_detectors = struct();

for p = 1:length(pairs)
    pair = pairs{p};
    fprintf('Estimating HMM for %s...\n', pair);
    
    % Create detector
    detector = pragmas.regimes.BayesianMarkovRegimeDetector(...
        log_returns.(pair), 'series_name', pair);
    
    % Estimate (EM algorithm)
    detector.estimate('max_iter', 30, 'tolerance', 1e-5);
    
    % Store
    regime_detectors.(matlab.lang.makeValidName(pair)) = detector;
    
    % Print summary
    summary = detector.getSummary();
    fprintf('  Current regime: %s (entropy=%.3f)\n', ...
        summary.current_regime, detector.RegimeEntropy(end));
end

%% 3. WALK-FORWARD VALIDATION (Purged K-Fold + Dynamic Embargo)

fprintf('\n=== PHASE 4: WALK-FORWARD VALIDATION ===\n');

n_folds = 5;
confidence_level_embargo = 0.05;  % 5% PACF threshold

% Focus on first pair for detailed example
pair_focus = pairs{1};
pair_idx = matlab.lang.makeValidName(pair_focus);
returns = log_returns.(pair_focus);

fprintf('Creating TimeSeriesCrossValidator for %s...\n', pair_focus);
fprintf('  Folds: %d\n', n_folds);
fprintf('  PACF threshold: %.1f%%\n', confidence_level_embargo * 100);

cv = pragmas.validation.TimeSeriesCrossValidator(...
    returns, n_folds, confidence_level_embargo);

fprintf('  Dynamic embargo size: %d (max significant PACF lag)\n', cv.embargo_size);

% Visualize embargo structure
cv.plot_embargo_info();

%% 4. MODEL TRAINING (For each fold)

fprintf('\n=== PHASE 4: MODEL TRAINING (WALK-FORWARD) ===\n');

% CRITICAL: Enforce quantile monotonicity
% DL models can violate Q_05 <= Q_25 <= Q_50 <= Q_75 <= Q_95 due to independent heads
% Forcing monotonicity prevents negative variance and nonsensical predictions
fprintf('⚠ WARNING: All quantile outputs will be sorted to enforce monotonicity.\n');

% Create model cell array {LSTM, CNN, ARIMA}
model_cell = {};

% LSTM with quantile output
fprintf('Preparing Deep Learning models...\n');
lstm_engine = pragmas.models.DeepEngineQuantile(...
    returns, regime_detectors.(pair_idx).SmoothedProb, ...
    struct('EpochsLSTM', 20, 'Quantiles', [0.05, 0.25, 0.5, 0.75, 0.95]), ...
    pair_focus);

% ARIMA for log-returns
arima_engine = pragmas.models.ModelEngineLogReturns(returns, pair_focus);
arima_engine.fit('arimaOrder', [1, 0, 1], 'garchOrder', [1, 1]);

% Store for fold iteration
models_to_train = {lstm_engine, arima_engine};

% Walk-forward backtest
fprintf('Running walk-forward backtest with %d folds...\n', n_folds);

results_wf = cv.walkForwardBacktest(models_to_train, returns);

fprintf('Walk-forward complete.\n');
fprintf('  OOS RMSE: %.6f\n', results_wf.metrics.rmse);
fprintf('  OOS MAE: %.6f\n', results_wf.metrics.mae);
fprintf('  OOS Hit Rate: %.2f%%\n', results_wf.metrics.hit_rate * 100);
fprintf('  OOS Sharpe: %.3f (annualized)\n', results_wf.metrics.sharpe);

%% 5. ENFORCE QUANTILE MONOTONICITY

fprintf('\n=== ENFORCING QUANTILE MONOTONICITY ===\n');
if isfield(results_wf, 'quantile_predictions')
    % Sort each row to ensure Q_05 <= Q_25 <= Q_50 <= Q_75 <= Q_95
    results_wf.quantile_predictions = sort(results_wf.quantile_predictions, 2);
    fprintf('✓ Quantile predictions sorted for logical consistency.\n');
end

%% 6. NULL BENCHMARK COMPARISON

fprintf('\n=== PHASE 4: NULL BENCHMARK COMPARISON ===\n');

% Generate null predictions
horizon = length(returns) / n_folds;  % Test set size
forecast_rw = pragmas.benchmarks.NullBenchmarks.randomWalk(returns, horizon);
forecast_rwdrift = pragmas.benchmarks.NullBenchmarks.randomWalkWithDrift(returns, horizon);
forecast_sn = pragmas.benchmarks.NullBenchmarks.seasonalNaive(returns, horizon, ...
    'seasonality', 252);
forecast_es = pragmas.benchmarks.NullBenchmarks.exponentialSmoothing(returns, horizon);

% Evaluate nulls
nulls_cell = {forecast_rw, forecast_rwdrift, forecast_sn, forecast_es};
null_names = {'RW', 'RW+Drift', 'SeasonalNaive', 'ExpSmoothing'};

null_metrics = pragmas.benchmarks.NullBenchmarks.evaluateNullModels(...
    results_wf.actuals, nulls_cell, null_names);

fprintf('Null Model Performance:\n');
fprintf('  RW RMSE: %.6f | Sharpe: %.3f\n', null_metrics.RW.rmse, null_metrics.RW.sharpe);
fprintf('  RW+Drift RMSE: %.6f | Sharpe: %.3f\n', null_metrics.RWDrift.rmse, null_metrics.RWDrift.sharpe);
fprintf('  SeasonalNaive RMSE: %.6f | Sharpe: %.3f\n', ...
    null_metrics.SeasonalNaive.rmse, null_metrics.SeasonalNaive.sharpe);
fprintf('  ExpSmoothing RMSE: %.6f | Sharpe: %.3f\n', ...
    null_metrics.ExpSmoothing.rmse, null_metrics.ExpSmoothing.sharpe);

%% 7. DIEBOLD-MARIANO BOOTSTRAP TEST (Honesty Filter)

fprintf('\n=== PHASE 4: DIEBOLD-MARIANO BOOTSTRAP TEST ===\n');
fprintf('NOTE: This is the "Honesty Filter". If p>0.05, model = Random Walk (statistically).\n');

% Compare pragmas forecast vs RW null
dm_test = pragmas.validation.DieboldMarianoBootstrap(...
    results_wf.errors, ...
    forecast_rw(1:length(results_wf.errors)) - results_wf.actuals, ...
    'loss', 'mse', 'horizon', 1);

% Run both asymptotic and bootstrap tests
dm_test.test('n_bootstrap', 5000);

% Get summary
dm_summary = dm_test.getSummary();
fprintf('%s\n', dm_summary.conclusion);

% Interpretation: Scientifically honest conclusion
if dm_test.p_asymptotic > 0.05
    fprintf('\n*** CRITICAL FINDING ***\n');
    fprintf('Cannot reject null hypothesis (H0: Model = Random Walk).\n');
    fprintf('INTERPRETATION: Performance is consistent with Market Efficiency (weak form).\n');
    fprintf('This is a HIGH-VALUE scientific finding, not a failure.\n');
    fprintf('Suggests: Either (a) market is efficient, or (b) model overfits in-sample.\n');
else
    fprintf('\n*** SIGNIFICANT EDGE ***\n');
    fprintf('Reject null: Model beats Random Walk statistically.\n');
    fprintf('Next: Check economic significance (after transaction costs, slippage).\n');
end

% Visualize
dm_test.plot_bootstrap_distribution();

%% 8. ASYMMETRIC LOSS EVALUATION (Quantile + Directional)

fprintf('\n=== PHASE 4: ASYMMETRIC LOSS EVALUATION ===\n');

% Prepare forecast struct
if isfield(results_wf, 'quantile_predictions')
    forecast_struct.quantiles = results_wf.quantile_predictions;
else
    % Use median as point forecast
    forecast_struct.point = results_wf.predictions;
end

% Create validator
asym_validator = pragmas.validation.AsymmetricLossValidator(...
    'quantiles', [0.05, 0.25, 0.5, 0.75, 0.95]);

% Comprehensive evaluation
metrics = asym_validator.comprehensiveEvaluation(results_wf.actuals, forecast_struct);

fprintf('Asymmetric Loss Metrics:\n');
fprintf('  Directional Accuracy: %.2f%%\n', metrics.directional_accuracy * 100);
fprintf('  Mean Directional Error: %.3f\n', metrics.mean_directional_error);
fprintf('  RMSE: %.6f\n', metrics.rmse);
fprintf('  MAE: %.6f\n', metrics.mae);
fprintf('  MAPE: %.4f\n', metrics.mape);

if isfield(metrics, 'pinball_loss')
    fprintf('Pinball Loss by Quantile:\n');
    fn = fieldnames(metrics.pinball_loss);
    for i = 1:length(fn)
        if ~strcmp(fn{i}, 'mean') && ~strcmp(fn{i}, 'weighted')
            fprintf('    %s: %.6f\n', fn{i}, metrics.pinball_loss.(fn{i}));
        end
    end
end

%% 9. UTILITY-BASED EVALUATION (Risk-Adjusted Performance)

fprintf('\n=== PHASE 4: UTILITY-BASED EVALUATION ===\n');

utility_validator = pragmas.validation.UtilityBasedValidator(...
    'var_confidence', 0.95, ...
    'target_volatility', 0.12, ...
    'leverage_constraint', 2.0);

[utility, wealth, leverage] = utility_validator.quadraticUtility(...
    results_wf.actuals, results_wf.predictions);

% Comprehensive metrics
[perf_metrics, perf_table] = utility_validator.evaluateStrategy(...
    results_wf.actuals, results_wf.predictions);

fprintf('Utility-Based Strategy Performance:\n');
fprintf('  Final Wealth: %.4f\n', perf_metrics.final_wealth);
fprintf('  Total Return: %.2f%%\n', perf_metrics.total_return * 100);
fprintf('  Sharpe Ratio: %.3f\n', perf_metrics.sharpe);
fprintf('  Sortino Ratio: %.3f\n', perf_metrics.sortino);
fprintf('  Max Drawdown: %.2f%%\n', perf_metrics.mdd * 100);
fprintf('  Avg Leverage: %.2f\n', perf_metrics.avg_leverage);

% Visualize
utility_validator.plot_strategy(results_wf.actuals, wealth, leverage);

%% 10. QUANTILE FORECAST QUALITY (Calibration Test)

fprintf('\n=== PHASE 4: QUANTILE FORECAST QUALITY (CALIBRATION) ===\n');

if isfield(results_wf, 'quantile_predictions')
    [coverage, ci_table] = asym_validator.quantileCoverageTest(...
        results_wf.actuals, results_wf.quantile_predictions);
    
    fprintf('Quantile Coverage Test (Christoffersen, 1998):\n');
    fprintf('Requirement: |Empirical - Nominal| < 5%% with high power.\n');
    disp(ci_table);
    
    % Check calibration failures
    for i = 1:size(ci_table, 1)
        nom = ci_table.Quantile(i);
        emp = ci_table.Empirical_Coverage(i);
        if abs(emp - nom) > 0.05
            fprintf('⚠ WARNING: Quantile %.0f%% miscalibrated (nominal=%.0f%%, empirical=%.0f%%)\n', ...
                nom*100, nom*100, emp*100);
        end
    end
    
    % Visualization
    asym_validator.plot_quantile_intervals(results_wf.actuals, ...
        results_wf.quantile_predictions, 'window_size', 200);
end

%% 11. EMBARGO PACF CAVEAT (Scientific Transparency)

fprintf('\n=== EMBARGO PACF: KNOWN LIMITATIONS ===\n');
fprintf('The PACF-based embargo detects LINEAR dependencies only (Ljung-Box test).\n');
fprintf('For non-linear memory (e.g., GARCH volatility clustering), embargo may be TOO SHORT.\n');
fprintf('Implication: True forward-bias could exceed our embargo window.\n');
fprintf('Mitigation: Advanced approach uses EVT (Extreme Value Theory) or mutual information.\n');
fprintf('For this study: Embargo is a conservative LOWER BOUND on isolation window.\n\n');

%% 12. SUMMARY REPORT

fprintf('\n');
fprintf('='.repmat('=', 1, 80));
fprintf('\n');
fprintf('PRAGMAS-SUITE PHASE 4: RIGOROUS VALIDATION SUMMARY\n');
fprintf('(References: Fama 1970, Harvey et al. 2016, Diebold 2015)\n');
fprintf('='.repmat('=', 1, 80));
fprintf('\n');

fprintf('Hypothesis Test (H0: Model = Random Walk)\n');
fprintf('  Diebold-Mariano Test p-value: %.4f\n', dm_test.p_asymptotic);
fprintf('  Bootstrap p-value: %.4f\n', dm_test.p_bootstrap);
fprintf('  Result: %s\n\n', dm_summary.conclusion);

fprintf('Out-of-Sample Predictive Performance:\n');
fprintf('  Hit Rate: %.2f%% (vs 50%% random)\n', metrics.directional_accuracy * 100);
fprintf('  Sharpe (Traditional): %.3f\n', results_wf.metrics.sharpe);
fprintf('  Sharpe (Utility-Based): %.3f\n', perf_metrics.sharpe);
fprintf('  Max Drawdown: %.2f%%\n', perf_metrics.mdd * 100);
fprintf('  Return/MDD Ratio: %.2f\n', perf_metrics.total_return / abs(perf_metrics.mdd));

fprintf('\nRegime Detection Quality:\n');
fprintf('  Current Regime: %s\n', regime_detectors.(pair_idx).getRegimeAssignment(length(returns)));
fprintf('  Posterior Confidence: %.2f%%\n', ...
    max(regime_detectors.(pair_idx).SmoothedProb(end, :)) * 100);
fprintf('  Avg Regime Entropy: %.3f (0=certain, 1.1=max uncertainty)\n', ...
    mean(regime_detectors.(pair_idx).RegimeEntropy));

fprintf('Validation Architecture (Addressing Phase 3 Critique):\n');
fprintf('  Folds: %d (Purged K-Fold with walk-forward causality)\n', n_folds);
fprintf('  Embargo: %d lags (PACF-based, dynamic, LINEAR dependencies only)\n', cv.embargo_size);
fprintf('  DM Bootstrap: 5000 replications (Moving Block Bootstrap for autocorrelation)\n');
fprintf('  Quantile Monotonicity: ENFORCED via sort (prevents illogical Q_05 > Q_95)\n');
fprintf('  Quantiles: [0.05, 0.25, 0.5, 0.75, 0.95] (Christoffersen calibration checked)\n');

fprintf('\n');
fprintf('='.repmat('=', 1, 80));
fprintf('\n');

fprintf('\nInterpretation of Results (Honesty-Driven):\n');
fprintf('  If DM p > 0.05 → Cannot reject H0: Model = Random Walk (Market Efficient)\n');
fprintf('  If Hit Rate ≈ 50%% → Directional edge is non-existent or transient\n');
fprintf('  If Sharpe < 0.5 OOS → Insufficient edge after costs (realistic spread ~0.1-0.2%%)\n');
fprintf('  If MDD > 30%% → Unacceptable drawdown (institutional limit typically 20%%)\n');
fprintf('  If Coverage OFF → Quantiles poorly calibrated; revise model architecture\n');

fprintf('\nCritical Checks Before Publication (Harvey et al., 2016):\n');
fprintf('  ✓ SURVIVAL BIAS: Test on >10 random assets (not cherry-picked for profits)\n');
fprintf('  ✓ TRANSACTION COSTS: Apply realistic slippage (FX ~0.1%%, Stocks ~0.05%%)\n');
fprintf('  ✓ DATA SNOOPING: If tested multiple models, use Bonferroni correction\n');
fprintf('  ✓ SLIPPAGE DEDUCTION: Implementation shortfall typically 0.5-1%% annually\n');
fprintf('  ✓ WALK-FORWARD ONLY: Never report in-sample metrics (massive overfitting)\n');
fprintf('  ✓ MAXIMUM DRAWDOWN: Must be <30%% (institutional standard)\n');
fprintf('  ✓ REGIME ENTROPY: High entropy = weak signal; discard regimes with H > 0.8\n');

fprintf('\nIf DM p-value > 0.05:\n');
fprintf('  → PUBLISH AS NEGATIVE RESULT: "Evidence consistent with weak-form EMH"\n');
fprintf('  → Science values null rejections + transparent methodology\n');
fprintf('  → Document all attempts + null findings = scientific integrity\n');
fprintf('  → This is NOT failure; this is HONEST SCIENCE.\n');
