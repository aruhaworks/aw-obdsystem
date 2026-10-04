local Core, FW
local pending, cooldowns, scanAt = {}, {}, {}

local function use(src, ghost)
    TriggerClientEvent('aw_obd:client:open', src, ghost)
end

local function boot(final)
    local mode = Config.Framework
    if mode == 'auto' then
        if GetResourceState('es_extended') == 'started' then
            mode = 'esx'
        elseif GetResourceState('qbx_core') == 'started' then
            mode = 'qbx'
        elseif GetResourceState('qb-core') == 'started' then
            mode = 'qb'
        elseif final and GetResourceState('ox_inventory') == 'started' then
            mode = 'standalone'
        end
    end

    if mode == 'esx' then
        Core = exports['es_extended']:getSharedObject()
        FW = 'esx'
        Core.RegisterUsableItem(Config.Items.scanner, function(src) use(src, false) end)
        Core.RegisterUsableItem(Config.Items.ghost, function(src) use(src, true) end)
    elseif mode == 'qbx' then
        FW = 'qbx'
        exports.qbx_core:CreateUseableItem(Config.Items.scanner, function(src) use(src, false) end)
        exports.qbx_core:CreateUseableItem(Config.Items.ghost, function(src) use(src, true) end)
    elseif mode == 'qb' then
        Core = exports['qb-core']:GetCoreObject()
        FW = 'qb'
        Core.Functions.CreateUseableItem(Config.Items.scanner, function(src) use(src, false) end)
        Core.Functions.CreateUseableItem(Config.Items.ghost, function(src) use(src, true) end)
    elseif mode == 'standalone' then
        FW = 'standalone'
    end
end

CreateThread(function()
    local tries = 0
    while not FW and tries < 60 do
        boot(tries >= 20)
        tries = tries + 1
        if not FW then Wait(500) end
    end
end)

exports('scanner', function(event, item, inventory)
    if event == 'usingItem' then
        TriggerClientEvent('aw_obd:client:open', inventory.id)
    end
end)

exports('ghost', function(event, item, inventory)
    if event == 'usingItem' then
        TriggerClientEvent('aw_obd:client:open', inventory.id, true)
    end
end)

local function player(src)
    if FW == 'esx' then return Core.GetPlayerFromId(src) end
    if FW == 'qb' then return Core.Functions.GetPlayer(src) end
    if FW == 'qbx' then return exports.qbx_core:GetPlayer(src) end
end

local function jobOf(src)
    local p = player(src)
    if not p then return '' end
    if FW == 'esx' then return p.job and p.job.name or '' end
    return p.PlayerData.job.name
end

local function isPolice(src)
    if FW == 'standalone' then return IsPlayerAceAllowed(src, 'aw_obd.police') end
    return Config.PoliceJobs[jobOf(src)] == true
end

local function nameOf(src)
    local p = player(src)
    if not p then return GetPlayerName(src) end
    if FW == 'esx' then return p.getName() end
    local c = p.PlayerData.charinfo
    return c.firstname .. ' ' .. c.lastname
end

local function itemCount(src, item)
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:Search(src, 'count', item) or 0
    end
    local p = player(src)
    if not p then return 0 end
    if FW == 'esx' then
        local i = p.getInventoryItem(item)
        return i and i.count or 0
    end
    local i = p.Functions.GetItemByName(item)
    return i and i.amount or 0
end

local function takeItem(src, item, n)
    if GetResourceState('ox_inventory') == 'started' then
        return exports.ox_inventory:RemoveItem(src, item, n)
    end
    local p = player(src)
    if not p then return false end
    if FW == 'esx' then
        p.removeInventoryItem(item, n)
        return true
    end
    return p.Functions.RemoveItem(item, n)
end

local function notify(src, key)
    TriggerClientEvent('aw_obd:client:notify', src, key)
end

local function norm(plate)
    return (tostring(plate or ''):gsub('^%s+', ''):gsub('%s+$', ''):upper())
end

local function num(v, d, lo, hi)
    v = tonumber(v) or d
    return math.max(lo, math.min(hi, v))
end

local function seedOf(plate)
    local s = 7
    for i = 1, #plate do
        s = (s * 31 + plate:byte(i)) % 1000003
    end
    return s
end

local function getRecord(plate)
    local row = MySQL.single.await('SELECT * FROM aw_obd_vehicles WHERE plate = ?', { plate })
    if not row then
        local km = 8000 + seedOf(plate) % 152000
        MySQL.insert.await('INSERT INTO aw_obd_vehicles (plate, mileage, history) VALUES (?, ?, ?)', { plate, km, '[]' })
        row = { plate = plate, mileage = km, stolen = 0, tamper = 0, history = '[]' }
    end
    row.stolen = (row.stolen == 1 or row.stolen == true) and 1 or 0
    row.tamper = row.tamper or 0
    row.hist = json.decode(row.history or '[]') or {}
    return row
