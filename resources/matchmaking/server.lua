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

-- Shared chase locations for both ranked and normal mode (tester-provided coords)
local CHASE_LOCATIONS = {
    {
        name = 'j1',
        runner = { x = -851.27, y = -156.47, z = 37.39, h = 70.00 },
        chaser = { x = -843.19, y = -159.52, z = 37.27, h = 74.52 },
    },
    {
        name = 'Bank Kwadraciak',
        runner = { x = 150.23, y = -1032.16, z = 28.66, h = 342.54 },
        chaser = { x = 154.02, y = -1034.46, z = 28.56, h = 346.60 },
    },
    {
        name = 'Bank Beta',
        runner = { x = -1212.03, y = -311.69, z = 37.29, h = 298.01 },
        chaser = { x = -1220.45, y = -316.44, z = 37.16, h = 298.91 },
    },
    {
        name = 'Pacyfik',
        runner = { x = 219.27, y = 206.40, z = 104.97, h = 124.73 },
        chaser = { x = 226.61, y = 211.55, z = 105.06, h = 124.77 },
    },
    {
        name = 'Bobcat',
        runner = { x = 920.72, y = -2114.48, z = 29.79, h = 314.45 },
        chaser = { x = 920.74, y = -2119.19, z = 29.75, h = 307.74 },
    },
    -- Kasyno disabled: coords are on casino roof, need street-level coords
    -- {
    --     name = 'Kasyno',
    --     runner = { x = 914.91, y = 42.08, z = 80.42, h = 127.38 },
    --     chaser = { x = 927.25, y = 45.18, z = 80.63, h = 95.52 },
    -- },
    {
        name = 'Fleeca Urzednicza',
        runner = { x = 326.85, y = -264.21, z = 53.48, h = 312.89 },
        chaser = { x = 318.57, y = -272.21, z = 53.44, h = 325.30 },
    },
    {
        name = 'Dolar Pills',
        runner = { x = 44.35, y = -1557.10, z = 28.82, h = 50.93 },
        chaser = { x = 56.41, y = -1567.20, z = 28.98, h = 50.08 },
    },
}

-- ========================
-- Join / leave queue
-- ========================

local TIER_ORDER = { 'bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist' }
local TIER_INDEX = {}
for i, name in ipairs(TIER_ORDER) do TIER_INDEX[name] = i end

-- Cache of models per tier for random car selection in ranked
local tierModels = {}

local TIER_ASSIGNMENTS = {
    bronze    = { 'gb_cometcl', 'rh4', 'ballerc', 'futo' },
    silver    = { 'gb_cometclf', 'gb_retinueloz', 'gb_schrauber' },
    gold      = { 'roxanne', 'buffaloh', 'jester5', 'sent6', 'gb_gresleystx' },
    platinum  = { 'gb_argento7f', 'gb_solace', 'gb_sultanrsx' },
    diamond   = { 'gb_tr3s' },
    blacklist = { 'gsttoros1', 'gb_comets2r' },
}

