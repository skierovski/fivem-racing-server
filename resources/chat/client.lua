-- Request chat history when player loads
Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('blacklist:requestChatHistory')
end)

print('[Chat] ^2Client-side loaded^0')
