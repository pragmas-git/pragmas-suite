%% PRAGMAS-SUITE: Main Pipeline - Phase 1 Demo
% Script de prueba y demostración del módulo de datos y microestructura.
% Ejecuta: pragmas_config; main;

clear all; close all; clc;

%% 1. Cargar configuración global
pragmas_config;

%% 2. EJEMPLO A: Descargar datos de criptomonedas (CoinGecko - gratuito)
fprintf('\n=== Descargando datos de criptomonedas (CoinGecko) ===\n');

% Definir rango temporal (ejemplo: últimos 90 días)
endDate = datetime('now');
startDate = endDate - days(90);

% Crear fetcher para BTC y ETH
fetcher_crypto = pragmas.data.DataFetcher({'BTC-USD', 'ETH-USD'}, startDate, endDate, 'crypto');

% Descargar asincronamente
fprintf('Descargando BTC-USD y ETH-USD en paralelo...\n');
tic;
fetcher_crypto.fetchAsync();
elapsed = toc;
fprintf('Descarga completada en %.2f segundos.\n\n', elapsed);

% Mostrar datos
if ~isempty(fetcher_crypto.DataTables{1})
    btc_data = fetcher_crypto.DataTables{1};
    eth_data = fetcher_crypto.DataTables{2};
    
    fprintf('BTC-USD: %d observaciones\n', height(btc_data));
    fprintf('ETH-USD: %d observaciones\n', height(eth_data));
    
    %% 3. Calcular métricas de microestructura
    fprintf('\n=== Calculando Hurst Exponent (R/S Analysis) ===\n');
    
    % Retornos logarítmicos
    btc_returns = diff(log(btc_data.Close));
    eth_returns = diff(log(eth_data.Close));
    
    % Hurst exponent
    H_btc = pragmas.data.computeHurst(btc_returns);
    H_eth = pragmas.data.computeHurst(eth_returns);
    
    fprintf('BTC-USD Hurst: %.4f ', H_btc);
    if H_btc > 0.55
        fprintf('(Trending/Persistente)\n');
    elseif H_btc < 0.45
        fprintf('(Mean-reverting/Anti-persistente)\n');
    else
        fprintf('(Random Walk)\n');
    end
    
    fprintf('ETH-USD Hurst: %.4f ', H_eth);
    if H_eth > 0.55
        fprintf('(Trending/Persistente)\n');
    elseif H_eth < 0.45
        fprintf('(Mean-reverting/Anti-persistente)\n');
    else
        fprintf('(Random Walk)\n');
    end
    
    %% 4. Aplicar Fractional Differentiation
    fprintf('\n=== Aplicando Diferenciación Fraccional (d=0.3) ===\n');
    
    d = 0.3;  % Orden fraccional (estima óptimo con ADF tests en Phase 2)
    
    btc_fracdiff = pragmas.data.fractionalDiff(btc_data.Close, d);
    eth_fracdiff = pragmas.data.fractionalDiff(eth_data.Close, d);
    
    fprintf('BTC fraccional-diferenciado: %d valores (truncados iniciales %d)\n', ...
        length(btc_fracdiff), height(btc_data) - length(btc_fracdiff));
    fprintf('ETH fraccional-diferenciado: %d valores (truncados iniciales %d)\n', ...
        length(eth_fracdiff), height(eth_data) - length(eth_fracdiff));
    
    %% 5. Visualización
    fprintf('\n=== Generando gráficos ===\n');
    
    figure('Name', 'Pragmas-Suite Phase 1: Microestructura', 'NumberTitle', 'off');
    
    % Subplot 1: Series de precios
    subplot(3, 2, 1);
    plot(btc_data.Time, btc_data.Close, 'b-', 'LineWidth', 1);
    title('BTC-USD: Precio');
    xlabel('Fecha'); ylabel('USD');
    grid on;
    
    subplot(3, 2, 2);
    plot(eth_data.Time, eth_data.Close, 'r-', 'LineWidth', 1);
    title('ETH-USD: Precio');
    xlabel('Fecha'); ylabel('USD');
    grid on;
    
    % Subplot 2: Retornos logarítmicos
    subplot(3, 2, 3);
    plot(btc_data.Time(2:end), btc_returns, 'b-', 'LineWidth', 0.8);
    title(sprintf('BTC Retornos Log (Hurst=%.4f)', H_btc));
    xlabel('Fecha'); ylabel('Log-Return');
    grid on;
    
    subplot(3, 2, 4);
    plot(eth_data.Time(2:end), eth_returns, 'r-', 'LineWidth', 0.8);
    title(sprintf('ETH Retornos Log (Hurst=%.4f)', H_eth));
    xlabel('Fecha'); ylabel('Log-Return');
    grid on;
    
    % Subplot 3: Fractional Differentiation
    subplot(3, 2, 5);
    plot(1:length(btc_fracdiff), btc_fracdiff, 'b-', 'LineWidth', 0.8);
    title(sprintf('BTC: Diferenciación Fraccional (d=%.2f)', d));
    xlabel('Índice'); ylabel('Valor');
    grid on;
    
    subplot(3, 2, 6);
    plot(1:length(eth_fracdiff), eth_fracdiff, 'r-', 'LineWidth', 0.8);
    title(sprintf('ETH: Diferenciación Fraccional (d=%.2f)', d));
    xlabel('Índice'); ylabel('Valor');
    grid on;
    
    sgtitle('pragmas-suite Phase 1: Microestructura de Mercado', 'FontSize', 14, 'FontWeight', 'bold');
    
    %% 6. Estadísticas descriptivas
    fprintf('\n=== Estadísticas Descriptivas ===\n');
    fprintf('\nBTC-USD Retornos:\n');
    fprintf('  Media: %.6f\n', mean(btc_returns));
    fprintf('  Std Dev: %.6f\n', std(btc_returns));
    fprintf('  Min: %.6f, Max: %.6f\n', min(btc_returns), max(btc_returns));
    fprintf('  Hurst: %.4f\n', H_btc);
    
    fprintf('\nETH-USD Retornos:\n');
    fprintf('  Media: %.6f\n', mean(eth_returns));
    fprintf('  Std Dev: %.6f\n', std(eth_returns));
    fprintf('  Min: %.6f, Max: %.6f\n', min(eth_returns), max(eth_returns));
    fprintf('  Hurst: %.4f\n', H_eth);
    
    %% 7. Resumen y próximos pasos
    fprintf('\n=== Resumen ===\n');
    fprintf('✓ Descarga asincrónica completada (parfeval)\n');
    fprintf('✓ Hurst Exponent calculado (R/S Analysis)\n');
    fprintf('✓ Diferenciación Fraccional aplicada (estacionariedad preservando memoria)\n');
    fprintf('\nPróximos pasos (Phase 2):\n');
    fprintf('  1. Ajuste automático de ARIMA-GARCH en series fraccional-diferenciadas\n');
    fprintf('  2. Detección de regímenes (HMM: Bull/Bear/Sideways)\n');
    fprintf('  3. Entrenamiento asincrónico de LSTM/CNN\n');
    fprintf('  4. Validación con Model Confidence Set (MCS)\n');
    
else
    fprintf('⚠ Error: No se descargaron datos. Verifica conexión a internet y APIs.\n');
end

fprintf('\n=== Fin de main.m ===\n\n');
