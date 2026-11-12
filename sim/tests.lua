-- Forever Floating Text's test suite: exact checks, each a short scripted moment of play run
-- through the addon's real code in the fake game (wowstub.lua). Run from the addon's folder:
--   lua5.3 sim/tests.lua
-- Exits with 1 if any test fails. Every test also fails on any Lua error during it: the fake
-- game's hidden values throw when compared or used in math, as the game's do.
-- The timings in these tests are the ones measured in the author's logs (dates in the names).

local READ = READ_FILE or function(path)
    local f = assert(io.open(path, "rb"), "can't open " .. path .. " (run from the addon's folder)")
    local text = f:read("*a")
    f:close()
    return text
end
local PRINT = print -- the fake game's print keeps the addon's chat messages instead
local ADDON = "ForeverFloatingText"
local FILES = {"Core.lua", "Spots.lua", "Heals.lua", "Incoming.lua", "Alerts.lua", "Procs.lua", "Loot.lua", "Notices.lua"}

------------------------------------------------------------------------
-- A fresh game for each test
------------------------------------------------------------------------
local G -- the current test's game

local function NewGame(opt)
    opt = opt or {}
    assert(load(READ("sim/wowstub.lua"), "@wowstub.lua"))()
    function hooksecurefunc(t, name, fn)
        local orig = t[name]
        t[name] = function(...) local r = orig(...); fn(...); return r end
    end
    MANA, AURA_END = "Mana", "<%s> fades"
    GetFramerate = nil -- a test at another frame rate sets it (and SIM.FRAME) after NewGame
    UnitClass = nil -- not in the stub: no class; a test sets it after NewGame (Shaman())
    function UnitPowerType() return 0, "MANA" end
    local feed = {n = 0}
    C_CombatText = {
        GetCurrentEventInfo = function() return table.unpack(feed, 1, feed.n) end,
        GetActiveUnit = function() return "player" end, SetActiveUnit = function() end,
    }
    local form
    function GetShapeshiftFormID() return form end
    -- Stormstrike's cooldown as the game reports it (isActive / isOnGCD are never secret)
    local cooldown = {isActive = false, isOnGCD = false, startTime = 0, duration = 0}
    C_Spell.GetSpellCooldown = function() return cooldown end
    for k, v in pairs(opt.cvars or {}) do SIM.cvars[k] = v end
    if opt.filters then
        for i, f in ipairs(opt.filters) do Blizzard_CombatLog_Filters.filters[i] = f end
        Blizzard_CombatLog_Filters.currentFilter = opt.currentFilter or 1
    end
    ForeverFloatingTextDB = opt.db or {}
    ForeverFloatingTextLog = nil
    local ns = {}
    for _, name in ipairs(FILES) do assert(load(READ(name), "@" .. name))(ADDON, ns) end
    local FFT = ns.FFT
    local g = {ns = ns, FFT = FFT, shown = {}, castN = 0, procs = {}}
    local realShow = FFT.Show
    FFT.Show = function(self, plate, text, color, crit, o)
        local args = {}
        for i, a in ipairs(o and o.args or {}) do args[i] = SIM.Reveal(a) end
        g.shown[#g.shown + 1] = {t = SIM.now, plate = plate, text = text, fmt = o and o.fmt, args = args,
            key = o and o.key, color = color, crit = crit}
        return realShow(self, plate, text, color, crit, o)
    end
    -- (1.31.0) the procs spot (Procs.lua): what was shown there, with hidden names revealed
    local realProc = FFT.ProcShow
    FFT.ProcShow = function(self, key, color, text, fmt, args, seconds)
        local a = {}
        for i, x in ipairs(args or {}) do a[i] = SIM.Reveal(x) end
        g.procs[#g.procs + 1] = {t = SIM.now, key = key, text = text, fmt = fmt, args = a, color = color}
        return realProc(self, key, color, text, fmt, args, seconds)
    end
    SIM.units.player = {guid = "Player-1-0001", name = "You"}
    SIM.AddUnit("nameplate1", {guid = "Creature-0-1-1-1-1-MOB", name = "Mob", enemy = true})
    SIM.AddUnit("nameplate2", {guid = "Creature-0-1-1-1-2-MOB", name = "Mob 2", enemy = true})
    SIM.target = "nameplate1"
    SIM.spells[17364] = {name = "Stormstrike", harmful = true}
    SIM.spells[8042] = {name = "Earth Shock", harmful = true}
    SIM.spells[36936] = {name = "Totemic Recall"}
    SIM.spells[133] = {name = "Fireball", harmful = true}
    SIM.Fire("ADDON_LOADED", ADDON)
    if opt.ownFilter ~= false then FFT:WriteOwnClogFilter() end -- as the addon did at the last logout
    SIM.Fire("PLAYER_LOGIN")
    SlashCmdList.FOREVERFLOATINGTEXT("debug")
    SIM.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    SIM.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
    SIM.inCombat = true
    SIM.Fire("PLAYER_REGEN_DISABLED")
    SIM.inCombat = false -- the CVar changes in these tests happen out of combat
    g.feed = feed
    g.SetForm = function(f) form = f end
    g.SetCooldown = function(active, gcd) cooldown = active == nil and nil or {isActive = active, isOnGCD = gcd or false} end
    G = g
    return g
end

-- What happens in the game (times in seconds from the start of the test)
local function At(t, fn) SIM.At(t, fn) end
local function Run(t) SIM.RunUntil(t) end
local function Swing(speed, missed)
    SIM.Fire("PLAYER_SWING", speed or 3.30, 0)
    SIM.ClogLine(missed and "SWING_MISSED" or "SWING_DAMAGE", missed)
end
local function Cast(id, notSent)
    G.castN = G.castN + 1
    local guid = "Cast-3-0-0-" .. id .. "-" .. G.castN
    if not notSent then SIM.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", guid, id) end
    SIM.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id)
    SIM.ClogLine("SPELL_CAST_SUCCESS")
end
local function Hit(unit, school, flag, amount)
    SIM.Fire("UNIT_COMBAT", unit or "nameplate1", "WOUND", flag or "", SIM.Secret(amount or 100), school or 1)
end
local function Miss(unit, what) SIM.Fire("UNIT_COMBAT", unit or "nameplate1", what or "PARRY", "", SIM.Secret(0), 1) end
local function Line(event, missType) SIM.ClogLine(event, missType) end
local function Feed(kind, ...)
    local v = {...}
    G.feed.n = select("#", ...)
    for i = 1, 8 do G.feed[i] = v[i] end
    SIM.Fire("COMBAT_TEXT_UPDATE", kind)
end
local function HealOn(unit, amount) SIM.Fire("UNIT_COMBAT", unit, "HEAL", "", SIM.Secret(amount), 8) end

