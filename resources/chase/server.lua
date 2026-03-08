-- ============================================================
-- Chase/Run game mode: server-side match management
-- ============================================================

local ChaseConfig = {
    RANKED_ROUND_DURATION = 300,
    NORMAL_ROUND_DURATION = 600,
    CATCH_DISTANCE = 10.0,
    CATCH_TIME = 9.0,
    COUNTDOWN_DURATION = 3,

    ESCAPE_DISTANCE = 400.0,
    RANKED_ESCAPE_TIME = 5.0,
    NORMAL_ESCAPE_TIME = 10.0,

    ARREST_MAX_SPEED = 8.94, -- 20 mph in m/s

    MAX_PIT_STRIKES = 3,
    MAX_BRAKE_CHECK_STRIKES = 3,

    REMATCH_WINDOW = 15,

    CAR_PICK_TIMEOUT = 15, -- seconds to pick a car before auto-randomize
    HELI_VOTE_TIMEOUT = 15, -- seconds to wait for helicopter vote
    HELI_MODEL = 'polmav',

    -- mph thresholds per police code for legal PIT maneuvers
    PIT_SPEED_LIMITS = {
        green  = 0,
        yellow = 50,
        orange = 80,
        red    = 110,
    },

    -- Boxing: runner below this speed (m/s) with N+ chasers within radius for X seconds
    BOX_SPEED_THRESHOLD = 2.24, -- ~5 mph in m/s
    BOX_CHASER_RADIUS = 8.0,
    BOX_MIN_CHASERS = 2,
    BOX_TIME = 5.0,
}

