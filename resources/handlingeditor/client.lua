local isOpen = false
local pendingOverrides = {}

local HANDLING_FIELDS = {
    { name = "fMass", type = "float", desc = "Weight (kg)" },
    { name = "fInitialDragCoeff", type = "float", desc = "Drag coefficient" },
    { name = "fPercentSubmerged", type = "float", desc = "% submerged before float" },
    { name = "fDriveBiasFront", type = "float", desc = "Drive bias front (0=RWD, 1=FWD)" },
    { name = "nInitialDriveGears", type = "int", desc = "Number of gears", readonly = true },
    { name = "fInitialDriveForce", type = "float", desc = "Engine power" },
    { name = "fDriveInertia", type = "float", desc = "Drive inertia" },
    { name = "fClutchChangeRateScaleUpShift", type = "float", desc = "Clutch upshift rate" },
    { name = "fClutchChangeRateScaleDownShift", type = "float", desc = "Clutch downshift rate" },
    { name = "fInitialDriveMaxFlatVel", type = "float", desc = "Max speed (km/h)", readonly = true },
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

local FIELD_TYPE_MAP = {}
local FIELD_READONLY = {}
for _, field in ipairs(HANDLING_FIELDS) do
    FIELD_TYPE_MAP[field.name] = field.type
    if field.readonly then FIELD_READONLY[field.name] = true end
end

local function applyHandlingValue(vehicle, name, value, fieldType)
    if fieldType == "int" then
        SetVehicleHandlingInt(vehicle, "CHandlingData", name, math.floor(value))
    else
        SetVehicleHandlingFloat(vehicle, "CHandlingData", name, value + 0.0)
    end

end

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
                readonly = field.readonly or false,
            })
        end
    end
    return data
end

-- Per-frame thread: continuously re-apply overrides so GTA can't reset them
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle ~= 0 and next(pendingOverrides) then
            for name, info in pairs(pendingOverrides) do
                applyHandlingValue(vehicle, name, info.value, info.type)
            end
        end
    end
end)

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
        cb({ ok = false })
        return
    end

    local name = data.name
    local value = tonumber(data.value)
    if not value then
        cb({ ok = false })
        return
    end

    local fieldType = FIELD_TYPE_MAP[name]
    if not fieldType then
        cb({ ok = false })
        return
    end

    if FIELD_READONLY[name] then
        print('^1[handling-editor]^0 ' .. name .. ' is read-only (edit handling.meta + restart server)')
        cb({ ok = false })
        return
    end

    local before
    if fieldType == "int" then
        before = GetVehicleHandlingInt(vehicle, "CHandlingData", name)
    else
        before = GetVehicleHandlingFloat(vehicle, "CHandlingData", name)
    end

    applyHandlingValue(vehicle, name, value, fieldType)
    pendingOverrides[name] = { value = value, type = fieldType }

    print(string.format('^3[handling-editor]^0 %s: ^1%s^0 -> ^2%s^0 (locked)', name, tostring(before), tostring(value)))

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

-- /handling — toggle editor UI
RegisterCommand('handling', function()
    if isOpen then
        closeEditor()
    else
        openEditor()
    end
end, false)

-- /handling_reset — clear all overrides, revert to original handling
RegisterCommand('handling_reset', function()
    pendingOverrides = {}
    print('^2[handling-editor]^0 All overrides cleared. Respawn car to get original handling.')
end, false)

-- /handling_strip — remove all performance mods from current vehicle
RegisterCommand('handling_strip', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        print('^1[handling-editor]^0 Not in vehicle')
        return
    end

    SetVehicleModKit(vehicle, 0)
    local perfMods = { 11, 12, 13, 15, 16, 18 }
    for _, modType in ipairs(perfMods) do
        SetVehicleMod(vehicle, modType, -1, false)
    end
    print('^2[handling-editor]^0 Stripped performance mods (engine, brakes, transmission, suspension, armor, turbo)')
end, false)

-- /htest — diagnostic: test which native approaches actually affect vehicle physics
RegisterCommand('htest', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        print('^1[htest]^0 Get in a vehicle first')
        return
    end

    local model = GetEntityModel(vehicle)
    local modelName = GetDisplayNameFromVehicleModel(model)
    print('^3[htest]^0 ===== DIAGNOSTIC on ' .. modelName .. ' (entity ' .. vehicle .. ') =====')

    -- Test 1: SetVehicleHandlingFloat
    local before1 = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveForce")
    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveForce", 0.01)
    local after1 = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fInitialDriveForce")
    print(string.format('^3[htest 1]^0 SetVehicleHandlingFloat fInitialDriveForce: %s -> 0.01 (readback: %s)', before1, after1))

    -- Test 2: SetEntityMaxSpeed (hard speed cap in m/s)
    SetEntityMaxSpeed(vehicle, 5.0)
    print('^3[htest 2]^0 SetEntityMaxSpeed -> 5.0 m/s (18 km/h) — try driving fast')

    -- Test 3: ModifyVehicleTopSpeed (percentage, 0.0 = normal)
    ModifyVehicleTopSpeed(vehicle, -0.9)
    print('^3[htest 3]^0 ModifyVehicleTopSpeed -> -0.9 (10% of normal)')

    -- Test 4: SetVehicleEnginePowerMultiplier
    SetVehicleEnginePowerMultiplier(vehicle, 0.01)
    print('^3[htest 4]^0 SetVehicleEnginePowerMultiplier -> 0.01 (1% power)')

    -- Test 5: SetVehicleHandlingFloat on mass
    local beforeMass = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass")
    SetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass", 50000.0)
    local afterMass = GetVehicleHandlingFloat(vehicle, "CHandlingData", "fMass")
    print(string.format('^3[htest 5]^0 SetVehicleHandlingFloat fMass: %s -> 50000 (readback: %s) — car should feel very heavy', beforeMass, afterMass))

    print('^3[htest]^0 ===== Now try driving. Report which effects you feel: =====')
    print('^3[htest]^0   - Speed capped at ~18 km/h? (test 2)')
    print('^3[htest]^0   - Very slow acceleration? (test 4)')
    print('^3[htest]^0   - Car feels super heavy? (test 5)')
    print('^3[htest]^0 Use /htest_reset to undo all tests')
end, false)

-- /htest_reset — undo diagnostics
RegisterCommand('htest_reset', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    SetEntityMaxSpeed(vehicle, 500.0)
    ModifyVehicleTopSpeed(vehicle, 0.0)
    SetVehicleEnginePowerMultiplier(vehicle, 1.0)
    pendingOverrides = {}
    print('^2[htest]^0 All test overrides cleared. Respawn car for full reset.')
end, false)

RegisterKeyMapping('handling', 'Handling Editor', 'keyboard', '')
