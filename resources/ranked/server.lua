-- ============================================================
-- Ranked system: Elo-based MMR, tier promotion/demotion, BlackList
-- ============================================================

local RankedConfig = {
    K_FACTOR = 50,
    K_PLACEMENT = 100,
    PLACEMENT_MATCHES = 3,
    MIN_MMR = 0,

    TIERS = {
        { name = 'bronze',    min = 0,    max = 500  },
        { name = 'silver',    min = 501,  max = 650  },
        { name = 'gold',      min = 651,  max = 800  },
        { name = 'platinum',  min = 801,  max = 950  },
        { name = 'diamond',   min = 951,  max = 1100 },
        { name = 'blacklist', min = 1101, max = 99999 },
    },

    BLACKLIST_SIZE = 20,
}

-- ========================
-- Elo calculation
-- ========================

--- Calculate expected score (probability of winning)
local function expectedScore(ratingA, ratingB)
    return 1.0 / (1.0 + 10 ^ ((ratingB - ratingA) / 400.0))
end

--- Get K-factor for a player (higher during placement for faster calibration)
function getKFactor(player)
    local totalMatches = (player.wins or 0) + (player.losses or 0)
    if totalMatches < RankedConfig.PLACEMENT_MATCHES then
        return RankedConfig.K_PLACEMENT
    end
    return RankedConfig.K_FACTOR
end

--- Calculate MMR changes for a match (per-player K-factor)
--- @param winnerMMR number
--- @param loserMMR number
--- @param winnerK number|nil
--- @param loserK number|nil
--- @return number winnerGain, number loserLoss
function CalculateMMRChange(winnerMMR, loserMMR, winnerK, loserK)
    winnerK = winnerK or RankedConfig.K_FACTOR
    loserK = loserK or RankedConfig.K_FACTOR

    local expectedWin = expectedScore(winnerMMR, loserMMR)
    local expectedLose = expectedScore(loserMMR, winnerMMR)

    local winnerGain = math.floor(winnerK * (1 - expectedWin) + 0.5)
    local loserLoss = math.floor(loserK * (0 - expectedLose) + 0.5)

    if winnerGain < 5 then winnerGain = 5 end
    if loserLoss > -5 then loserLoss = -5 end

    return winnerGain, loserLoss
end

-- ========================
-- Tier determination
-- ========================

function GetTierForMMR(mmr)
    for i = #RankedConfig.TIERS, 1, -1 do
        if mmr >= RankedConfig.TIERS[i].min then
            return RankedConfig.TIERS[i].name
        end
    end
    return 'bronze'
end

-- ========================
-- Process match result
-- ========================

local CROSS_TIER_CONFIG = {
    UNDERDOG_WIN_BONUS = 1.3,
    FAVORED_LOSE_PENALTY = 1.3,
    FAVORED_WIN_REDUCTION = 0.8,
    UNDERDOG_LOSE_REDUCTION = 0.8,
}

--- Call this after a ranked match ends
--- @param winnerId string - player identifier
--- @param loserId string - player identifier
--- @param winnerRole string - 'chaser' or 'runner'
--- @param durationSeconds number
--- @param isCrossTier boolean|nil
local function calculateMatchMMR(winner, loser, isCrossTier)
    local winnerK = getKFactor(winner)
    local loserK = getKFactor(loser)
    local gain, loss = CalculateMMRChange(winner.mmr, loser.mmr, winnerK, loserK)

    if isCrossTier then
        local winnerIsLowerTier = (winner.mmr < loser.mmr)
        if winnerIsLowerTier then
            gain = math.floor(gain * CROSS_TIER_CONFIG.UNDERDOG_WIN_BONUS + 0.5)
            loss = math.floor(loss * CROSS_TIER_CONFIG.FAVORED_LOSE_PENALTY + 0.5)
        else
            gain = math.floor(gain * CROSS_TIER_CONFIG.FAVORED_WIN_REDUCTION + 0.5)
            loss = math.floor(loss * CROSS_TIER_CONFIG.UNDERDOG_LOSE_REDUCTION + 0.5)
        end
        if gain < 5 then gain = 5 end
        if loss > -5 then loss = -5 end
    end

    return gain, loss
end

