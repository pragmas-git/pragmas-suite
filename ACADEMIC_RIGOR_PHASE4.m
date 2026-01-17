% ACADEMIC RIGOR: Addressing Fundamental Critiques & Phase 4 Roadmap
% 
% This document addresses 5 critical methodological gaps in pragmas-suite v0.3
% and proposes rigorous corrections aligned with academic standards in:
%   - Econometrics (EMH, non-stationarity, variance ratio tests)
%   - Financial ML (look-ahead bias, walk-forward CV, out-of-sample validation)
%   - Statistical hypothesis testing (Diebold-Mariano, Hansen MCS rigor)
%   - Reproducibility (FAIR principles, seed management, benchmarks vs baselines)

%% ============================================================================
%  1. THE "PRICE PREDICTION" FALLACY & LOG-RETURN REFACTORING
% ============================================================================
%
% CURRENT FLAW (v0.3):
%   - ModelEngine.predict() outputs point forecasts of log-prices P_{t+h}
%   - Returns = log(P_t/P_{t-1}), which is stationarity assumption
%   - BUT: μ(P) drifts → EMH violation if predicting mean(P)
%   - MSE loss ignores economic relevance: predicting $1 wrong at $100 vs $1
%
% ROOT CAUSE:
%   Line ~650 in main_hybrid.m:
%     forecasts_arima = engine.predict(20);  % ← Returns log-prices, not log-returns!
%
% PHASE 4 SOLUTION: Dual Prediction Framework
%
%   Level 1: Predictands = Log-Returns (stationary)
%     - Predict: r_{t+h} = log(P_t/P_{t-1})
%     - Loss: MSE(r) ← Standard, but economically neutral
%
%   Level 2: Return Distributions (probabilistic)
%     - Output: {μ, σ²} or quantiles [5%, 25%, 50%, 75%, 95%]
%     - Loss: Log-Score (Pinball Loss for quantiles)
%     - Interpretation: "95% confident return will be [-2%, +3%]"
%
%   Level 3: Null Hypothesis Testing
%     - H0: Sharpe(Model) = Sharpe(Random Walk + drift)
%     - Test: Diebold-Mariano vs naive Pt+1 = Pt (random walk)
%     - Only reject H0 if p-value < 0.05 in out-of-sample
%
% CODE CHANGES REQUIRED:
%
%   % OLD (v0.3):
%   forecasts_arima = engine.predict(20);  % Returns scalar forecasts
%   errors = forecasts_arima - actuals_val;  % Compare levels
%   mse = mean(errors.^2);  % Economically agnostic
%
%   % NEW (Phase 4):
%   [forecasts_arima, pred_dist] = engine.predict(20, 'returns', 'quantiles');
%   % pred_dist.mu = μ(r), pred_dist.sigma = σ(r)
%   % pred_dist.quantiles = [q05, q25, q50, q75, q95]
%
%   % Economically-weighted loss (Pinball Loss):
%   quantile_loss = zeros(5, length(actuals_val));
%   for q_idx = 1:5
%       tau = [0.05, 0.25, 0.50, 0.75, 0.95];
%       quantile_loss(q_idx, :) = max(tau(q_idx) * (actuals_val - pred_dist.quantiles(q_idx, :)), ...
%                                       (tau(q_idx) - 1) * (actuals_val - pred_dist.quantiles(q_idx, :)));
%   end
%   pinball_score = mean(quantile_loss, 2);
%
%   % Null Hypothesis Test: Diebold-Mariano
%   forecast_naive = ones(20, 1) * mean(actuals_val(1:end-1));  % RW + drift
%   error_proposed = forecasts_arima - actuals_val;
%   error_naive = forecast_naive - actuals_val;
%   [dm_stat, p_value_dm] = diebold_mariano_test(error_proposed, error_naive);
%
% REFERENCE:
%   - Diebold & Mariano (1995): "Comparing Predictive Accuracy"
%   - Granger & Newbold (1986): Log-returns for non-stationary series
%   - Christoffersen (2011): "Elements of Financial Risk Management", Ch. 3

