-- ============================================================
-- Chase/Run game mode: server-side match management
-- ============================================================

local ChaseConfig = {
    ROUND_DURATION = 300,
    CATCH_DISTANCE = 10.0,
    CATCH_TIME = 9.0,
    COUNTDOWN_DURATION = 3,

    ESCAPE_DISTANCE = 400.0,
    ESCAPE_TIME = 5.0,

    ARREST_MAX_SPEED = 8.94, -- 20 mph in m/s

    MAX_AIRBORNE_TIME = 2.0,
    RAM_SPEED_THRESHOLD = 30.0,
    MAX_WARNINGS = 2,

    REMATCH_WINDOW = 15,
}

local activeMatches = {}
local playerMatchMap = {}
local spawnReady = {}

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
        mode = matchData.mode,
        isCrossTier = matchData.isCrossTier or false,
        forceTier = matchData.forceTier,
        forceModel = matchData.forceModel,
        state = 'countdown',
        startTime = 0,
        duration = ChaseConfig.ROUND_DURATION,

        runner = matchData.runner,
        chasers = matchData.mode == 'ranked'
            and { { source = matchData.chaser.source, identifier = matchData.chaser.identifier, mmr = matchData.chaser.mmr, tier = matchData.chaser.tier } }
            or matchData.chasers,

        runnerX = matchData.runnerX, runnerY = matchData.runnerY,
        runnerZ = matchData.runnerZ, runnerHeading = matchData.runnerHeading,
        chaserX = matchData.chaserX, chaserY = matchData.chaserY,
        chaserZ = matchData.chaserZ, chaserHeading = matchData.chaserHeading,

        catchTimer = 0,
        escapeTimer = 0,
        warnings = {},
        result = nil,
    }

    activeMatches[matchId] = match

    playerMatchMap[match.runner.source] = matchId
    for _, chaser in ipairs(match.chasers) do
        playerMatchMap[chaser.source] = matchId
    end

    -- Move all players into a private routing bucket for this match
    local matchBucket = 1000 + matchId
    SetPlayerRoutingBucket(match.runner.source, matchBucket)
    for _, chaser in ipairs(match.chasers) do
        SetPlayerRoutingBucket(chaser.source, matchBucket)
    end

    TriggerClientEvent('blacklist:closeMenu', match.runner.source)
    for _, chaser in ipairs(match.chasers) do
        TriggerClientEvent('blacklist:closeMenu', chaser.source)
    end

    Citizen.Wait(500)

    -- Spawn runner at runner coords, chasers at chaser coords
    -- If forceModel is set (ranked), both players get the exact same car model
    if match.forceModel then
        TriggerEvent('blacklist:spawnPlayerWithModel', match.runner.source, match.forceModel,
            match.runnerX, match.runnerY, match.runnerZ, match.runnerHeading)

        for _, chaser in ipairs(match.chasers) do
            TriggerEvent('blacklist:spawnPlayerWithModel', chaser.source, match.forceModel,
                match.chaserX, match.chaserY, match.chaserZ, match.chaserHeading)
        end
    else
        TriggerEvent('blacklist:spawnPlayerVehicle', match.runner.source,
            match.runnerX, match.runnerY, match.runnerZ, match.runnerHeading, match.forceTier)

        for _, chaser in ipairs(match.chasers) do
            TriggerEvent('blacklist:spawnPlayerVehicle', chaser.source,
                match.chaserX, match.chaserY, match.chaserZ, match.chaserHeading, match.forceTier)
        end
    end

    -- Wait for all players to finish spawning (with timeout)
    local allSources = getAllMatchSources(match)
    local spawnDeadline = GetGameTimer() + 20000
    while GetGameTimer() < spawnDeadline do
        local allReady = true
        for _, src in ipairs(allSources) do
            if not spawnReady[src] then allReady = false break end
        end
        if allReady then break end
        Citizen.Wait(200)
    end

    for _, src in ipairs(allSources) do
        spawnReady[src] = nil
    end

    -- Freeze everyone during countdown
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseFreeze', src, true)
    end

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseCountdown', src, ChaseConfig.COUNTDOWN_DURATION)
    end

    Citizen.Wait(ChaseConfig.COUNTDOWN_DURATION * 1000)

    -- No headstart: unfreeze everyone simultaneously
    match.state = 'active'
    match.startTime = GetGameTimer()

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseFreeze', src, false)
    end

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'start',
            duration = ChaseConfig.ROUND_DURATION,
            role = src == match.runner.source and 'runner' or 'chaser',
        })
    end

    print(('[Chase] Match #%d started (%s mode) at %s'):format(matchId, match.mode, matchData.locationName or 'unknown'))

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

            local elapsed = (GetGameTimer() - match.startTime) / 1000
            if elapsed >= match.duration then
                endMatch(matchId, 'chaser', 'time_expired')
                break
            end
        end
    end)
