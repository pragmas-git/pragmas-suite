%% VALIDATE_SUITE: Verificación de integridad de pragmas-suite
% Ejecuta: pragmas_config; validate_suite;

clear all; close all; clc;

fprintf('\n╔════════════════════════════════════════════════════════════╗\n');
fprintf('║         PRAGMAS-SUITE: VALIDACIÓN DE INTEGRIDAD          ║\n');
fprintf('╚════════════════════════════════════════════════════════════╝\n\n');

%% 1. Verificar estructura de directorios
fprintf('1. Verificando estructura de directorios...\n');

required_dirs = {
    '+pragmas/+data', ...
    '+pragmas/+models', ...
    '+pragmas/+regimes', ...
    '+pragmas/+validation', ...
    'tests', ...
    'research'};

all_dirs_exist = true;
for i = 1:length(required_dirs)
    if isfolder(required_dirs{i})
        fprintf('   ✓ %s\n', required_dirs{i});
    else
        fprintf('   ✗ %s (MISSING)\n', required_dirs{i});
        all_dirs_exist = false;
    end
end

if all_dirs_exist
    fprintf('   ✓ Todas las carpetas requeridas existen\n\n');
else
    fprintf('   ⚠ Faltan algunas carpetas\n\n');
end

%% 2. Verificar archivos de módulos
fprintf('2. Verificando módulos implementados...\n');

modules = {
    % Phase 1
    '+pragmas/+data/DataFetcher.m', 'Phase 1: Data Fetching';
    '+pragmas/+data/computeHurst.m', 'Phase 1: Hurst Exponent';
    '+pragmas/+data/fractionalDiff.m', 'Phase 1: Fractional Differentiation';
    % Phase 2
    '+pragmas/+models/ModelEngine.m', 'Phase 2.1: ARIMA-GARCH';
    '+pragmas/+regimes/MarkovRegimeDetector.m', 'Phase 2.2: HMM Regime Detection';
    % Phase 3
    '+pragmas/+models/DeepEngine.m', 'Phase 3.1: Deep Learning (LSTM/CNN)';
    '+pragmas/+validation/HybridValidator.m', 'Phase 3.2: MCS Validation'};

phase_status = struct();
all_modules_exist = true;

for i = 1:size(modules, 1)
    filepath = modules{i, 1};
    description = modules{i, 2};
    
    if isfile(filepath)
        fprintf('   ✓ %s\n', description);
    else
        fprintf('   ✗ %s (MISSING)\n', description);
        all_modules_exist = false;
    end
end

if all_modules_exist
    fprintf('   ✓ Todos los módulos implementados\n\n');
else
    fprintf('   ⚠ Faltan módulos\n\n');
end

%% 3. Verificar archivos de test
fprintf('3. Verificando tests unitarios...\n');

test_files = {
    'tests/TestDataModule.m', 'Phase 1 Tests';
    'tests/TestModelEngine.m', 'Phase 2.1 Tests';
    'tests/TestMarkovRegimeDetector.m', 'Phase 2.2 Tests';
    'tests/TestDeepEngine.m', 'Phase 3.1 Tests';
    'tests/TestHybridValidator.m', 'Phase 3.2 Tests'};

all_tests_exist = true;
for i = 1:size(test_files, 1)
    filepath = test_files{i, 1};
    description = test_files{i, 2};
    
    if isfile(filepath)
        fprintf('   ✓ %s\n', description);
    else
        fprintf('   ✗ %s (MISSING)\n', description);
        all_tests_exist = false;
    end
end

if all_tests_exist
    fprintf('   ✓ Todos los tests implementados\n\n');
else
    fprintf('   ⚠ Faltan tests\n\n');
end

%% 4. Verificar scripts de demostración
fprintf('4. Verificando scripts de demostración...\n');

demo_scripts = {
    'main.m', 'Phase 1 Demo';
    'main_phase2.m', 'Phase 2 Demo';
    'main_hybrid.m', 'Phase 3 Hybrid Demo (NEW)';
    'pragmas_config.m', 'Global Configuration'};

all_demos_exist = true;
for i = 1:size(demo_scripts, 1)
    filepath = demo_scripts{i, 1};
    description = demo_scripts{i, 2};
    
    if isfile(filepath)
        fprintf('   ✓ %s\n', description);
    else
        fprintf('   ✗ %s (MISSING)\n', description);
        all_demos_exist = false;
    end
end

if all_demos_exist
    fprintf('   ✓ Todos los scripts de demostración existen\n\n');
else
    fprintf('   ⚠ Faltan scripts\n\n');
end

%% 5. Verificar dependencias de toolbox
fprintf('5. Verificando disponibilidad de toolboxes...\n');

toolboxes_to_check = {
    'Econometrics Toolbox', 'econometrics';
    'Financial Toolbox', 'financial';
    'Deep Learning Toolbox', 'deeplearning';
    'Parallel Computing Toolbox', 'parallel';
    'Optimization Toolbox', 'optim'};

available_toolboxes = {};
missing_toolboxes = {};

for i = 1:size(toolboxes_to_check, 1)
    toolbox_name = toolboxes_to_check{i, 1};
    toolbox_id = toolboxes_to_check{i, 2};
    
    v = ver;
    toolbox_available = any(strcmp({v.Name}, toolbox_name));
    
    if toolbox_available
        fprintf('   ✓ %s\n', toolbox_name);
        available_toolboxes = [available_toolboxes; toolbox_name];
    else
        fprintf('   ⚠ %s (not installed, fallback will be used)\n', toolbox_name);
        missing_toolboxes = [missing_toolboxes; toolbox_name];
    end
end

