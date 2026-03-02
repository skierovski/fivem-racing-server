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

            if closestDist < 99999.0 then
                TriggerServerEvent('blacklist:reportDistance', closestDist)
            end
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
-- Traffic suppression + vehicle exit block + ghost mode reset
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
        end
    end
end)

-- ========================
-- Ghost mode reset: restore alpha + collision for all players during match
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        if isInMatch then
            local myPed = PlayerPedId()
            local myVehicle = GetVehiclePedIsIn(myPed, false)

            for _, playerId in ipairs(GetActivePlayers()) do
                if playerId ~= PlayerId() then
                    local otherPed = GetPlayerPed(playerId)
                    if otherPed ~= 0 then
                        ResetEntityAlpha(otherPed)
                        SetEntityCollision(otherPed, true, true)

                        local otherVehicle = GetVehiclePedIsIn(otherPed, false)
                        if otherVehicle ~= 0 then
                            ResetEntityAlpha(otherVehicle)
                            SetEntityCollision(otherVehicle, true, true)
                        end

                        if myVehicle ~= 0 and otherVehicle ~= 0 then
                            SetEntityNoCollisionEntity(myVehicle, otherVehicle, false)
                            -- re-enable by NOT calling the disable version
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
-- Anti-jump detection
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)

        if isInMatch then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 then
                local isAirborne = IsEntityInAir(vehicle)

                if isAirborne then
                    airborneTimer = airborneTimer + 0.1
                    if airborneTimer >= 2.0 then
                        TriggerServerEvent('blacklist:reportViolation', 'jump')
                        airborneTimer = 0.0
                    end
                else
                    airborneTimer = 0.0
                end
            end
        else
            airborneTimer = 0.0
        end
    end
end)

-- ========================
-- Anti-ram detection (for chasers only)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)

        if isInMatch and myRole == 'chaser' then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 then
                local hasCollided = HasEntityCollidedWithAnything(vehicle)

                if hasCollided then
                    local speed = GetEntitySpeed(vehicle)
                    if speed > 30.0 then
                        TriggerServerEvent('blacklist:reportViolation', 'ram')
                    end
                end
            end
        end
    end
end)

-- ========================
-- NUI setup
-- ========================

Citizen.CreateThread(function()
    SetNuiFocus(false, false)
end)

print('[Chase] ^2Client-side loaded^0')