local POLICE_CODE_ORDER = { 'green', 'yellow', 'orange', 'red' }
local POLICE_CODE_INDEX = {}
for i, code in ipairs(POLICE_CODE_ORDER) do POLICE_CODE_INDEX[code] = i end

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

    local isNormal = matchData.mode == 'normal'
    local duration = isNormal and ChaseConfig.NORMAL_ROUND_DURATION or ChaseConfig.RANKED_ROUND_DURATION
    local escapeTime = isNormal and ChaseConfig.NORMAL_ESCAPE_TIME or ChaseConfig.RANKED_ESCAPE_TIME

    local match = {
        id = matchId,
        mode = matchData.mode,
        isCrossTier = matchData.isCrossTier or false,
        forceTier = matchData.forceTier,
        forceModel = matchData.forceModel,
        runnerModel = matchData.runnerModel,
        state = 'countdown',
        startTime = 0,
        duration = duration,
        escapeTime = escapeTime,

        runner = matchData.runner,
        chasers = matchData.mode == 'ranked'
            and { { source = matchData.chaser.source, identifier = matchData.chaser.identifier, mmr = matchData.chaser.mmr, tier = matchData.chaser.tier } }
            or matchData.chasers,

        runnerX = matchData.runnerX, runnerY = matchData.runnerY,
        runnerZ = matchData.runnerZ, runnerHeading = matchData.runnerHeading,
        chaserX = matchData.chaserX, chaserY = matchData.chaserY,
        chaserZ = matchData.chaserZ, chaserHeading = matchData.chaserHeading,
        chaserSpawns = matchData.chaserSpawns,
        heliSpawn = matchData.heliSpawn,

        catchTimer = 0,
        escapeTimer = 0,
        chaserDistances = {},
        boxingTimer = 0,
        pitStrikes = {},
        brakeCheckStrikes = {},
        result = nil,

        policeCode = isNormal and 'green' or nil,
        heliPilot = nil,
        heliVotes = {},

        runnerCarPool = matchData.runnerCarPool or {},
        chaserCarPool = matchData.chaserCarPool or {},
        carPicks = {},
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

    -- === Car pick phase (normal mode only) ===
    if isNormal and #match.runnerCarPool > 0 then
        match.state = 'car_pick'

        TriggerClientEvent('blacklist:carPick', match.runner.source, {
            role = 'runner',
            cars = match.runnerCarPool,
            timeout = ChaseConfig.CAR_PICK_TIMEOUT,
        })
        for _, chaser in ipairs(match.chasers) do
            TriggerClientEvent('blacklist:carPick', chaser.source, {
                role = 'chaser',
                cars = match.chaserCarPool,
                timeout = ChaseConfig.CAR_PICK_TIMEOUT,
            })
        end

        local pickDeadline = GetGameTimer() + (ChaseConfig.CAR_PICK_TIMEOUT * 1000)
        while GetGameTimer() < pickDeadline do
            if match.state == 'finished' or match.state == 'cancelled' then return end
            local allPicked = true
            local allSources = getAllMatchSources(match)
            for _, src in ipairs(allSources) do
                if not match.carPicks[src] then allPicked = false break end
            end
            if allPicked then break end
            Citizen.Wait(500)
        end

        -- Randomize for anyone who didn't pick
        if not match.carPicks[match.runner.source] then
            local pool = match.runnerCarPool
            match.carPicks[match.runner.source] = pool[math.random(#pool)]
        end
        for _, chaser in ipairs(match.chasers) do
            if not match.carPicks[chaser.source] then
                local pool = match.chaserCarPool
                match.carPicks[chaser.source] = pool[math.random(#pool)]
            end
        end

        match.runnerModel = match.carPicks[match.runner.source]
        for _, chaser in ipairs(match.chasers) do
            chaser.assignedCar = match.carPicks[chaser.source]
        end

        local allSources = getAllMatchSources(match)
        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:carPickDone', src)
        end

        print(('[Chase] Match #%d: Car picks done. Runner=%s | Chasers=%s'):format(
            matchId, match.runnerModel or '?',
            table.concat((function()
                local t = {}
                for _, c in ipairs(match.chasers) do table.insert(t, c.assignedCar or '?') end
                return t
            end)(), ', ')))

        match.state = 'countdown'
        Citizen.Wait(500)
    end

    -- === Helicopter vote (normal mode with 3+ chasers) ===
    if isNormal and #match.chasers >= 3 then
        match.state = 'heli_vote'
        for _, chaser in ipairs(match.chasers) do
            TriggerClientEvent('blacklist:heliVote', chaser.source, ChaseConfig.HELI_VOTE_TIMEOUT)
        end
        TriggerClientEvent('blacklist:chaseHUD', match.runner.source, {
            action = 'warning',
            message = 'Chasers are voting on helicopter support...',
        })

        local voteDeadline = GetGameTimer() + (ChaseConfig.HELI_VOTE_TIMEOUT * 1000)
        while GetGameTimer() < voteDeadline do
            if match.state == 'finished' or match.state == 'cancelled' then return end
            local allVoted = true
            for _, chaser in ipairs(match.chasers) do
                if match.heliVotes[chaser.source] == nil then allVoted = false break end
            end
            if allVoted then break end
            Citizen.Wait(500)
        end

        local yesVotes = 0
        local totalVoters = #match.chasers
        for _, chaser in ipairs(match.chasers) do
            if match.heliVotes[chaser.source] == true then yesVotes = yesVotes + 1 end
        end

        if yesVotes > totalVoters / 2 then
            local heliIdx = math.random(#match.chasers)
            match.heliPilot = match.chasers[heliIdx].source
            print(('[Chase] Match #%d: Helicopter approved (%d/%d). Pilot: %s'):format(
                matchId, yesVotes, totalVoters, GetPlayerName(match.heliPilot) or match.heliPilot))
        else
            print(('[Chase] Match #%d: Helicopter denied (%d/%d)'):format(matchId, yesVotes, totalVoters))
        end

        match.state = 'countdown'
    end

    -- === Spawn vehicles ===
    if match.forceModel then
        TriggerEvent('blacklist:spawnPlayerWithModel', match.runner.source, match.forceModel,
            match.runnerX, match.runnerY, match.runnerZ, match.runnerHeading)

        for _, chaser in ipairs(match.chasers) do
            TriggerEvent('blacklist:spawnPlayerWithModel', chaser.source, match.forceModel,
                match.chaserX, match.chaserY, match.chaserZ, match.chaserHeading)
        end
    elseif isNormal then
        if match.runnerModel then
            TriggerEvent('blacklist:spawnPlayerWithModel', match.runner.source, match.runnerModel,
                match.runnerX, match.runnerY, match.runnerZ, match.runnerHeading)
        else
            TriggerEvent('blacklist:spawnPlayerVehicle', match.runner.source,
                match.runnerX, match.runnerY, match.runnerZ, match.runnerHeading)
        end

        for i, chaser in ipairs(match.chasers) do
            if chaser.source == match.heliPilot and match.heliSpawn then
                local hs = match.heliSpawn
                TriggerClientEvent('blacklist:spawnHelicopter', chaser.source,
                    hs.x, hs.y, hs.z, hs.h, ChaseConfig.HELI_MODEL)
            else
                local sp = match.chaserSpawns and match.chaserSpawns[i]
                local cx = sp and sp.x or match.chaserX
                local cy = sp and sp.y or match.chaserY
                local cz = sp and sp.z or match.chaserZ
                local ch = sp and sp.h or match.chaserHeading

                local carModel = chaser.assignedCar
                if carModel then
                    TriggerEvent('blacklist:spawnPlayerWithModel', chaser.source, carModel,
                        cx, cy, cz, ch)
                else
                    TriggerEvent('blacklist:spawnPlayerVehicle', chaser.source,
                        cx, cy, cz, ch)
                end
            end
        end
    else
        TriggerEvent('blacklist:spawnPlayerVehicle', match.runner.source,
            match.runnerX, match.runnerY, match.runnerZ, match.runnerHeading, match.forceTier)

        for _, chaser in ipairs(match.chasers) do
            TriggerEvent('blacklist:spawnPlayerVehicle', chaser.source,
                match.chaserX, match.chaserY, match.chaserZ, match.chaserHeading, match.forceTier)
        end
    end

    -- Tell normal mode clients to enable chase traffic
    if isNormal then
        local allSrc = getAllMatchSources(match)
        for _, src in ipairs(allSrc) do
            TriggerClientEvent('blacklist:chaseTrafficMode', src, true)
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

    -- Abort if someone disconnected during spawn wait
    if match.state == 'finished' or match.state == 'cancelled' then
        print(('[Chase] Match #%d aborted — player left during spawn'):format(matchId))
        return
    end

    for _, src in ipairs(allSources) do
        if not GetPlayerName(src) then
            cancelMatch(matchId, 'player_left_during_setup')
            print(('[Chase] Match #%d aborted — player %d gone after spawn'):format(matchId, src))
            return
        end
    end

    -- Freeze everyone during countdown
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseFreeze', src, true)
    end

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseCountdown', src, ChaseConfig.COUNTDOWN_DURATION)
    end

    Citizen.Wait(ChaseConfig.COUNTDOWN_DURATION * 1000)

    -- Abort if someone disconnected during countdown
    if match.state == 'finished' or match.state == 'cancelled' then
        print(('[Chase] Match #%d aborted — player left during countdown'):format(matchId))
        return
    end

    for _, src in ipairs(allSources) do
        if not GetPlayerName(src) then
            cancelMatch(matchId, 'player_left_during_setup')
            print(('[Chase] Match #%d aborted — player %d gone after countdown'):format(matchId, src))
            return
        end
    end

    -- Unfreeze everyone simultaneously
    match.state = 'active'
    match.startTime = GetGameTimer()

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseFreeze', src, false)
    end

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'start',
            duration = match.duration,
            role = src == match.runner.source and 'runner' or 'chaser',
            policeCode = match.policeCode,
            isHeliPilot = src == match.heliPilot,
            mode = match.mode,
            runnerServerId = match.runner.source,
        })
    end

    print(('[Chase] Match #%d started (%s mode, %ds) at %s%s'):format(
        matchId, match.mode, match.duration, matchData.locationName or 'unknown',
        match.heliPilot and (' | heli=' .. (GetPlayerName(match.heliPilot) or '?')) or ''))

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

    match.chaserDistances[source] = distance

    -- Catch: any single chaser close enough and slow enough
    if distance <= ChaseConfig.CATCH_DISTANCE and speed <= ChaseConfig.ARREST_MAX_SPEED then
        match.catchTimer = match.catchTimer + 0.5
        match.escapeTimer = 0
        match.boxingTimer = 0
        if match.catchTimer >= ChaseConfig.CATCH_TIME then
            endMatch(matchId, 'chaser', 'caught')
            return
        end
    else
        match.catchTimer = 0
    end

    -- Escape: ALL chasers must be beyond escape distance
    local allFar = true
    for _, c in ipairs(match.chasers) do
        local d = match.chaserDistances[c.source]
        if not d or d < ChaseConfig.ESCAPE_DISTANCE then
            allFar = false
            break
        end
    end

    if allFar then
        match.escapeTimer = match.escapeTimer + 0.5
        if match.escapeTimer >= match.escapeTime then
            endMatch(matchId, 'runner', 'escaped')
            return
        end
    else
        match.escapeTimer = 0
    end

    -- Boxing detection (normal mode only): runner barely moving + multiple chasers close
    if match.mode == 'normal' and match.policeCode then
        checkBoxing(match, matchId)
    end

    -- Find closest chaser distance for HUD display
    local closestDist = 99999
    for _, c in ipairs(match.chasers) do
        local d = match.chaserDistances[c.source]
        if d and d < closestDist then closestDist = d end
    end

    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'distance',
            distance = math.min(closestDist, 400),
            catchProgress = match.catchTimer / ChaseConfig.CATCH_TIME,
            escapeProgress = match.escapeTimer / match.escapeTime,
            policeCode = match.policeCode,
        })
    end
end)

-- ========================
-- Runner speed report (for boxing detection)
-- ========================

RegisterNetEvent('blacklist:reportRunnerSpeed')
AddEventHandler('blacklist:reportRunnerSpeed', function(speed)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'active' then return end
    if source ~= match.runner.source then return end

    match.runnerSpeed = tonumber(speed) or 0.0
end)

-- ========================
-- Boxing win condition check
-- ========================

function checkBoxing(match, matchId)
    local runnerSpeed = match.runnerSpeed or 999
    if runnerSpeed > ChaseConfig.BOX_SPEED_THRESHOLD then
        match.boxingTimer = 0
        return
    end

    local closeChasers = 0
    for _, c in ipairs(match.chasers) do
        local d = match.chaserDistances[c.source]
        if d and d <= ChaseConfig.BOX_CHASER_RADIUS then
            closeChasers = closeChasers + 1
        end
    end

    if closeChasers >= ChaseConfig.BOX_MIN_CHASERS then
        match.boxingTimer = match.boxingTimer + 0.5
        if match.boxingTimer >= ChaseConfig.BOX_TIME then
            local allSources = getAllMatchSources(match)
            for _, src in ipairs(allSources) do
                TriggerClientEvent('blacklist:chaseHUD', src, {
                    action = 'warning',
                    message = 'Runner has been BOXED IN!',
                })
            end
            endMatch(matchId, 'chaser', 'boxed')
        end
    else
        match.boxingTimer = 0
    end
end

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
AddEventHandler('blacklist:reportViolation', function(violationType, extraData)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'active' then return end

    local playerName = GetPlayerName(source)
    local allSources = getAllMatchSources(match)

    if violationType == 'runner_jump' then
        if match.policeCode then
            escalatePoliceCode(matchId, 'Runner big jump')
        else
            for _, src in ipairs(allSources) do
                TriggerClientEvent('blacklist:chaseHUD', src, {
                    action = 'warning',
                    message = playerName .. ': Illegal jump — DISQUALIFIED!',
                })
            end
            print(('[Chase] Match #%d: %s DQ — runner illegal jump'):format(matchId, playerName))
            endMatch(matchId, 'chaser', 'runner_disqualified_jump')
        end

    elseif violationType == 'runner_ram_pd' then
        if match.policeCode then
            escalatePoliceCode(matchId, 'Runner rammed PD')
        end

    elseif violationType == 'chaser_pit' then
        local pitSpeed = tonumber(extraData) or 0

        if match.policeCode then
            local allowedSpeed = ChaseConfig.PIT_SPEED_LIMITS[match.policeCode] or 0
            if pitSpeed <= allowedSpeed then
                print(('[Chase] Match #%d: %s legal PIT at %d mph (code %s allows %d)'):format(
                    matchId, playerName, pitSpeed, match.policeCode, allowedSpeed))
                return
            end
        end

        match.pitStrikes[source] = (match.pitStrikes[source] or 0) + 1
        local count = match.pitStrikes[source]

        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:chaseHUD', src, {
                action = 'warning',
                message = playerName .. ': Illegal PIT! (' .. count .. '/' .. ChaseConfig.MAX_PIT_STRIKES .. ')',
            })
        end

        print(('[Chase] Match #%d: %s pit strike %d/%d (speed=%d, code=%s)'):format(
            matchId, playerName, count, ChaseConfig.MAX_PIT_STRIKES, pitSpeed, match.policeCode or 'ranked'))

        if count >= ChaseConfig.MAX_PIT_STRIKES then
            endMatch(matchId, 'runner', 'chaser_disqualified_pit')
        end

    elseif violationType == 'runner_brake_check' then
        local runnerSource = match.runner.source
        match.brakeCheckStrikes[runnerSource] = (match.brakeCheckStrikes[runnerSource] or 0) + 1
        local count = match.brakeCheckStrikes[runnerSource]

        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:chaseHUD', src, {
                action = 'warning',
                message = (GetPlayerName(runnerSource) or 'Runner') .. ': Brake-check violation! (' .. count .. '/' .. ChaseConfig.MAX_BRAKE_CHECK_STRIKES .. ')',
            })
        end

        print(('[Chase] Match #%d: Runner brake-check strike %d/%d'):format(matchId, count, ChaseConfig.MAX_BRAKE_CHECK_STRIKES))

        if count >= ChaseConfig.MAX_BRAKE_CHECK_STRIKES then
            endMatch(matchId, 'chaser', 'runner_disqualified_brake_check')
        end

    elseif violationType == 'runner_water' then
        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:chaseHUD', src, {
                action = 'warning',
                message = playerName .. ': Drove into water — DISQUALIFIED!',
            })
        end
        print(('[Chase] Match #%d: %s DQ — runner in water'):format(matchId, playerName))
        endMatch(matchId, 'chaser', 'runner_disqualified_water')

    elseif violationType == 'runner_terrain' then
        if match.policeCode then
            escalatePoliceCode(matchId, 'Runner off-road abuse')
        else
            for _, src in ipairs(allSources) do
                TriggerClientEvent('blacklist:chaseHUD', src, {
                    action = 'warning',
                    message = playerName .. ': Illegal terrain — DISQUALIFIED!',
                })
            end
            print(('[Chase] Match #%d: %s DQ — runner terrain abuse'):format(matchId, playerName))
            endMatch(matchId, 'chaser', 'runner_disqualified_terrain')
        end

    elseif violationType == 'runner_died' then
        for _, src in ipairs(allSources) do
            TriggerClientEvent('blacklist:chaseHUD', src, {
                action = 'warning',
                message = (playerName or 'Runner') .. ' has been eliminated!',
            })
        end
        print(('[Chase] Match #%d: Runner died'):format(matchId))
        endMatch(matchId, 'chaser', 'runner_died')
    end
