-- ============================================================
-- BlackList Racing - Database Schema
-- ============================================================

CREATE DATABASE IF NOT EXISTS `blacklist_racing`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `blacklist_racing`;

-- ============================================================
-- Players
-- ============================================================
CREATE TABLE IF NOT EXISTS `players` (
    `identifier` VARCHAR(64) NOT NULL,
    `discord_id` VARCHAR(32) DEFAULT NULL,
    `name` VARCHAR(128) NOT NULL DEFAULT 'Unknown',
    `mmr` INT NOT NULL DEFAULT 500,
    `tier` ENUM('bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist') NOT NULL DEFAULT 'bronze',
    `wins` INT UNSIGNED NOT NULL DEFAULT 0,
    `losses` INT UNSIGNED NOT NULL DEFAULT 0,
    `chases_played` INT UNSIGNED NOT NULL DEFAULT 0,
    `escapes_played` INT UNSIGNED NOT NULL DEFAULT 0,
    `selected_vehicle` VARCHAR(64) DEFAULT NULL,
    `is_online` TINYINT(1) NOT NULL DEFAULT 0,
    `last_seen` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`),
    INDEX `idx_mmr` (`mmr` DESC),
    INDEX `idx_tier` (`tier`),
    INDEX `idx_discord` (`discord_id`)
) ENGINE=InnoDB;

-- ============================================================
-- Player vehicles (garage with tuning)
-- ============================================================
CREATE TABLE IF NOT EXISTS `player_vehicles` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64) NOT NULL,
    `model` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NOT NULL DEFAULT '',
    `tier` ENUM('bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist', 'custom') NOT NULL DEFAULT 'bronze',
    `tuning` JSON DEFAULT NULL,
    `is_selected` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_owner` (`identifier`),
    INDEX `idx_owner_selected` (`identifier`, `is_selected`),
    CONSTRAINT `fk_vehicle_owner` FOREIGN KEY (`identifier`) REFERENCES `players`(`identifier`) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ============================================================
-- Match history
-- ============================================================
CREATE TABLE IF NOT EXISTS `match_history` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `mode` ENUM('ranked', 'normal') NOT NULL,
    `chaser_ids` JSON NOT NULL,
    `runner_id` VARCHAR(64) NOT NULL,
    `winner_role` ENUM('chaser', 'runner') NOT NULL,
    `winner_id` VARCHAR(64) NOT NULL,
    `duration_seconds` INT UNSIGNED NOT NULL DEFAULT 300,
    `max_distance` FLOAT DEFAULT NULL,
    `mmr_change_runner` INT DEFAULT 0,
    `mmr_change_chaser` INT DEFAULT 0,
    `start_location` VARCHAR(128) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_runner` (`runner_id`),
    INDEX `idx_winner` (`winner_id`),
    INDEX `idx_mode` (`mode`),
    INDEX `idx_created` (`created_at` DESC)
) ENGINE=InnoDB;

-- ============================================================
-- BlackList view (top 20 by MMR)
-- ============================================================
CREATE OR REPLACE VIEW `blacklist_top20` AS
SELECT
    `identifier`,
    `name`,
    `mmr`,
    `tier`,
    `wins`,
    `losses`,
    `chases_played`,
    `escapes_played`,
    RANK() OVER (ORDER BY `mmr` DESC) AS `position`
FROM `players`
ORDER BY `mmr` DESC
LIMIT 20;

-- ============================================================
-- Chat messages (optional history)
-- ============================================================
CREATE TABLE IF NOT EXISTS `chat_messages` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64) NOT NULL,
    `player_name` VARCHAR(128) NOT NULL,
    `tier` VARCHAR(16) DEFAULT 'bronze',
    `message` TEXT NOT NULL,
    `channel` VARCHAR(32) NOT NULL DEFAULT 'global',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_channel_time` (`channel`, `created_at` DESC)
) ENGINE=InnoDB;

-- ============================================================
-- Tier thresholds reference (for app logic, not enforced in DB)
-- ============================================================
-- Bronze:    0 - 499
-- Silver:    500 - 999
-- Gold:      1000 - 1499
-- Platinum:  1500 - 1999
-- Diamond:   2000 - 2499
-- BlackList: Top 20 players with MMR >= 2500

