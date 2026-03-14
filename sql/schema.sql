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

-- Seed vehicle catalog (ranked tier cars only; addon cars are in separate SQL files)
INSERT INTO `vehicle_catalog` (`model`, `label`, `tier`, `class`, `top_speed`) VALUES
-- Bronze (~105 mph)
('gbcometcl', 'Comet Classic', 'bronze', 'sports', 105.0),
('rh4', 'Annis RH4', 'bronze', 'classic', 105.0),
('ballerc', 'Baller Classic', 'bronze', 'suv', 105.0),
('futo', 'Karin Futo', 'bronze', 'sports', 105.0),

-- Silver (~115 mph)
('gbcometclf', 'Comet Classic Florio', 'silver', 'sports', 115.0),
('gbretinueloz', 'Retinue Loz', 'silver', 'sports', 115.0),
('gbschrauber', 'Schrauber', 'silver', 'sports', 115.0),
('tailgater2', 'Tailgater S', 'silver', 'sports', 115.0),

-- Gold (~125 mph)
('roxanne', 'Roxanne', 'gold', 'sports', 125.0),
('buffaloh', 'Buffalo S Hellhound', 'gold', 'sedan', 125.0),
('jester5', 'Jester', 'gold', 'sports', 125.0),
('sent6', 'Sentinel 6', 'gold', 'sports', 125.0),
('gbgresleystx', 'Gresley STX', 'gold', 'sports', 125.0),

-- Platinum (~135 mph)
('gbargento7f', 'Argento 7F', 'platinum', 'sports', 135.0),
('gbsolace', 'Solace', 'platinum', 'sports', 135.0),
('gbsultanrsx', 'Sultan RSX', 'platinum', 'sports', 135.0),

-- Diamond (~145 mph)
('gbtr3s', 'TR3S', 'diamond', 'sports', 145.0),

-- Blacklist (~155 mph)
('gsttoros1', 'GST Toros', 'blacklist', 'suv', 155.0),
('gbcomets2r', 'Comet S2R', 'blacklist', 'sports', 155.0)

ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `tier` = VALUES(`tier`), `top_speed` = VALUES(`top_speed`);

-- ============================================================
-- Player reports
-- ============================================================
CREATE TABLE IF NOT EXISTS `player_reports` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `match_id` INT UNSIGNED DEFAULT NULL,
    `reporter_id` VARCHAR(64) NOT NULL,
    `reporter_name` VARCHAR(128) NOT NULL DEFAULT '',
    `reported_id` VARCHAR(64) NOT NULL DEFAULT '',
    `reported_name` VARCHAR(128) NOT NULL DEFAULT '',
    `reason` VARCHAR(64) NOT NULL,
    `mode` VARCHAR(32) NOT NULL DEFAULT 'unknown',
    `status` ENUM('pending', 'reviewed', 'actioned', 'dismissed') NOT NULL DEFAULT 'pending',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_reported` (`reported_id`, `created_at` DESC),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB;
