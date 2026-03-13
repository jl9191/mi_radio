# 🎵 Mi Radio v3 — Radio para Autos (FiveM)

Radio de vehículo con búsqueda de YouTube y soporte para URLs directas. Cada auto tiene su propia radio independiente y los jugadores cercanos pueden escucharla.

## Requisitos

- **QBCore Framework**
- **[xsound](https://github.com/Starter-xsound/xsound)** — recurso de audio

## Instalación

1. Coloca la carpeta `mi_radio` en tu directorio de resources
2. Agrega `ensure mi_radio` en tu `server.cfg` (después de `xsound` y `qb-core`)
3. Reinicia el servidor

## Configuración

Edita `config.lua`:

```lua
Config.Command = "carradio"   -- Comando para abrir la radio
Config.MaxDistance = 20.0        -- Distancia en metros que otros jugadores escuchan la música
```

## Uso

1. Entra a un vehículo
2. Escribe `/carradiov3` en el chat
3. Busca una canción o pega una URL directa (YouTube, .mp3, .ogg, etc.)
4. Usa los controles: ▶️ Play/Pause, ⏹️ Stop, ⏩ +15s, ⏪ -15s, 🔊 Volumen

## Características

- 🔍 Búsqueda de YouTube integrada
- 🔗 Soporte para URLs directas (mp3, ogg, wav, etc.)
- 🚗 Radios independientes por vehículo (múltiples autos con música simultáneamente)
- 🔊 Audio 3D posicional — otros jugadores cercanos escuchan la música
- 🎛️ Controles: play, pause, stop, adelantar, retroceder, volumen, barra de progreso
- 🧹 Limpieza automática al eliminar/despawnear el vehículo
