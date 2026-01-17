%MAIN_EXPERIMENT_VAR_CRPS Compare Parametric vs Hybrid (GARCH+KDE)
% Produces VaR backtest and CRPS comparison + saves results.

clear; clc;

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(projectRoot));

cfg = config();
rng(cfg.seed);

if cfg.horizon ~= 1
    warning('main_experiment_var_crps:HorizonNotImplemented', 'This experiment assumes cfg.horizon==1.');
end

% --- Data ---
pricesTT = load_data(cfg);
retsTT = clean_returns(compute_returns(pricesTT, cfg), cfg);
assets = string(cfg.assetsList);

allSumm = table();
allSeries = struct();
allEval = struct();

for a = 1:numel(assets)
    asset = char(assets(a));
    ret1 = retsTT(:, asset);

    % --- Models ---
    par = parametric_pipeline(ret1, cfg);
    hyb = garch_kde_model(ret1, cfg);

    % --- VaR series ---
    zAlpha = norminv(cfg.alpha, 0, 1);
    varPar = par.mu.Variables + par.sigma.Variables * zAlpha;
    varHyb = hyb.var.Variables;

    % --- VaR backtest ---
    varBtPar = var_backtest(ret1.Variables, varPar, cfg.alpha);
    varBtHyb = var_backtest(ret1.Variables, varHyb, cfg.alpha);

    % --- CRPS (parametric, Normal) per time ---
    y = ret1.Variables;
    mu = par.mu.Variables;
    sig = par.sigma.Variables;
    mask = isfinite(y) & isfinite(mu) & isfinite(sig) & sig > 0;
    crpsPar = nan(size(y));

    z = (y(mask) - mu(mask)) ./ sig(mask);
    phi = normpdf(z);
    Phi = normcdf(z);
    crpsPar(mask) = sig(mask) .* ( z .* (2*Phi - 1) + 2*phi - 1/sqrt(pi) );

    % --- CRPS (hybrid) via windowed sampling of residual KDE ---
    muH = hyb.mu.Variables;
    sigH = hyb.sigma.Variables;
    zAll = (y - muH) ./ sigH;

    idx = get_rolling_indices(height(ret1), cfg);
    crpsHyb = nan(size(y));

    nSamp = 800; % trade-off accuracy/speed
    for i = 1:numel(idx)
        trIdx = idx(i).trainIdx;
        teIdx = idx(i).testIdx;

        zTrain = zAll(trIdx);
        zTrain = zTrain(isfinite(zTrain));
        if numel(zTrain) < 200
            continue;
        end

        kde = kde_distribution(zTrain, cfg.alpha, cfg.kde.bandwidth);
        u = rand(nSamp, 1);
        % Inverse-CDF sampling: ensure unique/monotone CDF for interp1
        F = kde.cdf;
        xg = kde.grid;
        F = max(F, 0);
        F = min(F, 1);
        F = cummax(F);
        [Fu, ia] = unique(F, 'stable');
        xU = xg(ia);
        if numel(Fu) < 2
            zSamp = repmat(median(zTrain, 'omitnan'), nSamp, 1);
        else
            % Avoid extrapolation blow-ups: KDE CDF on a finite grid rarely spans [0,1].
            u = max(min(u, Fu(end)), Fu(1));
            zSamp = interp1(Fu, xU, u, 'linear');
        end

        zSorted = sort(zSamp);
        n = numel(zSorted);
        ii = (1:n)';
        pairSum = 2 * sum((2*ii - n - 1) .* zSorted);
        EabsZZ = pairSum / (n^2);

        for j = teIdx
            if ~isfinite(muH(j)) || ~isfinite(sigH(j)) || sigH(j) <= 0 || ~isfinite(y(j))
                continue;
            end
            xSamp = muH(j) + sigH(j) .* zSamp;
            crpsHyb(j) = mean(abs(xSamp - y(j))) - 0.5 * sigH(j) * EabsZZ;
        end
    end

    % --- DM test on CRPS (loss) ---
    dm = struct('DM', NaN, 'pValue', NaN, 'meanDiff', NaN, 'n', NaN);
    try
        dm = diebold_mariano(crpsPar, crpsHyb, cfg.horizon);
    catch
    end

    % --- Summaries ---
    crpsMeanPar = mean(crpsPar, 'omitnan');
    crpsMeanHyb = mean(crpsHyb, 'omitnan');

    row = table(string(asset), cfg.alpha, crpsMeanPar, crpsMeanHyb, ...
        varBtPar.violationRate, varBtHyb.violationRate, ...
        varBtPar.pValue, varBtHyb.pValue, ...
        varBtPar.pValue_cc, varBtHyb.pValue_cc, ...
        dm.DM, dm.pValue, dm.meanDiff, dm.n, ...
        'VariableNames', {'Asset','Alpha','CRPS_Parametric','CRPS_Hybrid', ...
        'VaRRate_Parametric','VaRRate_Hybrid','KupiecP_Parametric','KupiecP_Hybrid', ...
        'ChristoffersenP_Parametric','ChristoffersenP_Hybrid', ...
        'DM_CRPS','DM_pValue','DM_meanDiff','DM_n'});

    allSumm = [allSumm; row]; %#ok<AGROW>

    % Series & eval per asset
    allSeries.(asset) = struct();
    allSeries.(asset).crps = timetable(ret1.Time, crpsPar, crpsHyb, 'VariableNames', {'CRPS_Parametric','CRPS_Hybrid'});
    allSeries.(asset).var = timetable(ret1.Time, varPar, varHyb, 'VariableNames', {'VaR_Parametric','VaR_Hybrid'});

    allEval.(asset) = struct('varBacktest', struct('parametric', varBtPar, 'hybrid', varBtHyb), 'dmCRPS', dm);
