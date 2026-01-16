```
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║     ██████╗ ██████╗  █████╗  ██████╗ ███╗   ███╗ █████╗ ███████╗        ║
║     ██╔══██╗██╔══██╗██╔══██╗██╔════╝ ████╗ ████║██╔══██╗██╔════╝        ║
║     ██████╔╝██████╔╝███████║██║  ███╗██╔████╔██║███████║███████╗        ║
║     ██╔═══╝ ██╔══██╗██╔══██║██║   ██║██║╚██╔╝██║██╔══██║╚════██║        ║
║     ██║     ██║  ██║██║  ██║╚██████╔╝██║ ╚═╝ ██║██║  ██║███████║        ║
║     ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝        ║
║                                                                            ║
║  Hybrid Econometrics + Deep Learning Framework for MATLAB                 ║
║  Research & Academic Validation Suite                                     ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
```

# pragmas-suite: Hybrid Econometrics + Deep Learning Framework

**Objetivo:** Suite modular MATLAB para investigación en econometría dinámica y detección de microestructuras de mercado mediante validación asincrónica.

## Estructura

```
pragmas-suite/
├── +pragmas/
│   ├── +data/          # Descarga, limpieza, Hurst Exponent, Fractional Differentiation
│   ├── +models/        # ARIMA-GARCH (Phase 2), LSTM/CNN (Phase 2)
│   ├── +regimes/       # HMM, Markov Switching (Phase 2)
│   ├── +validation/    # Tests estadísticos: Diebold-Mariano, MCS (Phase 2)
│   └── +trading/       # Backtesting vectorizado (Phase 2)
├── research/           # Papers, Live Scripts, bibliografía
├── tests/              # Unit tests (matlab.unittest)
├── pragmas_config.m    # Configuración global
└── main.m              # Pipeline de demostración
```

## Quick Start

1. **Configurar path:**
   ```matlab
   cd('pragmas-suite');
   pragmas_config;
   ```

2. **Ejecutar demo (Phase 1):**
   ```matlab
   main
   ```

3. **Ejecutar tests:**
   ```matlab
   runtests('tests/TestDataModule.m');
   ```

## Módulos Implementados (Phase 1)

### `+pragmas/+data/DataFetcher.m`
Clase para descarga asincrónica de datos financieros (CoinGecko, Yahoo Finance).

**Propiedades:**
- `Symbols`: Símbolos a descargar
- `StartDate`, `EndDate`: Rango temporal
- `Source`: 'crypto' o 'yahoo'
- `DataTables`: Timetables con datos descargados

**Métodos principales:**
- `fetchAsync()`: Descarga en paralelo usando `parfeval`
- `fetchSingle(symbol)`: Descarga individual (compatible con parfeval)

**Ejemplo:**
```matlab
fetcher = pragmas.data.DataFetcher({'BTC-USD', 'ETH-USD'}, ...
    datetime('2025-01-01'), datetime('now'), 'crypto');
fetcher.fetchAsync();
btc_data = fetcher.DataTables{1};  % Acceder a datos de BTC
```

### `+pragmas/+data/computeHurst.m`
Calcula el Hurst Exponent mediante Rescaled Range (R/S) Analysis.

**Entrada:** Serie temporal (vector, timetable, o retornos)  
**Salida:** H ∈ [0, 1.5] (escalar)

**Interpretación:**
- H ≈ 0.5: Random walk (sin correlación)
- H > 0.5: Persistente (trending)
- H < 0.5: Anti-persistente (mean-reverting)

**Ejemplo:**
```matlab
returns = diff(log(btc_data.Close));
H = pragmas.data.computeHurst(returns);
fprintf('Hurst Exponent: %.4f\n', H);
```

### `+pragmas/+data/fractionalDiff.m`
Diferenciación fraccional para estacionariedad preservando memoria de largo plazo.

