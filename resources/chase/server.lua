-- ============================================================
-- Chase/Run game mode: server-side match management
-- ============================================================

local ChaseConfig = {
    ROUND_DURATION = 300, -- 5 minutes in seconds
    RUNNER_HEAD_START = 5, -- seconds before chasers can move
    CATCH_DISTANCE = 15.0, -- meters to count as "close"
    CATCH_TIME = 5.0, -- seconds chaser must stay close to catch
    COUNTDOWN_DURATION = 3, -- seconds before round start

    -- Anti-cheat
    MAX_AIRBORNE_TIME = 2.0, -- seconds before jump is flagged
    RAM_SPEED_THRESHOLD = 30.0, -- speed in m/s for ram detection
    MAX_WARNINGS = 2, -- warnings before disqualification
}

-- Active matches: matchId -> matchState
local activeMatches = {}
local playerMatchMap = {} -- source -> matchId

local matchIdCounter = 0

-- ========================
-- Start a match (triggered by matchmaking)
-- ========================

RegisterNetEvent('blacklist:startChaseMatch')
AddEventHandler('blacklist:startChaseMatch', function(matchData)
    matchIdCounter = matchIdCounter + 1
    local matchId = matchIdCounter

    local match = {
        id = matchId,
        mode = matchData.mode, -- 'ranked' or 'normal'
        isCrossTier = matchData.isCrossTier or false,
        forceTier = matchData.forceTier,
        state = 'countdown', -- countdown, headstart, active, finished
        startTime = 0,
        duration = ChaseConfig.ROUND_DURATION,

        runner = matchData.runner,
        chasers = matchData.mode == 'ranked'
            and { { source = matchData.chaser.source, identifier = matchData.chaser.identifier, mmr = matchData.chaser.mmr, tier = matchData.chaser.tier } }
            or matchData.chasers,

        startX = matchData.startX,
        startY = matchData.startY,
        startZ = matchData.startZ,
        startHeading = matchData.startHeading or 0.0,

        -- Tracking
        catchTimer = 0,
        warnings = {},
        result = nil,
    }

    activeMatches[matchId] = match

    -- Map players to this match
    playerMatchMap[match.runner.source] = matchId
    for _, chaser in ipairs(match.chasers) do
        playerMatchMap[chaser.source] = matchId
    end

    -- Close menu for all participants
    TriggerClientEvent('blacklist:closeMenu', match.runner.source)
    for _, chaser in ipairs(match.chasers) do
        TriggerClientEvent('blacklist:closeMenu', chaser.source)
    end

    -- Spawn vehicles and teleport players
    Citizen.Wait(500)

    -- Runner spawns at the start location
    TriggerEvent('blacklist:spawnPlayerVehicle', match.runner.source,
        match.startX, match.startY, match.startZ, match.startHeading, match.forceTier)

    -- Chasers spawn slightly behind
    for i, chaser in ipairs(match.chasers) do
        local offset = i * 8.0
        TriggerEvent('blacklist:spawnPlayerVehicle', chaser.source,
            match.startX - offset, match.startY, match.startZ, match.startHeading, match.forceTier)
    end

    Citizen.Wait(1000)

    -- Freeze everyone for countdown
    TriggerClientEvent('blacklist:chaseFreeze', match.runner.source, true)
    for _, chaser in ipairs(match.chasers) do
        TriggerClientEvent('blacklist:chaseFreeze', chaser.source, true)
    end

    -- Send countdown to all
    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseCountdown', src, ChaseConfig.COUNTDOWN_DURATION)
    end

    -- Wait for countdown
    Citizen.Wait(ChaseConfig.COUNTDOWN_DURATION * 1000)

    -- Unfreeze runner (head start)
    match.state = 'headstart'
    TriggerClientEvent('blacklist:chaseFreeze', match.runner.source, false)

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'headstart',
            duration = ChaseConfig.RUNNER_HEAD_START,
            role = src == match.runner.source and 'runner' or 'chaser',
        })
    end

    -- Wait for head start
    Citizen.Wait(ChaseConfig.RUNNER_HEAD_START * 1000)

    -- Unfreeze chasers - round starts
    match.state = 'active'
    match.startTime = GetGameTimer()

    for _, chaser in ipairs(match.chasers) do
        TriggerClientEvent('blacklist:chaseFreeze', chaser.source, false)
    end

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'start',
            duration = ChaseConfig.ROUND_DURATION,
            role = src == match.runner.source and 'runner' or 'chaser',
        })
    end

    print(('[Chase] Match #%d started (%s mode)'):format(matchId, match.mode))

    -- Start the match monitoring thread
    monitorMatch(matchId)
end)

-- ========================
-- Match monitoring
-- ========================

