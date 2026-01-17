# PRAGMAS-SUITE DASHBOARD: Interactive GUI for Phase 4

## Why Dashboard Over Batch Scripts

### Problem with Batch Scripts (Previous Approach)

```matlab
% main_phase4_rigorous.m
% User must edit this file repeatedly to change parameters
pair_focus = 'EURUSD';              % Edit here
n_folds = 5;                        % Edit here
confidence_level_embargo = 0.05;    % Edit here
target_volatility = 0.12;           % Edit here
% ... 400+ lines of hard-coded logic
main_phase4_rigorous;               % Run all at once
```

**Problems:**
1. **Manual parameter editing** → Error-prone (typos, syntax errors)
2. **No parameter logging** → Can't reproduce "which settings did I use last time?"
3. **No interactivity** → Can't visualize intermediate results or stop early
4. **No auditability** → Hard to track which iterations led to published results
5. **Inefficient iteration** → Change one param = edit file + rerun entire pipeline

### Solution: Interactive Dashboard

```matlab
% Launch once, reuse infinitely
app = PragmasDashboard();
```

**Advantages:**
1. **GUI Parameter Input** → Sliders, spinners, dropdowns (no code editing)
2. **Automatic Logging** → All runs tracked with timestamps + parameters (JSON)
3. **Real-Time Visualization** → See plots update without waiting for full pipeline
4. **Phase-by-Phase Execution** → Run Phase 1 alone, debug, then Phase 2
5. **Export Auditability** → Download results + parameters for publication
6. **No Code Editing** → Researchers never touch MATLAB code (safer)

---

## Dashboard Architecture

### MVC Pattern

```
Model (Business Logic)
├── pragmas.data.DataFetcher
├── pragmas.models.ModelEngineLogReturns
├── pragmas.models.DeepEngineQuantile
├── pragmas.regimes.BayesianMarkovRegimeDetector
├── pragmas.validation.TimeSeriesCrossValidator
├── pragmas.validation.DieboldMarianoBootstrap
├── pragmas.validation.UtilityBasedValidator
└── pragmas.benchmarks.NullBenchmarks

Controller (Callbacks)
├── executePhase1 (Data Fetch)
├── executePhase2 (Model Fit)
├── executePhase3 (Validation)
├── executeFullPipeline (All 3)
├── exportResults (Save to CSV/JSON)
└── clearAll (Reset state)

View (UI Components)
├── UIAxes: Plots (4 panels)
├── UITable: Results metrics
├── UIEditField: Symbol input
├── UISpinner: Folds, Horizon
├── UISlider: Embargo threshold, Risk aversion, VaR level, Leverage cap
├── UIButton: Phase execution + Export
└── UILabel: Status + Progress
```

**Key Design Decision**: Model (engines) is completely decoupled from View (UI).
- If you refactor an engine's interface, only update 1-2 callbacks
- Engines are tested independently (unit tests in `tests/`)
- UI is just a thin wrapper around existing code

---

## Usage Guide

### 1. Launch Dashboard

```matlab
>> PragmasDashboard
```

Or:

```matlab
>> app = PragmasDashboard.launch();
```

### 2. Input Parameters (Left Panel)

#### DATA INPUT Section
- **Symbol**: `BTC-USD`, `EURUSD`, `AAPL`, etc.
- **Asset Type**: `crypto`, `forex`, `stock`, `futures`
- **Start Date**: Picker (e.g., 2020-01-01)
- **End Date**: Picker (e.g., 2026-01-17)

#### VALIDATION PARAMETERS Section
- **Purged K-Folds**: 3-10 (default 5)
  - Higher = more rigorous but slower
  - Lower = faster but less robust
- **PACF Embargo Threshold**: 0.01-0.20 (default 0.05)
  - Higher = longer embargo (more conservative)
  - Lower = shorter embargo (more aggressive)
  - This sets the p-value threshold for determining max significant PACF lag
- **Forecast Horizon**: 1-100 days (default 20)
  - How many days ahead to predict

#### MODEL PARAMETERS Section
- **Risk Aversion (λ)**: 0.5-5.0 (default 2.0)
  - Higher λ = more conservative (lower leverage)
  - Quadratic utility: U(w) = w - (λ/2)w²
- **VaR Confidence**: 0.90-0.99 (default 0.95)
  - Leverage constrained to achieve this VaR level
- **Leverage Cap**: 1.0-5.0 (default 2.0)
  - Maximum leverage allowed (hard constraint)

### 3. Execute Pipeline

#### Option A: Full Pipeline (Easiest)
Click **▶▶ FULL PIPELINE**
- Automatically runs Phase 1, 2, 3 sequentially
- Progress bar shows current phase
- Results appear in Results Table + Plots tabs

