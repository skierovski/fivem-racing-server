-- Reset ALL vehicles to 'custom' tier (removes old tier assignments)
UPDATE vehicle_catalog SET tier = 'custom' WHERE tier != 'custom';

-- Bronze tier
UPDATE vehicle_catalog SET tier = 'bronze' WHERE model IN ('gbcometcl', 'rh4', 'ballerc', 'futo');

-- Silver tier
UPDATE vehicle_catalog SET tier = 'silver' WHERE model IN ('gbcometclf', 'gbretinueloz', 'gbschrauber');

-- Gold tier
UPDATE vehicle_catalog SET tier = 'gold' WHERE model IN ('roxanne', 'buffaloh', 'jester5', 'sent6', 'gbgresleystx');

-- Platinum tier
UPDATE vehicle_catalog SET tier = 'platinum' WHERE model IN ('gbargento7f', 'gbsolace', 'gbsultanrsx');

-- Diamond tier
UPDATE vehicle_catalog SET tier = 'diamond' WHERE model IN ('gbtr3s');

-- Blacklist tier
UPDATE vehicle_catalog SET tier = 'blacklist' WHERE model IN ('gsttoros1', 'gbcomets2r');
