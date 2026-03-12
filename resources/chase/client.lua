-- ============================================================
-- Chase/Run game mode: client-side HUD, distance tracking, anti-cheat
-- ============================================================

local CC = {
    -- Distance
    FAR_DISTANCE          = 999.0,
    FAR_DISTANCE_OPP      = 99999,
    MAX_DISTANCE_CAP      = 400.0,

    -- Unit conversion
    MS_TO_MPH             = 2.23694,
    MS_TO_KMH             = 3.6,
    RAD_TO_DEG            = 57.2958,
    KMH_TO_MPH            = 0.621371,

    -- Collision / telemetry
    COLLISION_COOLDOWN_MS = 1500,
    PIT_REPORT_COOLDOWN   = 5000,
    RAM_REPORT_COOLDOWN   = 5000,
    JUMP_REPORT_COOLDOWN  = 15000,
    PLAYER_CONTACT_DIST   = 8.0,

    -- Ram detection (runner side)
    RAM_SPEED_MIN_MPH     = 30,
    RAM_ANGLE_THRESHOLD   = 60,
    RAM_DETECT_RADIUS     = 6.0,
    RAM_SPEED_RATIO       = 0.8,

    -- Post-match timeouts
    POST_MATCH_RANKED_MS  = 20000,
    POST_MATCH_NORMAL_MS  = 8000,

    -- Heli spawn
    HELI_SPAWN_HEIGHT     = 40.0,
    HELI_CLEAR_HEIGHT     = 30.0,

    -- Respawn
    RESPAWN_HEALTH        = 200,
    RESPAWN_WAIT_MS       = 5000,

    -- Airborne thresholds
    AIRBORNE_LONG_SEC     = 2.0,
    AIRBORNE_WARN_SEC     = 1.0,
    AIRBORNE_DQ_HEIGHT    = 10.0,

    -- Traffic density (normal chase mode)
    TRAFFIC_DENSITY       = 0.3,

    -- Prop protection
    PROP_SCAN_RADIUS      = 150.0,
    PROP_DELETE_RADIUS    = 3.0,

    -- Brake-check detection (ranked only)
    BRAKE_CHECK_DECEL     = 25,
    BRAKE_CHECK_DIST      = 35,
    BRAKE_CHECK_REPEAT_MS = 8000,
    BRAKE_CHECK_CONTEXT   = 3000,

    -- Follow-up analysis
    FOLLOW_UP_NO_TIME     = 700,
    FOLLOW_UP_HAD_TIME    = 1500,
    FOLLOW_UP_WINDOW      = 3000,

    -- Hill / terrain
    SLOPE_STEEP           = 25,
    SLOPE_HILL            = 15,
    SLOPE_MILD            = 5,
    HILL_GRACE_SEC        = 5.0,
    HILL_COUNTDOWN_SEC    = 10,

    -- Terrain logging
    TERRAIN_LOG_COOLDOWN  = 2000,

    -- Summary
    SUMMARY_INTERVAL_MS   = 10000,
}

local isInMatch = false
local isPostMatch = false
local myRole = nil -- 'chaser' or 'runner'
local matchTimer = 0
local matchStartTime = 0
local isFrozen = false
local airborneTimer = 0.0
local currentPoliceCode = nil
local isHeliPilot = false
local chaseTrafficEnabled = false
local matchMode = nil -- 'ranked' or 'normal'
local isSoloTest = false
local runnerServerId = nil
local chaseSirenState = 'off'
local soloDummyPed = 0
local soloDummyVehicle = 0
local ghostedChaserIds = {}
local heliModel = nil
local visionCircleBlip = nil

-- Spike strip + Gun state (Code Orange / Red)
local spikeStripEntity = nil
local hasPlacedSpike = false
local spikeStripCoords = nil
local chaserVehSaved = nil
local hasGunBeenGiven = false
local lastShotTime = 0
local runnerTiresBurst = {}

local SPIKE_ANIM_DICT = 'amb@world_human_gardener_plant@male@base'
local SPIKE_ANIM_NAME = 'base'
local SPIKE_MODEL = 'p_ld_stinger_s'
local SPIKE_DESPAWN_DIST = 100.0
local SPIKE_TIRE_RADIUS = 3.5
local GUN_HASH = GetHashKey('WEAPON_COMBATPISTOL')
local GUN_DQ_SPEED_MPH = 50.0
local GUN_DQ_WINDOW_MS = 1500

local WHEEL_TIRE_MAP = {
    { bone = 'wheel_lf', tire = 0 },
    { bone = 'wheel_rf', tire = 1 },
    { bone = 'wheel_lr', tire = 4 },
    { bone = 'wheel_rr', tire = 5 },
}

local function getRunnerVehicle()
    if not runnerServerId then return nil end
    local rPlayer = GetPlayerFromServerId(runnerServerId)
    if not rPlayer or rPlayer == -1 then return nil end
    local rPed = GetPlayerPed(rPlayer)
    if rPed == 0 then return nil end
    return GetVehiclePedIsIn(rPed, false)
end

local function cleanupSpikeStrip()
    if spikeStripEntity and DoesEntityExist(spikeStripEntity) then
        SetEntityAsMissionEntity(spikeStripEntity, true, true)
        DeleteObject(spikeStripEntity)
    end
    spikeStripEntity = nil
    hasPlacedSpike = false
    spikeStripCoords = nil
end

local function cleanupGun()
    local ped = PlayerPedId()
    RemoveWeaponFromPed(ped, GUN_HASH)
    hasGunBeenGiven = false
    lastShotTime = 0
    runnerTiresBurst = {}
    pcall(function() exports.base:SetAllowWeapons(false) end)
end

local function cleanupCodeFeatures()
    cleanupSpikeStrip()
    cleanupGun()
    chaserVehSaved = nil
end

-- Street light + traffic light models: indestructible in ranked
local STREET_LIGHT_HASHES = {}
for _, m in ipairs({
    'prop_streetlight_01', 'prop_streetlight_01b',
    'prop_streetlight_02', 'prop_streetlight_03',
    'prop_streetlight_03b', 'prop_streetlight_03c',
    'prop_streetlight_03d', 'prop_streetlight_03e',
    'prop_streetlight_04', 'prop_streetlight_05',
    'prop_streetlight_06', 'prop_streetlight_07a',
    'prop_streetlight_07b', 'prop_streetlight_08',
    'prop_streetlight_09', 'prop_streetlight_10',
    'prop_streetlight_11a', 'prop_streetlight_11b',
    'prop_streetlight_11c', 'prop_streetlight_12a',
    'prop_streetlight_12b', 'prop_streetlight_14a',
    'prop_streetlight_15a', 'prop_streetlight_16a',
    'prop_floodlight_01',
    'prop_traffic_01a', 'prop_traffic_01b', 'prop_traffic_01d',
}) do STREET_LIGHT_HASHES[GetHashKey(m)] = true end

local HYDRANT_HASHES = {}
for _, m in ipairs({
    'prop_fire_hydrant_1', 'prop_fire_hydrant_2',
    'prop_fire_hydrant_3', 'prop_fire_hydrant_4',
}) do HYDRANT_HASHES[GetHashKey(m)] = true end

-- ========================
-- Shared helpers
-- ========================

local function forEachOtherPlayer(callback)
    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local otherPed = GetPlayerPed(playerId)
            if otherPed ~= 0 then
                callback(playerId, otherPed)
            end
        end
    end
end

local function forceFullVisibility()
    local myPed = PlayerPedId()
    local myVehicle = GetVehiclePedIsIn(myPed, false)

    ResetEntityAlpha(myPed)
    SetEntityCollision(myPed, true, true)
    SetEntityAlpha(myPed, 255, false)
    if myVehicle ~= 0 then
        ResetEntityAlpha(myVehicle)
        SetEntityCollision(myVehicle, true, true)
        SetEntityAlpha(myVehicle, 255, false)
    end

    forEachOtherPlayer(function(_, otherPed)
        ResetEntityAlpha(otherPed)
        SetEntityCollision(otherPed, true, true)
        SetEntityAlpha(otherPed, 255, false)

        local otherVehicle = GetVehiclePedIsIn(otherPed, false)
        if otherVehicle ~= 0 then
            ResetEntityAlpha(otherVehicle)
            SetEntityCollision(otherVehicle, true, true)
            SetEntityAlpha(otherVehicle, 255, false)
        end
    end)
end

-- ========================
-- Freeze control
-- ========================

RegisterNetEvent('blacklist:chaseFreeze')
AddEventHandler('blacklist:chaseFreeze', function(freeze)
    isFrozen = freeze
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        FreezeEntityPosition(vehicle, freeze)
    end
    FreezeEntityPosition(ped, freeze)
end)

-- ========================
-- Countdown
-- ========================

RegisterNetEvent('blacklist:chaseCountdown')
AddEventHandler('blacklist:chaseCountdown', function(seconds)
    isInMatch = true
    isPostMatch = false
    exports.base:SetPlayerState('in_match')
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'countdown', seconds = seconds })

    -- Kill the freeroam ghost threads (root cause of blinking ghost)
    TriggerEvent('blacklist:enableGhostMode', false)

    forceFullVisibility()
end)

-- ========================
-- HUD updates from server
-- ========================

