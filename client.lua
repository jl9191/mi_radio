local QBCore = exports['qb-core']:GetCoreObject()
local isGuiOpen = false

-- Estado por vehículo: vehicleRadios[plate] = { soundId, vehicle, timeStamp, maxDuration, isPaused, volume, title, url }
local vehicleRadios = {}

-- Última placa del vehículo en que estamos (para detectar cambio de vehículo)
local lastVehiclePlate = nil

-- Helper: obtener placa limpia de un vehículo
function getPlate(vehicle)
    if vehicle == 0 then return nil end
    return string.gsub(GetVehicleNumberPlateText(vehicle), "%s+", "")
end

-- Helper: obtener la radio del vehículo actual del jugador
function getActiveRadio()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil, nil, nil end
    local plate = getPlate(veh)
    return plate, vehicleRadios[plate], veh
end

-- Función para abrir/cerrar la radio
function toggleRadio(status)
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    if status then
        if vehicle ~= 0 then
            isGuiOpen = true
            SetNuiFocus(true, true)
            SendNUIMessage({
                type = "show",
                status = true,
                apiKey = Config.YoutubeApiKey
            })

            -- Sincronizar UI con el estado actual de este vehículo
            local plate = getPlate(vehicle)
            local radio = vehicleRadios[plate]

            if radio and exports.xsound:soundExists(radio.soundId) then
                -- Hay radio activa en este vehículo, sincronizar NUI
                SendNUIMessage({
                    type = "syncState",
                    title = radio.title or "Desconocido",
                    isPlaying = not radio.isPaused,
                    currentTime = radio.timeStamp,
                    maxDuration = radio.maxDuration,
                    volume = radio.volume or 0.5
                })
            else
                -- No hay radio activa, resetear NUI
                SendNUIMessage({
                    type = "syncState",
                    title = nil,
                    isPlaying = false,
                    currentTime = 0,
                    maxDuration = 0,
                    volume = 0.5
                })
            end
        else
            QBCore.Functions.Notify("Debes estar en un vehiculo para usar la radio", "error")
        end
    else
        isGuiOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({
            type = "show",
            status = false
        })
    end
end

-- Comando para abrir la radio
RegisterCommand(Config.Command, function()
    toggleRadio(not isGuiOpen)
end)

-- Callback para cerrar la radio desde el NUI
RegisterNUICallback('close', function(data, cb)
    toggleRadio(false)
    cb('ok')
end)

-- Callback para reproducir música
RegisterNUICallback('playMusic', function(data, cb)
    local url = data.url
    local title = data.title or "Desconocido"
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)

    if vehicle ~= 0 then
        local plate = getPlate(vehicle)
        local soundId = "radio_" .. plate

        -- Si este vehículo ya tiene radio activa, destruirla primero
        if vehicleRadios[plate] and vehicleRadios[plate].soundId then
            if exports.xsound:soundExists(vehicleRadios[plate].soundId) then
                exports.xsound:Destroy(vehicleRadios[plate].soundId)
            end
        end

        -- Crear sonido posicional en la posición del vehículo
        local vehCoords = GetEntityCoords(vehicle)
        exports.xsound:PlayUrlPos(soundId, url, 0.5, vehCoords, false)
        exports.xsound:Distance(soundId, Config.MaxDistance)

        -- Guardar estado para este vehículo
        vehicleRadios[plate] = {
            soundId = soundId,
            vehicle = vehicle,
            timeStamp = 0,
            maxDuration = data.duration or 0,
            isPaused = false,
            volume = 0.5,
            title = title,
            url = url
        }
    end
    cb('ok')
end)

-- Callback para pausar
RegisterNUICallback('pauseMusic', function(data, cb)
    local plate, radio = getActiveRadio()
    if radio and radio.soundId then
        exports.xsound:Pause(radio.soundId)
        radio.isPaused = true
    end
    cb('ok')
end)

-- Callback para reanudar
RegisterNUICallback('resumeMusic', function(data, cb)
    local plate, radio = getActiveRadio()
    if radio and radio.soundId then
        exports.xsound:Resume(radio.soundId)
        radio.isPaused = false
    end
    cb('ok')
end)

-- Callback para cambiar volumen
RegisterNUICallback('setVolume', function(data, cb)
    local plate, radio = getActiveRadio()
    if radio and radio.soundId then
        exports.xsound:setVolume(radio.soundId, data.volume)
        radio.volume = data.volume
    end
    cb('ok')
end)

