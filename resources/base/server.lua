-- Disable default auto-spawn
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        print('[Base] ^2Spawn control loaded^0')
    end
end)

-- Override default spawn behavior
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source
    print(('[Base] Player connecting: %s (id: %d)'):format(name, source))
end)

-- Player fully loaded
RegisterNetEvent('blacklist:playerLoaded')
AddEventHandler('blacklist:playerLoaded', function()
    local source = source
    print(('[Base] Player loaded: %s (id: %d)'):format(GetPlayerName(source), source))
    TriggerClientEvent('blacklist:setPlayerVisible', source, false)
end)

AddEventHandler('playerDropped', function(reason)
    local source = source
    print(('[Base] Player dropped: %s (reason: %s)'):format(GetPlayerName(source), reason))
end)
