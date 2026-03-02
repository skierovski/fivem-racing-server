-- ============================================================
-- Chase/Run game mode: server-side match management
-- ============================================================

local ChaseConfig = {
    ROUND_DURATION = 300,
    RUNNER_HEAD_START = 5,
    CATCH_DISTANCE = 10.0,
    CATCH_TIME = 9.0,
    COUNTDOWN_DURATION = 3,

    ESCAPE_DISTANCE = 400.0,
    ESCAPE_TIME = 15.0,

    MAX_AIRBORNE_TIME = 2.0,
    RAM_SPEED_THRESHOLD = 30.0,
    MAX_WARNINGS = 2,
}

local activeMatches = {}
local playerMatchMap = {}

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
        state = 'countdown',
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

    TriggerClientEvent('blacklist:closeMenu', match.runner.source)
    for _, chaser in ipairs(match.chasers) do
        TriggerClientEvent('blacklist:closeMenu', chaser.source)
    end

    Citizen.Wait(500)

    TriggerEvent('blacklist:spawnPlayerVehicle', match.runner.source,
        match.startX, match.startY, match.startZ, match.startHeading, match.forceTier)

    for i, chaser in ipairs(match.chasers) do
        local offset = i * 8.0
        TriggerEvent('blacklist:spawnPlayerVehicle', chaser.source,
            match.startX - offset, match.startY, match.startZ, match.startHeading, match.forceTier)
    end

    Citizen.Wait(1000)

    TriggerClientEvent('blacklist:chaseFreeze', match.runner.source, true)
    for _, chaser in ipairs(match.chasers) do
        TriggerClientEvent('blacklist:chaseFreeze', chaser.source, true)
    end

    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseCountdown', src, ChaseConfig.COUNTDOWN_DURATION)
    end

    Citizen.Wait(ChaseConfig.COUNTDOWN_DURATION * 1000)

    match.state = 'headstart'
    TriggerClientEvent('blacklist:chaseFreeze', match.runner.source, false)

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'headstart',
            duration = ChaseConfig.RUNNER_HEAD_START,
            role = src == match.runner.source and 'runner' or 'chaser',
        })
    end

    Citizen.Wait(ChaseConfig.RUNNER_HEAD_START * 1000)

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
                endMatch(matchId, 'runner', 'time_expired')
                break
            end
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

    local isChaser = false
    for _, c in ipairs(match.chasers) do
        if c.source == source then isChaser = true break end
    end
    if not isChaser then return end

    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'distance',
            distance = distance,
        })
    end

    if distance <= ChaseConfig.CATCH_DISTANCE then
        match.catchTimer = match.catchTimer + 0.5
        match.escapeTimer = 0
        if match.catchTimer >= ChaseConfig.CATCH_TIME then
            endMatch(matchId, 'chaser', 'caught')
        end
    elseif distance >= ChaseConfig.ESCAPE_DISTANCE then
        match.catchTimer = 0
        match.escapeTimer = match.escapeTimer + 0.5
        if match.escapeTimer >= ChaseConfig.ESCAPE_TIME then
            endMatch(matchId, 'runner', 'escaped')
        end
    else
        match.catchTimer = 0
        match.escapeTimer = 0
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

    local elapsed = math.floor((GetGameTimer() - match.startTime) / 1000)
    local allSources = getAllMatchSources(match)

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
