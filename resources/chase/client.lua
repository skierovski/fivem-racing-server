-- ============================================================
-- Chase/Run game mode: client-side HUD, distance tracking, anti-cheat
-- ============================================================

local isInMatch = false
local isPostMatch = false
local myRole = nil -- 'chaser' or 'runner'
local matchTimer = 0
local matchStartTime = 0
local isFrozen = false
local airborneTimer = 0.0

-- ========================
-- Freeze control
-- ========================

RegisterNetEvent('blacklist:chaseFreeze')
AddEventHandler('blacklist:chaseFreeze', function(freeze)
    isFrozen = freeze
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        FreezeEntityPosition(vehicle, freeze)
    end
    FreezeEntityPosition(ped, freeze)
end)

-- ========================
-- Countdown
-- ========================

RegisterNetEvent('blacklist:chaseCountdown')
AddEventHandler('blacklist:chaseCountdown', function(seconds)
    isInMatch = true
    exports.base:SetPlayerState('in_match')
    SendNUIMessage({ action = 'countdown', seconds = seconds })

    -- Kill the freeroam ghost threads (root cause of blinking ghost)
    TriggerEvent('blacklist:enableGhostMode', false)

    -- Aggressive one-time ghost cleanup on match start
    local myPed = PlayerPedId()
    local myVehicle = GetVehiclePedIsIn(myPed, false)

    ResetEntityAlpha(myPed)
    SetEntityCollision(myPed, true, true)
    if myVehicle ~= 0 then
        ResetEntityAlpha(myVehicle)
        SetEntityCollision(myVehicle, true, true)
        SetEntityAlpha(myVehicle, 255, false)
    end

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local otherPed = GetPlayerPed(playerId)
            if otherPed ~= 0 then
                ResetEntityAlpha(otherPed)
                SetEntityCollision(otherPed, true, true)
                SetEntityAlpha(otherPed, 255, false)

                local otherVehicle = GetVehiclePedIsIn(otherPed, false)
                if otherVehicle ~= 0 then
                    ResetEntityAlpha(otherVehicle)
                    SetEntityCollision(otherVehicle, true, true)
                    SetEntityAlpha(otherVehicle, 255, false)
                end
            end
        end
    end
end)

-- ========================
-- HUD updates from server
-- ========================

RegisterNetEvent('blacklist:chaseHUD')
AddEventHandler('blacklist:chaseHUD', function(data)
    if data.action == 'headstart' then
        myRole = data.role
        SendNUIMessage({
            action = 'headstart',
            role = data.role,
            duration = data.duration,
        })

    elseif data.action == 'start' then
        myRole = data.role
        matchTimer = data.duration
        matchStartTime = GetGameTimer()
        SendNUIMessage({
            action = 'start',
            role = data.role,
            duration = data.duration,
        })

    elseif data.action == 'distance' then
        SendNUIMessage({
            action = 'distance',
            distance = math.floor(data.distance),
            catchProgress = data.catchProgress,
            escapeProgress = data.escapeProgress,
        })

    elseif data.action == 'warning' then
        SendNUIMessage({
            action = 'warning',
            message = data.message,
        })

    elseif data.action == 'end' then
        isInMatch = false
        isPostMatch = true
        myRole = nil
        SendNUIMessage({
            action = 'matchEnd',
            won = data.won,
            winnerRole = data.winnerRole,
            reason = data.reason,
            duration = data.duration,
            isRanked = data.isRanked,
        })
        if data.isRanked then
            SetNuiFocus(true, true)
        end
    end
end)

-- ========================
-- MMR result from ranked system
-- ========================

RegisterNetEvent('blacklist:matchResult')
AddEventHandler('blacklist:matchResult', function(data)
    SendNUIMessage({
        action = 'mmrUpdate',
        mmrChange = data.mmrChange,
        newMMR = data.newMMR,
        newTier = data.newTier,
        oldTier = data.oldTier,
        promoted = data.promoted,
        demoted = data.demoted,
        isPlacement = data.isPlacement,
        placementMatch = data.placementMatch,
        placementTotal = data.placementTotal,
    })
end)

-- ========================
-- Rematch
-- ========================

RegisterNUICallback('requestRematch', function(data, cb)
    TriggerServerEvent('blacklist:requestRematch')
    cb({})
end)

RegisterNetEvent('blacklist:rematchStatus')
AddEventHandler('blacklist:rematchStatus', function(status)
    SendNUIMessage({ action = 'rematchStatus', status = status })
    if status == 'accepted' then
        isPostMatch = false
        SetNuiFocus(false, false)
    end
end)

