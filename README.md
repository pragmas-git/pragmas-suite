```
 ____  ____    _    ____ __  __    _    ____     ____  _   _ ___ _____ _____
|  _ \|  _ \  / \  / ___|  \/  |  / \  / ___|   / ___|| | | |_ _|_   _| ____|
| |_) | |_) |/ _ \| |  _| |\/| | / _ \ \___ \   \___ \| | | || |  | | |  _|
|  __/|  _ < / ___ \ |_| | |  | |/ ___ \ ___) |   ___) | |_| || |  | | | |___
|_|   |_| \_\_/   \_\____|_|  |_/_/   \_\____/   |____/ \___/|___| |_| |_____|
```

# PRAGMAS-SUITE

A MATLAB framework for quantitative finance research with rolling windows and reproducible evaluation. Designed for a final degree project (TFG) focusing on FX forecasting using parametric, nonparametric, and hybrid models.

## Overview

Pragmas-Suite is a comprehensive research framework that implements an end-to-end pipeline for:
- **Data Processing**: Converting intraday FX tick data (Dukascopy format) to canonical daily NY close prices
- **Modeling**: Parametric (GARCH), nonparametric (KDE, LSTM, XGBoost), and hybrid (GARCH+KDE) forecasting models
- **Signal Generation**: Probability-based and threshold-based trading signals
- **Portfolio Optimization**: Markowitz-style portfolio construction
- **Backtesting**: Rolling window backtesting with performance metrics
- **Evaluation**: Statistical tests including VaR backtesting, CRPS scoring, and Diebold-Mariano tests

## Project Status

**Current Implementation (Completed):**
- ✅ End-to-end integration of Dukascopy intraday `.parquet` data → canonical daily series (NY close) per FX pair
- ✅ Daily dataset stored in `data/processed/` and consumed by pipeline without affecting models/backtest
- ✅ Automatic data quality auditing (tables + CSV/MAT + plots) saved to `results/`
- ✅ Parametric (GARCH) and hybrid (GARCH+KDE) models fully implemented
- ✅ VaR backtesting and CRPS evaluation framework
- ✅ Interactive MATLAB App for GUI-based research workflow
- ✅ LaTeX report generation for thesis/documentation

## Project Structure

```
pragmas-suite/
├── app/                    # Interactive MATLAB App (PragmasSuiteApp)
├── backtest/              # Backtesting engine and metrics
├── config/                # Centralized configuration
├── data/                  # Raw/processed/features data
│   ├── raw/              # Dukascopy parquet files (intraday)
│   └── processed/        # Canonical daily close prices
├── evaluation/           # Statistical evaluation methods
│   ├── crps_score.m      # Continuous Ranked Probability Score
│   ├── diebold_mariano.m # DM test for forecast comparison
│   └── var_backtest.m    # VaR backtesting (Kupiec, Christoffersen)
├── main/                 # Orchestration scripts
│   ├── main_run_all.m           # End-to-end pipeline scaffold
│   └── main_experiment_var_crps.m  # VaR+CRPS comparison experiment
├── models/               # Forecasting models
│   ├── parametric/      # GARCH models
│   ├── nonparametric/   # KDE, LSTM, XGBoost (stubs)
│   └── hybrid/          # GARCH+KDE hybrid model
├── portfolios/          # Portfolio optimization (Markowitz)
├── report/              # LaTeX report templates
├── results/             # Outputs (plots, tables, MAT files)
├── signals/             # Signal generation (prob_up, threshold, zscore)
├── tests/               # Unit tests (matlab.unittest)
└── utils/               # Utilities (data loading, returns, features, rolling indices)
```

## FX Data Pipeline (Dukascopy Intraday → Daily NY Close)

### Universe and Period

Currently configured for 4 major FX pairs (based on available data):
- **EURUSD**
- **GBPUSD**
- **AUDUSD**
- **USDJPY**

Default period: **2015–2025**

### Canonical Daily Close Definition

