-- ============================================================
-- Benny's Garage - Tuning System (client)
-- ============================================================

local isInGarage = false
local garageVehicle = nil
local garageCam = nil
local garageModel = nil

-- Tracked state (reading these back from natives is unreliable)
local trackedNeonEnabled = false
local trackedNeonColor = { r = 0, g = 150, b = 255 }
local trackedWheelColor = 0
local trackedPaintType1 = 0
local trackedPaintType2 = 0

-- GoM BBC Showcase interior (streamed via cfx-gom-map-bbcshowcase resource)
local GARAGE_INTERIOR_COORDS = vector3(859.19, -2376.54, 30.35)
local GARAGE_POS = vector4(867.05, -2376.86, 30.35, 83.52)

-- Camera orbit state
local camAngleH = 0.0    -- horizontal angle (radians)
local camAngleV = 0.2    -- vertical angle (radians)
local camRadius = 5.5
local CAM_MIN_RADIUS = 2.5
local CAM_MAX_RADIUS = 9.0
local CAM_MIN_V = -0.1
local CAM_MAX_V = 0.8
local CAM_SENSITIVITY = 0.003
local CAM_ZOOM_SPEED = 0.5
local CAM_HEIGHT_OFFSET = 0.6

-- Mod slot definitions sent to NUI
local MOD_SLOTS = {
    { id = 'spoiler',     slot = 0,  label = 'Spoiler' },
    { id = 'frontBumper', slot = 1,  label = 'Front Bumper' },
    { id = 'rearBumper',  slot = 2,  label = 'Rear Bumper' },
    { id = 'sideSkirts',  slot = 3,  label = 'Side Skirts' },
    { id = 'hood',        slot = 7,  label = 'Hood' },
    { id = 'engine',      slot = 11, label = 'Engine' },
    { id = 'brakes',      slot = 12, label = 'Brakes' },
    { id = 'transmission',slot = 13, label = 'Transmission' },
    { id = 'suspension',  slot = 15, label = 'Suspension' },
}

local WINDOW_TINT_LABELS = {
    [0] = 'None', [1] = 'Pure Black', [2] = 'Dark Smoke',
    [3] = 'Light Smoke', [4] = 'Stock', [5] = 'Limo', [6] = 'Green',
}

