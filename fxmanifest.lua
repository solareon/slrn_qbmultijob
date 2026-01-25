fx_version 'cerulean'
game 'gta5'
version '1.0.6'

lua54 'yes'

title 'SLRN Multijob'
description 'QB-Core multijob application for LB-Phone'
author 'solareon.'
version '1.0.6'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/cl_main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_main.lua',
}

files {
    'ui/**/*'
}

ui_page 'ui/index.html'

dependency 'lb-phone'