%% ============================================================================
%  2. FRACTIONAL DIFFERENTIATION: LOOK-AHEAD BIAS & OUT-OF-SAMPLE d
% ============================================================================
%
% CURRENT FLAW (v0.3):
%   % pragmas_config.m, Line ~15:
%   d_optimal = 0.3;  % ← HARD-CODED, or computed on FULL DATASET
%
%   % This commits look-ahead bias:
%   %   1. Compute d on [P_1 ... P_1000] (entire history)
%   %   2. Apply frac-diff to get [r_1 ... r_1000]
%   %   3. Train on [r_1 ... r_800], test on [r_801 ... r_1000]
%   %   → r_801 already "knows" d was optimal for r_1000!
%
% ROOT CAUSE:
%   fractionalDiff.m computes minimal d via ADF test on full series
%   → Future data pollutes parameter estimation
%
% PHASE 4 SOLUTION: Walk-Forward Fractional Differentiation
%
%   For each fold (train_idx, test_idx):
%     1. Compute d_fold ONLY on train_idx
%     2. Apply d_fold to BOTH train and test
%     3. Test frac-diff on HELD-OUT test_idx
%     → No future information leaks
%
% CODE STRUCTURE (pseudocode):
%
%   class FractionalDiffValidator
%       % Properties
%       OriginalSeries      % Full price series
%       OptimalDList        % d values per fold
%       TestRMSE            % Out-of-sample error
%       
%       % Methods
%       function validate(obj, num_folds)
%           n = length(obj.OriginalSeries);
%           fold_size = floor(n / num_folds);
%           
%           for fold = 1:num_folds
%               % Train-test split
%               train_idx = 1 : fold * fold_size - 1;
%               test_idx = fold * fold_size : min((fold+1)*fold_size, n);
%               
%               % Compute d ONLY on train
%               P_train = obj.OriginalSeries(train_idx);
%               d_fold = estimate_d_adf(P_train, 0.95);  % ← Only train!
%               
%               % Apply to test
%               P_test = obj.OriginalSeries(test_idx);
%               r_test = pragmas.data.fractionalDiff(P_test, d_fold);
%               
%               % Check stationarity (must pass ADF on test)
%               [h_test, pval_adf] = adftest(r_test);
%               obj.TestRMSE(fold) = ~h_test;  % 1 if stationary, 0 if fails
%               obj.OptimalDList(fold) = d_fold;
%           end
%       end
%   end
%
% REFERENCE:
%   - López de Prado (2018): "Advances in Financial Machine Learning", Ch. 5
%   - de Prado & Lewis (2019): "Optimal Asymptotic Least-Squares Estimation"
%   - ADF Test: Augmented Dickey-Fuller, null = non-stationary