end

local function saveRecord(rec)
    MySQL.update.await(
        'UPDATE aw_obd_vehicles SET mileage = ?, stolen = ?, tamper = ?, last_tamper = ?, last_tamper_at = ?, history = ? WHERE plate = ?',
        { rec.mileage, rec.stolen, rec.tamper, rec.last_tamper, rec.last_tamper_at, json.encode(rec.hist), rec.plate }
    )
end

local function health(t, km, plate)
    local seed = seedOf(plate)
    local h = {
        engine = num(t.engine / 10, 100, 0, 100),
        body = num(t.body / 10, 100, 0, 100),
        fuelsys = num(t.tank / 10, 100, 0, 100),
        fuel = num(t.fuel, 100, 0, 100),
        oil = num(100 - (km % 15000) / 150, 100, 0, 100),
        brakes = num(100 - (km % 40000) / 400, 100, 0, 100),
        tyres = num(100 - t.burst * 25, 100, 0, 100)
    }
    local battery = 62 + seed % 38
    if h.body < 40 then battery = battery - 20 end
    if h.engine < 30 then battery = battery - 15 end
    h.battery = num(battery, 100, 0, 100)
    for k, v in pairs(h) do
        h[k] = math.floor(v + 0.5)
    end
    return h
end

local rank = { crit = 3, warn = 2, info = 1 }

