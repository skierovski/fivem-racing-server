local Tier = require('lib.tier_utils')

describe('getTierIndex', function()
    it('returns 1 for bronze', function()
        expect(Tier.getTierIndex('bronze')).toBe(1)
    end)

    it('returns 6 for blacklist', function()
        expect(Tier.getTierIndex('blacklist')).toBe(6)
    end)

    it('returns 1 for unknown tier', function()
        expect(Tier.getTierIndex('mythic')).toBe(1)
    end)

    it('returns correct index for each tier', function()
        expect(Tier.getTierIndex('silver')).toBe(2)
        expect(Tier.getTierIndex('gold')).toBe(3)
        expect(Tier.getTierIndex('platinum')).toBe(4)
        expect(Tier.getTierIndex('diamond')).toBe(5)
    end)
end)

describe('getAvailableTiers', function()
    it('returns only bronze for bronze player', function()
        local tiers = Tier.getAvailableTiers('bronze')
        expect(#tiers).toBe(1)
        expect(tiers[1]).toBe('bronze')
    end)

    it('returns bronze and silver for silver player', function()
        local tiers = Tier.getAvailableTiers('silver')
        expect(#tiers).toBe(2)
        expect(tiers[1]).toBe('bronze')
        expect(tiers[2]).toBe('silver')
    end)

    it('returns all tiers for blacklist player', function()
        local tiers = Tier.getAvailableTiers('blacklist')
        expect(#tiers).toBe(6)
    end)

    it('returns gold and below for gold player', function()
        local tiers = Tier.getAvailableTiers('gold')
        expect(#tiers).toBe(3)
        expect(tiers[3]).toBe('gold')
    end)

    it('defaults to bronze for unknown tier', function()
        local tiers = Tier.getAvailableTiers('unknown')
        expect(#tiers).toBe(1)
        expect(tiers[1]).toBe('bronze')
    end)
end)

describe('filterVehiclesByTiers', function()
    local catalog = {
        { model = 'sultan',   label = 'Sultan',   tier = 'bronze' },
        { model = 'comet',    label = 'Comet',    tier = 'silver' },
        { model = 'zentorno', label = 'Zentorno', tier = 'gold' },
        { model = 'turismo',  label = 'Turismo',  tier = 'platinum' },
        { model = 'krieger',  label = 'Krieger',  tier = 'diamond' },
        { model = 'deveste',  label = 'Deveste',  tier = 'blacklist' },
    }

    it('filters to bronze only', function()
        local result = Tier.filterVehiclesByTiers(catalog, { 'bronze' })
        expect(#result).toBe(1)
        expect(result[1].model).toBe('sultan')
    end)

    it('filters to bronze + silver', function()
        local result = Tier.filterVehiclesByTiers(catalog, { 'bronze', 'silver' })
        expect(#result).toBe(2)
    end)

    it('returns all for all tiers', function()
        local allTiers = { 'bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist' }
        local result = Tier.filterVehiclesByTiers(catalog, allTiers)
        expect(#result).toBe(6)
    end)

    it('returns empty for empty catalog', function()
        local result = Tier.filterVehiclesByTiers({}, { 'bronze' })
        expect(#result).toBe(0)
    end)

    it('returns empty for no matching tiers', function()
        local result = Tier.filterVehiclesByTiers(catalog, { 'mythic' })
        expect(#result).toBe(0)
    end)
end)

describe('canAccessTier', function()
    it('bronze can access bronze', function()
        expect(Tier.canAccessTier('bronze', 'bronze')).toBeTrue()
    end)

    it('bronze cannot access silver', function()
        expect(Tier.canAccessTier('bronze', 'silver')).toBeFalse()
    end)

    it('gold can access bronze', function()
        expect(Tier.canAccessTier('gold', 'bronze')).toBeTrue()
    end)

    it('gold can access gold', function()
        expect(Tier.canAccessTier('gold', 'gold')).toBeTrue()
    end)

    it('gold cannot access platinum', function()
        expect(Tier.canAccessTier('gold', 'platinum')).toBeFalse()
    end)

    it('blacklist can access everything', function()
        expect(Tier.canAccessTier('blacklist', 'bronze')).toBeTrue()
        expect(Tier.canAccessTier('blacklist', 'diamond')).toBeTrue()
        expect(Tier.canAccessTier('blacklist', 'blacklist')).toBeTrue()
    end)
end)