-- ========================
-- Chase HUD cleanup on return to menu
-- ========================

RegisterNetEvent('blacklist:returnToMenu')
AddEventHandler('blacklist:returnToMenu', function()
    isInMatch = false
    isPostMatch = false
    myRole = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideAll' })
end)

-- ========================
-- Distance tracking (chaser only, NO blip)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)

        if isInMatch and myRole == 'chaser' then
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)

            local closestDist = 99999.0

            for _, playerId in ipairs(GetActivePlayers()) do
                if playerId ~= PlayerId() then
                    local otherPed = GetPlayerPed(playerId)
                    if otherPed ~= 0 then
                        local otherCoords = GetEntityCoords(otherPed)
                        local dist = #(myCoords - otherCoords)
                        if dist < closestDist then
                            closestDist = dist
                        end
                    end
                end
            end

            -- If opponent is beyond streaming range (~400m), GTA can't track them.
            if closestDist >= 99999.0 then
                closestDist = 999.0
            end

            local myVehicle = GetVehiclePedIsIn(myPed, false)
            local mySpeed = myVehicle ~= 0 and GetEntitySpeed(myVehicle) or 0.0

            TriggerServerEvent('blacklist:reportDistance', closestDist, math.min(closestDist, 400.0), mySpeed)
        end
    end
end)

-- ========================
-- Timer display update
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        if isInMatch and matchStartTime > 0 then
            local elapsed = (GetGameTimer() - matchStartTime) / 1000
            local remaining = math.max(0, matchTimer - elapsed)
            SendNUIMessage({
                action = 'timer',
                remaining = math.floor(remaining),
            })
        end
    end
end)

-- ========================
-- Traffic suppression + vehicle exit block + ghost nuke
-- Runs every frame during match and post-match results screen
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if isInMatch or isPostMatch then
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            SetGarbageTrucks(false)
            SetRandomBoats(false)
            SetRandomTrains(false)

            for i = 1, 15 do
                EnableDispatchService(i, false)
            end

            DisableControlAction(0, 75, true)  -- F (exit vehicle)
            DisableControlAction(0, 23, true)  -- F (enter vehicle)

            -- Per-frame ghost nuke: force full visibility + collision on ALL entities
            local myPed = PlayerPedId()
            local myVehicle = GetVehiclePedIsIn(myPed, false)

            SetEntityAlpha(myPed, 255, false)
            SetEntityCollision(myPed, true, true)
            if myVehicle ~= 0 then
                SetEntityAlpha(myVehicle, 255, false)
                SetEntityCollision(myVehicle, true, true)
            end

            for _, playerId in ipairs(GetActivePlayers()) do
                if playerId ~= PlayerId() then
                    local otherPed = GetPlayerPed(playerId)
                    if otherPed ~= 0 then
                        SetEntityAlpha(otherPed, 255, false)
                        SetEntityCollision(otherPed, true, true)

                        local otherVehicle = GetVehiclePedIsIn(otherPed, false)
                        if otherVehicle ~= 0 then
                            SetEntityAlpha(otherVehicle, 255, false)
                            SetEntityCollision(otherVehicle, true, true)
                        end
                    end
                end
            end
        end
    end
end)

-- ========================
-- Periodic NPC cleanup during match and post-match
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(3000)

        if isInMatch or isPostMatch then
            local playerPed = PlayerPedId()

            local handle, ped = FindFirstPed()
            local success = true
            while success do
                if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    DeleteEntity(ped)
                end
                success, ped = FindNextPed(handle)
            end
            EndFindPed(handle)

            local myVeh = GetVehiclePedIsIn(playerPed, false)
            local vHandle, veh = FindFirstVehicle()
            success = true
            while success do
                if veh ~= myVeh and DoesEntityExist(veh) then
                    local driver = GetPedInVehicleSeat(veh, -1)
                    if driver == 0 or not IsPedAPlayer(driver) then
                        DeleteEntity(veh)
                    end
                end
                success, veh = FindNextVehicle(vHandle)
            end
            EndFindVehicle(vHandle)
        end
    end
end)

-- ============================================================
-- ANTI-CHEAT TELEMETRY v1.0 — Comprehensive F8 Console Logger
-- Press F8 in-game to view all logs in real time
-- ============================================================

local AC_VERSION = '1.0'

