local isMenuOpen = false
local wasInFreeRoam = false

RegisterNetEvent('blacklist:openMenu')
AddEventHandler('blacklist:openMenu', function()
    if isMenuOpen then return end
    isMenuOpen = true

    local currentState = exports.base:GetPlayerState()
    wasInFreeRoam = (currentState == 'freeroam')

    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'showMenu', show = true, fromFreeRoam = wasInFreeRoam })

    TriggerServerEvent('blacklist:requestPlayerData')
end)

RegisterNetEvent('blacklist:closeMenu')
AddEventHandler('blacklist:closeMenu', function()
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'showMenu', show = false })
end)

AddEventHandler('blacklist:toggleMenu', function()
    if isMenuOpen then
        if wasInFreeRoam then
            closeMenu()
            exports.base:SetPlayerState('freeroam')
        end
    else
        TriggerEvent('blacklist:openMenu')
    end
end)

-- Receive player data from server
RegisterNetEvent('blacklist:receivePlayerData')
AddEventHandler('blacklist:receivePlayerData', function(data)
    SendNUIMessage({
        action = 'playerData',
        player = data
    })
end)

-- Receive BlackList top 20
RegisterNetEvent('blacklist:receiveBlacklist')
AddEventHandler('blacklist:receiveBlacklist', function(data)
    SendNUIMessage({
        action = 'blacklistData',
        blacklist = data
    })
end)

-- Receive vehicle catalog for player's tier
RegisterNetEvent('blacklist:receiveVehicles')
AddEventHandler('blacklist:receiveVehicles', function(catalog, owned)
    SendNUIMessage({
        action = 'vehicleData',
        catalog = catalog,
        owned = owned
    })
end)

-- Receive chat message
RegisterNetEvent('blacklist:chatMessage')
AddEventHandler('blacklist:chatMessage', function(data)
    SendNUIMessage({
        action = 'chatMessage',
        message = data
    })
end)

-- Receive queue status updates
RegisterNetEvent('blacklist:queueUpdate')
AddEventHandler('blacklist:queueUpdate', function(data)
    SendNUIMessage({
        action = 'queueUpdate',
        queue = data
    })
end)

-- NUI Callbacks

RegisterNUICallback('closeMenu', function(data, cb)
    -- Never close the menu via ESC -- player must pick an action
    -- (the menu closes programmatically when joining freeroam/ranked/etc.)
    cb({})
end)

RegisterNUICallback('joinRanked', function(data, cb)
    TriggerEvent('blacklist:enableGhostMode', false)
    TriggerServerEvent('blacklist:joinQueue', 'ranked', data.crossTier == true, data.testMode == true)
    cb({})
end)

RegisterNUICallback('joinNormalChase', function(data, cb)
    TriggerEvent('blacklist:enableGhostMode', false)
    TriggerServerEvent('blacklist:joinQueue', 'normal')
    cb({})
end)

RegisterNUICallback('joinSoloTest', function(data, cb)
    TriggerEvent('blacklist:enableGhostMode', false)
    TriggerServerEvent('blacklist:joinSoloTest', data.mode or 'ranked', data.role or 'runner', data.tier)
    cb({})
end)

local function closeMenu()
    isMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'showMenu', show = false })
end

RegisterNUICallback('joinFreeRoam', function(data, cb)
    TriggerServerEvent('blacklist:joinFreeRoam')
    closeMenu()
    exports.base:SetPlayerState('freeroam')
    cb({})
end)

RegisterNUICallback('openMap', function(data, cb)
    closeMenu()
    exports.base:AllowGTAMap()
    cb({})
end)

RegisterNUICallback('openGTASettings', function(data, cb)
    closeMenu()
    exports.base:AllowGTAMap()
    cb({})
end)

RegisterNUICallback('resumeFreeRoam', function(data, cb)
    closeMenu()
    exports.base:SetPlayerState('freeroam')
    cb({})
end)

RegisterNUICallback('leaveQueue', function(data, cb)
    TriggerServerEvent('blacklist:leaveQueue')
    cb({})
end)

RegisterNUICallback('selectVehicle', function(data, cb)
    TriggerServerEvent('blacklist:selectVehicle', data.model)
    cb({})
end)

RegisterNUICallback('enterGarage', function(data, cb)
    if not data.model then cb({}) return end
    closeMenu()
    TriggerEvent('blacklist:enterGarage', data.model)
    cb({})
end)

RegisterNUICallback('saveVehicleTuning', function(data, cb)
    TriggerServerEvent('blacklist:saveVehicleTuning', data.model, data.tuning)
    cb({})
end)

RegisterNUICallback('sendChat', function(data, cb)
    TriggerServerEvent('blacklist:sendChat', data.message)
    cb({})
end)

RegisterNUICallback('requestBlacklist', function(data, cb)
    TriggerServerEvent('blacklist:requestBlacklist')
    cb({})
end)

RegisterNUICallback('requestVehicles', function(data, cb)
    TriggerServerEvent('blacklist:requestVehicles')
    cb({})
end)