#### Option B: Phase-by-Phase (Most Educational)
1. Click **▶ Phase 1: Data Fetch**
   - Fetches data, computes log-returns + Hurst exponent
   - Plots: Price history
   - Status: "✓ Phase 1 complete. Fetched 1500 observations."

2. Click **▶ Phase 2: Model Fit**
   - Fits ARIMA, Bayesian HMM
   - Plots: Regime posteriors over time
   - Status: "✓ Phase 2 complete. Models fitted."

3. Click **▶ Phase 3: Validation**
   - Runs TimeSeriesCrossValidator, DieboldMarianoBootstrap
   - Plots: Drawdown path, Quantile predictions
   - Results Table: DM p-value, MDD, Sharpe, etc.
   - Status: "✓ Phase 3 complete. DM p-value: 0.0847"

### 4. Interpret Results

**Results Table** (Results tab) shows:
| Metric | Value |
|--------|-------|
| Embargo Size (lags) | 8 |
| DM Statistic | -0.342 |
| DM p-value (asymptotic) | 0.0847 |
| DM p-value (bootstrap) | 0.0923 |
| Market Efficiency? | Check if p > 0.05 |

**Interpretation:**
- If **p > 0.05**: Cannot reject null (model = RW). Market is efficient or model overfits.
- If **p < 0.05**: Model beats RW statistically. Verify survival bias next.

**Plots Tab:**
1. **Cumulative Returns (OOS)**: Should show upward trend if model works
2. **Drawdown Path (%)**: Watch for spikes below -20%, -30% (risk thresholds)
3. **Regime Posteriors**: See if HMM identifies Bull/Bear regimes
4. **Quantile Predictions**: Visual of forecast intervals

### 5. Export Results (Reproducibility)

Click **💾 Export Results**

Creates two files:
- `pragmas_results_20260117_143022.csv`: Results table
- `pragmas_params_20260117_143022.json`: Parameters used (for audit trail)

**Example JSON:**
```json
{
  "symbol": "BTC-USD",
  "nFolds": 5,
  "pacfThreshold": 0.05,
  "horizon": 20,
  "riskAversion": 2.0,
  "varConfidence": 0.95,
  "leverageCap": 2.0,
  "timestamp": "20260117_143022"
}
```

**Why?**
- Publication reviewers can request: "Show me the exact params for Figure 3"
- You reply: "See attached pragmas_params_20260117_143022.json"
- Full reproducibility achieved

### 6. Clear & Restart

Click **🗑️ Clear All** to reset all plots, data, and results.

---

## Advanced: Batch Testing (Multiple Assets)

```matlab
% Script to test 10 random currency pairs (survival bias check)
clear; clc;

app = PragmasDashboard();
pairs = {'EURUSD', 'GBPUSD', 'AUDUSD', 'NZDUSD', 'JPYUSD', ...
         'CADUSD', 'CHFUSD', 'NOKUSD', 'SEKUSD', 'SGDUSD'};

results = [];

for i = 1:length(pairs)
    pair = pairs{i};
    
    % Set parameters
    app.SymbolEditField.Value = pair;
    app.FoldsSpinner.Value = 5;
    app.PacfThresholdSlider.Value = 0.05;
    
    % Run pipeline
    app.ExecuteFullPipelineButton.ButtonPushedFcn(app, []);
    pause(2);  % Wait for execution
    
    % Extract p-value from results
    if ~isempty(app.ResultsTable.Data)
        p_val = app.ResultsTable.Data{4, 2};  % DM p-value row
        results = [results; {pair, p_val}];
    end
end

% Display summary
results_table = array2table(results, 'VariableNames', {'Asset', 'DM_pvalue'});
disp(results_table);

% Count how many beat null (p < 0.05)
beat_null = sum(cell2mat(results(:, 2)) < 0.05);
fprintf('Results: %d/%d assets beat RW null (%.1f%%)\n', beat_null, length(pairs), beat_null/length(pairs)*100);
```

---

## Technical Implementation Details

### Parameter Logging (Auditability)

Each execution logs:
```matlab
logRun(app, 'Phase 1: Data Fetch', struct(...
    'symbol', 'BTC-USD', ...
    'startDate', datetime(2020,1,1), ...
    'endDate', datetime('now'), ...
    'assetType', 'crypto', ...
    'nObservations', 1500, ...
    'hurst', 0.523));
```

Stored in `app.RunLog` (in-memory) + exported to JSON (persistent).

### Error Handling

All callbacks wrapped in try-catch:
```matlab
try
    % Execute phase
    logRun(app, 'Phase X', params);
    updateStatus(app, '✓ Phase X complete');
catch ME
    uialert(app.UIFigure, ME.message, 'Phase X Error');
    updateStatus(app, sprintf('✗ Phase X failed: %s', ME.message));
end
```

