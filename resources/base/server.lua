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
    SetPlayerRoutingBucket(source, 0)
    print(('[Base] Player dropped: %s (reason: %s)'):format(GetPlayerName(source), reason))
end)

-- Safety: ensure player is in bucket 0 when returning to menu
RegisterNetEvent('blacklist:resetBucket')
AddEventHandler('blacklist:resetBucket', function()
    local source = source
    SetPlayerRoutingBucket(source, 0)
end)

-- /refresh command: restart resources from F8 console
local REFRESH_IGNORE = { base = true, oxmysql = true, hardcap = true, sessionmanager = true, spawnmanager = true }

RegisterNetEvent('blacklist:refreshResource')
AddEventHandler('blacklist:refreshResource', function(name)
    local source = source
    local playerName = GetPlayerName(source)

    if name == 'all' then
        local count = 0
        for i = 0, GetNumResources() - 1 do
            local res = GetResourceByFindIndex(i)
            if res and GetResourceState(res) == 'started' and not REFRESH_IGNORE[res] then
                ExecuteCommand('ensure ' .. res)
                count = count + 1
            end
        end
        print(('[Base] %s refreshed ALL resources (%d restarted)'):format(playerName, count))
        TriggerClientEvent('blacklist:refreshDone', source, 'all (' .. count .. ' resources)')
    else
        ExecuteCommand('ensure ' .. name)
        print(('[Base] %s refreshed resource: %s'):format(playerName, name))
        TriggerClientEvent('blacklist:refreshDone', source, name)
    end
end)