-- Load allowed wheel types from JSON
local ALLOWED_WHEEL_TYPES = {}
local WHEEL_TYPE_LABELS = {}
local wheelTypesRaw = LoadResourceFile(GetCurrentResourceName(), 'data/wheel_types.json')
if wheelTypesRaw then
    local parsed = json.decode(wheelTypesRaw)
    for _, wt in ipairs(parsed) do
        WHEEL_TYPE_LABELS[wt.typeIndex] = wt.label
        ALLOWED_WHEEL_TYPES[#ALLOWED_WHEEL_TYPES + 1] = wt.typeIndex
    end
end

-- ========================
-- Enter garage
-- ========================

RegisterNetEvent('blacklist:enterGarage')
AddEventHandler('blacklist:enterGarage', function(model)
    if isInGarage then return end
    isInGarage = true
    garageModel = model

    -- Stop freeroam cleanup threads so they don't delete our garage vehicle
    TriggerEvent('blacklist:enableGhostMode', false)
    -- Move to private routing bucket so nobody can see us
    TriggerServerEvent('blacklist:enterGarageBucket')

    local ped = PlayerPedId()

    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Citizen.Wait(0) end

    -- Hide ped and place it at the garage so the engine streams interior/collision there
    SetEntityVisible(ped, false, false)
    SetEntityAlpha(ped, 0, false)
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, GARAGE_POS.x, GARAGE_POS.y, GARAGE_POS.z, false, false, false, true)

    -- Request vehicle model immediately so it loads in parallel with the interior
    local hash = GetHashKey(model)
    RequestModel(hash)

    RequestCollisionAtCoord(GARAGE_POS.x, GARAGE_POS.y, GARAGE_POS.z)

    -- MLO interior: auto-loaded by FiveM (this_is_a_map resource), just pin it
    NewLoadSceneStart(GARAGE_INTERIOR_COORDS.x, GARAGE_INTERIOR_COORDS.y, GARAGE_INTERIOR_COORDS.z,
                      GARAGE_INTERIOR_COORDS.x, GARAGE_INTERIOR_COORDS.y, GARAGE_INTERIOR_COORDS.z, 50.0, 0)
    local deadline = GetGameTimer() + 4000
    while GetGameTimer() < deadline do
        if IsNewLoadSceneLoaded() then break end
        Citizen.Wait(0)
    end
    NewLoadSceneStop()

    local interior = GetInteriorAtCoords(GARAGE_INTERIOR_COORDS.x, GARAGE_INTERIOR_COORDS.y, GARAGE_INTERIOR_COORDS.z)
    if IsValidInterior(interior) then
        if not IsInteriorReady(interior) then
            LoadInterior(interior)
            local waitDeadline = GetGameTimer() + 2000
            while not IsInteriorReady(interior) and GetGameTimer() < waitDeadline do
                Citizen.Wait(0)
            end
        end
        PinInteriorInMemory(interior)
    end

    -- Collision: request once more and do a short conditional wait
    RequestCollisionAtCoord(GARAGE_POS.x, GARAGE_POS.y, GARAGE_POS.z)
    local deadline = GetGameTimer() + 1000
    while GetGameTimer() < deadline do
        if HasCollisionLoadedAroundEntity(ped) then break end
        RequestCollisionAtCoord(GARAGE_POS.x, GARAGE_POS.y, GARAGE_POS.z)
        Citizen.Wait(0)
    end

    -- Wait for model (was loading in parallel with everything above)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(hash) do
        Citizen.Wait(0)
        if GetGameTimer() > timeout then
            hash = GetHashKey('sultan')
            RequestModel(hash)
            while not HasModelLoaded(hash) do Citizen.Wait(0) end
            break
        end
    end

    garageVehicle = CreateVehicle(hash, GARAGE_POS.x, GARAGE_POS.y, GARAGE_POS.z - 0.3, GARAGE_POS.w, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetVehicleDirtLevel(garageVehicle, 0.0)
    SetEntityInvincible(garageVehicle, true)
    SetVehicleOnGroundProperly(garageVehicle)
    SetEntityCoords(garageVehicle, GARAGE_POS.x, GARAGE_POS.y, GARAGE_POS.z - 0.3, false, false, false, false)
    SetEntityHeading(garageVehicle, GARAGE_POS.w)
    SetVehicleHandbrake(garageVehicle, true)
    SetVehicleDoorsLocked(garageVehicle, 2)
    SetVehicleLights(garageVehicle, 2)
    SetVehicleModKit(garageVehicle, 0)

    -- Create orbit camera
    camAngleH = math.rad(GARAGE_POS.w + 180.0)
    camAngleV = 0.2
    camRadius = 5.5

    garageCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    updateCameraPosition()
    SetCamActive(garageCam, true)
    RenderScriptCams(true, true, 300, true, true)

    ClearFocus()

    -- Request tuning data from server (fires while camera transition plays)
    TriggerServerEvent('blacklist:requestTuningData', model)

    Citizen.Wait(350)
    DoScreenFadeIn(300)
end)

-- ========================
-- Receive tuning data + open NUI
-- ========================

RegisterNetEvent('blacklist:receiveTuningData')
AddEventHandler('blacklist:receiveTuningData', function(tuning, savedTuning)
    if not isInGarage or not garageVehicle then return end

    -- Apply saved tuning to the vehicle first
    if savedTuning then
        applyFullTuning(garageVehicle, savedTuning)
    end

    -- Build mod counts for each slot
    local modData = {}
    for _, def in ipairs(MOD_SLOTS) do
        local count = GetNumVehicleMods(garageVehicle, def.slot)
        local current = GetVehicleMod(garageVehicle, def.slot)
        modData[#modData + 1] = {
            id = def.id,
            slot = def.slot,
            label = def.label,
            count = count,
            current = current,
        }
    end

    -- Wheel info (only allowed types)
    local wheelData = {}
    for _, typeIdx in ipairs(ALLOWED_WHEEL_TYPES) do
        SetVehicleWheelType(garageVehicle, typeIdx)
        local count = GetNumVehicleMods(garageVehicle, 23)
        wheelData[#wheelData + 1] = {
            typeIndex = typeIdx,
            label = WHEEL_TYPE_LABELS[typeIdx] or ('Type ' .. typeIdx),
            count = count,
        }
    end
    -- Restore current wheel type
    local curWheelType = (savedTuning and savedTuning.wheelType) or 0
    SetVehicleWheelType(garageVehicle, curWheelType)
    if savedTuning and savedTuning.wheelIndex then
        SetVehicleMod(garageVehicle, 23, savedTuning.wheelIndex, false)
    end

    -- Window tint
    local tintLabels = {}
    for i = 0, 6 do
        tintLabels[#tintLabels + 1] = { index = i, label = WINDOW_TINT_LABELS[i] or ('Tint ' .. i) }
    end

    -- Livery count
    local liveryCount = GetVehicleLiveryCount(garageVehicle)
    if liveryCount <= 0 then
        liveryCount = GetNumVehicleMods(garageVehicle, 48)
    end

    -- Detect available extras (0-14)
    local extrasData = {}
    for i = 0, 14 do
        if DoesExtraExist(garageVehicle, i) then
            extrasData[#extrasData + 1] = {
                id = i,
                enabled = IsVehicleExtraTurnedOn(garageVehicle, i),
            }
        end
    end

    -- Current colors
    local pr, pg, pb = GetVehicleCustomPrimaryColour(garageVehicle)
    local sr, sg, sb = GetVehicleCustomSecondaryColour(garageVehicle)

    -- Turbo state
    local hasTurbo = IsToggleModOn(garageVehicle, 18)

    -- Initialize tracked state from saved tuning (natives are unreliable right after apply)
    if savedTuning then
        trackedNeonEnabled = savedTuning.neon == true
        if savedTuning.neonColor then
            trackedNeonColor = { r = savedTuning.neonColor.r or 0, g = savedTuning.neonColor.g or 150, b = savedTuning.neonColor.b or 255 }
        end
        trackedWheelColor = savedTuning.wheelColor or 0
        trackedPaintType1 = savedTuning.paintType1 or 0
        trackedPaintType2 = savedTuning.paintType2 or 0
    else
        trackedNeonEnabled = false
        trackedNeonColor = { r = 0, g = 150, b = 255 }
        trackedWheelColor = 0
        trackedPaintType1 = 0
        trackedPaintType2 = 0
    end

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openTuning',
        model = garageModel,
        mods = modData,
        wheels = wheelData,
        tints = tintLabels,
        liveryCount = liveryCount,
        currentTuning = savedTuning or {},
        currentColors = {
            primary = { r = pr or 0, g = pg or 0, b = pb or 0 },
            secondary = { r = sr or 30, g = sg or 30, b = sb or 30 },
        },
        turbo = hasTurbo,
        neon = trackedNeonEnabled,
        neonColor = trackedNeonColor,
        currentWheelType = curWheelType,
        currentWheelIndex = GetVehicleMod(garageVehicle, 23),
        currentWindowTint = GetVehicleWindowTint(garageVehicle),
        currentLivery = GetVehicleLivery(garageVehicle) >= 0 and GetVehicleLivery(garageVehicle) or GetVehicleMod(garageVehicle, 48),
        currentWheelColor = trackedWheelColor,
        paintType1 = trackedPaintType1,
        paintType2 = trackedPaintType2,
        extras = extrasData,
    })
end)

