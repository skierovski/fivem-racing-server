local function getIdentifier(source)
    return exports.lib:GetIdentifier(source)
end

local MAX_MESSAGE_LENGTH = 256
local recentMessages = {}
local MAX_HISTORY = 50

RegisterNetEvent('blacklist:sendChat')
AddEventHandler('blacklist:sendChat', function(message)
    local source = source
    if not message or type(message) ~= 'string' then return end

    message = message:sub(1, MAX_MESSAGE_LENGTH)

    -- Strip any HTML/script injection
    message = message:gsub('<', '&lt;'):gsub('>', '&gt;')

    if #message == 0 then return end

    local identifier = getIdentifier(source)
    local playerName = GetPlayerName(source) or 'Unknown'

    -- Get player tier from DB
    exports.oxmysql:execute(
        'SELECT tier FROM players WHERE identifier = ?',
        { identifier },
        function(result)
            local tier = 'bronze'
            if result and result[1] then
                tier = result[1].tier
            end

            local chatData = {
                name = playerName,
                tier = tier,
                message = message
            }

            -- Store in history
            table.insert(recentMessages, chatData)
            if #recentMessages > MAX_HISTORY then
                table.remove(recentMessages, 1)
            end

            -- Broadcast to all players
            TriggerClientEvent('blacklist:chatMessage', -1, chatData)

            -- Persist to DB (optional)
            exports.oxmysql:execute(
                'INSERT INTO chat_messages (identifier, player_name, tier, message) VALUES (?, ?, ?, ?)',
                { identifier, playerName, tier, message }
            )
        end
    )
end)

-- Send recent chat history to newly connected player
RegisterNetEvent('blacklist:requestChatHistory')
AddEventHandler('blacklist:requestChatHistory', function()
    local source = source
    for _, msg in ipairs(recentMessages) do
        TriggerClientEvent('blacklist:chatMessage', source, msg)
    end
end)

print('[Chat] ^2Server-side loaded^0')