%% ============================================================================
%  3. HMM FRAGILITY: REGIME UNCERTAINTY & POSTERIOR PROBABILITIES
% ============================================================================
%
% CURRENT FLAW (v0.3):
%   % MarkovRegimeDetector.viterbiDecode() returns:
%   regime_indices = [1, 1, 2, 2, 3, 1, ...]  % ← POINT ESTIMATE
%   
%   % Then main_hybrid.m (Line ~180):
%   currentRegime = regimes(end);  % Last regime
%   if currentRegime == 1
%       bestModel = 'LSTM';  % ← BINARY DECISION with 0 uncertainty!
%   end
%
%   % PROBLEM:
%   % - If HMM is 60% confident in "Bull" and 40% confident in "Bear"
%   %   → Taking LSTM (Bull choice) is overconfident
%   % - Viterbi gives MAP estimate, ignores posterior variance
%   % - Regime flip at t+1 invalidates t's trading decision
%
% ROOT CAUSE:
%   MarkovRegimeDetector outputs P(S_t | F_t) implicitly in Viterbi,
%   but code ignores posterior confidence intervals
%
% PHASE 4 SOLUTION: Bayesian HMM with Posterior Uncertainty
%
%   Instead of Viterbi (hard assignment), use Backward Filtering:
%   
%   γ_t,i = P(S_t = i | F_T)  % Smoothed posterior, not filtered
%   
%   Then, for each time t, report:
%     State = argmax_i(γ_t,i)
%     Confidence = max(γ_t,i) ∈ [1/3, 1]  (1/3 = uniform, 1 = certain)
%
% CODE STRUCTURE:
%
%   class BayesianMarkovRegimeDetector < MarkovRegimeDetector
%       % Additional property
%       SmoothedPosterior  % γ_t,i matrix (T x K)
%       StateConfidence    % max(γ_t,i) per time (T x 1)
%       
%       function [regimes, confidence] = getRegimesWithUncertainty(obj)
%           % Backward-Filtering-Forward-Sampling (Kim, 1994)
%           obj.SmoothedPosterior = obj.backward_algorithm();  % ← Replaces Viterbi
%           [~, regimes] = max(obj.SmoothedPosterior, [], 2);  % Hard assign
%           confidence = max(obj.SmoothedPosterior, [], 2);    % Uncertainty
%       end
%       
%       function model_selection(obj, models)
%           % Conditional model choice WITH uncertainty
%           for t = 1:length(obj.regimes)
%               prob_bull = obj.SmoothedPosterior(t, 1);
%               prob_bear = obj.SmoothedPosterior(t, 2);
%               prob_sideways = obj.SmoothedPosterior(t, 3);
%               
%               % Weighted ensemble instead of binary choice
%               forecast(t) = prob_bull * models.lstm(t) + ...
%                             prob_bear * models.cnn(t) + ...
%                             prob_sideways * models.arima(t);
%           end
%       end
%   end
%
% ECONOMIC IMPLICATION:
%   - When confidence < 0.50 (noisy regime), use ENSEMBLE instead of LSTM
%   - Reduces regime-lag errors (drawdown amplification)
%   - More honest uncertainty reporting
%
% REFERENCE:
%   - Kim (1994): "Smoothing algorithms for state-space models"
%   - Guidolin & Timmermann (2007): "Asset allocation under multivariate regime switching"
%   - Hamilton (1989): "A new approach to the economic analysis of nonstationary time series"

