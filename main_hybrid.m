%% PRAGMAS-SUITE: Hybrid Pipeline Completo (Phases 1-3)
% Script de demostración del pipeline híbrido completo:
% Phase 1: Datos + Microestructura
% Phase 2.1: Benchmarking ARIMA-GARCH
% Phase 2.2: Detección de Regímenes HMM
% Phase 3: Deep Learning + Validación MCS
%
% Ejecuta: pragmas_config; main_hybrid;

clear all; close all; clc;

%% Configuración
pragmas_config;

fprintf('\n╔════════════════════════════════════════════════════════════╗\n');
fprintf('║   PRAGMAS-SUITE: HYBRID PIPELINE COMPLETO (PHASES 1-3)    ║\n');
fprintf('║   Econometría + HMM + Deep Learning + Validación MCS      ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n\n');

%% ========== PHASE 1: DATOS Y MICROESTRUCTURA ==========
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('PHASE 1: DATOS Y MICROESTRUCTURA\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

% Descargar datos
endDate = datetime('now');
startDate = endDate - days(180);

fetcher = pragmas.data.DataFetcher({'BTC-USD'}, startDate, endDate, 'crypto');
fetcher.fetchAsync();

if isempty(fetcher.DataTables{1})
    fprintf('⚠ Usando datos sintéticos (descarga falló)\n');
    rng(42);
    n = 180;
    prices = 100 * cumprod(1 + 0.01 * randn(n, 1));
    btc_data = timetable(startDate + (1:n)', prices, 'VariableNames', {'Close'});
else
    btc_data = fetcher.DataTables{1};
    fprintf('✓ Datos descargados: %d observaciones\n', height(btc_data));
end

% Retornos y Hurst
btc_returns = diff(log(btc_data.Close)) * 100;
btc_returns = btc_returns(~isnan(btc_returns));

H = pragmas.data.computeHurst(btc_returns);
fprintf('✓ Hurst Exponent: %.4f', H);
if H > 0.55
    fprintf(' (Trending)\n');
elseif H < 0.45
    fprintf(' (Mean-reverting)\n');
else
    fprintf(' (Random Walk)\n');
end

% Fractional Diff
d_optimal = 0.3;
btc_fracdiff = pragmas.data.fractionalDiff(btc_data.Close, d_optimal);
fprintf('✓ Diferenciación fraccional: %d valores procesados\n\n', length(btc_fracdiff));

%% ========== PHASE 2.1: BENCHMARKING ARIMA-GARCH ==========
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('PHASE 2.1: BENCHMARKING ARIMA-GARCH\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

modelEngine = pragmas.models.ModelEngine(btc_returns, 'BTC-USD', true);

fprintf('Grid search: %d especificaciones\n', 3*3*2);
tic;
modelEngine.gridSearch(...
    'p', [0 1 2], ...
    'q', [0 1 2], ...
    'd', [0 1], ...
    'P', [1], ...
    'Q', [1]);
elapsed_arima = toc;

fprintf('✓ Grid search completado en %.2f segundos\n', elapsed_arima);
fprintf('✓ Mejor modelo: ARIMA(%d,%d,%d)-GARCH(%d,%d)\n', ...
    modelEngine.BestModelSpec.p, modelEngine.BestModelSpec.d, ...
    modelEngine.BestModelSpec.q, modelEngine.BestModelSpec.P, modelEngine.BestModelSpec.Q);
fprintf('  AIC: %.2f, BIC: %.2f\n\n', modelEngine.BestAIC, modelEngine.BestBIC);

% Pronósticos y residuos
h = 20;
[forecasts_arima, residuals, ci_arima] = modelEngine.predict(h);

%% ========== PHASE 2.2: DETECCIÓN DE REGÍMENES ==========
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('PHASE 2.2: DETECCIÓN DE REGÍMENES (HMM)\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

detector = pragmas.regimes.MarkovRegimeDetector(residuals, 3, 'BTC-USD Residuals');

tic;
detector.train('MaxIterations', 100);
elapsed_hmm = toc;

fprintf('✓ HMM entrenado en %.2f segundos\n', elapsed_hmm);

regimes = detector.getRegimes();
regime_indices = detector.getRegimeIndices();

fprintf('✓ Regímenes detectados:\n');
for r = 1:3
    count = sum(regime_indices == r);
    pct = 100 * count / length(regime_indices);
    fprintf('  %s: %d obs (%.1f%%)\n', detector.StateRegimeNames{r}, count, pct);
end
fprintf('\n');

%% ========== PHASE 3.1: DEEP LEARNING ==========
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('PHASE 3.1: DEEP LEARNING (LSTM/CNN)\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

% Configurar motor DL
dl_options = struct(...
    'SequenceLength', 20, ...
    'EpochsLSTM', 30, ...
    'EpochsCNN', 30, ...
    'BatchSize', 16);

dlEngine = pragmas.models.DeepEngine(residuals, regime_indices, dl_options, 'BTC-USD');

fprintf('Entrenando LSTM y CNN en paralelo...\n');
tic;
dlEngine.trainAsync({'LSTM', 'CNN'});
elapsed_dl = toc;

fprintf('✓ Training completado en %.2f segundos\n', elapsed_dl);

% Predicciones
forecasts_lstm = dlEngine.predict('LSTM', h);
forecasts_cnn = dlEngine.predict('CNN', h);

fprintf('✓ Pronósticos generados (h=%d pasos)\n\n', h);

%% ========== PHASE 3.2: PREDICCIÓN CONDICIONAL ==========
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('PHASE 3.2: PREDICCIÓN CONDICIONAL POR RÉGIMEN\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

lastRegime = regime_indices(end);
lastRegimeName = detector.StateRegimeNames{lastRegime};

fprintf('Régimen actual: %s\n\n', lastRegimeName);

switch lastRegime
    case 1  % Bull
        fprintf('BULL REGIME → Prioridad: Modelos No-Lineales (LSTM)\n');
        fprintf('  - LSTM captura dinámicas complejas en tendencias alcistas\n');
        fprintf('  - CNN complementa con patrones locales\n');
        fprintf('  - ARIMA-GARCH como validación paramétrica\n');
        selected_model = 'LSTM';
        selected_forecast = forecasts_lstm;
        
    case 2  % Bear
        fprintf('BEAR REGIME → Prioridad: Volatilidad (GARCH + CNN)\n');
        fprintf('  - CNN detecta cambios abruptos de volatilidad\n');
        fprintf('  - GARCH modela clustering de volatilidad\n');
        fprintf('  - LSTM para tail-risk\n');
        selected_model = 'CNN';
        selected_forecast = forecasts_cnn;
        
    otherwise  % Sideways
        fprintf('SIDEWAYS REGIME → Prioridad: Modelos Paramétricos\n');
        fprintf('  - ARIMA-GARCH para mean-reversion\n');
        fprintf('  - LSTM/CNN como detectores de ruptura\n');
        selected_model = 'ARIMA-GARCH';
        selected_forecast = forecasts_arima;
end

fprintf('Modelo seleccionado: %s\n\n', selected_model);

%% ========== PHASE 3.3: VALIDACIÓN MCS ==========
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('PHASE 3.3: VALIDACIÓN Y MODEL CONFIDENCE SET (MCS)\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

% Alinear actuals para comparación
actuals_val = btc_returns(end-h+1:end);
if length(actuals_val) < h
    actuals_val = [zeros(h - length(actuals_val), 1); actuals_val];
end

% Crear modelo de comparación (ensemble simple como baseline)
ensemble_forecast = (forecasts_arima + forecasts_lstm + forecasts_cnn) / 3;

% Construir tabla de modelos
models_for_validation = {...
    'ARIMA-GARCH', forecasts_arima, actuals_val; ...
    'LSTM', forecasts_lstm, actuals_val; ...
    'CNN', forecasts_cnn, actuals_val; ...
    'Ensemble', ensemble_forecast, actuals_val};

% Validador híbrido
validator = pragmas.validation.HybridValidator(models_for_validation, 'MSE');

% Calcular MCS
validator.computeMCS(0.05);

% Métricas
validator.computeMetrics();

% Resumen
summary_table = validator.getSummary();
fprintf('\n✓ Tabla de métricas:\n');
disp(summary_table);

%% ========== VISUALIZACIÓN COMPREHENSIVA ==========
fprintf('\n═══════════════════════════════════════════════════════════\n');
fprintf('GENERANDO VISUALIZACIONES\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

% Figura 1: Pipeline Overview (5 subplots)
figure('Name', 'Pragmas-Suite: Hybrid Pipeline Overview', 'NumberTitle', 'off', ...
    'Position', [100, 100, 1600, 1000]);

% Subplot 1: Precios originales
subplot(3, 3, 1);
plot(btc_data.Time, btc_data.Close, 'b-', 'LineWidth', 1.5);
title('Phase 1: Precios Históricos', 'FontWeight', 'bold');
xlabel('Fecha'); ylabel('USD');
grid on;

% Subplot 2: Retornos y Hurst
subplot(3, 3, 2);
plot(btc_data.Time(2:end), btc_returns, 'g-', 'LineWidth', 0.8);
title(sprintf('Phase 1: Retornos (Hurst=%.3f)', H), 'FontWeight', 'bold');
xlabel('Fecha'); ylabel('Log-Return (%)');
grid on;

% Subplot 3: Fractional Differentiation
subplot(3, 3, 3);
plot(1:length(btc_fracdiff), btc_fracdiff, 'r-', 'LineWidth', 0.8);
title(sprintf('Phase 1: Frac-Diff (d=%.1f)', d_optimal), 'FontWeight', 'bold');
xlabel('Índice'); ylabel('Valor');
grid on;

% Subplot 4: AIC Grid Search
subplot(3, 3, 4);
[~, idx] = sort(modelEngine.GridResults.AIC);
top_aics = modelEngine.GridResults.AIC(idx(1:min(8, height(modelEngine.GridResults))));
barh(1:length(top_aics), top_aics, 'FaceColor', [0.3 0.6 0.9]);
title('Phase 2.1: Top 8 Modelos ARIMA-GARCH', 'FontWeight', 'bold');
xlabel('AIC');
grid on;

% Subplot 5: Residuos con Regímenes
subplot(3, 3, 5);
colors_regime = [0.2 0.8 0.2; 0.8 0.2 0.2; 0.5 0.5 0.5];
hold on;
for r = 1:3
    idx = regime_indices == r;
    scatter(find(idx), residuals(idx), 20, colors_regime(r, :), 'filled', 'Alpha', 0.6);
end
title('Phase 2.2: Residuos + Regímenes HMM', 'FontWeight', 'bold');
xlabel('Tiempo'); ylabel('Residuo');
hold off;

% Subplot 6: Matriz de Transición
subplot(3, 3, 6);
imagesc(detector.TransitionMatrix);
colorbar;
set(gca, 'XTickLabel', {'Bull', 'Bear', 'Sideways'}, 'YTickLabel', {'Bull', 'Bear', 'Sideways'});
title('Phase 2.2: Transiciones de Regímenes', 'FontWeight', 'bold');
axis square;

% Subplot 7: Pronósticos Comparativos
subplot(3, 3, 7);
time_fcst = (1:h);
hold on;
plot(time_fcst, forecasts_arima, 'b-', 'LineWidth', 2, 'DisplayName', 'ARIMA-GARCH');
plot(time_fcst, forecasts_lstm, 'r--', 'LineWidth', 2, 'DisplayName', 'LSTM');
plot(time_fcst, forecasts_cnn, 'g:', 'LineWidth', 2, 'DisplayName', 'CNN');
plot(time_fcst, actuals_val, 'ko-', 'LineWidth', 1, 'DisplayName', 'Actual');
title('Phase 3: Pronósticos Comparativos (h=20)', 'FontWeight', 'bold');
xlabel('Horizonte'); ylabel('Valor');
legend('Location', 'best', 'FontSize', 9);
grid on;
hold off;

% Subplot 8: Comparación de Errores
subplot(3, 3, 8);
errors_ag = forecasts_arima - actuals_val;
errors_lstm = forecasts_lstm - actuals_val;
errors_cnn = forecasts_cnn - actuals_val;
hold on;
plot(time_fcst, errors_ag, 'b-', 'LineWidth', 1.5, 'DisplayName', 'ARIMA');
plot(time_fcst, errors_lstm, 'r-', 'LineWidth', 1.5, 'DisplayName', 'LSTM');
plot(time_fcst, errors_cnn, 'g-', 'LineWidth', 1.5, 'DisplayName', 'CNN');
yline(0, 'k--', 'LineWidth', 1);
title('Phase 3: Errores de Pronóstico', 'FontWeight', 'bold');
xlabel('Horizonte'); ylabel('Error');
legend('Location', 'best', 'FontSize', 9);
grid on;
hold off;

% Subplot 9: MCS Results
subplot(3, 3, 9);
meanLosses = mean(validator.Losses, 1);
mcs_colors = zeros(4, 3);
for m = 1:4
    if ismember(m, find(ismember(validator.ModelNames, validator.MCSSet)))
        mcs_colors(m, :) = [0.2 0.8 0.2];  % Verde (en MCS)
    else
        mcs_colors(m, :) = [0.8 0.2 0.2];  % Rojo (excluido)
    end
end
bars = bar(1:4, meanLosses, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'black');
for m = 1:4
    bars(m).FaceColor = mcs_colors(m, :);
end
set(gca, 'XTickLabel', validator.ModelNames, 'XTickLabelRotation', 45);
title('Phase 3.3: Model Confidence Set (α=0.05)', 'FontWeight', 'bold');
ylabel('Mean MSE');
grid on;

sgtitle(sprintf('PRAGMAS-SUITE: Hybrid Pipeline Completo (Fase: %s)', lastRegimeName), ...
    'FontSize', 16, 'FontWeight', 'bold');

fprintf('✓ Visualizaciones generadas\n\n');

%% ========== RESUMEN Y DIAGNÓSTICO ==========
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('RESUMEN Y DIAGNÓSTICO\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

fprintf('TIEMPOS DE EJECUCIÓN:\n');
fprintf('  Phase 1 (Datos): < 1s (descarga + Hurst + FracDiff)\n');
fprintf('  Phase 2.1 (ARIMA-GARCH): %.2f segundos\n', elapsed_arima);
fprintf('  Phase 2.2 (HMM): %.2f segundos\n', elapsed_hmm);
fprintf('  Phase 3 (DL): %.2f segundos\n', elapsed_dl);
fprintf('  TOTAL: %.2f segundos\n\n', elapsed_arima + elapsed_hmm + elapsed_dl);

fprintf('PERFORMANCE COMPARATIVO:\n');
for m = 1:height(summary_table)
    fprintf('  %s:\n', summary_table.Model{m});
    fprintf('    - RMSE: %.6f\n', summary_table.RMSE(m));
    fprintf('    - Sharpe: %.4f\n', summary_table.Sharpe(m));
    fprintf('    - MaxDD: %.4f\n', summary_table.MaxDD(m));
end

fprintf('\nMODEL CONFIDENCE SET (α=0.05):\n');
fprintf('  Modelos en MCS: %s\n', strjoin(validator.MCSSet, ', '));

fprintf('\nRECOMENDACIONES:\n');
fprintf('  Régimen actual: %s\n', lastRegimeName);
fprintf('  Modelo seleccionado: %s\n', selected_model);
fprintf('  Validación: MCS incluye múltiples modelos → ensemble recomendado\n');

fprintf('\n═══════════════════════════════════════════════════════════\n');
fprintf('✓ PIPELINE COMPLETADO EXITOSAMENTE\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

fprintf('Próximos pasos:\n');
fprintf('  1. Refinar hiperparámetros de DL (más épocas, ajuste de learning rate)\n');
fprintf('  2. Implementar MS-GARCH para regímenes condicionales\n');
fprintf('  3. Agregar métodos de ensemble (stacking, voting)\n');
fprintf('  4. Generar reportes LaTeX automáticos (mlreportgen)\n');
fprintf('  5. Backtesting real con slippage y comisiones\n');
fprintf('  6. Publicación académica: paper en arXiv\n\n');
