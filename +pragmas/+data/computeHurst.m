function H = computeHurst(series)
    % COMPUTEHURST Hurst Exponent vía R/S Analysis.
    % Input:
    %   series: vector de retornos log o precios (e.g., diff(log(data.Close)))
    % Output:
    %   H: Hurst exponent (escalar entre 0 y 1)
    % 
    % Interpretación:
    %   H ~0.5: Random walk (no correlación)
    %   H > 0.5: Persistente (trending)
    %   H < 0.5: Anti-persistente (mean-reverting)
    
    % Validar entrada
    if istimetable(series)
        series = series{:, :};  % Extrae valores si es timetable
    end
    
    series = series(:);  % Asegurar columna
    series = series(~isnan(series));  % Remover NaNs
    
    N = length(series);
    if N < 100
        error('Serie demasiado corta para Hurst (mín. 100 observaciones).');
    end
    
    % Tamaños de subseries (potencias de 2 para eficiencia y robustez)
    tau = 2.^(3:floor(log2(N/2)));
    logTau = log(tau);
    logRS = zeros(size(tau));
    
    % Calcular R/S para cada escala tau
    for i = 1:length(tau)
        n = tau(i);
        numSubs = floor(N / n);
        
        rsSubs = zeros(numSubs, 1);
        
        for j = 1:numSubs
            % Subserie [t1, ..., tn]
            subStart = (j - 1) * n + 1;
            subEnd = j * n;
            sub = series(subStart:subEnd);
            
            % Media de la subserie
            meanSub = mean(sub);
            
            % Desviaciones acumuladas
            deviations = sub - meanSub;
            cumDev = cumsum(deviations);
            
            % Rango R
            R = max(cumDev) - min(cumDev);
            
            % Desviación estándar S
            S = std(sub);
            
            % R/S ratio
            if S > 0 && R > 0
                rsSubs(j) = R / S;
            else
                rsSubs(j) = NaN;
            end
        end
        
        % Media log de R/S (remover valores inválidos)
        validRS = rsSubs(~isnan(rsSubs) & rsSubs > 0);
        if ~isempty(validRS)
            logRS(i) = log(mean(validRS));
        else
            logRS(i) = NaN;
        end
    end
    
    % Regresión log-log para estimar H
    validIdx = ~isnan(logRS);
    if sum(validIdx) < 2
        error('Insuficientes puntos válidos para regresión.');
    end
    
    p = polyfit(logTau(validIdx), logRS(validIdx), 1);
    H = p(1);  % Slope de la regresión
    
    % Warning si H está fuera del rango esperado
    if H < 0 || H > 1.5
        warning('Hurst exponent H = %.3f está fuera del rango típico [0, 1]. Revisa datos.', H);
    end
end