%% ============================================================================
%  4. MODEL CONFIDENCE SET: ECONOMIC LOSS FUNCTIONS & PAIRWISE TESTS
% ============================================================================
%
% CURRENT FLAW (v0.3):
%   % HybridValidator.m, Line ~200:
%   mse_loss = (predictions - actuals).^2;  % ← Symmetric loss!
%   
%   % Then MCS compares mean MSE:
%   mean_loss = mean(mse_loss, 1);  % [0.0145, 0.0123, 0.0156, 0.0133]
%   
%   % PROBLEM:
%   % - MSE penalizes +1% error = -1% error equally
%   % - In finanzas, missing upside (Type I) costs different than downside miss (Type II)
%   % - Example: +2% move missed vs -2% move missed are ECONOMICALLY different
%   %   (upside miss = lost profit; downside miss = lost risk hedging)
%   % - MCS becomes overpowered (all 4 models in set) because they're similar
%
% ROOT CAUSE:
%   Loss function is L(ŷ, y) = (ŷ - y)² , which is economically neutral
%
% PHASE 4 SOLUTION: Asymmetric Loss Functions & Pairwise Diebold-Mariano
%
%   1. ASYMMETRIC LOSS (Pinball Loss for quantiles):
%      L_τ(e) = max(τ * e, (τ-1) * e)  for τ ∈ {0.05, 0.25, 0.50, 0.75, 0.95}
%      → Penalizes under-/over-forecasts differently
%
%   2. ECONOMIC LOSS (Directional Accuracy):
%      L_dir(ŷ, y) = -I[sign(ŷ-ŷ_t-1) = sign(y-y_t-1)]
%      → "Did you predict the right direction?"
%      → More relevant for trading signals
%
%   3. PAIRWISE DIEBOLD-MARIANO TEST within MCS:
%      For models i, j in MCS set:
%         H0: E[loss_i - loss_j] = 0
%         Test: DM statistic = (loss_i - loss_j) / SE
%         p_ij = 2 * (1 - normcdf(|DM|))
%         If p_ij < 0.05 → Cannot include both i and j
%         → Eliminates redundant models
%
% CODE STRUCTURE:
%
%   class RigorousHybridValidator < HybridValidator
%       % Additional properties
%       AsymmetricLosses  % Pinball loss per quantile
%       PairwiseDM        % Diebold-Mariano matrix (K x K)
%       ReducedMCSSet     % After pairwise tests
%       
%       function validator = RigorousHybridValidator(models, loss_type, asymmetric_tau)
%           % Constructor with asymmetric loss params
%           % asymmetric_tau = [0.05, 0.25, 0.50, 0.75, 0.95]
%       end
%       
%       function computeAsymmetricLosses(obj, tau_vector)
%           % Compute pinball loss
%           errors = obj.Predictions - repmat(obj.Actuals, 1, size(obj.Predictions, 2));
%           
%           for tau_idx = 1:length(tau_vector)
%               tau = tau_vector(tau_idx);
%               obj.AsymmetricLosses(tau_idx, :) = max(tau * errors, (tau - 1) * errors);
%           end
%           
%           % Aggregate across quantiles
%           obj.Losses = mean(obj.AsymmetricLosses, 1);  % Average pinball
%       end
%       
%       function computePairwiseDieboldMariano(obj)
%           % Test all pairs for significant differences
%           K = size(obj.Losses, 2);
%           obj.PairwiseDM = zeros(K, K);
%           
%           for i = 1:K
%               for j = i+1:K
%                   loss_diff = obj.Losses(:, i) - obj.Losses(:, j);
%                   [dm_stat, p_val] = diebold_mariano(loss_diff);
%                   obj.PairwiseDM(i, j) = p_val;
%                   obj.PairwiseDM(j, i) = p_val;
%               end
%           end
%       end
%       
%       function mcs_refined = computeMCSWithPairwiseRefinement(obj, alpha)
%           % Standard MCS first
%           mcs_initial = obj.computeMCS(alpha);  % ← v0.3 method
%           
%           % Then eliminate redundant models via pairwise tests
%           obj.computePairwiseDieboldMariano();
%           mcs_refined = mcs_initial;
%           
%           for i = 1:length(mcs_initial)
%               for j = i+1:length(mcs_initial)
%                   if obj.PairwiseDM(mcs_initial(i), mcs_initial(j)) < alpha
%                       % Keep better one, remove worse
%                       loss_i = mean(obj.Losses(mcs_initial(i), :));
%                       loss_j = mean(obj.Losses(mcs_initial(j), :));
%                       if loss_i > loss_j
%                           mcs_refined = mcs_refined(mcs_refined ~= mcs_initial(i));
%                       else
%                           mcs_refined = mcs_refined(mcs_refined ~= mcs_initial(j));
%                       end
%                   end
%               end
%           end
%       end
%   end
%
% REFERENCE:
%   - Hansen, Lunde & Nason (2011): "The Model Confidence Set" (original)
%   - Koenker & Mizera (2014): "Quantile regression"
%   - Diebold & Mariano (1995): Comprehensive pairwise testing