-- F8 color codes: ^1=red ^2=green ^3=yellow ^4=blue ^5=cyan ^6=purple ^0=reset
local CLR = { R='^1', G='^2', Y='^3', B='^4', C='^5', P='^6', X='^0' }

-- ========================
-- Telemetry state
-- ========================

local telem = {
    wasAirborne       = false,
    airborneStart     = 0,
    airborneStartSpd  = 0,
    airborneStartHgt  = 0,
    airborneMaxHgt    = 0,
    airborneCause     = 'UNKNOWN',
    preAirborneSlope  = 0,

    lastCollisionTime = 0,
    lastEnvCrash      = nil,
    lastWallHitTime   = 0,
    lastWallHitSpeed  = 0,

    lastSpeed         = 0,
    lastHeading       = 0,
    isBraking         = false,
    brakeStartTime    = 0,
    isAccelerating    = false,
    steeringAngle     = 0,

    oppPrevSpeed      = 0,
    oppPrevDist       = 999,
    oppSpeedHistory   = {},
    maxOppSamples     = 10,

    lastBrakeCheck    = nil,
    brakeCheckCount   = 0,

    speedSamples      = {},
    maxSpeedSamples   = 20,

    pitch             = 0,
    roll              = 0,
    lastTerrainLog    = 0,
    lastTerrainType   = 'FLAT',

    totalCollisions   = 0,
    playerContacts    = 0,
    envCollisions     = 0,
    airborneCount     = 0,
    spinOuts          = 0,
    wallBounces       = 0,
    lastSummaryTime   = 0,
}

-- ========================
-- Logging
-- ========================

local function matchTime()
    if matchStartTime and matchStartTime > 0 then
        return (GetGameTimer() - matchStartTime) / 1000.0
    end
    return 0.0
end

local function acLog(level, msg)
    local color = CLR.G
    if level == 'WARN' then color = CLR.Y
    elseif level == 'CRIT' then color = CLR.R
    elseif level == 'DATA' then color = CLR.C
    elseif level == 'ANLZ' then color = CLR.P end

    local role = (myRole or '???'):upper()
    local t = ('%.1f'):format(matchTime())

    print(('%s[AC]%s %s[%s]%s [%ss] [%s] %s'):format(
        CLR.C, CLR.X, color, level, CLR.X, t, role, msg))

    TriggerServerEvent('blacklist:chaseLog', {
        message = ('[%s] [%ss] [%s] %s'):format(level, t, role, msg)
    })
end

-- ========================
-- Vehicle data snapshot
-- ========================

local function getVehicleData(vehicle)
    if not vehicle or vehicle == 0 then return nil end

    local speed   = GetEntitySpeed(vehicle)
    local coords  = GetEntityCoords(vehicle)
    local fwd     = GetEntityForwardVector(vehicle)
    local rotVel  = GetEntityRotationVelocity(vehicle)

    return {
        entity    = vehicle,
        speed     = speed,
        speedKmh  = math.floor(speed * 3.6),
        heading   = GetEntityHeading(vehicle),
        coords    = coords,
        pitch     = GetEntityPitch(vehicle),
        roll      = GetEntityRoll(vehicle),
        height    = GetEntityHeightAboveGround(vehicle),
        fwd       = fwd,
        vel       = GetEntityVelocity(vehicle),
        rotVel    = rotVel,
        yawRate   = math.abs(rotVel.z) * 57.2958,
        steering  = GetVehicleSteeringAngle(vehicle),
        onWheels  = IsVehicleOnAllWheels(vehicle),
        inAir     = IsEntityInAir(vehicle),
        upright   = IsEntityUpright(vehicle),
        upsideDown = IsEntityUpsidedown(vehicle),
        braking   = IsControlPressed(0, 72) or IsDisabledControlPressed(0, 72),
        throttle  = IsControlPressed(0, 71) or IsDisabledControlPressed(0, 71),
    }
end

-- ========================
-- Closest opponent snapshot
-- ========================

