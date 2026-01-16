%% PRAGMAS-SUITE: Phase 2 Demo - Benchmarking Paramétrico
% Script de demostración del módulo ModelEngine.
% Integra descarga de datos (Phase 1) con búsqueda automática ARIMA-GARCH (Phase 2).
%
% Ejecuta: pragmas_config; main_phase2;

clear all; close all; clc;

%% 1. Cargar configuración
pragmas_config;

%% 2. Descargar datos (Phase 1: DataFetcher)
fprintf('\n========== PHASE 2: BENCHMARKING PARAMÉTRICO ==========\n');
fprintf('Paso 1: Descargando datos desde CoinGecko...\n');

endDate = datetime('now');
startDate = endDate - days(180);  % 6 meses

fetcher = pragmas.data.DataFetcher({'BTC-USD'}, startDate, endDate, 'crypto');
fetcher.fetchAsync();

if isempty(fetcher.DataTables{1})
    warning('No se pudo descargar BTC-USD. Usando datos sintéticos para demostración.');
    % Generar datos sintéticos para testing
    rng(42);
    n = 180;
    prices = 100 * cumprod(1 + 0.01 * randn(n, 1));
    btc_data = timetable(startDate + (1:n)', prices, 'VariableNames', {'Close'});
else
    btc_data = fetcher.DataTables{1};
end

fprintf('Datos descargados: %d observaciones\n', height(btc_data));

%% 3. Calcular retornos y métricas (Phase 1)
fprintf('\nPaso 2: Calculando métricas de microestructura...\n');

% Retornos logarítmicos
btc_returns = diff(log(btc_data.Close)) * 100;  % En porcentaje
btc_returns = btc_returns(~isnan(btc_returns));

% Hurst Exponent
H = pragmas.data.computeHurst(btc_returns);
fprintf('  Hurst Exponent: %.4f ', H);
if H > 0.55
    fprintf('(Trending)\n');
elseif H < 0.45
    fprintf('(Mean-reverting)\n');
else
    fprintf('(Random Walk)\n');
end

% Diferenciación fraccional
d_optimal = 0.3;  % En Phase 3 ajustar con ADF tests
btc_fracdiff = pragmas.data.fractionalDiff(btc_data.Close, d_optimal);
fprintf('  Diferenciación fraccional (d=%.1f): %d valores\n', d_optimal, length(btc_fracdiff));

%% 4. ARIMA-GARCH Grid Search (Phase 2)
fprintf('\nPaso 3: Grid Search ARIMA-GARCH en paralelo...\n');

% Crear motor econométrico
modelEngine = pragmas.models.ModelEngine(btc_returns, 'BTC-USD', true);

% Definir grid de búsqueda
% Recomendación: mantener pequeño para rapidez (expandir en análisis real)
fprintf('\nDefinición del grid de búsqueda:\n');
fprintf('  p (orden AR): [0, 1, 2]\n');
fprintf('  d (diferenciación): [0, 1]\n');
fprintf('  q (orden MA): [0, 1, 2]\n');
fprintf('  P (GARCH AR): [1]\n');
fprintf('  Q (GARCH MA): [1]\n');
fprintf('Total de especificaciones a evaluar: 3 × 2 × 3 × 1 × 1 = 18\n\n');

% Ejecutar grid search
tic;
modelEngine.gridSearch(...
    'p', [0 1 2], ...
    'q', [0 1 2], ...
    'd', [0 1], ...
    'P', [1], ...
    'Q', [1]);
elapsed = toc;

fprintf('Grid search completado en %.2f segundos\n\n', elapsed);

%% 5. Mostrar resultados
modelEngine.disp();

%% 6. Extraer estadísticas de convergencia
fprintf('Estadísticas de convergencia:\n');
validSpecs = ~isinf(modelEngine.GridResults.AIC);
fprintf('  Especificaciones convergidas: %d / %d\n', sum(validSpecs), height(modelEngine.GridResults));

if sum(validSpecs) > 0
    fprintf('  Mejor AIC: %.2f\n', min(modelEngine.GridResults.AIC(validSpecs)));
    fprintf('  Peor AIC: %.2f\n', max(modelEngine.GridResults.AIC(validSpecs)));
    fprintf('  Rango AIC: %.2f\n', max(modelEngine.GridResults.AIC(validSpecs)) - min(modelEngine.GridResults.AIC(validSpecs)));
end

%% 7. Pronósticos del modelo óptimo
fprintf('\nPaso 4: Generando pronósticos 20 pasos adelante...\n');

h = 20;  % Horizonte de pronóstico
[forecasts, residuals, ci] = modelEngine.predict(h, 'confidenceLevel', 0.95);

fprintf('Pronóstico medio: %.4f%%\n', mean(forecasts));
fprintf('Desv. estándar pronósticos: %.4f%%\n', std(forecasts));

%% 8. Visualización completa
fprintf('\nPaso 5: Generando gráficos...\n');

figure('Name', 'Pragmas-Suite Phase 2: Benchmarking Paramétrico', 'NumberTitle', 'off', ...
    'Position', [100, 100, 1400, 900]);

% Subplot 1: Precios y retornos
subplot(3, 3, 1);
plot(btc_data.Time, btc_data.Close, 'b-', 'LineWidth', 1.5);
title('BTC-USD: Serie de Precios', 'FontWeight', 'bold');
xlabel('Fecha'); ylabel('USD');
grid on;

subplot(3, 3, 2);
plot(btc_data.Time(2:end), btc_returns, 'g-', 'LineWidth', 0.8);
title(sprintf('Retornos Log (Hurst=%.4f)', H), 'FontWeight', 'bold');
xlabel('Fecha'); ylabel('Retorno (%)');
grid on;

subplot(3, 3, 3);
plot(1:length(btc_fracdiff), btc_fracdiff, 'r-', 'LineWidth', 0.8);
title(sprintf('Diferenciación Fraccional (d=%.1f)', d_optimal), 'FontWeight', 'bold');
xlabel('Índice'); ylabel('Valor');
grid on;

% Subplot 2: Distribución de AIC
subplot(3, 3, 4);
aic_valid = modelEngine.GridResults.AIC(~isinf(modelEngine.GridResults.AIC));
histogram(aic_valid, 'FaceColor', [0.2, 0.5, 0.8], 'EdgeColor', 'black');
xline(modelEngine.BestAIC, 'r--', 'LineWidth', 2, 'Label', 'Mejor AIC');
title('Distribución de AIC (Grid Search)', 'FontWeight', 'bold');
xlabel('AIC'); ylabel('Frecuencia');
grid on;

% Subplot 3: Top modelos
subplot(3, 3, 5);
[~, idx] = sort(modelEngine.GridResults.AIC);
top_n = min(10, height(modelEngine.GridResults));
top_aics = modelEngine.GridResults.AIC(idx(1:top_n));
top_labels = cell(top_n, 1);
for i = 1:top_n
    row = modelEngine.GridResults(idx(i), :);
    top_labels{i} = sprintf('ARIMA(%d,%d,%d)', row.p(1), row.d(1), row.q(1));
end
barh(1:top_n, top_aics, 'FaceColor', [0.3, 0.6, 0.9]);
set(gca, 'YTickLabel', flip(top_labels));
title('Top 10 Modelos por AIC', 'FontWeight', 'bold');
xlabel('AIC');
grid on;

% Subplot 4: Residuos del modelo
subplot(3, 3, 6);
if length(residuals) > 0
    plot(1:min(500, length(residuals)), residuals(1:min(500, length(residuals))), 'k-', 'LineWidth', 0.8);
    title('Residuos del Modelo Óptimo', 'FontWeight', 'bold');
    xlabel('Tiempo'); ylabel('Residuo');
    grid on;
    
    % ACF de residuos
    subplot(3, 3, 7);
    residuals_clean = residuals(~isnan(residuals));
    if length(residuals_clean) > 10
        [acf_vals, lags] = autocorr(residuals_clean, 20);
        stem(lags, acf_vals, 'filled', 'Color', [0.2, 0.6, 0.3]);
        yline(0, 'k-', 'LineWidth', 0.5);
        yline([1.96/sqrt(length(residuals_clean)), -1.96/sqrt(length(residuals_clean))], ...
            'k--', 'LineWidth', 0.5);
        title('ACF de Residuos', 'FontWeight', 'bold');
        xlabel('Lag'); ylabel('ACF');
        grid on;
    end
else
    text(0.5, 0.5, 'No hay residuos disponibles', 'HorizontalAlignment', 'center');
end

% Subplot 5: Pronósticos
subplot(3, 3, 8);
time_forecast = btc_data.Time(end) + (1:h)';
plot(btc_data.Time, btc_returns, 'b-', 'LineWidth', 1, 'DisplayName', 'Retornos históricos');
hold on;
plot(time_forecast, forecasts, 'r-', 'LineWidth', 2, 'DisplayName', 'Pronóstico');
if ~isempty(ci)
    fill([time_forecast; flip(time_forecast)], ...
        [ci(1, :)'; flip(ci(2, :)')], ...
        'red', 'FaceAlpha', 0.2, 'EdgeColor', 'none', 'DisplayName', 'IC 95%');