%% ============================================================================
%  5. OUT-OF-SAMPLE VALIDATION: WALK-FORWARD CV & BENCHMARKS
% ============================================================================
%
% CURRENT FLAW (v0.3):
%   % main_hybrid.m uses simple train-test split:
%   train_idx = 1:150;
%   test_idx = 151:180;
%   
%   % PROBLEMS:
%   % 1. Single split = high variance in performance estimate
%   % 2. No walk-forward = assumes future = past (violated in regimes)
%   % 3. No null model = no baseline to beat
%   % 4. No bootstrap CIs = reported Sharpe could be spurious
%
% ROOT CAUSE:
%   DeepEngine.prepareData() does naive random split, ignoring time series structure
%
% PHASE 4 SOLUTION: Purged K-Fold Walk-Forward with Embargo
%
%   % Pseudo-code:
%   class TimeSeriesCrossValidator
%       function [train_idx_folds, test_idx_folds] = purged_k_fold(data, n_folds, embargo_pct)
%           % Purged K-Fold avoids look-ahead bias (López de Prado, 2018)
%           n = length(data);
%           fold_size = floor(n / n_folds);
%           embargo = floor(embargo_pct * fold_size);
%           
%           for fold = 1:n_folds
%               test_start = (fold - 1) * fold_size + 1;
%               test_end = fold * fold_size;
%               test_idx = test_start:test_end;
%               
%               % Embargo: exclude samples near test boundary (to avoid lookahead)
%               embargo_start = max(1, test_start - embargo);
%               embargo_end = min(n, test_end + embargo);
%               
%               % Train = all except test + embargo
%               train_idx = setdiff(1:n, embargo_start:embargo_end);
%               
%               train_idx_folds{fold} = train_idx;
%               test_idx_folds{fold} = test_idx;
%           end
%       end
%       
%       function results = walk_forward_backtest(model, data, cv_folds)
%           % For each fold, train on earlier data, test on future
%           n_folds = length(cv_folds);
%           results.predictions = [];
%           results.actuals = [];
%           
%           for fold = 1:n_folds
%               train_idx = cv_folds(fold).train_idx;
%               test_idx = cv_folds(fold).test_idx;
%               
%               % Train on past
%               model.fit(data(train_idx));
%               
%               % Predict future (out-of-sample)
%               pred_fold = model.predict(data(test_idx));
%               
%               results.predictions = [results.predictions; pred_fold];
%               results.actuals = [results.actuals; data(test_idx)];
%           end
%           
%           % Compute OOS metrics (unbiased performance)
%           results.sharpe_oos = compute_sharpe(results.predictions, results.actuals);
%           results.dm_pvalue = diebold_mariano(results.predictions, benchmark_predictions);
%       end
%   end
%
% NULL MODELS (Must include):
%   1. Random Walk: P_t+1 = P_t
%   2. Random Walk + Drift: P_t+1 = P_t + mean(ΔP)
%   3. Seasonal Naive: P_t+1 = P_t-252  (yearly seasonality)
%   4. Exponential Smoothing: EWMA baseline
%
%   → If your LSTM Sharpe < Sharpe(RW+drift), you're overfitting
%
% CODE INTEGRATION:
%
%   % v0.3 (Naive):
%   [train_idx, test_idx] = split_data(returns, 0.8);
%   model.train(returns(train_idx));
%   forecast = model.predict(20);
%   sharpe = compute_sharpe(forecast, returns(test_idx:end));  % Biased!
%
%   % Phase 4 (Rigorous):
%   cv = TimeSeriesCrossValidator(returns);
%   cv_folds = cv.purged_k_fold(returns, 5, 0.1);  % 5 folds, 10% embargo
%   
%   % Compare models
%   models = {'LSTM', 'ARIMA', 'RW+Drift', 'EWMA'};
%   for m_idx = 1:length(models)
%       results(m_idx) = cv.walk_forward_backtest(models{m_idx}, returns, cv_folds);
%   end
%   
%   % Only report OOS metrics
%   sharpe_oos = arrayfun(@(r) r.sharpe_oos, results);
%   dm_pvalues = arrayfun(@(r) r.dm_pvalue, results);
%   
%   % Report: "LSTM Sharpe = 0.95 (p=0.23 vs RW+Drift)" 
%   %         → Not significant, likely overfitting
%
% REFERENCE:
%   - López de Prado (2018): "Advances in Financial Machine Learning", Ch. 7
%   - Hyndman & Athanasopoulos (2021): "Forecasting: Principles & Practice", Ch. 3
%   - Christoffersen (2011): "Elements of Financial Risk Management"