local function getOpponentData()
    local myPed    = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local best     = {
        dist = 99999, speed = 0, speedKmh = 0, heading = 0,
        ped = 0, vehicle = 0, coords = myCoords,
        fwd = vector3(0,1,0), yawRate = 0, braking = false,
    }

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local otherPed = GetPlayerPed(playerId)
            if otherPed ~= 0 then
                local otherCoords = GetEntityCoords(otherPed)
                local dist = #(myCoords - otherCoords)
                if dist < best.dist then
                    best.dist    = dist
                    best.ped     = otherPed
                    best.coords  = otherCoords
                    local veh = GetVehiclePedIsIn(otherPed, false)
                    best.vehicle = veh
                    if veh ~= 0 then
                        best.speed    = GetEntitySpeed(veh)
                        best.speedKmh = math.floor(best.speed * 3.6)
                        best.heading  = GetEntityHeading(veh)
                        best.fwd      = GetEntityForwardVector(veh)
                        local rv      = GetEntityRotationVelocity(veh)
                        best.yawRate  = math.abs(rv.z) * 57.2958
                        best.braking  = false
                    end
                end
            end
        end
    end

    return best
end

-- ========================
-- Utilities
-- ========================

local function headingDiff(h1, h2)
    local diff = math.abs(h1 - h2)
    if diff > 180 then diff = 360 - diff end
    return diff
end

local function addSpeedSample(kmh)
    table.insert(telem.speedSamples, kmh)
    if #telem.speedSamples > telem.maxSpeedSamples then
        table.remove(telem.speedSamples, 1)
    end
end

local function getSpeedTrend()
    local n = #telem.speedSamples
    if n < 4 then return 'STABLE', 0 end
    local recent = telem.speedSamples[n]
    local older  = telem.speedSamples[math.max(1, n - 5)]
    local diff   = recent - older
    if diff < -15 then return 'BRAKING_HARD', diff
    elseif diff < -5 then return 'DECELERATING', diff
    elseif diff > 10 then return 'ACCELERATING', diff
    else return 'STABLE', diff end
end

-- ========================
-- Pit maneuver & collision analysis
-- ========================

local function analyzePitManeuver(myData, opp)
    local toOpp     = opp.coords - myData.coords
    local toOppLen  = #toOpp
    if toOppLen < 0.01 then toOppLen = 0.01 end
    local toOppN    = toOpp / toOppLen

    local approachDot   = myData.fwd.x * toOppN.x + myData.fwd.y * toOppN.y
    local approachAngle = math.acos(math.max(-1, math.min(1, approachDot))) * 57.2958

    local hdgDiff = headingDiff(myData.heading, opp.heading)
    local spdDiff = myData.speedKmh - opp.speedKmh

    local contactType = 'SIDESWIPE'
    if approachAngle < 30 then
        contactType = hdgDiff < 45 and 'REAR_END' or 'T_BONE'
    elseif approachAngle > 150 then
        contactType = 'HEAD_ON'
    elseif hdgDiff < 45 then
        contactType = 'PIT_MANEUVER'
    end

    local intentScore = 0
    local factors = {}

    if math.abs(myData.steering) > 10 then
        intentScore = intentScore + 2
        table.insert(factors, ('steering=%.0f°'):format(myData.steering))
    end

    if not telem.isBraking then
        intentScore = intentScore + 1
        table.insert(factors, 'no_brake')
    else
        intentScore = intentScore - 2
        local brakeDur = (GetGameTimer() - telem.brakeStartTime) / 1000.0
        table.insert(factors, ('braking_%.1fs'):format(brakeDur))
    end

    if spdDiff > 30 then
        intentScore = intentScore + 2
        table.insert(factors, ('closing_fast+%d'):format(spdDiff))
    elseif spdDiff > 15 then
        intentScore = intentScore + 1
    end

    if hdgDiff < 15 and contactType == 'SIDESWIPE' then
        intentScore = intentScore - 1
        table.insert(factors, 'parallel')
    end

    -- Opponent braked / slowed suddenly (brake-check scenario)
    if opp.speedKmh < telem.oppPrevSpeed - 20 then
        intentScore = intentScore - 1
        table.insert(factors, ('opp_braked_%d→%d'):format(telem.oppPrevSpeed, opp.speedKmh))
    end

    if telem.lastEnvCrash and (GetGameTimer() - telem.lastEnvCrash.time) < 3000 and myRole == 'chaser' then
        intentScore = intentScore - 2
        local gap = GetGameTimer() - telem.lastEnvCrash.time
        table.insert(factors, ('follow_up_%dms'):format(gap))
    end

    -- Runner brake-checked right before contact — chaser likely couldn't avoid
    if telem.lastBrakeCheck and (GetGameTimer() - telem.lastBrakeCheck.time) < 3000 and myRole == 'chaser' then
        intentScore = intentScore - 3
        local gap = GetGameTimer() - telem.lastBrakeCheck.time
        table.insert(factors, ('BRAKE_CHECKED_%dms_ago_opp_%d→%d'):format(
            gap, telem.lastBrakeCheck.oppSpeedBefore, telem.lastBrakeCheck.oppSpeedAfter))
    end

    local intent = 'LIKELY_ACCIDENTAL'
    if intentScore >= 3 then intent = 'LIKELY_INTENTIONAL'
    elseif intentScore >= 1 then intent = 'UNCLEAR' end

    return {
        contactType   = contactType,
        approachAngle = approachAngle,
        headingDiff   = hdgDiff,
        speedDiff     = spdDiff,
        intent        = intent,
        intentScore   = intentScore,
        factors       = table.concat(factors, ', '),
    }
