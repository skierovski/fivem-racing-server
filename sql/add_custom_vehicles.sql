-- ============================================================
-- Add 'custom' tier for PixaCars testing vehicles
-- ============================================================

USE `blacklist_racing`;

-- Add 'custom' to tier ENUMs
ALTER TABLE `vehicle_catalog`
    MODIFY `tier` ENUM('bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist', 'custom') NOT NULL;

ALTER TABLE `player_vehicles`
    MODIFY `tier` ENUM('bronze', 'silver', 'gold', 'platinum', 'diamond', 'blacklist', 'custom') NOT NULL DEFAULT 'bronze';

-- Insert PixaCars into vehicle_catalog
INSERT INTO `vehicle_catalog` (`model`, `label`, `tier`, `class`) VALUES
-- Klasyki (Classics)
('callista', 'Callista', 'custom', 'classic'),
('coqvice', 'Coquette Vice', 'custom', 'classic'),
('espexecutive', 'Esperanto Executive', 'custom', 'classic'),
('rh4', 'Annis RH4', 'custom', 'classic'),
('turismo2lm', 'Turismo LM', 'custom', 'classic'),
-- Muscle
('gauntlets', 'Gauntlet S', 'custom', 'muscle'),
('jdvigeror', 'Vigero Rumbler', 'custom', 'muscle'),
('vulture', 'Vulture', 'custom', 'muscle'),
-- Sedany (Sedans)
('asteropers', 'Asterope RS', 'custom', 'sedan'),
('buffaloh', 'Buffalo S Hellhound', 'custom', 'sedan'),
('cypherct', 'Cypher Hatchback', 'custom', 'sedan'),
('sentinelp', 'Sentinel Sedan', 'custom', 'sedan'),
('superd3', 'Super Diamond', 'custom', 'sedan'),
('vincent2', 'Vincent', 'custom', 'sedan'),
-- Sportowe (Sports)
('as_nexus', 'Nexus', 'custom', 'sports'),
('as_zr350', 'ZR350', 'custom', 'sports'),
('blis2gpr', 'Blista GPR', 'custom', 'sports'),
('buffalo4h', 'Buffalo Hellfire', 'custom', 'sports'),
('estancia', 'Estancia', 'custom', 'sports'),
('gauntletctx', 'Hellfire CTX', 'custom', 'sports'),
('jester5', 'Jester', 'custom', 'sports'),
('paragonxr', 'Paragon FR', 'custom', 'sports'),
('pentro', 'Pentro', 'custom', 'sports'),
('revolutionw', 'Revolucion', 'custom', 'sports'),
('elegyrh5', 'RH5', 'custom', 'sports'),
('elegyx', 'RH8-X', 'custom', 'sports'),
('roxanne', 'Roxanne', 'custom', 'sports'),
('schlagenstr', 'Schlagen STR', 'custom', 'sports'),
('remustwo', 'Remus Two', 'custom', 'sports'),
('sultanrsv8', 'Sultan RS V8', 'custom', 'sports'),
('supergts', 'Super GTS', 'custom', 'sports'),
('gstvectre1', 'Vectre GOM', 'custom', 'sports'),
-- Supercars
('cycloneex0', 'Cyclone EX-0', 'custom', 'super'),
('mf1', 'MF1', 'custom', 'super'),
('nerops', 'Nero Pur Sport', 'custom', 'super'),
('osirisr', 'Osiris R', 'custom', 'super'),
('sheavas', 'Sheavas', 'custom', 'super'),
('tempestaes', 'Tempesta Evo', 'custom', 'super'),
('tempestafr', 'Tempesta FR', 'custom', 'super'),
-- SUVs
('nscout', '2020 Scout', 'custom', 'suv'),
('ballerc', 'Baller Classic', 'custom', 'suv'),
('dubsta22', 'Dubsta 22', 'custom', 'suv'),
('gresleyh', 'Gresley Hell', 'custom', 'suv'),
-- Terenowe (Off-road)
('caracaran', 'Caracara 2022', 'custom', 'offroad'),
('mesaxl', 'Mesa Gator', 'custom', 'offroad'),
('nsandstorm', 'Sandstorm', 'custom', 'offroad'),
-- Test/GOM
('benefacgt', 'Benefactor GT', 'custom', 'sports'),
('fx7r', 'FX7R', 'custom', 'sports'),
('gstarg2', 'GST Arg2', 'custom', 'sports'),
('gstbisxl3', 'GST Bisxl3', 'custom', 'sports'),
('gstbufst1', 'GST Buffalo ST', 'custom', 'sports'),
('gstgauntc2', 'GST Gauntlet C2', 'custom', 'muscle'),
('gstsadlt1', 'GST Sadler T1', 'custom', 'offroad'),
('gstsg71', 'GST SG71', 'custom', 'sports'),
('pbbgtsj', 'PBB GTS J', 'custom', 'sports'),
('sent6', 'Sentinel 6', 'custom', 'sports'),
('gsttoros1', 'GST Toros', 'custom', 'suv'),
('hycrh7', 'RH7 HYC', 'custom', 'sports')
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `tier` = VALUES(`tier`);
