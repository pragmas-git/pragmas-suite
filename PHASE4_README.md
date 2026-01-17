# PRAGMAS-SUITE PHASE 4: RIGOROUS ECONOMETRIC VALIDATION

## Overview

**Phase 4** transforms pragmas-suite from an ambitious hybrid model (Phase 1-3) into a **publication-ready research framework** with academic rigor comparable to Econometrica or Journal of Finance standards.

## What Changed from Phase 3

### Methodological Fixes

| Issue | Phase 3 Problem | Phase 4 Solution |
|-------|-----------------|-----------------|
| **Price Prediction Fallacy** | Models predicted non-stationary prices | Predict stationary log-returns only |
| **Look-Ahead Bias** | Fractional diff d computed on full dataset | Compute d per fold + dynamic embargo |
| **Regime Uncertainty** | Hard Viterbi assignments without confidence | Bayesian posteriors γ_t,i with CIs |
| **Loss Function** | MSE (economically agnostic) | Pinball loss + utility-based maximization |
| **Validation** | Single train-test split | Purged K-Fold with walk-forward causality |

### Key Implementations

1. **TimeSeriesCrossValidator.m** (650 lines)
   - Purged K-Fold walk-forward validation
   - Dynamic PACF-based embargo (not fixed %)
   - Strict causality: train indices < test start

2. **DieboldMarianoBootstrap.m** (600 lines)
   - Moving Block Bootstrap for robust hypothesis testing
   - Handles autocorrelation + non-normality in returns
   - Both asymptotic & bootstrap p-values (transparency)

3. **NullBenchmarks.m** (400 lines)
   - Random Walk, RW+Drift, Seasonal Naive baselines
   - Tests H₀: "Model = Random Walk" (market efficiency)

4. **AsymmetricLossValidator.m** (550 lines)
   - Pinball loss for quantile regression
   - Directional accuracy metrics
   - Christoffersen (1998) coverage calibration test

5. **UtilityBasedValidator.m** (500 lines)
   - Quadratic utility: U(w) = w - (λ/2)w²
   - Optimal leverage under VaR constraint
   - Sharpe, Sortino, Calmar ratios

6. **DeepEngineQuantile.m** (550 lines)
   - Refactored for log-returns (stationary)
   - Quantile outputs: [Q₀.₀₅, Q₀.₂₅, Q₀.₅₀, Q₀.₇₅, Q₀.₉₅]
   - Pinball loss instead of MSE

7. **ModelEngineLogReturns.m** (450 lines)
   - ARIMA/GARCH on log-returns
   - Confidence intervals from volatility forecasts

8. **BayesianMarkovRegimeDetector.m** (750 lines)
   - Probabilistic regime detection (posteriors, not Viterbi)
   - EM algorithm for parameter estimation
   - Shannon entropy quantifies regime uncertainty

## Quick Start

### 1. Run Verification

```matlab
VERIFY_PHASE4_IMPLEMENTATION;  % Checks all components
```

### 2. Run Phase 4 Pipeline

```matlab
pragmas_config;              % Initialize config
main_phase4_rigorous;        % Full integration example
```

### 3. Understand the Risk Visualization

```matlab
example_mdd_visualization;   % Why MDD matters more than Sharpe
```

## The "Honesty Filter": Diebold-Mariano Test

The DM Bootstrap test is the core of Phase 4's scientific integrity:

```
If DM p-value > 0.05
  ↓
  Cannot reject H₀: Model = Random Walk
  ↓
  INTERPRETATION: Market is efficient OR model overfits
  ↓
  This is PUBLISHABLE (negative results matter!)
```

**Key insight**: If your model can't beat RW out-of-sample, that's a *major finding*, not a failure.

## Critical Checks Before Publication

