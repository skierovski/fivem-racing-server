local MM = require('lib.matchmaking_logic')

describe('expandSearchRange', function()
    it('returns initial range at time 0', function()
        expect(MM.expandSearchRange(0)).toBe(100)
    end)

    it('expands by one step after one interval', function()
        expect(MM.expandSearchRange(10000)).toBe(150)
    end)

    it('expands by two steps after two intervals', function()
        expect(MM.expandSearchRange(20000)).toBe(200)
    end)

    it('does not exceed max range', function()
        expect(MM.expandSearchRange(1000000)).toBe(500)
    end)

    it('does not expand before interval', function()
        expect(MM.expandSearchRange(9999)).toBe(100)
    end)

    it('respects custom config', function()
        local config = {
            RANKED_MMR_RANGE_INITIAL = 50,
            RANKED_MMR_RANGE_EXPAND = 25,
            RANKED_MMR_RANGE_MAX = 200,
            RANKED_EXPAND_INTERVAL = 5000,
        }
        expect(MM.expandSearchRange(5000, config)).toBe(75)
        expect(MM.expandSearchRange(500000, config)).toBe(200)
    end)
end)

describe('assignRole', function()
    it('assigns runner when escapes <= chases', function()
        expect(MM.assignRole(10, 5, false)).toBe('runner')
    end)

    it('assigns chaser when escapes > chases', function()
        expect(MM.assignRole(5, 10, false)).toBe('chaser')
    end)

    it('assigns runner when equal counts', function()
        expect(MM.assignRole(5, 5, false)).toBe('runner')
    end)

    it('forces runner when runner queue is empty', function()
        expect(MM.assignRole(0, 100, true)).toBe('runner')
    end)

    it('assigns runner when both nil', function()
        expect(MM.assignRole(nil, nil, false)).toBe('runner')
    end)
end)

describe('findRankedMatch', function()
    it('returns nil for empty queue', function()
        expect(MM.findRankedMatch({}, 0)).toBeNil()
    end)

    it('returns nil for single player', function()
        local queue = {
            { source = 1, mmr = 1000, joinedAt = 0, chases = 0, escapes = 0 },
        }
        expect(MM.findRankedMatch(queue, 0)).toBeNil()
    end)

    it('matches two players within range', function()
        local queue = {
            { source = 1, mmr = 1000, joinedAt = 0, chases = 5, escapes = 3 },
            { source = 2, mmr = 1050, joinedAt = 0, chases = 3, escapes = 5 },
        }
        local match = MM.findRankedMatch(queue, 0)
        expect(match).toNotBeNil()
        expect(match.chaser).toNotBeNil()
        expect(match.runner).toNotBeNil()
    end)

    it('does not match players outside range', function()
        local queue = {
            { source = 1, mmr = 1000, joinedAt = 0, chases = 0, escapes = 0 },
            { source = 2, mmr = 1200, joinedAt = 0, chases = 0, escapes = 0 },
        }
        local match = MM.findRankedMatch(queue, 0)
        expect(match).toBeNil()
    end)

    it('matches after range expansion', function()
        local queue = {
            { source = 1, mmr = 1000, joinedAt = 0, chases = 0, escapes = 0 },
            { source = 2, mmr = 1200, joinedAt = 0, chases = 0, escapes = 0 },
        }
        -- After 30 seconds of waiting, range should be 100 + 3*50 = 250
        local match = MM.findRankedMatch(queue, 30000)
        expect(match).toNotBeNil()
    end)

    it('assigns roles based on chase/escape balance', function()
        local queue = {
            { source = 1, mmr = 1000, joinedAt = 0, chases = 10, escapes = 2 },
            { source = 2, mmr = 1050, joinedAt = 0, chases = 2, escapes = 10 },
        }
        local match = MM.findRankedMatch(queue, 0)
        -- Player 1: chases(10) <= escapes(2) is FALSE -> a is NOT chaser -> b(player 2) is chaser
        expect(match.chaser.source).toBe(2)
        expect(match.runner.source).toBe(1)
    end)
end)

describe('findNormalMatch', function()
    it('returns nil with no runners', function()
        local chasers = { { source = 1 } }
        expect(MM.findNormalMatch({}, chasers)).toBeNil()
    end)

    it('returns nil with no chasers', function()
        local runners = { { source = 1 } }
        expect(MM.findNormalMatch(runners, {})).toBeNil()
    end)

    it('matches 1 runner with available chasers', function()
        local runners = { { source = 1 } }
        local chasers = { { source = 2 }, { source = 3 } }
        local match = MM.findNormalMatch(runners, chasers)
        expect(match).toNotBeNil()
        expect(match.runner.source).toBe(1)
        expect(match.chaserCount).toBe(2)
    end)

    it('caps chasers at max (4)', function()
        local runners = { { source = 1 } }
        local chasers = {}
        for i = 2, 8 do
            chasers[#chasers + 1] = { source = i }
        end
        local match = MM.findNormalMatch(runners, chasers)
        expect(match.chaserCount).toBe(4)
    end)
end)

describe('removeFromQueue', function()
    it('removes existing player', function()
        local queue = {
            { source = 1 }, { source = 2 }, { source = 3 },
        }
        local removed = MM.removeFromQueue(queue, 2)
        expect(removed).toBeTrue()
        expect(#queue).toBe(2)
    end)

    it('returns false for non-existent player', function()
        local queue = { { source = 1 } }
        local removed = MM.removeFromQueue(queue, 99)
        expect(removed).toBeFalse()
        expect(#queue).toBe(1)
    end)

    it('handles empty queue', function()
        local removed = MM.removeFromQueue({}, 1)
        expect(removed).toBeFalse()
    end)
end)