RegisterNetEvent('blacklist:chaseHUD')
AddEventHandler('blacklist:chaseHUD', function(data)
    if data.action == 'headstart' then
        myRole = data.role
        SendNUIMessage({
            action = 'headstart',
            role = data.role,
            duration = data.duration,
        })

    elseif data.action == 'start' then
        myRole = data.role
        matchMode = data.mode
        isSoloTest = data.solo or false
        matchTimer = data.duration
        matchStartTime = GetGameTimer()
        currentPoliceCode = data.policeCode
        isHeliPilot = data.isHeliPilot or false
        runnerServerId = data.runnerServerId
        SendNUIMessage({
            action = 'start',
            role = data.role,
            duration = data.duration,
            policeCode = data.policeCode,
            isHeliPilot = data.isHeliPilot,
            solo = isSoloTest,
        })

    elseif data.action == 'codeChange' then
        currentPoliceCode = data.policeCode
        SendNUIMessage({
            action = 'codeChange',
            policeCode = data.policeCode,
            pitLimit = data.pitLimit,
            reason = data.reason,
        })

        if data.policeCode == 'red' and myRole == 'chaser' and not hasGunBeenGiven then
            hasGunBeenGiven = true
            exports.base:SetAllowWeapons(true)
            Citizen.SetTimeout(500, function()
                local ped = PlayerPedId()
                GiveWeaponToPed(ped, GUN_HASH, 2, false, true)
                SetPedAmmo(ped, GUN_HASH, 2)
                local rVeh = getRunnerVehicle()
                if rVeh and rVeh ~= 0 then
                    for _, w in ipairs(WHEEL_TIRE_MAP) do
                        runnerTiresBurst[w.tire] = IsVehicleTyreBurst(rVeh, w.tire, false)
                    end
                end
            end)
        end

    elseif data.action == 'distance' then
        SendNUIMessage({
            action = 'distance',
            distance = math.floor(data.distance),
            catchProgress = data.catchProgress,
            escapeProgress = data.escapeProgress,
            policeCode = data.policeCode,
        })

    elseif data.action == 'warning' then
        SendNUIMessage({
            action = 'warning',
            message = data.message,
        })

    elseif data.action == 'end' then
        isInMatch = false
        isPostMatch = true
        myRole = nil
        cleanupCodeFeatures()
        SendNUIMessage({
            action = 'matchEnd',
            won = data.won,
            winnerRole = data.winnerRole,
            reason = data.reason,
            duration = data.duration,
            isRanked = data.isRanked,
        })
        if data.isRanked then
            SetNuiFocus(true, true)
        end
    end
end)

-- ========================
-- MMR result from ranked system
-- ========================

RegisterNetEvent('blacklist:matchResult')
AddEventHandler('blacklist:matchResult', function(data)
    SendNUIMessage({
        action = 'mmrUpdate',
        mmrChange = data.mmrChange,
        newMMR = data.newMMR,
        newTier = data.newTier,
        oldTier = data.oldTier,
        promoted = data.promoted,
        demoted = data.demoted,
        isPlacement = data.isPlacement,
        placementMatch = data.placementMatch,
        placementTotal = data.placementTotal,
    })
end)

-- ========================
-- Rematch
-- ========================

RegisterNUICallback('requestRematch', function(data, cb)
    TriggerServerEvent('blacklist:requestRematch')
    cb({})
end)

RegisterNetEvent('blacklist:rematchStatus')
AddEventHandler('blacklist:rematchStatus', function(status)
    SendNUIMessage({ action = 'rematchStatus', status = status })
    if status == 'accepted' then
        isPostMatch = false
        SetNuiFocus(false, false)
    end
end)

-- ========================
-- Forfeit / quit confirmation prompt
-- ========================

local forfeitPromptActive = false

AddEventHandler('blacklist:showForfeitPrompt', function()
    if not isInMatch or forfeitPromptActive then return end
    forfeitPromptActive = true

    if matchMode == 'ranked' then
        SendNUIMessage({ action = 'forfeitPrompt', title = 'FORFEIT?', message = 'You will lose MMR.', confirm = 'Forfeit', cancel = 'Cancel' })
    else
        SendNUIMessage({ action = 'forfeitPrompt', title = 'QUIT?', message = 'You will leave this chase.', confirm = 'Quit', cancel = 'Cancel' })
    end
    SetNuiFocus(true, true)
end)

RegisterNUICallback('forfeitConfirm', function(_, cb)
    forfeitPromptActive = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideForfeitPrompt' })
    TriggerServerEvent('blacklist:forfeitMatch')
    cb('ok')
end)

RegisterNUICallback('forfeitCancel', function(_, cb)
    forfeitPromptActive = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideForfeitPrompt' })
    cb('ok')
end)

-- ========================
-- Chase HUD cleanup on return to menu
-- ========================

RegisterNetEvent('blacklist:returnToMenu')
AddEventHandler('blacklist:returnToMenu', function()
    isInMatch = false
    isPostMatch = false
    myRole = nil
    currentPoliceCode = nil
    isHeliPilot = false
    heliModel = nil
    forfeitPromptActive = false
    chaseSirenState = 'off'
    chaseTrafficEnabled = false
    matchMode = nil
    isSoloTest = false
    runnerServerId = nil
    ghostedChaserIds = {}
    cleanupCodeFeatures()
    if visionCircleBlip and DoesBlipExist(visionCircleBlip) then
        RemoveBlip(visionCircleBlip)
    end
    visionCircleBlip = nil
    cleanupPdBlips()
    SendNUIMessage({ action = 'hideAll' })
end)

-- ========================
-- Vision circle (last known runner position) for chasers
-- ========================

RegisterNetEvent('blacklist:visionCircle')
AddEventHandler('blacklist:visionCircle', function(x, y, z)
    if visionCircleBlip and DoesBlipExist(visionCircleBlip) then
        RemoveBlip(visionCircleBlip)
    end
    visionCircleBlip = AddBlipForRadius(x, y, z, 200.0)
    SetBlipColour(visionCircleBlip, 1)
    SetBlipAlpha(visionCircleBlip, 100)
    SetBlipRotation(visionCircleBlip, 0)
end)

RegisterNetEvent('blacklist:clearVisionCircle')
AddEventHandler('blacklist:clearVisionCircle', function()
    if visionCircleBlip and DoesBlipExist(visionCircleBlip) then
        RemoveBlip(visionCircleBlip)
    end
    visionCircleBlip = nil
end)

-- ========================
-- Distance tracking (chaser only, NO blip)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)

        if isInMatch and myRole == 'chaser' then
            local myPed = PlayerPedId()
            local myCoords = GetEntityCoords(myPed)

            local closestDist = CC.FAR_DISTANCE
            if runnerServerId then
                local runnerPlayer = GetPlayerFromServerId(runnerServerId)
                if runnerPlayer and runnerPlayer ~= -1 then
                    local runnerPed = GetPlayerPed(runnerPlayer)
                    if runnerPed ~= 0 and DoesEntityExist(runnerPed) then
                        closestDist = #(myCoords - GetEntityCoords(runnerPed))
                    end
                end
            end

            if closestDist >= CC.FAR_DISTANCE and soloDummyPed ~= 0 and DoesEntityExist(soloDummyPed) then
                closestDist = #(myCoords - GetEntityCoords(soloDummyPed))
            end

            local myVehicle = GetVehiclePedIsIn(myPed, false)
            local mySpeed = myVehicle ~= 0 and GetEntitySpeed(myVehicle) or 0.0

            TriggerServerEvent('blacklist:reportDistance', closestDist, math.min(closestDist, CC.MAX_DISTANCE_CAP), mySpeed)
        end
    end
end)

-- ========================
-- Timer display update
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        if isInMatch and matchStartTime > 0 then
            local elapsed = (GetGameTimer() - matchStartTime) / 1000
            local remaining = math.max(0, matchTimer - elapsed)
            SendNUIMessage({
                action = 'timer',
                remaining = math.floor(remaining),
            })
        end
    end
end)

-- ========================
-- PD blips: show other chasers on minimap (normal chase mode)
-- ========================

local pdBlips = {}

local function cleanupPdBlips()
    for _, blip in pairs(pdBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    pdBlips = {}
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if isInMatch and myRole == 'chaser' and matchMode == 'normal' then
            for _, playerId in ipairs(GetActivePlayers()) do
                if playerId ~= PlayerId() then
                    local otherPed = GetPlayerPed(playerId)
                    if otherPed ~= 0 then
                        local serverId = GetPlayerServerId(playerId)
                        if serverId ~= runnerServerId then
                            if not pdBlips[playerId] or not DoesBlipExist(pdBlips[playerId]) then
                                local blip = AddBlipForEntity(otherPed)
                                SetBlipSprite(blip, 1)
                                SetBlipColour(blip, 3)
                                SetBlipScale(blip, 1.2)
                                SetBlipAsShortRange(blip, false)
                                BeginTextCommandSetBlipName('STRING')
                                AddTextComponentSubstringPlayerName('PD')
                                EndTextCommandSetBlipName(blip)
                                pdBlips[playerId] = blip
                            end
                        end
                    end
                end
            end

            for pid, blip in pairs(pdBlips) do
                local otherPed = GetPlayerPed(pid)
                if otherPed == 0 or not DoesEntityExist(otherPed) then
                    if DoesBlipExist(blip) then RemoveBlip(blip) end
                    pdBlips[pid] = nil
                end
            end
        elseif not isInMatch then
            cleanupPdBlips()
        end
    end
end)