-- ========================
-- Camera orbit logic
-- ========================

function updateCameraPosition()
    if not garageCam or not garageVehicle then return end

    local vehPos = GetEntityCoords(garageVehicle)
    local spawnPos = vector3(GARAGE_POS.x, GARAGE_POS.y, GARAGE_POS.z - 0.3)
    if #(vehPos - spawnPos) > 0.5 then
        SetEntityCoords(garageVehicle, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false, false)
        SetEntityHeading(garageVehicle, GARAGE_POS.w)
        vehPos = spawnPos
    end

    local center = vector3(vehPos.x, vehPos.y, vehPos.z + CAM_HEIGHT_OFFSET)

    local x = center.x + camRadius * math.cos(camAngleV) * math.cos(camAngleH)
    local y = center.y + camRadius * math.cos(camAngleV) * math.sin(camAngleH)
    local z = center.z + camRadius * math.sin(camAngleV)

    SetCamCoord(garageCam, x, y, z)
    PointCamAtCoord(garageCam, center.x, center.y, center.z)
end

-- Camera input comes from NUI (JS sends mouse deltas)
RegisterNUICallback('cameraOrbit', function(data, cb)
    if not isInGarage or not garageCam or not garageVehicle then cb({}) return end
    local dx = tonumber(data.dx) or 0
    local dy = tonumber(data.dy) or 0
    camAngleH = camAngleH - dx * 0.008
    camAngleV = camAngleV + dy * 0.008
    camAngleV = math.max(CAM_MIN_V, math.min(CAM_MAX_V, camAngleV))
    updateCameraPosition()
    cb({})
end)

