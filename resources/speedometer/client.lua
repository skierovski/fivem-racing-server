local isVisible = false
local UPDATE_MS = 50

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(UPDATE_MS)

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local inVehicle = vehicle ~= 0

        if inVehicle and not isVisible then
            isVisible = true
            SendNUIMessage({ action = 'show', visible = true })
        elseif not inVehicle and isVisible then
            isVisible = false
            SendNUIMessage({ action = 'show', visible = false })
        end

        if inVehicle then
            local speed = GetEntitySpeed(vehicle)
            local speedKmh = math.floor(speed * 3.6)
            local speedMph = math.floor(speed * 2.236936)

            local rpm = GetVehicleCurrentRpm(vehicle)
            local gear = GetVehicleCurrentGear(vehicle)
            local health = GetVehicleEngineHealth(vehicle)
            local healthPct = math.max(0, math.min(100, math.floor(health / 10)))

            SendNUIMessage({
                action = 'update',
                speed = speedKmh,
                speedMph = speedMph,
                rpm = rpm,
                gear = gear,
                health = healthPct,
            })
        end
    end
end)

print('[Speedometer] ^2Client-side loaded^0')
