local MatchmakingLogic = {}

MatchmakingLogic.DEFAULT_CONFIG = {
    RANKED_MMR_RANGE_INITIAL = 100,
    RANKED_MMR_RANGE_EXPAND = 50,
    RANKED_MMR_RANGE_MAX = 500,
    RANKED_EXPAND_INTERVAL = 10000,
    NORMAL_MIN_CHASERS = 1,
    NORMAL_MAX_CHASERS = 4,
}

function MatchmakingLogic.expandSearchRange(waitTimeMs, config)
    config = config or MatchmakingLogic.DEFAULT_CONFIG
    local expansions = math.floor(waitTimeMs / config.RANKED_EXPAND_INTERVAL)
    return math.min(
        config.RANKED_MMR_RANGE_INITIAL + (expansions * config.RANKED_MMR_RANGE_EXPAND),
        config.RANKED_MMR_RANGE_MAX
    )
end

function MatchmakingLogic.assignRole(chases, escapes, runnerQueueEmpty)
    if runnerQueueEmpty then return 'runner' end
    if (escapes or 0) <= (chases or 0) then
        return 'runner'
    end
    return 'chaser'
end

function MatchmakingLogic.findRankedMatch(queue, now, config)
    config = config or MatchmakingLogic.DEFAULT_CONFIG
    if #queue < 2 then return nil end

    for i = 1, #queue do
        queue[i].searchRange = MatchmakingLogic.expandSearchRange(
            now - queue[i].joinedAt, config
        )
    end

    for i = 1, #queue do
        for j = i + 1, #queue do
            local a = queue[i]
            local b = queue[j]
            local mmrDiff = math.abs(a.mmr - b.mmr)
            local maxRange = math.max(a.searchRange, b.searchRange)

            if mmrDiff <= maxRange then
                local aIsChaser = (a.chases or 0) <= (a.escapes or 0)
                local chaser, runner
                if aIsChaser then
                    chaser = a
                    runner = b
                else
                    chaser = b
                    runner = a
                end

                return {
                    chaser = chaser,
                    runner = runner,
                    indexA = i,
                    indexB = j,
                }
            end
        end
    end

    return nil
end

function MatchmakingLogic.findNormalMatch(runnerQueue, chaserQueue, config)
    config = config or MatchmakingLogic.DEFAULT_CONFIG
    if #runnerQueue == 0 or #chaserQueue == 0 then return nil end

    local runner = runnerQueue[1]
    local numChasers = math.min(#chaserQueue, config.NORMAL_MAX_CHASERS)

    local chasers = {}
    for i = 1, numChasers do
        chasers[i] = chaserQueue[i]
    end

    return {
        runner = runner,
        chasers = chasers,
        runnerIndex = 1,
        chaserCount = numChasers,
    }
end

function MatchmakingLogic.removeFromQueue(queue, source)
    for i = #queue, 1, -1 do
        if queue[i].source == source then
            table.remove(queue, i)
            return true
        end
    end
    return false
end

return MatchmakingLogic