**Entrada:**
- `series`: Vector de precios
- `d`: Orden fraccional (típicamente 0.1–0.5)
- `thresh`: Umbral de truncamiento (default: 1e-5)

**Salida:** Serie diferenciada (fraccionalmente)

**Motivación:** A diferencia de `diff()` tradicional, preserva autocorrelaciones de largo plazo mientras logra estacionariedad.

**Ejemplo:**
```matlab
d = 0.3;  % Estima óptimo con ADF tests
stationary_series = pragmas.data.fractionalDiff(btc_data.Close, d);
```

## Configuración Global (`pragmas_config.m`)

Define variables globales accesibles desde cualquier módulo:

```matlab
global PRAGMAS_DATA_SOURCES;           % URLs de APIs
global PRAGMAS_API_KEYS;               % API keys (Alpha Vantage, etc.)
global PRAGMAS_PARPOOL_SIZE;           % Número de workers paralelos
global PRAGMAS_LOG_LEVEL;              % Nivel de logging
```

## Asincronía: `parfeval` y Parallel Computing

La clase `DataFetcher.fetchAsync()` utiliza `parfeval` para descargar múltiples símbolos sin bloqueo. Para habilitar paralelismo:

```matlab
% Inicia pool paralelo manualmente (opcional)
parpool(4);  % 4 workers
```

## Tests Unitarios

Localizados en `tests/TestDataModule.m`. Cubre:

- **Hurst Exponent:** Validación de rango, manejo de NaNs, rechazo de series cortas
- **Fractional Differentiation:** Verificación de longitud, efecto de threshold, NaN handling
- **DataFetcher:** Inicialización, fetch de APIs (si hay conexión)

**Ejecutar:**
```matlab
runtests('tests/TestDataModule.m');
```

## Toolboxes Requeridas

- **Econometrics Toolbox** (Phase 2: ARIMA-GARCH)
- **Financial Toolbox** (Métodos financieros, HMM)
- **Deep Learning Toolbox** (Phase 2: LSTM/CNN)
- **Parallel Computing Toolbox** (Asincronía: `parfeval`, `parpool`)
- **Optimization Toolbox** (Phase 2: Ajuste Bayesiano)

**Nota:** Si no tienes una toolbox, comunica para adaptaciones (e.g., implementar GARCH manualmente).

### `+pragmas/+regimes/MarkovRegimeDetector.m`
Clase para detección de regímenes de mercado mediante Hidden Markov Model.

**Propiedades:**
- `Series`: Retornos o residuos de entrada
- `NumStates`: Número de regímenes (default: 3 → Bull/Bear/Sideways)
- `TransitionMatrix`: Matriz de transición P(régimen_{t+1} | régimen_t)
- `StateMeans`, `StateVars`: Parámetros Gaussian de cada estado
- `DecodedStates`: Secuencia óptima decodificada (Viterbi)

**Métodos principales:**
- `train(varargin)`: Entrena HMM con EM (Baum-Welch)
- `getRegimes()`: Retorna etiquetas {'Bull', 'Bear', 'Sideways'}
- `plotRegimes()`: Visualiza series con colores por régimen
- `plotRegimeTransitions()`: Heatmap de matriz de transición
- `plotRegimeStatistics()`: Estadísticas por régimen (distribuciones, duraciones)

**Características:**
- EM (Baum-Welch) automático con convergencia monitorizada
- Forward-Backward e implementación manual de Viterbi
- Fallback manual si Statistics Toolbox no disponible
- Asincronía con `parfeval` para múltiples series

**Ejemplo:**
```matlab
% Entrenar HMM en residuos ARIMA-GARCH
detector = pragmas.regimes.MarkovRegimeDetector(residuals, 3, 'BTC Residuals');
detector.train('MaxIterations', 100);
regimes = detector.getRegimes();  % {'Bull', 'Bear', 'Sideways', ...}

% Visualizar
detector.plotRegimes();
detector.plotRegimeStatistics();
disp(detector.TransitionMatrix);  % Ver persistencia
```

