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

-- Queue storage (unified: no separate runner/chaser queues)
local rankedQueue = {} -- { source, identifier, mmr, tier, crossTier, chases, escapes, joinedAt, searchRange }
local normalQueue = {}  -- { source, identifier, mmr, tier, chases, escapes }
local testRankedQueue = {} -- { source, identifier, mmr, tier, chases, escapes }

-- Player states
local playerStates = {} -- [source] = 'menu' | 'ranked_queue' | 'normal_queue' | 'test_ranked_queue' | 'in_match' | 'freeroam'

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
    bronze    = { 'gbcometcl', 'rh4', 'ballerc', 'futo', 'gbargento2f' },
    silver    = { 'gbcometclf', 'gbretinueloz', 'gbschrauber', 'tailgater2', 'vstr' },
    gold      = { 'roxanne', 'buffaloh', 'jester5', 'sent6', 'gbgresleystx' },
    platinum  = { 'gbargento7f', 'gbsolace', 'gbsultanrsx', 'sentinel5', 'gbdominatorgsx' },
    diamond   = { 'gbtr3s', 'elegyrh5', 'gst73r1', 'jester4', 'gbargento7fs' },
    blacklist = { 'gsttoros1', 'gbcomets2r', 'gstsentgts1', 'gsttam1', 'tenf2' },
}

Citizen.CreateThread(function()
    Citizen.Wait(2000)

    -- Auto-apply tier assignments so DB is always in sync with code
    exports.oxmysql:execute('UPDATE vehicle_catalog SET tier = ? WHERE tier != ?', { 'custom', 'custom' })
    Citizen.Wait(200)
    for tier, models in pairs(TIER_ASSIGNMENTS) do
        for _, m in ipairs(models) do
            exports.oxmysql:execute(
                'INSERT IGNORE INTO vehicle_catalog (model, label, tier, class) VALUES (?, ?, ?, ?)',
                { m, m, tier, 'sports' }
            )
        end
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
AddEventHandler('blacklist:joinQueue', function(mode, crossTier, testMode)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    if playerStates[source] and playerStates[source] ~= 'menu' then
        TriggerClientEvent('blacklist:queueUpdate', source, { status = 'error', message = 'Already in queue or match' })
        return
    end

    exports.oxmysql:execute(
        'SELECT mmr, tier, chases_played, escapes_played FROM players WHERE identifier = ?',
        { identifier },
        function(result)
            if not result or not result[1] then return end
            local player = result[1]

            if mode == 'ranked' and testMode == true then
                table.insert(testRankedQueue, {
                    source = source,
                    identifier = identifier,
                    mmr = player.mmr,
                    tier = player.tier,
                    chases = player.chases_played or 0,
                    escapes = player.escapes_played or 0,
                })
                playerStates[source] = 'test_ranked_queue'
                TriggerClientEvent('blacklist:queueUpdate', source, {
                    status = 'waiting',
                    message = 'Searching for test match...'
                })
                print(('[Matchmaking] %s joined TEST ranked queue (MMR: %d, tier: %s)'):format(
                    GetPlayerName(source), player.mmr, player.tier))

            elseif mode == 'ranked' then
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
                    message = 'Searching for match...'
                })
                print(('[Matchmaking] %s joined ranked queue (MMR: %d, tier: %s, crossTier: %s)'):format(
                    GetPlayerName(source), player.mmr, player.tier, tostring(crossTier == true)))

            elseif mode == 'normal' then
                table.insert(normalQueue, {
                    source = source,
                    identifier = identifier,
                    mmr = player.mmr,
                    tier = player.tier,
                    chases = player.chases_played or 0,
                    escapes = player.escapes_played or 0,
                })
                playerStates[source] = 'normal_queue'
                TriggerClientEvent('blacklist:queueUpdate', source, {
                    status = 'waiting',
                    message = 'Searching for match...'
                })
                print(('[Matchmaking] %s joined normal queue'):format(GetPlayerName(source)))
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
        processTestRankedQueue()
        processNormalQueue()
    end
end)

-- ========================
-- Role assignment: scaled 50/50 balance
-- ========================

function assignRoles(a, b)
    local aTotal = (a.chases or 0) + (a.escapes or 0)
    local bTotal = (b.chases or 0) + (b.escapes or 0)

    local aEscRatio = aTotal > 0 and (a.escapes / aTotal) or 0.5
    local bEscRatio = bTotal > 0 and (b.escapes / bTotal) or 0.5

    -- diff > 0 means A has escaped more → A should chase
    local diff = aEscRatio - bEscRatio
    local chanceAChases = math.max(0.10, math.min(0.90, 0.5 + diff * 0.8))

    if math.random() < chanceAChases then
        return a, b  -- a = chaser, b = runner
    else
        return b, a  -- b = chaser, a = runner
    end
end

-- ========================
-- Queue processing
-- ========================

