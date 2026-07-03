local MOD_VERSION = "2.0"

script_name("Hitman Console")
script_author("L0K3D")
script_version(MOD_VERSION)

local sampev = require 'samp.events'
local models = require 'game.models'
local imgui  = require 'mimgui'
local fa     = require 'fAwesome6_solid'
local json   = require 'dkjson'

local ImVec2, ImVec4 = imgui.ImVec2, imgui.ImVec4

local function icon(name) return fa[name] or '' end

local C = {
    title = ImVec4(0.36, 0.64, 0.98, 1.0),
    text  = ImVec4(0.93, 0.93, 0.93, 1.0),
    dim   = ImVec4(0.72, 0.74, 0.88, 1.0),
    green = ImVec4(0.27, 0.80, 0.27, 1.0),
    red   = ImVec4(0.90, 0.26, 0.26, 1.0),
}

local settingsOpen = imgui.new.bool(false)

local selfUndercover = false
local undercoverTdId = nil

local target = {
    active = false,
    name = nil,
    pid = nil,
    distance = nil,
    zone = nil,
    state = nil,
    skin = nil,
    faction = nil,
    number = nil,
    lastUpdate = 0,
}

local backupMode = false
local VK_Y = 0x59

local smsPending = nil

local blockedIds = {}

local sniperAiming = false
local sniperOnTarget = false

local selfPhoneOn = true

local CONTRACT_MIN_DIST = 100

local contract = {
    active    = false,
    name      = nil,
    pid       = nil,
    sum       = nil,
    found     = false,
    outcome   = nil,
    endTime   = 0,
    lastId    = 0,
    hideFind  = false,
    hideCheck = false,
    hideId    = false,
    hideNumber = false,
}

local report = {
    active    = false,
    done = nil, total = nil,
    hours = nil, hoursReq = nil,
    hideUntil = 0,
    expect = 0,
}

local killcpUntil = 0

local diedUntil = 0

local secActive = false
local secValue = 0
local secLastClk = 0
local secExpect = 0
local secDone = false
local secLoginPhase = false
local secEndTime = 0
local secFont = nil
local cancelTime = 0
local contractIndoors = false

local SEAT_NAMES = { [0] = "front right", [1] = "rear left", [2] = "rear right", [3] = "rear" }

local FACTION_SHORT = {
    ["Los Santos Police Department"]      = "LS Police",
    ["Las Venturas Police Department"]    = "LV Police",
    ["San Fierro Police Department"]      = "SF Police",
    ["Grove Police Department"]           = "Grove Police",
    ["School Instructors LV"]             = "SI LV",
    ["School Instructors SF"]             = "SI SF",
    ["Las Venturas Paramedic Department"] = "LV Paramedic",
    ["San Fierro Paramedic Department"]   = "SF Paramedic",
    ["Los Santos Paramedic Department"]   = "LS Paramedic",
    ["The Russian Mafia"]                 = "Russian Mafia",
    ["Los Aztecas"]                       = "Aztecas",
    ["The Rifa"]                          = "Rifa",
    ["Los Vagos"]                         = "Vagos",
}

local idToVeh = {}
for name, id in pairs(models) do
    if type(id) == "number" and id >= 400 and id <= 611 and not idToVeh[id] then
        idToVeh[id] = name
    end
end

local function prettify(name)
    name = name:gsub("_", " ")
    return (name:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b:lower() end))
end

local function vehicleName(model)
    local n = idToVeh[model]
    if not n then return "vehicle" end
    return prettify(n)
end

local new = imgui.new

local SCHEMA = {
    { key = "report",  title = "Activity Raport", items = {
        { key = "targets", label = "Targets killed" },
        { key = "hours",   label = "Hours played" },
    }},
    { key = "console", title = "Hitman Console", items = {
        { key = "phone",    label = "Phone" },
        { key = "distok",   label = "Distance check (too close / far enough)" },
        { key = "reward",   label = "Reward" },
        { key = "contract", label = "Contract status" },
        { key = "ammo",     label = "Sniper ammo" },
    }},
    { key = "target",  title = "Target", items = {
        { key = "name",    label = "Name" },
        { key = "faction", label = "Faction" },
        { key = "state",   label = "State" },
        { key = "skin",    label = "Skin (portrait)" },
    }},
}

local FEATURES = {
    { key = "keep10s", def = true,  label = "Keep console 10s after contract ends" },
    { key = "tgtnoc",  def = false, label = "Show Target even without an active contract" },
    { key = "hidecp",  def = false, label = "Auto /killcp on /gethit & console hides" },
    { key = "logincd", def = true,  label = "Show /gethit cooldown timer (bottom of screen)" },
}

local DATA_PATH  = getWorkingDirectory() .. "\\hitman_console.json"
local CFG_PATH   = getWorkingDirectory() .. "\\hitman_console.cfg"
local STATS_PATH = getWorkingDirectory() .. "\\hitman_stats.txt"

local S = {}
local feat = {}
local stats = {}
local prim = new.float[3](0.36, 0.64, 0.98)
local opacity = new.int(93)
local backupHi = new.bool(false)

local DEFAULT_MESSAGES = {
    iesi = {
        "poti sa iesi pana afara te rog?",
        "salut, sunt blocat afara si adminii nu raspund, poti veni sa imi dai kill?",
    },
    stai = {
        "salut, poti sa te opresti te rog sa urc si eu?",
        "salut, poti sa te opresti putin? sunt in spate",
    },
}
local messages = { iesi = {}, stai = {} }

local function applyPrimary()
    C.title.x, C.title.y, C.title.z = prim[0], prim[1], prim[2]
end

local function consoleAlpha()
    return opacity[0] / 100
end

local function tint(base, amt, a)
    local r = base + (prim[0] - base) * amt
    local g = base + (prim[1] - base) * amt
    local b = base + (prim[2] - base) * amt
    return ImVec4(r, g, b, a or 1.0)
end

local function buildData()
    local vis = {}
    for _, cat in ipairs(SCHEMA) do
        local c = { enabled = S[cat.key].enabled[0] and true or false }
        for _, it in ipairs(cat.items) do
            c[it.key] = S[cat.key][it.key][0] and true or false
        end
        vis[cat.key] = c
    end
    local features = {}
    for _, ft in ipairs(FEATURES) do
        features[ft.key] = feat[ft.key][0] and true or false
    end

    local cooldown = nil
    if secActive then
        cooldown = {
            login = secLoginPhase and true or false,
            done  = secDone and true or false,
            start = secLoginPhase and (os.time() - math.floor(secValue)) or secEndTime,
            saved = os.time(),
        }
    end
    return {
        settings = {
            visible  = vis,
            features = features,
            primary  = { prim[0], prim[1], prim[2] },
            opacity  = opacity[0],
            backupHi = backupHi[0] and true or false,
        },
        stats    = stats,
        messages = messages,
        cooldown = cooldown,
    }
end

local function saveData()
    local ok, str = pcall(json.encode, buildData(), { indent = true })
    if not ok or type(str) ~= "string" then return end
    local f = io.open(DATA_PATH, "w")
    if not f then return end
    f:write(str)
    f:close()
end