## Innovación: Hybrid Pipeline (Phase 2.1 + 2.2)

El pipeline integrado combina econometría paramétrica con detección de dinámicas no lineales:

```
Retornos brutos
    ↓
[Phase 1] Hurst + Fractional Diff → Serie estacionaria con memoria
    ↓
[Phase 2.1] ARIMA-GARCH → Modelo paramétrico + residuos filtrados
    ↓
[Phase 2.2] HMM en residuos → Detección de Bull/Bear/Sideways
    ↓
[Predicción Condicional]
  - Si Bull: Prioridad LSTM/CNN (no lineal)
  - Si Bear: Prioridad GARCH (volatilidad)
  - Si Sideways: Prioridad ARIMA (media)
```

## Módulos Phase 3: Deep Learning + Validación

### `+pragmas/+models/DeepEngine.m`
Entrenamiento asincrónico de LSTM y CNN-1D sobre residuos econométricos.

**Propiedades:**
- `Series`: Vector de residuos (entrada a DL)
- `Regimes`: Índices de régimen para entrenamiento condicional
- `ModelTypes`: Arquitecturas a entrenar {'LSTM', 'CNN'}
- `TrainedModels`: Cell array con redes entrenadas

**Arquitecturas:**
- **LSTM:** 2 capas × 50 unidades, dropout=0.2, fully connected output
- **CNN-1D:** Conv1d (64 filtros) → Conv1d (128 filtros) → Global Average Pooling → FC output

**Métodos principales:**
- `prepareData()`: Crea secuencias lagged de longitud configurable
- `trainLSTM()`, `trainCNN()`: Entrenamiento individual
- `trainAsync()`: Paralela via `parfeval` (entrenamiento simultáneo LSTM+CNN)
- `predict(modelType, h)`: Pronósticos h pasos adelante

**Ejemplo:**
```matlab
% Entrenar DL en residuos ARIMA-GARCH con régimen conditioning
dlEngine = pragmas.models.DeepEngine(residuals, regime_indices, ...
    struct('SequenceLength', 20, 'EpochsLSTM', 50), 'BTC-USD');
dlEngine.trainAsync({'LSTM', 'CNN'});

% Predicciones
lstm_fcst = dlEngine.predict('LSTM', 20);
cnn_fcst = dlEngine.predict('CNN', 20);
```

**Característica única:** Acepta `Regimes` para entrenar modelos conditionales:
```matlab
% Entrenar LSTM solo en datos Bull, CNN solo en datos Bear
bull_indices = regime_indices == 1;
bear_indices = regime_indices == 2;

dlEngine_bull = pragmas.models.DeepEngine(residuals(bull_indices), ...
    regime_indices(bull_indices), opts, 'BTC-Bull');
dlEngine_bull.trainLSTM();

dlEngine_bear = pragmas.models.DeepEngine(residuals(bear_indices), ...
    regime_indices(bear_indices), opts, 'BTC-Bear');
dlEngine_bear.trainCNN();
```

### `+pragmas/+validation/HybridValidator.m`
Validación rigurosa mediante Model Confidence Set (Hansen et al., 2011) y métricas financieras.

**Propiedades:**
- `Models`: Cell array {nombre, pronósticos, actuals} para cada modelo
- `Losses`: Matriz de pérdidas (N_obs × N_models)
- `MCSSet`: Conjunto de modelos que no se pueden rechazar a α=0.05
- `LossType`: 'MSE', 'MAE', 'MAPE'

**Métodos principales:**
- `computeLosses()`: Calcula MSE/MAE/MAPE elemento-wise
- `computeMCS(alpha)`: MCS simplificado (t-test vs best, p-value filtering)
- `computeMetrics()`: RMSE, MAE, Sharpe, Sortino, MaxDD, Calmar
- `getSummary()`: Tabla publication-ready
- `plotComparison()`: Dashboard 6-subplot

