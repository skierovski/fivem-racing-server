local isOpen = false

local HANDLING_FIELDS = {
    { name = "fMass", type = "float", desc = "Weight (kg)" },
    { name = "fInitialDragCoeff", type = "float", desc = "Drag coefficient" },
    { name = "fPercentSubmerged", type = "float", desc = "% submerged before float" },
    { name = "fDriveBiasFront", type = "float", desc = "Drive bias front (0=RWD, 1=FWD)" },
    { name = "nInitialDriveGears", type = "int", desc = "Number of gears" },
    { name = "fInitialDriveForce", type = "float", desc = "Engine power" },
    { name = "fDriveInertia", type = "float", desc = "Drive inertia" },
    { name = "fClutchChangeRateScaleUpShift", type = "float", desc = "Clutch upshift rate" },
    { name = "fClutchChangeRateScaleDownShift", type = "float", desc = "Clutch downshift rate" },
    { name = "fInitialDriveMaxFlatVel", type = "float", desc = "Max speed (km/h)" },
    { name = "fBrakeForce", type = "float", desc = "Brake force" },
    { name = "fBrakeBiasFront", type = "float", desc = "Brake bias front" },
    { name = "fHandBrakeForce", type = "float", desc = "Handbrake force" },
    { name = "fSteeringLock", type = "float", desc = "Max steering angle" },
    { name = "fTractionCurveMax", type = "float", desc = "Traction max (grip)" },
    { name = "fTractionCurveMin", type = "float", desc = "Traction min" },
    { name = "fTractionCurveLateral", type = "float", desc = "Lateral traction" },
    { name = "fTractionSpringDeltaMax", type = "float", desc = "Traction spring delta max" },
    { name = "fLowSpeedTractionLossMult", type = "float", desc = "Low speed traction loss" },
    { name = "fCamberStiffnesss", type = "float", desc = "Camber stiffness" },
    { name = "fTractionBiasFront", type = "float", desc = "Traction bias front" },
    { name = "fTractionLossMult", type = "float", desc = "Traction loss multiplier" },
    { name = "fSuspensionForce", type = "float", desc = "Suspension force" },
    { name = "fSuspensionCompDamp", type = "float", desc = "Suspension compression damp" },
    { name = "fSuspensionReboundDamp", type = "float", desc = "Suspension rebound damp" },
    { name = "fSuspensionUpperLimit", type = "float", desc = "Suspension upper limit" },
    { name = "fSuspensionLowerLimit", type = "float", desc = "Suspension lower limit" },
    { name = "fSuspensionRaise", type = "float", desc = "Suspension raise" },
    { name = "fSuspensionBiasFront", type = "float", desc = "Suspension bias front" },
    { name = "fAntiRollBarForce", type = "float", desc = "Anti-roll bar force" },
    { name = "fAntiRollBarBiasFront", type = "float", desc = "Anti-roll bar bias front" },
    { name = "fRollCentreHeightFront", type = "float", desc = "Roll centre height front" },
    { name = "fRollCentreHeightRear", type = "float", desc = "Roll centre height rear" },
    { name = "fCollisionDamageMult", type = "float", desc = "Collision damage mult" },
    { name = "fWeaponDamageMult", type = "float", desc = "Weapon damage mult" },
    { name = "fDeformationDamageMult", type = "float", desc = "Deformation damage mult" },
    { name = "fEngineDamageMult", type = "float", desc = "Engine damage mult" },
    { name = "fPetrolTankVolume", type = "float", desc = "Fuel tank volume" },
    { name = "fOilVolume", type = "float", desc = "Oil volume" },
    { name = "fSeatOffsetDistX", type = "float", desc = "Seat offset X" },
    { name = "fSeatOffsetDistY", type = "float", desc = "Seat offset Y" },
    { name = "fSeatOffsetDistZ", type = "float", desc = "Seat offset Z" },
    { name = "nMonetaryValue", type = "int", desc = "Monetary value" },
    { name = "fBackEndPopUpCarImpulseMult", type = "float", desc = "Rear pop-up car impulse" },
    { name = "fBackEndPopUpBuildingImpulseMult", type = "float", desc = "Rear pop-up building impulse" },
    { name = "fBackEndPopUpMaxDeltaSpeed", type = "float", desc = "Rear pop-up max delta speed" },
    { name = "fCamberFront", type = "float", desc = "Camber front" },
    { name = "fCamberRear", type = "float", desc = "Camber rear" },
    { name = "fCastor", type = "float", desc = "Caster angle" },
    { name = "fToeFront", type = "float", desc = "Toe front" },
    { name = "fToeRear", type = "float", desc = "Toe rear" },
    { name = "fEngineResistance", type = "float", desc = "Engine resistance" },
    { name = "fInAirSteerMult", type = "float", desc = "In-air steering mult" },
}

