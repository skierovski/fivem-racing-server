-- ============================================================
-- Shared client-side utilities
-- ============================================================

local MODEL_LOAD_TIMEOUT = 10000
local FALLBACK_MODEL = 'sultan'
local COLLISION_TIMEOUT = 8000

--- Load a vehicle model hash with a timeout, falling back to sultan on failure.
--- Yields (blocks the current thread) until the model is ready.
--- @param model string  model name to load
--- @return number hash  the loaded model hash (may be the fallback)
local function loadModelWithFallback(model)
    local hash = GetHashKey(model)
    RequestModel(hash)

    local deadline = GetGameTimer() + MODEL_LOAD_TIMEOUT
    while not HasModelLoaded(hash) do
        Citizen.Wait(100)
        if GetGameTimer() > deadline then
            print(('[Lib] ^3Model "%s" failed to load, falling back to %s^0'):format(model, FALLBACK_MODEL))
            hash = GetHashKey(FALLBACK_MODEL)
            RequestModel(hash)
            while not HasModelLoaded(hash) do Citizen.Wait(100) end
            break
        end
    end

    return hash
end

--- Stream collision and find solid ground at the given coordinates.
--- Yields until collision is loaded and ground is probed.
--- @param entity number  entity to check collision around
--- @param x number
--- @param y number
--- @param z number
--- @param probeHeight number|nil  height offset for ground probe (default 100)
--- @param probeAttempts number|nil  max probe iterations (default 30)
--- @return number finalZ  the resolved ground-level Z (with +0.5 offset) or the input z
local function resolveGroundZ(entity, x, y, z, probeHeight, probeAttempts)
    probeHeight = probeHeight or 100.0
    probeAttempts = probeAttempts or 30

    RequestCollisionAtCoord(x, y, z)
    local deadline = GetGameTimer() + COLLISION_TIMEOUT
    while not HasCollisionLoadedAroundEntity(entity) do
        Citizen.Wait(50)
        RequestCollisionAtCoord(x, y, z)
        if GetGameTimer() > deadline then break end
    end

    local found, groundZ = false, z
    for _ = 1, probeAttempts do
        found, groundZ = GetGroundZFor_3dCoord(x, y, z + probeHeight, false)
        if found then break end
        Citizen.Wait(100)
    end

    return found and (groundZ + 0.5) or z
end

exports('LoadModelWithFallback', loadModelWithFallback)
exports('ResolveGroundZ', resolveGroundZ)

print('[Lib] ^2Shared client utilities loaded^0')