**Interpretación MCS:**
- **Conjunto de Confianza:** Modelos cuyas pérdidas NO difieren significativamente del mejor
- **Estadística:** t-test vs best model: $t = \frac{\bar{d} - 0}{SE(\bar{d})}$
- **p-valor:** $p = 1 - \Phi(t)$ (normal standard)
- **MCS Set:** Modelos con p-valor ≥ (1 - α) a α=0.05 → p ≥ 0.95

**Ejemplo:**
```matlab
% Comparar ARIMA-GARCH vs LSTM vs CNN
models = {
    'ARIMA-GARCH', forecasts_arima, actuals; ...
    'LSTM', forecasts_lstm, actuals; ...
    'CNN', forecasts_cnn, actuals};

validator = pragmas.validation.HybridValidator(models, 'MSE');
validator.computeMCS(0.05);
validator.computeMetrics();

summary = validator.getSummary();
disp(summary);
%     Model          RMSE      MAE   Sharpe  Sortino    MaxDD   Calmar  InMCS
%     ────────────────────────────────────────────────────────────────────────
%     ARIMA-GARCH    0.0156  0.0121  1.234   1.567    -0.0234  4.123   1
%     LSTM           0.0142  0.0109  1.456   1.823    -0.0198  5.234   1
%     CNN            0.0155  0.0118  1.198   1.489    -0.0267  3.876   0

validator.plotComparison();
```

**Métricas Financieras:**
- **Sharpe:** $\text{Sharpe} = \frac{\mu(r)}{\sigma(r)} \times \sqrt{252}$
- **Sortino:** $\text{Sortino} = \frac{\mu(r)}{\sigma(\text{negative } r)} \times \sqrt{252}$ (penaliza downside)
- **MaxDD:** $\text{MDD} = \min_t \left( \frac{C_t - C_{\max(0..t)}}{C_{\max(0..t)}} \right)$ (maximum drawdown)
- **Calmar:** $\text{Calmar} = \frac{\text{annual return}}{|\text{MaxDD}|}$ (retorno ajustado por riesgo)

## Scripts de Demostración

### [main_hybrid.m](main_hybrid.m) - **Nuevo: Phase 3 Completa**
Pipeline **híbrido integrado** de todas las fases (Phase 1 → 3):

1. **Phase 1:** Descarga async BTC-USD
   - Calcula Hurst Exponent (detección de dinámicas)
   - Fractional Differentiation (estacionariedad + memoria)

2. **Phase 2.1:** Grid search ARIMA-GARCH automático
   - 18 especificaciones (p,d,q × P,Q)
   - AIC/BIC ranking automático
   - Genera residuos para Phase 2.2

3. **Phase 2.2:** Detección de regímenes HMM
   - Entrenamiento EM en residuos
   - Decodificación Viterbi → Bull/Bear/Sideways
   - Análisis de transiciones y duraciones

4. **Phase 3.1:** Deep Learning asincrónico
   - LSTM y CNN entrenados en paralelo via `parfeval`
   - Séquences lagged del residuo como input
   - Pronósticos h=20 pasos

5. **Phase 3.2:** Predicción condicional por régimen
   - Detecta régimen actual (Bull/Bear/Sideways)
   - Selecciona modelo basado en régimen:
     - **Bull:** Prioridad LSTM (captura no-linealidades)
     - **Bear:** Prioridad CNN (detecta cambios abruptos)
     - **Sideways:** Prioridad ARIMA-GARCH (mean-reversion)

6. **Phase 3.3:** Validación Model Confidence Set
   - Compara 4 modelos: ARIMA-GARCH, LSTM, CNN, Ensemble
   - Calcula MCS a α=0.05
   - Genera tabla con RMSE, Sharpe, Sortino, MaxDD, Calmar
   - Visualiza 9 subplots (precios, regímenes, pronósticos, MCS)