local function getVehicleHandlingData(vehicle)
    local data = {}
    for _, field in ipairs(HANDLING_FIELDS) do
        local val
        if field.type == "int" then
            val = GetVehicleHandlingInt(vehicle, "CHandlingData", field.name)
        elseif field.type == "float" then
            val = GetVehicleHandlingFloat(vehicle, "CHandlingData", field.name)
        end
        if val then
            table.insert(data, {
                name = field.name,
                value = val,
                type = field.type,
                desc = field.desc,
            })
        end
    end
    return data
end

local function openEditor()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        print('^1[handling]^0 You must be in a vehicle')
        return
    end

    local model = GetEntityModel(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(model)
    local data = getVehicleHandlingData(vehicle)

    SendNUIMessage({
        action = 'open',
        vehicle = modelName,
        fields = data,
    })
    SetNuiFocus(true, true)
    isOpen = true
end

local function closeEditor()
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
    isOpen = false
end

RegisterNUICallback('close', function(_, cb)
    closeEditor()
    cb('ok')
end)

RegisterNUICallback('setValue', function(data, cb)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        print('^1[handling-editor]^0 Not in vehicle')
        cb({ ok = false })
        return
    end

    local name = data.name
    local value = tonumber(data.value)
    if not value then
        print('^1[handling-editor]^0 Invalid value for ' .. tostring(name))
        cb({ ok = false })
        return
    end

    local fieldType = nil
    for _, field in ipairs(HANDLING_FIELDS) do
        if field.name == name then
            fieldType = field.type
            break
        end
    end

    if not fieldType then
        print('^1[handling-editor]^0 Unknown field: ' .. name)
        cb({ ok = false })
        return
    end

    local before
    if fieldType == "int" then
        before = GetVehicleHandlingInt(vehicle, "CHandlingData", name)
        SetVehicleHandlingInt(vehicle, "CHandlingData", name, math.floor(value))
    else
        before = GetVehicleHandlingFloat(vehicle, "CHandlingData", name)
        SetVehicleHandlingFloat(vehicle, "CHandlingData", name, value + 0.0)
    end

    local after
    if fieldType == "int" then
        after = GetVehicleHandlingInt(vehicle, "CHandlingData", name)
    else
        after = GetVehicleHandlingFloat(vehicle, "CHandlingData", name)
    end

    print(string.format('^3[handling-editor]^0 %s: ^1%s^0 -> ^2%s^0 (readback: ^5%s^0)', name, tostring(before), tostring(value), tostring(after)))

    cb({ ok = true, value = value })
end)

RegisterNUICallback('getValues', function(_, cb)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        cb({ fields = {} })
        return
    end
    cb({ fields = getVehicleHandlingData(vehicle) })
end)

RegisterNUICallback('exportMeta', function(_, cb)
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        cb({ xml = '' })
        return
    end

    local lines = {}
    table.insert(lines, '  <Item type="CHandlingData">')
    for _, field in ipairs(HANDLING_FIELDS) do
        local val
        if field.type == "int" then
            val = GetVehicleHandlingInt(vehicle, "CHandlingData", field.name)
        elseif field.type == "float" then
            val = GetVehicleHandlingFloat(vehicle, "CHandlingData", field.name)
        end
        if val then
            if field.type == "float" then
                table.insert(lines, string.format('    <%s value="%f" />', field.name, val))
            else
                table.insert(lines, string.format('    <%s value="%d" />', field.name, val))
            end
        end
    end
    table.insert(lines, '  </Item>')

    cb({ xml = table.concat(lines, '\n') })
end)

RegisterCommand('handling', function()
    if isOpen then
        closeEditor()
    else
        openEditor()
    end
end, false)

RegisterKeyMapping('handling', 'Handling Editor', 'keyboard', '')
