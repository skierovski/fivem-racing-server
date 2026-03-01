RegisterCommand('refresh', function(source, args)
    local name = args[1]
    if not name then
        print('^3[dev]^0 Usage: /refresh <resource>  |  /refresh all')
        return
    end
    TriggerServerEvent('dev:refreshResource', name)
end, false)

RegisterNetEvent('dev:refreshDone')
AddEventHandler('dev:refreshDone', function(name)
    print('^2[dev]^0 Refreshed ^5' .. name .. '^0')
end)

RegisterCommand('coords', function()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    print(('^3[coords]^0 x=%.2f  y=%.2f  z=%.2f  heading=%.2f'):format(pos.x, pos.y, pos.z, heading))
    print(('^3[coords]^0 vector4(%.2f, %.2f, %.2f, %.2f)'):format(pos.x, pos.y, pos.z, heading))
end, false)

print('[dev] ^2/refresh and /coords commands ready (F8)^0')