end

-- ========================
-- Airborne cause detection
-- ========================

local function determineAirborneCause(myData)
    local now = GetGameTimer()

    if telem.lastWallHitTime > 0 and (now - telem.lastWallHitTime) < 500 then
        return 'WALL_BOUNCE'
    end

    if math.abs(telem.pitch) > 10 then
        return 'HILL'
    end

    if telem.lastCollisionTime > 0 and (now - telem.lastCollisionTime) < 500 then
        return 'PLAYER_HIT'
    end

    if myData.height < 1.5 then
        return 'BUMP'
    end

    return 'UNKNOWN'
end

-- ========================
-- Match lifecycle logging (hooks into existing HUD events)
-- ========================

RegisterNetEvent('blacklist:chaseHUD')
AddEventHandler('blacklist:chaseHUD', function(data)
    if data.action == 'start' then
        telem.totalCollisions = 0
        telem.playerContacts  = 0
        telem.envCollisions   = 0
        telem.airborneCount   = 0
        telem.spinOuts        = 0
        telem.wallBounces     = 0
        telem.speedSamples    = {}
        telem.oppSpeedHistory = {}
        telem.lastEnvCrash    = nil
        telem.lastBrakeCheck  = nil
        telem.brakeCheckCount = 0
        telem.lastSummaryTime = GetGameTimer()
        telem.lastTerrainType = 'FLAT'

        acLog('INFO', ('========== MATCH START ==========  role=%s  duration=%ds'):format(
            data.role or '?', data.duration or 0))

    elseif data.action == 'end' then
        acLog('INFO', ('========== MATCH END ==========  won=%s  reason=%s'):format(
            tostring(data.won), data.reason or '?'))
        acLog('DATA', ('FINAL STATS | contacts: player=%d env=%d total=%d | airborne=%d | spins=%d | wall_bounces=%d | brake_checks=%d'):format(
            telem.playerContacts, telem.envCollisions, telem.totalCollisions,
            telem.airborneCount, telem.spinOuts, telem.wallBounces, telem.brakeCheckCount))
    end
end)