-- ============================================================
-- Vehicle catalog (reference data - which cars exist per tier)
-- ============================================================
CREATE TABLE IF NOT EXISTS `vehicle_catalog` (
    `model` VARCHAR(64) NOT NULL,
    `label` VARCHAR(128) NOT NULL,
    `tier` ENUM('bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist', 'custom') NOT NULL,
    `class` VARCHAR(32) NOT NULL DEFAULT 'sports',
    `top_speed` FLOAT DEFAULT NULL,
    `image_url` VARCHAR(256) DEFAULT NULL,
    PRIMARY KEY (`model`),
    INDEX `idx_tier` (`tier`)
) ENGINE=InnoDB;

-- Seed vehicle catalog
INSERT INTO `vehicle_catalog` (`model`, `label`, `tier`, `class`, `top_speed`) VALUES
-- Bronze tier (street cars, slower)
('futo', 'Karin Futo', 'bronze', 'sports', 125.0),
('sultan', 'Karin Sultan', 'bronze', 'sports', 130.0),
('blista', 'Dinka Blista', 'bronze', 'compact', 120.0),
('penumbra', 'Maibatsu Penumbra', 'bronze', 'sports', 128.0),
('prairie', 'Bollokan Prairie', 'bronze', 'compact', 122.0),
('kuruma', 'Karin Kuruma', 'bronze', 'sports', 132.0),

-- Silver tier
('feltzer2', 'Benefactor Feltzer', 'silver', 'sports', 140.0),
('jester', 'Dinka Jester', 'silver', 'sports', 145.0),
('massacro', 'Dewbauchee Massacro', 'silver', 'sports', 143.0),
('elegy2', 'Annis Elegy RH8', 'silver', 'sports', 142.0),
('carbonizzare', 'Grotti Carbonizzare', 'silver', 'sports', 144.0),
('comet2', 'Pfister Comet', 'silver', 'sports', 141.0),

-- Gold tier
('schafter3', 'Benefactor Schafter V12', 'gold', 'sports', 155.0),
('surano', 'Benefactor Surano', 'gold', 'sports', 152.0),
('ninef', 'Obey 9F', 'gold', 'sports', 150.0),
('rapidgt', 'Dewbauchee Rapid GT', 'gold', 'sports', 153.0),
('coquette', 'Invetero Coquette', 'gold', 'sports', 156.0),
('banshee', 'Bravado Banshee', 'gold', 'sports', 158.0),

-- Platinum tier
('turismor', 'Grotti Turismo R', 'platinum', 'super', 165.0),
('zentorno', 'Pegassi Zentorno', 'platinum', 'super', 168.0),
('entityxf', 'Overflod Entity XF', 'platinum', 'super', 166.0),
('infernus', 'Pegassi Infernus', 'platinum', 'super', 162.0),
('vacca', 'Pegassi Vacca', 'platinum', 'super', 160.0),
('bullet', 'Vapid Bullet', 'platinum', 'super', 163.0),

-- Diamond tier
('t20', 'Progen T20', 'diamond', 'super', 175.0),
('osiris', 'Pegassi Osiris', 'diamond', 'super', 173.0),
('reaper', 'Pegassi Reaper', 'diamond', 'super', 172.0),
('fmj', 'Vapid FMJ', 'diamond', 'super', 174.0),
('nero', 'Truffade Nero', 'diamond', 'super', 176.0),
('tempesta', 'Pegassi Tempesta', 'diamond', 'super', 171.0),

-- BlackList tier (fastest / most exotic)
('emerus', 'Progen Emerus', 'blacklist', 'super', 185.0),
('krieger', 'Benefactor Krieger', 'blacklist', 'super', 188.0),
('s80rr', 'Annis S80RR', 'blacklist', 'super', 183.0),
('deveste', 'Principe Deveste Eight', 'blacklist', 'super', 190.0),
('thrax', 'Truffade Thrax', 'blacklist', 'super', 186.0),
('tigon', 'Lampadati Tigon', 'blacklist', 'super', 184.0)

ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