end
title('Pronóstico h=20 Pasos', 'FontWeight', 'bold');
xlabel('Fecha'); ylabel('Retorno (%)');
legend('Location', 'best');
grid on;
hold off;

% Subplot 6: Matriz de correlación (p, d, q)
subplot(3, 3, 9);
corr_matrix = zeros(3, 3);
for i = 1:3
    for j = 1:3
        p_val = i - 1;
        d_val = j - 1;
        mask = (modelEngine.GridResults.p == p_val) & (modelEngine.GridResults.d == d_val);
        if sum(mask) > 0
            corr_matrix(i, j) = min(modelEngine.GridResults.AIC(mask));
        else
            corr_matrix(i, j) = NaN;
        end
    end
end
imagesc(corr_matrix);
colorbar;
set(gca, 'XTickLabel', {'d=0', 'd=1'}, 'YTickLabel', {'p=0', 'p=1', 'p=2'});
title('AIC por (p, d)', 'FontWeight', 'bold');
axis square;

sgtitle('pragmas-suite Phase 2: Benchmarking ARIMA-GARCH', 'FontSize', 16, 'FontWeight', 'bold');

%% 9. Tabla de resultados detallada
fprintf('\n========== RESULTADOS DETALLADOS ==========\n');
fprintf('Grid Search Results (ordenados por AIC):\n');
[~, sortIdx] = sort(modelEngine.GridResults.AIC);
topResults = modelEngine.GridResults(sortIdx(1:min(10, height(modelEngine.GridResults))), :);
disp(topResults(:, {'p', 'd', 'q', 'P', 'Q', 'AIC', 'BIC'}));

