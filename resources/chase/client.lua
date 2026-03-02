-- ============================================================
-- Chase/Run game mode: client-side HUD, distance tracking, anti-cheat
-- ============================================================

local isInMatch = false
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
        })

    elseif data.action == 'warning' then
        SendNUIMessage({
            action = 'warning',
            message = data.message,
        })

    elseif data.action == 'end' then
        isInMatch = false
        myRole = nil
        SendNUIMessage({
            action = 'matchEnd',
            won = data.won,
            winnerRole = data.winnerRole,
            reason = data.reason,
            duration = data.duration,
        })
    end
end)

-- ========================
-- Chase HUD cleanup on return to menu
-- ========================

RegisterNetEvent('blacklist:returnToMenu')
AddEventHandler('blacklist:returnToMenu', function()
    isInMatch = false
    myRole = nil
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

            TriggerServerEvent('blacklist:reportDistance', closestDist, math.min(closestDist, 400.0))
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
-- Runs every frame during match
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if isInMatch then
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
-- Periodic NPC cleanup during match
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(3000)

        if isInMatch then
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

-- ========================
-- Tester diagnostic logging: airborne + collision detection
-- ========================

local wasAirborne = false
local airborneStartTime = 0
local airborneStartSpeed = 0
local lastEnvCrash = nil -- { time = ms, speed = km/h }
local lastCollisionTime = 0

local function logChase(msg)
    local prefix = ('[CHASE LOG] role=%s | %s'):format(myRole or 'unknown', msg)
    print(prefix)
    TriggerServerEvent('blacklist:chaseLog', { message = msg })
end

local function getClosestPlayerInfo()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local closestDist = 99999.0
    local closestSpeed = 0.0
    local closestPed = 0

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local otherPed = GetPlayerPed(playerId)
            if otherPed ~= 0 then
                local dist = #(myCoords - GetEntityCoords(otherPed))
                if dist < closestDist then
                    closestDist = dist
                    closestPed = otherPed
                    local otherVeh = GetVehiclePedIsIn(otherPed, false)
                    closestSpeed = otherVeh ~= 0 and math.floor(GetEntitySpeed(otherVeh) * 3.6) or 0
                end
            end
        end
    end

    return closestDist, closestSpeed
end

-- Airborne tracking
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)

        if isInMatch then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 then
                local isAir = IsEntityInAir(vehicle)
                local speed = math.floor(GetEntitySpeed(vehicle) * 3.6)
                local height = GetEntityHeightAboveGround(vehicle)

                if isAir and not wasAirborne then
                    wasAirborne = true
                    airborneStartTime = GetGameTimer()
                    airborneStartSpeed = speed
                    logChase(('AIRBORNE START | speed=%d km/h | height=%.1fm'):format(speed, height))
                elseif not isAir and wasAirborne then
                    local duration = (GetGameTimer() - airborneStartTime) / 1000.0
                    wasAirborne = false
                    logChase(('AIRBORNE END | duration=%.1fs | launch_speed=%d km/h | landing_speed=%d km/h'):format(
                        duration, airborneStartSpeed, speed))

                    if duration >= 2.0 then
                        TriggerServerEvent('blacklist:reportViolation', 'jump')
                    end
                    airborneTimer = 0.0
                end
            else
                wasAirborne = false
            end
        else
            wasAirborne = false
            airborneTimer = 0.0
        end
    end
end)

-- Collision tracking (both runner and chaser)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)

        if isInMatch then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and HasEntityCollidedWithAnything(vehicle) then
                local now = GetGameTimer()
                if now - lastCollisionTime < 2000 then goto skipCollision end
                lastCollisionTime = now

                local speed = math.floor(GetEntitySpeed(vehicle) * 3.6)
                local oppDist, oppSpeed = getClosestPlayerInfo()

                local isPlayerContact = oppDist < 8.0
                local contactType = isPlayerContact and 'PLAYER_CONTACT' or 'ENVIRONMENT'

                if isPlayerContact then
                    local subType = 'INTENTIONAL'
                    local extraInfo = ''

                    if lastEnvCrash and (now - lastEnvCrash.time) < 2000 and myRole == 'chaser' then
                        subType = 'FOLLOW_UP'
                        local gap = now - lastEnvCrash.time
                        extraInfo = (' | sub=FOLLOW_UP | gap=%dms | runner_crashed_at=%d km/h'):format(gap, lastEnvCrash.speed)
                    else
                        extraInfo = ' | sub=INTENTIONAL'
                    end

                    logChase(('COLLISION | type=%s%s | my_speed=%d km/h | opponent_speed=%d km/h | dist=%.1fm'):format(
                        contactType, extraInfo, speed, oppSpeed, oppDist))

                    if myRole == 'chaser' and speed > 30.0 then
                        TriggerServerEvent('blacklist:reportViolation', 'ram')
                    end
                else
                    logChase(('COLLISION | type=ENVIRONMENT | my_speed=%d km/h | opponent_dist=%.1fm'):format(speed, oppDist))

                    -- Track environment crash for follow-up detection
                    if myRole == 'runner' then
                        lastEnvCrash = { time = now, speed = speed }
                        TriggerServerEvent('blacklist:chaseLog', {
                            message = ('RUNNER_ENV_CRASH | speed=%d km/h'):format(speed),
                        })
                    end
                end
            end

            ::skipCollision::
        end
    end
end)

-- Broadcast runner's env crash time to chasers for follow-up detection
RegisterNetEvent('blacklist:runnerCrashInfo')
AddEventHandler('blacklist:runnerCrashInfo', function(data)
    if myRole == 'chaser' then
        lastEnvCrash = { time = GetGameTimer(), speed = data.speed or 0 }
    end
end)

-- ========================
-- NUI setup
-- ========================

Citizen.CreateThread(function()
    SetNuiFocus(false, false)
end)

print('[Chase] ^2Client-side loaded^0')