local function codes(h, rec, t)
    local out = {}
    local function add(code, sev)
        out[#out + 1] = { code = code, sev = sev }
    end
    if h.engine < 70 then add('P0300', 'warn') end
    if h.engine < 40 then add('P0217', 'crit') end
    if h.engine < 15 then add('P0606', 'crit') end
    if h.body < 50 then add('C0561', 'warn') end
    if h.fuelsys < 80 then add('P0087', 'warn') end
    if h.fuelsys < 40 then add('P0191', 'crit') end
    if h.fuel < 10 then add('P0463', 'info') end
    if t.burst > 0 then add('C0750', 'warn') end
    if h.oil < 20 then add('P0520', 'warn') end
    if h.battery < 30 then add('P0562', 'warn') end
    if h.brakes < 25 then add('C0035', 'crit') end
    if rec.tamper >= 3 then add('U3000', 'crit') end
    table.sort(out, function(a, b) return rank[a.sev] > rank[b.sev] end)
    return out
end

local function average(h)
    local s, n = 0, 0
    for _, v in pairs(h) do
        s = s + v
        n = n + 1
    end
    return math.floor(s / n + 0.5)
end

RegisterNetEvent('aw_obd:server:check', function()
    local src = source
    local ok = not Config.RequireItem
        or itemCount(src, Config.Items.scanner) > 0
        or itemCount(src, Config.Items.ghost) > 0
    TriggerClientEvent('aw_obd:client:checked', src, ok)
end)

RegisterNetEvent('aw_obd:server:open', function(plate, ghostMode)
    local src = source
    local hasGhost = itemCount(src, Config.Items.ghost) > 0
    if ghostMode and not hasGhost then return notify(src, 'n_noaccess') end
    if Config.RequireItem and not hasGhost and itemCount(src, Config.Items.scanner) < 1 then
        return notify(src, 'n_noitem')
    end
    plate = norm(plate)
    if plate == '' then return notify(src, 'n_novehicle') end
    local rec = getRecord(plate)
    TriggerClientEvent('aw_obd:client:opened', src, {
        plate = plate,
        km = rec.mileage,
        history = rec.hist,
        ghost = hasGhost,
        autoGhost = ghostMode == true,
        police = isPolice(src)
    })
end)

RegisterNetEvent('aw_obd:server:scan', function(plate, t)
    local src = source
    plate = norm(plate)
    if plate == '' or type(t) ~= 'table' then return end
    local now = os.time()
    if scanAt[src] and now - scanAt[src] < Config.ScanCooldown then return end
    scanAt[src] = now

    local tt = {
        engine = num(t.engine, 1000, -4000, 1000),
        body = num(t.body, 1000, -4000, 1000),
        tank = num(t.tank, 1000, -4000, 1000),
        fuel = num(t.fuel, 100, 0, 100),
        burst = math.floor(num(t.burst, 0, 0, 8))
    }

    local rec = getRecord(plate)
    local h = health(tt, rec.mileage, plate)
    local list = codes(h, rec, tt)
    local by = nameOf(src)

    rec.hist[#rec.hist + 1] = { t = now, km = rec.mileage, by = by, dtc = #list, hp = average(h) }
    while #rec.hist > Config.HistoryLimit do
        table.remove(rec.hist, 1)
    end
    saveRecord(rec)

    TriggerClientEvent('aw_obd:client:scanResult', src, {
        id = ('AW-%06d'):format(math.random(0, 999999)),
        plate = plate,
        model = tostring(t.model or ''):sub(1, 24),
        km = rec.mileage,
        time = now,
        tech = by,
        health = h,
        dtc = list,
        history = rec.hist
    })
end)

local function sanitize(action, extra, rec)
    extra = type(extra) == 'table' and extra or {}
    if action == 'mileage' then
        local km = math.floor(tonumber(extra.km) or -1)
        if km < 0 or km >= rec.mileage then return false end
        return { km = km }
    end
    if action == 'plate' then
        local p = norm(extra.plate):gsub('[^A-Z0-9 ]', '')
        if #p < 1 or #p > 8 then return false end
        return { plate = p }
    end
    return {}
end

local function alertPolice(src)
    local c = GetEntityCoords(GetPlayerPed(src))
    local f = Config.Alert.fuzz
    local at = vector3(c.x + math.random(-f, f), c.y + math.random(-f, f), c.z)
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        if isPolice(id) then
            TriggerClientEvent('aw_obd:client:alert', id, at)
        end
    end
end

RegisterNetEvent('aw_obd:server:begin', function(action, plate, extra)
    local src = source
    local def = Config.Actions[action]
    if not def or pending[src] then return end
    plate = norm(plate)
    if plate == '' or itemCount(src, Config.Items.ghost) < 1 then
        return notify(src, 'n_noaccess')
    end
    local key = src .. ':' .. action
    local now = GetGameTimer()
    if cooldowns[key] and cooldowns[key] > now then return notify(src, 'n_cooldown') end
    if def.consume and itemCount(src, def.consume.item) < def.consume.count then
        return notify(src, 'n_missing')
    end
    local clean = sanitize(action, extra, getRecord(plate))
    if not clean then return notify(src, 'n_fail') end
    pending[src] = { action = action, plate = plate, extra = clean, endAt = now + def.duration }
    TriggerClientEvent('aw_obd:client:beginOk', src, action, def.duration)
end)

RegisterNetEvent('aw_obd:server:cancel', function()
    pending[source] = nil
end)

RegisterNetEvent('aw_obd:server:finish', function()
    local src = source
    local job = pending[src]
    pending[src] = nil
    if not job then return end
    if GetGameTimer() < job.endAt - 500 then return end
    if itemCount(src, Config.Items.ghost) < 1 then return end

    local def = Config.Actions[job.action]
    if def.consume and not takeItem(src, def.consume.item, def.consume.count) then
        return notify(src, 'n_missing')
    end
    cooldowns[src .. ':' .. job.action] = GetGameTimer() + def.cooldown * 1000

    local rec = getRecord(job.plate)
    if job.action == 'mileage' then
        rec.mileage = job.extra.km
    elseif job.action == 'clearlog' then
        rec.hist = {}
    elseif job.action == 'wipeflag' then
        rec.stolen = 0
    end

    rec.tamper = math.max(0, rec.tamper + def.trace)
    if def.trace > 0 then
        rec.last_tamper = job.action
        rec.last_tamper_at = os.time()
    end
    saveRecord(rec)

    if math.random(100) <= def.alert then
        alertPolice(src)
    end

    TriggerClientEvent('aw_obd:client:applied', src, job.action, {
        extra = job.extra,
        km = rec.mileage,
        history = rec.hist
    })
end)

RegisterNetEvent('aw_obd:server:police', function(op, plate)
    local src = source
    if not isPolice(src) then return notify(src, 'n_nopolice') end
    plate = norm(plate)
    if plate == '' then return end
    local rec = getRecord(plate)
    if op == 'flag' then
        rec.stolen = rec.stolen == 1 and 0 or 1
        saveRecord(rec)
        notify(src, rec.stolen == 1 and 'n_flagged' or 'n_unflagged')
    end
    TriggerClientEvent('aw_obd:client:forensic', src, {
        tamper = rec.tamper,
        last = rec.last_tamper,
        lastAt = rec.last_tamper_at,
        stolen = rec.stolen == 1
    })
end)

AddEventHandler('playerDropped', function()
    local src = source
    pending[src] = nil
    scanAt[src] = nil
end)