For each New York calendar day (DST-aware), the close is defined as:
- Last mid price `0.5*(ask+bid)` strictly before **17:00 America/New_York**
- Weekends excluded (Monday–Friday only)
- No interpolation or re-sampling; works directly at daily level

### Data Flow: Raw → Processed → Results

1. **Input**: `data/raw/<pair>/..._m1.parquet` (irregular intraday tick data)
2. **Processing**: `utils/build_fx_daily_close_from_parquet.m` builds:
   - `data/processed/fx_daily_close.mat` with `pricesTT` (daily timetable) and `report` (QC statistics)
3. **Loading**: `utils/load_data.m`:
   - If `data/processed/fx_daily_close.mat` exists, loads it
   - If not found but parquet files detected, automatically calls the builder

## Data Quality Reporting

When building the daily dataset from parquet files, the following are automatically generated:

### Reports (CSV/MAT)
- `results/data_quality_report.csv` + `results/data_quality_report.mat`
  - Summary per pair with metrics: total observations, expected vs available days, % missing days, tick statistics per day, spreads, etc.
- `results/data_quality_daily_obs_counts.csv`
  - Long format with `DayNY` and `ObsCount` for auditing and appendices

### Visualizations (PNG)
- `results/data_quality_obs_per_day_hist.png`
  - Histogram of intraday observations per day (per asset)
- `results/data_quality_spread_boxplot.png`
  - Boxplot of absolute spread `|ask-bid|` (sampled, in price units)
- `results/data_quality_spread_bps_boxplot.png`
  - Boxplot of normalized spread in basis points (bps):
    $$\text{Spread}_{bps} = 10^4 \cdot \frac{|ask-bid|}{mid}$$
  - Recommended visualization for comparing liquidity across assets with different price scales

### Interpretation Guide
- **Histogram obs/day**: Tails toward low values typically correspond to holidays, partial sessions, or feed gaps
- **Boxplot absolute spread**: Useful for outlier detection, but not cross-asset comparable (USDJPY lives on a different scale)
- **Boxplot spread in bps**: Direct comparability of liquidity and detection of "real" outliers without scale bias

## Models

### Parametric Models
- **GARCH(1,1)**: Standard GARCH model for volatility forecasting
  - Location: `models/parametric/`
  - Pipeline: `parametric_pipeline.m` (fits GARCH, forecasts mu and sigma)

### Nonparametric Models
- **KDE (Kernel Density Estimation)**: For residual distribution modeling
  - Location: `models/nonparametric/kde_distribution.m`
- **LSTM** and **XGBoost**: Stubs for future implementation
  - Location: `models/nonparametric/`

### Hybrid Models
- **GARCH+KDE**: Combines parametric GARCH volatility with nonparametric residual distribution
  - Location: `models/hybrid/garch_kde_model.m`
  - Process:
    1. Fit rolling GARCH to get `sigma_t`
    2. Compute standardized residuals `z_t = (r_t - mu_t)/sigma_t`
    3. Fit KDE on `z_t` (rolling window)
    4. Reconstruct distribution for `r_{t+1}` via `r ~ mu_t + sigma_t * Z` where `Z ~ KDE`

## Evaluation Methods

### VaR Backtesting
- **Kupiec Test**: Tests unconditional coverage (violation rate)
- **Christoffersen Test**: Tests conditional coverage (independence of violations)
- Location: `evaluation/var_backtest.m`

### CRPS (Continuous Ranked Probability Score)
- Probabilistic forecast accuracy metric (lower is better)
- Implemented for both parametric (Normal) and hybrid (KDE-sampled) distributions
- Location: `evaluation/crps_score.m`

### Diebold-Mariano Test
- Statistical test for forecast comparison
- Tests whether one forecast significantly outperforms another
- Location: `evaluation/diebold_mariano.m`

## Usage

### Quick Start

1. **Load/Create Daily Dataset**:
```matlab
addpath(genpath(pwd));
cfg = config();
pricesTT = load_data(cfg);
```