-- ========================
-- Traffic suppression + vehicle exit block + ghost nuke
-- Runs every frame during match and post-match results screen
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if isInMatch or isPostMatch then
            -- Pedestrians: always zero
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)

            if chaseTrafficEnabled then
                SetVehicleDensityMultiplierThisFrame(CC.TRAFFIC_DENSITY)
                SetRandomVehicleDensityMultiplierThisFrame(CC.TRAFFIC_DENSITY)
                SetParkedVehicleDensityMultiplierThisFrame(CC.TRAFFIC_DENSITY)
            else
                SetVehicleDensityMultiplierThisFrame(0.0)
                SetRandomVehicleDensityMultiplierThisFrame(0.0)
                SetParkedVehicleDensityMultiplierThisFrame(0.0)
            end

            SetGarbageTrucks(false)
            SetRandomBoats(false)
            SetRandomTrains(false)

            for i = 1, 15 do
                EnableDispatchService(i, false)
            end

            local canExitVeh = myRole == 'chaser' and (currentPoliceCode == 'orange' or currentPoliceCode == 'red')
            if not canExitVeh then
                DisableControlAction(0, 75, true)  -- F (exit vehicle)
                DisableControlAction(0, 23, true)  -- F (enter vehicle)
            end

            forceFullVisibility()
        end
    end
end)

-- ========================
-- Ghosted chaser: disable collision for PD trolls
-- ========================

RegisterNetEvent('blacklist:ghostChaser')
AddEventHandler('blacklist:ghostChaser', function(chaserServerId)
    ghostedChaserIds[chaserServerId] = true
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if isInMatch and next(ghostedChaserIds) then
            local myPed = PlayerPedId()
            local myVehicle = GetVehiclePedIsIn(myPed, false)
            for _, playerId in ipairs(GetActivePlayers()) do
                local sId = GetPlayerServerId(playerId)
                if ghostedChaserIds[sId] then
                    local otherPed = GetPlayerPed(playerId)
                    if otherPed ~= 0 then
                        local otherVeh = GetVehiclePedIsIn(otherPed, false)
                        SetEntityNoCollisionEntity(myPed, otherPed, true)
                        if otherVeh ~= 0 then
                            SetEntityNoCollisionEntity(myPed, otherVeh, true)
                            SetEntityAlpha(otherVeh, 150, false)
                        end
                        if myVehicle ~= 0 then
                            SetEntityNoCollisionEntity(myVehicle, otherPed, true)
                            if otherVeh ~= 0 then
                                SetEntityNoCollisionEntity(myVehicle, otherVeh, true)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ========================
-- Police siren controls for chasers (Q = Code 2 lights only, Alt = Code 3 lights+sound)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if isInMatch and myRole == 'chaser' then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh ~= 0 then
                DisableControlAction(0, 44, true)
                DisableControlAction(0, 19, true)
                DisableControlAction(0, 86, true)

                if IsDisabledControlJustPressed(0, 44) then
                    if chaseSirenState == 'code2' then
                        SetVehicleSiren(veh, false)
                        chaseSirenState = 'off'
                    else
                        SetVehicleSiren(veh, true)
                        SetVehicleHasMutedSirens(veh, true)
                        chaseSirenState = 'code2'
                    end
                end

                if IsDisabledControlJustPressed(0, 19) then
                    if chaseSirenState == 'code3' then
                        SetVehicleSiren(veh, false)
                        chaseSirenState = 'off'
                    else
                        SetVehicleSiren(veh, true)
                        SetVehicleHasMutedSirens(veh, false)
                        chaseSirenState = 'code3'
                    end
                end

                if chaseSirenState == 'code2' then
                    SetVehicleHasMutedSirens(veh, true)
                end
            else
                chaseSirenState = 'off'
            end
        end
    end
end)

-- ========================
-- Custom siren traffic reaction (normal chase mode)
-- NPCs gradually slow to a stop only when chaser has sirens active
-- ========================

Citizen.CreateThread(function()
    local slowingVehs = {}
    while true do
        Citizen.Wait(1000)

        if not isInMatch or not chaseTrafficEnabled or myRole ~= 'chaser' or chaseSirenState == 'off' then
            if not isInMatch then slowingVehs = {} end
            goto continue
        end

        local myPed = PlayerPedId()
        local myCoords = GetEntityCoords(myPed)

        for veh, data in pairs(slowingVehs) do
            if not DoesEntityExist(veh) or #(myCoords - GetEntityCoords(veh)) > 120.0 then
                slowingVehs[veh] = nil
            else
                data.targetSpeed = math.max(0, data.targetSpeed - 5.0)
                SetVehicleMaxSpeed(veh, data.targetSpeed)
            end
        end

        local vHandle, veh = FindFirstVehicle()
        local success = true
        while success do
            if DoesEntityExist(veh) and not slowingVehs[veh] then
                local driver = GetPedInVehicleSeat(veh, -1)
                if driver ~= 0 and not IsPedAPlayer(driver) then
                    local vehCoords = GetEntityCoords(veh)
                    local dist = #(myCoords - vehCoords)
                    if dist < 60.0 and dist > 5.0 then
                        local currentSpeed = GetEntitySpeed(veh)
                        slowingVehs[veh] = { targetSpeed = currentSpeed, driver = driver }
                        SetBlockingOfNonTemporaryEvents(driver, true)
                        SetDriverAbility(driver, 1.0)
                        SetDriverAggressiveness(driver, 0.0)
                        SetVehicleMaxSpeed(veh, currentSpeed)
                    end
                end
            end
            success, veh = FindNextVehicle(vHandle)
        end
        EndFindVehicle(vHandle)

        ::continue::
    end
end)

-- ========================
-- NPC ped cleanup (always delete non-player peds)
-- NPC vehicles: only delete in ranked (no traffic), keep alive in normal (30% traffic)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(3000)

        if isInMatch or isPostMatch then
            local playerPed = PlayerPedId()

            local handle, ped = FindFirstPed()
            local success = true
            while success do
                if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    local pedVeh = GetVehiclePedIsIn(ped, false)
                    if not chaseTrafficEnabled or pedVeh == 0 then
                        DeleteEntity(ped)
                    end
                end
                success, ped = FindNextPed(handle)
            end
            EndFindPed(handle)

            if not chaseTrafficEnabled then
                local myVeh = GetVehiclePedIsIn(playerPed, false)
                local vHandle, veh = FindFirstVehicle()
                success = true
                while success do
                    if veh ~= myVeh and veh ~= (chaserVehSaved or 0) and DoesEntityExist(veh) then
                        local driver = GetPedInVehicleSeat(veh, -1)
                        if driver == 0 or not IsPedAPlayer(driver) then
                            DeleteEntity(veh)
                        end
                    end
                    success, veh = FindNextVehicle(vHandle)
                end
                EndFindVehicle(vHandle)
            end
        end
    end
end)

-- ========================
-- Car pick phase
-- ========================

RegisterNetEvent('blacklist:carPick')
AddEventHandler('blacklist:carPick', function(data)
    SendNUIMessage({
        action = 'carPick',
        role = data.role,
        cars = data.cars,
        timeout = data.timeout,
    })
    SetNuiFocus(true, true)
end)

RegisterNUICallback('carPick', function(data, cb)
    TriggerServerEvent('blacklist:carPickResponse', data.model)
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNetEvent('blacklist:carPickDone')
AddEventHandler('blacklist:carPickDone', function()
    SendNUIMessage({ action = 'carPickDone' })
    SetNuiFocus(false, false)
end)

-- ========================
-- Helicopter vote
-- ========================

RegisterNetEvent('blacklist:heliVote')
AddEventHandler('blacklist:heliVote', function(timeout)
    SendNUIMessage({ action = 'heliVote', timeout = timeout })
    SetNuiFocus(true, true)
end)

RegisterNUICallback('heliVote', function(data, cb)
    TriggerServerEvent('blacklist:heliVoteResponse', data.vote == true)
    SetNuiFocus(false, false)
    cb({})
end)

-- ========================
-- Traffic mode toggle (normal chase only)
-- ========================

RegisterNetEvent('blacklist:chaseTrafficMode')
AddEventHandler('blacklist:chaseTrafficMode', function(enabled)
    chaseTrafficEnabled = enabled
end)

-- ========================
-- Ranked prop protection: street lights indestructible, other props vanish on collision
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(200)
        if not isInMatch or matchMode ~= 'ranked' then goto continue end

        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local playerCoords = GetEntityCoords(ped)

        local handle, obj = FindFirstObject()
        local success = true
        while success do
            if DoesEntityExist(obj) and not IsEntityAPed(obj) and not IsEntityAVehicle(obj) then
                local objCoords = GetEntityCoords(obj)
                local dist = #(playerCoords - objCoords)

                if dist < CC.PROP_SCAN_RADIUS then
                    local modelHash = GetEntityModel(obj)

                    if STREET_LIGHT_HASHES[modelHash] then
                        SetEntityInvincible(obj, true)
                        SetDisableFragDamage(obj, true)
                        FreezeEntityPosition(obj, true)
                    elseif HYDRANT_HASHES[modelHash] and GetEntityHealth(obj) <= 0 then
                        SetEntityAsMissionEntity(obj, true, true)
                        DeleteObject(obj)
                    elseif dist < CC.PROP_DELETE_RADIUS and vehicle ~= 0 and HasEntityCollidedWithAnything(obj) then
                        SetEntityAsMissionEntity(obj, true, true)
                        DeleteObject(obj)
                    end
                end
            end
            success, obj = FindNextObject(handle)
        end
        EndFindObject(handle)

        ::continue::
    end
end)

-- ========================
-- Helicopter spawn (for heli pilot chaser)
-- ========================

