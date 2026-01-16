# PRAGMAS-SUITE: QUICKSTART GUIDE

**pragmas-suite** es un framework MATLAB completo para investigación en econometría dinámica e integración de Deep Learning con validación rigurosa.

## 🚀 Inicio Rápido (5 minutos)

### 1. Configuración Inicial
```matlab
% Abre MATLAB en la carpeta pragmas-suite
cd('pragmas-suite')
pragmas_config  % Carga configuración global

% Verifica integridad
validate_suite  % ✓ Debería ver "PRAGMAS-SUITE COMPLETAMENTE VALIDADA"
```

### 2. Ejecutar Demo Phase 1 (Datos)
```matlab
main  % Ejecuta demo Phase 1
```
**Salida esperada:**
- Datos de BTC-USD descargados
- Hurst Exponent calculado
- Series estacionarias generadas
- 3 gráficos de microestructura

### 3. Ejecutar Demo Phase 2 (Econometría + Regímenes)
```matlab
main_phase2  % Ejecuta demo Phase 2.1 + 2.2
```
**Salida esperada:**
- Grid search ARIMA-GARCH completado
- 12 subplots mostrando:
  - Precios históricos
  - Retornos y Hurst Exponent
  - Grid search AIC results
  - Residuos coloreados por régimen (Bull/Bear/Sideways)
  - Matriz de transición
  - Estadísticas por régimen

### 4. Ejecutar Demo Phase 3 (Deep Learning + MCS)
```matlab
main_hybrid  % Ejecuta PIPELINE COMPLETO: Phase 1-3
```
**Salida esperada:**
- LSTM y CNN entrenados en paralelo
- Predicciones comparativas (h=20 pasos)
- Model Confidence Set calculado a α=0.05
- Tabla con Sharpe, Sortino, MaxDD, Calmar
- 9 subplots mostrando pipeline híbrido completo

## 📊 Ejemplos de Uso

### Ejemplo 1: Descargar datos y calcular Hurst
```matlab
pragmas_config;

% Descargar datos
fetcher = pragmas.data.DataFetcher({'BTC-USD', 'ETH-USD'}, ...
    datetime('2024-01-01'), datetime('now'), 'crypto');
fetcher.fetchAsync();  % Descarga en paralelo

btc_data = fetcher.DataTables{1};
eth_data = fetcher.DataTables{2};

% Calcular Hurst Exponent
btc_returns = diff(log(btc_data.Close)) * 100;
H_btc = pragmas.data.computeHurst(btc_returns);

fprintf('Bitcoin Hurst: %.4f\n', H_btc);
% Si H > 0.5: Tendencia (Trending)
% Si H < 0.5: Reversión a media (Mean-reverting)
% Si H ≈ 0.5: Paseo aleatorio (Random Walk)
```

### Ejemplo 2: Entrenar ARIMA-GARCH y detectar regímenes
```matlab
pragmas_config;

% Simular retornos (o cargar datos reales)
rng(42);
returns = 100 * diff(log(100 * cumprod(1 + 0.01 * randn(100, 1))));

% Phase 2.1: Grid search ARIMA-GARCH
engine = pragmas.models.ModelEngine(returns, 'BTC-USD', true);
engine.gridSearch('p', [0 1 2], 'd', [0 1], 'q', [0 1]);

fprintf('Mejor modelo: ARIMA(%d,%d,%d)-GARCH(%d,%d)\n', ...
    engine.BestModelSpec.p, engine.BestModelSpec.d, ...
    engine.BestModelSpec.q, engine.BestModelSpec.P, ...
    engine.BestModelSpec.Q);

% Extraer residuos
residuals = engine.BestFit.residuals;

% Phase 2.2: Detectar regímenes con HMM
detector = pragmas.regimes.MarkovRegimeDetector(residuals, 3, 'BTC-USD');
detector.train('MaxIterations', 100);

regimes = detector.getRegimes();
fprintf('Regímenes: %s\n', strjoin(regimes, ', '));

% Visualizar
detector.plotRegimes();
detector.plotRegimeStatistics();
```

### Ejemplo 3: Entrenar LSTM/CNN y validar con MCS
```matlab
pragmas_config;

% Generar datos de demostración
rng(42);
returns = 100 * diff(log(100 * cumprod(1 + 0.01 * randn(150, 1))));
regimes = randi([1 3], length(returns), 1);

% Phase 3.1: Entrenar DL
dl_opts = struct('SequenceLength', 20, 'EpochsLSTM', 30, 'EpochsCNN', 30);
dlEngine = pragmas.models.DeepEngine(returns, regimes, dl_opts, 'BTC-USD');
dlEngine.trainAsync({'LSTM', 'CNN'});

% Predicciones
lstm_fcst = dlEngine.predict('LSTM', 20);
cnn_fcst = dlEngine.predict('CNN', 20);
arima_fcst = 0.001 * ones(20, 1);  % Placeholder

% Phase 3.2: Validar con MCS
actuals = returns(end-19:end);
models = {
    'ARIMA-GARCH', arima_fcst, actuals; ...
    'LSTM', lstm_fcst, actuals; ...
    'CNN', cnn_fcst, actuals};

validator = pragmas.validation.HybridValidator(models, 'MSE');
validator.computeMCS(0.05);  % α = 0.05
validator.computeMetrics();

% Ver resultados
summary = validator.getSummary();
disp(summary);

% Visualizar
validator.plotComparison();

fprintf('\nModelos en Model Confidence Set: %s\n', strjoin(validator.MCSSet, ', '));
```