%% ============================================================================
%  SUMMARY TABLE: Current Flaws vs Phase 4 Solutions
% ============================================================================
%
%  Issue                           | v0.3 Status    | Phase 4 Solution
% ─────────────────────────────────┼────────────────┼─────────────────────────
%  1. Price Prediction Fallacy      | ✗ Predicts P   | ✓ Predicts r + quantiles
%  2. Look-Ahead Bias (FracDiff)    | ✗ Full-sample d | ✓ Walk-forward d
%  3. HMM Regime Uncertainty        | ✗ Hard Viterbi | ✓ Posterior γ_t,i
%  4. Economic Loss Functions       | ✗ MSE only     | ✓ Pinball + Directional
%  5. MCS Redundancy                | ✗ Large set    | ✓ Pairwise DM tests
%  6. Out-of-Sample Validation      | ✗ Single split | ✓ Purged K-Fold WF
%  7. Null Model Comparison         | ✗ None         | ✓ RW, RW+Drift, EWMA
%  8. Diebold-Mariano Tests         | ✗ No tests     | ✓ p-values reported
%  9. Bootstrap Confidence Intervals | ✗ No CIs       | ✓ Bootstrap Sharpe CIs
% 10. Reproducibility & Seeds       | ✗ Ad-hoc       | ✓ Full seed mgmt
%
%% ============================================================================
%  PHASE 4 ARCHITECTURE: Refactored Classes
% ============================================================================
%
% NEW CLASSES (to be implemented):
%
%   1. pragmas.validation.AsymmetricLossValidator
%      - Pinball loss for quantiles
%      - Directional accuracy metrics
%      - Pairwise Diebold-Mariano tests
%
%   2. pragmas.validation.TimeSeriesCrossValidator
%      - Purged K-Fold walk-forward
%      - Embargo handling
%      - Out-of-sample evaluation
%
%   3. pragmas.regimes.BayesianMarkovRegimeDetector
%      - Smooth posterior γ_t,i instead of hard Viterbi
%      - Posterior confidence intervals
%      - Probabilistic model selection
%
%   4. pragmas.models.RobustDeepEngine
%      - Log-return prediction instead of prices
%      - Probabilistic outputs (quantile regression)
%      - Walk-forward training with embargo
%
%   5. pragmas.benchmarks.NullModelComparator
%      - Random Walk baseline
%      - Random Walk + Drift
%      - Seasonal Naive
%      - Comparison via Diebold-Mariano
%
% INTEGRATION (main_academic_rigorous.m):
%   % Full walk-forward backtest with null models
%   cv = TimeSeriesCrossValidator(returns, 5);
%   
%   models = {
%       'ARIMA-GARCH (Phase 2.1)', engine_arima;
%       'LSTM (Phase 3.1)', dlEngine_lstm;
%       'Random Walk', NaiveModel('rw');
%       'RW + Drift', NaiveModel('rw_drift');
%   };
%   
%   for fold = 1:cv.n_folds
%       % Train on in-sample
%       for m = 1:length(models)
%           models(m).fit(returns(cv.train_idx(fold)));
%           pred(m) = models(m).predict(length(cv.test_idx(fold)));
%       end
%       
%       % Evaluate OOS
%       results(fold) = evaluate_oos(pred, returns(cv.test_idx(fold)));
%   end
%   
%   % Aggregate OOS performance
%   sharpe_oos = mean([results.sharpe]);
%   dm_pval = diebold_mariano_vs_best(results);
%   
%   % Report with uncertainty
%   fprintf('LSTM Sharpe (OOS) = %.3f ± %.3f (CI95%%)\n', ...
%       mean(sharpe_oos), std(sharpe_oos) * 1.96);
%   fprintf('vs RW+Drift: p-value = %.3f %s\n', dm_pval, ...
%       iif(dm_pval < 0.05, '[SIGNIFICANT]', '[NOT significant]'));

