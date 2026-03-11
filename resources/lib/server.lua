-- ============================================================
-- Shared server-side utilities
-- ============================================================

--- Extract the FiveM license identifier for a player
--- @param source number  server-side player ID
--- @return string|nil
local function getIdentifier(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, 'license:') then
            return id
        end
    end
    return nil
end

--- Extract the bare Discord user ID (without the "discord:" prefix)
--- @param source number  server-side player ID
--- @return string|nil
local function getDiscordIdentifier(source)
    for _, id in ipairs(GetPlayerIdentifiers(source)) do
        if string.find(id, 'discord:') then
            return string.gsub(id, 'discord:', '')
        end
    end
    return nil
end

exports('GetIdentifier', getIdentifier)
exports('GetDiscordIdentifier', getDiscordIdentifier)

print('[Lib] ^2Shared server utilities loaded^0')