## 🏗️ Estructura de Módulos

```
+pragmas/
├── +data/
│   ├── DataFetcher.m              # Descarga asincrónica
│   ├── computeHurst.m             # R/S Analysis
│   └── fractionalDiff.m           # Estacionariedad
├── +models/
│   ├── ModelEngine.m              # Grid search ARIMA-GARCH
│   └── DeepEngine.m               # LSTM/CNN paralelo
├── +regimes/
│   └── MarkovRegimeDetector.m     # HMM + Viterbi
└── +validation/
    └── HybridValidator.m          # MCS + Métricas financieras
```

## 📋 Matriz de Decisión: Qué Ejecutar

| Objetivo | Script | Duración | Salida |
|----------|--------|----------|--------|
| Verificar suite | `validate_suite` | < 1 min | ✓ Status de todos módulos |
| Data microstructure | `main` | 2-3 min | Hurst, Frac-Diff, plots |
| ARIMA-GARCH + HMM | `main_phase2` | 5-10 min | Grid search, regímenes, transiciones |
| **Pipeline completo** | `main_hybrid` | 15-20 min | **LSTM/CNN/MCS/Sharpe/etc.** |

## 🧪 Ejecutar Tests

```matlab
% Todos los tests
runtests('tests')

% Test específico
runtests('tests/TestDeepEngine.m')
runtests('tests/TestHybridValidator.m')
```

**Cobertura actual:**
- ✓ 102 unit tests en 5 módulos
- ✓ Validación de convergencia (ARIMA, HMM, DL)
- ✓ Edge cases (series corta, datos con NaNs)
- ✓ Robustez sin toolboxes (fallback implementations)

## 🔧 Configuración Avanzada

Edita `pragmas_config.m` para ajustar:

```matlab
% Tamaño de pool paralelo
global PRAGMAS_PARPOOL_SIZE;
PRAGMAS_PARPOOL_SIZE = 8;  % O el número de cores disponibles

% Opciones de Deep Learning
global PRAGMAS_DEEPENGINE_OPTIONS;
PRAGMAS_DEEPENGINE_OPTIONS.EpochsLSTM = 100;  % Más épocas = mejor fit
PRAGMAS_DEEPENGINE_OPTIONS.SequenceLength = 30;  % Ventana más larga
PRAGMAS_DEEPENGINE_OPTIONS.LearningRate = 0.0001;  % Más conservador

% Nivel de significancia MCS
global PRAGMAS_VALIDATOR_OPTIONS;
PRAGMAS_VALIDATOR_OPTIONS.MCSDelta = 0.01;  % Más riguroso (α=0.01)
```

## 🎯 Flujo Completo (Phase 1 → 3)

```
Raw Returns
    ↓
[Phase 1] Hurst + Fractional Diff
    ↓ (Estacionario con memoria)
[Phase 2.1] ARIMA-GARCH Grid Search
    ↓ (Residuos filtrados)
[Phase 2.2] HMM Regime Detection
    ↓ (Bull/Bear/Sideways)
[Phase 3.1] LSTM/CNN Training
    ↓ (Non-linear signal extraction)
[Phase 3.2] HybridValidator + MCS
    ↓ (Statistically rigorous comparison)
Final Forecast → Conditional Strategy
```

## ⚠️ Requisitos Mínimos

- MATLAB R2020b+
- Recomendado:
  - Econometrics Toolbox (Phase 2.1)
  - Deep Learning Toolbox (Phase 3.1)
  - Parallel Computing Toolbox (Async)
  
  **Fallbacks automáticos si no disponibles**

## 🐛 Troubleshooting

### Error: "Undefined function or variable 'pragmas'"
```matlab
% Solución: Ejecutar pragmas_config primero
pragmas_config
```

### Advertencia: "parpool not initialized"
```matlab
% Solución: Crear pool manualmente (opcional)
parpool(4);  % 4 workers
```

### Lentitud en trainAsync()
```matlab
% Solución: Reducir EpochsLSTM/EpochsCNN en pragmas_config
PRAGMAS_DEEPENGINE_OPTIONS.EpochsLSTM = 20;  % Default: 50
PRAGMAS_DEEPENGINE_OPTIONS.EpochsCNN = 20;
```

## 📚 Documentación Completa

Ver [README.md](README.md) para:
- Descripción detallada de cada módulo
- Metodologías académicas (referencias)
- Interpretación de resultados
- Métricas financieras

## 🚀 Próximos Pasos

1. Ejecutar `main_hybrid` y revisar resultados MCS
2. Modificar `SequenceLength` y `Epochs` para ajuste fino
3. Agregar más activos financieros (multiasset pipeline)
4. Implementar Ensemble voting para toma de decisiones
5. Publicar resultados académicos en arXiv

## 📧 Soporte

Para errores o sugerencias, refiere a los comentarios en los módulos `.m` o la documentación en README.md.

---

**Versión:** 0.3 (Phase 3 Completa)  
**Última actualización:** Enero 2026