-- What the addon did
local function Decisions(what)
    local out = {}
    for _, l in ipairs(ForeverFloatingTextLog.lines) do
        if l:find("^%d+%.%d+   " .. what) then out[#out + 1] = l end
    end
    return out
end
local function Shown(key)
    local out = {}
    for _, s in ipairs(G.shown) do if key == nil or s.key == key then out[#out + 1] = s end end
    return out
end
local function Count(list, pattern)
    local n = 0
    for _, l in ipairs(list) do if l:find(pattern, 1, true) then n = n + 1 end end
    return n
end

------------------------------------------------------------------------
-- Checks
------------------------------------------------------------------------
local function Eq(got, want, what)
    if got ~= want then error(("%s: got %s, want %s"):format(what, tostring(got), tostring(want)), 2) end
end
local function Ok(cond, what) if not cond then error(what, 2) end end

local tests = {}
local function Test(name, fn) tests[#tests + 1] = {name = name, fn = fn} end

------------------------------------------------------------------------
-- The files and loading
------------------------------------------------------------------------
Test("the .toc lists the files the game loads, in order", function()
    local toc = READ(ADDON .. ".toc")
    local files = {}
    for line in toc:gmatch("[^\r\n]+") do
        if not line:find("^#") and line:find("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
    end
    Eq(table.concat(files, " "), "Core.lua Spots.lua Heals.lua Incoming.lua Alerts.lua Procs.lua Loot.lua Notices.lua Options.lua", "files")
    Eq(toc:match("## Interface: (%d+)"), "16001", "made for WoW: Forever")
    Ok(toc:find("## SavedVariables: ForeverFloatingTextDB, ForeverFloatingTextLog", 1, true), "saved variables")
    Ok(toc:match("## Version: (%d+%.%d+%.%d+)"), "a version")
    for _, f in ipairs(files) do Ok(load(READ(f), "@" .. f), f .. " compiles") end
end)

Test("it loads with no error, and /fft is its command", function()
    NewGame()
    Eq(SLASH_FOREVERFLOATINGTEXT1, "/fft", "slash command")
    Ok(type(SlashCmdList.FOREVERFLOATINGTEXT) == "function", "slash handler")
    Ok(G.FFT:ClogActive(), "the Combat Log is in use")
end)

------------------------------------------------------------------------
-- Blizzard's settings and the Combat Log filter
------------------------------------------------------------------------
local OWN = {
    floatingCombatTextCombatDamage_v2 = "1", floatingCombatTextCombatHealing_v2 = "1",
    floatingCombatTextCombatLogPeriodicSpells_v2 = "1", floatingCombatTextPetMeleeDamage_v2 = "1",
    floatingCombatTextPetSpellDamage_v2 = "1", floatingCombatTextSpellMechanics_v2 = "1",
    enableFloatingCombatText = "0", floatingCombatTextEnergyGains_v2 = "0",
    floatingCombatTextPeriodicEnergyGains_v2 = "0", floatingCombatTextCombatState_v2 = "0",
}

Test("Blizzard's numbers are hidden while playing, the feed is on", function()
    NewGame({cvars = OWN})
    Eq(SIM.cvars.floatingCombatTextCombatDamage_v2, "0", "damage numbers over mobs")
    Eq(SIM.cvars.floatingCombatTextCombatHealing_v2, "0", "heal numbers")
    Eq(SIM.cvars.enableFloatingCombatText, "1", "the feed's CVar")
    Eq(SIM.cvars.floatingCombatTextPeriodicEnergyGains_v2, "1", "periodic energy gains (the feed)")
end)

Test("every logout puts the player's own settings back, and the next login hides them again", function()
    NewGame({cvars = OWN})
    SIM.Fire("PLAYER_LOGOUT")
    for k, v in pairs(OWN) do Eq(SIM.cvars[k], v, k .. " after logout") end
    local cvars, db = {}, ForeverFloatingTextDB
    for k, v in pairs(SIM.cvars) do cvars[k] = v end
    NewGame({cvars = cvars, db = db})
    Eq(SIM.cvars.floatingCombatTextCombatDamage_v2, "0", "hidden again at the next login")
    SIM.inCombat = true -- a /reload in a fight
    SIM.Fire("PLAYER_LOGOUT")
    for k, v in pairs(OWN) do Eq(SIM.cvars[k], v, k .. " after a /reload in combat") end
end)

Test("turning the addon off gives Blizzard's settings back at once", function()
    NewGame({cvars = OWN})
    ForeverFloatingTextDB.enabled = false
    G.FFT:ApplyBlizzardText()
    for k, v in pairs(OWN) do Eq(SIM.cvars[k], v, k) end
end)

Test("the old OwnCombatText filter is taken over at login and renamed at logout", function()
    NewGame({ownFilter = false, currentFilter = 2, filters = {
        {name = "My actions", settings = {}, colors = {}, filters = {{}}},
        {name = "OwnCombatText", quickButtonName = "OwnCombatText", settings = {}, colors = {}, filters = {{}}},
    }})
    Ok(G.FFT:OwnFilterInUse(), "in use at the first login")
    SIM.Fire("PLAYER_LOGOUT")
    local f = Blizzard_CombatLog_Filters
    Eq(#f.filters, 2, "no second filter")
    Eq(f.filters[2].name, "Forever Floating Text", "renamed")
    Eq(f.currentFilter, 2, "still selected")
end)

------------------------------------------------------------------------
-- Power gains and buffs (the combat text feed)
------------------------------------------------------------------------
-- (1.30.3) resource gains show at the incoming spot: the "+%s" ones there
local function PowerShown()
    local out = {}
    for _, s in ipairs(Shown("incoming")) do if s.fmt and s.fmt:find("^%+%%s") then out[#out + 1] = s end end
    return out
end
Test("Mana Spring ticks show, hidden or not; a gain of 0 doesn't", function()
    NewGame()
    ForeverFloatingTextDB.showPeriodicPower = true -- (1.31.0) off by default
    At(1, function() Feed("PERIODIC_ENERGIZE", 10, "MANA") end)
    At(2, function() Feed("PERIODIC_ENERGIZE", SIM.Secret(10), SIM.Secret("MANA")) end)
    At(3, function() Feed("PERIODIC_ENERGIZE", 0, "MANA") end)
    Run(4)
    local p = PowerShown()
    Eq(#p, 2, "gains shown")
    Eq(p[1].fmt, "+%s Mana", "named by the game's string")
    Eq(p[1].args[1], 10, "the amount")
    Eq(p[2].args[1], 10, "a hidden amount, drawn as it is")
end)

Test("a gain that comes by UNIT_COMBAT and the feed shows once", function()
    NewGame()
    At(1, function()
        SIM.Fire("UNIT_COMBAT", "player", "ENERGIZE", "", 50, 0)
        Feed("ENERGIZE", 50, "MANA")
    end)
    Run(2)
    Eq(#PowerShown(), 1, "shown once")
end)

Test("buffs gained and faded show at the buffs spot; fades only when chosen", function()
    NewGame()
    ForeverFloatingTextDB.showAuraFades = true
    At(1, function() Feed("SPELL_AURA_START", SIM.Secret("Lightning Shield")) end)
    At(2, function() Feed("SPELL_AURA_END_HARMFUL", "Frost Nova") end)
    At(3, function() Feed("SPELL_AURA_END", nil) end) -- nothing to name: skipped
    Run(4)
    local a = {}
    for _, s in ipairs(Shown("buffs")) do if s.fmt then a[#a + 1] = s end end
    Eq(#a, 2, "auras shown")
    Eq(a[1].fmt, "<%s>", "gained")
    Eq(a[2].fmt, "<%s> fades", "faded, the game's AURA_END")
    for _, s in ipairs(Shown("alerts")) do Ok(not s.fmt, "none at the alerts spot") end
    ForeverFloatingTextDB.showAuraFades = false -- the default (1.31.0)
    At(5, function() Feed("SPELL_AURA_END", SIM.Secret("Lightning Shield")) end)
    Run(6)
    local n = 0
    for _, s in ipairs(Shown("buffs")) do if s.fmt then n = n + 1 end end
    Eq(n, 2, "fades off: not shown")
end)

Test("the UNIT_AURA probe logs added and removed auras, hidden values too, and shows nothing", function()
    NewGame()
    At(1, function()
        SIM.Fire("UNIT_AURA", "player", {addedAuras = {{name = SIM.Secret("Strength of Earth"),
            spellId = SIM.Secret(8076), auraInstanceID = SIM.Secret(41), sourceUnit = SIM.Secret("player"),
            isFromPlayerOrPlayerPet = SIM.Secret(true), isHelpful = SIM.Secret(true), duration = SIM.Secret(0)}}})
    end)
    At(2, function() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {41}}) end)
    At(3, function() SIM.Fire("UNIT_AURA", "player", {updatedAuraInstanceIDs = {41}}) end) -- not logged
    At(4, function() SIM.Fire("UNIT_AURA", "player", SIM.Secret({})) end)
    Run(5)
    local logged = 0
    for _, l in ipairs(ForeverFloatingTextLog.lines) do
        if l:find("UNIT_AURA player", 1, true) then logged = logged + 1 end
        Ok(not l:find("probe failed", 1, true), "probe failed: " .. l)
    end
    Eq(logged, 3, "added, removed, secret info")
    local a = 0
    for _, s in ipairs(Shown("buffs")) do if s.fmt then a = a + 1 end end
    Eq(a, 0, "nothing shown: hidden 'yours' with no cast of yours, a hidden id")
end)

-- Blizzard's CombatText frame, as CombatText.lua: it marks itself lowHealth / lowMana as it crosses
-- 20%, worked out from values hidden from addons, and does nothing while not visible
local function BlizzardCombatText(level)
    local f = SIM.NewFrame("Frame", "CombatText")
    f:RegisterEvent("UNIT_HEALTH")
    f:RegisterEvent("UNIT_POWER_UPDATE")
    f:SetScript("OnEvent", function(self, event, unit)
        if not self:IsVisible() or unit ~= "player" then return end
        if event == "UNIT_HEALTH" then self.lowHealth = level.health <= 0.2 and 1 or nil end
        if event == "UNIT_POWER_UPDATE" then self.lowMana = level.mana <= 0.2 and 1 or nil end
    end)
    return f
end
local function LowTexts()
    local n = {}
    for _, s in ipairs(G.procs) do -- (1.31.0) at the procs spot, kept while it lasts
        if s.text == "Mana Low" or s.text == "Health Low" then n[#n + 1] = s.text end
    end
    return n
end

Test("low mana / health: Blizzard's frame runs unseen, its warning shows at the alerts spot", function()
    NewGame()
    local level = {health = 1, mana = 1}
    local f = BlizzardCombatText(level)
    G.FFT:ApplyBlizzardCombatTextFrame()
    Ok(f:IsShown() and f:GetAlpha() == 0, "kept shown, unseen")
    At(1, function() level.mana = 0.5; SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end)
    At(2, function() level.mana = 0.19; SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end)
    At(2.5, function() SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end) -- still low: once
    At(3, function() level.mana = 0.25; SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end)
    At(4, function() level.mana = 0.15; SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end) -- within 5 s: not again
    At(10, function() level.mana = 0.5; SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end)
    At(11, function() level.mana = 0.1; SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end) -- again
    At(12, function() level.health = 0.1; SIM.Fire("UNIT_HEALTH", "player") end)
    Run(13)
    local t = LowTexts()
    Eq(#t, 3, "Mana Low twice, Health Low once")
    Eq(t[3], "Health Low", "the game's words")
end)

Test("low mana / health off: Blizzard's frame hidden as before, nothing shown", function()
    NewGame()
    ForeverFloatingTextDB.showLowWarnings = false
    local level = {health = 1, mana = 0.1}
    local f = BlizzardCombatText(level)
    G.FFT:ApplyBlizzardCombatTextFrame()
    Ok(not f:IsShown(), "hidden")
    At(1, function() SIM.Fire("UNIT_POWER_UPDATE", "player", "MANA") end)
    Run(2)
    Eq(#LowTexts(), 0, "nothing")
    ForeverFloatingTextDB.showLowWarnings = true
    G.FFT:ApplyBlizzardCombatTextFrame()
    Ok(f:IsShown() and f:GetAlpha() == 0, "turned on again: shown, unseen")
end)

-- 2026-11-10, in game: a `show` written by the addon made Blizzard's combat text fail (tainted)
Test("Blizzard's combat text kinds are only ever cleared, never set by the addon", function()
    NewGame({db = {showAuras = false}})
    BlizzardCombatText({health = 1, mana = 1})
    CombatTextTypeInfo = {
        SPELL_AURA_START = {cvar = "floatingCombatTextAuras_v2", show = "Blizzard's"},
        ENERGIZE = {cvar = "floatingCombatTextEnergyGains_v2", show = "Blizzard's"},
    }
    G.FFT:ApplyBlizzardCombatTextFrame()
    Eq(CombatTextTypeInfo.SPELL_AURA_START.show, "Blizzard's", "buffs off: Blizzard's own value left alone")
    Eq(CombatTextTypeInfo.ENERGIZE.show, nil, "power gains on: cleared")
    ForeverFloatingTextDB.showPower = false
    G.FFT:ApplyBlizzardCombatTextFrame()
    Eq(CombatTextTypeInfo.ENERGIZE.show, nil, "turned off: not set by the addon")
    CombatTextTypeInfo = nil
end)

-- 2026-11-10 12:33 log, 7406.506: the read after combat came 0.03 s into the next fight and failed
Test("your buffs aren't read while the game hides auras", function()
    NewGame()
    C_Secrets = {ShouldAurasBeSecret = function() return true end}
    C_UnitAuras = {GetAuraDataByIndex = function() error("Auras cannot be accessed when secret") end}
    At(1, function() SIM.Fire("PLAYER_REGEN_ENABLED") end)
    Run(2)
    for _, l in ipairs(ForeverFloatingTextLog.lines) do
        Ok(not l:find("read failed", 1, true), "the read was tried: " .. l)
    end
    C_Secrets, C_UnitAuras = nil, nil
end)

local function AllAuras()
    ForeverFloatingTextDB.showAuraFades, ForeverFloatingTextDB.showTotemBuffs = true, true
end

-- totem buffs (2026-11-10 08:10 log, out of combat): UNIT_AURA only, the feed brings nothing
local function TotemAura(name, id, extra)
    local a = {name = name, spellId = 8162, auraInstanceID = id, sourceUnit = "nameplate2",
        isFromPlayerOrPlayerPet = true, isHelpful = true, duration = 0}
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end
local function AuraTexts()
    local out = {}
    for _, s in ipairs(Shown("buffs")) do -- (1.31.0) their own spot
        if s.fmt then out[#out + 1] = s.fmt:gsub("%%s", tostring(s.args and s.args[1])) end
    end
    return out
end

Test("a totem's buff shows when placed and fades when recalled", function()
    NewGame()
    AllAuras() -- (1.31.0) fades and totem buffs are off by default
    At(1, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 515)}}) end)
    At(2, function() SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Healing Stream", 517, {sourceUnit = "player"})}}) end)
    At(4, function() Cast(36936); SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {515, 517}}) end)
    At(5, function() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {513}}) end) -- from before: no name
    Run(6)
    local t = AuraTexts()
    Eq(#t, 4, "two gained, two faded")
    Eq(t[1], "<Strength of Earth>", "gained")
    Eq(t[3], "<Strength of Earth> fades", "faded, the game's AURA_END")
end)

-- 2026-11-10 10:31 log, 159.203: Grounding Totem's buff "from nil, mine false" before its totem's plate
Test("a buff with no source in your cast's frame is yours (Grounding Totem); elsewhere not", function()
    NewGame()
    AllAuras() -- (1.31.0) fades and totem buffs are off by default
    local function NoSource(name, id)
        local a = TotemAura(name, id, {isFromPlayerOrPlayerPet = false})
        a.sourceUnit = nil
        return a
    end
    At(1, function() Cast(8177); SIM.Fire("UNIT_AURA", "player", {addedAuras = {NoSource("Grounding Totem", 63)}}) end)
    At(3, function() SIM.Fire("UNIT_AURA", "player", {addedAuras = {NoSource("Someone's", 64)}}) end)
    At(5, function() Cast(36936); SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {63, 64}}) end)
    Run(6)
    local t = AuraTexts()
    Eq(#t, 2, "Grounding gained and faded only")
    Eq(t[1], "<Grounding Totem>", "gained")
    Eq(t[2], "<Grounding Totem> fades", "faded")
end)

-- 2026-11-10 10:36 log: in combat the whole added / removed list is hidden
local function TotemSpells()
    SIM.spells[8160] = {name = "Strength of Earth Totem"}
    SIM.spells[5394] = {name = "Healing Stream Totem"}
    SIM.spells[6363] = {name = "Searing Totem"}
    SIM.spells[66842] = {name = "Call of the Elements"}
    SIM.spells[36936] = {name = "Totemic Recall"}
end
local function HiddenAdd() SIM.Fire("UNIT_AURA", "player", {addedAuras = SIM.Secret({})}) end
local function HiddenRemove() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = SIM.Secret({})}) end

Test("in combat (all hidden), a totem's buff and its recall show what was learned out of combat", function()
    NewGame()
    AllAuras() -- (1.31.0) fades and totem buffs are off by default
    TotemSpells()
    At(1, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 70)}}) end)
    At(3, function() Cast(36936); SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {70}}) end)
    At(5, function() Cast(8160); HiddenAdd() end)
    At(7, function() Cast(36936); HiddenRemove() end)
    At(8, function() Cast(36936); HiddenRemove() end) -- nothing up any more
    Run(9)
    local t = AuraTexts()
    Eq(#t, 4, "gained and faded, twice")
    Eq(t[3], "<Strength of Earth>", "in combat, gained")
    Eq(t[4], "<Strength of Earth> fades", "in combat, faded")
    Ok(ForeverFloatingTextDB.auraCasts[8160].gives == "Strength of Earth", "kept in the saved variables")
end)

Test("Call of the Elements: each buff learned for its own totem, then shown in combat", function()
    NewGame()
    AllAuras() -- (1.31.0) fades and totem buffs are off by default
    TotemSpells()
    local function CotE() Cast(66842); Cast(6363, true); Cast(8160, true); Cast(5394, true) end
    At(1, function()
        CotE()
        SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 80), TotemAura("Healing Stream", 81)}})
    end)
    At(3, function() CotE() end)
    At(3.1, function() HiddenAdd() end) -- 0.10 s after, as in the 08:10 log
    Run(4)
    local t = AuraTexts()
    Eq(#t, 4, "two out of combat, two in combat")
    Eq(ForeverFloatingTextDB.auraCasts[5394].gives, "Healing Stream", "learned by name")
    Ok(not ForeverFloatingTextDB.auraCasts[6363], "Searing Totem gives nothing")
end)

Test("in combat: nothing learned, or a hidden change with no cast of yours (out of range): nothing", function()
    NewGame()
    TotemSpells()
    At(1, function() Cast(8160); HiddenAdd() end) -- never seen out of combat
    At(3, function() HiddenRemove() end)
    Run(4)
    Eq(#AuraTexts(), 0, "nothing")
end)

-- 10:31 log, 117.923: a buff from before the /reload faded with no name
Test("your buffs at load are read, so they can fade by name", function()
    NewGame()
    AllAuras() -- (1.31.0) fades and totem buffs are off by default
    local now = {TotemAura("Strength of Earth", 11), TotemAura("Blessing of Wisdom", 12, {isFromPlayerOrPlayerPet = false})}
    C_UnitAuras = {GetAuraDataByIndex = function(unit, i) return unit == "player" and now[i] or nil end}
    At(1, function() SIM.Fire("PLAYER_ENTERING_WORLD") end)
    At(2, function() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {11, 12}}) end)
    Run(3)
    local t = AuraTexts()
    Eq(#t, 1, "yours only")
    Eq(t[1], "<Strength of Earth> fades", "faded by name")
end)

