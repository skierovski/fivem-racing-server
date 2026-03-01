local isInFreeRoam = false
local isFreeroamMenuOpen = false

-- ========================
-- Full client-side freeroam entry
-- ========================

RegisterNetEvent('blacklist:enterFreeRoamClient')
AddEventHandler('blacklist:enterFreeRoamClient', function(spawn)
    local ped = PlayerPedId()
    local x, y, z, heading = spawn.x, spawn.y, spawn.z, spawn.heading

    -- 1. Fade out
    DoScreenFadeOut(300)
    Citizen.Wait(400)

    -- 2. Freeze + place player HIGH above spawn so collision can load
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, x, y, z + 50.0, false, false, false, true)
    SetEntityHeading(ped, heading)

    -- 3. Stream the area and load collision
    SetFocusPosAndVel(x, y, z + 50.0, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(x, y, z)

    local timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(ped) do
        Citizen.Wait(50)
        RequestCollisionAtCoord(x, y, z)
        if GetGameTimer() > timeout then break end
    end

    -- 4. Find solid ground
    local found, groundZ = false, z
    for attempt = 1, 50 do
        found, groundZ = GetGroundZFor_3dCoord(x, y, z + 200.0, false)
        if found then break end
        Citizen.Wait(100)
    end

    local finalZ = found and (groundZ + 1.0) or z
    SetEntityCoords(ped, x, y, finalZ, false, false, false, true)
    ClearFocus()

    -- 5. Make visible, show HUD
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    DisplayHud(true)
    DisplayRadar(true)

    -- 6. Fade in (player spawns on foot, uses F1 to pick a car)
    DoScreenFadeIn(500)

    -- 8. Enable ghost mode
    isInFreeRoam = true

    -- 9. Show hint after a moment
    Citizen.Wait(2000)
    SendNUIMessage({ action = 'showHint', show = true })
    Citizen.SetTimeout(5000, function()
        SendNUIMessage({ action = 'showHint', show = false })
    end)
end)

RegisterNetEvent('blacklist:enableGhostMode')
AddEventHandler('blacklist:enableGhostMode', function(enable)
    isInFreeRoam = enable
end)

-- ========================
-- Remove peds, traffic, props every frame
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if isInFreeRoam then
            -- Kill all ped spawning
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)

            -- Kill all vehicle traffic
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)

            -- Disable garbage trucks, ambulances, etc.
            SetGarbageTrucks(false)
            SetRandomBoats(false)
            SetRandomTrains(false)

            -- Disable dispatch services (cops, fire, ambulance)
            for i = 1, 15 do
                EnableDispatchService(i, false)
            end
        end
    end
end)

-- Clean up existing peds and vehicles periodically
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(2000)

        if isInFreeRoam then
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
-- Ghost mode (no collisions with other players)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)

        if isInFreeRoam then
            local myPed = PlayerPedId()
            local myVehicle = GetVehiclePedIsIn(myPed, false)

            for _, playerId in ipairs(GetActivePlayers()) do
                if playerId ~= PlayerId() then
                    local otherPed = GetPlayerPed(playerId)
                    if otherPed ~= 0 then
                        SetEntityNoCollisionEntity(myPed, otherPed, false)

                        local otherVehicle = GetVehiclePedIsIn(otherPed, false)
                        if myVehicle ~= 0 and otherVehicle ~= 0 then
                            SetEntityNoCollisionEntity(myVehicle, otherVehicle, false)
                        end

                        SetEntityAlpha(otherPed, 100, false)
                        if otherVehicle ~= 0 then
                            SetEntityAlpha(otherVehicle, 100, false)
                        end
                    end
                end
            end
        end
    end
end)

-- ========================
-- Disable wanted level + death handling
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if isInFreeRoam then
            ClearPlayerWantedLevel(PlayerId())
            SetMaxWantedLevel(0)

            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                DoScreenFadeOut(300)
                Citizen.Wait(500)

                NetworkResurrectLocalPlayer(152.47, 1033.83, 29.34, 333.42, true, false)

                local newPed = PlayerPedId()
                ClearPedBloodDamage(newPed)
                SetEntityHealth(newPed, GetEntityMaxHealth(newPed))
                SetEntityInvincible(newPed, false)

                Citizen.Wait(300)
                DoScreenFadeIn(500)
            end
        end
    end
end)

-- ========================
-- Freeroam mini-menu (F1 key)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if isInFreeRoam and not isFreeroamMenuOpen then
            if IsControlJustPressed(0, 288) then -- F1
                openFreeroamMenu()
            end
        end
    end
end)