- [ ] **Survival Bias**: Test on >10 random assets (not cherry-picked)
- [ ] **Transaction Costs**: Deduct realistic spreads (FX ~0.1%, Stocks ~0.05%)
- [ ] **Slippage**: -0.5% to -1% annually for implementation shortfall
- [ ] **Walk-Forward Only**: Never report in-sample Sharpe (massive bias)
- [ ] **Quantile Calibration**: Empirical coverage ≈ Nominal (Christoffersen test)
- [ ] **Maximum Drawdown**: Must be <30% (institutional standard)
- [ ] **Data Snooping**: If multiple variants tested, apply Bonferroni correction
- [ ] **Regime Entropy**: Discard regimes with H > 0.8 (too uncertain)

## Expected Outcomes

### Based on Market Efficiency Theory (Fama, 1970)

**In-sample (Phase 3):**
- Sharpe: ~1.5
- Hit Rate: 60-65%

**Out-of-sample (Phase 4, expected):**
- Sharpe: 0.2-0.5 (70% decline)
- Hit Rate: 51-55% (barely above random)
- DM p-value: >0.05 in most asset classes

### Interpretation if p > 0.05

```
"Results are consistent with weak-form market efficiency.
The hybrid model fails to produce economically significant 
profits after accounting for transaction costs, suggesting
either: (1) markets are efficient, or (2) our methods cannot
exploit the available patterns. This negative result prevents
others from pursuing similar approaches (Harvey et al., 2016)."
```

## File Structure

```
+pragmas/
├── +benchmarks/
│   └── NullBenchmarks.m                    [NEW]
├── +data/
│   ├── computeHurst.m
│   ├── DataFetcher.m
│   └── fractionalDiff.m
├── +models/
│   ├── DeepEngine.m
│   ├── DeepEngineQuantile.m                [NEW]
│   ├── ModelEngine.m
│   └── ModelEngineLogReturns.m             [NEW]
├── +regimes/
│   ├── BayesianMarkovRegimeDetector.m      [NEW]
│   └── MarkovRegimeDetector.m
├── +trading/
└── +validation/
    ├── AsymmetricLossValidator.m           [NEW]
    ├── DieboldMarianoBootstrap.m           [NEW]
    ├── HybridValidator.m
    ├── TimeSeriesCrossValidator.m          [NEW]
    └── UtilityBasedValidator.m             [NEW]

[ROOT]
├── main.m
├── main_phase2.m
├── main_phase4_rigorous.m                  [NEW - ENTRY POINT]
├── example_mdd_visualization.m             [NEW - PEDAGOGY]
├── PHASE4_IMPLEMENTATION_SUMMARY.m         [NEW - DOCUMENTATION]
├── VERIFY_PHASE4_IMPLEMENTATION.m          [NEW - VERIFICATION]
└── pragmas_config.m
```

## Key Technical Insights

### 1. Dynamic Embargo (Not Fixed %)

Traditional approaches use fixed embargo: `embargo_size = 0.12 * T`

Phase 4 uses **PACF-based embargo**:
- Compute PACF up to T/5 lags
- Find max lag where significance > 95% confidence
- Use that as embargo size (data-driven, not arbitrary)

**Why**: Different assets have different serial dependencies. Fixed % wastes information in stable periods, allows leakage in volatile periods.

### 2. Moving Block Bootstrap for DM Test

Standard DM test assumes i.i.d. errors. Financial returns are autocorrelated (GARCH clustering).

Phase 4 uses **Moving Block Bootstrap (MBB)**:
- Samples blocks of consecutive returns together
- Preserves temporal dependence structure
- More robust p-values than asymptotic normal

**Why**: Non-normal + autocorrelated data = unreliable asymptotic p-values. Bootstrap p-value is "honest p-value".

### 3. Quantile Monotonicity Enforcement

DL networks can predict illogical quantiles: Q₀.₀₅ > Q₀.₅₀ > Q₀.₉₅

Phase 4 applies: `sort(quantile_predictions, 2)` after inference

**Why**: Violated monotonicity → negative variance → nonsensical strategy leverage.