Test("a buff the feed shows too (Ghost Wolf) shows once, gained and faded", function()
    NewGame()
    AllAuras() -- (1.31.0) fades and totem buffs are off by default
    At(1, function()
        Feed("SPELL_AURA_START", SIM.Secret("Ghost Wolf"))
        SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Ghost Wolf", 600, {sourceUnit = "player"})}})
    end)
    At(3, function()
        SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {600}})
        Feed("SPELL_AURA_END", SIM.Secret("Ghost Wolf")) -- after it in the frame
    end)
    Run(4)
    Eq(#AuraTexts(), 2, "the feed's two only")
end)

Test("someone else's buff, or a debuff, from UNIT_AURA: nothing", function()
    NewGame()
    At(1, function() SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 700, {isFromPlayerOrPlayerPet = false})}}) end)
    At(2, function() SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Frost Nova", 701, {isHelpful = false})}}) end)
    At(3, function() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {700, 701}}) end)
    Run(4)
    Eq(#AuraTexts(), 0, "nothing")
end)

Test("hidden values (in combat): yours only in your cast's frame, and no fade without an id", function()
    NewGame()
    local hidden = {isFromPlayerOrPlayerPet = SIM.Secret(true), auraInstanceID = SIM.Secret(800)}
    At(1, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura(SIM.Secret("Strength of Earth"), nil, hidden)}}) end)
    At(1.1, function() SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura(SIM.Secret("Healing Stream"), nil, hidden)}}) end)
    At(3, function() SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura(SIM.Secret("Someone's"), nil, hidden)}}) end)
    At(4, function() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {SIM.Secret(800)}}) end)
    Run(5)
    Eq(#AuraTexts(), 2, "the two in the cast's frame (up to 0.15 s)")
end)

