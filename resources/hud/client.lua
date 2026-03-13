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

-- Send speed/gear/rpm data to NUI
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(80)

        if hudVisible then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh ~= 0 then
                SendNUIMessage({
                    action = 'updateHud',
                    speed = math.floor(GetEntitySpeed(veh) * 3.6),
                    gear = GetVehicleCurrentGear(veh),
                    rpm = GetVehicleCurrentRpm(veh),
                    inVehicle = true,
                })
            else
                SendNUIMessage({ action = 'updateHud', inVehicle = false })
            end
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

-- NUI callback: send chat message
RegisterNUICallback('sendChat', function(data, cb)
    if data.message and #data.message > 0 then
        TriggerServerEvent('blacklist:sendChat', data.message)
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
