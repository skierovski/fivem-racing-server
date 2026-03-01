local hudVisible = false

-- Show/hide HUD based on player state
RegisterNetEvent('blacklist:setHudVisible')
AddEventHandler('blacklist:setHudVisible', function(show)
    hudVisible = show
    SendNUIMessage({ action = 'showHud', show = show })
end)

-- Auto-show when entering freeroam or match, auto-hide when in menu
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
                local speed = GetEntitySpeed(veh) * 3.6
                local gear = GetVehicleCurrentGear(veh)
                local rpm = GetVehicleCurrentRpm(veh)

                SendNUIMessage({
                    action = 'updateHud',
                    speed = math.floor(speed),
                    gear = gear,
                    rpm = rpm,
                    inVehicle = true,
                })
            else
                SendNUIMessage({
                    action = 'updateHud',
                    inVehicle = false,
                })
            end
        end
    end
end)

-- Receive tier updates from other resources
RegisterNetEvent('blacklist:receivePlayerData')
AddEventHandler('blacklist:receivePlayerData', function(data)
    if data and data.tier then
        SendNUIMessage({ action = 'updateTier', tier = data.tier })
    end
end)

-- Also grab tier on resource start
Citizen.CreateThread(function()
    Citizen.Wait(3000)
    TriggerServerEvent('blacklist:requestPlayerData')
end)

print('[HUD] ^2Custom HUD loaded^0')
