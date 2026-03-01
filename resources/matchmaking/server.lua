-- ============================================================
-- Matchmaking: ranked 1v1 queue + normal chase queue
-- ============================================================

local Config = {
    RANKED_MMR_RANGE_INITIAL = 100,
    RANKED_MMR_RANGE_EXPAND = 50,
    RANKED_MMR_RANGE_MAX = 500,
    RANKED_EXPAND_INTERVAL = 10000, -- ms between range expansions

    NORMAL_MIN_CHASERS = 1,
    NORMAL_MAX_CHASERS = 4,

    MATCH_CHECK_INTERVAL = 3000, -- ms between queue checks
}

-- Queue storage
local rankedQueue = {} -- { source, identifier, mmr, tier, joinedAt, searchRange }
local normalRunnerQueue = {} -- { source, identifier, mmr, tier }
local normalChaserQueue = {} -- { source, identifier, mmr, tier }

-- Player states
local playerStates = {} -- [source] = 'menu' | 'ranked_queue' | 'normal_runner_queue' | 'normal_chaser_queue' | 'in_match' | 'freeroam'

-- Bank spawn locations for normal mode
local BANK_LOCATIONS = {
    { x = 150.26,   y = -1040.20, z = 29.37,  heading = 340.0, name = 'Fleeca Bank - Legion Square' },
    { x = -1212.98, y = -330.52,  z = 37.78,  heading = 27.0,  name = 'Fleeca Bank - Rockford Hills' },
    { x = -2962.58, y = 482.63,   z = 15.70,  heading = 87.0,  name = 'Fleeca Bank - Banham Canyon' },
    { x = 314.19,   y = -278.73,  z = 54.17,  heading = 340.0, name = 'Fleeca Bank - Alta' },
    { x = -351.53,  y = -49.53,   z = 49.04,  heading = 340.0, name = 'Fleeca Bank - Burton' },
    { x = 253.36,   y = 228.15,   z = 101.68, heading = 160.0, name = 'Pacific Standard Bank' },
}

-- ========================
-- Join / leave queue
-- ========================

local TIER_ORDER = { 'bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist' }
local TIER_INDEX = {}
for i, name in ipairs(TIER_ORDER) do TIER_INDEX[name] = i end

RegisterNetEvent('blacklist:joinQueue')
AddEventHandler('blacklist:joinQueue', function(mode, crossTier)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    -- Prevent double-queue
    if playerStates[source] and playerStates[source] ~= 'menu' then
        TriggerClientEvent('blacklist:queueUpdate', source, { status = 'error', message = 'Already in queue or match' })
        return
    end

    -- Get player data from DB
    exports.oxmysql:execute(
        'SELECT mmr, tier, chases_played, escapes_played FROM players WHERE identifier = ?',
        { identifier },
        function(result)
            if not result or not result[1] then return end
            local player = result[1]

            if mode == 'ranked' then
                table.insert(rankedQueue, {
                    source = source,
                    identifier = identifier,
                    mmr = player.mmr,
                    tier = player.tier,
                    crossTier = crossTier == true,
                    chases = player.chases_played or 0,
                    escapes = player.escapes_played or 0,
                    joinedAt = GetGameTimer(),
                    searchRange = Config.RANKED_MMR_RANGE_INITIAL,
                })
                playerStates[source] = 'ranked_queue'
                TriggerClientEvent('blacklist:queueUpdate', source, {
                    status = 'waiting',
                    message = crossTier and 'Searching for cross-tier opponent...' or 'Searching for ranked opponent...'
                })
                print(('[Matchmaking] %s joined ranked queue (MMR: %d, crossTier: %s)'):format(
                    GetPlayerName(source), player.mmr, tostring(crossTier == true)))

            elseif mode == 'normal' then
                -- Assign role based on lifetime balance (fewer escapes = runner)
                local isRunner = (player.escapes_played or 0) <= (player.chases_played or 0)

                -- If no runners in queue, force runner
                if #normalRunnerQueue == 0 then
                    isRunner = true
                end

                if isRunner then
                    table.insert(normalRunnerQueue, {
                        source = source,
                        identifier = identifier,
                        mmr = player.mmr,
                        tier = player.tier,
                    })
                    playerStates[source] = 'normal_runner_queue'
                    TriggerClientEvent('blacklist:queueUpdate', source, {
                        status = 'waiting',
                        message = 'Waiting as runner... need chasers'
                    })
                else
                    table.insert(normalChaserQueue, {
                        source = source,
                        identifier = identifier,
                        mmr = player.mmr,
                        tier = player.tier,
                    })
                    playerStates[source] = 'normal_chaser_queue'
                    TriggerClientEvent('blacklist:queueUpdate', source, {
                        status = 'waiting',
                        message = 'Waiting as chaser... need runner'
                    })
                end
                print(('[Matchmaking] %s joined normal queue as %s'):format(
                    GetPlayerName(source), isRunner and 'runner' or 'chaser'))
            end
        end
    )
end)