RegisterNUICallback('cameraZoom', function(data, cb)
    if not isInGarage or not garageCam or not garageVehicle then cb({}) return end
    local delta = tonumber(data.delta) or 0
    if delta < 0 then
        camRadius = math.max(CAM_MIN_RADIUS, camRadius - CAM_ZOOM_SPEED)
    elseif delta > 0 then
        camRadius = math.min(CAM_MAX_RADIUS, camRadius + CAM_ZOOM_SPEED)
    end
    updateCameraPosition()
    cb({})
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if isInGarage then
            DisableAllControlActions(0)
        end
    end
end)

-- ========================
-- NUI Callbacks: real-time mod preview
-- ========================

RegisterNUICallback('applyMod', function(data, cb)
    if not garageVehicle then cb({}) return end
    local slot = tonumber(data.slot)
    local value = tonumber(data.value)
    if slot and value then
        if value < 0 then
            RemoveVehicleMod(garageVehicle, slot)
        else
            SetVehicleMod(garageVehicle, slot, value, false)
        end
    end
    cb({})
end)

RegisterNUICallback('applyWheelType', function(data, cb)
    if not garageVehicle then cb({}) return end
    local wtype = tonumber(data.wheelType) or 0
    SetVehicleWheelType(garageVehicle, wtype)
    -- Return new wheel count for this type
    local count = GetNumVehicleMods(garageVehicle, 23)
    cb({ count = count })
end)

RegisterNUICallback('applyWheelIndex', function(data, cb)
    if not garageVehicle then cb({}) return end
    local idx = tonumber(data.wheelIndex) or 0
    if idx < 0 then
        RemoveVehicleMod(garageVehicle, 23)
    else
        SetVehicleMod(garageVehicle, 23, idx, false)
    end
    cb({})
end)

RegisterNUICallback('applyColor', function(data, cb)
    if not garageVehicle then cb({}) return end
    local r = tonumber(data.r) or 0
    local g = tonumber(data.g) or 0
    local b = tonumber(data.b) or 0
    if data.target == 'primary' then
        SetVehicleModColor_1(garageVehicle, trackedPaintType1, 0, 0)
        SetVehicleCustomPrimaryColour(garageVehicle, r, g, b)
    elseif data.target == 'secondary' then
        SetVehicleModColor_2(garageVehicle, trackedPaintType2, 0)
        SetVehicleCustomSecondaryColour(garageVehicle, r, g, b)
    end
    cb({})
end)

RegisterNUICallback('applyPaintType', function(data, cb)
    if not garageVehicle then cb({}) return end
    local paintType = tonumber(data.paintType) or 0
    local target = data.target
    if target == 'primary' then
        trackedPaintType1 = paintType
        SetVehicleModColor_1(garageVehicle, paintType, 0, 0)
        local r, g, b = GetVehicleCustomPrimaryColour(garageVehicle)
        SetVehicleCustomPrimaryColour(garageVehicle, r, g, b)
    elseif target == 'secondary' then
        trackedPaintType2 = paintType
        SetVehicleModColor_2(garageVehicle, paintType, 0)
        local r, g, b = GetVehicleCustomSecondaryColour(garageVehicle)
        SetVehicleCustomSecondaryColour(garageVehicle, r, g, b)
    end
    cb({})
end)

RegisterNUICallback('applyWindowTint', function(data, cb)
    if not garageVehicle then cb({}) return end
    SetVehicleWindowTint(garageVehicle, tonumber(data.value) or 0)
    cb({})
end)

RegisterNUICallback('applyLivery', function(data, cb)
    if not garageVehicle then cb({}) return end
    local val = tonumber(data.value) or -1
    SetVehicleLivery(garageVehicle, val)
    SetVehicleMod(garageVehicle, 48, val, false)
    cb({})
end)

RegisterNUICallback('applyTurbo', function(data, cb)
    if not garageVehicle then cb({}) return end
    ToggleVehicleMod(garageVehicle, 18, data.enabled == true)
    cb({})
end)