end

-- ========================
-- Distance report from client
-- ========================

RegisterNetEvent('blacklist:reportDistance')
AddEventHandler('blacklist:reportDistance', function(distance, displayDistance, chaserSpeed)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'active' then return end

    local isChaser = false
    for _, c in ipairs(match.chasers) do
        if c.source == source then isChaser = true break end
    end
    if not isChaser then return end

    local speed = tonumber(chaserSpeed) or 0.0

    if distance <= ChaseConfig.CATCH_DISTANCE and speed <= ChaseConfig.ARREST_MAX_SPEED then
        match.catchTimer = match.catchTimer + 0.5
        match.escapeTimer = 0
        if match.catchTimer >= ChaseConfig.CATCH_TIME then
            endMatch(matchId, 'chaser', 'caught')
            return
        end
    elseif distance >= ChaseConfig.ESCAPE_DISTANCE then
        match.catchTimer = 0
        match.escapeTimer = match.escapeTimer + 0.5
        if match.escapeTimer >= ChaseConfig.ESCAPE_TIME then
            endMatch(matchId, 'runner', 'escaped')
            return
        end
    else
        match.catchTimer = 0
        match.escapeTimer = 0
    end

    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'distance',
            distance = displayDistance or math.min(distance, 400),
            catchProgress = match.catchTimer / ChaseConfig.CATCH_TIME,
            escapeProgress = match.escapeTimer / ChaseConfig.ESCAPE_TIME,
        })
    end
end)

-- ========================
-- Forfeit (player leaves match via ESC)
-- ========================

RegisterNetEvent('blacklist:forfeitMatch')
AddEventHandler('blacklist:forfeitMatch', function()
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state == 'finished' then return end

    local isRunner = (source == match.runner.source)
    if isRunner then
        endMatch(matchId, 'chaser', 'forfeit')
    else
        endMatch(matchId, 'runner', 'forfeit')
    end

    print(('[Chase] %s forfeited match #%d'):format(GetPlayerName(source), matchId))
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
    match.rematchRequests = {}

    local elapsed = math.floor((GetGameTimer() - match.startTime) / 1000)
    local allSources = getAllMatchSources(match)
    local isRanked = match.mode == 'ranked' and #match.chasers == 1

    for _, src in ipairs(allSources) do
        local role = src == match.runner.source and 'runner' or 'chaser'
        local won = role == winnerRole

        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'end',
            won = won,
            winnerRole = winnerRole,
            reason = reason,
            duration = elapsed,
            isRanked = isRanked,
        })
    end

    if isRanked then
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

    local returnDelay = isRanked and (ChaseConfig.REMATCH_WINDOW * 1000) or 8000

    match.returnTimerActive = true
    Citizen.SetTimeout(returnDelay, function()
        if not match.returnTimerActive then return end
        returnPlayersToMenu(matchId)
    end)

    print(('[Chase] Match #%d ended: %s wins (%s) after %ds'):format(matchId, winnerRole, reason, elapsed))
end

