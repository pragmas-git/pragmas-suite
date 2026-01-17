function figPaths = export_report_figures(results, outDir)
%EXPORT_REPORT_FIGURES Export key figures used in the LaTeX report.

arguments
    results (1,1) struct
    outDir (1,1) string
end

if ~exist(outDir, 'dir'); mkdir(outDir); end

figPaths = struct();

assets = string(fieldnames(results.series));
for a = 1:numel(assets)
    asset = assets(a);
    s = results.series.(char(asset));

    % CRPS time series
    try
        f = figure('Visible','off');
        plot(s.crps.Time, s.crps.CRPS_Parametric, 'DisplayName','Parametric'); hold on;
        plot(s.crps.Time, s.crps.CRPS_Hybrid, 'DisplayName','Hybrid');
        grid on; legend('Location','best');
        title(sprintf('CRPS: %s', asset));
        p = fullfile(outDir, sprintf('crps_%s.pdf', asset));
        exportgraphics(f, p, 'ContentType','vector');
        close(f);
        figPaths.(char(asset)).crps = p;
    catch
    end

    % VaR time series
    try
        f = figure('Visible','off');
        plot(s.var.Time, s.var.VaR_Parametric, 'DisplayName','VaR Parametric'); hold on;
        plot(s.var.Time, s.var.VaR_Hybrid, 'DisplayName','VaR Hybrid');
        grid on; legend('Location','best');
        title(sprintf('VaR: %s', asset));
        p = fullfile(outDir, sprintf('var_%s.pdf', asset));
        exportgraphics(f, p, 'ContentType','vector');
        close(f);
        figPaths.(char(asset)).var = p;
    catch
    end
end

end
