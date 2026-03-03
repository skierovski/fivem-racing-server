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
                callback({ model = 'futo', tuning = {}, label = 'Karin Futo', tier = 'bronze' })
            end
        end
    )
end

--- Spawn a specific model for a player, loading their tuning for that model from DB
RegisterNetEvent('blacklist:spawnPlayerWithModel')
AddEventHandler('blacklist:spawnPlayerWithModel', function(targetSource, model, x, y, z, heading)
    local identifier = getIdentifier(targetSource)
    if not identifier then return end

    exports.oxmysql:execute(
        'SELECT tuning FROM player_vehicles WHERE identifier = ? AND model = ? LIMIT 1',
        { identifier, model },
        function(result)
            local tuning = {}
            if result and result[1] and result[1].tuning then
                tuning = type(result[1].tuning) == 'string' and json.decode(result[1].tuning) or result[1].tuning
            end
            TriggerClientEvent('blacklist:doSpawnVehicle', targetSource,
                { model = model, tuning = tuning, label = model, tier = 'ranked' }, x, y, z, heading)
        end
    )
end)

--- Spawn a vehicle for a player at given coords, optionally forcing a tier
RegisterNetEvent('blacklist:spawnPlayerVehicle')
AddEventHandler('blacklist:spawnPlayerVehicle', function(targetSource, x, y, z, heading, forceTier)
    local source = source
    local identifier = getIdentifier(targetSource or source)
    if not identifier then return end

    GetPlayerVehicle(identifier, function(vehicleData)
        if forceTier and vehicleData.tier ~= forceTier then
            GetPlayerVehicleForTier(identifier, forceTier, function(tierVehicle)
                TriggerClientEvent('blacklist:doSpawnVehicle', targetSource or source, tierVehicle, x, y, z, heading)
            end)
        else
            TriggerClientEvent('blacklist:doSpawnVehicle', targetSource or source, vehicleData, x, y, z, heading)
        end
    end)
end)

--- Get best vehicle a player owns from a specific tier (for cross-tier enforcement)
function GetPlayerVehicleForTier(identifier, tier, callback)
    exports.oxmysql:execute(
        [[SELECT pv.model, pv.tuning, vc.label, vc.tier
          FROM player_vehicles pv
          JOIN vehicle_catalog vc ON vc.model = pv.model
          WHERE pv.identifier = ? AND vc.tier = ?
          LIMIT 1]],
        { identifier, tier },
        function(result)
            if result and result[1] then
                local data = result[1]
                if data.tuning and type(data.tuning) == 'string' then
                    data.tuning = json.decode(data.tuning)
                end
                callback(data)
            else
                -- Player has no vehicle in this tier: give default for tier
                local defaults = {
                    bronze = { model = 'futo', label = 'Karin Futo' },
                    silver = { model = 'gb_cometclf', label = 'Pfister Comet CLF' },
                    gold = { model = 'roxanne', label = 'Roxanne' },
                    platinum = { model = 'gb_argento7f', label = 'Argento 7F' },
                    diamond = { model = 'gb_tr3s', label = 'TR3S' },
                    blacklist = { model = 'gsttoros1', label = 'GST Toros' },
                }
                local def = defaults[tier] or defaults.bronze
                callback({ model = def.model, tuning = {}, label = def.label, tier = tier })
            end
        end
    )
end

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
                    { identifier, 'futo', 'Karin Futo', 'bronze' }
                )
                exports.oxmysql:execute(
                    'UPDATE players SET selected_vehicle = ? WHERE identifier = ?',
                    { 'futo', identifier }
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
