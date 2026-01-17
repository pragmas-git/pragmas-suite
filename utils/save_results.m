function outPath = save_results(results, cfg, tag)
%SAVE_RESULTS Persist a run to results/ with consistent naming.
%   outPath = SAVE_RESULTS(results, cfg, tag)

arguments
    results (1,1) struct
    cfg (1,1) struct
    tag string = "run"
end

if ~isfield(cfg, 'resultsDir')
    error('save_results:MissingResultsDir', 'cfg.resultsDir is required.');
end

if ~exist(cfg.resultsDir, 'dir')
    mkdir(cfg.resultsDir);
end

ts = datestr(now, 'yyyymmdd_HHMMSS');
outPath = fullfile(cfg.resultsDir, sprintf('%s_%s.mat', tag, ts));

save(outPath, 'results');

end
