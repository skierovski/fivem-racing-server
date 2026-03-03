-- ============================================================
-- Reset all players to new FACEIT-style ELO system
-- Everyone starts fresh at 500 MMR (top of bronze)
-- New tiers: Bronze 0-500, Silver 501-650, Gold 651-800,
--            Platinum 801-950, Diamond 951-1100, Blacklist 1101+
-- ============================================================

USE `blacklist_racing`;

-- Reset all players to 500 MMR, bronze tier, zero stats
UPDATE players SET
    mmr = 500,
    tier = 'bronze',
    wins = 0,
    losses = 0,
    chases_played = 0,
    escapes_played = 0;

-- Update schema defaults
ALTER TABLE players ALTER COLUMN mmr SET DEFAULT 500;
ALTER TABLE players MODIFY `tier` ENUM('bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist') NOT NULL DEFAULT 'bronze';
