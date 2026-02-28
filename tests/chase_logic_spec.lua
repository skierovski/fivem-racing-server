local Chase = require('lib.chase_logic')

describe('updateCatchTimer', function()
    it('increments when within catch distance', function()
        local timer = Chase.updateCatchTimer(0, 10.0)
        expect(timer).toBe(0.5)
    end)

    it('accumulates over multiple ticks', function()
        local timer = Chase.updateCatchTimer(2.0, 10.0)
        expect(timer).toBe(2.5)
    end)

    it('resets when outside catch distance', function()
        local timer = Chase.updateCatchTimer(3.0, 20.0)
        expect(timer).toBe(0)
    end)

    it('increments at exact catch distance', function()
        local timer = Chase.updateCatchTimer(0, 15.0)
        expect(timer).toBe(0.5)
    end)

    it('resets just outside catch distance', function()
        local timer = Chase.updateCatchTimer(4.0, 15.1)
        expect(timer).toBe(0)
    end)
end)

describe('isCaught', function()
    it('returns false when timer below threshold', function()
        expect(Chase.isCaught(4.9)).toBeFalse()
    end)

    it('returns true when timer at threshold', function()
        expect(Chase.isCaught(5.0)).toBeTrue()
    end)

    it('returns true when timer above threshold', function()
        expect(Chase.isCaught(6.0)).toBeTrue()
    end)

    it('returns false at 0', function()
        expect(Chase.isCaught(0)).toBeFalse()
    end)
end)

describe('isTimeExpired', function()
    it('returns false before duration', function()
        expect(Chase.isTimeExpired(299)).toBeFalse()
    end)

    it('returns true at duration', function()
        expect(Chase.isTimeExpired(300)).toBeTrue()
    end)

    it('returns true after duration', function()
        expect(Chase.isTimeExpired(400)).toBeTrue()
    end)
end)

describe('isAirborneViolation', function()
    it('returns false within limit', function()
        expect(Chase.isAirborneViolation(1.5)).toBeFalse()
    end)

    it('returns false at exact limit', function()
        expect(Chase.isAirborneViolation(2.0)).toBeFalse()
    end)

    it('returns true above limit', function()
        expect(Chase.isAirborneViolation(2.1)).toBeTrue()
    end)
end)

describe('isRamViolation', function()
    it('returns false below threshold', function()
        expect(Chase.isRamViolation(25.0)).toBeFalse()
    end)

    it('returns true at threshold', function()
        expect(Chase.isRamViolation(30.0)).toBeTrue()
    end)

    it('returns true above threshold', function()
        expect(Chase.isRamViolation(50.0)).toBeTrue()
    end)
end)

describe('shouldDisqualify', function()
    it('returns false with 0 warnings', function()
        expect(Chase.shouldDisqualify(0)).toBeFalse()
    end)

    it('returns false with 1 warning', function()
        expect(Chase.shouldDisqualify(1)).toBeFalse()
    end)

    it('returns true at max warnings', function()
        expect(Chase.shouldDisqualify(2)).toBeTrue()
    end)

    it('returns true above max warnings', function()
        expect(Chase.shouldDisqualify(5)).toBeTrue()
    end)
end)

describe('getAllMatchSources', function()
    it('returns runner source for 1v1', function()
        local match = {
            runner = { source = 1 },
            chasers = { { source = 2 } },
        }
        local sources = Chase.getAllMatchSources(match)
        expect(#sources).toBe(2)
        expect(sources[1]).toBe(1)
        expect(sources[2]).toBe(2)
    end)

    it('returns all sources for 1v4', function()
        local match = {
            runner = { source = 10 },
            chasers = {
                { source = 20 }, { source = 30 },
                { source = 40 }, { source = 50 },
            },
        }
        local sources = Chase.getAllMatchSources(match)
        expect(#sources).toBe(5)
        expect(sources[1]).toBe(10)
    end)
end)

describe('determineWinner', function()
    it('chaser wins on runner disconnect', function()
        local winner, reason = Chase.determineWinner(true, 1, 0, false)
        expect(winner).toBe('chaser')
        expect(reason).toBe('runner_disconnected')
    end)

    it('runner wins when all chasers disconnect', function()
        local winner, reason = Chase.determineWinner(false, 0, 0, false)
        expect(winner).toBe('runner')
        expect(reason).toBe('all_chasers_disconnected')
    end)

    it('chaser wins on catch', function()
        local winner, reason = Chase.determineWinner(false, 1, 5.0, false)
        expect(winner).toBe('chaser')
        expect(reason).toBe('caught')
    end)

    it('runner wins on time expired', function()
        local winner, reason = Chase.determineWinner(false, 1, 0, true)
        expect(winner).toBe('runner')
        expect(reason).toBe('time_expired')
    end)

    it('returns nil when match still active', function()
        local winner, reason = Chase.determineWinner(false, 1, 2.0, false)
        expect(winner).toBeNil()
        expect(reason).toBeNil()
    end)

    it('prioritizes runner disconnect over catch', function()
        local winner, reason = Chase.determineWinner(true, 1, 5.0, true)
        expect(winner).toBe('chaser')
        expect(reason).toBe('runner_disconnected')
    end)
end)