RegisterNetEvent('blacklist:spawnHelicopter')
AddEventHandler('blacklist:spawnHelicopter', function(x, y, z, heading, model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Citizen.Wait(100)
    end

    local spawnZ = z + CC.HELI_SPAWN_HEIGHT
    local found, groundZ = GetGroundZFor_3dCoord(x, y, spawnZ + 50.0, false)
    if found and groundZ + CC.HELI_CLEAR_HEIGHT > spawnZ then
        spawnZ = groundZ + CC.HELI_CLEAR_HEIGHT
    end

    local heli = CreateVehicle(hash, x, y, spawnZ, heading, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetVehicleLivery(heli, 0)

    local ped = PlayerPedId()
    TaskWarpPedIntoVehicle(ped, heli, -1)
    SetVehicleEngineOn(heli, true, true, false)
    FreezeEntityPosition(heli, true)

    isHeliPilot = true
    heliModel = hash
    TriggerServerEvent('blacklist:spawnReady')
end)

-- ========================
-- Runner speed reporting (for boxing detection)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if isInMatch and myRole == 'runner' then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 then
                local speed = GetEntitySpeed(vehicle)
                TriggerServerEvent('blacklist:reportRunnerSpeed', speed)
            end
        end
    end
end)

-- ========================
-- Runner death detection
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)
        if isInMatch and myRole == 'runner' then
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                TriggerServerEvent('blacklist:reportViolation', 'runner_died')
                isInMatch = false
            end
        end
    end
end)

-- ========================
-- PD chaser death: respawn after 5s at same position with same vehicle
-- ========================

Citizen.CreateThread(function()
    local isRespawning = false
    while true do
        Citizen.Wait(500)
        if isInMatch and myRole == 'chaser' and not isRespawning then
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                isRespawning = true
                local veh = GetVehiclePedIsIn(ped, true)
                local coords = GetEntityCoords(veh ~= 0 and veh or ped)
                local heading = GetEntityHeading(veh ~= 0 and veh or ped)
                local model = isHeliPilot and heliModel or (veh ~= 0 and GetEntityModel(veh) or nil)

                Citizen.Wait(5000)

                if not isInMatch then
                    isRespawning = false
                    goto continue
                end

                local spawnZ = coords.z
                if isHeliPilot then
                    spawnZ = coords.z + CC.HELI_SPAWN_HEIGHT
                end

                NetworkResurrectLocalPlayer(coords.x, coords.y, spawnZ, heading, true, false)
                local newPed = PlayerPedId()
                ClearPedBloodDamage(newPed)
                SetEntityHealth(newPed, CC.RESPAWN_HEALTH)

                if veh ~= 0 and DoesEntityExist(veh) then
                    SetEntityAsMissionEntity(veh, true, true)
                    DeleteVehicle(veh)
                end

                if model then
                    RequestModel(model)
                    local timeout = 50
                    while not HasModelLoaded(model) and timeout > 0 do
                        Citizen.Wait(100)
                        timeout = timeout - 1
                    end

                    if HasModelLoaded(model) then
                        local newVeh = CreateVehicle(model, coords.x, coords.y, spawnZ, heading, true, false)
                        SetPedIntoVehicle(newPed, newVeh, -1)
                        SetVehicleEngineOn(newVeh, true, true, false)
                        if isHeliPilot then
                            SetVehicleLivery(newVeh, 0)
                            FreezeEntityPosition(newVeh, true)
                            Citizen.Wait(1000)
                            FreezeEntityPosition(newVeh, false)
                        end
                        SetModelAsNoLongerNeeded(model)
                    end
                end

                isRespawning = false
                ::continue::
            end
        end
    end
end)

-- ========================
-- Spike strip: preserve chaser vehicle when on foot (Code Orange+)
-- ========================

Citizen.CreateThread(function()
    local lastVeh = 0
    while true do
        Citizen.Wait(300)
        if isInMatch and myRole == 'chaser' and (currentPoliceCode == 'orange' or currentPoliceCode == 'red') then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                lastVeh = veh
                chaserVehSaved = veh
            elseif lastVeh ~= 0 then
                if chaserVehSaved and DoesEntityExist(chaserVehSaved) then
                    SetEntityAsMissionEntity(chaserVehSaved, true, true)
                end
                lastVeh = 0
            end
        else
            lastVeh = 0
        end
    end
end)

-- ========================
-- Spike strip placement (G key on foot, Code Orange+)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if isInMatch and myRole == 'chaser' and not hasPlacedSpike
            and (currentPoliceCode == 'orange' or currentPoliceCode == 'red') then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)

            if veh == 0 and not IsEntityDead(ped) then
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_DETONATE~ to place spike strip')
                EndTextCommandDisplayHelp(0, false, true, -1)

                if IsControlJustPressed(0, 47) then
                    hasPlacedSpike = true

                    RequestAnimDict(SPIKE_ANIM_DICT)
                    local dl = GetGameTimer() + 5000
                    while not HasAnimDictLoaded(SPIKE_ANIM_DICT) and GetGameTimer() < dl do Citizen.Wait(10) end

                    FreezeEntityPosition(ped, true)
                    TaskPlayAnim(ped, SPIKE_ANIM_DICT, SPIKE_ANIM_NAME, 8.0, -8.0, 2000, 1, 0, false, false, false)
                    Citizen.Wait(2000)
                    FreezeEntityPosition(ped, false)
                    ClearPedTasks(ped)

                    if not isInMatch then goto skipSpawn end

                    local coords = GetEntityCoords(ped)
                    local heading = GetEntityHeading(ped)

                    local spikeHash = GetHashKey(SPIKE_MODEL)
                    RequestModel(spikeHash)
                    dl = GetGameTimer() + 5000
                    while not HasModelLoaded(spikeHash) and GetGameTimer() < dl do Citizen.Wait(10) end

                    if HasModelLoaded(spikeHash) then
                        local groundZ = coords.z
                        local found, gz = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
                        if found then groundZ = gz end

                        spikeStripEntity = CreateObject(spikeHash, coords.x, coords.y, groundZ, true, true, false)
                        SetEntityHeading(spikeStripEntity, heading)
                        FreezeEntityPosition(spikeStripEntity, true)
                        SetModelAsNoLongerNeeded(spikeHash)
                        spikeStripCoords = GetEntityCoords(spikeStripEntity)
                    end

                    ::skipSpawn::
                end
            end
        end
    end
end)

-- ========================
-- Spike strip tire burst detection (per-wheel)
-- Chaser detects proximity, server relays burst to runner's client
-- ========================

Citizen.CreateThread(function()
    local burstLog = {}
    while true do
        Citizen.Wait(100)
        if isInMatch and spikeStripEntity and DoesEntityExist(spikeStripEntity) and spikeStripCoords then
            local rVeh = getRunnerVehicle()
            if rVeh and rVeh ~= 0 and DoesEntityExist(rVeh) then
                local vCoords = GetEntityCoords(rVeh)
                if #(vCoords - spikeStripCoords) < 12.0 then
                    for _, w in ipairs(WHEEL_TIRE_MAP) do
                        local bIdx = GetEntityBoneIndexByName(rVeh, w.bone)
                        if bIdx ~= -1 then
                            local wPos = GetWorldPositionOfEntityBone(rVeh, bIdx)
                            local key = w.tire
                            if #(wPos - spikeStripCoords) < SPIKE_TIRE_RADIUS
                                and not burstLog[key]
                                and not IsVehicleTyreBurst(rVeh, w.tire, false) then
                                burstLog[key] = true
                                local netId = NetworkGetNetworkIdFromEntity(rVeh)
                                TriggerServerEvent('blacklist:spikeTireBurst', netId, w.tire)
                            end
                        end
                    end
                end
            end
        else
            burstLog = {}
        end
    end
end)

-- Runner receives tire burst from server (spike strip hit)
RegisterNetEvent('blacklist:applyTireBurst')
AddEventHandler('blacklist:applyTireBurst', function(netId, tireIndex)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        SetVehicleTyreBurst(veh, tireIndex, true, 1000.0)
    end
end)

-- ========================
-- Spike strip auto-despawn at 100 m
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)
        if isInMatch and spikeStripEntity and DoesEntityExist(spikeStripEntity) and spikeStripCoords then
            local myCoords = GetEntityCoords(PlayerPedId())
            if #(myCoords - spikeStripCoords) > SPIKE_DESPAWN_DIST then
                cleanupSpikeStrip()
            end
        end
    end
end)

-- ========================
-- Gun ammo cap + DQ monitoring (Code Red)
-- ========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)
        if isInMatch and myRole == 'chaser' and hasGunBeenGiven then
            local ped = PlayerPedId()

            if GetAmmoInPedWeapon(ped, GUN_HASH) > 2 then
                SetPedAmmo(ped, GUN_HASH, 2)
            end

            if IsPedShooting(ped) then
                lastShotTime = GetGameTimer()
            end

            local rVeh = getRunnerVehicle()
            if rVeh and rVeh ~= 0 then
                if lastShotTime > 0 and (GetGameTimer() - lastShotTime) < GUN_DQ_WINDOW_MS then
                    local rSpeedMph = GetEntitySpeed(rVeh) * CC.MS_TO_MPH
                    for _, w in ipairs(WHEEL_TIRE_MAP) do
                        local isBurst = IsVehicleTyreBurst(rVeh, w.tire, false)
                        if isBurst and not runnerTiresBurst[w.tire] then
                            if rSpeedMph > GUN_DQ_SPEED_MPH then
                                TriggerServerEvent('blacklist:reportViolation', 'chaser_illegal_shot', rSpeedMph)
                                lastShotTime = 0
                                break
                            end
                        end
                    end
                end

                for _, w in ipairs(WHEEL_TIRE_MAP) do
                    runnerTiresBurst[w.tire] = IsVehicleTyreBurst(rVeh, w.tire, false)
                end
            end
        end
    end
