local active, busy = false, false
local ctx = { veh = 0, plate = '', model = '' }
local tuiMode = nil
local cache = { at = 0, ok = false }

local kinds = {
    n_noitem = 'error',
    n_novehicle = 'error',
    n_cooldown = 'warning',
    n_missing = 'error',
    n_noaccess = 'error',
    n_fail = 'error',
    n_cancel = 'warning',
    n_done = 'success',
    n_alert = 'warning',
    n_nopolice = 'error',
    n_flagged = 'success',
    n_unflagged = 'info'
}

local function L(k)
    local set = Config.Locale[Config.Language] or Config.Locale.en
    return set[k] or k
end

local function notify(msg, kind, desc)
    if GetResourceState(Config.Notify.resource) == 'started' then
        if desc then
            exports[Config.Notify.resource]:Notify(kind or 'info', msg, desc)
        else
            exports[Config.Notify.resource]:Notify(kind or 'info', msg)
        end
        return
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(false, true)
end

local function showText(text, mode)
    if not Config.TextUI.enabled or GetResourceState(Config.TextUI.resource) ~= 'started' then return end
    if tuiMode == mode then return end
    exports[Config.TextUI.resource]:DrawText(text)
    tuiMode = mode
end

local function hideText(mode)
    if not tuiMode then return end
    if mode and tuiMode ~= mode then return end
    exports[Config.TextUI.resource]:HideText()
    tuiMode = nil
end

local function clamp(v, a, b)
    return math.max(a, math.min(b, v))
end

local function target()
    local ped = PlayerPedId()
    local v = GetVehiclePedIsIn(ped, false)
    if v ~= 0 then return v end
    local c = GetEntityCoords(ped)
    return GetClosestVehicle(c.x, c.y, c.z, Config.Distance, 0, 71)
end

local function control(e)
    if NetworkHasControlOfEntity(e) then return true end
    local stop = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(e) and GetGameTimer() < stop do
        NetworkRequestControlOfEntity(e)
        Wait(50)
    end
    return NetworkHasControlOfEntity(e)
end

local function telemetry(v)
    local burst = 0
    for i = 0, 7 do
        if IsVehicleTyreBurst(v, i, false) then burst = burst + 1 end
    end
    return {
        engine = GetVehicleEngineHealth(v),
        body = GetVehicleBodyHealth(v),
        tank = GetVehiclePetrolTankHealth(v),
        fuel = GetVehicleFuelLevel(v),
        burst = burst,
        model = ctx.model
    }
end

local function closeUi()
    if not active then return end
    active = false
    hideText('work')
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function startLive()
    CreateThread(function()
        while active do
            local v = ctx.veh
            if v == 0 or not DoesEntityExist(v) then break end
            if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(v)) > Config.Distance + 4.0 then break end

            local on = GetIsVehicleEngineRunning(v)
            local rpm = on and GetVehicleCurrentRpm(v) or 0.0
            local eng = clamp(GetVehicleEngineHealth(v) / 10, 0, 100)

            SendNUIMessage({
                action = 'live',
                data = {
                    speed = math.floor(GetEntitySpeed(v) * 3.6),
                    rpm = math.floor(rpm * 8000),
                    gear = GetVehicleCurrentGear(v),
                    temp = on and math.floor(78 + rpm * 18 + (100 - eng) * 0.45) or 25,
                    volt = on and (13.6 + rpm * 0.8) or 12.2,
                    fuel = math.floor(clamp(GetVehicleFuelLevel(v), 0, 100)),
                    engine = math.floor(eng)
                }
            })
            Wait(400)
        end
        closeUi()
    end)
end

local function requestOpen(ghostMode, entity)
    if active or busy then return end
    local v = (entity and entity ~= 0) and entity or target()
    if v == 0 then return notify(L('n_novehicle'), 'error') end
    local label = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(v)))
    if label == 'NULL' then label = GetDisplayNameFromVehicleModel(GetEntityModel(v)) end
    ctx.veh = v
    ctx.model = label
    TriggerServerEvent('aw_obd:server:open', GetVehicleNumberPlateText(v), ghostMode == true)
end

if Config.Command then
    RegisterCommand(Config.Command, function() requestOpen(false) end, false)
end

RegisterNetEvent('aw_obd:client:open', function(ghostMode)
    requestOpen(ghostMode)
end)

RegisterNetEvent('aw_obd:client:notify', function(key)
    notify(L(key), kinds[key] or 'info')
end)

RegisterNetEvent('aw_obd:client:checked', function(ok)
    cache.ok = ok
end)

RegisterNetEvent('aw_obd:client:opened', function(d)
    ctx.plate = d.plate
    active = true
    hideText()
    local codes = {}
    for code, text in pairs(Config.Codes) do
        codes[code] = text[Config.Language] or text.en
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        data = d,
        model = ctx.model,
        locale = Config.Locale[Config.Language] or Config.Locale.en,
        codes = codes
    })
    startLive()
end)

RegisterNetEvent('aw_obd:client:scanResult', function(d)
    SendNUIMessage({ action = 'scan', data = d })
end)

RegisterNetEvent('aw_obd:client:forensic', function(d)
    SendNUIMessage({ action = 'forensic', data = d })
end)

