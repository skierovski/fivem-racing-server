-- Fix Paprycjusz: sync is_selected with players.selected_vehicle
-- No vehicle had is_selected=1, so GetPlayerVehicle returned fallback (futo, empty tuning)

USE blacklist_racing;

-- Clear all is_selected for this player
UPDATE player_vehicles SET is_selected = 0
WHERE identifier = 'license:6bcb5b36ccd92bb9ebcf0d8748d3164b6b50c5dd';

-- Set gbschrauber as selected (matches players.selected_vehicle)
UPDATE player_vehicles SET is_selected = 1
WHERE identifier = 'license:6bcb5b36ccd92bb9ebcf0d8748d3164b6b50c5dd'
  AND model = 'gbschrauber';