%% 10. PHASE 2.2: Detección de Regímenes (HMM)
fprintf('\n========== PHASE 2.2: DETECCIÓN DE REGÍMENES ==========\n');
fprintf('Paso 6: Entrenando HMM en residuos de ARIMA-GARCH...\n');

% Crear detector de regímenes
detector = pragmas.regimes.MarkovRegimeDetector(residuals, 3, 'BTC-USD Residuals');

% Entrenar HMM (EM automático)
tic;
detector.train('MaxIterations', 100);
elapsed_hmm = toc;

fprintf('HMM entrenado en %.2f segundos\n', elapsed_hmm);

% Obtener regímenes decodificados
regimes = detector.getRegimes();
regime_indices = detector.getRegimeIndices();

% Mostrar información del HMM
detector.disp();

%% 11. Análisis de Regímenes
fprintf('Paso 7: Analizando regímenes detectados...\n');

% Estadísticas por régimen
regime_names = {'Bull', 'Bear', 'Sideways'};
fprintf('\nEstadísticas de retornos por régimen:\n');
for r = 1:3
    idx = regime_indices == r;
    if sum(idx) > 0
        mean_ret = mean(btc_returns(idx));
        std_ret = std(btc_returns(idx));
        count = sum(idx);
        pct = 100 * count / length(regime_indices);
        fprintf('  %s: Media=%.4f%%, Std=%.4f%%, Obs=%d (%.1f%%)\n', ...
            regime_names{r}, mean_ret, std_ret, count, pct);
    end
