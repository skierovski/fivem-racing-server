local HandlingOverrides = {}

-- vecCentreOfMassOffset & vecInertiaMultiplier do NOT work via SetVehicleHandlingVector
-- at runtime (known FiveM engine bug). They only apply through .meta files loaded at
-- server start. All other float/int fields work if we call ModifyVehicleTopSpeed afterwards.
local BROKEN_VECTORS = {
    vecCentreOfMassOffset = true,
    vecInertiaMultiplier  = true,
}

local function applyToCurrentVehicle(filterKey)
    local ped = PlayerPedId()
    if not ped or not IsPedInAnyVehicle(ped, false) then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then return end
    local model = GetDisplayNameFromVehicleModel(GetEntityModel(veh)):lower()
    if filterKey and model ~= filterKey then return end
    ApplyHandlingOverrides(veh, model)
end

-- Full bulk update (resource start / reconnect)
RegisterNetEvent('handling:receiveOverrides')
AddEventHandler('handling:receiveOverrides', function(overrides)
    HandlingOverrides = overrides or {}
    local count = 0
    for _ in pairs(HandlingOverrides) do count = count + 1 end
    print(('[handling] ^2Received %d handling overrides^0'):format(count))
    Citizen.CreateThread(function()
        Citizen.Wait(100)
        applyToCurrentVehicle()
    end)
end)

-- Single car update (from /rh command)
RegisterNetEvent('handling:receiveSingleOverride')
AddEventHandler('handling:receiveSingleOverride', function(carKey, data)
    HandlingOverrides[carKey] = data
    print(('[handling] ^2Updated override for %s^0'):format(carKey))
    Citizen.CreateThread(function()
        Citizen.Wait(0)
        applyToCurrentVehicle(carKey)
    end)
end)

RegisterNetEvent('handling:refreshResult')
AddEventHandler('handling:refreshResult', function(ok, info)
    if ok then
        print(('[handling] ^2Refreshed: %s^0'):format(info))
    else
        print(('[handling] ^1Error: %s^0'):format(info))
    end
end)

TriggerServerEvent('handling:requestOverrides')

-- /rh futo   — refresh single car handling from disk
-- /rh all    — reload all tier cars
RegisterCommand('rh', function(_, args)
    local name = args[1]
    if not name then
        print('^3[handling]^0 Usage: /rh <carname>  |  /rh all')
        return
    end
    if name == 'all' then
        TriggerServerEvent('dev:refreshResource', 'handling')
    else
        TriggerServerEvent('handling:refreshCar', name)
    end
end, false)

function ApplyHandlingOverrides(vehicle, modelName)
    if not vehicle or not DoesEntityExist(vehicle) then return end
    if not modelName then return end

    local key = modelName:lower()
    local data = HandlingOverrides[key]
    if not data then return end

    for field, value in pairs(data.floats) do
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', field, value + 0.0)
    end

    for field, value in pairs(data.ints) do
        SetVehicleHandlingInt(vehicle, 'CHandlingData', field, value)
    end

    for field, vec in pairs(data.vectors) do
        if not BROKEN_VECTORS[field] then
            SetVehicleHandlingVector(vehicle, 'CHandlingData', field, vector3(vec.x, vec.y, vec.z))
        end
    end

    for field, value in pairs(data.subFloats) do
        SetVehicleHandlingFloat(vehicle, 'CCarHandlingData', field, value + 0.0)
    end

    -- Force the engine to recalculate physics with the new handling values.
    -- Without this call, SetVehicleHandlingFloat updates internal data but
    -- actual vehicle behavior stays unchanged (known FiveM quirk).
    ModifyVehicleTopSpeed(vehicle, 1.0)
end

exports('ApplyHandlingOverrides', ApplyHandlingOverrides)

print('[handling] ^2/rh command ready — usage: /rh futo | /rh all^0')
