%% VISUALIZATION ENHANCEMENT: Maximum Drawdown Focus
% 
% INSIGHT FROM USER CRITIQUE:
% "Un inversor no le importa el retorno absoluto. Le importa el MDD."
% 
% Drawdown = (Current Value - Previous Peak) / Previous Peak
% Maximum Drawdown (MDD) = min(Drawdown across all time)
% 
% Why MDD matters:
%   - Psychological: Investors abandon strategies during 30%+ drawdowns
%   - Risk Capital: MDD determines minimum capital required (VAR-like metric)
%   - Institutional: Funds typically fire managers with MDD > 20-25%
%
% This script replaces the simplistic cumsum plot with risk-centric visualization

clear all; close all; clc;

%% 1. SIMULATE EXAMPLE RETURNS (Realistic)

rng(42);  % Reproducibility

% Three scenarios: 
% A) Good model (small MDD, positive drift)
% B) Mediocre (large MDD, small positive drift) 
% C) Null (Random Walk)

T = 252 * 3;  % 3 years daily

% Scenario A: Good model (Sharpe~0.6, MDD~15%)
returns_good = 0.0001 + randn(T, 1) * 0.008;  % 10% annual vol, positive drift
returns_good(returns_good < -0.04) = -0.02;   % Asymmetric loss tail

% Scenario B: Mediocre (Sharpe~0.2, MDD~35%)
returns_mediocre = 0.00005 + randn(T, 1) * 0.012;
crash_idx = [300, 500, 800];
returns_mediocre(crash_idx) = -0.05;

% Scenario C: Null (Random Walk)
returns_null = randn(T, 1) * 0.010;

%% 2. COMPUTE CUMULATIVE WEALTH AND DRAWDOWN

function [wealth, mdd, dd_ts] = computeDrawdown(returns, initial)
    wealth = initial * cumprod(1 + returns);
    running_max = cummax(wealth);
    dd_ts = (wealth - running_max) ./ running_max;  % Drawdown time series
    mdd = min(dd_ts);
end

[w_good, mdd_good, dd_good] = computeDrawdown(returns_good, 1);
[w_med, mdd_med, dd_med] = computeDrawdown(returns_mediocre, 1);
[w_null, mdd_null, dd_null] = computeDrawdown(returns_null, 1);

%% 3. STANDARD (BAD) VISUALIZATION: Cumulative Returns Only
% This hides risk and misleads investors

fig1 = figure('Position', [100, 100, 1400, 600], 'Name', 'BAD: Returns-Only View');
sgtitle('❌ MISLEADING: Standard Cumulative Return Plot (Hides Risk)', 'FontSize', 14, 'Color', 'r');

subplot(1, 3, 1);
t = 1:T;
plot(t, w_good, 'LineWidth', 2.5);
xlabel('Days'); ylabel('Cumulative Wealth ($)');
title(sprintf('Good Model\nFinal: $%.2f, Sharpe: 0.60', w_good(end)));
grid on;

subplot(1, 3, 2);
plot(t, w_med, 'LineWidth', 2.5);
xlabel('Days'); ylabel('Cumulative Wealth ($)');
title(sprintf('Mediocre Model\nFinal: $%.2f, Sharpe: 0.20', w_med(end)));
grid on;

subplot(1, 3, 3);
plot(t, w_null, 'LineWidth', 2.5);
xlabel('Days'); ylabel('Cumulative Wealth ($)');
title(sprintf('Null (RW)\nFinal: $%.2f, Sharpe: ~0.00', w_null(end)));
grid on;

annotation('textbox', [0.05, 0.02, 0.9, 0.05], ...
    'String', 'PROBLEM: Two models with similar final wealth but very different MDD. Investor would pick wrong model.', ...
    'FontSize', 11, 'BackgroundColor', 'yellow', 'EdgeColor', 'red', 'LineWidth', 2);

%% 4. RIGOROUS (GOOD) VISUALIZATION: Drawdown-Centric