end

%% 12. Visualización Extendida con Regímenes
fprintf('\nPaso 8: Generando visualizaciones con regímenes...\n');

figure('Name', 'Pragmas-Suite Phase 2.2: Hybrid Pipeline', 'NumberTitle', 'off', ...
    'Position', [100, 100, 1600, 1000]);

% Subplot 1: Precios originales con regímenes
subplot(3, 4, 1);
hold on;
colors_regime = [0.2 0.8 0.2; 0.8 0.2 0.2; 0.5 0.5 0.5];  % Green Bull, Red Bear, Gray Sideways
for r = 1:3
    idx = regime_indices == r;
    plot(btc_data.Time(idx), btc_data.Close(idx), '.', 'Color', colors_regime(r, :), ...
        'MarkerSize', 5, 'DisplayName', regime_names{r});
end
title('Precios con Regímenes (HMM)', 'FontWeight', 'bold');
xlabel('Fecha'); ylabel('USD');
legend('Location', 'best', 'FontSize', 8);
grid on;
hold off;

% Subplot 2: Retornos y regímenes
subplot(3, 4, 2);
hold on;
for r = 1:3
    idx = regime_indices == r;
    if any(idx)
        % Alinear índices (retornos tienen una obs menos)
        idx_ret = idx(2:end);
        if length(idx_ret) == length(btc_returns)
            scatter(1:length(btc_returns), btc_returns(idx_ret), 20, colors_regime(r, :), 'filled', ...
                'DisplayName', regime_names{r}, 'Alpha', 0.6);
        end
    end
end
title('Retornos con Regímenes', 'FontWeight', 'bold');
xlabel('Tiempo'); ylabel('Retorno (%)');
legend('Location', 'best', 'FontSize', 8);
grid on;
hold off;

% Subplot 3: Residuos ARIMA-GARCH con regímenes
subplot(3, 4, 3);
hold on;
for r = 1:3
    idx = regime_indices == r;
    scatter(find(idx), residuals(idx), 20, colors_regime(r, :), 'filled', ...
        'DisplayName', regime_names{r}, 'Alpha', 0.6);
end
title('Residuos ARIMA-GARCH con Regímenes', 'FontWeight', 'bold');
xlabel('Tiempo'); ylabel('Residuo');
legend('Location', 'best', 'FontSize', 8);
grid on;
hold off;

% Subplot 4: Distribución de duraciones de regímenes
subplot(3, 4, 4);
durations_per_regime = cell(3, 1);
for r = 1:3
    idx = regime_indices == r;
    changes = [true; diff(idx) ~= 0; true];
    boundaries = find(changes);
    durs = diff(boundaries) - 1;
    durations_per_regime{r} = durs(durs > 0);
end
hold on;
for r = 1:3
    if ~isempty(durations_per_regime{r})
        histogram(durations_per_regime{r}, 'FaceColor', colors_regime(r, :), ...
            'DisplayName', regime_names{r}, 'EdgeColor', 'black', 'FaceAlpha', 0.6);
    end
end
title('Duración de Regímenes', 'FontWeight', 'bold');
xlabel('Duración (obs)'); ylabel('Frecuencia');
legend('Location', 'best', 'FontSize', 8);
grid on;
hold off;

% Subplot 5: Matriz de transición (heatmap)
subplot(3, 4, 5);
imagesc(detector.TransitionMatrix);
colorbar;
set(gca, 'XTickLabel', regime_names, 'YTickLabel', regime_names);
title('Matriz de Transición (HMM)', 'FontWeight', 'bold');
for i = 1:3
    for j = 1:3
        text(j, i, sprintf('%.2f', detector.TransitionMatrix(i, j)), ...
            'HorizontalAlignment', 'center', 'Color', 'white', 'FontSize', 10);
    end
end
axis square;