function processRankedQueue()
    if #rankedQueue < 2 then return end

    local now = GetGameTimer()

    for _, entry in ipairs(rankedQueue) do
        local waitTime = now - entry.joinedAt
        local expansions = math.floor(waitTime / Config.RANKED_EXPAND_INTERVAL)
        entry.searchRange = math.min(
            Config.RANKED_MMR_RANGE_INITIAL + (expansions * Config.RANKED_MMR_RANGE_EXPAND),
            Config.RANKED_MMR_RANGE_MAX
        )
    end

    -- Score all valid pairs, pick the best one
    local bestPair = nil
    local bestScore = math.huge

    for i = 1, #rankedQueue do
        for j = i + 1, #rankedQueue do
            local a = rankedQueue[i]
            local b = rankedQueue[j]

            local mmrDiff = math.abs(a.mmr - b.mmr)
            local maxRange = math.max(a.searchRange, b.searchRange)

            if mmrDiff > maxRange then goto continue end

            local sameTier = a.tier == b.tier
            local isCrossTier = false

            if not sameTier then
                if a.crossTier and b.crossTier then
                    isCrossTier = true
                else
                    goto continue
                end
            end

            -- Lower score = better match; same-tier strongly preferred
            local score = mmrDiff + (isCrossTier and 1000 or 0)

            if score < bestScore then
                bestScore = score
                bestPair = { i = i, j = j, a = a, b = b, isCrossTier = isCrossTier }
            end

            ::continue::
        end
    end

    if not bestPair then return end

    local chaser, runner = assignRoles(bestPair.a, bestPair.b)

    table.remove(rankedQueue, math.max(bestPair.i, bestPair.j))
    table.remove(rankedQueue, math.min(bestPair.i, bestPair.j))

    playerStates[chaser.source] = 'in_match'
    playerStates[runner.source] = 'in_match'

    local forceTier = chaser.tier
    if bestPair.isCrossTier then
        local chaserIdx = TIER_INDEX[chaser.tier] or 1
        local runnerIdx = TIER_INDEX[runner.tier] or 1
        forceTier = chaserIdx < runnerIdx and chaser.tier or runner.tier
    end

    startRankedMatch(chaser, runner, bestPair.isCrossTier, forceTier)
end

function processTestRankedQueue()
    if #testRankedQueue < 2 then return end

    local a = table.remove(testRankedQueue, 1)
    local b = table.remove(testRankedQueue, 1)

    local chaser, runner = assignRoles(a, b)

    playerStates[chaser.source] = 'in_match'
    playerStates[runner.source] = 'in_match'

    local randomTier = TIER_ORDER[math.random(#TIER_ORDER)]
    local models = tierModels[randomTier] or {}
    if #models == 0 then
        for _, tier in ipairs(TIER_ORDER) do
            if tierModels[tier] and #tierModels[tier] > 0 then
                randomTier = tier
                models = tierModels[tier]
                break
            end
        end
    end

    startRankedMatch(chaser, runner, false, randomTier)

    print(('[Matchmaking] TEST ranked match: %s vs %s | random tier: %s'):format(
        GetPlayerName(chaser.source), GetPlayerName(runner.source), randomTier))
end

function processNormalQueue()
    local minPlayers = Config.NORMAL_MIN_CHASERS + 1
    if #normalQueue < minPlayers then return end

    -- Pick the player with the highest escape ratio as runner (needs more chasing,
    -- but as runner they give others chaser roles → system balances overall)
    local bestRunnerIdx = 1
    local bestRunnerScore = -1

    for i, p in ipairs(normalQueue) do
        local total = (p.chases or 0) + (p.escapes or 0)
        local escRatio = total > 0 and (p.escapes / total) or 0.5
        -- Invert: player who has CHASED the most (lowest escRatio) should be runner
        local runnerScore = 1 - escRatio
        -- Add small random jitter for variety
        runnerScore = runnerScore + math.random() * 0.15
        if runnerScore > bestRunnerScore then
            bestRunnerScore = runnerScore
            bestRunnerIdx = i
        end
    end

    local runner = table.remove(normalQueue, bestRunnerIdx)

    local numChasers = math.min(#normalQueue, Config.NORMAL_MAX_CHASERS)
    local chasers = {}
    for i = 1, numChasers do
        table.insert(chasers, table.remove(normalQueue, 1))
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

    TriggerClientEvent('blacklist:queueUpdate', chaser.source, { status = 'matched', message = 'Match found!' })
    TriggerClientEvent('blacklist:queueUpdate', runner.source, { status = 'matched', message = 'Match found!' })

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

    TriggerClientEvent('blacklist:queueUpdate', runner.source, { status = 'matched', message = 'Match found!' })
    for _, c in ipairs(chasers) do
        TriggerClientEvent('blacklist:queueUpdate', c.source, { status = 'matched', message = 'Match found!' })
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
    for i = #testRankedQueue, 1, -1 do
        if testRankedQueue[i].source == source then
            table.remove(testRankedQueue, i)
        end
    end
    for i = #normalQueue, 1, -1 do
        if normalQueue[i].source == source then
            table.remove(normalQueue, i)
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
