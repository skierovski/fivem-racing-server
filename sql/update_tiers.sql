-- Reset ALL vehicles to 'custom' tier (removes old tier assignments)
UPDATE vehicle_catalog SET tier = 'custom' WHERE tier != 'custom';

-- Bronze tier
UPDATE vehicle_catalog SET tier = 'bronze' WHERE model IN ('gb_cometcl', 'rh4', 'ballerc', 'futo');

-- Silver tier
UPDATE vehicle_catalog SET tier = 'silver' WHERE model IN ('gb_cometclf', 'gb_retinueloz', 'gb_schrauber');

-- Gold tier
UPDATE vehicle_catalog SET tier = 'gold' WHERE model IN ('roxanne', 'buffaloh', 'jester5', 'sent6', 'gb_gresleystx');

-- Platinum tier
UPDATE vehicle_catalog SET tier = 'platinum' WHERE model IN ('gb_argento7f', 'gb_solace', 'gb_sultanrsx');

-- Diamond tier
UPDATE vehicle_catalog SET tier = 'diamond' WHERE model IN ('gb_tr3s');

-- Blacklist tier
UPDATE vehicle_catalog SET tier = 'blacklist' WHERE model IN ('gsttoros1', 'gb_comets2r');