function openFreeroamMenu()
    isFreeroamMenuOpen = true
    SetNuiFocus(true, true)

    -- Send vehicle catalog to NUI
    TriggerServerEvent('blacklist:requestVehiclesForFreeroam')

    SendNUIMessage({ action = 'openFreeroamMenu' })
end

function closeFreeroamMenu()
    isFreeroamMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeFreeroamMenu' })
end

-- Receive vehicle list for freeroam menu
RegisterNetEvent('blacklist:receiveFreeroamVehicles')
AddEventHandler('blacklist:receiveFreeroamVehicles', function(catalog)
    SendNUIMessage({
        action = 'vehicleList',
        vehicles = catalog,
    })
end)

-- ========================
-- NUI Callbacks
-- ========================

RegisterNUICallback('closeFreeroamMenu', function(data, cb)
    closeFreeroamMenu()
    cb({})
end)

RegisterNUICallback('selectFreeroamCar', function(data, cb)
    closeFreeroamMenu()

    local model = data.model
    if not model then cb({}) return end

    -- Ask server for saved tuning, then spawn with it
    freeroamPendingModel = model
    TriggerServerEvent('blacklist:requestFreeroamTuning', model)
    cb({})
end)

RegisterNetEvent('blacklist:receiveFreeroamTuning')
AddEventHandler('blacklist:receiveFreeroamTuning', function(model, tuning)
    if not isInFreeRoam then return end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)

    local currentVeh = GetVehiclePedIsIn(ped, false)
    if currentVeh ~= 0 then
        DeleteEntity(currentVeh)
    end

    local hash = GetHashKey(model)
    RequestModel(hash)

    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        Citizen.Wait(100)
        if GetGameTimer() > timeout then
            hash = GetHashKey('sultan')
            RequestModel(hash)
            while not HasModelLoaded(hash) do Citizen.Wait(100) end
            break
        end
    end

    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
    SetModelAsNoLongerNeeded(hash)
    TaskWarpPedIntoVehicle(ped, vehicle, -1)

    SetVehicleModKit(vehicle, 0)
    if tuning then
        exports.vehicles:ApplyTuning(vehicle, tuning)
    else
        SetVehicleMod(vehicle, 11, GetNumVehicleMods(vehicle, 11) - 1, false)
        SetVehicleMod(vehicle, 12, GetNumVehicleMods(vehicle, 12) - 1, false)
        SetVehicleMod(vehicle, 13, GetNumVehicleMods(vehicle, 13) - 1, false)
        SetVehicleMod(vehicle, 15, GetNumVehicleMods(vehicle, 15) - 1, false)
        ToggleVehicleMod(vehicle, 18, true)
    end

    SetVehicleRadioEnabled(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')
end)

RegisterNUICallback('teleportToWaypoint', function(data, cb)
    closeFreeroamMenu()

    local waypointBlip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(waypointBlip) then
        cb({ success = false })
        return
    end

    local coords = GetBlipInfoIdCoord(waypointBlip)
    local x, y = coords.x, coords.y

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = vehicle ~= 0 and vehicle or ped

    DoScreenFadeOut(300)
    Citizen.Wait(400)

    FreezeEntityPosition(entity, true)
    SetEntityCoordsNoOffset(entity, x, y, 300.0, false, false, false)

    -- Load collision at destination
    RequestCollisionAtCoord(x, y, 300.0)
    local timeout = GetGameTimer() + 10000
    while not HasCollisionLoadedAroundEntity(entity) do
        Citizen.Wait(50)
        RequestCollisionAtCoord(x, y, 300.0)
        if GetGameTimer() > timeout then break end
    end

    -- Find solid ground
    local found, groundZ = false, 300.0
    for attempt = 1, 40 do
        found, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, false)
        if found then break end
        Citizen.Wait(100)
    end

    local finalZ = found and (groundZ + 1.0) or 300.0
    SetEntityCoordsNoOffset(entity, x, y, finalZ, false, false, false)

    FreezeEntityPosition(entity, false)
    Citizen.Wait(300)
    DoScreenFadeIn(500)

    cb({ success = true })
end)

RegisterNUICallback('openMap', function(data, cb)
    closeFreeroamMenu()
    exports.base:AllowGTAMap()
    cb({})
end)

RegisterNUICallback('backToMainMenu', function(data, cb)
    closeFreeroamMenu()
    isInFreeRoam = false
    TriggerServerEvent('blacklist:leaveFreeRoam')
    TriggerEvent('blacklist:returnToMenu')
    cb({})
end)

print('[FreeRoam] ^2Client-side loaded^0')
