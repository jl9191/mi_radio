fx_version 'cerulean'
game 'gta5'

description 'Radio para autos con búsqueda de YouTube'
author 'Antigravity'
version '1.0.0'

client_scripts {
    'config.lua',
    'client.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js'
}

dependencies {
    'xsound'
}
