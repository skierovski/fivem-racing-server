local RankedLogic = {}

RankedLogic.DEFAULT_K_FACTOR = 32
RankedLogic.MIN_MMR = 0

RankedLogic.DEFAULT_TIERS = {
    { name = 'bronze',    min = 0,    max = 499   },
    { name = 'silver',    min = 500,  max = 999   },
    { name = 'gold',      min = 1000, max = 1499  },
    { name = 'platinum',  min = 1500, max = 1999  },
    { name = 'diamond',   min = 2000, max = 2499  },
    { name = 'blacklist', min = 2500, max = 99999  },
}

RankedLogic.DEFAULT_TIER_FLOORS = {
    bronze    = 0,
    silver    = 500,
    gold      = 1000,
    platinum  = 1500,
    diamond   = 2000,
    blacklist = 2500,
}

function RankedLogic.expectedScore(ratingA, ratingB)
    return 1.0 / (1.0 + 10 ^ ((ratingB - ratingA) / 400.0))
end

function RankedLogic.calculateMMRChange(winnerMMR, loserMMR, kFactor)
    kFactor = kFactor or RankedLogic.DEFAULT_K_FACTOR

    local expectedWin = RankedLogic.expectedScore(winnerMMR, loserMMR)
    local expectedLose = RankedLogic.expectedScore(loserMMR, winnerMMR)

    local winnerGain = math.floor(kFactor * (1 - expectedWin) + 0.5)
    local loserLoss = math.floor(kFactor * (0 - expectedLose) + 0.5)

    if winnerGain < 5 then winnerGain = 5 end
    if loserLoss > -5 then loserLoss = -5 end

    return winnerGain, loserLoss
end

function RankedLogic.getTierForMMR(mmr, tiers)
    tiers = tiers or RankedLogic.DEFAULT_TIERS
    for i = #tiers, 1, -1 do
        if mmr >= tiers[i].min then
            return tiers[i].name
        end
    end
    return 'bronze'
end

function RankedLogic.applyMatchResult(winnerMMR, loserMMR, loserTier, kFactor, tierFloors)
    kFactor = kFactor or RankedLogic.DEFAULT_K_FACTOR
    tierFloors = tierFloors or RankedLogic.DEFAULT_TIER_FLOORS

    local gain, loss = RankedLogic.calculateMMRChange(winnerMMR, loserMMR, kFactor)

    local newWinnerMMR = math.max(winnerMMR + gain, RankedLogic.MIN_MMR)
    local newLoserMMR = math.max(loserMMR + loss, RankedLogic.MIN_MMR)

    local loserFloor = tierFloors[loserTier] or 0
    if newLoserMMR < loserFloor then
        newLoserMMR = loserFloor
    end

    local newWinnerTier = RankedLogic.getTierForMMR(newWinnerMMR)
    local newLoserTier = RankedLogic.getTierForMMR(newLoserMMR)

    return {
        winnerGain = gain,
        loserLoss = loss,
        newWinnerMMR = newWinnerMMR,
        newLoserMMR = newLoserMMR,
        newWinnerTier = newWinnerTier,
        newLoserTier = newLoserTier,
        winnerPromoted = newWinnerTier ~= RankedLogic.getTierForMMR(winnerMMR),
        loserDemoted = newLoserTier ~= loserTier,
    }
end

return RankedLogic