% Subplot 6: Medias y varianzas por régimen
subplot(3, 4, 6);
bar(1:3, detector.StateMeans, 'FaceColor', [0.3 0.6 0.9], 'EdgeColor', 'black');
hold on;
errorbar(1:3, detector.StateMeans, sqrt(detector.StateVars), 'r.', 'LineWidth', 2);
set(gca, 'XTickLabel', regime_names);
title('Parámetros de Emisión (μ, σ²)', 'FontWeight', 'bold');
ylabel('Media (Retornos)');
grid on;
hold off;

% Subplot 7: ACF de residuos (sin régimen específico)
subplot(3, 4, 7);
residuals_clean = residuals(~isnan(residuals));
if length(residuals_clean) > 20
    [acf_vals, lags] = autocorr(residuals_clean, 20);
    stem(lags, acf_vals, 'filled', 'Color', [0.2 0.6 0.3]);
    yline(0, 'k-', 'LineWidth', 0.5);
    yline([1.96/sqrt(length(residuals_clean)), -1.96/sqrt(length(residuals_clean))], ...
        'k--', 'LineWidth', 0.5);
    title('ACF de Residuos', 'FontWeight', 'bold');
    xlabel('Lag'); ylabel('ACF');
    grid on;
end

% Subplot 8: Log-likelihood o probabilidades forward
subplot(3, 4, 8);
[alpha, logL] = detector.forwardAlgorithm(detector.StateMeans, detector.StateVars, detector.TransitionMatrix);
plot(sum(log(alpha + eps), 2), 'b-', 'LineWidth', 1.5);
title('Log-Likelihood Acumulado (Forward)', 'FontWeight', 'bold');
xlabel('Tiempo'); ylabel('Log-L');
grid on;

% Subplot 9: Pronósticos vs Realizados
subplot(3, 4, 9);
time_forecast = btc_data.Time(end) + (1:h)';
plot(btc_data.Time(max(1, end-50):end), btc_returns(max(1, end-50):end), ...
    'b-', 'LineWidth', 1, 'DisplayName', 'Histórico');
hold on;
plot(time_forecast, forecasts, 'r-', 'LineWidth', 2, 'DisplayName', 'Pronóstico');
if ~isempty(ci)
    fill([time_forecast; flip(time_forecast)], ...
        [ci(1, :)'; flip(ci(2, :)')], ...
        'red', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
end
title('Pronóstico con Regímenes (h=20)', 'FontWeight', 'bold');
xlabel('Fecha'); ylabel('Retorno (%)');
legend('Location', 'best', 'FontSize', 8);
grid on;
hold off;

% Subplot 10: Cambios de régimen en tiempo
subplot(3, 4, 10);
regime_colors = colors_regime(regime_indices, :);
scatter(1:length(regime_indices), ones(length(regime_indices), 1), ...
    10, regime_colors, 'filled', 'DisplayName', 'Regime Path');
set(gca, 'YLim', [0.5, 1.5], 'YTick', 1);
set(gca, 'YTickLabel', '');
title('Trayectoria de Regímenes', 'FontWeight', 'bold');
xlabel('Tiempo');
grid on;

% Subplot 11: Distribución de retornos en Bull vs Bear
subplot(3, 4, 11);
bull_rets = btc_returns(regime_indices(2:end) == 1);
bear_rets = btc_returns(regime_indices(2:end) == 2);
sideways_rets = btc_returns(regime_indices(2:end) == 3);
hold on;
if ~isempty(bull_rets)
    histogram(bull_rets, 'FaceColor', colors_regime(1, :), 'DisplayName', 'Bull', ...
        'EdgeColor', 'black', 'FaceAlpha', 0.6);
end
if ~isempty(bear_rets)
    histogram(bear_rets, 'FaceColor', colors_regime(2, :), 'DisplayName', 'Bear', ...
        'EdgeColor', 'black', 'FaceAlpha', 0.6);
end
if ~isempty(sideways_rets)
    histogram(sideways_rets, 'FaceColor', colors_regime(3, :), 'DisplayName', 'Sideways', ...
        'EdgeColor', 'black', 'FaceAlpha', 0.6);
