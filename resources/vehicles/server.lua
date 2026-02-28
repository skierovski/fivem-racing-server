-- ============================================================
-- Vehicle management: spawn, tuning, tier access
-- ============================================================

--- Get player's selected vehicle and tuning from DB
--- @param identifier string
--- @param callback function(vehicleData)
function GetPlayerVehicle(identifier, callback)
    exports.oxmysql:execute(
        [[SELECT pv.model, pv.tuning, vc.label, vc.tier
          FROM player_vehicles pv
          JOIN vehicle_catalog vc ON vc.model = pv.model
          WHERE pv.identifier = ? AND pv.is_selected = 1
          LIMIT 1]],
        { identifier },
        function(result)
            if result and result[1] then
                local data = result[1]
                if data.tuning and type(data.tuning) == 'string' then
                    data.tuning = json.decode(data.tuning)
                end
                callback(data)
            else
                -- No selected vehicle: give default bronze car
                callback({ model = 'sultan', tuning = {}, label = 'Karin Sultan', tier = 'bronze' })
            end
        end
    )
end

--- Spawn a vehicle for a player at given coords
RegisterNetEvent('blacklist:spawnPlayerVehicle')
AddEventHandler('blacklist:spawnPlayerVehicle', function(targetSource, x, y, z, heading)
    local source = source
    local identifier = getIdentifier(targetSource or source)
    if not identifier then return end

    GetPlayerVehicle(identifier, function(vehicleData)
        TriggerClientEvent('blacklist:doSpawnVehicle', targetSource or source, vehicleData, x, y, z, heading)
    end)
end)

--- Ensure a player has at least the default vehicle
RegisterNetEvent('blacklist:ensureDefaultVehicle')
AddEventHandler('blacklist:ensureDefaultVehicle', function()
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    exports.oxmysql:execute(
        'SELECT id FROM player_vehicles WHERE identifier = ? LIMIT 1',
        { identifier },
        function(result)
            if not result or #result == 0 then
                exports.oxmysql:execute(
                    'INSERT INTO player_vehicles (identifier, model, label, tier, is_selected) VALUES (?, ?, ?, ?, 1)',
                    { identifier, 'sultan', 'Karin Sultan', 'bronze' }
                )
                exports.oxmysql:execute(
                    'UPDATE players SET selected_vehicle = ? WHERE identifier = ?',
                    { 'sultan', identifier }
                )
            end
        end
    )
end)

exports('GetPlayerVehicle', GetPlayerVehicle)

function getIdentifier(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return nil
end

print('[Vehicles] ^2Server-side loaded^0')
