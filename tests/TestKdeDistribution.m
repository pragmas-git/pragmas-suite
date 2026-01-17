classdef TestKdeDistribution < matlab.unittest.TestCase
    methods (Test)
        function testCdfMonotoneAndBounded(tc)
            if exist('ksdensity','file') ~= 2 || ~license('test','Statistics_Toolbox')
                tc.assumeFail('Statistics and Machine Learning Toolbox (ksdensity) not available.');
            end

            rng(123);
            z = randn(2000,1);
            kde = kde_distribution(z, 0.05, []);

            tc.verifyGreaterThanOrEqual(min(kde.cdf), 0);
            tc.verifyLessThanOrEqual(max(kde.cdf), 1);
            tc.verifyTrue(all(diff(kde.cdf) >= -1e-12));

            tc.verifyGreaterThanOrEqual(kde.var, min(kde.grid));
            tc.verifyLessThanOrEqual(kde.var, max(kde.grid));
        end
    end
end
