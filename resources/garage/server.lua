-- ============================================================
-- Benny's Garage - Tuning System (server)
-- ============================================================

local function getIdentifier(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return nil
end

RegisterNetEvent('blacklist:requestTuningData')
AddEventHandler('blacklist:requestTuningData', function(model)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    exports.oxmysql:execute(
        'SELECT tuning FROM player_vehicles WHERE identifier = ? AND model = ? LIMIT 1',
        { identifier, model },
        function(result)
            local savedTuning = nil
            if result and result[1] and result[1].tuning then
                local raw = result[1].tuning
                if type(raw) == 'string' then
                    savedTuning = json.decode(raw)
                else
                    savedTuning = raw
                end
            end
            TriggerClientEvent('blacklist:receiveTuningData', source, {}, savedTuning)
        end
    )
end)

RegisterNetEvent('blacklist:saveTuning')
AddEventHandler('blacklist:saveTuning', function(model, tuning)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier or not model then return end

    local tuningJson = json.encode(tuning or {})

    -- Upsert: update if exists, insert if not
    exports.oxmysql:execute(
        'SELECT id FROM player_vehicles WHERE identifier = ? AND model = ? LIMIT 1',
        { identifier, model },
        function(result)
            if result and result[1] then
                exports.oxmysql:execute(
                    'UPDATE player_vehicles SET tuning = ? WHERE identifier = ? AND model = ?',
                    { tuningJson, identifier, model }
                )
            else
                -- Get vehicle label and tier from catalog
                exports.oxmysql:execute(
                    'SELECT label, tier FROM vehicle_catalog WHERE model = ? LIMIT 1',
                    { model },
                    function(catResult)
                        local label = 'Unknown'
                        local tier = 'bronze'
                        if catResult and catResult[1] then
                            label = catResult[1].label
                            tier = catResult[1].tier
                        end
                        exports.oxmysql:execute(
                            'INSERT INTO player_vehicles (identifier, model, label, tier, tuning, is_selected) VALUES (?, ?, ?, ?, ?, 0)',
                            { identifier, model, label, tier, tuningJson }
                        )
                    end
                )
            end
        end
    )

    print(('[Garage] %s saved tuning for %s'):format(GetPlayerName(source), model))
end)

-- ========================
-- Routing bucket isolation for garage
-- ========================

RegisterNetEvent('blacklist:enterGarageBucket')
AddEventHandler('blacklist:enterGarageBucket', function()
    local source = source
    SetPlayerRoutingBucket(source, 500 + source)
end)

RegisterNetEvent('blacklist:leaveGarageBucket')
AddEventHandler('blacklist:leaveGarageBucket', function()
    local source = source
    SetPlayerRoutingBucket(source, 0)
end)

print('[Garage] ^2Server-side loaded^0')
