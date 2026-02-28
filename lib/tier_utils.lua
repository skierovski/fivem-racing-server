local TierUtils = {}

TierUtils.TIER_ORDER = { 'bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist' }

function TierUtils.getTierIndex(tierName, tierOrder)
    tierOrder = tierOrder or TierUtils.TIER_ORDER
    for i, t in ipairs(tierOrder) do
        if t == tierName then return i end
    end
    return 1
end

function TierUtils.getAvailableTiers(playerTier, tierOrder)
    tierOrder = tierOrder or TierUtils.TIER_ORDER
    local playerIndex = TierUtils.getTierIndex(playerTier, tierOrder)

    local available = {}
    for i = 1, playerIndex do
        available[i] = tierOrder[i]
    end
    return available
end

function TierUtils.filterVehiclesByTiers(catalog, availableTiers)
    local tierSet = {}
    for _, t in ipairs(availableTiers) do
        tierSet[t] = true
    end

    local result = {}
    for _, vehicle in ipairs(catalog) do
        if tierSet[vehicle.tier] then
            result[#result + 1] = vehicle
        end
    end
    return result
end

function TierUtils.canAccessTier(playerTier, targetTier, tierOrder)
    tierOrder = tierOrder or TierUtils.TIER_ORDER
    local playerIndex = TierUtils.getTierIndex(playerTier, tierOrder)
    local targetIndex = TierUtils.getTierIndex(targetTier, tierOrder)
    return targetIndex <= playerIndex
end

return TierUtils