end)

-- ========================
-- Police code escalation (normal mode)
-- ========================

function escalatePoliceCode(matchId, reason)
    local match = activeMatches[matchId]
    if not match or not match.policeCode then return end

    local currentIdx = POLICE_CODE_INDEX[match.policeCode] or 1
    if currentIdx >= #POLICE_CODE_ORDER then return end

    local newCode = POLICE_CODE_ORDER[currentIdx + 1]
    match.policeCode = newCode

    local pitLimit = ChaseConfig.PIT_SPEED_LIMITS[newCode] or 0
    local allSources = getAllMatchSources(match)

    for _, src in ipairs(allSources) do
        TriggerClientEvent('blacklist:chaseHUD', src, {
            action = 'codeChange',
            policeCode = newCode,
            pitLimit = pitLimit,
            reason = reason,
        })
    end

    print(('[Chase] Match #%d: Police code escalated to %s (%s) | PIT limit: %d mph'):format(
        matchId, newCode:upper(), reason, pitLimit))
end

-- ========================
-- Helicopter vote response
-- ========================

RegisterNetEvent('blacklist:heliVoteResponse')
AddEventHandler('blacklist:heliVoteResponse', function(vote)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'heli_vote' then return end

    match.heliVotes[source] = (vote == true)
end)

-- ========================
-- Car pick response
-- ========================

