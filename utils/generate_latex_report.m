function out = generate_latex_report(results, cfg, opts)
%GENERATE_LATEX_REPORT Generate a LaTeX report (+ optional PDF build).

arguments
    results (1,1) struct
    cfg (1,1) struct = config()
    opts.outputDir (1,1) string = string(cfg.resultsDir)
    opts.templatePath (1,1) string = string(fullfile(cfg.projectRoot, 'report', 'templates', 'report_template.tex'))
    opts.compile (1,1) logical = true
end

ts = datestr(datetime('now'), 'yyyymmdd_HHMMSS');
outDir = fullfile(opts.outputDir, "latex_report_" + ts);
if ~exist(outDir, 'dir'); mkdir(outDir); end

% Export figures used in report
figDir = fullfile(outDir, 'figures');
figPaths = export_report_figures(results, figDir);

% Build LaTeX table from summary
summaryTbl = results.evaluation.summary;
summaryLatex = table_to_latex(summaryTbl);

cfgLatex = sprintf(['\\begin{tabular}{ll}\n',...
    '\\toprule\n',...
    'Seed & %d \\\\ \n',...
    'Alpha & %.4f \\\\ \n',...
    'Train/Test/Step & %d / %d / %d \\\\ \n',...
    '\\bottomrule\n',...
    '\\end{tabular}\n'], ...
    cfg.seed, cfg.alpha, cfg.rolling.train, cfg.rolling.test, cfg.rolling.step);

% Build figure include blocks
assets = string(fieldnames(figPaths));
figBlock = "";
for a = 1:numel(assets)
    asset = assets(a);
    p1 = "";
    p2 = "";
    try
        p1 = string(figPaths.(char(asset)).crps);
    catch
    end
    try
        p2 = string(figPaths.(char(asset)).var);
    catch
    end

    if strlength(p1) > 0
        rel1 = replace(p1, outDir + filesep, "");
        figBlock = figBlock + sprintf('\\subsection*{CRPS: %s}\n\\includegraphics[width=\\linewidth]{%s}\n\n', asset, rel1);
    end
    if strlength(p2) > 0
        rel2 = replace(p2, outDir + filesep, "");
        figBlock = figBlock + sprintf('\\subsection*{VaR: %s}\n\\includegraphics[width=\\linewidth]{%s}\n\n', asset, rel2);
    end
end

% Load template
if exist(opts.templatePath, 'file') ~= 2
    error('generate_latex_report:MissingTemplate', 'Missing template: %s', opts.templatePath);
end
tex = fileread(opts.templatePath);
tex = strrep(tex, '%%DATE%%', datestr(datetime('now'), 'yyyy-mm-dd HH:MM'));
tex = strrep(tex, '%%CFG_TABLE%%', cfgLatex);
tex = strrep(tex, '%%SUMMARY_TABLE%%', summaryLatex);
tex = strrep(tex, '%%FIGURES%%', figBlock);

texPath = fullfile(outDir, 'report.tex');
fid = fopen(texPath, 'w');
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, tex);

out = struct();
out.outDir = outDir;
out.texPath = texPath;
out.pdfPath = fullfile(outDir, 'report.pdf');
out.pdflatexLog = '';
out.compiled = false;

if ~opts.compile
    return;
end

pdflatex = find_pdflatex();
if strlength(pdflatex) == 0
    out.pdflatexLog = 'pdflatex not found on PATH. Skipping PDF compilation.';
    return;
end

cmd = sprintf('"%s" -interaction=nonstopmode -halt-on-error -output-directory "%s" "%s"', pdflatex, outDir, texPath);
[st1, out1] = system(cmd);
[st2, out2] = system(cmd);
out.pdflatexLog = out1 + newline + out2;

out.compiled = (st1 == 0) && (st2 == 0) && (exist(out.pdfPath, 'file') == 2);
end

function pdflatex = find_pdflatex()
%FIND_PDFLATEX Find pdflatex on PATH.
if ispc
    [st, out] = system('where pdflatex');
else
    [st, out] = system('which pdflatex');
end
if st ~= 0
    pdflatex = "";
    return;
end
lines = splitlines(string(out));
lines = strtrim(lines);
lines = lines(lines ~= "");
if isempty(lines)
    pdflatex = "";
else
    pdflatex = lines(1);
end
end

function s = table_to_latex(T)
%TABLE_TO_LATEX Minimal LaTeX tabular for a MATLAB table.
varNames = string(T.Properties.VariableNames);
colSpec = repmat('r', 1, width(T));
colSpec(1) = 'l';

s = sprintf('\\begin{tabular}{%s}\n\\toprule\n', colSpec);

% Header
for j = 1:numel(varNames)
    s = s + escape_latex(varNames(j));
    if j < numel(varNames)
        s = s + ' & ';
    else
        s = s + sprintf('\\\\ \\midrule\n');
    end
end

% Rows
for i = 1:height(T)
    for j = 1:width(T)
        v = T{i,j};
        s = s + format_cell(v);
        if j < width(T)
            s = s + ' & ';
        else
            s = s + sprintf('\\\\\n');
        end
    end
end

s = s + sprintf('\\bottomrule\n\\end{tabular}\n');
end

function out = format_cell(v)
if isstring(v) || ischar(v)
    out = escape_latex(string(v));
    return;
end
if isnumeric(v)
    if isscalar(v)
        if isfinite(v)
            out = sprintf('%.6g', v);
        else
            out = 'NaN';
        end
    else
        out = escape_latex(string(mat2str(v)));
    end
    return;
end
if islogical(v)
    out = string(v);
    return;
end
out = escape_latex(string(v));
end

function t = escape_latex(x)
%ESCAPE_LATEX Escape characters that break LaTeX.
x = string(x);
repl = [ ...
    "\\", "\\textbackslash{}"; ...
    "_", "\\_"; ...
    "%", "\\%"; ...
    "&", "\\&"; ...
    "#", "\\#"; ...
    "{", "\\{"; ...
    "}", "\\}"; ...
    "^", "\\textasciicircum{}"; ...
    "~", "\\textasciitilde{}" ...
];

t = x;
for k = 1:size(repl,1)
    t = replace(t, repl(k,1), repl(k,2));
end
end
