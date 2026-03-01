-- ============================================================
-- Free roam: spawn player in LS with their car, ghosted
-- ============================================================

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

-- Send full vehicle catalog for freeroam car selection
RegisterNetEvent('blacklist:requestVehiclesForFreeroam')
AddEventHandler('blacklist:requestVehiclesForFreeroam', function()
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    exports.oxmysql:execute(
        'SELECT tier FROM players WHERE identifier = ?',
        { identifier },
        function(playerResult)
            if not playerResult or not playerResult[1] then return end
            local playerTier = playerResult[1].tier

            local tierOrder = { 'bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist' }
            local playerTierIndex = 1
            for i, t in ipairs(tierOrder) do
                if t == playerTier then playerTierIndex = i break end
            end

            local availableTiers = {}
            for i = 1, playerTierIndex do
                table.insert(availableTiers, tierOrder[i])
            end

            local placeholders = {}
            for _ in ipairs(availableTiers) do
                table.insert(placeholders, '?')
            end

            exports.oxmysql:execute(
                'SELECT model, label, tier FROM vehicle_catalog WHERE tier IN (' .. table.concat(placeholders, ',') .. ') ORDER BY tier, label',
                availableTiers,
                function(catalog)
                    TriggerClientEvent('blacklist:receiveFreeroamVehicles', source, catalog or {})
                end
            )
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

function getIdentifier(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return nil
end

print('[FreeRoam] ^2Server-side loaded^0')