User sees error in dialog (not command window crash) → safer.

### Asynchronous Execution (Future Enhancement)

Current implementation is synchronous (UI freezes during phase execution).

For truly asynchronous (UI responsive):
```matlab
parfeval(@executePhase1, 0, app);  % Run in background
```

But requires more complex state management. Current approach is fine for most use cases.

---

## Performance Considerations

### Typical Execution Times (on standard hardware)

| Phase | Time | Bottleneck |
|-------|------|-----------|
| Phase 1 (Data Fetch) | 5-30s | API latency |
| Phase 2 (Model Fit) | 10-60s | LSTM/CNN training, EM iterations |
| Phase 3 (Validation) | 30-120s | Bootstrap DM test (1000 reps) |
| **Full Pipeline** | 45-210s | Phase 2 + 3 |

**Optimization Tips:**
- Reduce `EpochsLSTM` if training is slow (Phase 2)
- Reduce `n_bootstrap` in DM test if testing interactively (Phase 3)
- Use smaller `nFolds` (e.g., 3) for rapid iteration

---

## Deployment Options

### Option 1: As-Is (Development)
```matlab
PragmasDashboard;  % Launch from MATLAB editor
```
- Requires MATLAB R2016a+
- Interactive development, easy to modify callbacks
- Full access to workspace (can inspect `app.CurrentData`)

### Option 2: Compiled Executable (Distribution)
```bash
mcc -m PragmasDashboard.m -a +pragmas  # Compile
```
- Creates `PragmasDashboard.exe` (Windows) or `.app` (Mac)
- Run standalone (no MATLAB license required)
- Distribute to non-programmer collaborators
- Slower startup (~10s) due to JVM init

### Option 3: Web App (Cloud)
```bash
matlab.internal.cevalstringeval("navigator.launch(url)")
```
- Requires MATLAB Online or deployment server
- Access from any browser
- Ideal for institutional research labs

---

## Customization Examples

### Add New Parameter
Edit `createComponents` method:
```matlab
row = row + 1;
app.MyParameterLabel = uilabel(app.ControlGridLayout, 'Text', 'My Parameter:');
app.MyParameterSlider = uislider(app.ControlGridLayout, 'Value', 0.5, 'Limits', [0, 1]);
```

Edit callback:
```matlab
function executePhase1(app, ~)
    my_param = app.MyParameterSlider.Value;
    % Use my_param in engine call
end
```

### Add New Plot
The 4 UIAxes (PlotAxes1-4) can be customized in callbacks:
```matlab
plot(app.PlotAxes4, x_data, y_data, 'LineWidth', 2);
title(app.PlotAxes4, 'My Plot');
legend(app.PlotAxes4, {'Series 1', 'Series 2'});
```

### Extend with Custom Metrics
Edit `ResultsTab` section in `createComponents`:
```matlab
results_data = {
    'Metric 1', value1;
    'Metric 2', value2;
    'My Custom Metric', custom_value;  % Add here
};
app.ResultsTable.Data = results_data;
```

---

## FAQ

### Q: My MATLAB version is older than R2016a. Can I use this?
A: App Designer requires R2016a+. For older versions, use the batch script approach (main_phase4_rigorous.m).

### Q: How do I share results with collaborators who don't have MATLAB?
A: Export to CSV/JSON (buttons on dashboard), then share files. They can view in Excel or text editor.

### Q: Can I run multiple assets in parallel?
A: Current implementation is sequential. For parallelization, use parfeval in a custom script, or modify callbacks to use parfor loops.

### Q: The dashboard is slow. What can I optimize?
A: Profile using MATLAB Profiler (Home > Run & Time > Profile). Typically Phase 2 (LSTM training) is slowest—reduce EpochsLSTM or use smaller network.

### Q: I want to modify engine behavior. Do I need to rebuild the dashboard?
A: No. Engines are separate from dashboard. Modify `+pragmas/` code, then dashboard automatically uses updated engines (MATLAB hot-reloads).

---

## Conclusion

The **PragmasDashboard** transforms pragmas-suite from a research prototype (batch scripts + manual iteration) into a **professional research tool** that:

✓ **Reduces cognitive load** (GUI vs. code editing)
✓ **Enables rapid iteration** (sliders beat text edits)
✓ **Ensures reproducibility** (automatic logging)
✓ **Prevents data snooping** (audit trail of all runs)
✓ **Facilitates collaboration** (non-programmers can use it)
✓ **Supports publication** (export parameters for reviewer verification)

Aligned with best practices in scientific software (HCI + reproducibility standards).

---

**Version**: 1.0  
**Status**: ✓ Production Ready  
**Tested**: Phase 1, 2, 3 integration  
**Deployment**: MATLAB R2018a+, compilable to exe/web