RegisterNUICallback('applyNeon', function(data, cb)
    if not garageVehicle then cb({}) return end
    local enabled = data.enabled == true
    trackedNeonEnabled = enabled
    for i = 0, 3 do
        SetVehicleNeonLightEnabled(garageVehicle, i, enabled)
    end
    if enabled and data.color then
        trackedNeonColor = {
            r = tonumber(data.color.r) or 0,
            g = tonumber(data.color.g) or 150,
            b = tonumber(data.color.b) or 255,
        }
        SetVehicleNeonLightsColour(garageVehicle, trackedNeonColor.r, trackedNeonColor.g, trackedNeonColor.b)
    end
    cb({})
end)

RegisterNUICallback('applyWheelColor', function(data, cb)
    if not garageVehicle then cb({}) return end
    local colorIdx = tonumber(data.value) or 0
    trackedWheelColor = colorIdx
    local pearl, _ = GetVehicleExtraColours(garageVehicle)
    SetVehicleExtraColours(garageVehicle, pearl, colorIdx)
    cb({})
end)

RegisterNUICallback('applyNeonColor', function(data, cb)
    if not garageVehicle then cb({}) return end
    trackedNeonColor = {
        r = tonumber(data.r) or 0,
        g = tonumber(data.g) or 150,
        b = tonumber(data.b) or 255,
    }
    SetVehicleNeonLightsColour(garageVehicle, trackedNeonColor.r, trackedNeonColor.g, trackedNeonColor.b)
    cb({})
end)

RegisterNUICallback('applyExtra', function(data, cb)
    if not garageVehicle then cb({}) return end
    local extraId = tonumber(data.id)
    local enabled = data.enabled == true
    if extraId and DoesExtraExist(garageVehicle, extraId) then
        SetVehicleExtra(garageVehicle, extraId, not enabled)
    end
    cb({})
end)

-- ========================
-- Doors / Hood / Trunk
-- ========================

RegisterNUICallback('toggleDoor', function(data, cb)
    if not garageVehicle then cb({}) return end
    local doorIdx = tonumber(data.door)
    if data.open == true then
        SetVehicleDoorOpen(garageVehicle, doorIdx, false, false)
    else
        SetVehicleDoorShut(garageVehicle, doorIdx, false)
    end
    cb({})
end)

-- ========================
-- Save & Exit / Cancel
-- ========================

RegisterNUICallback('saveTuning', function(data, cb)
    if not isInGarage then cb({}) return end

    -- Collect full tuning state from vehicle
    local tuning = collectTuningFromVehicle()

    TriggerServerEvent('blacklist:saveTuning', garageModel, tuning)
    exitGarage()
    cb({})
end)

RegisterNUICallback('cancelTuning', function(data, cb)
    if not isInGarage then cb({}) return end
    exitGarage()
    cb({})
end)

function collectTuningFromVehicle()
    if not garageVehicle then return {} end
    local t = {}

    -- Colors
    local pr, pg, pb = GetVehicleCustomPrimaryColour(garageVehicle)
    local sr, sg, sb = GetVehicleCustomSecondaryColour(garageVehicle)
    t.color1 = { r = pr, g = pg, b = pb }
    t.color2 = { r = sr, g = sg, b = sb }
    t.paintType1 = trackedPaintType1
    t.paintType2 = trackedPaintType2

    -- Mod slots
    t.spoiler = GetVehicleMod(garageVehicle, 0)
    t.frontBumper = GetVehicleMod(garageVehicle, 1)
    t.rearBumper = GetVehicleMod(garageVehicle, 2)
    t.sideSkirts = GetVehicleMod(garageVehicle, 3)
    t.hood = GetVehicleMod(garageVehicle, 7)

    -- Mechanical
    t.engine = GetVehicleMod(garageVehicle, 11)
    t.brakes = GetVehicleMod(garageVehicle, 12)
    t.transmission = GetVehicleMod(garageVehicle, 13)
    t.suspension = GetVehicleMod(garageVehicle, 15)
    t.turbo = IsToggleModOn(garageVehicle, 18)

    -- Wheels
    t.wheelType = GetVehicleWheelType(garageVehicle)
    t.wheelIndex = GetVehicleMod(garageVehicle, 23)
    t.wheelColor = trackedWheelColor

    -- Livery (some cars use GetVehicleLivery, others use mod slot 48)
    local livNative = GetVehicleLivery(garageVehicle)
    local livMod    = GetVehicleMod(garageVehicle, 48)
    t.livery = (livNative >= 0) and livNative or livMod

    -- Window tint
    t.windowTint = GetVehicleWindowTint(garageVehicle)

    -- Neon (use tracked values -- GetVehicleNeonLightsColour can return wrong data)
    t.neon = trackedNeonEnabled
    if t.neon then
        t.neonColor = { r = trackedNeonColor.r, g = trackedNeonColor.g, b = trackedNeonColor.b }
    end

    -- Extras
    local extras = {}
    for i = 0, 14 do
        if DoesExtraExist(garageVehicle, i) then
            extras[tostring(i)] = IsVehicleExtraTurnedOn(garageVehicle, i)
        end
    end
    t.extras = extras

    return t
