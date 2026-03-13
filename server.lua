local VehicleRadios = {}

-- ============================================================
-- HELPERS
-- ============================================================

-- Duración máxima permitida (segundos). Evita que un cliente
-- envíe valores absurdos para manipular el sistema.
local MAX_DURATION = 10800 -- 3 horas

-- Devuelve la placa del vehículo que ocupa el jugador (src).
-- Retorna nil si no está en ningún vehículo.
local function getPlayerVehiclePlate(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return nil end
    local plate = string.gsub(GetVehicleNumberPlateText(veh) or "", "%s+", "")
    return plate ~= "" and plate or nil
end

-- Actualiza el timestamp acumulado de forma segura.
-- FIX: Centralizar esto evita la doble-suma que ocurría cuando
-- requestState y el thread de limpieza se ejecutaban casi al mismo tiempo.
local function refreshTimestamp(data)
    if not data.isPaused then
        local now = os.time()
        local diff = now - data.lastUpdate
        if diff > 0 then
            data.timestamp = data.timestamp + diff
            data.lastUpdate = now
        end
    end
end

-- ============================================================
-- EVENTOS
-- ============================================================

-- Sincronizar cuando alguien entra al vehículo o abre la radio
RegisterNetEvent('mi_radio:server:requestState', function(plate)
    local src = source
    if VehicleRadios[plate] then
        local data = VehicleRadios[plate]
        -- Refrescar antes de enviar para que el cliente reciba el tiempo exacto.
        refreshTimestamp(data)
        TriggerClientEvent('mi_radio:client:syncRadio', src, plate, data)
    else
        TriggerClientEvent('mi_radio:client:syncStop', src, plate)
    end
end)

-- Reproducir música
-- FIX: Validamos que el jugador realmente esté en el vehículo con esa placa.
-- Sin esto, cualquier cliente podría cambiar la radio de un coche ajeno.
RegisterNetEvent('mi_radio:server:playMusic', function(plate, url, title, duration)
    local src = source

    -- Validación de ownership
    local realPlate = getPlayerVehiclePlate(src)
    if realPlate ~= plate then return end

    -- Sanitización de inputs
    if type(url) ~= "string" or url == "" then return end
    if type(title) ~= "string" or title == "" then title = "Sin título" end

    -- FIX: Clampear duration para evitar manipulación.
    -- duration = 0 es válido (streams sin duración conocida).
    local dur = math.max(0, math.min(tonumber(duration) or 0, MAX_DURATION))

    VehicleRadios[plate] = {
        url        = url,
        title      = title,
        duration   = dur,
        isPaused   = false,
        timestamp  = 0,
        lastUpdate = os.time()
    }
    TriggerClientEvent('mi_radio:client:syncRadio', -1, plate, VehicleRadios[plate])
end)

-- Detener música
-- FIX: Validamos ownership
RegisterNetEvent('mi_radio:server:stopMusic', function(plate)
    local src = source
    local realPlate = getPlayerVehiclePlate(src)
    if realPlate ~= plate then return end

    if VehicleRadios[plate] then
        VehicleRadios[plate] = nil
        TriggerClientEvent('mi_radio:client:syncStop', -1, plate)
    end
end)

-- Pausar música
-- FIX: Validamos ownership
RegisterNetEvent('mi_radio:server:pauseMusic', function(plate)
    local src = source
    local realPlate = getPlayerVehiclePlate(src)
    if realPlate ~= plate then return end

    if VehicleRadios[plate] and not VehicleRadios[plate].isPaused then
        refreshTimestamp(VehicleRadios[plate])
        VehicleRadios[plate].isPaused = true
        TriggerClientEvent('mi_radio:client:syncPause', -1, plate)
    end
end)

-- Reanudar música
-- FIX: Validamos ownership
RegisterNetEvent('mi_radio:server:resumeMusic', function(plate)
    local src = source
    local realPlate = getPlayerVehiclePlate(src)
    if realPlate ~= plate then return end

    if VehicleRadios[plate] and VehicleRadios[plate].isPaused then
        VehicleRadios[plate].isPaused  = false
        VehicleRadios[plate].lastUpdate = os.time()
        TriggerClientEvent('mi_radio:client:syncResume', -1, plate)
    end
end)

-- Adelantar / retroceder
-- FIX: Validamos ownership y clampemos newTime al rango válido
RegisterNetEvent('mi_radio:server:seekMusic', function(plate, newTime)
    local src = source
    local realPlate = getPlayerVehiclePlate(src)
    if realPlate ~= plate then return end

    if VehicleRadios[plate] then
        local dur  = VehicleRadios[plate].duration
        local maxT = dur > 0 and dur or MAX_DURATION
        newTime = math.max(0, math.min(tonumber(newTime) or 0, maxT))

        VehicleRadios[plate].timestamp  = newTime
        VehicleRadios[plate].lastUpdate = os.time()
        TriggerClientEvent('mi_radio:client:syncSeek', -1, plate, newTime)
    end
end)

-- Limpieza automática cuando un vehículo es eliminado
AddEventHandler('entityRemoved', function(entity)
    if GetEntityType(entity) == 2 then
        local plate = string.gsub(GetVehicleNumberPlateText(entity) or "", "%s+", "")
        if plate ~= "" and VehicleRadios[plate] then
            VehicleRadios[plate] = nil
            TriggerClientEvent('mi_radio:client:syncStop', -1, plate)
        end
    end
end)

-- Thread para limpiar canciones terminadas
-- FIX: Usamos refreshTimestamp() en lugar de recalcular el diff manualmente,
-- evitando la doble-suma con requestState.
CreateThread(function()
    while true do
        Wait(5000)
        for plate, data in pairs(VehicleRadios) do
            refreshTimestamp(data)
            if data.duration > 0 and data.timestamp >= data.duration then
                VehicleRadios[plate] = nil
                TriggerClientEvent('mi_radio:client:syncStop', -1, plate)
            end
        end
    end
end)