end)

-- ========================
-- Runner ram PD detection (collision with chaser vehicles)
-- ========================

Citizen.CreateThread(function()
    local lastRamReport = 0
    while true do
        Citizen.Wait(200)
        if isInMatch and myRole == 'runner' and currentPoliceCode then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and HasEntityCollidedWithAnything(vehicle) then
                local now = GetGameTimer()
                if now - lastRamReport < CC.RAM_REPORT_COOLDOWN then goto continue end

                local speed = GetEntitySpeed(vehicle) * CC.MS_TO_MPH
                if speed < CC.RAM_SPEED_MIN_MPH then goto continue end

                local myHeading = GetEntityHeading(vehicle)
                local myCoords = GetEntityCoords(vehicle)

                for _, playerId in ipairs(GetActivePlayers()) do
                    if playerId ~= PlayerId() then
                        local otherPed = GetPlayerPed(playerId)
                        if otherPed ~= 0 then
                            local otherVeh = GetVehiclePedIsIn(otherPed, false)
                            if otherVeh ~= 0 then
                                local otherCoords = GetEntityCoords(otherVeh)
                                local dist = #(myCoords - otherCoords)
                                if dist < CC.RAM_DETECT_RADIUS then
                                    local chaserHeading = GetEntityHeading(otherVeh)
                                    local hdgDiff = math.abs(myHeading - chaserHeading)
                                    if hdgDiff > 180 then hdgDiff = 360 - hdgDiff end

                                    if hdgDiff < 90 then goto nextPlayer end

                                    local toOther = otherCoords - myCoords
                                    local angleToOther = math.deg(math.atan(toOther.y, toOther.x))
                                    local headingAngle = (450.0 - myHeading) % 360.0
                                    local diff = math.abs(headingAngle - ((angleToOther % 360 + 360) % 360))
                                    if diff > 180 then diff = 360 - diff end

                                    local chaserSpeed = GetEntitySpeed(otherVeh) * CC.MS_TO_MPH

                                    if diff < CC.RAM_ANGLE_THRESHOLD and speed > chaserSpeed * CC.RAM_SPEED_RATIO then
                                        lastRamReport = now
                                        TriggerServerEvent('blacklist:reportViolation', 'runner_ram_pd')
                                        break
                                    end
                                end
                                ::nextPlayer::
                            end
                        end
                    end
                end
                ::continue::
            end
        end
    end
end)

-- ============================================================
-- ANTI-CHEAT TELEMETRY v1.0 — Comprehensive F8 Console Logger
-- Press F8 in-game to view all logs in real time
-- ============================================================

local AC_VERSION = '1.0'

-- F8 color codes: ^1=red ^2=green ^3=yellow ^4=blue ^5=cyan ^6=purple ^0=reset
local CLR = { R='^1', G='^2', Y='^3', B='^4', C='^5', P='^6', X='^0' }

-- ========================
-- Telemetry state
-- ========================

local telem = {
    wasAirborne       = false,
    airborneStart     = 0,
    airborneStartSpd  = 0,
    airborneStartHgt  = 0,
    airborneMaxHgt    = 0,
    airborneCause     = 'UNKNOWN',
    preAirborneSlope  = 0,

    lastCollisionTime = 0,
    lastPitReport     = 0,
    lastJumpReport    = 0,
    lastEnvCrash      = nil,
    lastWallHitTime   = 0,
    lastWallHitSpeed  = 0,

    lastSpeed         = 0,
    lastHeading       = 0,
    isBraking         = false,
    brakeStartTime    = 0,
    isAccelerating    = false,
    steeringAngle     = 0,

    oppPrevSpeed      = 0,
    oppPrevDist       = 999,
    oppSpeedHistory   = {},
    maxOppSamples     = 10,

    lastBrakeCheck    = nil,
    brakeCheckCount   = 0,

    speedSamples      = {},
    maxSpeedSamples   = 20,

    pitch             = 0,
    roll              = 0,
    lastTerrainLog    = 0,
    lastTerrainType   = 'FLAT',

    totalCollisions   = 0,
    playerContacts    = 0,
    envCollisions     = 0,
    airborneCount     = 0,
    spinOuts          = 0,
    wallBounces       = 0,
    lastSummaryTime   = 0,

    preContactHealth  = nil,
    waterReported     = false,
    terrainReported   = false,
    hillTimeAccum     = 0,
    hillTimeLast      = 0,
    hillWarningActive = false,
    hillCountdown     = 10,
}

-- ========================
-- Logging
-- ========================

local function matchTime()
    if matchStartTime and matchStartTime > 0 then
        return (GetGameTimer() - matchStartTime) / 1000.0
    end
    return 0.0
end

local function acLog(level, msg)
    local color = CLR.G
    if level == 'WARN' then color = CLR.Y
    elseif level == 'CRIT' then color = CLR.R
    elseif level == 'DATA' then color = CLR.C
    elseif level == 'ANLZ' then color = CLR.P end

    local role = (myRole or '???'):upper()
    local t = ('%.1f'):format(matchTime())

    print(('%s[AC]%s %s[%s]%s [%ss] [%s] %s'):format(
        CLR.C, CLR.X, color, level, CLR.X, t, role, msg))

    TriggerServerEvent('blacklist:chaseLog', {
        message = ('[%s] [%ss] [%s] %s'):format(level, t, role, msg)
    })
end

-- ========================
-- Vehicle health snapshot for repair system
-- ========================

local function snapshotVehicleHealth(vehicle)
    if not vehicle or vehicle == 0 then return nil end
    return {
        body   = GetVehicleBodyHealth(vehicle),
        engine = GetVehicleEngineHealth(vehicle),
        petrol = GetVehiclePetrolTankHealth(vehicle),
    }
end

local function restoreVehicleHealth(vehicle, snapshot)
    if not vehicle or vehicle == 0 then return end
    SetVehicleFixed(vehicle)
    if snapshot then
        SetVehicleBodyHealth(vehicle, snapshot.body)
        SetVehicleEngineHealth(vehicle, snapshot.engine)
        SetVehiclePetrolTankHealth(vehicle, snapshot.petrol)
    end
end

-- ========================
-- Vehicle data snapshot
-- ========================

local function getVehicleData(vehicle)
    if not vehicle or vehicle == 0 then return nil end

    local speed   = GetEntitySpeed(vehicle)
    local coords  = GetEntityCoords(vehicle)
    local fwd     = GetEntityForwardVector(vehicle)
    local rotVel  = GetEntityRotationVelocity(vehicle)

    return {
        entity    = vehicle,
        speed     = speed,
        speedKmh  = math.floor(speed * 3.6),
        heading   = GetEntityHeading(vehicle),
        coords    = coords,
        pitch     = GetEntityPitch(vehicle),
        roll      = GetEntityRoll(vehicle),
        height    = GetEntityHeightAboveGround(vehicle),
        fwd       = fwd,
        vel       = GetEntityVelocity(vehicle),
        rotVel    = rotVel,
        yawRate   = math.abs(rotVel.z) * CC.RAD_TO_DEG,
        steering  = GetVehicleSteeringAngle(vehicle),
        onWheels  = IsVehicleOnAllWheels(vehicle),
        inAir     = IsEntityInAir(vehicle),
        upright   = IsEntityUpright(vehicle),
        upsideDown = IsEntityUpsidedown(vehicle),
        braking   = IsControlPressed(0, 72) or IsDisabledControlPressed(0, 72),
        throttle  = IsControlPressed(0, 71) or IsDisabledControlPressed(0, 71),
    }
end

-- ========================
-- Closest opponent snapshot
-- ========================

local function getOpponentData()
    local myPed    = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local best     = {
        dist = CC.FAR_DISTANCE_OPP, speed = 0, speedKmh = 0, heading = 0,
        ped = 0, vehicle = 0, coords = myCoords,
        fwd = vector3(0,1,0), yawRate = 0, braking = false,
        serverId = 0,
    }

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local otherPed = GetPlayerPed(playerId)
            if otherPed ~= 0 then
                local otherCoords = GetEntityCoords(otherPed)
                local dist = #(myCoords - otherCoords)
                if dist < best.dist then
                    best.dist     = dist
                    best.ped      = otherPed
                    best.coords   = otherCoords
                    best.serverId = GetPlayerServerId(playerId)
                    local veh = GetVehiclePedIsIn(otherPed, false)
                    best.vehicle = veh
                    if veh ~= 0 then
                        best.speed    = GetEntitySpeed(veh)
                        best.speedKmh = math.floor(best.speed * 3.6)
                        best.heading  = GetEntityHeading(veh)
                        best.fwd      = GetEntityForwardVector(veh)
                        local rv      = GetEntityRotationVelocity(veh)
                        best.yawRate  = math.abs(rv.z) * CC.RAD_TO_DEG
                        best.braking  = false
                    end
                end
            end
        end
    end

    if best.ped == 0 and soloDummyPed ~= 0 and DoesEntityExist(soloDummyPed) then
        local otherCoords = GetEntityCoords(soloDummyPed)
        local dist = #(myCoords - otherCoords)
        best.dist   = dist
        best.ped    = soloDummyPed
        best.coords = otherCoords
        local veh = soloDummyVehicle ~= 0 and DoesEntityExist(soloDummyVehicle) and soloDummyVehicle or GetVehiclePedIsIn(soloDummyPed, false)
        best.vehicle = veh
        if veh ~= 0 then
            best.speed    = GetEntitySpeed(veh)
            best.speedKmh = math.floor(best.speed * 3.6)
            best.heading  = GetEntityHeading(veh)
            best.fwd      = GetEntityForwardVector(veh)
            local rv      = GetEntityRotationVelocity(veh)
            best.yawRate  = math.abs(rv.z) * CC.RAD_TO_DEG
            best.braking  = false
        end
    end

    return best
