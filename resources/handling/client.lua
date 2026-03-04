local HandlingOverrides = {}

RegisterNetEvent('handling:receiveOverrides')
AddEventHandler('handling:receiveOverrides', function(overrides)
    HandlingOverrides = overrides or {}
    local count = 0
    for _ in pairs(HandlingOverrides) do count = count + 1 end
    print(('[handling] ^2Received %d handling overrides^0'):format(count))
end)

-- Request overrides from server on script (re)start
TriggerServerEvent('handling:requestOverrides')

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
        SetVehicleHandlingVector(vehicle, 'CHandlingData', field, vector3(vec.x, vec.y, vec.z))
    end

    for field, value in pairs(data.subFloats) do
        SetVehicleHandlingFloat(vehicle, 'CCarHandlingData', field, value + 0.0)
    end
end

exports('ApplyHandlingOverrides', ApplyHandlingOverrides)

print('[handling] ^2Client-side handling override system loaded^0')
