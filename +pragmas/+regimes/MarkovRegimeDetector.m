classdef MarkovRegimeDetector < handle
    % MARKOVREGIMEDETECTOR Detección de regímenes de mercado vía Hidden Markov Model.
    %
    % Clasifica mercado en 3 regímenes: "Bull" (alcista), "Bear" (bajista), "Sideways" (lateral).
    % Entrena HMM en series de retornos o residuos ARIMA-GARCH para capturar dinámicas no lineales.
    %
    % Uso típico:
    %   detector = pragmas.regimes.MarkovRegimeDetector(returns_or_residuals);
    %   detector.train();
    %   regimes = detector.getRegimes();
    %   detector.plotRegimes();
    %
    % Nota: Prefiere Statistics and Machine Learning Toolbox. Sin él, usa fallback EM.
    
    properties
        % Datos y configuración
        Series              % Vector de retornos/residuos
        SeriesName          % Identificador (ej. 'BTC-USD Residuals')
        NumStates           % Número de regímenes (default: 3)
        
        % Parámetros del HMM
        TransitionMatrix    % Matriz de transición (NumStates x NumStates)
        EmissionProb        % Matriz de emisión (alternativo: usar parámetros Gaussian)
        StateMeans          % Medias por estado
        StateVars           % Varianzas por estado
        StateProbs          % Probabilidades iniciales de estado
        
        % Resultados
        DecodedStates       % Secuencia de estados (Viterbi)
        ForwardProbs        % Probabilidades forward (DP)
        BackwardProbs       % Probabilidades backward (DP)
        StateRegimeNames    % Etiquetas {'Bull', 'Bear', 'Sideways'}
        
        % Parámetros del entrenamiento
        MaxIterations       % Máximo de iteraciones EM (default: 100)
        Tolerance           % Tolerancia de convergencia (default: 1e-4)
        UseToolbox          % Flag si Stats Toolbox está disponible
    end
    
    methods
        %% Constructor
        function obj = MarkovRegimeDetector(series, numStates, seriesName)
            % MARKOVREGIMEDETECTOR Inicializa detector de regímenes.
            %
            % Input:
            %   series: vector de retornos o residuos
            %   numStates: número de regímenes (default: 3)
            %   seriesName: string identificador (default: 'Series')
            
            if istimetable(series)
                obj.Series = series{:, :};
            else
                obj.Series = series(:);
            end
            
            obj.Series = obj.Series(~isnan(obj.Series));  % Remover NaNs
            
            if nargin < 2 || isempty(numStates)
                obj.NumStates = 3;
            else
                obj.NumStates = numStates;
            end
            
            if nargin < 3 || isempty(seriesName)
                obj.SeriesName = 'Series';
            else
                obj.SeriesName = seriesName;
            end
            
            obj.StateRegimeNames = {'Bull', 'Bear', 'Sideways'};
            if obj.NumStates ~= 3
                obj.StateRegimeNames = compose('State_%d', (1:obj.NumStates)');
            end
            
            obj.MaxIterations = 100;
            obj.Tolerance = 1e-4;
            obj.UseToolbox = license('test', 'Statistics_Toolbox');
        end
        
        %% Entrenamiento Principal
        function train(obj, varargin)
            % TRAIN Entrena HMM usando EM (Baum-Welch).
            %
            % Parámetros opcionales (name-value):
            %   'InitTransition': Matriz de transición inicial
            %   'InitMeans': Medias iniciales (NumStates x 1)
            %   'InitVars': Varianzas iniciales (NumStates x 1)
            %   'MaxIterations': Máximo de iteraciones EM
            
            p = inputParser;
            addParameter(p, 'InitTransition', [], @ismatrix);
            addParameter(p, 'InitMeans', [], @isvector);
            addParameter(p, 'InitVars', [], @isvector);
            addParameter(p, 'MaxIterations', obj.MaxIterations, @isnumeric);
            parse(p, varargin{:});
            
            % Inicialización
            [trans, mu, sigma] = obj.initializeParams(...
                p.Results.InitTransition, p.Results.InitMeans, p.Results.InitVars);
            
            obj.MaxIterations = p.Results.MaxIterations;
            
            fprintf('[%s] Iniciando entrenamiento HMM (%d estados, %d observaciones)...\n', ...
                obj.SeriesName, obj.NumStates, length(obj.Series));
            
            if obj.UseToolbox
                obj.trainWithToolbox(trans, mu, sigma);
            else
                obj.trainWithFallback(trans, mu, sigma);
            end
            
            % Decodificar estados (Viterbi)
            obj.viterbiDecode();
            
            fprintf('[%s] Entrenamiento completado.\n', obj.SeriesName);
        end
        
        %% Inicialización de Parámetros
        function [trans, mu, sigma] = initializeParams(obj, initTrans, initMu, initSigma)
            % INITIALIZEPARAMS Inicializa parámetros HMM.
            
            N = length(obj.Series);
            
            if isempty(initMu)
                % K-means para inicializar medias
                [idx, centers] = kmeans(obj.Series, obj.NumStates, 'Replicates', 3);
                mu = sort(centers);  % Ordena para interpretabilidad (Bull/Bear/Sideways)
            else
                mu = initMu(:);
            end
            
            if isempty(initSigma)
                % Varianzas iniciales por cluster
                sigma = ones(obj.NumStates, 1);
                for s = 1:obj.NumStates
                    if sum(idx == s) > 1
                        sigma(s) = var(obj.Series(idx == s));
                    else
                        sigma(s) = var(obj.Series);
                    end
                end
            else
                sigma = initSigma(:);
            end
            
            if isempty(initTrans)
                % Matriz de transición diagonal dominante (persistencia)
                trans = 0.05 * ones(obj.NumStates) / (obj.NumStates - 1);
                trans(1:obj.NumStates+1:end) = 0.9;  % Diagonal: 0.9 (persistencia)
            else
                trans = initTrans;
            end
            
            obj.StateMeans = mu;
            obj.StateVars = sigma;
            obj.TransitionMatrix = trans;
            obj.StateProbs = ones(obj.NumStates, 1) / obj.NumStates;  % Uniforme
        end
        
        %% Entrenamiento con Statistics Toolbox
        function trainWithToolbox(obj, initTrans, initMu, initSigma)
            % TRAINWITHTOOLBOX Usa hmmestimate y emisión Gaussian.
            
            try
                % Discretizar serie en símbolos (1:NumStates) basado en cuantiles
                [~, symbols] = histcounts(obj.Series, obj.NumStates);
                symbols = symbols + 1;  % Evitar índice 0
                
                % hmmestimate: estima matriz de transición
                obj.TransitionMatrix = hmmestimate(symbols, symbols);
                
                % Actualizar medias y varianzas con EM-like adjustment
                for s = 1:obj.NumStates
                    idx = symbols == s;
                    if sum(idx) > 0
                        obj.StateMeans(s) = mean(obj.Series(idx));
                        obj.StateVars(s) = max(var(obj.Series(idx)), 0.001);  % Evitar varianza cero
                    end
                end
                
                fprintf('  Entrenamiento con hmmestimate (Statistics Toolbox)\n');
                
            catch
                % Fallback si hmmestimate falla
                warning('hmmestimate falló; usando Baum-Welch manual.');
                obj.trainWithFallback(initTrans, initMu, initSigma);
            end
        end
        
        %% Entrenamiento Manual (Fallback EM)
        function trainWithFallback(obj, initTrans, initMu, initSigma)
            % TRAINWITHFALLBACK Implementación EM (Baum-Welch) sin toolbox.
            % Versión simplificada pero funcional para HMM Gaussian.
            
            N = length(obj.Series);
            trans = initTrans;
            mu = initMu;
            sigma = initSigma;
            logLikPrev = -inf;
            
            fprintf('  Entrenamiento con EM manual (Baum-Welch sin toolbox)\n');
            
            for iter = 1:obj.MaxIterations
                % E-step: Forward-Backward
                [alpha, logL] = obj.forwardAlgorithm(mu, sigma, trans);
                beta = obj.backwardAlgorithm(mu, sigma, trans, logL);
                
                % Suavizar: combinar forward-backward
                gamma = alpha .* beta;  % Probabilidades suavizadas
                gamma = gamma ./ sum(gamma, 2);  % Normalizar
                
                xi = zeros(N-1, obj.NumStates, obj.NumStates);
                for t = 1:N-1
                    for i = 1:obj.NumStates
                        for j = 1:obj.NumStates
                            emission_j = normpdf(obj.Series(t+1), mu(j), sqrt(sigma(j)));
                            xi(t, i, j) = (alpha(t, i) * trans(i, j) * emission_j * beta(t+1, j)) / sum(alpha(t, :) * trans * beta(t+1, :)');
                        end
                    end
                end
                
                % M-step: Actualizar parámetros
                % Transición
                transNew = zeros(obj.NumStates);
                for i = 1:obj.NumStates
                    gammaSum = sum(gamma(1:N-1, i));
                    if gammaSum > 0
                        for j = 1:obj.NumStates
                            transNew(i, j) = sum(xi(:, i, j)) / gammaSum;
                        end
                    else
                        transNew(i, :) = trans(i, :);
                    end
                end
                
                % Medias y varianzas
                muNew = zeros(obj.NumStates, 1);
                sigmaNew = zeros(obj.NumStates, 1);
                for j = 1:obj.NumStates
                    gammaJ = gamma(:, j);
                    gammaJSum = sum(gammaJ);
                    if gammaJSum > 0
                        muNew(j) = sum(gammaJ .* obj.Series) / gammaJSum;
                        sigmaNew(j) = sum(gammaJ .* (obj.Series - muNew(j)).^2) / gammaJSum;
                        sigmaNew(j) = max(sigmaNew(j), 0.001);  % Evitar varianza cero
                    else
                        muNew(j) = mu(j);
                        sigmaNew(j) = sigma(j);
                    end
                end
                
                % Convergencia
                logLikNew = sum(log(sum(alpha, 2)));  % Log-likelihood
                if mod(iter, 10) == 0
                    fprintf('    Iter %d: LogL = %.4f (ΔL = %.6f)\n', ...
                        iter, logLikNew, logLikNew - logLikPrev);
                end
                
                if abs(logLikNew - logLikPrev) < obj.Tolerance
                    fprintf('    Convergencia alcanzada en iter %d\n', iter);
                    break;
                end
                
                trans = transNew;
                mu = muNew;
                sigma = sigmaNew;
                logLikPrev = logLikNew;
            end
            
            obj.TransitionMatrix = trans;
            obj.StateMeans = mu;
            obj.StateVars = sigma;
        end
        
        %% Forward Algorithm
        function [alpha, logL] = forwardAlgorithm(obj, mu, sigma, trans)
            % FORWARDALGORITHM Calcula probabilidades forward.
            
            N = length(obj.Series);
            alpha = zeros(N, obj.NumStates);
            
            % Inicialización (t=1)
            for j = 1:obj.NumStates
                alpha(1, j) = obj.StateProbs(j) * normpdf(obj.Series(1), mu(j), sqrt(sigma(j)));
            end
            
            % Recursión
            for t = 2:N
                for j = 1:obj.NumStates
                    alpha(t, j) = normpdf(obj.Series(t), mu(j), sqrt(sigma(j))) * ...
                        sum(alpha(t-1, :) .* trans(:, j)');
                end
            end
            
            logL = sum(log(sum(alpha, 2) + eps));  % Log-likelihood
        end
        
        %% Backward Algorithm
        function beta = backwardAlgorithm(obj, mu, sigma, trans, logL)
            % BACKWARDALGORITHM Calcula probabilidades backward.
            
            N = length(obj.Series);
            beta = zeros(N, obj.NumStates);
            
            % Inicialización (t=N)
            beta(N, :) = 1;
            
            % Recursión backward
            for t = N-1:-1:1
                for i = 1:obj.NumStates
                    for j = 1:obj.NumStates
                        beta(t, i) = beta(t, i) + trans(i, j) * ...
                            normpdf(obj.Series(t+1), mu(j), sqrt(sigma(j))) * beta(t+1, j);
                    end
                end
            end
        end
        
        %% Viterbi Decoding
        function viterbiDecode(obj)
            % VITERBIDECODE Decodifica secuencia óptima de estados (Viterbi).
            
            N = length(obj.Series);
            viterbiProb = zeros(N, obj.NumStates);
            backPointer = zeros(N, obj.NumStates);
            
            % Inicialización (t=1)
            for j = 1:obj.NumStates
                viterbiProb(1, j) = log(obj.StateProbs(j)) + ...
                    log(normpdf(obj.Series(1), obj.StateMeans(j), sqrt(obj.StateVars(j))) + eps);
            end
            
            % Recursión (t=2:N)
            for t = 2:N
                for j = 1:obj.NumStates
                    [maxProb, maxIdx] = max(viterbiProb(t-1, :) + log(obj.TransitionMatrix(:, j)' + eps));
                    viterbiProb(t, j) = maxProb + ...
                        log(normpdf(obj.Series(t), obj.StateMeans(j), sqrt(obj.StateVars(j))) + eps);
                    backPointer(t, j) = maxIdx;
                end
            end
            
            % Backtracking
            states = zeros(N, 1);
            [~, states(N)] = max(viterbiProb(N, :));
            
            for t = N-1:-1:1
                states(t) = backPointer(t+1, states(t+1));
            end
            
            obj.DecodedStates = states;
        end
        
        %% Obtener Regímenes
        function regimes = getRegimes(obj)
            % GETREGIMES Retorna etiquetas de regímenes decodificados.
            
            if isempty(obj.DecodedStates)
                error('Primero ejecuta train() para decodificar estados.');
            end
            
            regimes = obj.StateRegimeNames(obj.DecodedStates);
        end
        
        function regimeIndices = getRegimeIndices(obj)
            % GETREGIMEINDICES Retorna índices numéricos (1-NumStates).
            
            if isempty(obj.DecodedStates)
                error('Primero ejecuta train() para decodificar estados.');
            end
            
            regimeIndices = obj.DecodedStates;
        end
        
        %% Visualización
        function plotRegimes(obj, varargin)
            % PLOTREGIMES Visualiza serie con colores por régimen.
            
            if isempty(obj.DecodedStates)
                error('Primero ejecuta train() para decodificar estados.');
            end
            
            p = inputParser;
            addParameter(p, 'ShowLegend', true, @islogical);
            addParameter(p, 'ShowTitle', true, @islogical);
            parse(p, varargin{:});
            
            figure('Name', sprintf('Regime Detection: %s', obj.SeriesName), 'NumberTitle', 'off');
            
            hold on;
            colors = lines(obj.NumStates);
            
            for s = 1:obj.NumStates
                idx = obj.DecodedStates == s;
                if any(idx)
                    scatter(find(idx), obj.Series(idx), 30, colors(s, :), 'filled', ...
                        'DisplayName', obj.StateRegimeNames{s});
                end
            end
            
            % Línea de tiempo
            plot(obj.Series, 'k-', 'LineWidth', 0.5, 'Alpha', 0.3, 'DisplayName', 'Series');
            
            if p.Results.ShowLegend
                legend('Location', 'best', 'FontSize', 10);
            end
            
            if p.Results.ShowTitle
                title(sprintf('HMM Regime Detection: %s', obj.SeriesName), 'FontWeight', 'bold');
            end
            
            xlabel('Time');
            ylabel('Returns/Residuals');
            grid on;
            hold off;
        end
        
        function plotRegimeTransitions(obj)
            % PLOTRGIEMETRANSITIONS Visualiza matriz de transición como heatmap.
            
            if isempty(obj.TransitionMatrix)
                error('Primero ejecuta train() para estimar matriz de transición.');
            end
            
            figure('Name', 'Transition Matrix', 'NumberTitle', 'off');
            imagesc(obj.TransitionMatrix);
            colorbar;
            
            set(gca, 'XTickLabel', obj.StateRegimeNames, ...
                'YTickLabel', obj.StateRegimeNames);
            
            title('Transition Probability Matrix (Heatmap)', 'FontWeight', 'bold');
            
            % Añadir valores en celdas
            for i = 1:obj.NumStates
                for j = 1:obj.NumStates
                    text(j, i, sprintf('%.2f', obj.TransitionMatrix(i, j)), ...
                        'HorizontalAlignment', 'center', 'Color', 'white', 'FontSize', 12);
                end
            end
        end
        
        function plotRegimeStatistics(obj)
            % PLOTREGIMESTATISTICS Visualiza estadísticas por régimen.
            
            if isempty(obj.DecodedStates)
                error('Primero ejecuta train() para decodificar estados.');
            end
            
            figure('Name', 'Regime Statistics', 'NumberTitle', 'off');
            
            % Subplot 1: Distribución de retornos por régimen
            subplot(2, 2, 1);
            for s = 1:obj.NumStates
                data_s = obj.Series(obj.DecodedStates == s);
                histogram(data_s, 20, 'DisplayName', obj.StateRegimeNames{s}, 'EdgeColor', 'black');
                hold on;
            end
            title('Distribution of Returns by Regime', 'FontWeight', 'bold');
            xlabel('Return');
            ylabel('Frequency');
            legend('Location', 'best');
            grid on;
            hold off;
            
            % Subplot 2: Medias y desv. std por régimen
            subplot(2, 2, 2);
            means = zeros(obj.NumStates, 1);
            stds = zeros(obj.NumStates, 1);
            for s = 1:obj.NumStates
                data_s = obj.Series(obj.DecodedStates == s);
                means(s) = mean(data_s);
                stds(s) = std(data_s);
            end
            bar(1:obj.NumStates, means, 'EdgeColor', 'black');
            hold on;
            errorbar(1:obj.NumStates, means, stds, 'r.', 'LineWidth', 2);
            set(gca, 'XTickLabel', obj.StateRegimeNames);
            title('Mean and Std Dev by Regime', 'FontWeight', 'bold');
            ylabel('Return');
            grid on;
            hold off;
            
            % Subplot 3: Duraciones de regímenes
            subplot(2, 2, 3);
            durations = zeros(obj.NumStates, 1);
            for s = 1:obj.NumStates
                idx = obj.DecodedStates == s;
                changes = [true; diff(idx) ~= 0; true];
                durs = diff(find(changes)) - 1;
                durations(s) = mean(durs(durs > 0));
            end
            bar(1:obj.NumStates, durations, 'EdgeColor', 'black');
            set(gca, 'XTickLabel', obj.StateRegimeNames);
            title('Average Regime Duration', 'FontWeight', 'bold');
            ylabel('Time Steps');
            grid on;
            
            % Subplot 4: Transiciones reales observadas
            subplot(2, 2, 4);
            transReal = zeros(obj.NumStates);
            for t = 1:length(obj.DecodedStates)-1
                s_from = obj.DecodedStates(t);
                s_to = obj.DecodedStates(t+1);
                transReal(s_from, s_to) = transReal(s_from, s_to) + 1;
            end
            % Normalizar
            for i = 1:obj.NumStates
                if sum(transReal(i, :)) > 0
                    transReal(i, :) = transReal(i, :) / sum(transReal(i, :));
                end
            end
            imagesc(transReal);
            colorbar;
            set(gca, 'XTickLabel', obj.StateRegimeNames, ...
                'YTickLabel', obj.StateRegimeNames);
            title('Observed Transition Probabilities', 'FontWeight', 'bold');
        end
        
        %% Información del Modelo
        function disp(obj)
            % DISP Muestra resumen del HMM.
            
            fprintf('\n========== MarkovRegimeDetector Summary ==========\n');
            fprintf('Serie: %s (%d observaciones)\n', obj.SeriesName, length(obj.Series));
            fprintf('Número de estados: %d\n', obj.NumStates);
            fprintf('\nEstados identificados: %s\n', strjoin(obj.StateRegimeNames, ', '));
            
            if ~isempty(obj.StateMeans)
                fprintf('\nEstadísticas por estado:\n');
                for s = 1:obj.NumStates
                    fprintf('  %s: μ=%.4f, σ²=%.4f\n', obj.StateRegimeNames{s}, ...
                        obj.StateMeans(s), obj.StateVars(s));
                end
            end
            
            if ~isempty(obj.TransitionMatrix)
                fprintf('\nMatriz de transición:\n');
                disp(array2table(obj.TransitionMatrix, ...
                    'RowNames', obj.StateRegimeNames, ...
                    'VariableNames', obj.StateRegimeNames));
            end
            
            if ~isempty(obj.DecodedStates)
                fprintf('\nDistribución de regímenes:\n');
                for s = 1:obj.NumStates
                    count = sum(obj.DecodedStates == s);
                    pct = 100 * count / length(obj.DecodedStates);
                    fprintf('  %s: %d obs (%.1f%%)\n', obj.StateRegimeNames{s}, count, pct);
                end
            end
            
            fprintf('================================================\n\n');
        end
    end
end
