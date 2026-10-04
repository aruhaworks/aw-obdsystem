fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'aw-obdsystem'
author 'ARUHAWORKS'
description 'ARUHAWORKS OBD-II Diagnostic Terminal'
version '2.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/server.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

dependencies {
    'oxmysql'
}
