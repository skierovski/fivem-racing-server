local RESOURCE_PATH = GetResourcePath(GetCurrentResourceName())
local TIER_FOLDERS = { 'bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist' }
local TIER_SET = {}
for _, t in ipairs(TIER_FOLDERS) do TIER_SET[t] = true end

local HandlingOverrides = {}

local function readFile(relativePath)
    local fullPath = RESOURCE_PATH .. '/' .. relativePath
    local f = io.open(fullPath, 'r')
    if not f then return nil end
    local content = f:read('*a')
    f:close()
    return content
end

local function parseMetaFile(filePath)
    local content = readFile(filePath)
    if not content then return nil end

    local data = { floats = {}, ints = {}, vectors = {}, subFloats = {} }

    data.handlingName = content:match('<handlingName>(%w+)</handlingName>')

    -- Strip SubHandlingData before parsing main block to avoid double-counting
    local subBlock = content:match('<Item type="CCarHandlingData">(.-)</Item>')
    local mainContent = content:gsub('<SubHandlingData>.-</SubHandlingData>', '')

    for name, val in mainContent:gmatch('<(f%w+)%s+value="([^"]+)"') do
        data.floats[name] = tonumber(val)
    end

    for name, val in mainContent:gmatch('<(n%w+)%s+value="([^"]+)"') do
        data.ints[name] = math.floor(tonumber(val))
    end

    for name, x, y, z in mainContent:gmatch('<(vec%w+)%s+x="([^"]+)"%s+y="([^"]+)"%s+z="([^"]+)"') do
        data.vectors[name] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end

    if subBlock then
        for name, val in subBlock:gmatch('<(f%w+)%s+value="([^"]+)"') do
            data.subFloats[name] = tonumber(val)
        end
    end

    return data
end

local function loadAllOverrides()
    HandlingOverrides = {}

    local manifest = readFile('fxmanifest.lua')
    if not manifest then
        print('[handling] ^1Failed to read fxmanifest.lua^0')
        return
    end

    local count = 0
    for path in manifest:gmatch("data_file%s+'HANDLING_FILE'%s+'([^']+)'") do
        local folder = path:match('^(%w+)/')
        if folder and TIER_SET[folder] then
            local data = parseMetaFile(path)
            if data then
                local modelName = path:match('/(.+)%.meta$')
                if modelName then
                    HandlingOverrides[modelName:lower()] = data
                    count = count + 1
                    print(('[handling]   %s/%s -> %s'):format(folder, modelName, data.handlingName or '?'))
                end
            else
                print(('[handling] ^1Failed to parse %s^0'):format(path))
            end
        end
    end

    print(('[handling] ^2Loaded %d tier handling overrides^0'):format(count))
end

loadAllOverrides()

RegisterNetEvent('handling:requestOverrides')
AddEventHandler('handling:requestOverrides', function()
    TriggerClientEvent('handling:receiveOverrides', source, HandlingOverrides)
end)

-- On resource (re)start, push to all connected players immediately
Citizen.CreateThread(function()
    Citizen.Wait(500)
    for _, playerId in ipairs(GetPlayers()) do
        TriggerClientEvent('handling:receiveOverrides', tonumber(playerId), HandlingOverrides)
    end
end)

print('[handling] ^2Server-side handling override system loaded^0')