RegisterNetEvent('aw_obd:client:beginOk', function(action, duration)
    busy = true
    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    SendNUIMessage({ action = 'progress', key = action, duration = duration })
    showText(('%s: %s'):format(L('tui_work'), L('a_' .. action)), 'work')

    CreateThread(function()
        local stop = GetGameTimer() + duration
        local ok = true
        while GetGameTimer() < stop do
            if not active or IsEntityDead(ped) or not DoesEntityExist(ctx.veh)
                or #(GetEntityCoords(ped) - GetEntityCoords(ctx.veh)) > Config.Distance + 4.0 then
                ok = false
                break
            end
            Wait(100)
        end
        ClearPedTasks(ped)
        busy = false
        hideText('work')
        if ok then
            TriggerServerEvent('aw_obd:server:finish')
        else
            TriggerServerEvent('aw_obd:server:cancel')
            SendNUIMessage({ action = 'progressStop' })
            notify(L('n_cancel'), 'warning')
        end
    end)
end)

local effects = {}

effects.plate = function(v, d)
    SetVehicleNumberPlateText(v, d.extra.plate)
    ctx.plate = d.extra.plate
    CreateThread(function()
        Wait(1200)
        closeUi()
    end)
end

effects.tune = function(v)
    if not control(v) then return end
    SetVehicleEnginePowerMultiplier(v, Config.Tune.power)
    SetTimeout(Config.Tune.time * 1000, function()
        if DoesEntityExist(v) then
            SetVehicleEnginePowerMultiplier(v, 0.0)
            SetVehicleEngineHealth(v, math.max(100.0, GetVehicleEngineHealth(v) - Config.Tune.damage))
        end
    end)
end

effects.unlock = function(v)
    if not control(v) then return end
    SetVehicleDoorsLocked(v, 1)
    SetVehicleDoorsLockedForAllPlayers(v, false)
    SetVehicleAlarm(v, false)
end

effects.immobilize = function(v)
    if not control(v) then return end
    SetVehicleEngineOn(v, false, true, true)
    SetVehicleUndriveable(v, true)
    SetTimeout(Config.Immobilize.time * 1000, function()
        if DoesEntityExist(v) then SetVehicleUndriveable(v, false) end
    end)
end

RegisterNetEvent('aw_obd:client:applied', function(action, d)
    local v = ctx.veh
    if effects[action] and v ~= 0 and DoesEntityExist(v) then
        effects[action](v, d)
    end
    SendNUIMessage({ action = 'applied', key = action, km = d.km, history = d.history })
    notify(L('n_done'), 'success', L('a_' .. action))
end)

RegisterNetEvent('aw_obd:client:alert', function(c)
    notify(L('n_alert'), 'warning')
    local area = AddBlipForRadius(c.x, c.y, c.z, Config.Alert.radius)
    SetBlipColour(area, 0)
    SetBlipAlpha(area, 110)
    local pin = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(pin, Config.Alert.sprite)
    SetBlipColour(pin, 0)
    SetBlipScale(pin, 0.9)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('blip_alert'))
    EndTextCommandSetBlipName(pin)
    SetTimeout(Config.Alert.blipTime * 1000, function()
        RemoveBlip(area)
        RemoveBlip(pin)
    end)
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb('ok')
end)

RegisterNUICallback('scan', function(_, cb)
    if ctx.veh ~= 0 and DoesEntityExist(ctx.veh) then
        TriggerServerEvent('aw_obd:server:scan', ctx.plate, telemetry(ctx.veh))
    end
    cb('ok')
end)

RegisterNUICallback('begin', function(d, cb)
    if not busy and d and d.action then
        TriggerServerEvent('aw_obd:server:begin', d.action, ctx.plate, d.extra)
    end
    cb('ok')
end)

RegisterNUICallback('police', function(d, cb)
    if d and d.op then
        TriggerServerEvent('aw_obd:server:police', d.op, ctx.plate)
    end
    cb('ok')
end)

local targetMode = nil

local function canUse()
    if active or busy then return false end
    if GetGameTimer() - cache.at > 8000 then
        cache.at = GetGameTimer()
        TriggerServerEvent('aw_obd:server:check')
    end
    return cache.ok
end

local function waitFor(res)
    local tries = 0
    while GetResourceState(res) ~= 'started' and tries < 60 do
        tries = tries + 1
        Wait(500)
    end
    return GetResourceState(res) == 'started'
end

CreateThread(function()
    local mode = Config.Target
    if mode == 'auto' then
        if waitFor('ox_target') then
            mode = 'ox_target'
        elseif GetResourceState('qb-target') == 'started' then
            mode = 'qb-target'
        else
            mode = 'none'
        end
    end

    if mode == 'ox_target' and waitFor('ox_target') then
        exports.ox_target:addGlobalVehicle({
            {
                name = 'aw_obd_open',
                icon = 'fa-solid fa-microchip',
                label = L('target_open'),
                distance = Config.TargetDistance,
                canInteract = function() return canUse() end,
                onSelect = function(data) requestOpen(false, data.entity) end
            }
        })
        targetMode = 'ox_target'
    elseif mode == 'qb-target' and waitFor('qb-target') then
        exports['qb-target']:AddGlobalVehicle({
            options = {
                {
                    icon = 'fa-solid fa-microchip',
                    label = L('target_open'),
                    canInteract = function() return canUse() end,
                    action = function(entity) requestOpen(false, entity) end
                }
            },
            distance = Config.TargetDistance
        })
        targetMode = 'qb-target'
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        if targetMode == 'ox_target' then
            exports.ox_target:removeGlobalVehicle('aw_obd_open')
        elseif targetMode == 'qb-target' then
            exports['qb-target']:RemoveGlobalVehicle({ L('target_open') })
        end
        hideText()
        SetNuiFocus(false, false)
    end
end)