local function updatePlayerRankedData(winnerId, loserId, winnerRole, gain, loss, newWinnerMMR, newWinnerTier, newLoserMMR, newLoserTier, durationSeconds)
    exports.oxmysql:execute(
        'UPDATE players SET mmr = ?, tier = ?, wins = wins + 1 WHERE identifier = ?',
        { newWinnerMMR, newWinnerTier, winnerId }
    )
    exports.oxmysql:execute(
        'UPDATE players SET mmr = ?, tier = ?, losses = losses + 1 WHERE identifier = ?',
        { newLoserMMR, newLoserTier, loserId }
    )

    local chaserRole = winnerRole == 'chaser' and winnerId or loserId
    local runnerRole = winnerRole == 'runner' and winnerId or loserId

    exports.oxmysql:execute(
        'UPDATE players SET chases_played = chases_played + 1 WHERE identifier = ?',
        { chaserRole }
    )
    exports.oxmysql:execute(
        'UPDATE players SET escapes_played = escapes_played + 1 WHERE identifier = ?',
        { runnerRole }
    )

    local chaserMMRChange = chaserRole == winnerId and gain or loss
    local runnerMMRChange = runnerRole == winnerId and gain or loss

    exports.oxmysql:execute(
        [[INSERT INTO match_history
            (mode, chaser_ids, runner_id, winner_role, winner_id,
             duration_seconds, mmr_change_chaser, mmr_change_runner)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
        {
            'ranked',
            json.encode({ chaserRole }),
            runnerRole,
            winnerRole,
            winnerId,
            durationSeconds,
            chaserMMRChange,
            runnerMMRChange,
        }
    )
end

local function notifyMatchResult(identifier, result, mmrChange, newMMR, newTier, oldTier, player)
    local source = getSourceFromIdentifier(identifier)
    if not source then return end

    local totalAfter = (player.wins or 0) + (player.losses or 0) + 1

    TriggerClientEvent('blacklist:matchResult', source, {
        result = result,
        mmrChange = mmrChange,
        newMMR = newMMR,
        newTier = newTier,
        oldTier = oldTier,
        promoted = result == 'win' and newTier ~= oldTier or nil,
        demoted = result == 'loss' and newTier ~= oldTier or nil,
        isPlacement = totalAfter <= RankedConfig.PLACEMENT_MATCHES,
        placementMatch = math.min(totalAfter, RankedConfig.PLACEMENT_MATCHES),
        placementTotal = RankedConfig.PLACEMENT_MATCHES,
    })
end

function ProcessRankedResult(winnerId, loserId, winnerRole, durationSeconds, isCrossTier)
    exports.oxmysql:execute(
        'SELECT identifier, mmr, tier, wins, losses, chases_played, escapes_played FROM players WHERE identifier IN (?, ?)',
        { winnerId, loserId },
        function(results)
            if not results or #results < 2 then
                print('[Ranked] ^1Error: could not find both players^0')
                return
            end

            local winner, loser
            for _, p in ipairs(results) do
                if p.identifier == winnerId then winner = p
                elseif p.identifier == loserId then loser = p
                end
            end

            if not winner or not loser then return end

            local gain, loss = calculateMatchMMR(winner, loser, isCrossTier)
            local newWinnerMMR = math.max(winner.mmr + gain, RankedConfig.MIN_MMR)
            local newLoserMMR = math.max(loser.mmr + loss, RankedConfig.MIN_MMR)
            local newWinnerTier = GetTierForMMR(newWinnerMMR)
            local newLoserTier = GetTierForMMR(newLoserMMR)

            updatePlayerRankedData(winnerId, loserId, winnerRole, gain, loss,
                newWinnerMMR, newWinnerTier, newLoserMMR, newLoserTier, durationSeconds)

            notifyMatchResult(winnerId, 'win', gain, newWinnerMMR, newWinnerTier, winner.tier, winner)
            notifyMatchResult(loserId, 'loss', loss, newLoserMMR, newLoserTier, loser.tier, loser)

            print(('[Ranked]%s Match result: %s (+%d -> %d %s) beat %s (%d -> %d %s)'):format(
                isCrossTier and ' [CROSS-TIER]' or '',
                winnerId, gain, newWinnerMMR, newWinnerTier,
                loserId, loss, newLoserMMR, newLoserTier
            ))
        end
    )
end

-- ========================
-- BlackList query
-- ========================

function GetBlacklistTop20(callback)
    exports.oxmysql:execute(
        'SELECT identifier, name, mmr, tier, wins, losses FROM players ORDER BY mmr DESC LIMIT ?',
        { RankedConfig.BLACKLIST_SIZE },
        function(result)
            if not result then
                print('[Ranked] ^1DB error fetching blacklist top 20^0')
                callback({})
                return
            end
            callback(result)
        end
    )
end

-- ========================
-- Exports (for other resources to call)
-- ========================

exports('CalculateMMRChange', CalculateMMRChange)
exports('GetTierForMMR', GetTierForMMR)
exports('ProcessRankedResult', ProcessRankedResult)
exports('GetBlacklistTop20', GetBlacklistTop20)

-- ========================
-- Utility
-- ========================

function getSourceFromIdentifier(identifier)
    for _, playerId in ipairs(GetPlayers()) do
        for _, id in ipairs(GetPlayerIdentifiers(playerId)) do
            if id == identifier then
                return tonumber(playerId)
            end
        end
    end
    return nil
end

print('[Ranked] ^2Tier system loaded^0')
print('[Ranked] Tiers: Bronze(0-500) Silver(501-650) Gold(651-800) Platinum(801-950) Diamond(951-1100) BlackList(1101+, Top 20)')
print(('[Ranked] K-Factor: %d (placement: %d, first %d matches)'):format(RankedConfig.K_FACTOR, RankedConfig.K_PLACEMENT, RankedConfig.PLACEMENT_MATCHES))
