fx_version 'cerulean'
game 'gta5'

author 'BlackList Racing'
description 'Benny\'s garage tuning system'
version '1.0.0'

ui_page 'html/index.html'

client_script 'client.lua'
server_script 'server.lua'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/icon-hood.png',
    'html/icon-trunk.png',
    'html/icon-door-front.png',
    'html/icon-door-rear.png',
    'data/colors.json',
    'data/wheel_types.json',
}

dependencies { 'oxmysql', 'lib' }