end

% --- Package results ---
results = struct();
results.meta = struct('timestamp', datetime('now'), 'entrypoint', 'main_experiment_var_crps', 'seed', cfg.seed);
results.cfg = cfg;
results.models = struct('parametric', struct(), 'hybrid', struct(), 'nonparametric', struct());
results.series = allSeries;
results.evaluation = struct('byAsset', allEval, 'summary', allSumm);

% --- Persist ---
outPath = save_results(results, cfg, "experiment_var_crps");

% Also write a CSV summary for thesis tables
try
    if ~exist(cfg.resultsDir, 'dir'); mkdir(cfg.resultsDir); end
    writetable(allSumm, fullfile(cfg.resultsDir, 'summary_var_crps.csv'));
catch
end

fprintf('Saved experiment: %s\n', outPath);
disp(allSumm);

% Optional quick plots (safe to comment out if running headless)
try
    if ~exist(cfg.resultsDir, 'dir'); mkdir(cfg.resultsDir); end
    % quick plots for the first asset only (lightweight)
    a0 = char(assets(1));
    s = results.series.(a0);
    ret0 = retsTT(:, a0);

    f1 = figure('Name','CRPS Comparison');
    plot(s.crps.Time, s.crps.CRPS_Parametric, 'DisplayName','Parametric'); hold on;
    plot(s.crps.Time, s.crps.CRPS_Hybrid, 'DisplayName','Hybrid');
    legend('Location','best'); grid on; title(sprintf('CRPS (lower is better): %s', a0));
    saveas(f1, fullfile(cfg.resultsDir, sprintf('crps_timeseries_%s.png', a0)));

    f2 = figure('Name','VaR Comparison');
    plot(ret0.Time, ret0.Variables, 'DisplayName','Return'); hold on;
    plot(s.var.Time, s.var.VaR_Parametric, 'DisplayName','VaR Parametric');
    plot(s.var.Time, s.var.VaR_Hybrid, 'DisplayName','VaR Hybrid');
    legend('Location','best'); grid on; title(sprintf('VaR @ alpha=%.2f: %s', cfg.alpha, a0));
    saveas(f2, fullfile(cfg.resultsDir, sprintf('var_timeseries_%s.png', a0)));
catch
end
