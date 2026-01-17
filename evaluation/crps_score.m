function s = crps_score(y, mu, sigma)
%CRPS_SCORE CRPS for a Normal predictive distribution.
%   s = CRPS_SCORE(y, mu, sigma)
%
%   y, mu, sigma can be vectors of equal length.
%   Returns mean CRPS.

arguments
    y (:,1) double
    mu (:,1) double
    sigma (:,1) double
end

y = y(:); mu = mu(:); sigma = sigma(:);
mask = isfinite(y) & isfinite(mu) & isfinite(sigma) & sigma > 0;
y = y(mask); mu = mu(mask); sigma = sigma(mask);

z = (y - mu) ./ sigma;
phi = normpdf(z);
Phi = normcdf(z);

% Closed form CRPS for Normal:
% CRPS = sigma * [ z*(2*Phi-1) + 2*phi - 1/sqrt(pi) ]
crps = sigma .* ( z .* (2*Phi - 1) + 2*phi - 1/sqrt(pi) );

s = mean(crps, 'omitnan');

end
