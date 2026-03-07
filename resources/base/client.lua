local hasSpawned = false
PlayerState = 'menu' -- 'menu', 'freeroam', 'in_match'

exports.spawnmanager:setAutoSpawn(true)
exports.spawnmanager:setAutoSpawnCallback(function()
    if hasSpawned then return end
    hasSpawned = true

    exports.spawnmanager:spawnPlayer({
        x = -75.0,
        y = -818.0,
        z = 326.0,
        heading = 0.0,
        model = 'a_m_y_hipster_01',
        skipFade = false,
    }, function()
        onSessionReady()
    end)
end)
exports.spawnmanager:forceRespawn()

function onSessionReady()
    local ped = PlayerPedId()

    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)

    DisplayHud(false)
    DisplayRadar(false)

    -- Force screen black BEFORE killing the loading screen so the world is never visible
    DoScreenFadeOut(0)
    Citizen.Wait(0)
    ShutdownLoadingScreenNui()

    Citizen.CreateThread(function()
        local timeout = GetGameTimer() + 3000
        while GetGameTimer() < timeout do
            DisableAllControlActions(0)
            Citizen.Wait(0)
        end
    end)

    TriggerServerEvent('blacklist:ensureDefaultVehicle')
    TriggerEvent('blacklist:openMenu')

    Citizen.Wait(500)
    DoScreenFadeIn(1000)
end

-- State management exports
function SetPlayerState(state)
    PlayerState = state
end
exports('SetPlayerState', SetPlayerState)
exports('GetPlayerState', function() return PlayerState end)

-- GTA pause menu is ALWAYS blocked. Our own menus replace it entirely.
local allowMapUntil = 0

function AllowGTAMap()
    allowMapUntil = GetGameTimer() + 800
    ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'), false, -1)
end
exports('AllowGTAMap', AllowGTAMap)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        HideHudComponentThisFrame(1)  -- WANTED_STARS
        HideHudComponentThisFrame(2)  -- WEAPON_ICON
        HideHudComponentThisFrame(3)  -- CASH
        HideHudComponentThisFrame(4)  -- MP_CASH
        HideHudComponentThisFrame(6)  -- VEHICLE_NAME
        HideHudComponentThisFrame(7)  -- AREA_NAME
        HideHudComponentThisFrame(9)  -- STREET_NAME
        HideHudComponentThisFrame(13) -- CASH_CHANGE
        HideHudComponentThisFrame(19) -- WEAPON_WHEEL
        HideHudComponentThisFrame(20) -- WEAPON_WHEEL_STATS
        HideHudComponentThisFrame(22) -- HUD_WEAPONS

        DisableControlAction(0, 37, true)

        DisableControlAction(0, 85, true)
        DisableControlAction(0, 81, true)
        DisableControlAction(0, 82, true)
        DisableControlAction(0, 333, true)
        DisableControlAction(0, 334, true)

        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 then
            SetVehicleRadioEnabled(veh, false)
        end

        -- Always block ESC from opening GTA pause
        DisableControlAction(0, 199, true)
        DisableControlAction(0, 200, true)

        -- Kill any GTA pause menu that sneaks through (except when map is explicitly allowed)
        if IsPauseMenuActive() and GetGameTimer() > allowMapUntil then
            SetPauseMenuActive(false)
        end

        if IsDisabledControlJustPressed(0, 200) then
            if PlayerState == 'freeroam' then
                TriggerEvent('blacklist:toggleMenu')
            elseif PlayerState == 'in_match' then
                TriggerServerEvent('blacklist:forfeitMatch')
            end
        end
    end
end)

-- /restart — full server restart (reloads handling.meta files)
RegisterCommand('restart', function()
    TriggerServerEvent('blacklist:restartServer')
end, false)

-- /refresh <resource> - restart a resource
RegisterCommand('refresh', function(source, args)
    local name = args[1]
    if not name then
        print('^3[refresh]^0 Usage: /refresh <resource_name> — then respawn your car')
        return
    end
    TriggerServerEvent('blacklist:refreshResource', name)
end, false)

RegisterNetEvent('blacklist:refreshDone')
AddEventHandler('blacklist:refreshDone', function(name)
    print('^2[refresh]^0 Refreshed ^5' .. name .. '^0')
end)

-- /coords command (always available regardless of dev resource)
RegisterCommand('coords', function()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    print(('^3[coords]^0 x=%.2f  y=%.2f  z=%.2f  heading=%.2f'):format(pos.x, pos.y, pos.z, heading))
    print(('^3[coords]^0 vector4(%.2f, %.2f, %.2f, %.2f)'):format(pos.x, pos.y, pos.z, heading))
end, false)

-- /weather and /time commands for testing
RegisterCommand('weather', function(source, args)
    local w = (args[1] or 'EXTRASUNNY'):upper()
    SetWeatherTypeNowPersist(w)
    SetWeatherTypeNow(w)
    print('^3[weather]^0 Set to ^5' .. w .. '^0')
end, false)

RegisterCommand('time', function(source, args)
    local h = tonumber(args[1]) or 12
    local m = tonumber(args[2]) or 0
    NetworkOverrideClockTime(h, m, 0)
    print('^3[time]^0 Set to ^5' .. h .. ':' .. string.format('%02d', m) .. '^0')
end, false)