end

-- ========================
-- Utilities
-- ========================

local function headingDiff(h1, h2)
    local diff = math.abs(h1 - h2)
    if diff > 180 then diff = 360 - diff end
    return diff
end

local function addSpeedSample(kmh)
    table.insert(telem.speedSamples, kmh)
    if #telem.speedSamples > telem.maxSpeedSamples then
        table.remove(telem.speedSamples, 1)
    end
end

local function getSpeedTrend()
    local n = #telem.speedSamples
    if n < 4 then return 'STABLE', 0 end
    local recent = telem.speedSamples[n]
    local older  = telem.speedSamples[math.max(1, n - 5)]
    local diff   = recent - older
    if diff < -15 then return 'BRAKING_HARD', diff
    elseif diff < -5 then return 'DECELERATING', diff
    elseif diff > 10 then return 'ACCELERATING', diff
    else return 'STABLE', diff end
end

-- ========================
-- Pit maneuver & collision analysis
-- ========================

local function analyzePitManeuver(myData, opp)
    local toOpp     = opp.coords - myData.coords
    local toOppLen  = #toOpp
    if toOppLen < 0.01 then toOppLen = 0.01 end
    local toOppN    = toOpp / toOppLen

    local approachDot   = myData.fwd.x * toOppN.x + myData.fwd.y * toOppN.y
    local approachAngle = math.acos(math.max(-1, math.min(1, approachDot))) * CC.RAD_TO_DEG

    local hdgDiff = headingDiff(myData.heading, opp.heading)
    local spdDiff = myData.speedKmh - opp.speedKmh

    local contactType = 'SIDESWIPE'
    if approachAngle < 30 then
        contactType = hdgDiff < 45 and 'REAR_END' or 'T_BONE'
    elseif approachAngle > 150 then
        contactType = 'HEAD_ON'
    elseif hdgDiff < 45 then
        contactType = 'PIT_MANEUVER'
    end

    local intentScore = 0
    local factors = {}

    if contactType == 'REAR_END' then
        intentScore = intentScore + 2
        table.insert(factors, 'rear_end')
    end

    if math.abs(myData.steering) > 10 then
        intentScore = intentScore + 2
        table.insert(factors, ('steering=%.0f°'):format(myData.steering))
    end

    if not telem.isBraking then
        intentScore = intentScore + 1
        table.insert(factors, 'no_brake')
    else
        intentScore = intentScore - 2
        local brakeDur = (GetGameTimer() - telem.brakeStartTime) / 1000.0
        table.insert(factors, ('braking_%.1fs'):format(brakeDur))
    end

    if spdDiff > 30 then
        intentScore = intentScore + 2
        table.insert(factors, ('closing_fast+%d'):format(spdDiff))
    elseif spdDiff > 15 then
        intentScore = intentScore + 1
    end

    if hdgDiff < 15 and contactType == 'SIDESWIPE' then
        intentScore = intentScore - 1
        table.insert(factors, 'parallel')
    end

    -- Opponent braked / slowed suddenly (brake-check scenario)
    if opp.speedKmh < telem.oppPrevSpeed - 20 then
        intentScore = intentScore - 1
        table.insert(factors, ('opp_braked_%d→%d'):format(telem.oppPrevSpeed, opp.speedKmh))
    end

    if matchMode == 'ranked' and telem.lastBrakeCheck and (GetGameTimer() - telem.lastBrakeCheck.time) < CC.BRAKE_CHECK_CONTEXT and myRole == 'chaser' then
        intentScore = intentScore - 3
        local gap = GetGameTimer() - telem.lastBrakeCheck.time
        table.insert(factors, ('BRAKE_CHECKED_%dms_ago_opp_%d→%d'):format(
            gap, telem.lastBrakeCheck.oppSpeedBefore, telem.lastBrakeCheck.oppSpeedAfter))
    end

    if telem.lastEnvCrash and (GetGameTimer() - telem.lastEnvCrash.time) < CC.FOLLOW_UP_WINDOW and myRole == 'chaser' then
        local gap = GetGameTimer() - telem.lastEnvCrash.time
        if gap <= CC.FOLLOW_UP_NO_TIME or (gap <= CC.FOLLOW_UP_HAD_TIME and telem.isBraking) then
            intentScore = intentScore - 2
            table.insert(factors, ('follow_up_%dms'):format(gap))
        else
            table.insert(factors, ('follow_up_%dms_DID_NOT_AVOID'):format(gap))
        end
    end

    local intent = 'LIKELY_ACCIDENTAL'
    if intentScore >= 3 then intent = 'LIKELY_INTENTIONAL'
    elseif intentScore >= 1 then intent = 'UNCLEAR' end

    return {
        contactType   = contactType,
        approachAngle = approachAngle,
        headingDiff   = hdgDiff,
        speedDiff     = spdDiff,
        intent        = intent,
        intentScore   = intentScore,
        factors       = table.concat(factors, ', '),
    }
end

-- ========================
-- Airborne cause detection
-- ========================

local function determineAirborneCause(myData)
    local now = GetGameTimer()

    if telem.lastWallHitTime > 0 and (now - telem.lastWallHitTime) < 500 then
        return 'WALL_BOUNCE'
    end

    if math.abs(telem.pitch) > 10 then
        return 'HILL'
    end

    if telem.lastCollisionTime > 0 and (now - telem.lastCollisionTime) < 500 then
        return 'PLAYER_HIT'
    end

    if myData.height < 1.5 then
        return 'BUMP'
    end

    return 'UNKNOWN'
end

-- ========================
-- Match lifecycle logging (hooks into existing HUD events)
-- ========================

RegisterNetEvent('blacklist:chaseHUD')
AddEventHandler('blacklist:chaseHUD', function(data)
    if data.action == 'start' then
        telem.totalCollisions = 0
        telem.playerContacts  = 0
        telem.envCollisions   = 0
        telem.airborneCount   = 0
        telem.spinOuts        = 0
        telem.wallBounces     = 0
        telem.speedSamples    = {}
        telem.oppSpeedHistory = {}
        telem.lastEnvCrash    = nil
        telem.lastBrakeCheck  = nil
        telem.brakeCheckCount = 0
        telem.lastSummaryTime = GetGameTimer()
        telem.lastTerrainType = 'FLAT'
        telem.preContactHealth = nil
        telem.waterReported    = false
        telem.terrainReported  = false
        telem.hillTimeAccum    = 0
        telem.hillTimeLast     = 0
        telem.hillWarningActive = false
        telem.hillCountdown    = 10

        acLog('INFO', ('========== MATCH START ==========  role=%s  duration=%ds'):format(
            data.role or '?', data.duration or 0))

    elseif data.action == 'end' then
        acLog('INFO', ('========== MATCH END ==========  won=%s  reason=%s'):format(
            tostring(data.won), data.reason or '?'))
        acLog('DATA', ('FINAL STATS | contacts: player=%d env=%d total=%d | airborne=%d | spins=%d | wall_bounces=%d | brake_checks=%d'):format(
            telem.playerContacts, telem.envCollisions, telem.totalCollisions,
            telem.airborneCount, telem.spinOuts, telem.wallBounces, telem.brakeCheckCount))
    end
end)

-- ============================================================
-- Telemetry sub-functions (extracted from fast/slow samplers)
-- ============================================================

local function updateInputState(vd)
    local wasBraking    = telem.isBraking
    telem.isBraking     = vd.braking
    telem.isAccelerating = vd.throttle
    telem.steeringAngle = vd.steering

    if vd.braking and not wasBraking then
        telem.brakeStartTime = GetGameTimer()
    end

    addSpeedSample(vd.speedKmh)
    telem.lastSpeed   = vd.speedKmh
    telem.lastHeading = vd.heading
    telem.pitch       = vd.pitch
    telem.roll        = vd.roll
end

local function detectWaterContact(vehicle)
    if GetEntitySubmergedLevel(vehicle) > 0.7 and myRole == 'runner' and not telem.waterReported then
        telem.waterReported = true
        acLog('CRIT', 'WATER DETECTED — runner vehicle submerged')
        TriggerServerEvent('blacklist:reportViolation', 'runner_water')
    end
end