### 4. Utility-Based Over MSE

Investor utility depends on **drawdown**, not prediction accuracy.

Phase 4 optimizes:
- Quadratic utility U(w) = w - (λ/2)w²
- Subject to |leverage| ≤ 3 and VaR₉₅ ≤ target

**Why**: Model with terrible MSE but 51% directional accuracy beats MSE-optimal model with 48% accuracy and high volatility.

## Common Pitfalls to Avoid

### ❌ Mistake 1: In-Sample Metrics

```matlab
% WRONG: Reports in-sample Sharpe
results = model.fit(data);
sharpe = results.sharpe;  % Massive overfitting bias!
```

### ✓ Correct: Walk-Forward Only

```matlab
% RIGHT: Reports out-of-sample Sharpe
cv = TimeSeriesCrossValidator(data, 5);
results = cv.crossValidate(model);
sharpe_oos = results.sharpe;  % Unbiased estimate
```

### ❌ Mistake 2: Not Deducting Costs

```matlab
% WRONG: Sharpe before costs
sharpe_gross = 0.45;

% RIGHT: Sharpe after costs
costs_annual = 0.001;  % 10 bps spread
sharpe_net = 0.45 - (costs_annual / daily_vol);
```

### ❌ Mistake 3: Cherry-Picking Assets

```matlab
% WRONG: Test only profitable symbols
symbols = {'EURUSD', 'GBPUSD'};  % Chosen because they worked

% RIGHT: Blind universe sampling
all_symbols = load('bloomberg_all_pairs.csv');
symbols = datasample(all_symbols, 10);  % Random 10
```

## Scientific References

1. **Fama (1970)**: "Efficient Capital Markets: A Review of Theory and Empirical Work"
   - Defines weak-form efficiency (history doesn't predict)

2. **Diebold & Mariano (1995)**: "Comparing Predictive Accuracy"
   - Foundation for DM test

3. **Politis & Romano (1994)**: "The Stationary Bootstrap"
   - Moving Block Bootstrap theory

4. **Christoffersen (1998)**: "Evaluating Interval Forecasts"
   - Calibration test for quantiles

5. **Harvey et al. (2016)**: "...and the Cross-Section of Expected Returns"
   - Shows >95% of factors disappear under proper testing

## Support & Debugging

### Q: My Sharpe dropped 70%—did I mess up?

**A**: No, this is **expected**. In-sample Sharpe ~1.5 is likely overfitting. OOS Sharpe 0.3-0.5 is realistic for financial models.

### Q: My DM p-value is 0.08. Should I still publish?

**A**: YES. Reporting p=0.08 is more honest than cherry-picking p=0.04 by testing 10 variants. Report all tests, apply Bonferroni if needed.

### Q: Can I use shorter embargo to get more test samples?

**A**: No. Embargo is minimum isolation window required for causal validity. Using shorter embargo is **look-ahead bias**, which invalidates the entire study.

### Q: What if my regime detector shows high entropy (H>0.8)?

**A**: High entropy = regime assignment is uncertain. Discard those regimes and use simple 2-regime model, or fall back to null baseline. Uncertainty is information!

## Contact & Contributing

This Phase 4 represents a methodological commitment to **transparency**, **rigor**, and **honest science**.

If you improve any component:
1. Maintain backward compatibility
2. Add unit tests in `tests/` folder
3. Document changes in CHANGELOG
4. Consider submitting to academic venue for peer review

## Final Note

> "The most important question in finance is not 'can we build it?',
> but 'does it work out-of-sample against null baselines?'"
>
> — Based on Harvey et al. (2016)

Phase 4 is designed to answer that question with **scientific rigor**.

---

**Version**: 4.0  
**Date**: January 2026  
**Status**: ✓ Production Ready  
**Tested**: 10 new modules, 4,000+ lines of code  
**Next**: Run `main_phase4_rigorous.m` on your data and interpret honestly.