Citizen.CreateThread(function()
    Citizen.Wait(2000)

    -- Auto-apply tier assignments so DB is always in sync with code
    exports.oxmysql:execute('UPDATE vehicle_catalog SET tier = ? WHERE tier != ?', { 'custom', 'custom' })
    Citizen.Wait(200)
    for tier, models in pairs(TIER_ASSIGNMENTS) do
        local placeholders = {}
        for _ in ipairs(models) do table.insert(placeholders, '?') end
        local params = { tier }
        for _, m in ipairs(models) do table.insert(params, m) end
        exports.oxmysql:execute(
            'UPDATE vehicle_catalog SET tier = ? WHERE model IN (' .. table.concat(placeholders, ',') .. ')',
            params
        )
    end
    print('[Matchmaking] ^2Tier assignments synced to DB^0')

    Citizen.Wait(500)

    -- Now cache the result
    exports.oxmysql:execute(
        'SELECT model, tier FROM vehicle_catalog WHERE tier != ?', { 'custom' },
        function(result)
            for _, row in ipairs(result or {}) do
                if not tierModels[row.tier] then tierModels[row.tier] = {} end
                table.insert(tierModels[row.tier], row.model)
            end
            print('[Matchmaking] Vehicle catalog cached: ' .. json.encode(tierModels))
        end
    )
end)

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
                local chaser, runner
                if math.random(2) == 1 then
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

                -- Force tier-locked vehicles: same tier uses own tier, cross-tier uses lower
                local forceTier = chaser.tier
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
    local loc = CHASE_LOCATIONS[math.random(#CHASE_LOCATIONS)]

    -- Pick one random car from the tier -- both players will drive this model
    local models = tierModels[forceTier] or {}
    local forceModel = #models > 0 and models[math.random(#models)] or nil

    local matchData = {
        mode = 'ranked',
        isCrossTier = isCrossTier or false,
        forceTier = forceTier,
        forceModel = forceModel,
        locationName = loc.name,
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
        runnerX = loc.runner.x, runnerY = loc.runner.y, runnerZ = loc.runner.z, runnerHeading = loc.runner.h,
        chaserX = loc.chaser.x, chaserY = loc.chaser.y, chaserZ = loc.chaser.z, chaserHeading = loc.chaser.h,
    }

    TriggerEvent('blacklist:startChaseMatch', matchData)

    local ctMsg = isCrossTier and ' (CROSS-TIER)' or ''
    TriggerClientEvent('blacklist:queueUpdate', chaser.source, { status = 'matched', message = 'Match found! You are the CHASER' .. ctMsg })
    TriggerClientEvent('blacklist:queueUpdate', runner.source, { status = 'matched', message = 'Match found! You are the RUNNER' .. ctMsg })

    print(('[Matchmaking] Ranked match%s at %s: %s (%s chaser, %d MMR) vs %s (%s runner, %d MMR)%s'):format(
        isCrossTier and ' [CROSS-TIER]' or '', loc.name,
        GetPlayerName(chaser.source), chaser.tier, chaser.mmr,
        GetPlayerName(runner.source), runner.tier, runner.mmr,
        forceTier and (' | forced tier: ' .. forceTier) or ''))
end

function startNormalChaseMatch(runner, chasers)
    local loc = CHASE_LOCATIONS[math.random(#CHASE_LOCATIONS)]

    local matchData = {
        mode = 'normal',
        chasers = {},
        runner = {
            source = runner.source,
            identifier = runner.identifier,
        },
        locationName = loc.name,
        runnerX = loc.runner.x, runnerY = loc.runner.y, runnerZ = loc.runner.z, runnerHeading = loc.runner.h,
        chaserX = loc.chaser.x, chaserY = loc.chaser.y, chaserZ = loc.chaser.z, chaserHeading = loc.chaser.h,
    }

    for _, c in ipairs(chasers) do
        table.insert(matchData.chasers, {
            source = c.source,
            identifier = c.identifier,
        })
    end

    TriggerEvent('blacklist:startChaseMatch', matchData)

    TriggerClientEvent('blacklist:queueUpdate', runner.source, { status = 'matched', message = 'Chase at ' .. loc.name .. '! You are the RUNNER' })
    for _, c in ipairs(chasers) do
        TriggerClientEvent('blacklist:queueUpdate', c.source, { status = 'matched', message = 'Chase at ' .. loc.name .. '! You are a CHASER' })
    end

    print(('[Matchmaking] Normal chase at %s: 1 runner vs %d chasers'):format(loc.name, #chasers))
end

-- ========================
-- Free roam
-- ========================

RegisterNetEvent('blacklist:leaveFreeRoam')
AddEventHandler('blacklist:leaveFreeRoam', function()
    local source = source
    if playerStates[source] == 'freeroam' then
        playerStates[source] = 'menu'
    end
end)

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