RegisterNetEvent('blacklist:carPickResponse')
AddEventHandler('blacklist:carPickResponse', function(model)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'car_pick' then return end
    if match.carPicks[source] then return end

    local isRunner = source == match.runner.source
    local pool = isRunner and match.runnerCarPool or match.chaserCarPool

    local valid = false
    for _, m in ipairs(pool) do
        if m == model then valid = true break end
    end

    if valid then
        match.carPicks[source] = model
        print(('[Chase] Match #%d: %s picked %s'):format(matchId, GetPlayerName(source) or source, model))
    end
end)

-- ========================
-- Vehicle repair routing
-- ========================

RegisterNetEvent('blacklist:requestRepair')
AddEventHandler('blacklist:requestRepair', function(target)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state ~= 'active' then return end

    if target == 'self' then
        TriggerClientEvent('blacklist:repairVehicle', source)
        print(('[Chase] Match #%d: Repairing %s (self-request)'):format(matchId, GetPlayerName(source) or source))
    elseif target == 'opponent' then
        local isChaser = false
        for _, c in ipairs(match.chasers) do
            if c.source == source then isChaser = true break end
        end

        if isChaser then
            TriggerClientEvent('blacklist:repairVehicle', match.runner.source)
            print(('[Chase] Match #%d: Repairing runner (opponent-request from chaser)'):format(matchId))
        else
            for _, c in ipairs(match.chasers) do
                TriggerClientEvent('blacklist:repairVehicle', c.source)
            end
            print(('[Chase] Match #%d: Repairing chaser(s) (opponent-request from runner)'):format(matchId))
        end
    end
end)

