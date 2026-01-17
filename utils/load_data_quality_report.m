function report = load_data_quality_report(cfg)
%LOAD_DATA_QUALITY_REPORT Load persisted data quality report if present.

arguments
    cfg (1,1) struct = config()
end

report = struct();

matPath = fullfile(cfg.resultsDir, 'data_quality_report.mat');
if exist(matPath, 'file') == 2
    S = load(matPath);
    if isfield(S, 'report')
        report = S.report;
    end
    if ~isfield(report, 'dataQualitySummary') && isfield(S, 'dataQualitySummary')
        report.dataQualitySummary = S.dataQualitySummary;
    end
    return;
end

procPath = fullfile(cfg.dataProcessedDir, 'fx_daily_close.mat');
if exist(procPath, 'file') == 2
    S = load(procPath);
    if isfield(S, 'report')
        report = S.report;
    end
end

end
