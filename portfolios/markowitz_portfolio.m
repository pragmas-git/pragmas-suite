function wTT = markowitz_portfolio(muTT, retTT, cfg)
%MARKOWITZ_PORTFOLIO Mean-variance weights (rolling rebalancing scaffold).
%   wTT = MARKOWITZ_PORTFOLIO(muTT, retTT, cfg)
%
%   Inputs:
%     muTT  timetable with expected returns per asset (aligned to retTT times)
%     retTT timetable of realized returns (used to estimate covariance in-window)
%
%   Output:
%     wTT timetable of weights per asset.

arguments
    muTT timetable
    retTT timetable
    cfg (1,1) struct
end

assets = retTT.Properties.VariableNames;
numAssets = numel(assets);

idx = get_rolling_indices(height(retTT), cfg);

W = nan(height(retTT), numAssets);

for i = 1:numel(idx)
    trIdx = idx(i).trainIdx;
    teIdx = idx(i).testIdx;

    R = retTT.Variables(trIdx,:);
    R = R(all(isfinite(R),2),:);

    if size(R,1) < 50
        continue;
    end

    Sigma = cov(R, 1); % population cov
    mu = muTT.Variables(idx(i).rebalanceTimeIndex,:); % row vector

    if any(~isfinite(mu)) || any(~isfinite(Sigma(:)))
        continue;
    end

    % Solve: minimize (lambda/2) w' Sigma w - mu w
    % s.t. sum(w)=1, 0<=w<=maxWeight (no short) unless allowShort
    lambda = cfg.portfolio.riskAversion;

    if exist('quadprog', 'file') == 2
        H = lambda * (Sigma + 1e-8*eye(numAssets));
        f = -mu(:);

        Aeq = ones(1, numAssets);
        beq = 1;

        if cfg.portfolio.allowShort
            lb = -cfg.portfolio.maxWeight * ones(numAssets,1);
            ub =  cfg.portfolio.maxWeight * ones(numAssets,1);
        else
            lb = zeros(numAssets,1);
            ub = cfg.portfolio.maxWeight * ones(numAssets,1);
        end

        try
            opts = optimoptions('quadprog', 'Display', 'off');
            w = quadprog(H, f, [], [], Aeq, beq, lb, ub, [], opts);
        catch
            w = [];
        end
    else
        w = [];
    end

    if isempty(w)
        if cfg.portfolio.fallbackEqualWeight
            w = ones(numAssets,1)/numAssets;
        else
            continue;
        end
    end

    % Hold weights constant over test window (rebalance schedule)
    W(teIdx,:) = repmat(w(:)', numel(teIdx), 1);
end

wTT = array2timetable(W, 'RowTimes', retTT.Time, 'VariableNames', assets);

end
