function res = diebold_mariano(loss1, loss2, h)
%DIEBOLD_MARIANO Diebold-Mariano test for equal predictive accuracy.
%   res = DIEBOLD_MARIANO(loss1, loss2, h)
%   loss1/loss2: vectors of loss values (same length)
%   h: forecast horizon (default 1)
%
%   Returns struct with fields: DM, pValue, meanDiff, n

arguments
    loss1 (:,1) double
    loss2 (:,1) double
    h (1,1) double {mustBeInteger, mustBePositive} = 1
end

loss1 = loss1(:);
loss2 = loss2(:);
mask = isfinite(loss1) & isfinite(loss2);
d = loss1(mask) - loss2(mask);

n = numel(d);
if n < 30
    error('diebold_mariano:TooFewObs', 'Need at least ~30 observations.');
end

% Newey-West style variance estimate (simple, lag = h-1)
lag = max(h-1, 0);

dBar = mean(d);

% autocovariances
gamma0 = mean((d - dBar).^2);
varHat = gamma0;
for k = 1:lag
    gam = mean((d(1+k:end)-dBar).*(d(1:end-k)-dBar));
    varHat = varHat + 2*(1 - k/(lag+1))*gam;
end

DM = dBar / sqrt(varHat / n);

% Asymptotic normal p-value
p = 2*(1 - normcdf(abs(DM), 0, 1));

res = struct('DM', DM, 'pValue', p, 'meanDiff', dBar, 'n', n);

end