fig2 = figure('Position', [100, 750, 1400, 800], 'Name', 'GOOD: Drawdown-Centric View');
sgtitle('✓ RIGOROUS: Maximum Drawdown & Wealth Evolution (Risk-Centric)', 'FontSize', 14, 'Color', 'g');

% Plot 1: Wealth with MDD annotation
ax1 = subplot(3, 3, 1);
plot(t, w_good, 'b-', 'LineWidth', 2);
hold on;
[mdd_val_g, idx_g] = min(dd_good);
plot(idx_g, w_good(idx_g), 'ro', 'MarkerSize', 10, 'DisplayName', sprintf('MDD trough'));
yline(w_good(1), 'k--', 'Initial Capital');
ylabel('Wealth ($)');
title(sprintf('Good Model\nMDD: %.1f%%', mdd_good*100));
grid on; legend;

ax2 = subplot(3, 3, 2);
plot(t, w_med, 'LineWidth', 2);
hold on;
[mdd_val_m, idx_m] = min(dd_med);
plot(idx_m, w_med(idx_m), 'ro', 'MarkerSize', 10);
yline(w_med(1), 'k--');
ylabel('Wealth ($)');
title(sprintf('Mediocre Model\nMDD: %.1f%%', mdd_med*100));
grid on;

ax3 = subplot(3, 3, 3);
plot(t, w_null, 'LineWidth', 2);
hold on;
[mdd_val_n, idx_n] = min(dd_null);
plot(idx_n, w_null(idx_n), 'ro', 'MarkerSize', 10);
yline(w_null(1), 'k--');
ylabel('Wealth ($)');
title(sprintf('Null Model (RW)\nMDD: %.1f%%', mdd_null*100));
grid on;

% Plot 2: Drawdown Time Series (where investor psychological breaks happen)
ax4 = subplot(3, 3, 4);
fill(t, dd_good*100, 'b', 'FaceAlpha', 0.4, 'DisplayName', 'Drawdown');
hold on;
yline(-20, 'r--', 'Psychological Limit (-20%)', 'LineWidth', 2);
yline(-30, 'r-', 'Institutional Limit (-30%)', 'LineWidth', 2);
ylabel('Drawdown (%)');
ylim([-40, 2]);
grid on;
legend('Location', 'southwest');
title('Good Model: Drawdown Path');

ax5 = subplot(3, 3, 5);
fill(t, dd_med*100, 'r', 'FaceAlpha', 0.4);
hold on;
yline(-20, 'r--', 'Psychological Limit', 'LineWidth', 2);
yline(-30, 'r-', 'Institutional Limit', 'LineWidth', 2);
ylabel('Drawdown (%)');
ylim([-40, 2]);
grid on;
title('Mediocre Model: Drawdown Path');

ax6 = subplot(3, 3, 6);
fill(t, dd_null*100, 'k', 'FaceAlpha', 0.4);
hold on;
yline(-20, 'r--', 'Psychological Limit', 'LineWidth', 2);
yline(-30, 'r-', 'Institutional Limit', 'LineWidth', 2);
ylabel('Drawdown (%)');
ylim([-40, 2]);
grid on;
title('Null Model: Drawdown Path');

% Plot 3: Recovery Time (another critical metric)
ax7 = subplot(3, 3, 7);
cumsum_days_dd_good = zeros(T, 1);
for i = 1:T
    if dd_good(i) < dd_good(max(1, i-1))
        cumsum_days_dd_good(i) = cumsum_days_dd_good(max(1, i-1)) + 1;
    else
        cumsum_days_dd_good(i) = 0;
    end
end
plot(t, cumsum_days_dd_good, 'b', 'LineWidth', 1.5);
ylabel('Days in Drawdown');
title('Good Model: Recovery Time');
grid on;

ax8 = subplot(3, 3, 8);
cumsum_days_dd_med = zeros(T, 1);
for i = 1:T
    if dd_med(i) < dd_med(max(1, i-1))
        cumsum_days_dd_med(i) = cumsum_days_dd_med(max(1, i-1)) + 1;
    else
        cumsum_days_dd_med(i) = 0;
    end
