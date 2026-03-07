-- ============================================================
-- Vehicle spawning and tuning on client side
-- ============================================================

local currentVehicle = nil

RegisterNetEvent('blacklist:doSpawnVehicle')
AddEventHandler('blacklist:doSpawnVehicle', function(vehicleData, x, y, z, heading)
    local model = vehicleData.model
    local tuning = vehicleData.tuning or {}

    if currentVehicle and DoesEntityExist(currentVehicle) then
        DeleteEntity(currentVehicle)
        currentVehicle = nil
    end

    local hash = GetHashKey(model)
    RequestModel(hash)

    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        Citizen.Wait(100)
        if GetGameTimer() > timeout then
            print('[Vehicles] ^1Failed to load model: ' .. model .. ', falling back to sultan^0')
            hash = GetHashKey('sultan')
            RequestModel(hash)
            while not HasModelLoaded(hash) do
                Citizen.Wait(100)
            end
            break
        end
    end

    local ped = PlayerPedId()
    local spawnZ = z + 15.0

    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)

    -- Spawn vehicle above target, retry up to 3 times if creation fails
    local vehicle = 0
    for attempt = 1, 3 do
        vehicle = CreateVehicle(hash, x, y, spawnZ, heading or 0.0, true, false)
        if vehicle ~= 0 then break end
        print(('[Vehicles] ^3CreateVehicle failed (attempt %d/3), retrying...^0'):format(attempt))
        Citizen.Wait(500)
    end

    if vehicle == 0 then
        print('[Vehicles] ^1CRITICAL: Vehicle creation failed after 3 attempts^0')
        TriggerServerEvent('blacklist:spawnReady')
        return
    end

    SetVehicleDirtLevel(vehicle, 0.0)

    SetModelAsNoLongerNeeded(hash)
    FreezeEntityPosition(vehicle, true)

    -- Warp ped into vehicle using immediate native, then verify
    SetPedIntoVehicle(ped, vehicle, -1)
    Citizen.Wait(50)

    if GetVehiclePedIsIn(ped, false) ~= vehicle then
        TaskWarpPedIntoVehicle(ped, vehicle, -1)
        Citizen.Wait(200)
    end

    if GetVehiclePedIsIn(ped, false) ~= vehicle then
        SetPedIntoVehicle(ped, vehicle, -1)
        Citizen.Wait(100)
        print('[Vehicles] ^3Ped warp required multiple attempts^0')
    end

    -- Stream the area and load collision
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(x, y, z)

    timeout = GetGameTimer() + 8000
    while not HasCollisionLoadedAroundEntity(vehicle) do
        Citizen.Wait(50)
        RequestCollisionAtCoord(x, y, z)
        if GetGameTimer() > timeout then break end
    end

    -- Find solid ground: tight probe first, wider fallback second
    local found, groundZ = false, z
    for attempt = 1, 30 do
        found, groundZ = GetGroundZFor_3dCoord(x, y, z + 5.0, false)
        if found and math.abs(groundZ - z) < 10.0 then break end
        found = false
        Citizen.Wait(100)
    end

    if not found then
        for attempt = 1, 15 do
            found, groundZ = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
            if found then break end
            Citizen.Wait(100)
        end
    end

    local finalZ = found and (groundZ + 0.3) or z
    SetEntityCoords(vehicle, x, y, finalZ, false, false, false, true)
    SetEntityHeading(vehicle, heading or 0.0)
    ClearFocus()

    applyTuning(vehicle, tuning)
    SetVehicleCanBeVisiblyDamaged(vehicle, false)
    SetVehicleRadioEnabled(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')

    -- Ensure full visibility and collision (clean slate after freeroam ghost)
    ResetEntityAlpha(vehicle)
    ResetEntityAlpha(ped)
    SetEntityAlpha(vehicle, 255, false)
    SetEntityAlpha(ped, 255, false)
    SetEntityCollision(vehicle, true, true)
    SetEntityCollision(ped, true, true)

    -- Keep frozen -- chase countdown will unfreeze
    FreezeEntityPosition(vehicle, true)
    FreezeEntityPosition(ped, true)

    -- Final safety: guarantee ped is in the vehicle
    if GetVehiclePedIsIn(ped, false) ~= vehicle then
        SetPedIntoVehicle(ped, vehicle, -1)
        print('[Vehicles] ^3Final ped-in-vehicle safety check triggered^0')
    end

    currentVehicle = vehicle

    DisplayHud(true)
    DisplayRadar(true)

    TriggerServerEvent('blacklist:spawnReady')
end)

