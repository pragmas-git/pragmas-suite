function kde = kde_distribution(z, alpha, bandwidth)
%KDE_DISTRIBUTION Fit KDE to standardized residuals and compute tail risk.
%   kde = KDE_DISTRIBUTION(z, alpha, bandwidth)
%   kde contains grid/pdf/cdf and VaR/CVaR for the residual distribution.

arguments
    z (:,1) double
    alpha (1,1) double {mustBeGreaterThan(alpha,0), mustBeLessThan(alpha,1)}
    bandwidth double = []
end

z = z(isfinite(z));
if numel(z) < 50
    error('kde_distribution:TooFewObs', 'Need more residuals for KDE.');
end

if exist('ksdensity', 'file') ~= 2 || ~license('test', 'Statistics_Toolbox')
    error('kde_distribution:MissingDependency', 'ksdensity (Statistics and Machine Learning Toolbox) is required for KDE.');
end

% Evaluate KDE on a robust grid
lo = quantile(z, 0.001);
hi = quantile(z, 0.999);
xs = linspace(lo, hi, 2000)';

if isempty(bandwidth)
    [f, xi] = ksdensity(z, xs, 'Function', 'pdf');
    [F, ~]  = ksdensity(z, xs, 'Function', 'cdf');
else
    [f, xi] = ksdensity(z, xs, 'Function', 'pdf', 'Bandwidth', bandwidth);
    [F, ~]  = ksdensity(z, xs, 'Function', 'cdf', 'Bandwidth', bandwidth);
end

% VaR at alpha (left tail)
% Ensure monotone/unique sample points for interpolation
F = max(F, 0);
F = min(F, 1);
F = cummax(F);
[Fu, ia] = unique(F, 'stable');
xiU = xi(ia);
if numel(Fu) < 2
    varZ = quantile(z, alpha);
else
    varZ = interp1(Fu, xiU, alpha, 'linear', 'extrap');
end

% CVaR (Expected Shortfall) via numerical integration on left tail
mask = xi <= varZ;
if ~any(mask)
    cvarZ = varZ;
else
    % Approx E[z | z<=VaR] ~ integral z f(z) dz / alpha over left tail
    dz = xi(2) - xi(1);
    tailMass = sum(f(mask))*dz;
    tailMass = max(tailMass, eps);
    cvarZ = sum(xi(mask).*f(mask))*dz / tailMass;
end

kde = struct();
kde.grid = xi;
kde.pdf = f;
kde.cdf = F;
kde.var = varZ;
kde.cvar = cvarZ;

end
