-- ============================================================
-- Free roam: spawn player in LS with their car, ghosted
-- ============================================================

local function getIdentifier(source)
    return exports.lib:GetIdentifier(source)
end

local freeroamPlayers = {} -- source -> true

RegisterNetEvent('blacklist:enterFreeRoam')
AddEventHandler('blacklist:enterFreeRoam', function(targetSource)
    local source = targetSource or source
    freeroamPlayers[source] = true

    local spawn = { x = 152.79, y = -1034.03, z = 29.34, heading = 331.69 }

    -- Fetch player's selected vehicle + tuning from DB
    local identifier = getIdentifier(source)
    if identifier then
        exports.vehicles:GetPlayerVehicle(identifier, function(vehicleData)
            spawn.vehicle = vehicleData
            TriggerClientEvent('blacklist:enterFreeRoamClient', source, spawn)
        end)
    else
        TriggerClientEvent('blacklist:enterFreeRoamClient', source, spawn)
    end

    print(('[FreeRoam] %s entered free roam'):format(GetPlayerName(source)))
end)

RegisterNetEvent('blacklist:leaveFreeRoam')
AddEventHandler('blacklist:leaveFreeRoam', function()
    local source = source
    freeroamPlayers[source] = nil
    TriggerClientEvent('blacklist:enableGhostMode', source, false)
end)

-- Send full vehicle catalog for freeroam car selection (all tiers, no restrictions)
RegisterNetEvent('blacklist:requestVehiclesForFreeroam')
AddEventHandler('blacklist:requestVehiclesForFreeroam', function()
    local source = source

    exports.oxmysql:execute(
        'SELECT model, label, tier FROM vehicle_catalog ORDER BY FIELD(tier, "bronze","silver","gold","platinum","diamond","blacklist","custom"), label',
        {},
        function(catalog)
            if not catalog then
                print('[FreeRoam] ^1DB error fetching vehicle catalog^0')
                return
            end
            TriggerClientEvent('blacklist:receiveFreeroamVehicles', source, catalog)
        end
    )
end)

RegisterNetEvent('blacklist:requestFreeroamTuning')
AddEventHandler('blacklist:requestFreeroamTuning', function(model)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then
        TriggerClientEvent('blacklist:receiveFreeroamTuning', source, model, nil)
        return
    end

    exports.oxmysql:execute(
        'SELECT tuning FROM player_vehicles WHERE identifier = ? AND model = ?',
        { identifier, model },
        function(result)
            local tuning = nil
            if result and result[1] and result[1].tuning then
                tuning = json.decode(result[1].tuning)
            end
            TriggerClientEvent('blacklist:receiveFreeroamTuning', source, model, tuning)
        end
    )
end)

AddEventHandler('playerDropped', function()
    local source = source
    freeroamPlayers[source] = nil
end)

exports('IsInFreeRoam', function(source)
    return freeroamPlayers[source] == true
end)

print('[FreeRoam] ^2Server-side loaded^0')