local function readJson(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return nil end
    local ok, obj = pcall(json.decode, raw)
    if ok and type(obj) == "table" then return obj end
    return nil
end

local function migrateLegacy()
    local out = { settings = {}, stats = {}, messages = {} }
    local f = io.open(CFG_PATH, "r")
    if f then
        local kv = {}
        for line in f:lines() do
            local k, v = line:match("^(.-)=(.+)$")
            if k then kv[k] = v end
        end
        f:close()
        local function b(k, d) local v = kv[k]; if v == nil then return d end; return v == "1" end
        local vis = {}
        for _, cat in ipairs(SCHEMA) do
            local c = { enabled = b(cat.key .. ".enabled", true) }
            for _, it in ipairs(cat.items) do c[it.key] = b(cat.key .. "." .. it.key, true) end
            vis[cat.key] = c
        end
        local features = {}
        for _, ft in ipairs(FEATURES) do features[ft.key] = b("feature." .. ft.key, ft.def) end
        out.settings.visible  = vis
        out.settings.features = features
        local pc = kv["style.primary"]
        if pc then
            local r, g, bl = pc:match("([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
            if r then out.settings.primary = { tonumber(r), tonumber(g), tonumber(bl) } end
        end
        local op = tonumber(kv["style.opacity"])
        if op then out.settings.opacity = op end
        out.settings.backupHi = b("backup.hi", false)
    end
    local sf = io.open(STATS_PATH, "r")
    if sf then
        for line in sf:lines() do
            local day, c, m, s, fa = line:match("^(%d%d%d%d%-%d%d%-%d%d)=(%d+)|(%d+)|(%d+)|(%d+)")
            if day then
                out.stats[day] = { contracts = tonumber(c), money = tonumber(m), success = tonumber(s), failed = tonumber(fa) }
            end
        end
        sf:close()
    end
    return out
end

do
    local data = readJson(DATA_PATH)
    local fresh = false
    if not data then
        data = migrateLegacy()
        fresh = true
    end
    data.settings = data.settings or {}
    data.stats    = data.stats or {}
    data.messages = data.messages or {}

    local vis = data.settings.visible or {}
    for _, cat in ipairs(SCHEMA) do
        local c = vis[cat.key] or {}
        S[cat.key] = { enabled = new.bool(c.enabled ~= false) }
        for _, it in ipairs(cat.items) do
            S[cat.key][it.key] = new.bool(c[it.key] ~= false)
        end
    end
    local features = data.settings.features or {}
    for _, ft in ipairs(FEATURES) do
        local v = features[ft.key]
        if v == nil then v = ft.def end
        feat[ft.key] = new.bool(v and true or false)
    end
    local pcol = data.settings.primary
    if type(pcol) == "table" and pcol[1] then
        prim[0] = tonumber(pcol[1]) or prim[0]
        prim[1] = tonumber(pcol[2]) or prim[1]
        prim[2] = tonumber(pcol[3]) or prim[2]
    end
    local op = tonumber(data.settings.opacity)
    if op then opacity[0] = math.max(40, math.min(100, math.floor(op))) end
    if data.settings.backupHi ~= nil then backupHi[0] = data.settings.backupHi and true or false end

    for day, d in pairs(data.stats) do
        if type(d) == "table" then
            stats[day] = {
                contracts = tonumber(d.contracts) or 0,
                money     = tonumber(d.money) or 0,
                success   = tonumber(d.success) or 0,
                failed    = tonumber(d.failed) or 0,
            }
        end
    end

    for _, kind in ipairs({ "iesi", "stai" }) do
        local list = data.messages[kind]
        local out = {}
        if type(list) == "table" then
            for _, m in ipairs(list) do
                if type(m) == "string" and m ~= "" then out[#out + 1] = m end
            end
        end
        if #out == 0 then
            for _, m in ipairs(DEFAULT_MESSAGES[kind]) do out[#out + 1] = m end
        end
        messages[kind] = out
    end

    local cd = data.cooldown
    if type(cd) == "table" and tonumber(cd.saved) and (os.time() - tonumber(cd.saved)) <= 25 then
        secActive = true
        secDone = cd.done and true or false
        if cd.login then
            secLoginPhase = true
            secValue = math.max(0, os.time() - (tonumber(cd.start) or os.time()))
            secLastClk = os.clock()
        else
            secLoginPhase = false
            secEndTime = tonumber(cd.start) or os.time()
        end
    end

    applyPrimary()
    if fresh then saveData() end
end

local MONTH_NAMES = { "January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December" }

local function commas(n)
    local s = tostring(math.floor(n))
    while true do
        local nw = s:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
        if nw == s then break end
        s = nw
    end
    return s
end

local function monthLabel(ym)
    local y, m = ym:match("(%d%d%d%d)%-(%d%d)")
    if not y then return ym end
    return (MONTH_NAMES[tonumber(m)] or m) .. " " .. y
end

local function recordContract(success, money)
    local day = os.date("%Y-%m-%d")
    local d = stats[day] or { contracts = 0, money = 0, success = 0, failed = 0 }
    d.contracts = d.contracts + 1
    d.money = d.money + (money or 0)
    if success then d.success = d.success + 1 else d.failed = d.failed + 1 end
    stats[day] = d
    saveData()
end

local SKIN_DIR = getWorkingDirectory() .. "\\resource\\HAC\\skins\\"
local skinTex = {}

local function pngSize(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read(24)
    f:close()
    if not d or #d < 24 then return nil end
    local function be(a) return d:byte(a) * 16777216 + d:byte(a + 1) * 65536 + d:byte(a + 2) * 256 + d:byte(a + 3) end
    return be(17), be(21)
end

local function getSkinTex(id)
    if id == nil then return nil end
    if skinTex[id] == nil then
        local path = SKIN_DIR .. id .. ".png"
        if doesFileExist(path) then
            local w, h = pngSize(path)
            local tex = imgui.CreateTextureFromFile(path)
            skinTex[id] = (tex and w and h and w > 0 and h > 0) and { tex = tex, w = w, h = h } or false
        else
            skinTex[id] = false
        end
    end
    return skinTex[id] or nil
end

local dlstatus = require('moonloader').download_status
local VERSION_URLS = {
    "https://raw.githubusercontent.com/L0K3D/hitman-console/main/version.json",
    "https://raw.githubusercontent.com/L0K3D/hitman-console/master/version.json",
}
local UPDATE_SCRIPT_URL = "https://raw.githubusercontent.com/L0K3D/hitman-console/main/hitman-console/hac.lua"
local updateInfo  = { available = false, version = nil, date = nil, url = nil }
local updateState = ""

local function verParts(s)
    local t = {}
    for n in tostring(s or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
    return t
end

local function isNewer(remote, current)
    local a, b = verParts(remote), verParts(current)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x > y then return true end
        if x < y then return false end
    end
    return false
end

local function checkVersion(i)
    i = i or 1
    local url = VERSION_URLS[i]
    if not url then return end
    local path = getWorkingDirectory() .. "\\hac_ver.tmp"
    downloadUrlToFile(url, path, function(_, status)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            local data = readJson(path)
            os.remove(path)
            if data and data.version then
                if isNewer(data.version, MOD_VERSION) then
                    updateInfo.available = true
                    updateInfo.version   = tostring(data.version)
                    updateInfo.date      = (type(data.date) == "string" and data.date ~= "") and data.date or nil
                    updateInfo.url       = (type(data.url) == "string" and data.url ~= "") and data.url or nil
                    sampAddChatMessage(("{5CA3FA}Hitman Console{FFFFFF}: version {5CA3FA}%s{FFFFFF} is available (you have %s). Open {5CA3FA}/hac{FFFFFF} -> Update to install."):format(updateInfo.version, MOD_VERSION), -1)
                end
            else
                checkVersion(i + 1)
            end
        elseif status == dlstatus.STATUSEX_DOWNLOADFAILED then
            os.remove(path)
            checkVersion(i + 1)
        end
    end)
end

local function doUpdate()
    if updateState == "working" then return end
    updateState = "working"
    local tmp = getWorkingDirectory() .. "\\hac_update.tmp"
    downloadUrlToFile(UPDATE_SCRIPT_URL, tmp, function(_, status)
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            local f = io.open(tmp, "r")
            local body = f and f:read("*a") or nil
            if f then f:close() end
            if body and #body > 2000 and body:find("Hitman Console", 1, true) then
                local dst = thisScript().path
                local cur = io.open(dst, "r")
                if cur then
                    local old = cur:read("*a"); cur:close()
                    local bak = io.open(dst .. ".bak", "w")
                    if bak then bak:write(old); bak:close() end
                end
                local out = io.open(dst, "w")
                if out then
                    out:write(body); out:close()
                    os.remove(tmp)
                    updateState = "done"
                    saveData()
                    sampAddChatMessage("{5CA3FA}Hitman Console{FFFFFF}: updated to " .. tostring(updateInfo.version) .. ", reloading...", -1)
                    thisScript():reload()
                    return
                end
            end
            os.remove(tmp)
            updateState = "failed"
            sampAddChatMessage("{FF6666}Hitman Console: update failed. Download it manually from " .. (updateInfo.url or "GitHub") .. ".", -1)
        elseif status == dlstatus.STATUSEX_DOWNLOADFAILED then
            os.remove(tmp)
            updateState = "failed"
            sampAddChatMessage("{FF6666}Hitman Console: update download failed. Check your connection or update manually.", -1)
        end
    end)
end

function main()
    while not isSampAvailable() do
        wait(0)
    end

    for _, i in ipairs({ 2046, 2047 }) do if sampTextdrawIsExists(i) then sampTextdrawDelete(i) end end

    local function toggleSettings() settingsOpen[0] = not settingsOpen[0] end
    sampRegisterChatCommand("hitmanconsole", toggleSettings)
    sampRegisterChatCommand("hac", toggleSettings)

    sampRegisterChatCommand("ghit", function() sampSendChat("/gethit") end)
    sampRegisterChatCommand("under", function() sampSendChat("/undercover") end)
    sampRegisterChatCommand("o1", function() sampSendChat("/order 1") end)
    sampRegisterChatCommand("myc", function() sampSendChat("/mycontract") end)

    math.randomseed(os.time())
    local function smsCmd(kind)
        return function(arg)
            local id = arg and arg:match("%d+")
            if not id then
                sampAddChatMessage("{5CA3FA}HAC{FFFFFF}: /" .. kind .. " {id}", -1)
                return
            end
            smsPending = { id = id, kind = kind, expect = os.clock() + 6 }
            sampSendChat("/number " .. id)
        end
    end
    sampRegisterChatCommand("iesi",   smsCmd("iesi"))
    sampRegisterChatCommand("getout", smsCmd("iesi"))
    sampRegisterChatCommand("stai",   smsCmd("stai"))
    sampRegisterChatCommand("stay",   smsCmd("stai"))

    sampAddChatMessage('{5CA3FA}Hitman Console{FFFFFF} loaded successfully, use {5CA3FA}/hac{FFFFFF} to view more information.', -1)
    checkVersion()

    local yWasDown, wasDead, pendingRefind = false, false, false
    while true do
        wait(0)

        local yDown = isKeyDown(VK_Y)
        if yDown and not yWasDown and contract.active and target.active
           and not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
            backupMode = not backupMode
        end
        yWasDown = yDown

        local dead = isCharDead(PLAYER_PED)
        if dead and not wasDead then
            diedUntil = os.clock() + 6
            if contract.active then
                sampAddChatMessage("(!) HAC: You died - your identity is no longer hidden.", 0xFF0000)
                pendingRefind = true
            end
        end
        if not dead and wasDead and pendingRefind then
            pendingRefind = false
            if contract.active and target.pid then
                local pid = target.pid
                lua_thread.create(function()
                    wait(2000)
                    if contract.active and pid then
                        contract.hideFind = true
                        sampSendChat("/find " .. pid)
                    end
                end)
            end
        end
        wasDead = dead

        local wpn = getCurrentCharWeapon(PLAYER_PED)
        sniperAiming = (wpn == 34 or wpn == 33) and isKeyDown(0x02)
            and not isCharInAnyCar(PLAYER_PED) and not sampIsChatInputActive() and not isPauseMenuActive()
        sniperOnTarget = false
        if sniperAiming and target.active then
            local tpid = tonumber(target.pid)
            if tpid then
                local res, ped = sampGetCharHandleBySampPlayerId(tpid)
                if res and doesCharExist(ped) then
                    local tx, ty, tz = getCharCoordinates(ped)
                    local cx, cy, cz = getActiveCameraCoordinates()
                    local ax, ay, az = getActiveCameraPointAt()
                    if (ax - cx) * (tx - cx) + (ay - cy) * (ty - cy) + (az - cz) * (tz - cz) > 0 then
                        local rw, rh = getScreenResolution()
                        local ccx, ccy = rw / 2, rh / 2
                        local hx, hy = convert3DCoordsToScreen(tx, ty, tz + 0.8)
                        local fx, fy = convert3DCoordsToScreen(tx, ty, tz - 0.9)
                        local vx, vy = hx - fx, hy - fy
                        local wx, wy = ccx - fx, ccy - fy
                        local seg2 = vx * vx + vy * vy
                        local t = seg2 > 0 and (wx * vx + wy * vy) / seg2 or 0
                        if t < 0 then t = 0 elseif t > 1 then t = 1 end
                        local px, py = fx + t * vx, fy + t * vy
                        local dist = math.sqrt((ccx - px) ^ 2 + (ccy - py) ^ 2)
                        local tol = math.max(6, math.sqrt(seg2) * 0.16)
                        sniperOnTarget = dist < tol
                    end
                end
            end
        end

        if secActive then
            local n
            if secLoginPhase then
                local clk = os.clock()
                local cdt = clk - secLastClk
                secLastClk = clk
                if cdt > 0 and cdt < 1.0 then secValue = secValue + cdt end
                n = math.floor(secValue)
            else
                n = os.time() - secEndTime
            end

            if feat.logincd[0] and not secDone and n < 420 then
                if not secFont then secFont = renderCreateFont("Pricedown", 16, 4) end
                if secFont then
                    local ready = n >= 300
                    local txt
                    if ready then
                        txt = "You can take a contract"
                    elseif secLoginPhase then
                        txt = "Next contract in " .. (300 - n) .. "s"
                    else
                        local remaining = 300 - n
                        if remaining < 60 then
                            txt = "Next contract in " .. remaining .. "s"
                        else
                            txt = "Next contract at " .. os.date("%H:%M", secEndTime + 300)
                        end
                    end
                    local col = ready and 0xFF33CC33 or 0xFFE53935
                    local sw, sh = getScreenResolution()
                    local tw = renderGetFontDrawTextLength(secFont, txt)
                    renderFontDrawText(secFont, txt, sw - tw - 20, sh * 0.96 - 30, col)
                end
            end
        end
    end
end

local function stripColors(s)
    s = s:gsub("~n~", "\n")
    s = s:gsub("~%a~", "")
    return s
end

local function cleanName(name)
    if type(name) ~= "string" then return name end
    return (name:gsub("%s*%(%d+%)%s*$", ""))
end

local function myNickname()
    local res, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if res then return sampGetPlayerNickname(id) end
    return nil
end

local function isMe(name)
    if not name then return false end
    local me = myNickname()
    return me ~= nil and cleanName(name) == me
end

local function sendCommand(cmd, delay)
    lua_thread.create(function()
        wait(delay or 0)
        sampSendChat(cmd)
    end)
end

local idSentForPid = nil
local idExpect = 0
local numberExpect = 0
local function requestId(pid)
    if pid and pid ~= idSentForPid then
        idSentForPid = pid
        target.faction, target.number = nil, nil
        contract.hideId, contract.hideNumber = true, true
        idExpect = os.clock() + 6
        numberExpect = os.clock() + 8
        sendCommand("/id " .. pid, 200)
        sendCommand("/number " .. pid, 500)
    end
end

local function readState(pid)
    pid = tonumber(pid)
    if not pid then return "Unknown", nil end
    if not sampIsPlayerConnected(pid) then return "Disconnected", nil end

    local res, ped = sampGetCharHandleBySampPlayerId(pid)
    if not res or not doesCharExist(ped) then
        return "Too far to collect data", nil
    end

    local skin = getCharModel(ped)

    if not isCharInAnyCar(ped) then
        return "On foot", skin
    end

    local car = storeCarCharIsInNoSave(ped)
    local vname = vehicleName(getCarModel(car))

    local okDrv, driver = pcall(getDriverOfCar, car)
    if okDrv and driver == ped then
        return "Driving a " .. vname, skin
    end

    local seat = nil
    pcall(function()
        for s = 0, 3 do
            if getCharInCarPassengerSeat(car, s) == ped then
                seat = s
                break
            end
        end
    end)

    if seat ~= nil then
        return ("Passenger %s in a %s"):format(SEAT_NAMES[seat] or ("seat " .. seat), vname), skin
    end
    return "Passenger in a " .. vname, skin
end

local function captureTarget(raw)
    if os.clock() < diedUntil then return end
    local s = stripColors(raw)

    local name = s:match("Target:%s*([^%(\n]+)")
    local pid  = s:match("%((%d+)%)")

    if not name or not pid then return end
    name = (name:gsub("%s+$", ""))

    target.name     = name
    target.pid      = pid
    target.distance = s:match("Distance:%s*(%S+)")
    target.zone     = s:match("Distance:.-%(([%a%s]+)%)")
    target.state, target.skin = readState(target.pid)
    target.active   = true
    target.lastUpdate = os.clock()
    if contract.active and not contract.outcome then
        requestId(target.pid)
    end
end

local function clearTarget()
    target.active = false
    target.name, target.pid, target.distance = nil, nil, nil
    target.zone, target.state, target.skin, target.faction, target.number = nil, nil, nil, nil, nil
    idSentForPid = nil
    backupMode = false
end

local function resetContract()
    contract.active = false
    contract.found  = false
    contract.outcome = nil
    contract.name, contract.pid, contract.sum = nil, nil, nil
    contract.hideFind, contract.hideCheck, contract.hideId, contract.hideNumber = false, false, false, false
    contractIndoors = false
    clearTarget()
end

local function targetLikelyIndoors()

    local d = tonumber((target.distance or ""):match("[%d%.]+"))
    if not d or d > 200 then return false end
    local pid = tonumber(target.pid)
    if not pid then return false end
    local res, ped = sampGetCharHandleBySampPlayerId(pid)
    return not (res and doesCharExist(ped))
end

local function endContract(outcome)
    local cancelled = (outcome == "cancelled")

    local indoors = cancelled and (contractIndoors or targetLikelyIndoors())
    contractIndoors = false

    if feat.keep10s[0] then
        contract.outcome = outcome
        contract.endTime = os.clock()
        clearTarget()
    else
        resetContract()
    end
    secDone = false
    secLoginPhase = false
    if cancelled then
        cancelTime = os.time()
        if indoors then

            secActive = false
            sampAddChatMessage("{5CA3FA}HAC{FFFFFF}: try to take a contract - the target may have been indoors.", -1)
        else

            secActive = true
            secEndTime = cancelTime
        end
    else
        secActive = true
        secEndTime = os.time()
    end
end

local function isTargetTd(id, text)
    if blockedIds[id] then return true end
    if type(text) == "string" and text:find("Target", 1, true) then
        blockedIds[id] = true
        return true
    end
    return false
end

local function isUndercoverTd(id, text)
    if id == undercoverTdId then return true end
    if type(text) == "string" and text:find("UNDERCOVER", 1, true) then
        undercoverTdId = id
        return true
    end
    return false
end

function sampev.onShowTextDraw(id, td)
    local text = td and td.text
    if isUndercoverTd(id, text) then selfUndercover = true end
    if isTargetTd(id, text) then captureTarget(text or "") end
end

function sampev.onTextDrawSetString(id, text)
    if isUndercoverTd(id, text) then selfUndercover = true end
    if isTargetTd(id, text) then captureTarget(text) end
end

function sampev.onTextDrawHide(id)
    if id == undercoverTdId then selfUndercover = false end
end

function sampev.onServerMessage(color, text)
    if type(text) ~= "string" then return end
    text = text:gsub("%[(%d+)%]", "(%1)")

    if os.clock() < secExpect then
        local bare = text:gsub("{%x%x%x%x%x%x}", ""):match("^%s*(%d+)%s*$")
        if bare then
            if secLoginPhase or not secActive then
                secActive = true
                secLoginPhase = true
                secValue = tonumber(bare)
                secLastClk = os.clock()
            end
            secExpect = 0
        end
    end

    if cancelTime > 0 and not secLoginPhase and text:find("Trebuie sa astepti", 1, true) then
        if os.time() - cancelTime < 310 then
            secActive = true
            secEndTime = cancelTime
            secDone = false
        else
            cancelTime = 0
        end
    end

    if text:find("currently inside", 1, true) and (text:find("interior", 1, true) or text:find("house", 1, true)) then
        contractIndoors = true
    end

    if text:find("You have disabled your current checkpoint", 1, true) then
        if os.clock() >= diedUntil and not isCharDead(PLAYER_PED) then clearTarget() end
        if os.clock() < killcpUntil then return false end
        return
    end

    if text:find("you had the checkpoint on", 1, true) and text:find("has disconnected", 1, true) then
        if contract.active then
            endContract("disconnected")
        else
            clearTarget()
        end
        return
    end

    local t = text:lower()
    if t:find("now undercover", 1, true) then
        selfUndercover = true
    elseif t:find("not undercover anymore", 1, true) then
        selfUndercover = false
    end

    if text:find("Anyone can see your name", 1, true) then
        diedUntil = os.clock() + 6
    end

    local who, onoff = text:match("%*?%s*(.-)%s+turns%s+(%a+)%s+.-[Pp]hone")
    if who and onoff then
        if isMe(who) then
            selfPhoneOn = (onoff:lower() == "on")
        end
    end

    if text:find("(Group) MOTD:", 1, true) then
        secActive = true
        secValue = 0
        secLastClk = os.clock()
        secDone = false
        secLoginPhase = true
        cancelTime = 0
    end

    local rcvName, rcvFac = text:match("^(.-) from (.-) received a contract")
    if not rcvName then rcvName = text:match("^(.-) received a contract") end
    if rcvName then
        if isMe(rcvName) then
            secDone = true
            secLoginPhase = false
            cancelTime = 0
            contract.active, contract.found = true, false
            contract.outcome = nil
            contract.name, contract.pid, contract.sum = nil, nil, nil

            report.hideUntil = os.clock() + 12
            sendCommand("/raport", 200)

            if feat.hidecp[0] then
                killcpUntil = os.clock() + 3
                sendCommand("/killcp", 400)
            end
        end
        return
    end

    local cName, cPid = text:match("You have a contract on%s*(.+)%s*%((%d+)%)")
    if not cName then
        cName, cPid = text:match("You have a contract on%s*(.-)%s*%[(%d+)%]%s*$")
    end
    if not cName then
        cName = text:match("You have a contract on%s*(.+)")
    end
    if cName then
        contract.active = true
        contract.name = cleanName(cName)
        if cPid then contract.pid = cPid end

        if cPid and not contract.found then
            contract.found = true
            contract.hideFind, contract.hideCheck = true, true
            sendCommand("/find " .. cPid, 150)
            sendCommand("/checkcontract " .. cPid, 650)
        end
        return
    end

    local fName, fDist = text:match("Checkpoint%-ul va afisa locatia playerului%s*(.-)%.%s*Distanta pana la player:%s*(%d+)")
    if not fName then
        fName, fDist = text:match("The checkpoint has been set on%s*(.-)%.%s*Distance:%s*(%d+)")
    end
    if fName and fDist then
        target.name       = cleanName(fName)
        target.distance   = fDist .. "m"
        target.pid        = contract.pid or target.pid
        target.state, target.skin = readState(target.pid)
        target.active     = true
        target.lastUpdate = os.clock()
        requestId(target.pid)
        if contract.hideFind then
            contract.hideFind = false
            return false
        end
        return
    end

    local sName, sAmt = text:match("^(.-) has a contract of (%$[%d,]+) on him")
    if sName and sAmt then
        contract.sum = sAmt
        if contract.hideCheck then
            contract.hideCheck = false
            return false
        end
        return
    end

    if text:find("Number:", 1, true) then
        local clean = text:gsub("{%x%x%x%x%x%x}", "")
        local tnum = clean:match("Number:%s*(%d+)")
        if not tnum and clean:match("Number:%s*[Nn]one") then tnum = "None" end
        if tnum and clean:find("Name:", 1, true) then

            if smsPending and os.clock() < smsPending.expect then
                local kind = smsPending.kind
                local nm = clean:match("Name:%s*([^|]+)")
                nm = nm and cleanName((nm:gsub("%s+$", ""))) or ("ID " .. smsPending.id)
                smsPending = nil
                if tnum == "None" then
                    sampAddChatMessage("{5CA3FA}HAC{FFFFFF}: " .. nm .. " has no phone number.", -1)
                else
                    local list = messages[kind] or {}
                    local msg = #list > 0 and list[math.random(#list)] or nil
                    if msg then sendCommand("/sms " .. tnum .. " " .. msg) end
                end
                return false
            end
            target.number = (tnum ~= "None") and tnum or nil

            local nPid = clean:match("%((%d+)%)")
            local hide = contract.hideNumber
                or os.clock() < numberExpect
                or (nPid ~= nil and (nPid == contract.pid or nPid == target.pid))
            contract.hideNumber = false
            if hide then return false end
            return
        end
    end

    if text:find("Faction:", 1, true) and text:find("Ping:", 1, true) then
        local idPid = text:match("%((%d+)%)")
        local fac   = text:match("Faction:%s*([^|(]+)")
        if idPid and fac then
            fac = fac:gsub("{%x%x%x%x%x%x}", "")
            fac = (fac:gsub("^%s*(.-)%s*$", "%1"))
            local hide = false
            if os.clock() < idExpect then
                target.faction = FACTION_SHORT[fac] or fac
                contract.hideId = false
                idExpect = 0
                hide = true
            elseif idPid == contract.pid or idPid == target.pid then
                target.faction = FACTION_SHORT[fac] or fac
                if contract.hideId then contract.hideId = false; hide = true end
            end
            if hide then return false end
            return
        end
    end

    if os.clock() < report.hideUntil and text:find("Loading faction activity", 1, true) then
        return false
    end

    if os.clock() < report.expect then
        local rd, rt = text:match("Targets killed:%s*(%d+)%s*/%s*(%d+)")
        if not rd then rd, rt = text:match("Contracte efectuate:%s*(%d+)%s*/%s*(%d+)") end
        if rd and rt then
            report.done, report.total, report.active = rd, rt, true
            if os.clock() < report.hideUntil then return false end
            return
        end

        local rh, rhr = text:match("Hours played:%s*([%d:]+)%s*/%s*([%d:]+)")
        if not rh then rh, rhr = text:match("Ore jucate:%s*([%d:]+)%s*/%s*([%d:]+)") end
        if rh and rhr then
            report.hours, report.hoursReq, report.active = rh, rhr, true
            if os.clock() < report.hideUntil then return false end
            return
        end
    end

    if contract.active then
        local done = text:match("^(.-) from .- has succe.-completed the contract") or text:match("^(.-) has succe.-completed the contract")
        if done and isMe(done) then
            local raw = (text:match("for %$([%d,]+)") or "0"):gsub(",", "")
            local money = tonumber(raw) or 0
            recordContract(true, money)
            endContract("done"); return
        end
        local failed = text:match("^(.-) from .- failed to complete the contract") or text:match("^(.-) failed to complete the contract")
        if failed and isMe(failed) then
            recordContract(false, 0)
            endContract("failed"); return
        end
        local canceled = text:match("^(.-) from .- canceled his contract") or text:match("^(.-) canceled his contract")
        if canceled and isMe(canceled) then endContract("cancelled"); return end
    end
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    if os.clock() < killcpUntil then
        lua_thread.create(function()
            wait(0)
            sampSendDialogResponse(dialogId, 1, 0, "")
        end)
        return false
    end
end

function sampev.onSendCommand(cmd)
    if type(cmd) ~= "string" then return end
    local lc = cmd:lower()
    if lc:find("^/raport") then
        report.expect = os.clock() + 12
    end
    if lc:find("^/sec") then
        secExpect = os.clock() + 4
    end
end

local HUD_WIDTH = 300
local HUD_SCALE = 1.0

local HUD_FLAGS = imgui.WindowFlags.NoTitleBar
    + imgui.WindowFlags.NoResize
    + imgui.WindowFlags.NoMove
    + imgui.WindowFlags.NoScrollbar
    + imgui.WindowFlags.NoScrollWithMouse
    + imgui.WindowFlags.NoCollapse
    + imgui.WindowFlags.NoSavedSettings
    + imgui.WindowFlags.NoFocusOnAppearing
    + imgui.WindowFlags.NoBringToFrontOnFocus
    + imgui.WindowFlags.NoInputs
    + imgui.WindowFlags.AlwaysAutoResize

local HUD_FLAGS_CLICK = imgui.WindowFlags.NoTitleBar
    + imgui.WindowFlags.NoResize
    + imgui.WindowFlags.NoMove
    + imgui.WindowFlags.NoScrollbar
    + imgui.WindowFlags.NoScrollWithMouse
    + imgui.WindowFlags.NoCollapse
    + imgui.WindowFlags.NoSavedSettings
    + imgui.WindowFlags.NoFocusOnAppearing
    + imgui.WindowFlags.NoBringToFrontOnFocus
    + imgui.WindowFlags.AlwaysAutoResize

local FONT_SIZE = 16.0
local WIN_FONTS = (os.getenv("SystemRoot") or "C:\\Windows") .. "\\Fonts\\"
local HUD_FONT = WIN_FONTS .. "trebuc.ttf"
imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
    imgui.GetIO().Fonts:Clear()
    if doesFileExist(HUD_FONT) then
        imgui.GetIO().Fonts:AddFontFromFileTTF(HUD_FONT, FONT_SIZE)
    else
        imgui.GetIO().Fonts:AddFontDefault()
    end
    fa.Init(FONT_SIZE)
end)

local function u32(col) return imgui.ColorConvertFloat4ToU32(col) end

local function cardHeader(ic, title, col)
    local dl = imgui.GetWindowDrawList()
    local sp = imgui.GetCursorScreenPos()
    local w  = imgui.GetContentRegionAvail().x
    local th = imgui.GetTextLineHeight()
    dl:AddRectFilled(ImVec2(sp.x - 6, sp.y - 3), ImVec2(sp.x + w + 6, sp.y + th + 3),
        u32(ImVec4(col.x, col.y, col.z, 0.16)), 4.0)
    imgui.TextColored(col, "%s", icon(ic) .. "  " .. title)
    imgui.Spacing()
end

local function row(ic, label, value, valColor)
    imgui.TextColored(C.dim, "%s", icon(ic) .. "  " .. label)
    imgui.SameLine()
    imgui.TextColored(valColor or C.text, "%s", value)
end

local function drawConsole()

    local showConsole = S.console.enabled[0] and contract.active
    local showTarget  = S.target.enabled[0] and target.active and (contract.active or feat.tgtnoc[0])
    if not (showConsole or showTarget) then return end

    local backupActive = backupMode and contract.active and target.active
    local sw, sh = getScreenResolution()

    imgui.SetNextWindowPos(ImVec2(sw - 16, sh * 0.5), imgui.Cond.Always, ImVec2(1.0, 0.0))
    imgui.SetNextWindowSizeConstraints(ImVec2(HUD_WIDTH, 0), ImVec2(HUD_WIDTH, imgui.FLT_MAX))

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 10.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, ImVec2(12, 10))
    imgui.PushStyleColor(imgui.Col.WindowBg, ImVec4(0.05, 0.05, 0.06, consoleAlpha()))

    imgui.Begin("##hitman_console", nil, backupActive and HUD_FLAGS_CLICK or HUD_FLAGS)
    imgui.SetWindowFontScale(HUD_SCALE)

    if showConsole then
        cardHeader("GUN", "HITMAN CONSOLE", C.title)
        if S.console.phone[0] then
            row("PHONE", "Phone", selfPhoneOn and "ON" or "OFF", selfPhoneOn and C.red or C.green)
        end

        if S.console.distok[0] and not feat.hidecp[0] then
            local d = tonumber((target.distance or ""):match("[%d%.]+"))
            if d and d >= CONTRACT_MIN_DIST then
                row("RULER_HORIZONTAL", "Distance", "Far enough", C.green)
            elseif d then
                row("RULER_HORIZONTAL", "Distance", "Too close", C.red)
            else
                row("RULER_HORIZONTAL", "Distance", "?", C.dim)
            end
        end
        if S.console.reward[0] and contract.sum then
            row("SACK_DOLLAR", "Reward", contract.sum, C.green)
        end
        if S.console.contract[0] then
            if contract.outcome == "done" then
                row("CIRCLE_CHECK", "Contract", "Done", C.green)
            elseif contract.outcome == "failed" then
                row("CIRCLE_XMARK", "Contract", "Failed", C.red)
            elseif contract.outcome == "cancelled" then
                row("BAN", "Contract", "Cancelled", C.red)
            elseif contract.outcome == "disconnected" then
                row("BAN", "Contract", "Disconnected", C.red)
            elseif contract.active then
                row("CROSSHAIRS", "Contract", "In process", C.title)
            else
                row("CROSSHAIRS", "Contract", "Unassigned", C.red)
            end
        end
        if S.console.ammo[0] then
            local ammo = getAmmoInCharWeapon(PLAYER_PED, 34)
            row("GUN", "Sniper Ammo", tostring(ammo), ammo > 0 and C.green or C.red)
        end
    end

    if contract.active and target.active then
        if showConsole then imgui.Spacing() end
        cardHeader("USERS", backupActive and "BACKUP (active)" or "BACKUP (press Y)", C.title)
        local bw = (imgui.GetContentRegionAvail().x - 8) / 2
        imgui.PushStyleColor(imgui.Col.Button, tint(0.20, 0.35, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, tint(0.26, 0.50, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, tint(0.16, 0.30, 1.0))
        local bkChat = backupHi[0] and "/hi" or "/f"
        if imgui.Button("STAY##bk", ImVec2(bw, 26)) then
            sendCommand(bkChat .. " Stai " .. (target.name or "?") .. " (" .. (target.pid or "?") .. "), telefon: " .. (target.number or "?"))
            backupMode = false
        end
        imgui.SameLine()
        if imgui.Button("GET OUT##bk", ImVec2(bw, 26)) then
            sendCommand(bkChat .. " Iesi " .. (target.name or "?") .. " (" .. (target.pid or "?") .. "), telefon: " .. (target.number or "?"))
            backupMode = false
        end
        imgui.PopStyleColor(3)
    end

    if showTarget then
        imgui.Spacing()
        cardHeader("LOCATION_DOT", "TARGET", C.title)
        if S.target.name[0] then row("USER", "Name", target.name or "?", C.text) end
        if S.target.faction[0] and target.faction then row("SHIELD", "Faction", target.faction, C.title) end
        if S.target.state[0] then row("PERSON", "State", target.state or "?", C.green) end
    end

    imgui.End()

    imgui.PopStyleColor(1)
    imgui.PopStyleVar(3)
end

local function drawReport()
    if not report.active then return end
    if not S.report.enabled[0] then return end
    if not contract.active then return end

    local sw, sh = getScreenResolution()

    imgui.SetNextWindowPos(ImVec2(sw - 16, sh * 0.5 - 8), imgui.Cond.Always, ImVec2(1.0, 1.0))
    imgui.SetNextWindowSizeConstraints(ImVec2(HUD_WIDTH, 0), ImVec2(HUD_WIDTH, imgui.FLT_MAX))

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 10.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, ImVec2(12, 10))
    imgui.PushStyleColor(imgui.Col.WindowBg, ImVec4(0.05, 0.05, 0.06, consoleAlpha()))

    imgui.Begin("##hitman_report", nil, HUD_FLAGS)
    imgui.SetWindowFontScale(HUD_SCALE)

    cardHeader("CLIPBOARD_CHECK", "ACTIVITY RAPORT", C.title)
    if S.report.targets[0] then
        row("SKULL", "Targets killed", (report.done or "?") .. "/" .. (report.total or "?"), C.text)
    end
    if S.report.hours[0] then
        row("CLOCK", "Hours played", (report.hours or "?") .. "/" .. (report.hoursReq or "?"), C.text)
    end

    imgui.End()

    imgui.PopStyleColor(1)
    imgui.PopStyleVar(3)
end

local function drawSkin()
    if not target.active then return end
    if not (S.target.enabled[0] and S.target.skin[0]) then return end
    if not (contract.active or feat.tgtnoc[0]) then return end
    local sk = target.skin and getSkinTex(target.skin)
    if not sk then return end

    local sw, sh = getScreenResolution()
    local maxW, maxH = 44, 92
    local SKIN_W_MUL = 1.4
    local SKIN_H_MUL = 2.0
    local scale = math.min(maxW / sk.w, maxH / sk.h)
    local dw, dh = sk.w * scale * SKIN_W_MUL, sk.h * scale * SKIN_H_MUL

    local title = "SKIN " .. tostring(target.skin)
    local headerW = imgui.CalcTextSize(icon("ADDRESS_CARD") .. "  " .. title).x
    local cardW = math.max(dw, headerW)
    local label = sniperAiming and (sniperOnTarget and "ON TARGET" or "OFF TARGET") or nil
    if label then cardW = math.max(cardW, imgui.CalcTextSize(label).x + 14) end

    local rightX = sw - 16 - HUD_WIDTH - 8
    imgui.SetNextWindowPos(ImVec2(rightX, sh * 0.5), imgui.Cond.Always, ImVec2(1.0, 0.0))

    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, ImVec2(6, 6))
    imgui.PushStyleColor(imgui.Col.WindowBg, ImVec4(0.05, 0.05, 0.06, consoleAlpha()))

    imgui.Begin("##hitman_skin", nil, HUD_FLAGS)
    imgui.SetWindowFontScale(HUD_SCALE)

    cardHeader("ADDRESS_CARD", title, C.title)

    imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, (cardW - dw) / 2))
    imgui.Image(sk.tex, ImVec2(dw, dh))

    if label then
        imgui.Spacing()
        local bh = imgui.GetTextLineHeight() + 6
        imgui.InvisibleButton("##aimbar", ImVec2(cardW, bh))
        local mn = imgui.GetItemRectMin()
        local mx = imgui.GetItemRectMax()
        local dl = imgui.GetWindowDrawList()
        local col = sniperOnTarget and ImVec4(0.18, 0.62, 0.24, 0.95) or ImVec4(0.74, 0.20, 0.20, 0.95)
        dl:AddRectFilled(mn, mx, u32(col), 4.0)
        local tsz = imgui.CalcTextSize(label)
        dl:AddText(ImVec2(mn.x + (mx.x - mn.x - tsz.x) / 2, mn.y + (mx.y - mn.y - tsz.y) / 2),
            u32(ImVec4(1, 1, 1, 1)), label)
    end

    imgui.End()
    imgui.PopStyleColor(1)
    imgui.PopStyleVar(3)
end

local consoleFrame
consoleFrame = imgui.OnFrame(
    function()
        local now = os.clock()

        if contract.outcome and (now - contract.endTime > 10) then

            if feat.hidecp[0] and contract.outcome ~= "disconnected" then
                killcpUntil = now + 3
                sendCommand("/killcp", 0)
            end
            resetContract()
        end

        consoleFrame.HideCursor = not (backupMode and contract.active and target.active)
        return target.active or contract.active
    end,
    function()
        drawConsole()
        drawSkin()
        drawReport()
    end
)
consoleFrame.HideCursor = true

local SETTINGS_FLAGS = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoSavedSettings
local CAT_ICON = { report = "CLIPBOARD_CHECK", console = "GUN", target = "LOCATION_DOT" }

local function catHeader(cat, s)
    local dl = imgui.GetWindowDrawList()
    local sp = imgui.GetCursorScreenPos()
    local w  = imgui.GetContentRegionAvail().x
    local h  = imgui.GetFrameHeight()
    local accent = s.enabled[0] and C.title or C.dim
    dl:AddRectFilled(ImVec2(sp.x - 6, sp.y - 2), ImVec2(sp.x + w + 6, sp.y + h + 2),
        u32(ImVec4(accent.x, accent.y, accent.z, 0.18)), 5.0)
    local changed = imgui.Checkbox("##cat_" .. cat.key, s.enabled)
    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    imgui.TextColored(accent, "%s", icon(CAT_ICON[cat.key] or "LIST_CHECK") .. "  " .. cat.title)
    return changed
end

local function sectionHeader(iconName, title)
    local dl = imgui.GetWindowDrawList()
    local sp = imgui.GetCursorScreenPos()
    local w  = imgui.GetContentRegionAvail().x
    local h  = imgui.GetFrameHeight()
    dl:AddRectFilled(ImVec2(sp.x - 6, sp.y - 2), ImVec2(sp.x + w + 6, sp.y + h + 2),
        u32(ImVec4(C.title.x, C.title.y, C.title.z, 0.18)), 5.0)
    imgui.AlignTextToFramePadding()
    imgui.TextColored(C.title, "%s", icon(iconName) .. "  " .. title)
end

local function renderCat(cat)
    local s = S[cat.key]
    local changed = catHeader(cat, s)
    imgui.Indent(20)
    imgui.Spacing()
    for _, it in ipairs(cat.items) do
        if imgui.Checkbox(it.label .. "##" .. cat.key, s[it.key]) then changed = true end
    end
    imgui.Unindent(20)
    imgui.Spacing()
    imgui.Spacing()
    return changed
end

imgui.OnFrame(
    function() return settingsOpen[0] end,
    function()
        local sw, sh = getScreenResolution()
        imgui.SetNextWindowPos(ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(ImVec2(800, 520), imgui.Cond.FirstUseEver)

        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 10.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 4.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.TabRounding, 4.0)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, ImVec2(16, 14))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, ImVec2(8, 8))
        imgui.PushStyleColor(imgui.Col.WindowBg, tint(0.065, 0.05, 0.97))
        imgui.PushStyleColor(imgui.Col.TitleBg, tint(0.085, 0.10, 1.0))
        imgui.PushStyleColor(imgui.Col.TitleBgActive, tint(0.14, 0.30, 1.0))
        imgui.PushStyleColor(imgui.Col.FrameBg, tint(0.14, 0.10, 1.0))
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, tint(0.22, 0.30, 1.0))
        imgui.PushStyleColor(imgui.Col.CheckMark, ImVec4(prim[0], prim[1], prim[2], 1.0))
        imgui.PushStyleColor(imgui.Col.Tab, tint(0.12, 0.12, 1.0))
        imgui.PushStyleColor(imgui.Col.TabHovered, tint(0.30, 0.45, 1.0))
        imgui.PushStyleColor(imgui.Col.TabActive, tint(0.30, 0.62, 1.0))
        imgui.PushStyleColor(imgui.Col.Separator, ImVec4(prim[0], prim[1], prim[2], 0.45))
        imgui.PushStyleColor(imgui.Col.Button, tint(0.20, 0.35, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, tint(0.26, 0.50, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, tint(0.16, 0.30, 1.0))
        imgui.PushStyleColor(imgui.Col.SliderGrab, tint(0.30, 0.55, 1.0))
        imgui.PushStyleColor(imgui.Col.SliderGrabActive, ImVec4(prim[0], prim[1], prim[2], 1.0))

        imgui.Begin("Hitman Console (last update: 03.07.2026)###hitman_settings", settingsOpen, SETTINGS_FLAGS)
        imgui.SetWindowFontScale(HUD_SCALE)

        local dirty = false

        if imgui.BeginTabBar("##hc_tabs") then

            if updateInfo.available then
                if imgui.BeginTabItem("  Update  ") then
                    imgui.Spacing()
                    sectionHeader("CIRCLE_UP", "Update available")
                    imgui.Spacing()
                    imgui.TextColored(C.green, "%s",
                        string.format("Version %s is available, your current version: %s.",
                            tostring(updateInfo.version), MOD_VERSION))
                    if updateInfo.date then
                        imgui.Spacing()
                        imgui.TextColored(C.dim, "%s", "Released: " .. updateInfo.date)
                    end
                    imgui.Spacing()
                    imgui.Spacing()
                    if updateState == "working" then
                        imgui.TextColored(C.dim, "%s", "Updating, please wait...")
                    elseif updateState == "done" then
                        imgui.TextColored(C.green, "%s", "Updated! Reloading...")
                    else
                        imgui.PushStyleColor(imgui.Col.Button, ImVec4(0.18, 0.55, 0.22, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, ImVec4(0.24, 0.68, 0.30, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonActive, ImVec4(0.14, 0.45, 0.18, 1.0))
                        if imgui.Button(icon("DOWNLOAD") .. "  Update now", ImVec2(200, 32)) then
                            doUpdate()
                        end
                        imgui.PopStyleColor(3)
                        if updateState == "failed" then
                            imgui.Spacing()
                            imgui.TextColored(C.red, "%s", "Update failed. Try again, or download manually:")
                            if updateInfo.url then
                                imgui.TextColored(C.dim, "%s", updateInfo.url)
                            end
                        end
                    end
                    imgui.EndTabItem()
                end
            end

            if imgui.BeginTabItem("  Visible info  ") then
                imgui.Spacing()
                imgui.TextColored(C.dim, "%s", "Toggle a category to hide it entirely; check the items you want to see.")
                imgui.Spacing()

                imgui.Columns(2, "##viscols", false)
                if renderCat(SCHEMA[1]) then dirty = true end
                if renderCat(SCHEMA[2]) then dirty = true end
                imgui.NextColumn()
                if renderCat(SCHEMA[3]) then dirty = true end
                imgui.Columns(1)
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("  Settings & Features  ") then
                imgui.Spacing()

                imgui.Columns(2, "##setcols", false)

                sectionHeader("LIST_CHECK", "Features")
                imgui.Spacing()
                for _, ft in ipairs(FEATURES) do
                    if imgui.Checkbox(ft.label .. "##feat", feat[ft.key]) then dirty = true end
                    imgui.Spacing()
                end

                imgui.Spacing()
                sectionHeader("COMMENTS", "Backup chat")
                imgui.Spacing()
                imgui.TextColored(C.dim, "%s", "Where the Stay / Get Out messages are sent.")
                imgui.Spacing()
                local fActive = not backupHi[0]
                imgui.PushStyleColor(imgui.Col.Button, fActive and tint(0.20, 0.35, 1.0) or ImVec4(0.16, 0.17, 0.22, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, fActive and tint(0.26, 0.50, 1.0) or ImVec4(0.24, 0.25, 0.32, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive, fActive and tint(0.16, 0.30, 1.0) or ImVec4(0.16, 0.17, 0.22, 1.0))
                if imgui.Button("Faction chat (/f)##bkf", ImVec2(160, 26)) then backupHi[0] = false; dirty = true end
                imgui.PopStyleColor(3)

                imgui.Spacing()

                local hActive = backupHi[0]
                imgui.PushStyleColor(imgui.Col.Button, hActive and tint(0.20, 0.35, 1.0) or ImVec4(0.16, 0.17, 0.22, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, hActive and tint(0.26, 0.50, 1.0) or ImVec4(0.24, 0.25, 0.32, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonActive, hActive and tint(0.16, 0.30, 1.0) or ImVec4(0.16, 0.17, 0.22, 1.0))
                if imgui.Button("Hitmans chat (/hi)##bkh", ImVec2(160, 26)) then backupHi[0] = true; dirty = true end
                imgui.PopStyleColor(3)

                imgui.NextColumn()

                sectionHeader("PALETTE", "Appearance")
                imgui.Spacing()
                if imgui.ColorEdit3("Primary color##primary", prim, imgui.ColorEditFlags.NoInputs) then
                    applyPrimary()
                    dirty = true
                end
                imgui.TextColored(C.dim, "%s", "Click the swatch to open the picker.")
                imgui.Spacing()
                if imgui.Button("Reset to default blue##resetcol", ImVec2(190, 0)) then
                    prim[0], prim[1], prim[2] = 0.36, 0.64, 0.98
                    applyPrimary()
                    dirty = true
                end

                imgui.Spacing()
                imgui.Spacing()
                imgui.TextColored(C.dim, "%s", "Console opacity")
                imgui.PushItemWidth(190)
                if imgui.SliderInt("##opacity", opacity, 40, 100, "%d%%") then dirty = true end
                imgui.PopItemWidth()

                imgui.Columns(1)
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem("  Stats  ") then
                imgui.Spacing()

                local months = {}
                local tC, tM, tS, tF = 0, 0, 0, 0
                for day, d in pairs(stats) do
                    local ym = day:sub(1, 7)
                    local mo = months[ym]
                    if not mo then mo = { contracts = 0, money = 0, success = 0, failed = 0, days = {} }; months[ym] = mo end
                    mo.contracts = mo.contracts + d.contracts
                    mo.money     = mo.money + d.money
                    mo.success   = mo.success + d.success
                    mo.failed    = mo.failed + d.failed
                    mo.days[#mo.days + 1] = day
                    tC, tM, tS, tF = tC + d.contracts, tM + d.money, tS + d.success, tF + d.failed
                end

                cardHeader("CHART_SIMPLE", "ALL TIME", C.title)
                row("CROSSHAIRS", "Contracts", tostring(tC), C.text)
                row("SACK_DOLLAR", "Earned", "$" .. commas(tM), C.green)
                row("CIRCLE_CHECK", "Success", tostring(tS), C.green)
                row("CIRCLE_XMARK", "Failed", tostring(tF), C.red)

                if tC == 0 then
                    imgui.Spacing()
                    imgui.TextColored(C.dim, "%s", "No contracts recorded yet.")
                else
                    local mk = {}
                    for ym in pairs(months) do mk[#mk + 1] = ym end
                    table.sort(mk, function(a, b) return a > b end)
                    for _, ym in ipairs(mk) do
                        local mo = months[ym]
                        imgui.Spacing()
                        cardHeader("CLIPBOARD_CHECK", monthLabel(ym), C.title)
                        row("CROSSHAIRS", "Total",
                            string.format("%d contracts   $%s   %d done / %d failed", mo.contracts, commas(mo.money), mo.success, mo.failed), C.text)
                        table.sort(mo.days, function(a, b) return a > b end)
                        imgui.Indent(22)
                        for _, day in ipairs(mo.days) do
                            local d = stats[day]
                            imgui.TextColored(C.dim, "%s",
                                string.format("%s:   %d ctc   $%s   %d done / %d failed", day:sub(9, 10), d.contracts, commas(d.money), d.success, d.failed))
                        end
                        imgui.Unindent(22)
                    end
                end
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end

        imgui.End()
        imgui.PopStyleColor(15)
        imgui.PopStyleVar(5)

        if dirty then saveData() end
    end
)