end

function exitGarage()
    DoScreenFadeOut(250)
    Citizen.Wait(300)

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeTuning' })

    if garageVehicle and DoesEntityExist(garageVehicle) then
        DeleteEntity(garageVehicle)
    end
    garageVehicle = nil
    garageModel = nil

    if garageCam then
        SetCamActive(garageCam, false)
        RenderScriptCams(false, true, 300, true, true)
        DestroyCam(garageCam, false)
        garageCam = nil
    end

    ClearFocus()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    FreezeEntityPosition(ped, false)

    isInGarage = false

    TriggerServerEvent('blacklist:leaveGarageBucket')

    Citizen.Wait(100)

    TriggerEvent('blacklist:openMenu')
    Citizen.Wait(300)
    DoScreenFadeIn(300)
end

-- ========================
-- Apply full tuning to a vehicle (used on initial load)
-- ========================

function applyFullTuning(vehicle, t)
    if not t or not vehicle then return end

    SetVehicleModKit(vehicle, 0)

    if t.paintType1 then
        SetVehicleModColor_1(vehicle, t.paintType1, 0, 0)
    end
    if t.paintType2 then
        SetVehicleModColor_2(vehicle, t.paintType2, 0)
    end
    if t.color1 then
        SetVehicleCustomPrimaryColour(vehicle, t.color1.r or 0, t.color1.g or 0, t.color1.b or 0)
    end
    if t.color2 then
        SetVehicleCustomSecondaryColour(vehicle, t.color2.r or 0, t.color2.g or 0, t.color2.b or 0)
    end

    local slots = { spoiler = 0, frontBumper = 1, rearBumper = 2, sideSkirts = 3, hood = 7,
                    engine = 11, brakes = 12, transmission = 13, suspension = 15 }
    for key, slot in pairs(slots) do
        if t[key] and t[key] >= 0 then
            SetVehicleMod(vehicle, slot, t[key], false)
        end
    end

    if t.wheelType then
        SetVehicleWheelType(vehicle, t.wheelType)
    end
    if t.wheelIndex and t.wheelIndex >= 0 then
        SetVehicleMod(vehicle, 23, t.wheelIndex, false)
    end
    if t.wheelColor then
        local pearl, _ = GetVehicleExtraColours(vehicle)
        SetVehicleExtraColours(vehicle, pearl, t.wheelColor)
    end

    if t.livery and t.livery >= 0 then
        SetVehicleLivery(vehicle, t.livery)
        SetVehicleMod(vehicle, 48, t.livery, false)
    end

    if t.windowTint then
        SetVehicleWindowTint(vehicle, t.windowTint)
    end

    ToggleVehicleMod(vehicle, 18, t.turbo == true)

    if t.neon then
        for i = 0, 3 do SetVehicleNeonLightEnabled(vehicle, i, true) end
        if t.neonColor then
            SetVehicleNeonLightsColour(vehicle, t.neonColor.r or 0, t.neonColor.g or 150, t.neonColor.b or 255)
        end
    end

    if t.extras then
        for idStr, enabled in pairs(t.extras) do
            local id = tonumber(idStr)
            if id and DoesExtraExist(vehicle, id) then
                SetVehicleExtra(vehicle, id, not enabled)
            end
        end
    end
end

-- Keep BBC Showcase interior pinned — re-pin every 10s if the game unloads it
Citizen.CreateThread(function()
    while true do
        local interior = GetInteriorAtCoords(GARAGE_INTERIOR_COORDS.x, GARAGE_INTERIOR_COORDS.y, GARAGE_INTERIOR_COORDS.z)
        if IsValidInterior(interior) then
            if not IsInteriorReady(interior) then
                LoadInterior(interior)
            end
            PinInteriorInMemory(interior)
        end
        Citizen.Wait(10000)
    end
end)

print('[Garage] ^2Client-side loaded^0')
