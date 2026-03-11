local botToken = GetConvar('discord_bot_token', '')
local guildId = GetConvar('discord_guild_id', '')
local requiredRoleId = GetConvar('discord_required_role_id', '')
local inviteUrl = GetConvar('discord_invite_url', 'https://discord.gg/blacklistracing')

local function getDiscordId(source)
    return exports.lib:GetDiscordIdentifier(source)
end

local function checkDiscordRole(discordId, callback)
    if botToken == '' or guildId == '' or requiredRoleId == '' then
        print('[Discord] ^1WARNING: Discord convars not configured. Allowing all players.^0')
        callback(true)
        return
    end

    PerformHttpRequest(
        ('https://discord.com/api/v10/guilds/%s/members/%s'):format(guildId, discordId),
        function(statusCode, responseText, headers)
            if statusCode == 200 then
                local member = json.decode(responseText)
                if member and member.roles then
                    for _, roleId in ipairs(member.roles) do
                        if roleId == requiredRoleId then
                            callback(true)
                            return
                        end
                    end
                end
                callback(false, 'missing_role')
            elseif statusCode == 404 then
                callback(false, 'not_in_server')
            else
                print(('[Discord] ^3API returned status %d for user %s^0'):format(statusCode, discordId))
                callback(false, 'api_error')
            end
        end,
        'GET',
        '',
        { ['Authorization'] = 'Bot ' .. botToken }
    )
end

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source
    deferrals.defer()
    deferrals.update('Verifying Discord membership...')

    Wait(0)

    local discordId = getDiscordId(source)

    if not discordId then
        deferrals.done('\n🔒 BlackList Racing\n\nYou must have Discord linked to your FiveM account.\nGo to FiveM Settings > Accounts > Link Discord.\n\nThen join our Discord: ' .. inviteUrl)
        return
    end

    checkDiscordRole(discordId, function(hasRole, reason)
        if hasRole then
            deferrals.done()
        elseif reason == 'not_in_server' then
            deferrals.done('\n🔒 BlackList Racing\n\nYou must join our Discord server to play.\n\n' .. inviteUrl)
        elseif reason == 'missing_role' then
            deferrals.done('\n🔒 BlackList Racing\n\nYou must have the Verified role in our Discord.\nJoin and follow the verification steps.\n\n' .. inviteUrl)
        else
            deferrals.done('\n🔒 BlackList Racing\n\nCould not verify your Discord status.\nPlease try again in a moment.\n\n' .. inviteUrl)
        end
    end)
end)

print('[Discord] ^2Role verification loaded^0')