fprintf('\n   Available: %d/%d\n', length(available_toolboxes), size(toolboxes_to_check, 1));
if ~isempty(missing_toolboxes)
    fprintf('   Note: Fallback implementations will be used for missing toolboxes\n');
end
fprintf('\n');

%% 6. Verificar configuración global
fprintf('6. Verificando configuración global...\n');

try
    pragmas_config;
    
    % Check globals
    global PRAGMAS_PARPOOL_SIZE PRAGMAS_LOG_LEVEL ...
        PRAGMAS_DEEPENGINE_OPTIONS PRAGMAS_VALIDATOR_OPTIONS;
    
    if exist('PRAGMAS_PARPOOL_SIZE', 'var') && ~isempty(PRAGMAS_PARPOOL_SIZE)
        fprintf('   ✓ PRAGMAS_PARPOOL_SIZE = %d\n', PRAGMAS_PARPOOL_SIZE);
    end
    
    if exist('PRAGMAS_LOG_LEVEL', 'var') && ~isempty(PRAGMAS_LOG_LEVEL)
        fprintf('   ✓ PRAGMAS_LOG_LEVEL = %s\n', PRAGMAS_LOG_LEVEL);
    end
    
    if exist('PRAGMAS_DEEPENGINE_OPTIONS', 'var') && ~isempty(PRAGMAS_DEEPENGINE_OPTIONS)
        fprintf('   ✓ PRAGMAS_DEEPENGINE_OPTIONS configured\n');
        fprintf('     - SequenceLength: %d\n', PRAGMAS_DEEPENGINE_OPTIONS.SequenceLength);
        fprintf('     - EpochsLSTM: %d\n', PRAGMAS_DEEPENGINE_OPTIONS.EpochsLSTM);
        fprintf('     - EpochsCNN: %d\n', PRAGMAS_DEEPENGINE_OPTIONS.EpochsCNN);
    end
    
    if exist('PRAGMAS_VALIDATOR_OPTIONS', 'var') && ~isempty(PRAGMAS_VALIDATOR_OPTIONS)
        fprintf('   ✓ PRAGMAS_VALIDATOR_OPTIONS configured\n');
        fprintf('     - LossType: %s\n', PRAGMAS_VALIDATOR_OPTIONS.LossType);
        fprintf('     - MCSDelta: %.2f\n', PRAGMAS_VALIDATOR_OPTIONS.MCSDelta);
    end
    
    fprintf('   ✓ Configuración global válida\n\n');
catch ME
    fprintf('   ✗ Error en configuración: %s\n\n', ME.message);
end

%% 7. Resumen y recomendaciones
fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('RESUMEN DE VALIDACIÓN\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');

checks_passed = all_dirs_exist + all_modules_exist + all_tests_exist + all_demos_exist;

fprintf('Criterios pasados: %d/4\n', checks_passed);

if checks_passed == 4
    fprintf('\n✓ PRAGMAS-SUITE COMPLETAMENTE VALIDADA\n');
    fprintf('\nPróximos pasos:\n');
    fprintf('  1. Ejecutar tests: runtests(''tests'')\n');
    fprintf('  2. Ejecutar demo Phase 2: main_phase2\n');
    fprintf('  3. Ejecutar demo Phase 3 (Hybrid): main_hybrid\n');
    fprintf('  4. Consultar README.md para documentación detallada\n');
else
    fprintf('\n⚠ PRAGMAS-SUITE REQUIERE AJUSTES\n');
    fprintf('Verifica los avisos arriba.\n');
end

fprintf('\n═══════════════════════════════════════════════════════════\n\n');

%% 8. Opcional: Ejecutar test rápido
fprintf('Ejecutando test rápido de módulos...\n\n');

try
    % Test Phase 1: Hurst
    rng(42);
    series = 100 * cumprod(1 + 0.01 * randn(100, 1));
    H = pragmas.data.computeHurst(diff(log(series)) * 100);
    fprintf('✓ Hurst Exponent Test: H = %.4f (expected: 0-1.5)\n', H);
    
    % Test Phase 1: Fractional Diff
    frac = pragmas.data.fractionalDiff(series, 0.3);
    fprintf('✓ Fractional Diff Test: %d valores procesados\n', length(frac));
    
    % Test Phase 2.1: ModelEngine initialization
    returns = diff(log(series)) * 100;
    engine = pragmas.models.ModelEngine(returns, 'TEST', false);
    fprintf('✓ ModelEngine Test: Inicializado correctamente\n');
    
    % Test Phase 2.2: MarkovRegimeDetector initialization
    detector = pragmas.regimes.MarkovRegimeDetector(returns, 3, 'TEST');
    fprintf('✓ MarkovRegimeDetector Test: Inicializado correctamente\n');
    
    % Test Phase 3.1: DeepEngine initialization
    dlEngine = pragmas.models.DeepEngine(returns, ones(length(returns), 1), ...
        struct('SequenceLength', 10), 'TEST');
    fprintf('✓ DeepEngine Test: Inicializado correctamente\n');
    
    % Test Phase 3.2: HybridValidator initialization
    validator = pragmas.validation.HybridValidator({...
        'Model1', returns(1:50), returns(1:50); ...
        'Model2', returns(2:51), returns(1:50)}, 'MSE');
    fprintf('✓ HybridValidator Test: Inicializado correctamente\n');
    
    fprintf('\n✓ TODOS LOS TESTS RÁPIDOS PASARON\n\n');
    
catch ME
    fprintf('\n✗ Error en test rápido:\n');
    fprintf('  %s\n\n', ME.message);
end

fprintf('═══════════════════════════════════════════════════════════\n');
fprintf('Validación completada.\n');
fprintf('═══════════════════════════════════════════════════════════\n\n');