function applyTuning(vehicle, tuning)
    if not tuning then tuning = {} end

    SetVehicleModKit(vehicle, 0)

    -- Paint finish (must be set before custom colors)
    if tuning.paintType1 then
        SetVehicleModColor_1(vehicle, tuning.paintType1, 0, 0)
    end
    if tuning.paintType2 then
        SetVehicleModColor_2(vehicle, tuning.paintType2, 0)
    end

    -- Primary color
    if tuning.color1 then
        SetVehicleCustomPrimaryColour(vehicle, tuning.color1.r or 0, tuning.color1.g or 0, tuning.color1.b or 0)
    end

    -- Secondary color
    if tuning.color2 then
        SetVehicleCustomSecondaryColour(vehicle, tuning.color2.r or 0, tuning.color2.g or 0, tuning.color2.b or 0)
    end

    -- Wheels
    if tuning.wheelType then
        SetVehicleWheelType(vehicle, tuning.wheelType)
    end
    if tuning.wheelIndex and tuning.wheelIndex >= 0 then
        SetVehicleMod(vehicle, 23, tuning.wheelIndex, false)
    end
    if tuning.wheelColor then
        local pearl, _ = GetVehicleExtraColours(vehicle)
        SetVehicleExtraColours(vehicle, pearl, tuning.wheelColor)
    end

    -- Visual mod slots
    local visualSlots = { spoiler = 0, frontBumper = 1, rearBumper = 2, sideSkirts = 3, hood = 7 }
    for key, slot in pairs(visualSlots) do
        if tuning[key] and tuning[key] >= 0 then
            SetVehicleMod(vehicle, slot, tuning[key], false)
        end
    end

    -- Livery
    if tuning.livery and tuning.livery >= 0 then
        SetVehicleLivery(vehicle, tuning.livery)
        SetVehicleMod(vehicle, 48, tuning.livery, false)
    end

    -- Window tint
    if tuning.windowTint then
        SetVehicleWindowTint(vehicle, tuning.windowTint)
    end

    -- Neon (underglow)
    if tuning.neon then
        for i = 0, 3 do SetVehicleNeonLightEnabled(vehicle, i, true) end
        if tuning.neonColor then
            SetVehicleNeonLightsColour(vehicle, tuning.neonColor.r or 0, tuning.neonColor.g or 150, tuning.neonColor.b or 255)
        end
    end

    -- Performance: use saved levels if present, otherwise max out
    local perfSlots = { engine = 11, brakes = 12, transmission = 13, suspension = 15 }
    for key, slot in pairs(perfSlots) do
        if tuning[key] ~= nil then
            if tuning[key] >= 0 then
                SetVehicleMod(vehicle, slot, tuning[key], false)
            end
        else
            SetVehicleMod(vehicle, slot, GetNumVehicleMods(vehicle, slot) - 1, false)
        end
    end

    -- Turbo: use saved value if present, otherwise enable
    if tuning.turbo ~= nil then
        ToggleVehicleMod(vehicle, 18, tuning.turbo == true)
    else
        ToggleVehicleMod(vehicle, 18, true)
    end

    -- Extras
    if tuning.extras then
        for idStr, enabled in pairs(tuning.extras) do
            local id = tonumber(idStr)
            if id and DoesExtraExist(vehicle, id) then
                SetVehicleExtra(vehicle, id, not enabled)
            end
        end
    end
end

--- Delete current vehicle (called when returning to menu)
RegisterNetEvent('blacklist:deleteVehicle')
AddEventHandler('blacklist:deleteVehicle', function()
    if currentVehicle and DoesEntityExist(currentVehicle) then
        DeleteEntity(currentVehicle)
        currentVehicle = nil
    end
end)

--- Get current vehicle entity
function GetCurrentVehicle()
    return currentVehicle
end

exports('GetCurrentVehicle', GetCurrentVehicle)
exports('ApplyTuning', applyTuning)

print('[Vehicles] ^2Client-side loaded^0')
