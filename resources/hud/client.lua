local hudVisible = false
local chatOpen = false

-- Auto-show when entering freeroam or match, hide when in menu (menu has its own chat)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        local state = exports.base:GetPlayerState()
        local shouldShow = (state == 'freeroam' or state == 'in_match')

        if shouldShow ~= hudVisible then
            hudVisible = shouldShow
            SendNUIMessage({ action = 'showHud', show = hudVisible })
        end
    end
end)

-- Hide GTA health/armor bars every frame
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if hudVisible then
            HideHudComponentThisFrame(3)  -- CASH
            HideHudComponentThisFrame(4)  -- MP_CASH
            HideHudComponentThisFrame(6)  -- VEHICLE_NAME
            HideHudComponentThisFrame(7)  -- AREA_NAME
            HideHudComponentThisFrame(9)  -- STREET_NAME
        end
    end
end)

-- T key opens chat (control 245 = INPUT_MP_TEXT_CHAT_ALL)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        DisableControlAction(0, 245, true)
        if hudVisible and not chatOpen then
            if IsDisabledControlJustPressed(0, 245) then
                chatOpen = true
                SetNuiFocus(true, false)
                SendNUIMessage({ action = 'openChat' })
            end
        end
    end
end)

-- NUI callback: close chat
RegisterNUICallback('closeChat', function(data, cb)
    chatOpen = false
    SetNuiFocus(false, false)
    cb({})
end)

-- NUI callback: send chat message (supports /commands)
RegisterNUICallback('sendChat', function(data, cb)
    if data.message and #data.message > 0 then
        local msg = data.message
        if string.sub(msg, 1, 1) == '/' then
            ExecuteCommand(string.sub(msg, 2))
        else
            TriggerServerEvent('blacklist:sendChat', msg)
        end
    end
    cb({})
end)

-- Receive chat messages and forward to NUI
RegisterNetEvent('blacklist:chatMessage')
AddEventHandler('blacklist:chatMessage', function(data)
    SendNUIMessage({ action = 'chatMessage', message = data })
end)

-- Receive tier from player data
RegisterNetEvent('blacklist:receivePlayerData')
AddEventHandler('blacklist:receivePlayerData', function(data)
    if data and data.tier then
        SendNUIMessage({ action = 'updateTier', tier = data.tier })
    end
end)

-- Request tier + chat history on start
Citizen.CreateThread(function()
    Citizen.Wait(3000)
    TriggerServerEvent('blacklist:requestPlayerData')
    TriggerServerEvent('blacklist:requestChatHistory')
end)

print('[HUD] ^2Custom HUD + Chat loaded^0')