local function processAirborne(vd)
    if vd.inAir and not telem.wasAirborne then
        telem.wasAirborne       = true
        telem.airborneStart     = GetGameTimer()
        telem.airborneStartSpd  = vd.speedKmh
        telem.airborneStartHgt  = vd.height
        telem.airborneMaxHgt    = vd.height
        telem.preAirborneSlope  = telem.pitch
        telem.airborneCause     = determineAirborneCause(vd)
        telem.airborneCount     = telem.airborneCount + 1

        acLog('INFO', ('AIRBORNE START | spd=%d km/h | hgt=%.1fm | cause=%s | slope=%.1f° | steering=%.0f°'):format(
            vd.speedKmh, vd.height, telem.airborneCause, telem.pitch, vd.steering))

    elseif vd.inAir and telem.wasAirborne then
        if vd.height > telem.airborneMaxHgt then
            telem.airborneMaxHgt = vd.height
        end

    elseif not vd.inAir and telem.wasAirborne then
        local dur = (GetGameTimer() - telem.airborneStart) / 1000.0
        telem.wasAirborne = false

        local level = 'INFO'
        if dur >= CC.AIRBORNE_LONG_SEC then level = 'CRIT'
        elseif dur >= CC.AIRBORNE_WARN_SEC then level = 'WARN' end

        local landing = 'CLEAN'
        if vd.upsideDown then landing = 'UPSIDE_DOWN'
        elseif not vd.upright then landing = 'TUMBLED'
        elseif math.abs(vd.roll) > 30 then landing = 'ROUGH' end

        acLog(level, ('AIRBORNE END | dur=%.1fs | launch=%d km/h | land=%d km/h | max_hgt=%.1fm | cause=%s | landing=%s'):format(
            dur, telem.airborneStartSpd, vd.speedKmh, telem.airborneMaxHgt, telem.airborneCause, landing))

        if (dur >= CC.AIRBORNE_LONG_SEC or telem.airborneMaxHgt >= CC.AIRBORNE_DQ_HEIGHT) and myRole == 'runner' then
            local now = GetGameTimer()
            if now - telem.lastJumpReport >= CC.JUMP_REPORT_COOLDOWN then
                telem.lastJumpReport = now
                TriggerServerEvent('blacklist:reportViolation', 'runner_jump')
            end
        end
        airborneTimer = 0.0
    end
end

-- ============================================================
-- THREAD 1 — Fast sampler (100 ms)
-- ============================================================

Citizen.CreateThread(function()
    TriggerServerEvent('blacklist:chaseLog', { message = '[DIAG] Thread1 STARTED' })

    while true do
        Citizen.Wait(100)

        if not isInMatch then
            telem.wasAirborne = false
            telem.airborneStart = 0
        else
            local ok, err = pcall(function()
                local ped     = PlayerPedId()
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle == 0 then return end

                local vd = getVehicleData(vehicle)
                if not vd then return end

                updateInputState(vd)
                detectWaterContact(vehicle)
                telem.preContactHealth = snapshotVehicleHealth(vehicle)
                processAirborne(vd)

                -- ======== COLLISION DETECTION ========

                if HasEntityCollidedWithAnything(vehicle) then
                    local now = GetGameTimer()
                    if now - telem.lastCollisionTime < CC.COLLISION_COOLDOWN_MS then return end
                    telem.lastCollisionTime = now
                    telem.totalCollisions   = telem.totalCollisions + 1

                    local opp = getOpponentData()
                    local isPlayerContact = opp.dist < CC.PLAYER_CONTACT_DIST

                    if isPlayerContact then
                        telem.playerContacts = telem.playerContacts + 1

                        local analysis = analyzePitManeuver(vd, opp)

                        local spinInfo = ''
                        if opp.yawRate > 45 then
                            spinInfo = (' | OPP_SPIN=YES %.0f°/s'):format(opp.yawRate)
                            telem.spinOuts = telem.spinOuts + 1
                        end

                        local brakeInfo = 'NO'
                        if telem.isBraking then
                            local brakeDur = (GetGameTimer() - telem.brakeStartTime) / 1000.0
                            brakeInfo = ('YES %.1fs'):format(brakeDur)
                        end

                        local trend, _ = getSpeedTrend()

                        local level = 'INFO'
                        if analysis.intent == 'LIKELY_INTENTIONAL' then level = 'WARN' end

                        acLog(level, ('CONTACT PLAYER | type=%s | intent=%s (score=%d) | my_spd=%d | opp_spd=%d km/h | dist=%.1fm'):format(
                            analysis.contactType, analysis.intent, analysis.intentScore, vd.speedKmh, opp.speedKmh, opp.dist))

                        acLog(level, ('  > approach=%.0f° | hdg_diff=%.0f° | spd_diff=%+d | steer=%.0f° | brake=%s | trend=%s%s'):format(
                            analysis.approachAngle, analysis.headingDiff, analysis.speedDiff,
                            vd.steering, brakeInfo, trend, spinInfo))

                        if #analysis.factors > 0 then
                            acLog('ANLZ', ('  > factors: %s'):format(analysis.factors))
                        end

                        local followUpReaction = nil
                        if telem.lastEnvCrash and myRole == 'chaser' then
                            local gap = now - telem.lastEnvCrash.time
                            if gap < CC.FOLLOW_UP_WINDOW then
                                local reaction = 'NO_TIME'
                                if gap > CC.FOLLOW_UP_HAD_TIME then
                                    reaction = 'HAD_TIME'
                                elseif gap > CC.FOLLOW_UP_NO_TIME then
                                    reaction = telem.isBraking and 'TRIED_AVOID' or 'DID_NOT_AVOID'
                                end
                                followUpReaction = reaction

                                acLog('ANLZ', ('  > FOLLOW-UP: runner crashed %dms ago @ %d km/h | reaction=%s | chaser_brake=%s | dist_at_crash=%.0fm'):format(
                                    gap, telem.lastEnvCrash.speed, reaction, brakeInfo, opp.dist))

                                if reaction == 'NO_TIME' or reaction == 'TRIED_AVOID' then
                                    TriggerServerEvent('blacklist:requestRepair', 'self')
                                end
                            end
                        end

                        if myRole == 'chaser' then
                            if matchMode == 'ranked' then
                                local wasBrakeChecked = telem.lastBrakeCheck
                                    and (now - telem.lastBrakeCheck.time) < CC.BRAKE_CHECK_CONTEXT

                                if wasBrakeChecked then
                                    local bcGap = now - telem.lastBrakeCheck.time
                                    acLog('CRIT', ('  > !! BRAKE-CHECK → RAM !! runner braked %dms before contact (%d→%d km/h) | chaser NOT penalized'):format(
                                        bcGap, telem.lastBrakeCheck.oppSpeedBefore, telem.lastBrakeCheck.oppSpeedAfter))

                                    local oppOnHill = false
                                    if opp.vehicle ~= 0 then
                                        local oppPitch = GetEntityPitch(opp.vehicle)
                                        if math.abs(oppPitch) > 10 then oppOnHill = true end
                                    end
                                    local wasEnvCrash = telem.lastEnvCrash and (now - telem.lastEnvCrash.time) < CC.FOLLOW_UP_WINDOW

                                    if not oppOnHill and not wasEnvCrash then
                                        acLog('CRIT', '  > DELIBERATE BRAKE-CHECK — runner penalized')
                                        TriggerServerEvent('blacklist:reportViolation', 'runner_brake_check')
                                    else
                                        acLog('ANLZ', '  > brake-check likely caused by terrain/crash — no runner penalty')
                                    end

                                    TriggerServerEvent('blacklist:requestRepair', 'self')
                                end
                            end

                            if analysis.intent == 'LIKELY_INTENTIONAL' then
                                local pitNow = GetGameTimer()
                                if pitNow - telem.lastPitReport >= CC.PIT_REPORT_COOLDOWN then
                                    telem.lastPitReport = pitNow
                                    local isRunnerContact = (opp.serverId == runnerServerId)
                                    if isRunnerContact then
                                        acLog('CRIT', ('  > PIT STRIKE — intentional contact on RUNNER (score=%d)'):format(analysis.intentScore))
                                        local pitSpeedMph = vd.speedKmh * CC.KMH_TO_MPH
                                        TriggerServerEvent('blacklist:reportViolation', 'chaser_pit', pitSpeedMph)
                                        TriggerServerEvent('blacklist:requestRepair', 'opponent')
                                    else
                                        acLog('CRIT', ('  > FRIENDLY FIRE — intentional contact on PD (score=%d)'):format(analysis.intentScore))
                                        TriggerServerEvent('blacklist:reportViolation', 'chaser_friendly_fire')
                                    end
                                end
                            end
                        end

                    else
                        telem.envCollisions = telem.envCollisions + 1

                        local prevSpd   = #telem.speedSamples > 2 and telem.speedSamples[#telem.speedSamples - 2] or vd.speedKmh
                        local speedLoss = prevSpd - vd.speedKmh

                        local severity = 'LIGHT'
                        if speedLoss > 50 then severity = 'HEAVY'
                        elseif speedLoss > 20 then severity = 'MEDIUM' end

                        telem.lastWallHitTime  = now
                        telem.lastWallHitSpeed = vd.speedKmh

                        local level = severity == 'HEAVY' and 'WARN' or 'INFO'

                        acLog(level, ('COLLISION ENV | severity=%s | spd=%d km/h | lost=%d km/h | pitch=%.1f° | roll=%.1f° | opp_dist=%.0fm'):format(
                            severity, vd.speedKmh, speedLoss, vd.pitch, vd.roll, opp.dist))

                        if myRole == 'runner' then
                            telem.lastEnvCrash = { time = now, speed = vd.speedKmh }
                            TriggerServerEvent('blacklist:chaseLog', {
                                message = ('RUNNER_ENV_CRASH | speed=%d km/h | severity=%s'):format(vd.speedKmh, severity),
                            })
                        end

                        if vd.inAir or vd.height > 1.5 then
                            telem.wallBounces = telem.wallBounces + 1
                            acLog('WARN', ('  > WALL BOUNCE | hgt=%.1fm | upright=%s | spd=%d km/h'):format(
                                vd.height, vd.upright and 'YES' or 'NO', vd.speedKmh))
                        end
                    end

                    telem.oppPrevSpeed = opp.speedKmh
                    telem.oppPrevDist  = opp.dist
                end
            end)

            if not ok then
                TriggerServerEvent('blacklist:chaseLog', { message = '[DIAG] Thread1 ERROR: ' .. tostring(err) })
            end
        end
    end
end)

