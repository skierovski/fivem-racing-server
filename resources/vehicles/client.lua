-- ============================================================
-- Vehicle spawning and tuning on client side
-- ============================================================

local currentVehicle = nil

RegisterNetEvent('blacklist:doSpawnVehicle')
AddEventHandler('blacklist:doSpawnVehicle', function(vehicleData, x, y, z, heading)
    local model = vehicleData.model
    local tuning = vehicleData.tuning or {}

    -- Delete previous vehicle if exists
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
            print('[Vehicles] ^1Failed to load model: ' .. model .. '^0')
            -- Fall back to sultan
            hash = GetHashKey('sultan')
            RequestModel(hash)
            while not HasModelLoaded(hash) do
                Citizen.Wait(100)
            end
            break
        end
    end

    local ped = PlayerPedId()

    -- Make player visible
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)

    -- Spawn vehicle
    local vehicle = CreateVehicle(hash, x, y, z, heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)

    -- Place player in driver seat
    TaskWarpPedIntoVehicle(ped, vehicle, -1)

    -- Apply tuning
    applyTuning(vehicle, tuning)

    SetVehicleCanBeVisiblyDamaged(vehicle, false)

    -- Kill radio immediately on spawn
    SetVehicleRadioEnabled(vehicle, false)
    SetVehRadioStation(vehicle, 'OFF')

    currentVehicle = vehicle

    DisplayHud(true)
    DisplayRadar(true)
end)

function applyTuning(vehicle, tuning)
    if not tuning then tuning = {} end

    SetVehicleModKit(vehicle, 0)

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