function returnPlayersToMenu(matchId)
    local match = activeMatches[matchId]
    if not match then return end

    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        SetPlayerRoutingBucket(src, 0)
        TriggerClientEvent('blacklist:returnToMenu', src)
        playerMatchMap[src] = nil
    end
    TriggerEvent('blacklist:matchEnded', allSources)
    activeMatches[matchId] = nil
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
    spawnReady[source] = nil
end)

-- ========================
-- Rematch (ranked 1v1 only)
-- ========================

RegisterNetEvent('blacklist:requestRematch')
AddEventHandler('blacklist:requestRematch', function()
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'finished' then return end
    if match.mode ~= 'ranked' or #match.chasers ~= 1 then return end
    if not match.rematchRequests then return end

    match.rematchRequests[source] = true

    local allSources = getAllMatchSources(match)
    local opponentSource = nil
    for _, src in ipairs(allSources) do
        if src ~= source then opponentSource = src end
    end

    if opponentSource and not match.rematchRequests[opponentSource] then
        TriggerClientEvent('blacklist:rematchStatus', opponentSource, 'opponent_requested')
        TriggerClientEvent('blacklist:rematchStatus', source, 'waiting')
    end

    local allAccepted = true
    for _, src in ipairs(allSources) do
        if not match.rematchRequests[src] then allAccepted = false break end
    end

    if allAccepted then
        match.returnTimerActive = false

        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:rematchStatus', src, 'accepted')
        end

        Citizen.SetTimeout(1500, function()
            startRematch(match)
        end)

        print(('[Chase] Rematch accepted for match #%d'):format(matchId))
    end
end)

function startRematch(oldMatch)
    local allSources = getAllMatchSources(oldMatch)
    for _, src in ipairs(allSources) do
        playerMatchMap[src] = nil
    end
    activeMatches[oldMatch.id] = nil

    local newRunner = oldMatch.chasers[1]
    local newChaser = oldMatch.runner

    TriggerEvent('blacklist:startChaseMatch', {
        mode = oldMatch.mode,
        isCrossTier = oldMatch.isCrossTier,
        forceTier = oldMatch.forceTier,
        forceModel = oldMatch.forceModel,
        locationName = 'rematch',

        runner = { source = newRunner.source, identifier = newRunner.identifier, mmr = newRunner.mmr, tier = newRunner.tier },
        chaser = { source = newChaser.source, identifier = newChaser.identifier, mmr = newChaser.mmr, tier = newChaser.tier },

        runnerX = oldMatch.runnerX, runnerY = oldMatch.runnerY,
        runnerZ = oldMatch.runnerZ, runnerHeading = oldMatch.runnerHeading,
        chaserX = oldMatch.chaserX, chaserY = oldMatch.chaserY,
        chaserZ = oldMatch.chaserZ, chaserHeading = oldMatch.chaserHeading,
    })
end

-- ========================
-- Spawn readiness signal from client
-- ========================

RegisterNetEvent('blacklist:spawnReady')
AddEventHandler('blacklist:spawnReady', function()
    spawnReady[source] = true
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

-- ========================
-- Tester diagnostic logs from client
-- ========================

RegisterNetEvent('blacklist:chaseLog')
AddEventHandler('blacklist:chaseLog', function(logData)
    local source = source
    local name = GetPlayerName(source) or 'Unknown'
    local matchId = playerMatchMap[source] or 0
    print(('[CHASE LOG] Match#%d | %s | %s'):format(matchId, name, logData.message or ''))

    -- If runner crashed into environment, relay timing to chasers
    if logData.message and string.find(logData.message, 'RUNNER_ENV_CRASH') then
        local match = activeMatches[matchId]
        if match then
            local speed = tonumber(string.match(logData.message, 'speed=(%d+)')) or 0
            for _, chaser in ipairs(match.chasers) do
                TriggerClientEvent('blacklist:runnerCrashInfo', chaser.source, { speed = speed })
            end
        end
    end
end)

print('[Chase] ^2Game mode loaded^0')