end
title('Distribución de Retornos por Régimen', 'FontWeight', 'bold');
xlabel('Retorno (%)'); ylabel('Frecuencia');
legend('Location', 'best', 'FontSize', 8);
grid on;
hold off;

% Subplot 12: Comparación AIC/BIC con Régimen Dominante
subplot(3, 4, 12);
[aics_sorted, idx_sorted] = sort(modelEngine.GridResults.AIC);
regimen_dominante = regime_indices(100:min(200, end));  % Muestra del medio
mode_regime = mode(regimen_dominante);
bar(1:min(5, length(aics_sorted)), aics_sorted(1:min(5, length(aics_sorted))), ...
    'FaceColor', colors_regime(mode_regime, :), 'EdgeColor', 'black');
title(sprintf('Top 5 AIC (Régimen Dominante: %s)', regime_names{mode_regime}), 'FontWeight', 'bold');
xlabel('Ranking'); ylabel('AIC');
grid on;

sgtitle('pragmas-suite Phase 2.2: Hybrid Pipeline (ARIMA-GARCH + HMM)', ...
    'FontSize', 16, 'FontWeight', 'bold');

%% 13. Análisis Condicional (Hybrid Pipeline)
fprintf('\nPaso 9: Análisis condicional basado en regímenes...\n');

fprintf('\nHybrid Pipeline Insights:\n');
fprintf('─────────────────────────────────────────────────────────────\n');

% Persistencia por régimen
fprintf('\nPersistencia de Regímenes (Probabilidad de permanecer):\n');
for r = 1:3
    persistencia = detector.TransitionMatrix(r, r);
    fprintf('  %s: %.1f%% (media esperada de duración: %.0f obs)\n', ...
        regime_names{r}, 100*persistencia, 1/(1-persistencia));
end

% Probabilidad de cambio de régimen
fprintf('\nTransiciones más probables entre regímenes:\n');
for i = 1:3
    for j = 1:3
        if i ~= j && detector.TransitionMatrix(i, j) > 0.05
            fprintf('  %s → %s: %.1f%%\n', regime_names{i}, regime_names{j}, ...
                100*detector.TransitionMatrix(i, j));
        end
    end
end

% Predicciones condicionales
fprintf('\nImplicaciones para pronóstico:\n');
last_regime = regime_indices(end);
fprintf('  Régimen actual (últimas obs): %s\n', regime_names{last_regime});
fprintf('  Modelos recomendados:\n');
if last_regime == 1  % Bull
    fprintf('    - Prioridad: Modelos no-lineales (LSTM/CNN) detectan oportunidades\n');
    fprintf('    - Suplemento: ARIMA-GARCH para validación paramétrica\n');
elseif last_regime == 2  % Bear
    fprintf('    - Prioridad: Hedging; modelos de tail-risk (GARCH)\n');
    fprintf('    - Suplemento: Mean-reversion strategies\n');
else  % Sideways
    fprintf('    - Prioridad: Modelos paramétricos (ARIMA-GARCH)\n');
    fprintf('    - Suplemento: Range-bound trading con DL para señales débiles\n');
end

%% 14. Resumen y próximos pasos
fprintf('\n========== RESUMEN PHASES 1-2.2 ==========\n');
fprintf('✓ Phase 1 (Datos): Descarga asincrónica + Hurst + Fractional Diff\n');
fprintf('✓ Phase 2.1 (Benchmarking): Grid search ARIMA-GARCH en paralelo\n');
fprintf('✓ Phase 2.2 (Regímenes): HMM Bull/Bear/Sideways + análisis condicional\n');
fprintf('✓ Hybrid Pipeline integrado: Datos → Paramétricos → Regímenes\n');
fprintf('\nPróximos pasos (Phase 3):\n');
fprintf('1. Entrenamiento de LSTM/CNN en residuos ARIMA-GARCH por régimen\n');
fprintf('2. Model Confidence Set (MCS) para comparación rigurosa de predictores\n');
fprintf('3. Validación asincrónica cruzada\n');
fprintf('4. Reportes automáticos en LaTeX/PDF\n');

fprintf('\n========== Fin de main_phase2.m (actualizado a Phase 2.2) ==========\n\n');