-- Callback para adelantar/retroceder (offset en segundos)
RegisterNUICallback('seekMusic', function(data, cb)
    local plate, radio = getActiveRadio()
    if radio and radio.soundId and exports.xsound:soundExists(radio.soundId) then
        local offset = data.offset or 0
        local newTime = radio.timeStamp + offset

        if newTime < 0 then newTime = 0 end

        local maxDuration = exports.xsound:getMaxDuration(radio.soundId) or 0
        if maxDuration <= 0 then maxDuration = radio.maxDuration end
        if maxDuration > 0 and newTime > maxDuration then
            newTime = maxDuration
        end

        exports.xsound:setTimeStamp(radio.soundId, newTime)
        radio.timeStamp = newTime
    end
    cb('ok')
end)

-- Callback para seek por porcentaje (barra de progreso)
RegisterNUICallback('seekToPercent', function(data, cb)
    local plate, radio = getActiveRadio()
    if radio and radio.soundId and exports.xsound:soundExists(radio.soundId) then
        local maxDuration = exports.xsound:getMaxDuration(radio.soundId) or 0
        if maxDuration <= 0 then maxDuration = radio.maxDuration end
        if maxDuration > 0 then
            local newTime = math.floor(maxDuration * data.percent)
            exports.xsound:setTimeStamp(radio.soundId, newTime)
            radio.timeStamp = newTime
        end
    end
    cb('ok')
end)

-- Callback para detener la música
RegisterNUICallback('stopMusic', function(data, cb)
    local plate, radio = getActiveRadio()
    if radio and radio.soundId then
        if exports.xsound:soundExists(radio.soundId) then
            exports.xsound:Destroy(radio.soundId)
        end
        vehicleRadios[plate] = nil
    end
    cb('ok')
end)

-- Thread para actualizar la posición del sonido con la del vehículo (TODOS los vehículos activos)
CreateThread(function()
    while true do
        Wait(250)
        for plate, radio in pairs(vehicleRadios) do
            if radio.vehicle and DoesEntityExist(radio.vehicle) then
                if exports.xsound:soundExists(radio.soundId) then
                    local vehCoords = GetEntityCoords(radio.vehicle)
                    exports.xsound:Position(radio.soundId, vehCoords)
                end
            else
                -- Vehículo eliminado/despawneado, limpiar
                if exports.xsound:soundExists(radio.soundId) then
                    exports.xsound:Destroy(radio.soundId)
                end
                vehicleRadios[plate] = nil
            end
        end
    end
end)

-- Thread para contar el tiempo local y enviar progreso al NUI (solo del vehículo actual)
CreateThread(function()
    while true do
        Wait(1000)

        -- Actualizar timestamps de TODAS las radios activas
        for plate, radio in pairs(vehicleRadios) do
            if not radio.isPaused and exports.xsound:soundExists(radio.soundId) then
                radio.timeStamp = radio.timeStamp + 1

                -- Si superó la duración, marcar como terminada
                if radio.maxDuration > 0 and radio.timeStamp >= radio.maxDuration then
                    radio.timeStamp = radio.maxDuration
                    radio.isPaused = true
                end

                -- Sincronizar con xsound si tiene datos reales
                local xsoundTime = exports.xsound:getTimeStamp(radio.soundId) or 0
                local xsoundMax = exports.xsound:getMaxDuration(radio.soundId) or 0
                if xsoundMax > 0 then
                    radio.timeStamp = xsoundTime
                    radio.maxDuration = xsoundMax
                end
            end
        end

        -- Enviar progreso al NUI solo del vehículo actual
        if isGuiOpen then
            local plate, radio = getActiveRadio()
            if radio then
                SendNUIMessage({
                    type = "updateProgress",
                    currentTime = radio.timeStamp,
                    maxDuration = radio.maxDuration
                })
            end
        end
    end
end)

-- Thread para detectar cambio de vehículo y sincronizar estado de la radio
CreateThread(function()
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local currentPlate = nil

        if veh ~= 0 then
            currentPlate = getPlate(veh)
        end

        -- Detectar si cambió de vehículo
        if currentPlate ~= lastVehiclePlate then
            lastVehiclePlate = currentPlate

            -- Si la GUI está abierta y cambiamos de vehículo, cerrarla
            if isGuiOpen then
                toggleRadio(false)
            end
        end
    end
end)
