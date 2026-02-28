local ChaseLogic = {}

ChaseLogic.DEFAULT_CONFIG = {
    ROUND_DURATION = 300,
    RUNNER_HEAD_START = 5,
    CATCH_DISTANCE = 15.0,
    CATCH_TIME = 5.0,
    MAX_AIRBORNE_TIME = 2.0,
    RAM_SPEED_THRESHOLD = 30.0,
    MAX_WARNINGS = 2,
}

function ChaseLogic.updateCatchTimer(currentTimer, distance, config)
    config = config or ChaseLogic.DEFAULT_CONFIG
    if distance <= config.CATCH_DISTANCE then
        return currentTimer + 0.5
    end
    return 0
end

function ChaseLogic.isCaught(catchTimer, config)
    config = config or ChaseLogic.DEFAULT_CONFIG
    return catchTimer >= config.CATCH_TIME
end

function ChaseLogic.isTimeExpired(elapsedSeconds, config)
    config = config or ChaseLogic.DEFAULT_CONFIG
    return elapsedSeconds >= config.ROUND_DURATION
end

function ChaseLogic.isAirborneViolation(airborneTime, config)
    config = config or ChaseLogic.DEFAULT_CONFIG
    return airborneTime > config.MAX_AIRBORNE_TIME
end

function ChaseLogic.isRamViolation(speed, config)
    config = config or ChaseLogic.DEFAULT_CONFIG
    return speed >= config.RAM_SPEED_THRESHOLD
end

function ChaseLogic.shouldDisqualify(warningCount, config)
    config = config or ChaseLogic.DEFAULT_CONFIG
    return warningCount >= config.MAX_WARNINGS
end

function ChaseLogic.getAllMatchSources(match)
    local sources = { match.runner.source }
    for _, c in ipairs(match.chasers) do
        sources[#sources + 1] = c.source
    end
    return sources
end

function ChaseLogic.determineWinner(runnerDisconnected, chaserCount, catchTimer, timeExpired, config)
    config = config or ChaseLogic.DEFAULT_CONFIG

    if runnerDisconnected then
        return 'chaser', 'runner_disconnected'
    end
    if chaserCount == 0 then
        return 'runner', 'all_chasers_disconnected'
    end
    if catchTimer >= config.CATCH_TIME then
        return 'chaser', 'caught'
    end
    if timeExpired then
        return 'runner', 'time_expired'
    end

    return nil, nil
end

return ChaseLogic
