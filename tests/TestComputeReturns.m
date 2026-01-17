classdef TestComputeReturns < matlab.unittest.TestCase
    methods (Test)
        function testLogReturnsBasic(tc)
            t = datetime(2020,1,1) + days(0:3);
            p = [100; 110; 121; 133.1];
            pricesTT = timetable(t(:), p, 'VariableNames', {'EURUSD'});

            cfg = config();
            cfg.fx.invertUSDpairs = strings(0,1);

            retsTT = compute_returns(pricesTT, cfg);
            expR = diff(log(p));
            tc.verifyEqual(retsTT.EURUSD, expR, 'AbsTol', 1e-12);
        end

        function testInvertUsdPair(tc)
            t = datetime(2020,1,1) + days(0:2);
            p = [100; 105; 110];
            pricesTT = timetable(t(:), p, 'VariableNames', {'USDJPY'});

            cfg = config();
            cfg.fx.invertUSDpairs = "USDJPY";

            retsTT = compute_returns(pricesTT, cfg);
            expR = -diff(log(p));
            tc.verifyEqual(retsTT.USDJPY, expR, 'AbsTol', 1e-12);
        end
    end
end
