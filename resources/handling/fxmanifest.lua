fx_version 'cerulean'
game 'gta5'

author 'BlackList Racing'
description 'Base game car handling overrides (futo)'
version '1.0.0'

server_script 'server.lua'
client_script 'client.lua'

files {
    'bronze/*.meta',
}

-- Futo is a base game car with no addon resource, so its handling override lives here
data_file 'HANDLING_FILE' 'bronze/futo.meta'
