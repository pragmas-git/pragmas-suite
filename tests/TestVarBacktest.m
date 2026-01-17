classdef TestVarBacktest < matlab.unittest.TestCase
    methods (Test)
        function testZeroViolations(tc)
            ret = (-0.01) * ones(100,1);
            varSeries = (-1.0) * ones(100,1); % very low VaR => no r < v
            res = var_backtest(ret, varSeries, 0.05);
            tc.verifyEqual(res.violations, 0);
            tc.verifyEqual(res.violationRate, 0);
        end

        function testAllViolations(tc)
            ret = (-1.0) * ones(50,1);
            varSeries = (0.0) * ones(50,1); % all r < v
            res = var_backtest(ret, varSeries, 0.05);
            tc.verifyEqual(res.violations, 50);
            tc.verifyEqual(res.violationRate, 1);
        end

        function testEmptyMasked(tc)
            ret = [NaN; NaN];
            varSeries = [NaN; NaN];
            res = var_backtest(ret, varSeries, 0.05);
            tc.verifyEqual(res.T, 0);
            tc.verifyTrue(isnan(res.pValue));
        end
    end
end