Citizen.CreateThread(function()
    SetWeatherTypeNowPersist('EXTRASUNNY')
    NetworkOverrideClockTime(12, 0, 0)
end)

-- Keep weather/time locked every frame
local forcedWeather = 'EXTRASUNNY'
local forcedHour = 12
local forcedMinute = 0

RegisterCommand('setweather', function(source, args)
    forcedWeather = (args[1] or 'EXTRASUNNY'):upper()
    SetWeatherTypeNowPersist(forcedWeather)
    SetWeatherTypeNow(forcedWeather)
    print('^3[weather]^0 Locked to ^5' .. forcedWeather .. '^0')
end, false)

RegisterCommand('settime', function(source, args)
    forcedHour = tonumber(args[1]) or 12
    forcedMinute = tonumber(args[2]) or 0
    NetworkOverrideClockTime(forcedHour, forcedMinute, 0)
    print('^3[time]^0 Locked to ^5' .. forcedHour .. ':' .. string.format('%02d', forcedMinute) .. '^0')
end, false)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        SetWeatherTypeNowPersist(forcedWeather)
        NetworkOverrideClockTime(forcedHour, forcedMinute, 0)
    end
end)

-- Disable wanted level + keep health/armor bars hidden
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        ClearPlayerWantedLevel(PlayerId())
        SetMaxWantedLevel(0)

        local ped = PlayerPedId()
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        SetPedArmour(ped, 0)
        RemoveAllPedWeapons(ped, true)
    end
end)

-- ========================
-- Proximity voice chat with distance-based fade
-- ========================

local VOICE_MAX_RANGE = 25.0
local VOICE_FULL_RANGE = 10.0

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)

        NetworkSetTalkerProximity(VOICE_MAX_RANGE)

        local myCoords = GetEntityCoords(PlayerPedId())
        for _, playerId in ipairs(GetActivePlayers()) do
            if playerId ~= PlayerId() then
                local otherPed = GetPlayerPed(playerId)
                if otherPed ~= 0 then
                    local dist = #(myCoords - GetEntityCoords(otherPed))
                    local vol = 0.0
                    if dist <= VOICE_FULL_RANGE then
                        vol = 1.0
                    elseif dist < VOICE_MAX_RANGE then
                        vol = 1.0 - ((dist - VOICE_FULL_RANGE) / (VOICE_MAX_RANGE - VOICE_FULL_RANGE))
                    end
                    MumbleSetVolumeOverrideByServerId(GetPlayerServerId(playerId), vol)
                end
            end
        end
    end
end)

-- Disable radio globally on resource start and for any new vehicle
Citizen.CreateThread(function()
    SetRadioToStationName('OFF')
    SetAudioFlag('IsDirectorModeActive', true)
    SetAudioFlag('PoliceScannerDisabled', true)

    while true do
        Citizen.Wait(1000)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 then
            SetVehicleRadioEnabled(veh, false)
            SetVehRadioStation(veh, 'OFF')
        end
    end
end)

-- Disable ambient/random NPCs in certain modes (configured by other resources)
RegisterNetEvent('blacklist:setPlayerVisible')
AddEventHandler('blacklist:setPlayerVisible', function(visible)
    local ped = PlayerPedId()
    SetEntityVisible(ped, visible, false)
    FreezeEntityPosition(ped, not visible)
    SetEntityInvincible(ped, not visible)
    if visible then
        DisplayHud(true)
        DisplayRadar(true)
    end
end)

-- Safe teleport with collision loading
RegisterNetEvent('blacklist:teleport')
AddEventHandler('blacklist:teleport', function(x, y, z, heading)
    local ped = PlayerPedId()

    DoScreenFadeOut(300)
    Citizen.Wait(400)

    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, x, y, z, false, false, false, true)
    if heading then
        SetEntityHeading(ped, heading)
    end

    -- Request collision and wait for it to load
    RequestCollisionAtCoord(x, y, z)

    local timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(ped) do
        Citizen.Wait(100)
        RequestCollisionAtCoord(x, y, z)
        if GetGameTimer() > timeout then break end
    end

    -- Double-check with ground Z probe
    local found, groundZ = false, z
    for attempt = 1, 20 do
        found, groundZ = GetGroundZFor_3dCoord(x, y, z + 100.0, false)
        if found then break end
        Citizen.Wait(100)
    end

    if found then
        SetEntityCoords(ped, x, y, groundZ + 1.0, false, false, false, true)
    end

    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(500)
end)

RegisterNetEvent('blacklist:returnToMenu')
AddEventHandler('blacklist:returnToMenu', function()
    DoScreenFadeOut(0)

    local ped = PlayerPedId()

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        DeleteEntity(vehicle)
    end

    SetEntityCoords(ped, -75.0, -818.0, 326.0, false, false, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    DisplayHud(false)
    DisplayRadar(false)

    PlayerState = 'menu'
    TriggerServerEvent('blacklist:resetBucket')
    TriggerEvent('blacklist:openMenu')

    Citizen.Wait(300)
    DoScreenFadeIn(500)
end)
