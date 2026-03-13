local function getIdentifier(source)
    return exports.lib:GetIdentifier(source)
end

local function getDiscordIdentifier(source)
    return exports.lib:GetDiscordIdentifier(source)
end

-- Player data request handler
RegisterNetEvent('blacklist:requestPlayerData')
AddEventHandler('blacklist:requestPlayerData', function()
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    exports.oxmysql:execute(
        'SELECT * FROM players WHERE identifier = ?',
        { identifier },
        function(result)
            if result and result[1] then
                TriggerClientEvent('blacklist:receivePlayerData', source, result[1])
            else
                -- First-time player: create record
                local name = GetPlayerName(source) or 'Unknown'
                local discordId = getDiscordIdentifier(source)
                exports.oxmysql:execute(
                    'INSERT INTO players (identifier, discord_id, name, mmr, tier) VALUES (?, ?, ?, 500, ?)',
                    { identifier, discordId, name, 'bronze' },
                    function()
                        exports.oxmysql:execute(
                            'SELECT * FROM players WHERE identifier = ?',
                            { identifier },
                            function(newResult)
                                if newResult and newResult[1] then
                                    TriggerClientEvent('blacklist:receivePlayerData', source, newResult[1])
                                end
                            end
                        )
                    end
                )
            end
        end
    )
end)

-- BlackList top 20 request
RegisterNetEvent('blacklist:requestBlacklist')
AddEventHandler('blacklist:requestBlacklist', function()
    local source = source
    exports.oxmysql:execute(
        'SELECT identifier, name, mmr, tier, wins, losses FROM players ORDER BY mmr DESC LIMIT 20',
        {},
        function(result)
            if not result then
                print('[Menu] ^1DB error fetching blacklist leaderboard^0')
                return
            end
            TriggerClientEvent('blacklist:receiveBlacklist', source, result)
        end
    )
end)

-- Vehicle catalog + owned vehicles request
RegisterNetEvent('blacklist:requestVehicles')
AddEventHandler('blacklist:requestVehicles', function()
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    -- All Season 1 cars available to everyone (ranked + PD)
    exports.oxmysql:execute(
        'SELECT * FROM vehicle_catalog ORDER BY FIELD(tier, "bronze","silver","gold","platinum","diamond","blacklist","custom"), label',
        {},
        function(catalog)
            if not catalog then
                print('[Menu] ^1DB error fetching vehicle catalog^0')
                return
            end
            exports.oxmysql:execute(
                'SELECT * FROM player_vehicles WHERE identifier = ?',
                { identifier },
                function(owned)
                    if not owned then
                        print('[Menu] ^1DB error fetching owned vehicles^0')
                        return
                    end
                    TriggerClientEvent('blacklist:receiveVehicles', source, catalog, owned)
                end
            )
        end
    )
end)

-- Select vehicle
RegisterNetEvent('blacklist:selectVehicle')
AddEventHandler('blacklist:selectVehicle', function(model)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    -- Deselect all, then select the chosen one
    exports.oxmysql:execute('UPDATE player_vehicles SET is_selected = 0 WHERE identifier = ?', { identifier })
    exports.oxmysql:execute('UPDATE player_vehicles SET is_selected = 1 WHERE identifier = ? AND model = ?', { identifier, model })
    exports.oxmysql:execute('UPDATE players SET selected_vehicle = ? WHERE identifier = ?', { model, identifier })
end)

-- Save vehicle tuning
RegisterNetEvent('blacklist:saveVehicleTuning')
AddEventHandler('blacklist:saveVehicleTuning', function(model, tuning)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    local tuningJson = json.encode(tuning)

    exports.oxmysql:execute(
        'INSERT INTO player_vehicles (identifier, model, tuning, is_selected) VALUES (?, ?, ?, 1) ON DUPLICATE KEY UPDATE tuning = ?',
        { identifier, model, tuningJson, tuningJson }
    )
end)

-- Recent matches for a player in a specific mode
RegisterNetEvent('blacklist:requestRecentMatches')
AddEventHandler('blacklist:requestRecentMatches', function(mode)
    local source = source
    local identifier = getIdentifier(source)
    if not identifier then return end

    mode = (mode == 'normal' or mode == 'ranked') and mode or 'ranked'

    exports.oxmysql:execute(
        [[SELECT m.*, p_runner.name as runner_name
          FROM match_history m
          LEFT JOIN players p_runner ON p_runner.identifier = m.runner_id
          WHERE m.runner_id = ? OR JSON_CONTAINS(m.chaser_ids, ?)
          ORDER BY m.id DESC LIMIT 10]],
        { identifier, json.encode(identifier) },
        function(results)
            if not results then
                TriggerClientEvent('blacklist:receiveRecentMatches', source, {})
                return
            end

            local matches = {}
            for _, row in ipairs(results) do
                local isRunner = row.runner_id == identifier
                local opponent = ''
                local mmrChange = 0
                local isWin = (row.winner_id == identifier)

                if isRunner then
                    local chaserIds = json.decode(row.chaser_ids or '[]')
                    if #chaserIds > 0 then
                        local oppId = chaserIds[1]
                        local oppResult = exports.oxmysql:executeSync(
                            'SELECT name FROM players WHERE identifier = ? LIMIT 1',
                            { oppId }
                        )
                        opponent = (oppResult and oppResult[1]) and oppResult[1].name or 'Unknown'
                        if #chaserIds > 1 then
                            opponent = opponent .. ' +' .. (#chaserIds - 1)
                        end
                    end
                    mmrChange = row.mmr_change_runner or 0
                else
                    opponent = row.runner_name or 'Unknown'
                    mmrChange = row.mmr_change_chaser or 0
                end

                table.insert(matches, {
                    opponent = opponent,
                    result = isWin and 'win' or 'loss',
                    mmrChange = mmrChange,
                    duration = row.duration_seconds or 0,
                })
            end

            TriggerClientEvent('blacklist:receiveRecentMatches', source, matches)
        end
    )
end)

-- Mode leaderboard (top 10)
RegisterNetEvent('blacklist:requestModeLeaderboard')
AddEventHandler('blacklist:requestModeLeaderboard', function(mode)
    local source = source
    exports.oxmysql:execute(
        'SELECT name, mmr, tier, wins, losses FROM players ORDER BY mmr DESC LIMIT 10',
        {},
        function(result)
            if not result then
                TriggerClientEvent('blacklist:receiveModeLeaderboard', source, {})
                return
            end
            TriggerClientEvent('blacklist:receiveModeLeaderboard', source, result)
        end
    )
end)

-- Check if player can close menu (only in freeroam)
RegisterNetEvent('blacklist:checkCanCloseMenu')
AddEventHandler('blacklist:checkCanCloseMenu', function()
    local source = source
    -- For now, always allow. Matchmaking resource will track player state.
    TriggerClientEvent('blacklist:closeMenu', source)
end)

-- Update player online status
AddEventHandler('playerConnecting', function()
    local source = source
    local identifier = getIdentifier(source)
    if identifier then
        exports.oxmysql:execute('UPDATE players SET is_online = 1, last_seen = NOW() WHERE identifier = ?', { identifier })
    end
end)

AddEventHandler('playerDropped', function()
    local source = source
    local identifier = getIdentifier(source)
    if identifier then
        exports.oxmysql:execute('UPDATE players SET is_online = 0, last_seen = NOW() WHERE identifier = ?', { identifier })
    end
end)

print('[Menu] ^2Server-side loaded^0')