RegisterNetEvent('blacklist:leaveQueue')
AddEventHandler('blacklist:leaveQueue', function()
    local source = source
    removeFromAllQueues(source)
    playerStates[source] = 'menu'
    TriggerClientEvent('blacklist:queueUpdate', source, { status = 'cancelled' })
end)

-- Clean up on disconnect
AddEventHandler('playerDropped', function()
    local source = source
    removeFromAllQueues(source)
    playerStates[source] = nil
end)

-- ========================
-- Queue processing loop
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.MATCH_CHECK_INTERVAL)
        processRankedQueue()
        processNormalQueue()
    end
end)

function processRankedQueue()
    if #rankedQueue < 2 then return end

    local now = GetGameTimer()

    -- Expand search range for players waiting long
    for _, entry in ipairs(rankedQueue) do
        local waitTime = now - entry.joinedAt
        local expansions = math.floor(waitTime / Config.RANKED_EXPAND_INTERVAL)
        entry.searchRange = math.min(
            Config.RANKED_MMR_RANGE_INITIAL + (expansions * Config.RANKED_MMR_RANGE_EXPAND),
            Config.RANKED_MMR_RANGE_MAX
        )
    end

    -- Try to find a match
    for i = 1, #rankedQueue do
        for j = i + 1, #rankedQueue do
            local a = rankedQueue[i]
            local b = rankedQueue[j]

            local mmrDiff = math.abs(a.mmr - b.mmr)
            local maxRange = math.max(a.searchRange, b.searchRange)
            local sameTier = a.tier == b.tier
            local isCrossTier = false

            if not sameTier then
                local aTierIdx = TIER_INDEX[a.tier] or 1
                local bTierIdx = TIER_INDEX[b.tier] or 1
                local tierGap = math.abs(aTierIdx - bTierIdx)

                -- Cross-tier only allowed if gap is 1 and both players opted in
                if tierGap == 1 and a.crossTier and b.crossTier then
                    isCrossTier = true
                else
                    goto continue
                end
            end

            if mmrDiff <= maxRange then
                local aIsChaser = (a.chases or 0) <= (a.escapes or 0)

                local chaser, runner
                if aIsChaser then
                    chaser = a
                    runner = b
                else
                    chaser = b
                    runner = a
                end

                -- Remove from queue
                table.remove(rankedQueue, math.max(i, j))
                table.remove(rankedQueue, math.min(i, j))

                playerStates[chaser.source] = 'in_match'
                playerStates[runner.source] = 'in_match'

                -- Determine forced tier for cross-tier matches (use lower tier)
                local forceTier = nil
                if isCrossTier then
                    local chaserIdx = TIER_INDEX[chaser.tier] or 1
                    local runnerIdx = TIER_INDEX[runner.tier] or 1
                    forceTier = chaserIdx < runnerIdx and chaser.tier or runner.tier
                end

                startRankedMatch(chaser, runner, isCrossTier, forceTier)
                return
            end

            ::continue::
        end
    end
end