**Salida esperada:**
```
╔════════════════════════════════════════════════════════════╗
║   PRAGMAS-SUITE: HYBRID PIPELINE COMPLETO (PHASES 1-3)    ║
║   Econometría + HMM + Deep Learning + Validación MCS      ║
╚════════════════════════════════════════════════════════════╝

═══════════════════════════════════════════════════════════
PHASE 1: DATOS Y MICROESTRUCTURA
═══════════════════════════════════════════════════════════

✓ Datos descargados: 180 observaciones
✓ Hurst Exponent: 0.5234 (Random Walk)
✓ Diferenciación fraccional: 180 valores procesados

═══════════════════════════════════════════════════════════
PHASE 2.1: BENCHMARKING ARIMA-GARCH
═══════════════════════════════════════════════════════════

Grid search: 18 especificaciones
✓ Grid search completado en 2.34 segundos
✓ Mejor modelo: ARIMA(1,1,1)-GARCH(1,1)
  AIC: -456.78, BIC: -438.12

═══════════════════════════════════════════════════════════
PHASE 2.2: DETECCIÓN DE REGÍMENES (HMM)
═══════════════════════════════════════════════════════════

✓ HMM entrenado en 0.45 segundos
✓ Regímenes detectados:
  Bull: 58 obs (32.4%)
  Bear: 65 obs (36.3%)
  Sideways: 56 obs (31.3%)

═══════════════════════════════════════════════════════════
PHASE 3.1: DEEP LEARNING (LSTM/CNN)
═══════════════════════════════════════════════════════════

Entrenando LSTM y CNN en paralelo...
✓ Training completado en 8.76 segundos
✓ Pronósticos generados (h=20 pasos)

═══════════════════════════════════════════════════════════
PHASE 3.2: PREDICCIÓN CONDICIONAL POR RÉGIMEN
═══════════════════════════════════════════════════════════

Régimen actual: Bull

BULL REGIME → Prioridad: Modelos No-Lineales (LSTM)
  - LSTM captura dinámicas complejas en tendencias alcistas
  - CNN complementa con patrones locales
  - ARIMA-GARCH como validación paramétrica
Modelo seleccionado: LSTM

═══════════════════════════════════════════════════════════
PHASE 3.3: VALIDACIÓN Y MODEL CONFIDENCE SET (MCS)
═══════════════════════════════════════════════════════════

✓ Tabla de métricas:
        Model          RMSE      MAE    Sharpe  Sortino    MaxDD   Calmar  InMCS
        ──────────────────────────────────────────────────────────────────────
        ARIMA-GARCH    0.0145  0.0112  1.123   1.456    -0.0243  4.123    1
        LSTM           0.0123  0.0095  1.567   2.034    -0.0156  6.789    1
        CNN            0.0156  0.0124  1.089   1.378    -0.0289  3.456    0
        Ensemble       0.0133  0.0103  1.321   1.654    -0.0198  5.234    1

TIEMPOS DE EJECUCIÓN:
  Phase 1 (Datos): < 1s (descarga + Hurst + FracDiff)
  Phase 2.1 (ARIMA-GARCH): 2.34 segundos
  Phase 2.2 (HMM): 0.45 segundos
  Phase 3 (DL): 8.76 segundos
  TOTAL: 11.55 segundos

PERFORMANCE COMPARATIVO:
  ARIMA-GARCH:
    - RMSE: 0.014500
    - Sharpe: 1.1230
    - MaxDD: -0.0243
  LSTM:
    - RMSE: 0.012300
    - Sharpe: 1.5670
    - MaxDD: -0.0156
  CNN:
    - RMSE: 0.015600
    - Sharpe: 1.0890
    - MaxDD: -0.0289
  Ensemble:
    - RMSE: 0.013300
    - Sharpe: 1.3210
    - MaxDD: -0.0198

MODEL CONFIDENCE SET (α=0.05):
  Modelos en MCS: ARIMA-GARCH, LSTM, Ensemble
  Excluidos: CNN (p-valor < 0.05)

RECOMENDACIONES:
  Régimen actual: Bull
  Modelo seleccionado: LSTM
  Validación: MCS incluye múltiples modelos → ensemble recomendado

✓ PIPELINE COMPLETADO EXITOSAMENTE
═══════════════════════════════════════════════════════════
```

