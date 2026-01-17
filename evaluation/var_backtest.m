function res = var_backtest(ret, varSeries, alpha)
%VAR_BACKTEST VaR backtests (Kupiec + Christoffersen).
%   res = VAR_BACKTEST(ret, varSeries, alpha)
%
%   ret: realized returns (vector)
%   varSeries: VaR forecast series (same length)
%   alpha: tail probability (e.g. 0.05)

arguments
    ret (:,1) double
    varSeries (:,1) double
    alpha (1,1) double {mustBeGreaterThan(alpha,0), mustBeLessThan(alpha,1)}
end

ret = ret(:);
varSeries = varSeries(:);
mask = isfinite(ret) & isfinite(varSeries);
r = ret(mask);
v = varSeries(mask);

if isempty(r)
    res = struct();
    res.T = 0;
    res.violations = 0;
    res.violationRate = NaN;
    res.alpha = alpha;
    res.LR_uc = NaN;
    res.pValue = NaN;
    res.pValue_uc = NaN;
    res.n00 = NaN;
    res.n01 = NaN;
    res.n10 = NaN;
    res.n11 = NaN;
    res.LR_ind = NaN;
    res.pValue_ind = NaN;
    res.LR_cc = NaN;
    res.pValue_cc = NaN;
    return;
end

viol = (r < v);
T = numel(viol);
x = sum(viol);

piHat = x / T;

% Kupiec LR_uc
LR_uc = kupiec_lr_uc(x, T, alpha);
p_uc = 1 - chi2cdf(LR_uc, 1);

% Christoffersen independence + conditional coverage
% Transition counts for violations indicator I_t (t=2..T)
% n01: no-viol -> viol, etc.
n00 = 0; n01 = 0; n10 = 0; n11 = 0;
if T >= 2
    I = double(viol);
    I0 = I(1:end-1);
    I1 = I(2:end);
    n00 = sum((I0 == 0) & (I1 == 0));
    n01 = sum((I0 == 0) & (I1 == 1));
    n10 = sum((I0 == 1) & (I1 == 0));
    n11 = sum((I0 == 1) & (I1 == 1));
end

LR_ind = christoffersen_lr_ind(n00, n01, n10, n11, piHat);
p_ind = 1 - chi2cdf(LR_ind, 1);

LR_cc = LR_uc + LR_ind;
p_cc = 1 - chi2cdf(LR_cc, 2);

res = struct();
res.T = T;
res.violations = x;
res.violationRate = piHat;
res.alpha = alpha;
res.LR_uc = LR_uc;
res.pValue = p_uc; % backward-compatible: Kupiec p-value
res.pValue_uc = p_uc;

res.n00 = n00;
res.n01 = n01;
res.n10 = n10;
res.n11 = n11;
res.LR_ind = LR_ind;
res.pValue_ind = p_ind;
res.LR_cc = LR_cc;
res.pValue_cc = p_cc;

end

function LR_uc = kupiec_lr_uc(x, T, alpha)
% Kupiec unconditional coverage likelihood ratio.
if T <= 0
    LR_uc = NaN;
    return;
end
piHat = x / T;
if x == 0 || x == T
    LR_uc = Inf;
    return;
end

logL0 = (T-x) * log(1-alpha) + x * log(alpha);
logL1 = (T-x) * log(1-piHat) + x * log(piHat);
LR_uc = -2 * (logL0 - logL1);
end

function LR_ind = christoffersen_lr_ind(n00, n01, n10, n11, piHat)
% Christoffersen independence test likelihood ratio.
% H0: iid violations with prob piHat
% H1: first-order Markov with probs pi01 and pi11

if any(isnan([n00 n01 n10 n11]))
    LR_ind = NaN;
    return;
end

N0 = n00 + n01;
N1 = n10 + n11;

% If there are no transitions from a state, the Markov model collapses.
if N0 == 0 || N1 == 0
    LR_ind = 0;
    return;
end

pi01 = n01 / N0;
pi11 = n11 / N1;

logL0 = (n00 + n10) * log(max(1-piHat, realmin)) + (n01 + n11) * log(max(piHat, realmin));
logL1 = n00 * log(max(1-pi01, realmin)) + n01 * log(max(pi01, realmin)) + ...
        n10 * log(max(1-pi11, realmin)) + n11 * log(max(pi11, realmin));

LR_ind = -2 * (logL0 - logL1);
end
