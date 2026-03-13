local QBCore = exports['qb-core']:GetCoreObject()
local isGuiOpen    = false
local currentSoundId  = nil
local currentVehicle  = nil

-- Rastreador de todas las radios que este cliente está reproduciendo (plate -> url)
local trackedRadios = {}
-- Caché de entidades de vehículos para optimizar el thread de posición (plate -> entity)
local activeVehicles = {}
-- Caché de vehículos que NO tienen música (evita spamear al servidor)
local emptyRadios = {}

-- Tracker de tiempo local
-- FIX (drift): En lugar de sumar +1 por cada Wait(1000) (impreciso),
-- guardamos el os.clock() real del último tick y sumamos la diferencia exacta.
local localTimeStamp  = 0
local localMaxDuration = 0
local localIsPaused   = false
local localLastTick   = 0  -- GetGameTimer() del último tick procesado

-- ============================================================
-- HELPERS
-- ============================================================

local function getVehicleFromPlate(plate)
    if activeVehicles[plate] and DoesEntityExist(activeVehicles[plate]) then
        return activeVehicles[plate]
    end
    local vehicles = GetGamePool('CVehicle')
    for _, veh in ipairs(vehicles) do
        local vehPlate = string.gsub(GetVehicleNumberPlateText(veh), "%s+", "")
        if vehPlate == plate then
            activeVehicles[plate] = veh
            return veh
        end
    end
    return nil
end

-- ============================================================
-- RADIO TOGGLE
-- ============================================================

function toggleRadio(status)
    local playerPed = PlayerPedId()
    local vehicle   = GetVehiclePedIsIn(playerPed, false)

    if status then
        if vehicle ~= 0 then
            isGuiOpen    = true
            SetNuiFocus(true, true)

            -- Reset de variables de sesión al abrir
            currentSoundId  = nil
            currentVehicle  = vehicle
            localTimeStamp  = 0
            localMaxDuration = 0
            localIsPaused   = false
            localLastTick   = GetGameTimer()

            local plate = string.gsub(GetVehicleNumberPlateText(vehicle), "%s+", "")
            TriggerServerEvent('mi_radio:server:requestState', plate)

            SendNUIMessage({ type = "show", status = true })
        else
            QBCore.Functions.Notify("Debes estar en un vehiculo para usar la radio", "error")
        end
    else
        isGuiOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ type = "show", status = false })
    end
end

RegisterCommand(Config.Command, function()
    toggleRadio(not isGuiOpen)
end)

-- ============================================================
-- NUI CALLBACKS
-- ============================================================

RegisterNUICallback('close', function(data, cb)
    toggleRadio(false)
    cb('ok')
end)

RegisterNUICallback('playMusic', function(data, cb)
    local playerPed = PlayerPedId()
    local vehicle   = GetVehiclePedIsIn(playerPed, false)
    if vehicle ~= 0 then
        local plate = string.gsub(GetVehicleNumberPlateText(vehicle), "%s+", "")
        TriggerServerEvent('mi_radio:server:playMusic', plate, data.url, data.title, data.duration)
    end
    cb('ok')
end)

RegisterNUICallback('stopMusic', function(data, cb)
    if currentVehicle then
        local plate = string.gsub(GetVehicleNumberPlateText(currentVehicle), "%s+", "")
        TriggerServerEvent('mi_radio:server:stopMusic', plate)
    end
    cb('ok')
end)

RegisterNUICallback('pauseMusic', function(data, cb)
    if currentVehicle then
        local plate = string.gsub(GetVehicleNumberPlateText(currentVehicle), "%s+", "")
        TriggerServerEvent('mi_radio:server:pauseMusic', plate)
    end
    cb('ok')
end)

RegisterNUICallback('resumeMusic', function(data, cb)
    if currentVehicle then
        local plate = string.gsub(GetVehicleNumberPlateText(currentVehicle), "%s+", "")
        TriggerServerEvent('mi_radio:server:resumeMusic', plate)
    end
    cb('ok')
end)

RegisterNUICallback('seekMusic', function(data, cb)
    if currentVehicle and currentSoundId then
        local plate   = string.gsub(GetVehicleNumberPlateText(currentVehicle), "%s+", "")
        local newTime = localTimeStamp + (data.offset or 0)
        if newTime < 0 then newTime = 0 end
        TriggerServerEvent('mi_radio:server:seekMusic', plate, newTime)
    end
    cb('ok')
end)

-- FIX (race condition seekToPercent): Si xsound aún no cargó la duración,
-- avisamos al usuario en lugar de fallar silenciosamente.
RegisterNUICallback('seekToPercent', function(data, cb)
    if currentVehicle and currentSoundId then
        local plate  = string.gsub(GetVehicleNumberPlateText(currentVehicle), "%s+", "")
        local maxDur = exports.xsound:getMaxDuration(currentSoundId) or 0
        if maxDur <= 0 then maxDur = localMaxDuration end

        if maxDur > 0 then
            local newTime = math.floor(maxDur * data.percent)
            TriggerServerEvent('mi_radio:server:seekMusic', plate, newTime)
        else
            -- El audio aún no está listo; notificar al NUI para que muestre feedback
            SendNUIMessage({ type = "seekNotReady" })
        end
    end
    cb('ok')
end)