**Ejecutar:** `pragmas_config; main_hybrid;`

### [main_phase2.m](main_phase2.m) - Phase 2 Completa (Legacy)
Integra todas las fases:
1. **Phase 1:** Descarga asincrónica de BTC-USD
2. **Phase 1:** Calcula Hurst Exponent y Fractional Differentiation
3. **Phase 2.1:** Grid search ARIMA-GARCH automático (18 especificaciones)
4. **Phase 2.2:** Entrenamiento HMM en residuos ARIMA-GARCH
5. **Análisis:** Detección de regímenes, transiciones, estadísticas
6. **Visualización:** 12 subplots mostrando Hybrid Pipeline completo

**Salida esperada:**
```
[BTC-USD] Iniciando entrenamiento HMM (3 estados, 179 observaciones)...
  Entrenamiento con EM manual (Baum-Welch sin toolbox)
    Iter 10: LogL = -123.45 (ΔL = 0.123)
    ...
    Convergencia alcanzada en iter 47

========== MarkovRegimeDetector Summary ==========
Estados identificados: Bull, Bear, Sideways

Estadísticas por estado:
  Bull: μ=0.0245, σ²=0.0312
  Bear: μ=-0.0189, σ²=0.0276
  Sideways: μ=0.0012, σ²=0.0089

Distribución de regímenes:
  Bull: 58 obs (32.4%)
  Bear: 65 obs (36.3%)
  Sideways: 56 obs (31.3%)

Hybrid Pipeline Insights:
Régimen actual (últimas obs): Bull
Modelos recomendados:
  - Prioridad: LSTM/CNN detectan oportunidades
  - Suplemento: ARIMA-GARCH para validación
```

**Ejecutar:** `pragmas_config; main_phase2;`

## Referencias Académicas

- López de Prado, M. (2018). *Advances in Financial Machine Learning*. Wiley.
- Peters, E. (1994). *Fractal Market Analysis*. Wiley.
- Diebold, F. X., & Mariano, R. S. (1995). "Comparing Predictive Accuracy." *JBES*, 13(3), 253–263.
- Hansen, P. R., Lunde, A., & Nason, J. M. (2011). "The Model Confidence Set." *Econometric Reviews*, 30(6), 581–605.

## Notas de Seguridad

⚠️ **Esta suite es para investigación académica y validación estadística.** Cualquier implementación en trading real debe realizarse bajo tu responsabilidad con gestión de riesgo profesional.

## Contacto / Issues

Para errores, sugerencias o extensiones, comunica en el espacio de trabajo.

---

**Última actualización:** Enero 2026  
**Versión:** 0.3 (Phase 3 Completa: Deep Learning + MCS)

---

## Roadmap Futuro (Phase 4+)

- [ ] **Transformer Architecture** para secuencias largas (Phase 4.1)
- [ ] **Markov Switching GARCH** (MS-GARCH) condicional a regímenes (Phase 4.2)
- [ ] **Ensemble Methods** (Stacking, Voting, Boosting) (Phase 4.3)
- [ ] **Backtesting Real** con slippage, comisiones, liquidez (Phase 5)
- [ ] **AutoML Pipeline** con optimización Bayesiana de hiperparámetros (Phase 5)
- [ ] **LaTeX Report Generation** automático (mlreportgen) (Phase 5)
- [ ] **Explainability (SHAP/LIME)** para transparencia DL (Phase 6)
- [ ] **API REST** para integración con plataformas trading (Phase 6)
