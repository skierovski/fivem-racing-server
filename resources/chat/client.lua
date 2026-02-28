-- Request chat history when player loads
Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('blacklist:requestChatHistory')
end)

-- Chat messages are forwarded to menu NUI via the menu resource's client.lua
-- This resource only handles the client-side event relay

RegisterNetEvent('blacklist:chatMessage')
AddEventHandler('blacklist:chatMessage', function(data)
    -- The menu resource also listens for this event and forwards to NUI
end)

print('[Chat] ^2Client-side loaded^0')