RegisterNUICallback('setVolume', function(data, cb)
    if currentSoundId then
        exports.xsound:setVolume(currentSoundId, data.volume)
    end
    cb('ok')
end)

-- ============================================================
-- EVENTOS DE SINCRONIZACIÓN (recibidos del servidor)
-- ============================================================

RegisterNetEvent('mi_radio:client:syncRadio', function(plate, data)
    local playerPed = PlayerPedId()
    local vehicle   = GetVehiclePedIsIn(playerPed, false)

    local myPlate = ""
    if vehicle ~= 0 then
        myPlate = string.gsub(GetVehicleNumberPlateText(vehicle), "%s+", "")
    end

    local soundId = "radio_" .. plate
    emptyRadios[plate] = nil

    if not exports.xsound:soundExists(soundId) or trackedRadios[plate] ~= data.url then
        if exports.xsound:soundExists(soundId) then
            exports.xsound:Destroy(soundId)
        end

        local vehObject = getVehicleFromPlate(plate)
        if vehObject then
            local coords = GetEntityCoords(vehObject)
            exports.xsound:PlayUrlPos(soundId, data.url, 0.5, coords, false)
            exports.xsound:Distance(soundId, Config.MaxDistance)
            trackedRadios[plate]  = data.url
            activeVehicles[plate] = vehObject

            if data.timestamp > 0 then
                exports.xsound:setTimeStamp(soundId, data.timestamp)
            end
            if data.isPaused then
                exports.xsound:Pause(soundId)
            end
        end
    else
        if data.timestamp > 0 then
            local currentTime = exports.xsound:getTimeStamp(soundId) or 0
            if math.abs(currentTime - data.timestamp) > 3 then
                exports.xsound:setTimeStamp(soundId, data.timestamp)
            end
        end
    end

    if myPlate == plate then
        currentSoundId   = soundId
        currentVehicle   = vehicle
        localTimeStamp   = tonumber(data.timestamp) or 0
        localMaxDuration = tonumber(data.duration) or 0
        localIsPaused    = data.isPaused
        -- FIX (drift): Reiniciamos el reloj local al recibir un sync del servidor,
        -- así el contador arranca desde un punto de referencia preciso.
        localLastTick = GetGameTimer()

        if isGuiOpen then
            SendNUIMessage({
                type        = "updateProgress",
                currentTime = localTimeStamp,
                maxDuration = localMaxDuration,
                title       = data.title,
                isPaused    = data.isPaused
            })
        end
    end
end)

RegisterNetEvent('mi_radio:client:syncStop', function(plate)
    local soundId = "radio_" .. plate
    if exports.xsound:soundExists(soundId) then
        exports.xsound:Destroy(soundId)
    end
    trackedRadios[plate]  = nil
    activeVehicles[plate] = nil
    emptyRadios[plate]    = GetGameTimer() + 10000

    if currentSoundId == soundId then
        currentSoundId   = nil
        -- FIX (stale currentVehicle): Limpiamos también currentVehicle aquí,
        -- no solo cuando el jugador cierra la GUI, para evitar referencias viejas.
        currentVehicle   = nil
        localTimeStamp   = 0
        localMaxDuration = 0
        localIsPaused    = false
        localLastTick    = 0
        if isGuiOpen then
            SendNUIMessage({ type = "stopProgress" })
        end
    end
end)

RegisterNetEvent('mi_radio:client:syncPause', function(plate)
    local soundId = "radio_" .. plate
    if exports.xsound:soundExists(soundId) then
        exports.xsound:Pause(soundId)
    end
    if currentSoundId == soundId then
        localIsPaused = true
        if isGuiOpen then
            SendNUIMessage({ type = "pauseProgress" })
        end
    end
end)

RegisterNetEvent('mi_radio:client:syncResume', function(plate)
    local soundId = "radio_" .. plate
    if exports.xsound:soundExists(soundId) then
        exports.xsound:Resume(soundId)
    end
    if currentSoundId == soundId then
        localIsPaused = false
        -- FIX (drift): Reiniciamos el reloj al reanudar para no acumular el tiempo pausado.
        localLastTick = GetGameTimer()
        if isGuiOpen then
            SendNUIMessage({ type = "resumeProgress" })
        end
    end
end)

RegisterNetEvent('mi_radio:client:syncSeek', function(plate, newTime)
    local soundId = "radio_" .. plate
    if exports.xsound:soundExists(soundId) then
        exports.xsound:setTimeStamp(soundId, newTime)
    end
    if currentSoundId == soundId then
        localTimeStamp = newTime
        -- FIX (drift): Reiniciamos el reloj al hacer seek para que el contador
        -- parta desde el nuevo tiempo sin acumular error anterior.
        localLastTick = GetGameTimer()
    end
end)

-- ============================================================
-- THREAD: Actualizar posición del sonido 3D
-- ============================================================

