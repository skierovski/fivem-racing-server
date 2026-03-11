RegisterNetEvent('enginesounds:apply')
AddEventHandler('enginesounds:apply', function(netId, sound)
    local src = source
    local ped = GetPlayerPed(src)
    if ped == 0 then return end

    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return end

    if NetworkGetEntityFromNetworkId(netId) ~= veh then return end

    Entity(veh).state:set('engineSound', sound or '', true)
end)