-- ========================
-- End match
-- ========================

-- ========================
-- Disconnect reason classification
-- ========================

local function isIntentionalQuit(reason)
    if not reason then return false end
    local r = reason:lower()
    return r:find('exiting') ~= nil or r:find('quit') ~= nil
end

-- ========================
-- Cancel match (no winner, no MMR change)
-- Used when a player disconnects due to connection loss or during setup
-- ========================

function cancelMatch(matchId, reason)
    local match = activeMatches[matchId]
    if not match or match.state == 'finished' or match.state == 'cancelled' then return end

    match.state = 'cancelled'

    local allSources = getAllMatchSources(match)
    for _, src in ipairs(allSources) do
        if GetPlayerName(src) then
            TriggerClientEvent('blacklist:chaseFreeze', src, false)
            TriggerClientEvent('blacklist:chaseHUD', src, {
                action = 'end',
                won = false,
                winnerRole = 'none',
                reason = reason,
                duration = 0,
                isRanked = false,
            })
        end
    end

    Citizen.SetTimeout(5000, function()
        returnPlayersToMenu(matchId)
    end)

    print(('[Chase] ^3Match #%d CANCELLED: %s^0'):format(matchId, reason))
end

-- ========================
-- End match (with winner/loser and ranked processing)
-- ========================