CreateThread(function()
    while true do
        local waitTime  = 1000
        local playerPed = PlayerPedId()
        local isInVeh   = IsPedInAnyVehicle(playerPed, false)

        local radioCount = 0
        for plate, entity in pairs(activeVehicles) do
            radioCount = radioCount + 1
            local soundId = "radio_" .. plate

            if DoesEntityExist(entity) then
                if exports.xsound:soundExists(soundId) then
                    local vCoords = GetEntityCoords(entity)
                    exports.xsound:Position(soundId, vCoords)
                    waitTime = isInVeh and 150 or 250
                end
            else
                if exports.xsound:soundExists(soundId) then
                    exports.xsound:Destroy(soundId)
                end
                trackedRadios[plate]  = nil
                activeVehicles[plate] = nil

                if currentSoundId == soundId then
                    currentSoundId = nil
                    -- FIX (stale currentVehicle): limpiar también aquí
                    currentVehicle = nil
                end
            end
        end

        if radioCount == 0 then waitTime = 1000 end
        Wait(waitTime)
    end
end)

-- ============================================================
-- THREAD: Contador de tiempo local (con drift fix)
-- FIX: En lugar de asumir que Wait(1000) = exactamente 1 segundo,
-- medimos la diferencia real con os.clock() y la acumulamos.
-- Esto elimina la deriva que se notaba en canciones largas.
-- ============================================================

CreateThread(function()
    while true do
        Wait(500) -- Tick más frecuente para mayor precisión, sin coste relevante

        if currentSoundId and not localIsPaused then
            local now  = GetGameTimer()
            local diff = (now - localLastTick) / 1000.0
            localLastTick = now

            -- Intento obtener la duración real de xsound si aún no la tenemos
            if localMaxDuration <= 0 then
                local maxDur = exports.xsound:getMaxDuration(currentSoundId) or 0
                if maxDur > 0 then
                    localMaxDuration = math.floor(maxDur)
                end
            end

            localTimeStamp = localTimeStamp + diff

            -- Clampear al máximo para no pasarnos
            if localMaxDuration > 0 and localTimeStamp >= localMaxDuration then
                localTimeStamp = localMaxDuration
                localIsPaused  = true
            end

            if isGuiOpen then
                SendNUIMessage({
                    type        = "updateProgress",
                    currentTime = math.floor(localTimeStamp),
                    maxDuration = localMaxDuration
                })
            end
        end
    end
end)

-- ============================================================
-- THREAD: Sincronizar al entrar a un vehículo
-- FIX (stale currentVehicle): Al salir del vehículo sin cerrar la GUI,
-- limpiamos currentVehicle y currentSoundId para no mantener referencias viejas.
-- ============================================================

CreateThread(function()
    local lastVeh = 0
    while true do
        Wait(500)
        local playerPed = PlayerPedId()
        local vehicle   = GetVehiclePedIsIn(playerPed, false)

        if vehicle ~= 0 and vehicle ~= lastVeh then
            local plate = string.gsub(GetVehicleNumberPlateText(vehicle), "%s+", "")
            TriggerServerEvent('mi_radio:server:requestState', plate)
            lastVeh = vehicle

        elseif vehicle == 0 then
            -- FIX: El jugador salió del vehículo
            if lastVeh ~= 0 then
                -- Si la GUI sigue abierta con datos del coche anterior, limpiar
                if isGuiOpen then
                    toggleRadio(false)
                end
                currentSoundId = nil
                currentVehicle = nil
            end
            lastVeh = 0
        end
    end
end)

-- ============================================================
-- THREAD: Escáner de área (Sincronización pasiva)
-- FIX (GetGamePool): Limitamos a un máximo de vehículos procesados por
-- tick para evitar micro-stutters en servidores con muchos vehículos.
-- ============================================================

local MAX_VEHICLES_PER_SCAN = 20 -- Máximo de vehículos a procesar por ciclo

CreateThread(function()
    while true do
        Wait(2000)
        local playerPed = PlayerPedId()
        local pCoords   = GetEntityCoords(playerPed)
        local currentVeh = GetVehiclePedIsIn(playerPed, false)
        local pPlate = ""
        if currentVeh ~= 0 then
            pPlate = string.gsub(GetVehicleNumberPlateText(currentVeh), "%s+", "")
        end

        local vehicles  = GetGamePool('CVehicle')
        local processed = 0

        -- Ordenar por distancia primero para priorizar los más cercanos
        local nearby = {}
        for _, veh in ipairs(vehicles) do
            if veh ~= currentVeh then
                local dist = #(pCoords - GetEntityCoords(veh))
                if dist < 35.0 then
                    nearby[#nearby + 1] = { veh = veh, dist = dist }
                end
            end
        end
        table.sort(nearby, function(a, b) return a.dist < b.dist end)

        for _, entry in ipairs(nearby) do
            if processed >= MAX_VEHICLES_PER_SCAN then break end
            processed = processed + 1

            local veh   = entry.veh
            local plate = string.gsub(GetVehicleNumberPlateText(veh), "%s+", "")

            if not trackedRadios[plate] and plate ~= pPlate then
                if not emptyRadios[plate] or GetGameTimer() > emptyRadios[plate] then
                    TriggerServerEvent('mi_radio:server:requestState', plate)
                end
            end
        end
    end
end)
