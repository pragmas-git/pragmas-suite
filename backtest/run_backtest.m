function bt = run_backtest(retTT, wTT, cfg)
%RUN_BACKTEST Simple backtest given returns and weights.
%   bt = RUN_BACKTEST(retTT, wTT, cfg)
%
%   Aligns by time and computes portfolio returns, equity curve and metrics.

arguments
    retTT timetable
    wTT timetable
    cfg (1,1) struct
end

% Align timetables on intersection of times
[retTT, wTT] = synchronize(retTT, wTT, 'intersection');
R = retTT.Variables;
W = wTT.Variables;

% If weights are signals (0/1), normalize to sum to 1 when possible
rowSum = sum(abs(W), 2);
needsNorm = rowSum > 0;
Wn = W;
Wn(needsNorm,:) = W(needsNorm,:) ./ rowSum(needsNorm);

portRet = sum(Wn .* R, 2, 'omitnan');
portTT = array2timetable(portRet, 'RowTimes', retTT.Time, 'VariableNames', {'PortRet'});

% Equity curve
wealth = cumprod(1 + portRet, 'omitnan');
wealthTT = array2timetable(wealth, 'RowTimes', retTT.Time, 'VariableNames', {'Wealth'});

% Metrics
mu = mean(portRet, 'omitnan');
sig = std(portRet, 'omitnan');
sharpe = (mu / sig) * sqrt(252);

peak = cummax(wealth);
dd = (wealth ./ peak) - 1;
maxDD = min(dd);

turnover = mean(sum(abs(diff(Wn)),2,'omitnan'), 'omitnan');

bt = struct();
bt.returns = portTT;
bt.wealth = wealthTT;
bt.metrics = struct('sharpe', sharpe, 'maxDrawdown', maxDD, 'turnover', turnover);

% Optional persistence
try
    save(fullfile(cfg.resultsDir, 'backtest.mat'), 'bt');
catch
end

end
