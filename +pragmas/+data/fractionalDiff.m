function diffSeries = fractionalDiff(series, d, thresh)
    % FRACTIONALDIFF Diferenciación fraccional para estacionariedad con memoria.
    %
    % Input:
    %   series: vector de precios (o cualquier serie temporal)
    %   d: orden fraccional (típicamente 0.1 - 0.5; estima con ADF si desconocido)
    %   thresh: umbral para truncar weights (default: 1e-5; valores > 0 truncan coeficientes)
    %
    % Output:
    %   diffSeries: serie diferenciada preservando memoria de largo plazo
    %
    % Referencia: López de Prado, Marcos. "Advances in Financial ML" (2018)
    %   - Combina beneficios de diferenciación (estacionariedad) con memoria (d fraccional)
    %   - Supera a diff() tradicional que pierde correlaciones de largo plazo
    
    % Validar inputs
    if istimetable(series)
        times = series.Time;
        series = series{:, :};
    else
        times = [];
    end
    
    series = series(:);  % Asegurar columna
    series = series(~isnan(series));  % Remover NaNs
    
    if nargin < 3
        thresh = 1e-5;
    end
    
    if d < 0 || d > 2
        warning('d = %.2f está fuera de [0, 2]. Proceder con cuidado.', d);
    end
    
    N = length(series);
    
    % Calcular pesos binomiales (Fixed-Window Fractional Differentiation)
    % w_k = (-1)^k * C(d, k) donde C(d, k) = d! / (k!(d-k)!)
    % Para d no entero: C(d, k) = Gamma(d+1) / (Gamma(k+1) * Gamma(d-k+1))
    
    weights = zeros(N, 1);
    weights(1) = 1;  % w_0 = 1
    
    for k = 2:N
        % Recurrencia: w_k = w_{k-1} * (-(d - k + 1) / k)
        weights(k) = weights(k - 1) * (-(d - k + 1)) / k;
        
        % Truncar si abs(weight) < threshold
        if abs(weights(k)) < thresh
            weights(k:end) = [];
            break;
        end
    end
    
    % Normalizar weights (opcional, para interpretabilidad)
    % weights = weights / sum(weights);  % Descomenta si quieres suma=1
    
    nWeights = length(weights);
    
    % Aplicar diferenciación fraccional
    diffSeries = zeros(N, 1);
    
    for t = nWeights:N
        % Convolución: Y_t = sum_{k=0}^{K} w_k * X_{t-k}
        idx = (t - nWeights + 1):t;
        diffSeries(t) = weights' * series(idx);
    end
    
    % Remover iniciales NaN (primer nWeights-1 valores)
    diffSeries = diffSeries(nWeights:end);
    
    % Si se proporcionó índice temporal, reconstruir timetable
    if ~isempty(times)
        times = times(nWeights:end);
        diffSeries = timetable(times, diffSeries, 'VariableNames', {'Value'});
    end
end