-- ============================================================
-- Slow-sampler sub-functions
-- ============================================================

local function classifyTerrain(vd)
    local slopeAbs    = math.abs(vd.pitch)
    local terrainType = 'FLAT'
    if slopeAbs > CC.SLOPE_STEEP then terrainType = 'STEEP_HILL'
    elseif slopeAbs > CC.SLOPE_HILL then terrainType = 'HILL'
    elseif slopeAbs > CC.SLOPE_MILD then terrainType = 'SLOPE' end

    local rollTag = ''
    if math.abs(vd.roll) > 20 then rollTag = ' BANKED'
    elseif math.abs(vd.roll) > 8 then rollTag = ' TILTED' end

    return terrainType, rollTag
end

local function trackHillTime(terrainType, vd, now)
end

local function detectBrakeCheck(vd, opp, now)
    if myRole ~= 'chaser' or opp.dist >= CC.BRAKE_CHECK_DIST then return end

    local nOpp = #telem.oppSpeedHistory
    if nOpp < 3 then return end

    local oppNow    = telem.oppSpeedHistory[nOpp]
    local oppRecent = telem.oppSpeedHistory[math.max(1, nOpp - 2)]
    local oppDecel  = oppRecent - oppNow

    if oppDecel <= CC.BRAKE_CHECK_DECEL or oppNow >= vd.speedKmh then return end

    local prevBC = telem.lastBrakeCheck
    local isRepeat = prevBC and (now - prevBC.time) < CC.BRAKE_CHECK_REPEAT_MS

    telem.lastBrakeCheck = {
        time           = now,
        oppSpeedBefore = oppRecent,
        oppSpeedAfter  = oppNow,
        dist           = opp.dist,
        mySpeed        = vd.speedKmh,
    }
    telem.brakeCheckCount = telem.brakeCheckCount + 1

    local repeatTag = isRepeat and ' | !! REPEATED !!' or ''

    acLog('CRIT', ('BRAKE-CHECK #%d | opp_spd %d→%d km/h (-%d) | dist=%.0fm | my_spd=%d km/h | my_brake=%s | closing=%s%s'):format(
        telem.brakeCheckCount,
        oppRecent, oppNow, oppDecel,
        opp.dist, vd.speedKmh,
        telem.isBraking and 'YES' or 'NO',
        opp.dist < telem.oppPrevDist and 'YES' or 'NO',
        repeatTag))

    local oppOnHill = false
    if opp.vehicle ~= 0 then
        if math.abs(GetEntityPitch(opp.vehicle)) > 10 then oppOnHill = true end
    end

    if oppOnHill then
        acLog('ANLZ', '  > NOTE: opponent on hill/slope — may be terrain decel, not intentional')
    elseif opp.dist < 15 then
        acLog('ANLZ', '  > DANGER: very close range brake-check — high collision risk')
    end
end

-- ============================================================
-- THREAD 2 — Slow sampler (500 ms)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(500)

        if not isInMatch then goto continue end

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle == 0 then goto continue end

        local vd = getVehicleData(vehicle)
        if not vd then goto continue end

        local opp = getOpponentData()
        local now = GetGameTimer()

        table.insert(telem.oppSpeedHistory, opp.speedKmh)
        if #telem.oppSpeedHistory > telem.maxOppSamples then
            table.remove(telem.oppSpeedHistory, 1)
        end
        telem.oppPrevSpeed = opp.speedKmh
        telem.oppPrevDist  = opp.dist

        local terrainType, rollTag = classifyTerrain(vd)

        if terrainType ~= 'FLAT' and not vd.inAir and terrainType ~= telem.lastTerrainType
            and (now - telem.lastTerrainLog > CC.TERRAIN_LOG_COOLDOWN) then
            telem.lastTerrainLog  = now
            telem.lastTerrainType = terrainType
            acLog('DATA', ('TERRAIN | type=%s%s | pitch=%.1f° | roll=%.1f° | spd=%d km/h | wheels_down=%s'):format(
                terrainType, rollTag, vd.pitch, vd.roll, vd.speedKmh, vd.onWheels and 'YES' or 'NO'))
        elseif terrainType == 'FLAT' then
            telem.lastTerrainType = 'FLAT'
        end

        trackHillTime(terrainType, vd, now)

        if vd.yawRate > 90 and not vd.inAir then
            acLog('WARN', ('SPIN | yaw_rate=%.0f°/s | spd=%d km/h | wheels=%s | steer=%.0f° | roll=%.1f°'):format(
                vd.yawRate, vd.speedKmh, vd.onWheels and 'YES' or 'NO', vd.steering, vd.roll))
        end

        if matchMode == 'ranked' then
            detectBrakeCheck(vd, opp, now)
        end

        if now - telem.lastSummaryTime >= CC.SUMMARY_INTERVAL_MS then
            telem.lastSummaryTime = now
            local trend, _ = getSpeedTrend()

            acLog('DATA', ('--- %ss SUMMARY --- spd=%d km/h | trend=%s | opp_dist=%.0fm | opp_spd=%d km/h'):format(
                ('%.0f'):format(matchTime()), vd.speedKmh, trend, opp.dist, opp.speedKmh))
            acLog('DATA', ('  > hits: player=%d env=%d | airborne=%d | spins=%d | wall_bounce=%d | brake_checks=%d | brake=%s | steer=%.0f°'):format(
                telem.playerContacts, telem.envCollisions,
                telem.airborneCount, telem.spinOuts, telem.wallBounces,
                telem.brakeCheckCount, telem.isBraking and 'YES' or 'NO', vd.steering))
        end

        ::continue::
    end
end)

-- ========================
-- Vehicle repair (triggered by server after penalty events)
-- ========================

RegisterNetEvent('blacklist:repairVehicle')
AddEventHandler('blacklist:repairVehicle', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return end

    restoreVehicleHealth(vehicle, telem.preContactHealth)
    acLog('INFO', 'VEHICLE REPAIRED to pre-contact state')
end)

-- ========================
-- Runner crash relay (chaser receives opponent crash context)
-- ========================

RegisterNetEvent('blacklist:runnerCrashInfo')
AddEventHandler('blacklist:runnerCrashInfo', function(data)
    if myRole == 'chaser' then
        telem.lastEnvCrash = { time = GetGameTimer(), speed = data.speed or 0 }

        local ped     = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local mySpeed = vehicle ~= 0 and math.floor(GetEntitySpeed(vehicle) * 3.6) or 0
        local braking = IsControlPressed(0, 72) or IsDisabledControlPressed(0, 72)
        local opp     = getOpponentData()

        acLog('INFO', ('RUNNER CRASHED | runner_spd=%d km/h | my_spd=%d km/h | dist=%.0fm | closing=%s | my_brake=%s'):format(
            data.speed or 0, mySpeed, opp.dist,
            opp.dist < telem.oppPrevDist and 'YES' or 'NO',
            braking and 'YES' or 'NO'))
    end
end)

-- ========================
-- NUI setup
-- ========================

Citizen.CreateThread(function()
    SetNuiFocus(false, false)
end)

-- ========================
-- Solo dummy NPC spawn + cleanup
-- ========================

local function cleanupSoloDummy()
    if soloDummyPed ~= 0 and DoesEntityExist(soloDummyPed) then
        DeleteEntity(soloDummyPed)
    end
    if soloDummyVehicle ~= 0 and DoesEntityExist(soloDummyVehicle) then
        DeleteEntity(soloDummyVehicle)
    end
    soloDummyPed = 0
    soloDummyVehicle = 0
end

RegisterNetEvent('blacklist:spawnSoloDummy')
AddEventHandler('blacklist:spawnSoloDummy', function(model, x, y, z, heading, dummyRole)
    cleanupSoloDummy()

    local vehHash = exports.lib:LoadModelWithFallback(model)

    local pedModel = dummyRole == 'chaser' and 's_m_y_cop_01' or 'a_m_y_business_01'
    local pedHash = GetHashKey(pedModel)
    RequestModel(pedHash)
    while not HasModelLoaded(pedHash) do Citizen.Wait(10) end

    local groundZ = z
    local found, gz = GetGroundZFor_3dCoord(x, y, z + 5.0, false)
    if found then groundZ = gz + 0.5 end

    local vehicle = CreateVehicle(vehHash, x, y, groundZ + 1.0, heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(vehHash)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDirtLevel(vehicle, 0.0)

    local ped = CreatePed(4, pedHash, x, y, groundZ + 1.0, heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(pedHash)
    SetPedIntoVehicle(ped, vehicle, -1)
    SetBlockingOfNonTemporaryEvents(ped, true)

    TaskVehicleDriveWander(ped, vehicle, 15.0, 786603)

    soloDummyPed = ped
    soloDummyVehicle = vehicle

    print(('[Chase] Solo dummy spawned: role=%s model=%s'):format(dummyRole, model))
end)

-- ========================
-- Chase UI cleanup (central)
-- ========================

local function clearChaseUI()
    isInMatch = false
    isPostMatch = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideAll' })
    cleanupSoloDummy()
    cleanupCodeFeatures()
end

exports('ClearChaseUI', clearChaseUI)

AddEventHandler('blacklist:clearChaseUI', clearChaseUI)

print(('[AC-LOG] %sAnti-Cheat Telemetry v%s loaded%s'):format(CLR.G, AC_VERSION, CLR.X))