function monitorMatch(matchId)
    Citizen.CreateThread(function()
        local match = activeMatches[matchId]
        if not match then return end

        while match.state == 'active' do
            Citizen.Wait(500)

            match = activeMatches[matchId]
            if not match or match.state ~= 'active' then break end

            -- Check timer
            local elapsed = (GetGameTimer() - match.startTime) / 1000
            if elapsed >= match.duration then
                endMatch(matchId, 'runner', 'time_expired')
                break
            end

            -- Distance checking is done client-side and reported to server
        end
    end)
end

-- ========================
-- Distance report from client
-- ========================

RegisterNetEvent('blacklist:reportDistance')
AddEventHandler('blacklist:reportDistance', function(distance)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'active' then return end

    -- Only chasers report distance
    local isChaser = false
    for _, c in ipairs(match.chasers) do
        if c.source == source then isChaser = true break end
    end
    if not isChaser then return end

    -- Broadcast distance to all players in match
    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'distance',
            distance = distance,
        })
    end

    -- Check catch condition
    if distance <= ChaseConfig.CATCH_DISTANCE then
        match.catchTimer = match.catchTimer + 0.5 -- called every 500ms
        if match.catchTimer >= ChaseConfig.CATCH_TIME then
            endMatch(matchId, 'chaser', 'caught')
        end
    else
        match.catchTimer = 0
    end
end)

-- ========================
-- Anti-cheat reports from client
-- ========================

RegisterNetEvent('blacklist:reportViolation')
AddEventHandler('blacklist:reportViolation', function(violationType)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'active' then return end

    match.warnings[source] = (match.warnings[source] or 0) + 1
    local count = match.warnings[source]

    local playerName = GetPlayerName(source)

    if violationType == 'jump' then
        local allSources = getAllMatchSources(match)
        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:chaseHUD', src, {
                action = 'warning',
                message = playerName .. ': Illegal jump! (' .. count .. '/' .. ChaseConfig.MAX_WARNINGS .. ')',
            })
        end
    elseif violationType == 'ram' then
        local allSources = getAllMatchSources(match)
        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:chaseHUD', src, {
                action = 'warning',
                message = playerName .. ': Ramming violation! (' .. count .. '/' .. ChaseConfig.MAX_WARNINGS .. ')',
            })
        end
    end

    if count >= ChaseConfig.MAX_WARNINGS then
        -- Disqualify the violator
        local isRunner = (source == match.runner.source)
        if isRunner then
            endMatch(matchId, 'chaser', 'runner_disqualified')
        else
            endMatch(matchId, 'runner', 'chaser_disqualified')
        end
    end

    print(('[Chase] Violation in match #%d: %s from %s (warning %d/%d)'):format(
        matchId, violationType, playerName, count, ChaseConfig.MAX_WARNINGS))
end)

-- ========================
-- End match
-- ========================

function endMatch(matchId, winnerRole, reason)
    local match = activeMatches[matchId]
    if not match or match.state == 'finished' then return end

    match.state = 'finished'
    match.result = { winnerRole = winnerRole, reason = reason }

    local elapsed = math.floor((GetGameTimer() - match.startTime) / 1000)
    local allSources = getAllMatchSources(match)

    -- Notify all players
    for _, src in ipairs(allSources) do
        local role = src == match.runner.source and 'runner' or 'chaser'
        local won = role == winnerRole

        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'end',
            won = won,
            winnerRole = winnerRole,
            reason = reason,
            duration = elapsed,
        })
    end

    -- Process ranked results
    if match.mode == 'ranked' and #match.chasers == 1 then
        local winnerId, loserId
        if winnerRole == 'runner' then
            winnerId = match.runner.identifier
            loserId = match.chasers[1].identifier
        else
            winnerId = match.chasers[1].identifier
            loserId = match.runner.identifier
        end
        exports.ranked:ProcessRankedResult(winnerId, loserId, winnerRole, elapsed, match.isCrossTier)
    end

    -- Return players to menu after delay
    Citizen.SetTimeout(8000, function()
        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:returnToMenu', src)
            playerMatchMap[src] = nil
        end
        TriggerEvent('blacklist:matchEnded', allSources)
        activeMatches[matchId] = nil
    end)

    print(('[Chase] Match #%d ended: %s wins (%s) after %ds'):format(matchId, winnerRole, reason, elapsed))
end

-- ========================
-- Player disconnect during match
-- ========================

AddEventHandler('playerDropped', function()
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state == 'finished' then return end

    if source == match.runner.source then
        endMatch(matchId, 'chaser', 'runner_disconnected')
    else
        -- Remove chaser; if no chasers left, runner wins
        for i, c in ipairs(match.chasers) do
            if c.source == source then
                table.remove(match.chasers, i)
                break
            end
        end
        if #match.chasers == 0 then
            endMatch(matchId, 'runner', 'all_chasers_disconnected')
        end
    end

    playerMatchMap[source] = nil
end)

-- ========================
-- Utility
-- ========================

function getAllMatchSources(match)
    local sources = { match.runner.source }
    for _, c in ipairs(match.chasers) do
        table.insert(sources, c.source)
    end
    return sources
end

print('[Chase] ^2Game mode loaded^0')