end
plot(t, cumsum_days_dd_med, 'r', 'LineWidth', 1.5);
ylabel('Days in Drawdown');
title('Mediocre Model: Recovery Time');
grid on;

ax9 = subplot(3, 3, 9);
cumsum_days_dd_null = zeros(T, 1);
for i = 1:T
    if dd_null(i) < dd_null(max(1, i-1))
        cumsum_days_dd_null(i) = cumsum_days_dd_null(max(1, i-1)) + 1;
    else
        cumsum_days_dd_null(i) = 0;
    end
end
plot(t, cumsum_days_dd_null, 'k', 'LineWidth', 1.5);
ylabel('Days in Drawdown');
title('Null Model: Recovery Time');
grid on;

%% 5. RISK METRICS COMPARISON TABLE

fprintf('\n');
fprintf('='.repmat('=', 1, 80));
fprintf('\nRISK-CENTRIC PERFORMANCE COMPARISON\n');
fprintf('='.repmat('=', 1, 80));
fprintf('\n');

% Compute metrics
sharpe_good = mean(returns_good) / std(returns_good) * sqrt(252);
sharpe_med = mean(returns_mediocre) / std(returns_mediocre) * sqrt(252);
sharpe_null = mean(returns_null) / std(returns_null) * sqrt(252);

calmar_good = (mean(returns_good) * 252) / (-mdd_good);  % Return / MDD
calmar_med = (mean(returns_mediocre) * 252) / (-mdd_med);
calmar_null = (mean(returns_null) * 252) / (-mdd_null);

metrics_table = table(...
    {'Good'; 'Mediocre'; 'Null'}, ...
    [w_good(end); w_med(end); w_null(end)], ...
    [mdd_good*100; mdd_med*100; mdd_null*100], ...
    [sharpe_good; sharpe_med; sharpe_null], ...
    [calmar_good; calmar_med; calmar_null], ...
    'VariableNames', {'Model', 'Final_Wealth', 'MDD_%', 'Sharpe', 'Calmar_Ratio'});

disp(metrics_table);

fprintf('\n');
fprintf('Interpretation:\n');
fprintf('  Good Model:    Low MDD (good for psychological + capital requirements) + good Sharpe\n');
fprintf('  Mediocre Model: High MDD (investor would liquidate) despite similar final wealth\n');
fprintf('  Calmar Ratio = Annual Return / |MDD| (emphasizes drawdown control)\n');
fprintf('\nDECISION: Pick "Good Model" even if final wealth were equal to "Mediocre"\n');
fprintf('BECAUSE institutional risk limits are based on MDD, not absolute return.\n');

%% 6. PRAGMAS-SPECIFIC: How to show in Phase 4

fprintf('\n');
fprintf('='.repmat('=', 1, 80));
fprintf('\nAPPLYING TO PRAGMAS-SUITE PHASE 4\n');
fprintf('='.repmat('=', 1, 80));
fprintf('\n');

fprintf('In main_phase4_rigorous.m, subplot(2,2,4) should show:\n');
fprintf('  LEFT:  Drawdown time series with risk thresholds (-20%%, -30%%)\n');
fprintf('  RIGHT: Recovery time histogram (how long until return to peak?)\n');
fprintf('\nCode snippet:\n');
fprintf('  subplot(2,2,4);\n');
fprintf('  dd = (wealth - cummax(wealth)) ./ cummax(wealth);\n');
fprintf('  fill(1:length(dd), dd*100, ''b'', ''FaceAlpha'', 0.3);\n');
fprintf('  yline(-20, ''r--'', ''Psychological Limit'');\n');
fprintf('  yline(-30, ''r-'', ''Institutional Limit'');\n');
fprintf('  ylabel(''Drawdown (%%)'');\n');
fprintf('  title(sprintf(''MDD: %.1f%%%% (Institutional Threshold: <30%%)'', min(dd)*100));\n');
fprintf('\nThis shows RISK first, returns second (aligns with investor psychology).\n');