2. **Run Full Pipeline**:
```matlab
% End-to-end scaffold
main/main_run_all.m

% Or run VaR+CRPS comparison experiment
main/main_experiment_var_crps.m
```

3. **Interactive App**:
```matlab
% Launch GUI
run_app()
% Or directly:
app = PragmasSuiteApp();
```

### Running Tests

```matlab
run_all_tests()
```

Available test suites:
- `TestBuildFxDailyCloseFromParquet.m`
- `TestComputeReturns.m`
- `TestKdeDistribution.m`
- `TestLatexReport.m`
- `TestVarBacktest.m`

## Configuration

Key parameters in `config/config.m`:

### Rolling Windows (TFG-locked)
- `cfg.rolling.train = 1000` (training window size)
- `cfg.rolling.test = 1` (test window size)
- `cfg.rolling.step = 1` (step size for rolling)

### FX Settings
- `cfg.fx.timezone = "America/New_York"` (timezone for close definition)
- `cfg.fx.closeHourNY = 17` (hour for NY close)
- `cfg.fx.qcSampleMax` and `cfg.fx.qcSamplePerFile` (optional, control QC sampling size)

### Risk/Evaluation
- `cfg.alpha = 0.05` (VaR/CVaR level)
- `cfg.confLevel = 0.95` (general confidence level)

### Reproducibility
- `cfg.seed = 42` (RNG seed for reproducibility)

### Portfolio
- `cfg.portfolio.allowShort = false`
- `cfg.portfolio.maxWeight = 1.0`
- `cfg.portfolio.riskAversion = 1.0` (lambda)

## Interface Conventions

- **Time Series**: `timetable` objects (MATLAB native)
- **Model Outputs**: `struct` with at least `mu`, `sigma`, `dist` fields
- **Rolling Windows**: Generated with `utils/get_rolling_indices.m`
- **Returns**: Log returns computed via `utils/compute_returns.m`

## Results Output

### Experiment Results
- `results/experiment_var_crps_*.mat`: Full experiment results
- `results/summary_var_crps.csv`: Summary table for thesis
- `results/crps_timeseries_*.png`: CRPS comparison plots
- `results/var_timeseries_*.png`: VaR comparison plots

### Data Quality
- `results/data_quality_report.csv`: Summary statistics
- `results/data_quality_*.png`: Quality control visualizations

## Interactive App Features

The `PragmasSuiteApp` provides a GUI for:
- **Data Tab**: Load processed data, build QC reports, view quality metrics
- **Models Tab**: Select baseline and hybrid models (currently GARCH and GARCH+KDE)
- **Run Tab**: Configure parameters (seed, alpha, rolling windows) and run experiments
- **Export Tab**: Generate LaTeX reports with optional PDF compilation
- **Visualizations**: Interactive plots for QC, CRPS, and VaR comparisons

## Dependencies

- **MATLAB R2020b+** (for `timetable`, `parquetread`, App Designer)
- **Statistics and Machine Learning Toolbox** (for GARCH, KDE)
- **Financial Toolbox** (optional, for some portfolio functions)
- **pdflatex** (optional, for PDF report compilation)

## Key Features

1. **Reproducible Research**: Fixed RNG seeds, versioned configs, persistent results
2. **Rolling Window Backtesting**: Proper out-of-sample evaluation by construction
3. **Comprehensive Evaluation**: Multiple statistical tests and metrics
4. **Data Quality Assurance**: Automatic QC reports and visualizations
5. **Modular Architecture**: Easy to extend with new models, signals, or evaluation methods
6. **Thesis-Ready Outputs**: LaTeX report generation, publication-quality plots

## Future Work / Stubs

- Full implementation of LSTM and XGBoost models
- Multi-asset portfolio optimization
- Additional signal generation methods
- Extended evaluation metrics (Sharpe, Sortino, etc.)

## License

[Specify license if applicable]

## Author

[Specify author/contributors if applicable]