function processNormalQueue()
    if #normalRunnerQueue == 0 or #normalChaserQueue == 0 then return end

    local runner = normalRunnerQueue[1]
    local chasers = {}

    local numChasers = math.min(#normalChaserQueue, Config.NORMAL_MAX_CHASERS)
    for i = 1, numChasers do
        table.insert(chasers, normalChaserQueue[i])
    end

    -- Remove matched players
    table.remove(normalRunnerQueue, 1)
    for i = numChasers, 1, -1 do
        table.remove(normalChaserQueue, i)
    end

    playerStates[runner.source] = 'in_match'
    for _, c in ipairs(chasers) do
        playerStates[c.source] = 'in_match'
    end

    startNormalChaseMatch(runner, chasers)
end

-- ========================
-- Match starters
-- ========================

function startRankedMatch(chaser, runner, isCrossTier, forceTier)
    local locations = {
        { x = -130.0,  y = -1520.0, z = 33.5 },
        { x = -530.0,  y = -680.0,  z = 33.5 },
        { x = 120.0,   y = -220.0,  z = 54.0 },
        { x = -820.0,  y = -1100.0, z = 11.0 },
        { x = 350.0,   y = -1050.0, z = 29.3 },
    }
    local loc = locations[math.random(#locations)]

    local matchData = {
        mode = 'ranked',
        isCrossTier = isCrossTier or false,
        forceTier = forceTier,
        chaser = {
            source = chaser.source,
            identifier = chaser.identifier,
            mmr = chaser.mmr,
            tier = chaser.tier,
        },
        runner = {
            source = runner.source,
            identifier = runner.identifier,
            mmr = runner.mmr,
            tier = runner.tier,
        },
        startX = loc.x,
        startY = loc.y,
        startZ = loc.z,
    }

    TriggerEvent('blacklist:startChaseMatch', matchData)

    local ctMsg = isCrossTier and ' (CROSS-TIER)' or ''
    TriggerClientEvent('blacklist:queueUpdate', chaser.source, { status = 'matched', message = 'Match found! You are the CHASER' .. ctMsg })
    TriggerClientEvent('blacklist:queueUpdate', runner.source, { status = 'matched', message = 'Match found! You are the RUNNER' .. ctMsg })

    print(('[Matchmaking] Ranked match%s: %s (%s chaser, %d MMR) vs %s (%s runner, %d MMR)%s'):format(
        isCrossTier and ' [CROSS-TIER]' or '',
        GetPlayerName(chaser.source), chaser.tier, chaser.mmr,
        GetPlayerName(runner.source), runner.tier, runner.mmr,
        forceTier and (' | forced tier: ' .. forceTier) or ''))
end

function startNormalChaseMatch(runner, chasers)
    local bank = BANK_LOCATIONS[math.random(#BANK_LOCATIONS)]

    local chaserSources = {}
    local chaserIdentifiers = {}
    for _, c in ipairs(chasers) do
        table.insert(chaserSources, c.source)
        table.insert(chaserIdentifiers, c.identifier)
    end

    local matchData = {
        mode = 'normal',
        chasers = {},
        runner = {
            source = runner.source,
            identifier = runner.identifier,
        },
        startX = bank.x,
        startY = bank.y,
        startZ = bank.z,
        startHeading = bank.heading,
        locationName = bank.name,
    }

    for _, c in ipairs(chasers) do
        table.insert(matchData.chasers, {
            source = c.source,
            identifier = c.identifier,
        })
    end

    TriggerEvent('blacklist:startChaseMatch', matchData)

    TriggerClientEvent('blacklist:queueUpdate', runner.source, { status = 'matched', message = 'Bank heist at ' .. bank.name .. '! You are the RUNNER' })
    for _, c in ipairs(chasers) do
        TriggerClientEvent('blacklist:queueUpdate', c.source, { status = 'matched', message = 'Bank heist at ' .. bank.name .. '! You are a CHASER' })
    end

    print(('[Matchmaking] Normal chase at %s: 1 runner vs %d chasers'):format(bank.name, #chasers))
end

-- ========================
-- Free roam
-- ========================

RegisterNetEvent('blacklist:joinFreeRoam')
AddEventHandler('blacklist:joinFreeRoam', function()
    local source = source
    removeFromAllQueues(source)
    playerStates[source] = 'freeroam'
    TriggerEvent('blacklist:enterFreeRoam', source)
    print(('[Matchmaking] %s entered free roam'):format(GetPlayerName(source)))
end)

-- ========================
-- Match ended callback (called by chase resource)
-- ========================

RegisterNetEvent('blacklist:matchEnded')
AddEventHandler('blacklist:matchEnded', function(sources)
    for _, src in ipairs(sources) do
        playerStates[src] = 'menu'
    end
end)

-- ========================
-- Utility
-- ========================

function removeFromAllQueues(source)
    for i = #rankedQueue, 1, -1 do
        if rankedQueue[i].source == source then
            table.remove(rankedQueue, i)
        end
    end
    for i = #normalRunnerQueue, 1, -1 do
        if normalRunnerQueue[i].source == source then
            table.remove(normalRunnerQueue, i)
        end
    end
    for i = #normalChaserQueue, 1, -1 do
        if normalChaserQueue[i].source == source then
            table.remove(normalChaserQueue, i)
        end
    end
end

function getIdentifier(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return nil
end

exports('GetPlayerState', function(source)
    return playerStates[source] or 'menu'
end)

print('[Matchmaking] ^2Queue system loaded^0')
