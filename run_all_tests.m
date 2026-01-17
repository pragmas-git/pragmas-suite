function results = run_all_tests()
%RUN_ALL_TESTS Run full matlab.unittest suite for pragmas-suite.

projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(projectRoot));

suite = testsuite(fullfile(projectRoot, 'tests'));
runner = testrunner('textoutput');
results = runner.run(suite);

if any([results.Failed])
    error('run_all_tests:Failed', 'Some tests failed.');
end

end