-- ============================================================
-- THREAD 1 — Fast sampler (100 ms)
-- Airborne + Collision + Input state
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)

        if not isInMatch then
            telem.wasAirborne = false
            telem.airborneStart = 0
            goto continue
        end

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 then goto continue end

        local vd = getVehicleData(vehicle)
        if not vd then goto continue end

        -- ---- Input tracking ----
        local wasBraking    = telem.isBraking
        telem.isBraking     = vd.braking
        telem.isAccelerating = vd.throttle
        telem.steeringAngle = vd.steering

        if vd.braking and not wasBraking then
            telem.brakeStartTime = GetGameTimer()
        end

        addSpeedSample(vd.speedKmh)
        telem.lastSpeed   = vd.speedKmh
        telem.lastHeading = vd.heading
        telem.pitch       = vd.pitch
        telem.roll        = vd.roll

        -- ======== AIRBORNE DETECTION ========

        if vd.inAir and not telem.wasAirborne then
            telem.wasAirborne       = true
            telem.airborneStart     = GetGameTimer()
            telem.airborneStartSpd  = vd.speedKmh
            telem.airborneStartHgt  = vd.height
            telem.airborneMaxHgt    = vd.height
            telem.preAirborneSlope  = telem.pitch
            telem.airborneCause     = determineAirborneCause(vd)
            telem.airborneCount     = telem.airborneCount + 1

            acLog('INFO', ('AIRBORNE START | spd=%d km/h | hgt=%.1fm | cause=%s | slope=%.1f° | steering=%.0f°'):format(
                vd.speedKmh, vd.height, telem.airborneCause, telem.pitch, vd.steering))

        elseif vd.inAir and telem.wasAirborne then
            if vd.height > telem.airborneMaxHgt then
                telem.airborneMaxHgt = vd.height
            end

        elseif not vd.inAir and telem.wasAirborne then
            local dur = (GetGameTimer() - telem.airborneStart) / 1000.0
            telem.wasAirborne = false

            local level = 'INFO'
            if dur >= 2.0 then level = 'CRIT'
            elseif dur >= 1.0 then level = 'WARN' end

            local landing = 'CLEAN'
            if vd.upsideDown then landing = 'UPSIDE_DOWN'
            elseif not vd.upright then landing = 'TUMBLED'
            elseif math.abs(vd.roll) > 30 then landing = 'ROUGH' end

            acLog(level, ('AIRBORNE END | dur=%.1fs | launch=%d km/h | land=%d km/h | max_hgt=%.1fm | cause=%s | landing=%s'):format(
                dur, telem.airborneStartSpd, vd.speedKmh, telem.airborneMaxHgt, telem.airborneCause, landing))

            if dur >= 2.0 and myRole == 'runner' then
                TriggerServerEvent('blacklist:reportViolation', 'runner_jump')
            end
            airborneTimer = 0.0
        end

        -- ======== COLLISION DETECTION ========

        if HasEntityCollidedWithAnything(vehicle) then
            local now = GetGameTimer()
            if now - telem.lastCollisionTime < 1500 then goto continue end
            telem.lastCollisionTime = now
            telem.totalCollisions   = telem.totalCollisions + 1

            local opp = getOpponentData()
            local isPlayerContact = opp.dist < 8.0

            if isPlayerContact then
                -- ---------- PLAYER CONTACT ----------
                telem.playerContacts = telem.playerContacts + 1

                local analysis = analyzePitManeuver(vd, opp)

                local spinInfo = ''
                if opp.yawRate > 45 then
                    spinInfo = (' | OPP_SPIN=YES %.0f°/s'):format(opp.yawRate)
                    telem.spinOuts = telem.spinOuts + 1
                end

                local brakeInfo = 'NO'
                if telem.isBraking then
                    local brakeDur = (GetGameTimer() - telem.brakeStartTime) / 1000.0
                    brakeInfo = ('YES %.1fs'):format(brakeDur)
                end

                local trend, _ = getSpeedTrend()

                local level = 'INFO'
                if analysis.intent == 'LIKELY_INTENTIONAL' then level = 'WARN' end

                acLog(level, ('CONTACT PLAYER | type=%s | intent=%s (score=%d) | my_spd=%d | opp_spd=%d km/h | dist=%.1fm'):format(
                    analysis.contactType, analysis.intent, analysis.intentScore, vd.speedKmh, opp.speedKmh, opp.dist))

                acLog(level, ('  > approach=%.0f° | hdg_diff=%.0f° | spd_diff=%+d | steer=%.0f° | brake=%s | trend=%s%s'):format(
                    analysis.approachAngle, analysis.headingDiff, analysis.speedDiff,
                    vd.steering, brakeInfo, trend, spinInfo))

                if #analysis.factors > 0 then
                    acLog('ANLZ', ('  > factors: %s'):format(analysis.factors))
                end

                -- Follow-up context: runner crashed → did chaser have time to react?
                if telem.lastEnvCrash and myRole == 'chaser' then
                    local gap = now - telem.lastEnvCrash.time
                    if gap < 3000 then
                        local reaction = 'NO_TIME'
                        if gap > 1500 then reaction = 'HAD_TIME'
                        elseif gap > 700 and telem.isBraking then reaction = 'TRIED_AVOID' end

                        acLog('ANLZ', ('  > FOLLOW-UP: runner crashed %dms ago @ %d km/h | reaction=%s | chaser_brake=%s | dist_at_crash=%.0fm'):format(
                            gap, telem.lastEnvCrash.speed, reaction, brakeInfo, opp.dist))
                    end
                end

                if myRole == 'chaser' then
                    local wasBrakeChecked = telem.lastBrakeCheck
                        and (now - telem.lastBrakeCheck.time) < 3000

                    if wasBrakeChecked then
                        local bcGap = now - telem.lastBrakeCheck.time
                        acLog('CRIT', ('  > !! BRAKE-CHECK → RAM !! runner braked %dms before contact (%d→%d km/h) | chaser NOT penalized'):format(
                            bcGap, telem.lastBrakeCheck.oppSpeedBefore, telem.lastBrakeCheck.oppSpeedAfter))
                    end

                    if analysis.intent == 'LIKELY_INTENTIONAL' then
                        acLog('CRIT', ('  > PIT STRIKE — intentional contact (score=%d)'):format(analysis.intentScore))
                        TriggerServerEvent('blacklist:reportViolation', 'chaser_pit')
                    end
                end

            else
                -- ---------- ENVIRONMENT COLLISION ----------
                telem.envCollisions = telem.envCollisions + 1

                local prevSpd   = #telem.speedSamples > 2 and telem.speedSamples[#telem.speedSamples - 2] or vd.speedKmh
                local speedLoss = prevSpd - vd.speedKmh

                local severity = 'LIGHT'
                if speedLoss > 50 then severity = 'HEAVY'
                elseif speedLoss > 20 then severity = 'MEDIUM' end

                telem.lastWallHitTime  = now
                telem.lastWallHitSpeed = vd.speedKmh

                local level = severity == 'HEAVY' and 'WARN' or 'INFO'

                acLog(level, ('COLLISION ENV | severity=%s | spd=%d km/h | lost=%d km/h | pitch=%.1f° | roll=%.1f° | opp_dist=%.0fm'):format(
                    severity, vd.speedKmh, speedLoss, vd.pitch, vd.roll, opp.dist))

                if myRole == 'runner' then
                    telem.lastEnvCrash = { time = now, speed = vd.speedKmh }
                    TriggerServerEvent('blacklist:chaseLog', {
                        message = ('RUNNER_ENV_CRASH | speed=%d km/h | severity=%s'):format(vd.speedKmh, severity),
                    })
                end

                if vd.inAir or vd.height > 1.5 then
                    telem.wallBounces = telem.wallBounces + 1
                    acLog('WARN', ('  > WALL BOUNCE | hgt=%.1fm | upright=%s | spd=%d km/h'):format(
                        vd.height, vd.upright and 'YES' or 'NO', vd.speedKmh))
                end
            end

            -- Track opponent speed for brake-check detection
            telem.oppPrevSpeed = opp.speedKmh
            telem.oppPrevDist  = opp.dist
        end

        ::continue::
    end
