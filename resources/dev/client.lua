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

print('[dev] ^2/refresh command ready (F8)^0')
