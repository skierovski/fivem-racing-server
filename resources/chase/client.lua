-- ============================================================
-- Chase/Run game mode: client-side HUD, distance tracking, anti-cheat
-- ============================================================

local isInMatch = false
local myRole = nil -- 'chaser' or 'runner'
local matchTimer = 0
local matchStartTime = 0
local isFrozen = false
local runnerBlip = nil
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
        cleanupBlips()
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
-- Distance tracking + blip (chaser only)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)

        if isInMatch and myRole == 'chaser' then
            -- Find the runner (closest player that isn't us)
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)

            local closestDist = 99999.0
            local runnerPed = nil

            for _, playerId in ipairs(GetActivePlayers()) do
                if playerId ~= PlayerId() then
                    local otherPed = GetPlayerPed(playerId)
                    if otherPed ~= 0 then
                        local otherCoords = GetEntityCoords(otherPed)
                        local dist = #(myCoords - otherCoords)
                        if dist < closestDist then
                            closestDist = dist
                            runnerPed = otherPed
                        end
                    end
                end
            end

            if runnerPed then
                TriggerServerEvent('blacklist:reportDistance', closestDist)

                -- Update blip
                updateRunnerBlip(runnerPed)
            end
        end
    end
end)

function updateRunnerBlip(ped)
    if runnerBlip then
        RemoveBlip(runnerBlip)
    end
    runnerBlip = AddBlipForEntity(ped)
    SetBlipSprite(runnerBlip, 1)
    SetBlipColour(runnerBlip, 1) -- red
    SetBlipScale(runnerBlip, 1.0)
    SetBlipAsShortRange(runnerBlip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('RUNNER')
    EndTextCommandSetBlipName(runnerBlip)
end

function cleanupBlips()
    if runnerBlip then
        RemoveBlip(runnerBlip)
        runnerBlip = nil
    end
end

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
                        airborneTimer = 0.0 -- reset after report
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
                    local speed = GetEntitySpeed(vehicle) -- m/s
                    if speed > 30.0 then
                        -- High-speed collision detected
                        -- Check if it was with another vehicle (potential ram)
                        -- Simple heuristic: if speed > threshold during collision, it's a ram
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
    -- NUI is always available but hidden
    SetNuiFocus(false, false)
end)

print('[Chase] ^2Client-side loaded^0')
