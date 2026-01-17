function crps = crps_from_samples(x, y)
%CRPS_FROM_SAMPLES Approximate CRPS using samples.
%   crps = CRPS_FROM_SAMPLES(x, y)
%   x: samples from predictive distribution (n x 1)
%   y: realized scalar
%
%   Uses: CRPS = E|X - y| - 0.5 E|X - X'|

arguments
    x (:,1) double
    y (1,1) double
end

x = x(isfinite(x));
if isempty(x) || ~isfinite(y)
    crps = NaN;
    return;
end

n = numel(x);

% First term
term1 = mean(abs(x - y));

% Second term: E|X - X'| computed in O(n log n) via sorted samples
xs = sort(x);
idx = (1:n)';
% sum_{i,j}|x_i-x_j| = 2*sum_{i=1}^n (2i-n-1)*x_(i)
pairSum = 2 * sum((2*idx - n - 1) .* xs);
term2 = pairSum / (n^2);

crps = term1 - 0.5 * term2;

end