------------------------------------------------------------------------
-- Heals on you
------------------------------------------------------------------------
Test("a direct heal from someone else shows who healed you", function()
    NewGame()
    At(1, function() Feed("HEAL", SIM.Secret("Priest"), SIM.Secret(420)); HealOn("player", 420) end)
    Run(2)
    local s = Shown("incoming")
    Eq(#s, 1, "one heal")
    Eq(s[1].fmt, "+%s [%s]", "with the name")
    Eq(s[1].args[2], "Priest", "the healer")
end)

Test("a heal-over-time tick from someone else has no name", function()
    NewGame()
    At(1, function() Feed("PERIODIC_HEAL", SIM.Secret("Priest"), SIM.Secret(30)); HealOn("player", 30) end)
    Run(2)
    Eq(Shown("incoming")[1].fmt, "+%s", "no name")
end)

Test("two heals close together get no names: which is whose can't be told", function()
    NewGame()
    At(1, function() Line("SPELL_PERIODIC_HEAL"); Feed("PERIODIC_HEAL", SIM.Secret("You"), SIM.Secret(14)); HealOn("player", 14) end)
    At(1.05, function() Feed("HEAL", SIM.Secret("Priest"), SIM.Secret(420)); HealOn("player", 420) end)
    Run(2)
    Eq(Shown("incoming")[1].fmt, "+%s", "no name")
end)

Test("two heals on you in one frame both show; one heal seen as player and target shows once", function()
    NewGame()
    At(1, function() Line("SPELL_PERIODIC_HEAL"); HealOn("player", 14); HealOn("player", 420) end)
    At(3, function() SIM.target = "player"; HealOn("player", 300); HealOn("target", 300) end)
    Run(4)
    Eq(#Shown("damage"), 1, "your own tick, with your heals (the damage spot)")
    Eq(#Shown("incoming"), 2, "the other heal, and the one seen twice once")
end)

------------------------------------------------------------------------
-- Your swings (timings: the author's logs, 2026-11-08 and 2026-11-09)
------------------------------------------------------------------------
Test("a swing's hit 0.461 s after it is yours; the log names the mob swung at", function()
    NewGame()
    At(1, function() Swing() end)
    At(1.461, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "your swing, 0.4"), 1, "shown as your swing")
    local named = 0
    for _, l in ipairs(ForeverFloatingTextLog.lines) do
        if l:find("your swing (0, weapon 3.30s, at nameplate1)", 1, true) then named = named + 1 end
    end
    Eq(named, 1, "swing line with its target, for replays")
end)

------------------------------------------------------------------------
-- Stormstrike reset (2026-11-09 logs: cooldown 6.0 s, resets reported 3.5-4.6 s after the cast)
------------------------------------------------------------------------
-- (1.31.0) at the procs spot, kept there (Procs.lua); before, a scrolling alert
local function StormstrikeAlerts()
    local n = 0
    for _, s in ipairs(G.procs) do if s.text == "Stormstrike!" then n = n + 1 end end
    for _, s in ipairs(Shown("alerts")) do Ok(s.text ~= "Stormstrike!", "not among the scrolling alerts") end
    return n
end

Test("Stormstrike reported ready 3.5 s after the cast shows \"Stormstrike!\", once", function()
    NewGame()
    At(1, function() Cast(17364); G.SetCooldown(true) end)
    At(4.488, function() Miss("nameplate1", "PARRY"); G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    At(4.6, function() SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    At(5.0, function() Miss("player", "DODGE") end)
    Run(6)
    Eq(StormstrikeAlerts(), 1, "shown once")
end)

Test("reset during a global cooldown (\"active, on the GCD\") counts", function()
    NewGame()
    At(1, function() Cast(17364); G.SetCooldown(true) end)
    At(3.9, function() G.SetCooldown(true, true); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    Run(5)
    Eq(StormstrikeAlerts(), 1, "shown")
end)

-- 2026-11-10 07:48 log: 7 of 7 alerts wrong, a Shock's GCD 4.43-4.72 s after the cast outlasting the rest
Test("a Shock's GCD 4.5 s after the cast that just outlasts its cooldown: nothing", function()
    NewGame()
    At(1, function() Cast(17364); G.SetCooldown(true) end)
    At(5.5, function() G.SetCooldown(true, true); SIM.Fire("SPELL_UPDATE_COOLDOWN") end) -- GCD to 7.0
    At(7.0, function() G.SetCooldown(false) end) -- the GCD and its 6.0 s end together
    Run(8)
    Eq(StormstrikeAlerts(), 0, "nothing")
end)

Test("a reset during a late GCD shows once the GCD is over", function()
    NewGame()
    local ended
    At(1, function() Cast(17364); G.SetCooldown(true) end)
    At(5.3, function() G.SetCooldown(true, true); SIM.Fire("SPELL_UPDATE_COOLDOWN") end) -- 4.3 s: unsure
    At(6.2, function() G.SetCooldown(false); ended = SIM.now end) -- GCD over 5.2 s after the cast: reset
    Run(7)
    Eq(StormstrikeAlerts(), 1, "shown")
    local at
    for _, s in ipairs(G.procs) do if s.text == "Stormstrike!" then at = s.t end end
    Ok(at and ended and at >= ended and at <= ended + 0.15,
        ("shown when the GCD ended, not before (%s, ended %s)"):format(tostring(at), tostring(ended)))
end)

Test("its own cooldown ending, its own global cooldown, or still on cooldown: nothing", function()
    NewGame()
    At(1, function() Cast(17364); G.SetCooldown(true, true) end) -- its own GCD at the cast
    At(1.1, function() SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    At(2, function() G.SetCooldown(true, false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    At(4, function() Miss("player", "DODGE") end) -- still on cooldown
    At(7.004, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end) -- its 6.0 s
    Run(8)
    Eq(StormstrikeAlerts(), 0, "nothing")
end)

Test("with no cooldown info from the game, no Stormstrike alert", function()
    NewGame()
    At(1, function() Cast(17364); G.SetCooldown(nil) end)
    At(3, function() Miss("player", "DODGE"); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    Run(4)
    Eq(StormstrikeAlerts(), 0, "nothing")
end)

------------------------------------------------------------------------
-- (1.31.0) The procs spot: kept still until used (Procs.lua)
------------------------------------------------------------------------
local function ProcsUp() return table.concat(G.FFT:ProcsUp(), " ") end

Test("\"Stormstrike!\" stays at the procs spot until you cast it, leave combat, or 10 s", function()
    NewGame()
    At(1, function() Cast(17364); G.SetCooldown(true) end)
    At(4.5, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    Run(6)
    Eq(ProcsUp(), "stormstrike", "shown and still up")
    At(6.5, function() Cast(17364); G.SetCooldown(true) end)
    Run(7.5)
    Eq(ProcsUp(), "", "gone with the next Stormstrike")
    At(9, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end) -- reset again
    At(10, function() SIM.inCombat = false; SIM.Fire("PLAYER_REGEN_ENABLED") end)
    Run(11)
    Eq(StormstrikeAlerts(), 2, "the second reset shown")
    Eq(ProcsUp(), "", "gone when you left combat")
    At(12, function() SIM.inCombat = true; SIM.Fire("PLAYER_REGEN_DISABLED"); Cast(17364); G.SetCooldown(true) end)
    At(15, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    Run(24.9)
    Eq(ProcsUp(), "stormstrike", "unused, still up")
    Run(25.5)
    Eq(ProcsUp(), "", "unused: gone after 10 s")
end)

Test("with Procs.lua not loaded yet (a /reload after installing 1.31.0), the reset is an alert, no error", function()
    NewGame()
    G.FFT.ProcShow = nil
    At(1, function() Cast(17364); G.SetCooldown(true) end)
    At(4.5, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    Run(6)
    local n = 0
    for _, s in ipairs(Shown("alerts")) do if s.text == "Stormstrike!" then n = n + 1 end end
    Eq(n, 1, "as an alert")
end)

-- The author's 2026-11-12 09:01 recording with the game's file: "Maelstrom Ready!" at the 5th
-- Maelstrom Weapon stack came as the feed's SPELL_CAST (9 of 9), a Lightning Bolt removed it in its frame
Test("the game's proc notice stays at the procs spot until a spell of yours uses it up", function()
    NewGame()
    SIM.spells[403] = {name = "Lightning Bolt", harmful = true}
    At(1, function() Feed("SPELL_CAST", SIM.Secret("Maelstrom Ready!")) end)
    At(2, function() Cast(8042) end) -- Earth Shock: nothing of yours removed with it
    At(3, function() Cast(17364); HiddenRemove() end) -- Stormstrike taking Flurry's last charge
    At(4, function() HiddenRemove() end) -- an aura of yours gone, no cast
    Run(5)
    Eq(#G.procs, 1, "shown once")
    Eq(G.procs[1].fmt, "%s", "drawn as the game names it")
    Eq(G.procs[1].args[1], "Maelstrom Ready!", "its name")
    Eq(ProcsUp(), "game", "still up")
    At(6, function() Cast(403); HiddenRemove() end)
    Run(7)
    Eq(ProcsUp(), "", "used up by the Lightning Bolt")
    for _, s in ipairs(G.shown) do Ok(s.args[1] ~= "Maelstrom Ready!", "not also as a scrolling text") end
end)

-- 1.31.0 draft in game (2026-11-12 09:35): the fading hid the rows' own frame on the first frame
-- nothing faded, so "Maelstrom Ready!" showed for one frame. The stub runs no OnUpdate: done here.
Test("a proc's text stays drawn frame after frame, and fades out once used", function()
    NewGame()
    SIM.spells[403] = {name = "Lightning Bolt", harmful = true}
    At(1, function() Feed("SPELL_CAST", SIM.Secret("Maelstrom Ready!")) end)
    Run(1.5)
    local f = G.FFT.procFrames
    local function Frames(n)
        for _ = 1, n do
            if f.fader:IsShown() then f.fader:GetScript("OnUpdate")(f.fader, 1 / 60) end
        end
    end
    Frames(30)
    Ok(f.rows:IsShown(), "the rows' frame still shown")
    Eq(ProcsUp(), "game", "still up")
    At(2, function() Cast(403); HiddenRemove() end)
    Run(2.5)
    Ok(f.fader:IsShown(), "fading")
    Frames(30)
    Ok(not f.fader:IsShown(), "faded, the fading stopped")
    Ok(f.rows:IsShown(), "the rows' frame stays, empty")
end)

-- The author, 2026-11-12: the procs' green was the buffs' green, and they got lost among buff gains
Test("procs have colors of their own: Stormstrike gold, the game's notices not the buffs' green", function()
    NewGame()
    At(1, function() Cast(17364); G.SetCooldown(true) end)
    At(4.5, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    At(5, function() Feed("SPELL_CAST", SIM.Secret("Maelstrom Ready!")) end)
    Run(6)
    local C = G.FFT.Color
    local function Same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end
    Eq(#G.procs, 2, "both shown")
    Ok(Same(G.procs[1].color, C("colorStormstrike")), "Stormstrike in its own color")
    Ok(Same(C("colorStormstrike"), C("colorAlert")), "the alerts' gold, as before 1.31.0")
    Ok(Same(G.procs[2].color, C("colorProc")), "the notice in the procs color")
    Ok(not Same(C("colorProc"), C("colorBuff")), "not the buffs' green")
    Ok(not Same(C("colorProc"), C("colorStormstrike")), "the two apart")
    -- a 1.31.0 draft saved the green: moved on once, at load
    NewGame({db = {colorProc = "ff1aff1a"}})
    Eq(ForeverFloatingTextDB.colorProc, G.FFT.DEFAULTS.colorProc, "the draft's green moved on")
    NewGame({db = {colorProc = "ff1aff1a", procColors2 = true}})
    Eq(ForeverFloatingTextDB.colorProc, "ff1aff1a", "picked again later: kept")
end)

-- (1.31.0) Reactive abilities (not yet in any of the author's logs: a shaman has none). The game's answers are made up here: C_Spell.IsSpellUsable's, a warrior's.
local function Warrior(state)
    UnitClass = function() return "Warrior", "WARRIOR", 1 end
    SIM.spells[7384] = {name = "Overpower", harmful = true}
    SIM.spells[5308] = {name = "Execute", harmful = true}
    C_Spell.IsSpellUsable = function(name) local s = state[name] or {}; return s[1] or false, s[2] or false end
end
local function Usable() SIM.Fire("SPELL_UPDATE_USABLE") end

Test("Overpower stays while the game says it can be cast; not before it was seen not to", function()
    NewGame()
    local state = {}
    Warrior(state)
    At(1, function() state.Overpower = {true}; Usable() end) -- usable at the first look: means nothing yet
    At(2, function() state.Overpower = {false}; Usable() end) -- no, with rage to spare: now it means something
    At(3, function() state.Overpower = {true}; Usable() end) -- your target dodged
    Run(3.5)
    Eq(ProcsUp(), "spell:Overpower", "shown")
    Eq(G.procs[#G.procs].text, "Overpower!", "by the game's name")
    At(4, function() state.Overpower = {false, true}; Usable() end) -- not enough rage: keep it
    Run(4.5)
    Eq(ProcsUp(), "spell:Overpower", "kept while rage runs short")
    At(5, function() state.Overpower = {false}; Usable() end) -- used, or its time is up
    Run(5.5)
    Eq(ProcsUp(), "", "gone when the game says no")
    Eq(#G.procs, 1, "shown once")
    -- another class: nothing looked at
    NewGame()
    Warrior({Overpower = {true}})
    UnitClass = function() return "Shaman", "SHAMAN", 7 end
    At(1, function() Usable() end)
    Run(2)
    Eq(#G.procs, 0, "a shaman has no Overpower")
end)

Test("the game's reactive notice: kept 5 s, left out when its ability's row came with it", function()
    NewGame()
    local state = {Overpower = {false}}
    Warrior(state)
    At(1, function() Usable() end)
    At(2, function() Feed("SPELL_ACTIVE", SIM.Secret("Overpower")); state.Overpower = {true}; Usable() end)
    Run(3)
    Eq(ProcsUp(), "spell:Overpower", "the usable ability's row only")
    At(4, function() Feed("SPELL_ACTIVE", SIM.Secret("Revenge")) end) -- nothing else said it
    Run(5)
    Eq(ProcsUp(), "reactive spell:Overpower", "the notice too")
    Eq(G.procs[#G.procs].args[1], "Revenge", "drawn as the game names it")
    Run(9.5)
    Eq(ProcsUp(), "spell:Overpower", "the notice gone after 5 s")
end)

Test("a highlighted spell stays at the procs spot until the game turns it off", function()
    NewGame()
    SIM.spells[12536] = {name = "Clearcasting"}
    SIM.spells[7384] = {name = "Overpower", harmful = true}
    At(1, function() SIM.Fire("SPELL_ACTIVATION_OVERLAY_SHOW", 12536) end)
    At(1.1, function() SIM.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 7384) end)
    Run(2)
    Eq(ProcsUp(), "spell:Overpower spell:Clearcasting", "both, newest on top")
    Ok(G.procs[1].color ~= G.procs[2].color, "a proc's overlay and a lit-up button apart")
    At(3, function() SIM.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 7384) end)
    Run(4)
    Eq(ProcsUp(), "spell:Clearcasting", "the glow gone with its _HIDE")
    At(5, function() SIM.Fire("SPELL_ACTIVATION_OVERLAY_HIDE", nil) end) -- no spell: every overlay
    Run(6)
    Eq(ProcsUp(), "", "the overlay gone")
    for _, s in ipairs(Shown("alerts")) do Ok(s.text ~= "Clearcasting!", "not a scrolling alert") end
end)

------------------------------------------------------------------------
-- (1.31.0) Notices.lua: dispels, emotes, cooldowns, gains (not in the author's logs yet)
------------------------------------------------------------------------
local function AlertTexts()
    local out = {}
    for _, s in ipairs(Shown("alerts")) do
        local text = s.text or (s.fmt and s.fmt:format(table.unpack(s.args)))
        if text ~= "+Combat" then out[#out + 1] = text end
    end
    return table.concat(out, " | ")
end

Test("experience, honor, reputation and skill with your loot, read by the game's own templates", function()
    NewGame()
    XP, HONOR = "XP", "Honor"
    COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
    COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
    COMBATLOG_HONORAWARD = "You have been awarded %d Honor."
    FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
    FACTION_STANDING_DECREASED = "Reputation with %s decreased by %d."
    SKILL_RANK_UP = "Your skill in %s has increased to %d."
    At(1, function() SIM.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Miner dies, you gain 120 experience.") end)
    At(2, function() SIM.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Miner dies, you gain 240 experience. (120 exp Rested bonus)") end)
    At(3, function() SIM.Fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 15 Honor.") end)
    At(4, function() SIM.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 25.") end)
    At(5, function() SIM.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Booty Bay decreased by 10.") end)
    At(6, function() SIM.Fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 76.") end)
    At(7, function() SIM.Fire("CHAT_MSG_COMBAT_XP_GAIN", SIM.Secret("You gain 5 experience.")) end) -- hidden: skipped
    Run(8)
    local loot = {}
    for _, s in ipairs(Shown("loot")) do loot[#loot + 1] = s.text end
    Eq(table.concat(loot, " | "), "+120 XP | +240 XP | +15 Honor | +25 Stormwind | -10 Booty Bay | Mining: 76",
        "the gains, with your loot")
    Eq(AlertTexts(), "", "none among the alerts")
    ForeverFloatingTextDB.showExperience = false
    At(9, function() SIM.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Miner dies, you gain 120 experience.") end)
    Run(10)
    Eq(#Shown("loot"), 6, "off: not shown")
end)

-- (1.31.0) the author: one lock for every position box, not a right-click on each
Test("/fft move shows every position box; one right-click, Lock all or /fft lock puts them all away", function()
    NewGame()
    local names = {}
    for _, spot in pairs(G.FFT.SPOTS) do names[#names + 1] = spot.frameName end
    local function Shown()
        local n = 0
        for _, name in ipairs(names) do if _G[name] and _G[name]:IsShown() then n = n + 1 end end
        return n
    end
    SlashCmdList.FOREVERFLOATINGTEXT("move")
    Eq(Shown(), #names, "every box out")
    Ok(ForeverFloatingTextLockBar:IsShown(), "the Lock all bar")
    _G[names[1]]:GetScript("OnMouseUp")(_G[names[1]], "RightButton")
    Eq(Shown(), 0, "one right-click: all locked")
    Ok(not ForeverFloatingTextLockBar:IsShown(), "the bar gone")
    SlashCmdList.FOREVERFLOATINGTEXT("move")
    ForeverFloatingTextLockBar.button:GetScript("OnClick")()
    Eq(Shown(), 0, "Lock all")
    SlashCmdList.FOREVERFLOATINGTEXT("move")
    SlashCmdList.FOREVERFLOATINGTEXT("lock")
    Eq(Shown(), 0, "/fft lock")
    G.FFT:ToggleMover("procs") -- one page's Unlock
    Eq(Shown(), 1, "one box")
    Ok(ForeverFloatingTextLockBar:IsShown(), "the bar with it")
end)

Test("crowd control on you, in the game's words; a kick's school lock; hidden: nothing", function()
    NewGame()
    Eq(ForeverFloatingTextDB.showCrowdControl, false, "off by default: the game's own frame shows it")
    ForeverFloatingTextDB.showCrowdControl = true
    local data
    C_LossOfControl = {GetActiveLossOfControlDataByUnit = function(unit, i) return data end}
    C_Spell.GetSchoolString = function(s) return s == 32 and "Shadow" or nil end
    LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL = "%s Locked"
    At(1, function()
        data = {locType = "STUN", spellID = 853, displayText = "Stunned", iconTexture = 135963, lockoutSchool = 0}
        SIM.Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
    end)
    At(1.1, function() SIM.Fire("LOSS_OF_CONTROL_ADDED", "player", 1) end) -- the same, again: once
    At(2, function()
        data = {locType = "SCHOOL_INTERRUPT", spellID = 1766, displayText = "Interrupted", iconTexture = 1, lockoutSchool = 32}
        SIM.Fire("LOSS_OF_CONTROL_ADDED", "player", 1)
    end)
    At(3, function() data = SIM.Secret({}); SIM.Fire("LOSS_OF_CONTROL_ADDED", "player", 1) end)
    At(4, function() SIM.Fire("LOSS_OF_CONTROL_ADDED", "party1", 1) end) -- not you
    Run(5)
    -- (1.31.0) at the procs spot, kept while it lasts
    local texts = {}
    for _, p in ipairs(G.procs) do texts[#texts + 1] = p.fmt:format(table.unpack(p.args)) end
    Eq(table.concat(texts, " | "), "|T135963:0|t Stunned | |T1:0|t Shadow Locked", "shown, each with its icon")
    Eq(ProcsUp(), "cc:1766 cc:853", "both still up")
    Eq(AlertTexts(), "", "not among the alerts")
    C_LossOfControl.GetActiveLossOfControlDataCountByUnit = function() return 0 end
    At(6, function() SIM.Fire("LOSS_OF_CONTROL_UPDATE", "player") end)
    Run(7)
    Eq(ProcsUp(), "", "gone when you're back in control")
end)

Test("the quieter layout: killing blows off once, periodic gains off, your totems' buffs off, repeats merged", function()
    NewGame({db = {showKills = true}}) -- an older DB with them on
    Eq(ForeverFloatingTextDB.showKills, false, "killing blows turned off once")
    NewGame({db = {showKills = true, layout2 = true}})
    Eq(ForeverFloatingTextDB.showKills, true, "turned on again later: stays")
    NewGame({db = {showCrowdControl = true}}) -- a 1.31.0 draft saved it on
    Eq(ForeverFloatingTextDB.showCrowdControl, false, "crowd control text turned off once")
    NewGame({db = {showCrowdControl = true, ccOff2 = true}})
    Eq(ForeverFloatingTextDB.showCrowdControl, true, "turned on again later: stays")
    NewGame()
    At(1, function() Feed("PERIODIC_ENERGIZE", 10, "MANA") end)
    At(2, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 515)}}) end)
    At(3, function() G.FFT:ShowAlert("Purged"); G.FFT:ShowAlert("Purged") end)
    At(3.5, function() G.FFT:ShowAlert("Purged") end)
    At(5, function() G.FFT:ShowAlert("Purged") end) -- more than a second later: a new one
    Run(6)
    local power = 0
    for _, s in ipairs(G.shown) do if s.key == "incoming" then power = power + 1 end end
    Eq(power, 0, "a Mana Spring tick: not shown")
    Eq(#AuraTexts(), 0, "your totem's buff: not shown")
    local purged, merged = 0, nil
    for _, s in ipairs(Shown("alerts")) do if s.text == "Purged" then purged = purged + 1 end end
    Eq(purged, 2, "three in a second: one text; a fourth later: another")
    SIM.inCombat = true; SIM.Fire("PLAYER_REGEN_DISABLED")
    Run(7)
    Eq(Shown("alerts")[#Shown("alerts")].text, "+Combat", "combat state, short")
end)

Test("/fft hide leaves a buff out by its name; /fft unhide brings it back", function()
    NewGame()
    AllAuras()
    SlashCmdList.FOREVERFLOATINGTEXT("hide strength of earth")
    At(1, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 515)}}) end)
    Run(2)
    Eq(#AuraTexts(), 0, "hidden, typed in any case before it was seen")
    NewGame()
    AllAuras()
    At(1, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 515)}}) end)
    Run(1.5)
    SlashCmdList.FOREVERFLOATINGTEXT("hide strength of earth") -- now its name is known
    At(2, function() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {515}}) end)
    At(3, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 516)}}) end)
    Run(4)
    Eq(#AuraTexts(), 1, "only the first, before it was hidden")
    Ok(ForeverFloatingTextDB.hiddenBuffs["Strength of Earth"], "kept as the game writes it")
    SlashCmdList.FOREVERFLOATINGTEXT("unhide Strength of Earth")
    Ok(not ForeverFloatingTextDB.hiddenBuffs["Strength of Earth"], "taken off")
end)

Test("your dispels and the crowd control you broke, from your own Combat Log lines", function()
    NewGame()
    SIM.spells[370] = {name = "Purge", harmful = true}
    At(1, function() Cast(370); Line("SPELL_DISPEL", "BUFF"); Line("SPELL_DISPEL", "BUFF") end) -- two buffs: once
    At(2, function() Line("SPELL_DISPEL", "DEBUFF") end)
    At(3, function() Line("SPELL_AURA_BROKEN_SPELL", "DEBUFF") end)
    At(4, function() Line("SPELL_DISPEL_FAILED") end)
    Run(5)
    Eq(AlertTexts(), "Purged | Cleansed | Broke crowd control | Dispel failed", "shown")
    local f = Blizzard_CombatLog_Filters.filters[Blizzard_CombatLog_Filters.currentFilter]
    Ok(f.filters[1].eventList.SPELL_DISPEL and not f.filters[1].eventList.SPELL_DISPEL_BUFF, "events by their own names")
    Ok(f.colors.eventColoring.SPELL_DISPEL_DEBUFF, "colored with the aura's type")
    Eq(Count(Decisions("show"), ""), 0, "no line taken for a hit")
end)

Test("your target's emotes only", function()
    NewGame()
    At(1, function() SIM.Fire("CHAT_MSG_MONSTER_EMOTE", "%s goes into a frenzy!", "Mob") end)
    At(2, function() SIM.Fire("CHAT_MSG_MONSTER_EMOTE", "%s flees in terror!", "Mob 2") end) -- not your target
    Run(3)
    Eq(AlertTexts(), "Mob goes into a frenzy!", "your target's")
end)

Test("a spell's cooldown ready: told when it lasted long enough, not for a short one or the GCD", function()
    NewGame()
    SIM.spells[8177] = {name = "Grounding Totem"}
    SIM.spells[8042] = {name = "Earth Shock", harmful = true}
    At(1, function() Cast(8177); G.SetCooldown(true, false) end)
    At(16, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end) -- 15 s
    At(20, function() Cast(8042); G.SetCooldown(true, false) end)
    At(26, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end) -- 6 s: shorter than 10
    At(30, function() Cast(8177); G.SetCooldown(true, true) end) -- only the GCD
    At(31, function() G.SetCooldown(false); SIM.Fire("SPELL_UPDATE_COOLDOWN") end)
    Run(32)
    Eq(AlertTexts(), "Grounding Totem ready!", "the long one only")
end)

Test("a proc notice nothing uses up goes after 30 s; with the option off, none", function()
    NewGame()
    At(1, function() Feed("SPELL_CAST", SIM.Secret("Maelstrom Ready!")) end)
    Run(30.5)
    Eq(ProcsUp(), "game", "up")
    Run(31.5)
    Eq(ProcsUp(), "", "gone")
    ForeverFloatingTextDB.showGameProcs = false
    At(33, function() Feed("SPELL_CAST", SIM.Secret("Maelstrom Ready!")) end)
    Run(34)
    Eq(#G.procs, 1, "off: not shown")
end)

-- The game logs the proc as a cast of yours too: a cast line in its frame with no cast of yours,
-- as a totem's attack looks in a dungeon. In a swing's frame with Windfury lines it would hold one back.
Test("the game's proc cast line isn't taken for a totem's: both Windfury attacks keep their lines", function()
    for _, feedFirst in ipairs({false, true}) do
        NewGame()
        At(1, function()
            Swing(3.60)
            if feedFirst then Feed("SPELL_CAST", SIM.Secret("Maelstrom Ready!")) end
            Line("SPELL_CAST_SUCCESS")
            if not feedFirst then Feed("SPELL_CAST", SIM.Secret("Maelstrom Ready!")) end
            Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE")
        end)
        At(1.228, function() Hit() end)
        At(1.504, function() Hit() end)
        At(1.958, function() Hit() end)
        Run(3)
        Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "both attacks, the notice "
            .. (feedFirst and "first" or "after its line"))
    end
end)

Test("weapon speed doesn't move the delay: an attack speed buff's 2.54 s swing still hits at 0.461", function()
    NewGame()
    At(1, function() Swing(2.54) end)
    At(1.461, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "your swing"), 1, "shown (1.25.1 dropped these)")
end)

Test("Flurry's 0.415 s hit is yours, even when frames make it 0.400", function()
    NewGame()
    At(1, function() Swing(2.95) end)
    At(1.400, function() Hit() end)
    At(5, function() Swing(2.95) end)
    At(5.415, function() Hit() end)
    Run(7)
    Eq(Count(Decisions("show"), "your swing"), 2, "both shown")
end)

Test("Ghost Wolf's swing hits sooner, 0.292-0.396 s", function()
    NewGame()
    At(1, function() G.SetForm(16); Swing(2.95); G.SetForm(nil) end)
    At(1.292, function() Hit() end)
    At(5, function() G.SetForm(16); Swing(3.30); G.SetForm(nil) end)
    At(5.396, function() Hit() end)
    Run(7)
    Eq(Count(Decisions("show"), "your swing"), 2, "both shown")
end)

Test("Stormstrike in the swing's frame delays its hit to 0.994 s", function()
    NewGame()
    At(1, function() Swing(); Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(1.994, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "your Combat Log line"), 1, "Stormstrike's own hit")
    Eq(Count(Decisions("show"), "later as your Stormstrike"), 1, "the swing's delayed hit")
end)

Test("a cast up to 0.44 s after the swing delays it too (Stormstrike, Totemic Recall)", function()
    NewGame()
    At(1, function() Swing() end)
    At(1.439, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(1.995, function() Hit() end)
    At(5, function() Swing() end)
    At(5.294, function() Cast(36936) end)
    At(5.997, function() Hit() end)
    Run(7)
    Eq(Count(Decisions("show"), "later as your Stormstrike"), 1, "after Stormstrike")
    Eq(Count(Decisions("show"), "later as your Totemic Recall"), 1, "after Totemic Recall")
end)

Test("a cast that doesn't delay the swing (Fire Nova): its normal hit is still yours, shown later", function()
    NewGame()
    At(1, function() Swing() end)
    At(1.364, function() Cast(8042) end) -- a cast whose swing hit came on time (2026-11-07 dungeon log)
    At(1.461, function() Hit() end)
    Run(3)
    -- (60 frames a second: the 0.461 s hit reads 0.45)
    local shows = Decisions("show")
    Eq(Count(shows, "your swing, 0.4"), 1, "shown, once the late window closed")
    Ok(tonumber(shows[1]:match("^(%d+%.%d+)")) > 2, "decided after the late window")
end)

Test("a triggered spell (no UNIT_SPELLCAST_SENT) doesn't delay the swing", function()
    NewGame()
    At(1, function() Swing(); Cast(133, true); Line("SPELL_DAMAGE"); Hit(nil, 4) end)
    At(1.461, function() Hit() end)
    Run(3)
    local shows = Decisions("show")
    Eq(Count(shows, "your swing, 0.4"), 1, "the swing on time")
    Ok(tonumber(shows[#shows]:match("^(%d+%.%d+)")) < 1.7, "decided at once, no late window")
end)

Test("a long cast stays \"sent\" however many casts come in between", function()
    NewGame()
    At(1, function()
        SIM.Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-long", 36936) -- its SENT at the start
        for i = 1, 150 do SIM.Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-other-" .. i, 8042) end
        SIM.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-long", 36936)
    end)
    Run(2)
    local noSent = 0
    for _, l in ipairs(ForeverFloatingTextLog.lines) do if l:find("no UNIT_SPELLCAST_SENT", 1, true) then noSent = noSent + 1 end end
    Eq(noSent, 0, "not taken for triggered")
end)

Test("with a cast before its hit, someone else's hit at 0.46 doesn't take the delayed swing", function()
    NewGame()
    At(1, function() Swing(); Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(1.46, function() Hit() end) -- someone else's
    At(1.994, function() Hit() end) -- yours
    Run(3)
    Eq(Count(Decisions("show"), "later as your Stormstrike"), 1, "the delayed one is the swing")
    Eq(Count(Decisions("drop"), "no Combat Log line"), 1, "the other one dropped")
end)

Test("a Stormstrike parried after the swing is Stormstrike's, not the swing's", function()
    NewGame({db = {showMisses = true}}) -- (off by default: misses are then not matched at all)
    At(1, function() Swing() end)
    At(1.439, function() Cast(17364); Line("SPELL_MISSED", "PARRY"); Miss("nameplate1", "PARRY") end)
    At(1.995, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "later as your Stormstrike"), 1, "the swing's delayed hit")
end)

Test("someone else's hit with nothing of yours is dropped", function()
    NewGame()
    At(1, function() Hit("nameplate2", 1) end)
    At(2, function() Hit("nameplate1", 16) end)
    At(3, function() Swing() end)
    At(4.0, function() Hit() end) -- 1.0 s after a swing with no cast: not the swing's
    Run(5)
    Eq(#Decisions("show"), 0, "nothing shown")
end)

-- (1.28.8) a swing with a cast before its hit is decided ~0.6 s after the hit came
Test("a swing's hit whose nameplate went to another mob meanwhile shows where it was, not on that mob", function()
    NewGame()
    At(1, function() Swing(); Cast(36936) end)
    At(1.461, function() Hit() end)
    At(1.6, function()
        SIM.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
        SIM.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1") -- the same plate, another mob
    end)
    Run(3)
    Eq(Count(Decisions("show"), "your swing"), 1, "still yours")
    Eq(Count(Decisions("show"), "its nameplate went away, shown where it was"), 1, "shown where it was")
    local numbers = 0
    for _, s in ipairs(G.shown) do
        if not s.key or type(s.key) ~= "string" then
            numbers = numbers + 1
            Ok(s.plate == nil, "not anchored to the plate")
        end
    end
    Eq(numbers, 1, "one number")
end)

Test("a long heal's target is kept however many casts are sent in between", function()
    NewGame()
    SIM.spells[331] = {name = "Healing Wave", helpful = true}
    At(1, function()
        SIM.Fire("UNIT_SPELLCAST_SENT", "player", "Friend", "Cast-heal", 331)
        for i = 1, 120 do SIM.Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-other-" .. i, 8042) end
        SIM.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-heal", 331)
    end)
    Run(2)
    local named = 0
    for _, l in ipairs(ForeverFloatingTextLog.lines) do
        if l:find("cast Healing Wave on Friend", 1, true) then named = named + 1 end
    end
    Eq(named, 1, "the target's name still known")
end)

Test("buffs off: UNIT_AURA shows nothing; turned on, buffs from meanwhile fade by name", function()
    NewGame({db = {showAuras = false, showAuraFades = true, showTotemBuffs = true}})
    local now = {TotemAura("Strength of Earth", 21)}
    C_UnitAuras = {GetAuraDataByIndex = function(unit, i) return unit == "player" and now[i] or nil end}
    At(1, function() Cast(8160); SIM.Fire("UNIT_AURA", "player", {addedAuras = {TotemAura("Strength of Earth", 21)}}) end)
    At(2, function() SIM.Fire("UNIT_AURA", "player", {updatedAuraInstanceIDs = {21}}) end)
    Run(3)
    Eq(#AuraTexts(), 0, "nothing while off")
    ForeverFloatingTextDB.showAuras = true
    At(4, function() SIM.Fire("UNIT_AURA", "player", {removedAuraInstanceIDs = {21}}) end)
    Run(5)
    local t = AuraTexts()
    Eq(#t, 1, "the fade")
    Eq(t[1], "<Strength of Earth> fades", "by name")
end)

------------------------------------------------------------------------
-- Windfury (2026-11-09 09:59 log)
------------------------------------------------------------------------
Test("Windfury: two lines with the swing, its hits at +0.23 and +0.50, the swing's at +0.96", function()
    NewGame()
    At(1, function() Swing(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.228, function() Hit() end)
    At(1.504, function() Hit() end)
    At(1.958, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(Count(Decisions("show"), "later as your Windfury"), 1, "the swing")
end)

local function WindfuryAlerts()
    local n = 0
    for _, s in ipairs(Shown("alerts")) do if s.text == "Windfury!" then n = n + 1 end end
    return n
end

Test("\"Windfury!\" once per proc, with its first attack; none for a swing without one, none when off", function()
    NewGame()
    At(1, function() Swing(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.228, function() Hit() end)
    At(1.504, function() Hit() end)
    At(1.958, function() Hit() end)
    At(5, function() Swing() end) -- a plain swing
    At(5.461, function() Hit() end)
    At(9, function() Cast(17364); Line("SPELL_DAMAGE"); Hit(); Line("SPELL_DAMAGE") end) -- from Stormstrike
    At(9.505, function() Hit() end)
    Run(11)
    Eq(WindfuryAlerts(), 2, "the swing's proc and Stormstrike's")
    for _, s in ipairs(Shown("alerts")) do
        -- the hit at 1.228 falls in the frame at 1.217 (frames of 1/60 s)
        if s.text == "Windfury!" then Ok(s.t >= 1.2, "not before its first attack: " .. s.t); break end
    end
    ForeverFloatingTextDB.showWindfury = false
    At(13, function() Swing(); Line("SPELL_DAMAGE") end)
    At(13.228, function() Hit() end)
    Run(15)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 4, "the extra attacks still shown")
    Eq(WindfuryAlerts(), 2, "off: no alert")
end)

Test("\"Windfury!\" once for a Stormstrike's proc whose second attack a swing takes (08:44 log, 2878.334)", function()
    NewGame()
    At(1, function() Cast(17364); Line("SPELL_DAMAGE"); Hit(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.227, function() Hit() end)
    At(1.378, function() Swing(nil, "PARRY") end)
    At(1.502, function() Hit() end)
    At(1.959, function() Miss("nameplate1", "PARRY") end)
    Run(3)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(WindfuryAlerts(), 1, "one proc, one alert")
end)

-- Windfury Totem's extra swing (2026-11-11 12:46 and 12:53 logs)
local function Shaman(group) -- a shaman, solo unless told (the stub starts in a group)
    UnitClass = function() return "Shaman", "SHAMAN", 7 end
    SIM.inGroup = group or false
end
local function ExtraSwing(speed)
    SIM.Fire("COMBAT_TEXT_UPDATE", "EXTRA_ATTACKS")
    Swing(speed)
end

Test("Windfury Totem: the extra swing 0.10 s later takes the hit 1.46 s after the first swing; one alert", function()
    NewGame(); Shaman()
    At(1, function() Swing(3.60) end)
    At(1.104, function() ExtraSwing(3.60) end)
    At(1.462, function() Hit() end)
    At(2.463, function() Hit() end) -- 12:53 log 17851.842: 1.463 after the first swing
    Run(4)
    Eq(Count(Decisions("show"), "(your swing, "), 1, "the first swing's")
    Eq(Count(Decisions("show"), "your extra swing (Windfury Totem)"), 1, "the extra swing's")
    Eq(WindfuryAlerts(), 1, "one alert")
end)

Test("Windfury Totem: both swings in one frame; a Stormstrike just before the late hit delays it 0.534 s", function()
    NewGame(); Shaman()
    At(1, function() Swing(3.60); ExtraSwing(3.60) end)
    At(1.465, function() Hit() end)
    At(2.447, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end) -- Stormstrike's own hit
    At(2.988, function() Hit() end) -- 12:53 log 17989.289
    Run(5)
    Eq(Count(Decisions("show"), "your extra swing (Windfury Totem)"), 1, "the delayed extra swing's")
    Eq(Count(Decisions("drop"), ""), 0, "nothing dropped")
end)

Test("Windfury Totem with Flurry: the late hit 1.30 s after the first swing (12:46 log)", function()
    NewGame(); Shaman()
    -- the weapon's Flurry delay learned first (three plain swings at 0.415)
    for i = 0, 2 do
        At(1 + 4 * i, function() Swing(3.21) end)
        At(1.415 + 4 * i, function() Hit() end)
    end
    At(13, function() Swing(3.21) end)
    At(13.117, function() ExtraSwing(3.21) end)
    At(13.414, function() Hit() end)
    At(14.303, function() Hit() end) -- 17417.305
    Run(16)
    Eq(Count(Decisions("show"), "your extra swing (Windfury Totem)"), 1, "the extra swing's")
    Eq(Count(Decisions("drop"), ""), 0, "nothing dropped")
end)

Test("Windfury Totem: not for another class, not an off-hand swing", function()
    NewGame() -- no class: not a shaman
    SIM.inGroup = false
    At(1, function() Swing(3.60) end)
    At(1.104, function() ExtraSwing(3.60) end)
    At(2.463, function() Hit() end)
    Run(4)
    Eq(Count(Decisions("show"), "your extra swing"), 0, "another class")
    Eq(WindfuryAlerts(), 0, "another class: no alert")
    NewGame(); Shaman()
    At(1, function() Swing(2.60) end)
    At(1.05, function() SIM.Fire("PLAYER_SWING", 2.60, 1); SIM.ClogLine("SWING_DAMAGE") end) -- off hand
    Run(3)
    Eq(WindfuryAlerts(), 0, "an off-hand swing isn't an extra one")
    UnitClass = nil
end)

-- (1.30.7) the late hit in a group too: 2026-11-11 16:33 log, 31166.195 (+1.463; the warrior's own +1.580)
Test("Windfury Totem in a group: the late hit is the extra swing's, a stranger's 0.50 s after it isn't yours", function()
    NewGame(); Shaman(true)
    At(1, function() Swing(3.60) end)
    At(1.104, function() ExtraSwing(3.60) end)
    At(1.462, function() Hit() end) -- yours, the first swing's
    At(1.600, function() Hit() end) -- someone else's, where a plain swing 0.10 s later would hit (1.30.5 showed it)
    At(2.463, function() Hit() end) -- yours, the extra swing's (1.30.6 looked for none in a group)
    At(2.580, function() Hit() end) -- someone else's, 0.12 s after it
    Run(4)
    Eq(Count(Decisions("show"), "(your swing, "), 1, "the first swing's")
    Eq(Count(Decisions("show"), "your extra swing (Windfury Totem)"), 1, "the extra swing's")
    Eq(#Decisions("show"), 2, "nothing else shown")
    Eq(WindfuryAlerts(), 1, "one alert")
    UnitClass = nil
end)

-- 2026-11-11 16:33 log, 31010.490: both swings in one frame, two hits at +0.460, none at +1.46
Test("Windfury Totem: the pair's two numbers in one frame are both yours, and no late one is looked for", function()
    NewGame(); Shaman(true)
    At(1, function() Swing(3.60); ExtraSwing(3.60) end)
    At(1.460, function() Hit(); Hit() end)
    At(2.463, function() Hit() end) -- someone else's: the extra swing's hit has come
    Run(4)
    Eq(Count(Decisions("show"), "(your swing, "), 1, "the first swing's")
    Eq(Count(Decisions("show"), "your extra swing (Windfury Totem), with your swing's hit"), 1, "the extra swing's")
    Eq(#Decisions("show"), 2, "the later one isn't shown")
    -- a plain swing's two hits in one frame still can't be told apart
    At(5, function() Swing(3.60) end)
    At(5.460, function() Hit(); Hit() end)
    Run(8)
    Eq(#Decisions("show"), 2, "no extra swing: neither shown")
    -- nor a pair's in a raid
    NewGame(); Shaman(true); SIM.inRaid = true
    At(1, function() Swing(3.60); ExtraSwing(3.60) end)
    At(1.460, function() Hit(); Hit() end)
    Run(4)
    Eq(#Decisions("show"), 0, "in a raid: neither shown")
    UnitClass = nil
end)

Test("Windfury Totem: the one quick hit of a pair that kills teaches the weapon no swing delay", function()
    NewGame(); Shaman()
    -- the swings 0.10 s apart as at 17850.379 (12:53 log), the pair's only number 0.241 s after as at
    -- 17419.307 (12:46 log; there both swings came in one frame, which never taught anything)
    At(1, function() Swing(3.60) end)
    At(1.104, function() ExtraSwing(3.60) end)
    At(1.241, function() Hit() end)
    Run(4)
    local seen = ForeverFloatingTextDB.swingAnims and ForeverFloatingTextDB.swingAnims["3.60"]
    Eq(seen and #seen or 0, 0, "nothing kept as a delay of the weapon")
    Eq(#Decisions("show"), 0, "and the hit isn't shown")
    UnitClass = nil
end)

Test("Windfury from Stormstrike: its extra line in the cast's frame", function()
    NewGame()
    At(1, function() Cast(17364); Line("SPELL_DAMAGE"); Hit(); Line("SPELL_DAMAGE") end)
    At(1.505, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 1, "the extra attack")
end)

Test("a hit outside Windfury's two slots doesn't take its line", function()
    NewGame()
    At(1, function() Swing(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.36, function() Hit() end) -- between the slots: someone else's
    At(5, function() Swing(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(5.275, function() Hit() end) -- just past the first slot (one such in the 14:54 group log)
    Run(7)
    Eq(Count(Decisions("show"), "Windfury"), 0, "not taken")
end)

Test("Windfury with Flurry: the swing's hit 0.905 s after the proc is yours (14:54 group log)", function()
    NewGame()
    At(1, function() Swing(2.95); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.23, function() Hit() end)
    At(1.50, function() Hit() end)
    At(1.905, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "later as your Windfury"), 1, "the swing")
end)

-- 13 procs in the kept logs (2026-11-09 09:59 560419.562: lines +0.103, hits 0.232, 0.504, 0.959 after them)
Test("Windfury lines 0.10 s after the swing: hits timed from the lines", function()
    NewGame()
    At(1, function() Swing() end)
    At(1.103, function() Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.335, function() Hit() end)
    At(1.607, function() Hit() end)
    At(2.062, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(Count(Decisions("show"), "after your swing"), 0, "timed from the lines")
    Eq(Count(Decisions("show"), "later as your Windfury"), 1, "the swing")
end)

-- 2026-11-10 12:33 log, solo, 7407.949: lines +0.099, hits 0.229, 0.501, 0.911 s after the swing; all dropped
Test("Windfury lines 0.10 s after the swing, hits timed from the swing: all three are yours", function()
    NewGame()
    SIM.inGroup = false -- solo, as in that log
    At(1, function() Swing(2.95) end)
    At(1.099, function() Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.229, function() Hit() end)
    At(1.501, function() Hit() end)
    At(1.911, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(Count(Decisions("show"), "after your swing"), 2, "timed from the swing")
    Eq(Count(Decisions("show"), "later as your Windfury"), 1, "the swing")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- in the simulator the swing-timed slots let in more of others' hits than they gave back of yours
Test("in a raid, hits timed from the swing are not taken (they could be anyone's)", function()
    NewGame()
    SIM.inRaid = true
    At(1, function() Swing(2.95) end)
    At(1.099, function() Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.229, function() Hit() end)
    At(1.501, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "Windfury"), 0, "not taken")
end)

-- (1.30.7) 2026-11-11 16:56 log, in a party, 32621.033: lines +0.113 ("Windfury Weapon" by the game's
-- file), hits 0.231, 0.505, 0.910 s after the swing; all dropped by 1.30.6 and no "Windfury!"
Test("in a party, Windfury hits timed from the swing are yours, with the alert", function()
    NewGame() -- the stub starts in a group, not a raid
    At(1, function() Swing(3.21) end)
    At(1.113, function() Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.231, function() Hit() end)
    At(1.505, function() Hit() end)
    At(1.910, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(Count(Decisions("show"), "after your swing"), 2, "timed from the swing")
    Eq(Count(Decisions("show"), "later as your Windfury"), 1, "the swing")
    Eq(#Decisions("drop"), 0, "none dropped")
    Eq(WindfuryAlerts(), 1, "the alert")
end)

-- (1.30.7) 2026-11-11 15:38 log, 29098.123: Stormstrike 0.49 s after a proc, its own hit in its frame
-- taken as the proc's second attack, the real one 0.018 s later dropped
Test("Stormstrike's own hit in a Windfury slot is the cast's; the Windfury attack just after keeps its line", function()
    NewGame()
    At(1, function() Swing(3.60); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.230, function() Hit() end)
    At(1.485, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(1.503, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "your Combat Log line, +0.000s"), 1, "Stormstrike's")
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "both Windfury attacks")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- (1.30.8) 2026-11-11 dungeon run: a groupmate's glancing swing in the proc lines' frame (40135.248)
-- and one in the first Windfury slot (40559.032) each took a line; the second attack was dropped
Test("a glancing hit is a white swing's: it takes no spell line and no Windfury line", function()
    NewGame()
    At(1, function() Swing(3.60); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE"); Hit(nil, 1, "GLANCING") end)
    At(1.219, function() Hit() end)
    At(1.236, function() Hit(nil, 1, "GLANCING") end)
    At(1.492, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "both Windfury attacks")
    Eq(Count(Decisions("drop"), "no Combat Log line"), 2, "the two glancing hits")
end)

-- 2026-11-09 14:12 log, 575583.916: lines +0.110, hits 0.234 and 0.501 s after the cast
Test("Windfury from Stormstrike, its lines 0.11 s after the cast, hits timed from the cast", function()
    NewGame()
    SIM.inGroup = false -- solo, as in that log
    At(1, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(1.110, function() Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.234, function() Hit() end)
    At(1.501, function() Hit() end)
    Run(3)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(Count(Decisions("show"), "after your Stormstrike"), 2, "timed from the cast")
end)

-- 2026-11-10 12:55 log at 30 frames a second, 8776.974: lines +0.134, hits 0.200 and 0.500 s after
-- them, both dropped by 1.28.10 (only the cast's own frame was looked at; 0.200 is the slot's edge)
Test("at 30 fps: Windfury from Stormstrike with its lines 4 frames after the cast", function()
    NewGame()
    SIM.FRAME = 1 / 30
    GetFramerate = function() return 30 end
    At(3.0, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(3.134, function() Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(3.334, function() Hit() end)
    At(3.634, function() Hit() end)
    Run(5)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- the same log: swings 0.433 / 0.467 s, a Windfury hit 0.500 s after its line, its swing 0.900 s
Test("at 30 fps: a swing 0.433 s after, Windfury hits at the slots' edges and its swing 0.900 s after are yours", function()
    NewGame()
    SIM.FRAME = 1 / 30
    GetFramerate = function() return 30 end
    At(3.0, function() Swing() end)
    At(3.434, function() Hit() end)
    At(6.0, function() Swing(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(6.2, function() Hit() end)
    At(6.534, function() Hit() end)
    At(6.9, function() Hit() end)
    Run(9)
    Eq(Count(Decisions("show"), "your swing, 0.43"), 1, "the plain swing")
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(Count(Decisions("show"), "later as your Windfury"), 1, "the Windfury swing")
end)

-- 2026-11-10 13:21 log, 10564.144: Stormstrike's proc, a swing 0.365 s later, its hit 0.960 s after the proc
Test("a swing that starts just after a Stormstrike's Windfury proc hits 0.96 s after the proc", function()
    NewGame()
    At(1, function() Cast(17364); Line("SPELL_DAMAGE"); Hit(); Line("SPELL_DAMAGE") end)
    At(1.228, function() Hit() end)
    At(1.365, function() Swing() end)
    At(1.960, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 1, "the Windfury attack")
    Eq(Count(Decisions("show"), "later as your Windfury"), 1, "the swing, late")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- the same swing with no proc before it lands as usual (Stormstrike 0.45 s before a swing doesn't delay it)
Test("a swing just after a Stormstrike with no proc hits at its usual 0.46 s", function()
    NewGame()
    At(1, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(1.365, function() Swing() end)
    At(1.826, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "your swing, 0.4"), 1, "the swing on time")
end)

-- 2026-11-10 13:50 log, 12134.959 (Earth Shock in the swing's frame) and 12137.976: 0.886 / 0.887 s
Test("a Flurry swing delayed by a cast hits 0.887 s after it", function()
    NewGame()
    At(1, function() Swing(2.95); Cast(8042); Line("SPELL_DAMAGE"); Hit(nil, 8) end)
    At(1.886, function() Hit() end)
    Run(3.5)
    Eq(Count(Decisions("show"), "later as your Earth Shock"), 1, "the swing")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- the same log, 12379.054: proc with the swing, Stormstrike 0.808 s later, the swing's hit 1.491 s after the proc
Test("a Windfury swing delayed again by a Stormstrike hits 1.49 s after the proc", function()
    NewGame()
    At(1, function() Swing(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.231, function() Hit() end)
    At(1.500, function() Hit() end)
    At(1.808, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(2.491, function() Hit() end)
    Run(4)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(Count(Decisions("show"), "your swing, 1.4"), 1, "the swing, after the Stormstrike")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- and with Flurry 1.385 s (12108.084, Stormstrike +0.826)
Test("a Flurry Windfury swing delayed by a Stormstrike hits 1.385 s after the proc", function()
    NewGame()
    At(1, function() Swing(2.95); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.231, function() Hit() end)
    At(1.506, function() Hit() end)
    At(1.826, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(2.385, function() Hit() end)
    Run(4)
    Eq(Count(Decisions("show"), "your swing, 1.3"), 1, "the swing, after the Stormstrike")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

Test("a totem's line in the swing's frame isn't taken for Windfury", function()
    NewGame()
    At(0.8, function() Line("SPELL_CAST_SUCCESS") end) -- the totem's cast (no cast of yours)
    At(1, function() Swing(); Line("SPELL_DAMAGE") end) -- its damage line, its hit still to come
    At(1.10, function() Hit(nil, 4) end) -- the totem's Fire hit, late
    At(1.228, function() Hit() end) -- someone else's physical hit in Windfury's slot
    Run(3)
    Eq(Count(Decisions("show"), "Windfury"), 0, "no Windfury")
end)

-- (1.28.14) From the 2026-11-10 15:25 dungeon log, read against the game's own combat log file.
-- 17824.661: a proc's two lines, a tank's damage shield 0.010 s and the tank's swing 0.037 s later took
-- them, and both Windfury hits were dropped
Test("a line from an earlier frame isn't a later hit's: Windfury's lines wait for their own hits", function()
    NewGame()
    At(1, function() Swing() end)
    At(1.033, function() Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.05, function() Hit("nameplate2", 8) end) -- someone's Nature hit, a frame after the lines
    At(1.067, function() Hit() end)               -- and someone's physical hit
    At(1.267, function() Hit() end)
    At(1.533, function() Hit() end)
    At(1.993, function() Hit() end)
    Run(4)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two Windfury hits")
    Eq(Count(Decisions("show"), "your swing"), 1, "the swing")
    Eq(#Decisions("show"), 3, "nothing else shown")
    Eq(Count(Decisions("drop"), "no Combat Log line"), 2, "the strangers' hits dropped")
end)

Test("Searing Totem's line a frame before its hit counts while its attack is in the air, not otherwise", function()
    NewGame({db = {minionSchools = {[3606] = 4}}})
    At(0.8, function() Line("SPELL_CAST_SUCCESS") end) -- the totem's cast (no cast of yours)
    At(1, function() Line("SPELL_DAMAGE") end)
    At(1.017, function() Hit(nil, 4) end)
    At(4, function() Line("SPELL_DAMAGE") end) -- a line whose hit never came, no attack in the air
    At(4.017, function() Hit(nil, 4) end)      -- someone's Fire hit a frame later
    Run(5)
    Eq(Count(Decisions("show"), "was on its way"), 1, "the totem's hit")
    Eq(#Decisions("show"), 1, "only that one")
    Eq(#Decisions("drop"), 1, "the other dropped")
end)

-- 17982.947: a swing with a miss line; its Dodge 0.416 s later was dropped and a hit 0.436 s later taken.
-- 17956.964: a swing with a hit line; a stranger's Miss was shown as its hit.
Test("a swing's line says hit or miss: a missed swing takes no hit, a swing that hit takes no miss", function()
    NewGame({db = {showMisses = true}})
    At(1, function() Swing(2.95, "DODGE") end)
    At(1.417, function() Miss("nameplate1", "DODGE") end)
    At(1.433, function() Hit() end) -- someone else's, closer to 0.46
    At(5, function() Swing() end)
    At(5.45, function() Miss("nameplate1", "MISS") end) -- someone else's, as close to 0.46
    At(5.467, function() Hit() end)
    Run(7)
    Eq(Count(Decisions("show"), "Dodge (your swing"), 1, "the missed swing's Dodge")
    Eq(Count(Decisions("show"), "your swing"), 2, "and the other swing's hit")
    Eq(#Decisions("drop"), 2, "the strangers' two dropped")
end)

-- 17982.947 again, and 18025.887 (a hit at 0.416 s lost to one at 0.487): every plain swing at
-- "weapon 2.95s" in that log hit after 0.408-0.417 s
Test("a weapon speed whose swings hit at 0.415 s is learned: the next takes the hit there, not one nearer 0.46", function()
    NewGame()
    for i = 0, 2 do
        At(1 + 3 * i, function() Swing(2.95) end)
        At(1.417 + 3 * i, function() Hit() end)
    end
    At(10, function() Swing(2.95) end)
    At(10.417, function() Hit(nil, 1, "CRITICAL") end) -- yours
    At(10.483, function() Hit() end)                   -- someone else's, nearer 0.46
    At(13, function() Swing(3.30) end)                 -- not learned for this speed: can't tell
    At(13.417, function() Hit() end)
    At(13.5, function() Hit() end)
    Run(15)
    Eq(Count(Decisions("show"), "your swing, 0.42"), 4, "the three, and the fourth at 0.415")
    Eq(#Decisions("show"), 4, "nothing else")
    local learned = 0
    for _, l in ipairs(ForeverFloatingTextLog.lines) do if l:find("hit after 0.415 s", 1, true) then learned = learned + 1 end end
    Eq(learned, 1, "logged once")
end)

-- 17824.632: proc 0.029 s after the swing, Stormstrike 0.19 s after the proc, the swing's hit 0.959 s
-- after the proc; a hunter's shot 1.41 s after it was shown as the swing "delayed by Stormstrike"
Test("a Windfury swing isn't delayed by a cast soon after the proc", function()
    NewGame()
    At(1, function() Swing(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.2, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(1.233, function() Hit() end)
    At(1.5, function() Hit() end)
    At(1.96, function() Hit() end)
    At(2.433, function() Hit() end) -- someone else's, where a delayed hit would come
    Run(4)
    Eq(Count(Decisions("show"), "later as your Windfury came with it"), 1, "the swing's hit, 0.96 s after the proc")
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "the two attacks")
    Eq(#Decisions("drop"), 1, "the late one dropped")
end)

-- (1.29.0) The 2026-11-10 18:53 log (solo, a new weapon, "weapon 3.10s"): plain swings hit after
-- 0.366, 0.464 or 0.732 s; the outer two were dropped
Test("a weapon's other swing delays are learned solo from swings with one hit, then shown", function()
    NewGame({db = {showMisses = true}})
    SIM.inGroup = false
    for i = 0, 2 do
        At(1 + 6 * i, function() Swing(3.10) end)
        At(1.366 + 6 * i, function() Hit(nil, 1, "GLANCING") end)
        At(4 + 6 * i, function() Swing(3.10, "PARRY") end)
        At(4.732 + 6 * i, function() Miss("nameplate1", "PARRY") end)
    end
    At(20, function() Swing(3.10) end)
    At(20.361, function() Hit() end)
    At(23, function() Swing(3.10) end)
    At(23.729, function() Hit() end)
    At(26, function() Swing(3.30) end) -- another weapon: nothing learned for it
    At(26.732, function() Hit() end)
    Run(28)
    Eq(Count(Decisions("drop"), "no Combat Log line"), 7, "the six that taught it, and the other weapon's")
    Eq(Count(Decisions("show"), "your swing, 0.3"), 1, "then a hit at 0.366")
    Eq(Count(Decisions("show"), "your swing, 0.7"), 1, "and one at 0.732")
    local learned = 0
    for _, l in ipairs(ForeverFloatingTextLog.lines) do if l:find("hit after 0.%d+ s too") then learned = learned + 1 end end
    Eq(learned, 2, "two delays logged once each")
    Ok(ForeverFloatingTextDB.swingAnims and ForeverFloatingTextDB.swingAnims["3.10"], "kept in the saved variables")
end)

Test("in a group nothing new is learned, and a hit outside the swing's window stays dropped", function()
    NewGame()
    for i = 0, 3 do
        At(1 + 3 * i, function() Swing(3.10) end)
        At(1.732 + 3 * i, function() Hit() end)
    end
    Run(14)
    Eq(Count(Decisions("drop"), "no Combat Log line"), 4, "all four dropped")
    Eq(ForeverFloatingTextDB.swingAnims, nil, "nothing learned")
end)

Test("a hit with its own spell line isn't the swing's at a learned delay", function()
    NewGame({db = {showMisses = true, swingAnims = {["3.10"] = {{d = 0.366, n = 5}, {d = 0.464, n = 5}}}}})
    At(1, function() Swing(3.10, "PARRY") end)
    At(1.373, function() Miss("nameplate1", "MISS"); Line("SPELL_MISSED", "MISS") end) -- a totem's miss
    At(1.464, function() Miss("nameplate1", "PARRY") end)
    Run(3)
    Eq(Count(Decisions("show"), "Parry (your swing"), 1, "the swing's Parry")
    Eq(Count(Decisions("show"), "Miss (your Combat Log line"), 1, "the totem's Miss by its line")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- 30476.705 (two lines: 0.366, 0.756, the swing 1.477), 30352.727 (one line: 0.361, swing 1.482),
-- 30458.068 (one line: 0.179, swing 0.862), 30634.656 (0.230, 0.504, swing 0.965)
Test("Windfury with learned swing delays: attacks at half of one or 0.755 s, the swing 0.50 or 0.755 s plus one", function()
    NewGame({db = {swingAnims = {["3.10"] = {{d = 0.366, n = 5}, {d = 0.464, n = 5}, {d = 0.731, n = 5}}}}})
    At(1, function() Swing(3.10); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(1.366, function() Hit() end)
    At(1.756, function() Hit() end)
    At(2.477, function() Hit(nil, 1, "GLANCING") end)
    At(5, function() Swing(3.10); Line("SPELL_DAMAGE") end)
    At(5.361, function() Hit() end)
    At(6.482, function() Hit(nil, 1, "GLANCING") end)
    At(9, function() Swing(3.10); Line("SPELL_DAMAGE") end)
    At(9.179, function() Hit() end)
    At(9.862, function() Hit() end)
    At(13, function() Swing(3.10); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(13.230, function() Hit() end)
    At(13.504, function() Hit() end)
    At(13.965, function() Hit(nil, 1, "GLANCING") end)
    Run(16)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 6, "every Windfury attack")
    Eq(Count(Decisions("show"), "later as your Windfury came with it"), 4, "every swing")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- 30209.011: Stormstrike in the swing's frame, its hit 1.494 s after; 30282.250: Stormstrike +0.570, 1.496 s
Test("with a long learned delay a swing delayed by a cast may hit 1.495 s after it", function()
    NewGame({db = {swingAnims = {["3.10"] = {{d = 0.366, n = 5}, {d = 0.464, n = 5}, {d = 0.731, n = 5}}}}})
    At(1, function() Swing(3.10); Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(2.494, function() Hit(nil, 1, "GLANCING") end)
    At(5, function() Swing(3.10) end)
    At(5.570, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(6.496, function() Hit() end)
    Run(8)
    Eq(Count(Decisions("show"), "your swing, 1.4"), 2, "both")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- (1.29.1) The 2026-11-10 19:58 log: Flurry swings ("2.77s", learned 0.320 / 0.414 / 0.651) with a cast
-- 0.48-0.60 s after them hit 1.334 and 1.338 s after (34136.259, 34151.090)
Test("the cast-delayed moment of a long delay scales with Flurry", function()
    NewGame({db = {swingAnims = {["2.77"] = {{d = 0.320, n = 5}, {d = 0.414, n = 5}, {d = 0.651, n = 5}}}}})
    At(1, function() Swing(2.77) end)
    At(1.483, function() Cast(8042); Line("SPELL_DAMAGE"); Hit(nil, 8) end)
    At(2.333, function() Hit(nil, 1, "CRITICAL") end)
    Run(4)
    Eq(Count(Decisions("show"), "your swing, 1.3"), 1, "the swing")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- 34136.853: Stormstrike's two Windfury lines with Flurry up; its attacks at 0.365 (half the plain
-- 0.732) and 0.502, then the Flurry swing delayed by that Stormstrike at 1.334
Test("Windfury's attacks go by the plain delays while Flurry is up", function()
    NewGame({db = {swingAnims = {
        ["3.10"] = {{d = 0.366, n = 5}, {d = 0.464, n = 5}, {d = 0.732, n = 5}},
        ["2.77"] = {{d = 0.320, n = 5}, {d = 0.414, n = 5}, {d = 0.651, n = 5}}}}})
    At(1, function() Swing(3.10) end)
    At(1.467, function() Hit() end)
    At(4, function() Swing(2.77) end)
    At(4.6, function() Cast(17364); Line("SPELL_DAMAGE"); Hit(); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE") end)
    At(4.967, function() Hit(nil, 1, "CRITICAL") end)
    At(5.1, function() Hit() end)
    At(5.333, function() Hit(nil, 1, "GLANCING") end)
    Run(7)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "both attacks")
    Eq(Count(Decisions("show"), "your swing, 1.3"), 1, "the Flurry swing")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- 34190.284: Stormstrike, two Windfury lines and Searing Totem's line in one frame; the totem's hit
-- took its line a little later, and Windfury's second attack was dropped
Test("a totem's line its own hit took isn't held back from Windfury", function()
    NewGame({db = {minionSchools = {[3606] = 4}}})
    At(0.8, function() Line("SPELL_CAST_SUCCESS") end) -- the totem's cast (no cast of yours)
    At(1, function()
        Cast(17364); Line("SPELL_DAMAGE"); Hit()
        Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE"); Line("SPELL_DAMAGE")
    end)
    At(1.017, function() Hit(nil, 4) end) -- the totem's Fire hit, a frame later
    At(1.233, function() Hit() end)
    At(1.500, function() Hit(nil, 1, "BLOCK_REDUCED") end)
    Run(3)
    Eq(Count(Decisions("show"), "your extra attack (Windfury)"), 2, "both attacks")
    Eq(#Decisions("drop"), 0, "none dropped")
end)

-- (1.30.8) 2026-11-11 dungeon run, 40439.005: Searing Totem's cast line, Stormstrike (its line and
-- hit) 0.019 s later, the totem's line 0.169 s after the cast, its Fire hit 0.196 s after that and
-- a groupmate's Deep Wound 0.020 s later, shown as a Windfury attack with "Windfury!"
Test("a cast's own line doesn't pay what the totem owes: the totem's later line is no Windfury proc", function()
    NewGame({db = {minionSchools = {[3606] = 4}}})
    At(0.800, function() Line("SPELL_CAST_SUCCESS") end) -- the totem's cast (no cast of yours)
    At(0.819, function() Cast(17364); Line("SPELL_DAMAGE"); Hit() end)
    At(0.988, function() Line("SPELL_DAMAGE") end) -- the totem's line
    At(1.184, function() Hit(nil, 4) end) -- the totem's Fire hit
    At(1.204, function() Hit() end) -- a groupmate's
    Run(3)
    Eq(Count(Decisions("show"), "was on its way"), 1, "the totem's hit")
    Eq(Count(Decisions("show"), "Windfury"), 0, "no Windfury attack")
    Eq(WindfuryAlerts(), 0, "no alert")
end)

-- (1.30.0) Where your damage shows, and your target with no nameplate
local function AtSpot(list) -- shown at the damage spot (no plate, its key)
    local n = 0
    for _, s in ipairs(list) do if s.plate == nil and s.key == "damage" then n = n + 1 end end
    return n
end
local function OnPlate(list) -- drawn over a nameplate
    local n = 0
    for _, s in ipairs(list) do if s.plate ~= nil then n = n + 1 end end
    return n
end
local function NoPlateTarget(token)
    local info = {guid = "Creature-0-1-1-1-9-" .. token, name = token, enemy = true}
    SIM.AddUnit(token, info)
    SIM.target = token
    SIM.Fire("PLAYER_TARGET_CHANGED")
    return info
end

Test("with the scrolling area chosen, your damage shows there, not over the nameplate", function()
    NewGame({db = {damageWhere = "spot"}})
    At(1, function() Cast(8042); Line("SPELL_DAMAGE"); Hit(nil, 8) end)
    At(2, function() Swing() end)
    At(2.467, function() Hit() end)
    Run(4)
    Eq(#Decisions("show"), 2, "both yours")
    Eq(AtSpot(G.shown), 2, "both at the damage spot")
end)

Test("your target with no nameplate: its own reports show at the damage spot", function()
    NewGame()
    NoPlateTarget("mob")
    At(1, function() Cast(8042); Line("SPELL_DAMAGE"); Hit("target", 8) end)
    At(2, function() Swing() end)
    At(2.467, function() Hit("target") end)
    At(3, function() Hit("target") end) -- someone else's, no line, no swing
    Run(5)
    Eq(#Decisions("show"), 2, "the spell and the swing")
    Eq(AtSpot(G.shown), 2, "at the spot")
    Eq(#Decisions("drop"), 1, "the stranger's dropped")
end)

Test("with a nameplate, the target's own report isn't counted twice", function()
    NewGame()
    At(1, function() Cast(8042); Line("SPELL_DAMAGE"); Hit("nameplate1", 8); Hit("target", 8) end)
    Run(3)
    Eq(#Decisions("show"), 1, "shown once")
    Eq(#Decisions("drop"), 0, "and not looked at as a second hit")
    Eq(OnPlate(G.shown) + AtSpot(G.shown), 1, "drawn once")
    Eq(OnPlate(G.shown), 1, "over the nameplate")
end)

Test("a swing at one target never takes a hit on the next one", function()
    NewGame()
    NoPlateTarget("mob")
    At(1, function() Swing() end)
    At(1.2, function() NoPlateTarget("mob2") end)
    At(1.467, function() Hit("target") end) -- reported for the new target
    Run(3)
    Eq(#Decisions("show"), 0, "not shown")
    Eq(#Decisions("drop"), 1, "dropped")
end)

Test("a swing made before the target's nameplate came takes its hit on the plate", function()
    NewGame()
    local info = NoPlateTarget("mob")
    At(1, function() Swing() end)
    At(1.2, function() SIM.AddUnit("nameplate3", info); SIM.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3") end)
    At(1.467, function() Hit("nameplate3") end)
    Run(3)
    Eq(Count(Decisions("show"), "your swing"), 1, "the swing's")
    Eq(OnPlate(G.shown), 1, "over the new nameplate")
end)

Test("five spots became three: the heal spot's place carries over to the damage spot", function()
    NewGame({db = {healFallbackX = 120, healFallbackY = 30, healSize = 18, powerX = 5, powerY = -90}})
    local db = ForeverFloatingTextDB
    Eq(db.damageX, 120, "damage spot x from the heal spot")
    Eq(db.damageY, 30, "and y")
    Eq(db.healSize, nil, "the heal spot's settings gone")
    Eq(db.powerX, nil, "the power spot's too")
    Eq(G.FFT.SPOTS.heal, nil, "no heal spot")
    Eq(G.FFT.SPOTS.power, nil, "no power spot")
end)

-- (1.30.0) Loot, from the game's own loot messages (templates as in its enUS GlobalStrings)
local function LootGame(db)
    LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s", "You receive loot: %sx%d"
    LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %s", "You receive item: %sx%d"
    LOOT_ITEM_CREATED_SELF, LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %s.", "You create: %sx%d."
    YOU_LOOT_MONEY, YOU_LOOT_MONEY_MOD, LOOT_MONEY_SPLIT = "You loot %s", "You loot %s (+%s)", "Your share of the loot is %s."
    GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
    ITEM_QUALITY_COLORS = {[0] = {hex = "|cff9d9d9d"}, [1] = {hex = "|cffffffff"}, [2] = {hex = "|cff1eff00"}}
    GetMoneyString = function(copper) return "money:" .. copper end
    NewGame({db = db})
end
local function Link(color, name) return ("|c%s|Hitem:1::::::::|h[%s]|h|r"):format(color, name) end
local function LootTexts()
    local out = {}
    for _, s in ipairs(Shown("loot")) do out[#out + 1] = s.text end
    return out
end

Test("loot: your items in their color with the count, money as coins; not others', not crafted, not gray", function()
    LootGame()
    At(1, function()
        SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. Link("ff1eff00", "Sample Ring"))
        SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. Link("ffffffff", "Linen Cloth") .. "x2")
        SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. Link("ff9d9d9d", "Broken Fang"))  -- gray
        SIM.Fire("CHAT_MSG_LOOT", "You create: " .. Link("ffffffff", "Linen Bandage") .. ".")
        SIM.Fire("CHAT_MSG_LOOT", "Bob receives loot: " .. Link("ff1eff00", "Their Ring") .. ".")
        SIM.Fire("CHAT_MSG_MONEY", "You loot 1 Gold, 23 Silver, 45 Copper")
        SIM.Fire("CHAT_MSG_MONEY", "Your share of the loot is 12 Copper.")
        SIM.Fire("CHAT_MSG_LOOT", SIM.Secret("You receive loot: " .. Link("ff1eff00", "Hidden Ring")))
    end)
    Run(2)
    local t = LootTexts()
    Eq(table.concat(t, " / "), "+|cff1eff00[Sample Ring]|r / +|cffffffff[Linen Cloth]|r x2 / +money:12345 / +money:12", "shown")
    local hidden = 0
    for _, l in ipairs(ForeverFloatingTextLog.lines) do if l:find("hidden, skipped", 1, true) then hidden = hidden + 1 end end
    Eq(hidden, 1, "the hidden message logged and skipped")
end)

Test("loot: a link colored by a quality token (|cnIQ2:) is drawn in the quality's color", function()
    LootGame()
    local quality = {Ring = 2, Cloth = 1, Fang = 0}
    C_Item = {GetItemInfo = function(link)
        local name = link:match("%[(.-)%]")
        return name, link, quality[name]
    end}
    local function IQ(q, name) return ("|cnIQ%d:|Hitem:1::::::::|h[%s]|h|r"):format(q, name) end
    At(1, function()
        SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. IQ(2, "Ring"))
        SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. IQ(1, "Cloth") .. "x3")
        SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. IQ(0, "Fang"))
    end)
    Run(2)
    Eq(table.concat(LootTexts(), " / "), "+|cff1eff00[Ring]|r / +|cffffffff[Cloth]|r x3", "green, white, gray left out")
    C_Item = nil
end)

Test("loot: gray shown when chosen, money off, loot off", function()
    LootGame({lootMinQuality = "0", showMoney = false})
    At(1, function()
        SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. Link("ff9d9d9d", "Broken Fang"))
        SIM.Fire("CHAT_MSG_MONEY", "You loot 5 Copper")
    end)
    At(2, function() ForeverFloatingTextDB.showLoot = false; SIM.Fire("CHAT_MSG_LOOT", "You receive loot: " .. Link("ff1eff00", "Ring")) end)
    Run(3)
    Eq(table.concat(LootTexts(), " / "), "+|cff9d9d9d[Broken Fang]|r", "only the gray item")
end)

Test("the alerts spot at the old default (0, 120) moves up to 240 once; a chosen place stays", function()
    NewGame({db = {alertsX = 0, alertsY = 120}})
    Eq(ForeverFloatingTextDB.alertsY, 240, "old default moved")
    NewGame({db = {alertsX = 0, alertsY = 150}})
    Eq(ForeverFloatingTextDB.alertsY, 150, "chosen place kept")
    NewGame({db = {alertsX = 0, alertsY = 120, alertsSpot2 = true}})
    Eq(ForeverFloatingTextDB.alertsY, 120, "120 picked after the move is kept")
    NewGame()
    Eq(ForeverFloatingTextDB.alertsY, 240, "new install")
end)

Test("enemy nameplates off: said once in chat", function()
    NewGame({cvars = {nameplateShowEnemies = "0"}})
    SIM.Fire("PLAYER_REGEN_ENABLED")
    SIM.Fire("PLAYER_REGEN_DISABLED")
    local n = 0
    for _, l in ipairs(SIM.printed) do if l:find("enemy nameplates are off", 1, true) then n = n + 1 end end
    Eq(n, 1, "one notice")
end)

------------------------------------------------------------------------
-- Run them
------------------------------------------------------------------------
-- `lua5.3 sim/tests.lua <text>`: only the tests whose name holds the text, with the addon's log
-- printed when one fails
local ONLY = arg and arg[1]
local failed = 0
local ran = 0
for _, t in ipairs(tests) do
  if not ONLY or t.name:find(ONLY, 1, true) then
    ran = ran + 1
    local ok, err = xpcall(t.fn, debug.traceback)
    if ok and SIM and #SIM.errors > 0 then ok, err = false, "a Lua error in the game: " .. SIM.errors[1] end
    if ok then
        PRINT("ok    " .. t.name)
    else
        failed = failed + 1
        PRINT("FAIL  " .. t.name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
        if ONLY and ForeverFloatingTextLog then
            for _, l in ipairs(ForeverFloatingTextLog.lines) do PRINT("      | " .. l) end
        end
    end
  end
end
PRINT(("%d tests, %d failed"):format(ran, failed))
if failed > 0 and os and os.exit then os.exit(1) end
return failed