function endMatch(matchId, winnerRole, reason)
    local match = activeMatches[matchId]
    if not match or match.state == 'finished' or match.state == 'cancelled' then return end

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
        if GetPlayerName(src) then
            SetPlayerRoutingBucket(src, 0)
            TriggerClientEvent('blacklist:chaseTrafficMode', src, false)
            TriggerClientEvent('blacklist:returnToMenu', src)
        end
        playerMatchMap[src] = nil
    end
    TriggerEvent('blacklist:matchEnded', allSources)
    activeMatches[matchId] = nil
end

-- ========================
-- Player disconnect during match
-- ========================

AddEventHandler('playerDropped', function(reason)
    local source = source
    local matchId = playerMatchMap[source]
    if not matchId then return end

    local match = activeMatches[matchId]
    if not match or match.state == 'finished' or match.state == 'cancelled' then
        playerMatchMap[source] = nil
        spawnReady[source] = nil
        return
    end

    local playerName = GetPlayerName(source) or 'Unknown'
    local intentional = isIntentionalQuit(reason)

    print(('[Chase] %s dropped from match #%d | reason="%s" | intentional=%s'):format(
        playerName, matchId, reason or 'unknown', tostring(intentional)))

    -- During setup: always cancel (match never started, nobody should lose)
    if match.state == 'countdown' then
        cancelMatch(matchId, 'player_left_during_setup')
        playerMatchMap[source] = nil
        spawnReady[source] = nil
        return
    end

    -- Active match: intentional quit = quitter loses, connection loss = cancel
    if intentional then
        local isRunner = (source == match.runner.source)
        if isRunner then
            endMatch(matchId, 'chaser', 'runner_quit')
        else
            for i, c in ipairs(match.chasers) do
                if c.source == source then
                    table.remove(match.chasers, i)
                    break
                end
            end
            if #match.chasers == 0 then
                endMatch(matchId, 'runner', 'chaser_quit')
            end
        end
    else
        cancelMatch(matchId, 'connection_lost')
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

    local newModel = exports.matchmaking:GetRandomModelForTier(oldMatch.forceTier) or oldMatch.forceModel

    TriggerEvent('blacklist:startChaseMatch', {
        mode = oldMatch.mode,
        isCrossTier = oldMatch.isCrossTier,
        forceTier = oldMatch.forceTier,
        forceModel = newModel,
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
-- Anti-cheat telemetry logs from client
-- ========================

RegisterNetEvent('blacklist:chaseLog')
AddEventHandler('blacklist:chaseLog', function(logData)
    local source = source
    local name = GetPlayerName(source) or 'Unknown'
    local matchId = playerMatchMap[source] or 0
    print(('[AC-LOG] Match#%d | %s | %s'):format(matchId, name, logData.message or ''))

    -- Relay runner environment crashes to all chasers with full context
    if logData.message and string.find(logData.message, 'RUNNER_ENV_CRASH') then
        local match = activeMatches[matchId]
        if match then
            local speed    = tonumber(string.match(logData.message, 'speed=(%d+)')) or 0
            local severity = string.match(logData.message, 'severity=(%w+)') or 'UNKNOWN'
            for _, chaser in ipairs(match.chasers) do
                TriggerClientEvent('blacklist:runnerCrashInfo', chaser.source, {
                    speed    = speed,
                    severity = severity,
                })
            end
        end
    end
end)

print('[Chase] ^2Game mode loaded  |  AC Telemetry relay active^0')