%% ============================================================================
%  SCIENTIFIC INTEGRITY CHECKLIST (Phase 4)
% ============================================================================
%
%  ☐ Null Hypothesis: H0 = "Model ≡ Random Walk" (EMH)
%  ☐ Predictands: Log-returns (stationary), not prices
%  ☐ Loss Function: Asymmetric (Pinball or Directional), not MSE
%  ☐ Validation: Walk-forward with embargo (no lookahead bias)
%  ☐ Baselines: RW, RW+Drift, EWMA, Seasonal Naive
%  ☐ Hypothesis Tests: Diebold-Mariano vs each baseline
%  ☐ Uncertainty Quantification: 95% CI on Sharpe, VaR, MDD
%  ☐ Reproducibility: Fixed seeds, saved results, published code
%  ☐ Regime Uncertainty: Posterior γ_t,i instead of hard states
%  ☐ MCS Refinement: Pairwise tests to eliminate redundancy
%  ☐ Data Leakage Audit: d, α, β estimated on train only
%  ☐ Benchmark vs Literature: Compare vs Nixtla, Prophet, statsmodels
%  ☐ Out-of-Sample Only: Report test metrics, never train metrics
%  ☐ Transaction Costs: Deduct 10-50 bps per trade (real slippage)
%  ☐ Regime Transitions: Test robustness during HMM regime changes
%
%% ============================================================================
%  EXPECTED IMPACT ON v0.3 Reported Metrics
% ============================================================================
%
% WARNING: Phase 4 rigor will likely REDUCE reported performance:
%
%  Metric              | v0.3 (In-Sample) | Phase 4 (Out-of-Sample)
% ─────────────────────┼──────────────────┼─────────────────────────
%  LSTM Sharpe         | 1.567            | 0.45 (70% reduction likely)
%  ARIMA-GARCH Sharpe  | 1.123            | 0.32
%  Vs RW+Drift p-val   | N/A (no test)    | 0.68 (NOT significant)
%  MCS Set Size        | 3/4 models       | 1/4 models (only RW survives)
%
% This is NOT a failure—it's scientific honesty.
% "A significant finding is a hypothesis generating a reportable p-value."
% If pragmas-suite cannot beat RW out-of-sample, it reveals:
%   1. Markets are more efficient than assumed
%   2. Models are overfit
%   3. More data / better features needed
%
% This is valuable negative result worth publishing.

%% ============================================================================
%  PUBLICATION STRATEGY (Post Phase 4)
% ============================================================================
%
% Reframe pragmas-suite as:
%   NOT: "We built a superior trading system"
%   BUT: "A reproducible MATLAB framework for testing ML in finance,
%         with safeguards against methodological pitfalls"
%
% Target journals (desk-rejectable now, but Phase 4 salvageable):
%   - Journal of Financial Data Science (JFDS)
%   - Quantitative Finance (IF=2.1)
%   - Journal of Machine Learning Research (JMLR)
%   - arXiv (preprint immediately)
%
% Key claims:
%   1. "We discovered that EMH holds in our sample" (null hypothesis)
%   2. "Walk-forward validation reveals overfitting in simple models"
%   3. "Bayesian regime detection improves robustness in transitions"
%   4. "Asymmetric loss functions outperform MSE in direction forecasting"
%
% This is publishable if honest about limitations.

%% ============================================================================
%  CONCLUSION: From Ambitious to Rigorous
% ============================================================================
%
% pragmas-suite v0.3 is AMBITIOUS but UNVALIDATED.
% Phase 4 makes it RIGOROUS by accepting uncomfortable truths:
%
%   ✓ Accept that most ML fails in finance (Blitz et al., 2020)
%   ✓ Test against random walk (embarrass yourself early)
%   ✓ Use out-of-sample metrics exclusively
%   ✓ Report uncertainty (CIs, p-values, posterior γ)
%   ✓ Publish negative results (still valuable)
%
% Expected outcome:
%   - If pragmas-suite survives Phase 4: publishable contribution
%   - If it fails: still publishable as "cautionary tale"
%     (e.g., "Why 99% of ML in finance fails")
%
% This is science. Let's be honest.