end)

-- ============================================================
-- THREAD 2 — Slow sampler (500 ms)
-- Terrain analysis + spin detection + periodic summary
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)

        if not isInMatch then goto skip end

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 then goto skip end

        local vd = getVehicleData(vehicle)
        if not vd then goto skip end

        local opp = getOpponentData()

        -- ---- Opponent speed history for brake-check detection ----
        table.insert(telem.oppSpeedHistory, opp.speedKmh)
        if #telem.oppSpeedHistory > telem.maxOppSamples then
            table.remove(telem.oppSpeedHistory, 1)
        end

        telem.oppPrevSpeed = opp.speedKmh
        telem.oppPrevDist  = opp.dist

        -- ---- Terrain classification ----
        local slopeAbs    = math.abs(vd.pitch)
        local terrainType = 'FLAT'
        if slopeAbs > 15 then terrainType = 'STEEP_HILL'
        elseif slopeAbs > 8 then terrainType = 'HILL'
        elseif slopeAbs > 3 then terrainType = 'SLOPE' end

        local rollTag = ''
        if math.abs(vd.roll) > 20 then rollTag = ' BANKED'
        elseif math.abs(vd.roll) > 8 then rollTag = ' TILTED' end

        local now = GetGameTimer()

        if terrainType ~= 'FLAT' and not vd.inAir and terrainType ~= telem.lastTerrainType
            and (now - telem.lastTerrainLog > 2000) then
            telem.lastTerrainLog  = now
            telem.lastTerrainType = terrainType
            acLog('DATA', ('TERRAIN | type=%s%s | pitch=%.1f° | roll=%.1f° | spd=%d km/h | wheels_down=%s'):format(
                terrainType, rollTag, vd.pitch, vd.roll, vd.speedKmh, vd.onWheels and 'YES' or 'NO'))
        elseif terrainType == 'FLAT' then
            telem.lastTerrainType = 'FLAT'
        end

        -- ---- Spin detection (loss of control, not from direct collision) ----
        if vd.yawRate > 90 and not vd.inAir then
            acLog('WARN', ('SPIN | yaw_rate=%.0f°/s | spd=%d km/h | wheels=%s | steer=%.0f° | roll=%.1f°'):format(
                vd.yawRate, vd.speedKmh, vd.onWheels and 'YES' or 'NO', vd.steering, vd.roll))
        end

        -- ---- BRAKE-CHECK DETECTION ----
        -- Analyzes opponent speed history for sharp intentional deceleration
        if myRole == 'chaser' and opp.dist < 35 then
            local nOpp = #telem.oppSpeedHistory
            if nOpp >= 3 then
                local oppNow    = telem.oppSpeedHistory[nOpp]
                local oppRecent = telem.oppSpeedHistory[math.max(1, nOpp - 2)]
                local oppDecel  = oppRecent - oppNow

                -- Opponent dropped 25+ km/h while near the chaser and chaser is faster
                if oppDecel > 25 and oppNow < vd.speedKmh then
                    local prevBC = telem.lastBrakeCheck
                    local isRepeat = prevBC and (now - prevBC.time) < 8000

                    telem.lastBrakeCheck = {
                        time           = now,
                        oppSpeedBefore = oppRecent,
                        oppSpeedAfter  = oppNow,
                        dist           = opp.dist,
                        mySpeed        = vd.speedKmh,
                    }
                    telem.brakeCheckCount = telem.brakeCheckCount + 1

                    local repeatTag = isRepeat and ' | !! REPEATED !!' or ''

                    acLog('CRIT', ('BRAKE-CHECK #%d | opp_spd %d→%d km/h (-%d) | dist=%.0fm | my_spd=%d km/h | my_brake=%s | closing=%s%s'):format(
                        telem.brakeCheckCount,
                        oppRecent, oppNow, oppDecel,
                        opp.dist, vd.speedKmh,
                        telem.isBraking and 'YES' or 'NO',
                        opp.dist < telem.oppPrevDist and 'YES' or 'NO',
                        repeatTag))

                    -- Check if runner was on a hill or hit a wall (not intentional brake-check)
                    local oppOnHill = false
                    if opp.vehicle ~= 0 then
                        local oppPitch = GetEntityPitch(opp.vehicle)
                        if math.abs(oppPitch) > 10 then oppOnHill = true end
                    end

                    if oppOnHill then
                        acLog('ANLZ', '  > NOTE: opponent on hill/slope — may be terrain decel, not intentional')
                    elseif opp.dist < 15 then
                        acLog('ANLZ', '  > DANGER: very close range brake-check — high collision risk')
                    end
                end
            end
        end

        -- ---- Periodic summary (every 10 s) ----
        if now - telem.lastSummaryTime >= 10000 then
            telem.lastSummaryTime = now
            local trend, _ = getSpeedTrend()

            acLog('DATA', ('--- %ss SUMMARY --- spd=%d km/h | trend=%s | opp_dist=%.0fm | opp_spd=%d km/h'):format(
                ('%.0f'):format(matchTime()), vd.speedKmh, trend, opp.dist, opp.speedKmh))
            acLog('DATA', ('  > hits: player=%d env=%d | airborne=%d | spins=%d | wall_bounce=%d | brake_checks=%d | brake=%s | steer=%.0f°'):format(
                telem.playerContacts, telem.envCollisions,
                telem.airborneCount, telem.spinOuts, telem.wallBounces,
                telem.brakeCheckCount, telem.isBraking and 'YES' or 'NO', vd.steering))
        end

        ::skip::
    end
end)

-- ========================
-- Runner crash relay (chaser receives opponent crash context)
-- ========================

RegisterNetEvent('blacklist:runnerCrashInfo')
AddEventHandler('blacklist:runnerCrashInfo', function(data)
    if myRole == 'chaser' then
        telem.lastEnvCrash = { time = GetGameTimer(), speed = data.speed or 0 }

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local mySpeed = vehicle ~= 0 and math.floor(GetEntitySpeed(vehicle) * 3.6) or 0
        local braking = IsControlPressed(0, 72) or IsDisabledControlPressed(0, 72)
        local opp     = getOpponentData()

        acLog('INFO', ('RUNNER CRASHED | runner_spd=%d km/h | my_spd=%d km/h | dist=%.0fm | closing=%s | my_brake=%s'):format(
            data.speed or 0, mySpeed, opp.dist,
            opp.dist < telem.oppPrevDist and 'YES' or 'NO',
            braking and 'YES' or 'NO'))
    end
end)

-- ========================
-- NUI setup
-- ========================

Citizen.CreateThread(function()
    SetNuiFocus(false, false)
end)

print(('[AC-LOG] %sAnti-Cheat Telemetry v%s loaded%s'):format(CLR.G, AC_VERSION, CLR.X))
