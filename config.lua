Config = {}

-- YouTube Data API v3 Key (Obligatorio para la búsqueda)
-- Consíguelo en: https://console.cloud.google.com → APIs → YouTube Data API v3
Config.YoutubeApiKey = "AIzaSyB0ZVpU-4M2pvWg6_-mQzcQ5CVyvx9JCII"

-- Comando para abrir la radio
Config.Command = "carradiov3"

-- Distancia máxima para escuchar la radio (si se implementa sincronización externa)
Config.MaxDistance = 20.0

-- Nombres de vehículos o clases que NO pueden usar la radio (opcional)
Config.BlacklistedVehicles = {
    -- "bmx",
}
