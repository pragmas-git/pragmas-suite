function app = run_app()
%RUN_APP Launch the interactive research app.
projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(projectRoot));
app = PragmasSuiteApp();
end
