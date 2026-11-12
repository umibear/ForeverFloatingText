-- Forever Floating Text simulator: a fake WoW, so the addon's real code can run outside the game.
-- Runs in the browser (sim.html, fengari = Lua 5.3 in JavaScript); the game itself runs Lua 5.1.
--
-- What it does like the game:
--   * a clock (GetTime) the simulator moves, in frames of 1/60 s; all events of one frame share
--     one time, and C_Timer callbacks run in a later frame, after that frame's game events
--   * secret values: they throw on math, ordering and joining, as in the game; SetFormattedText
--     takes them. The simulator can still read what's inside (SIM.Reveal), the addon can't.
--   * the Combat Log: a line (COMBAT_LOG_MESSAGE) only for events the selected filter lets through,
--     colored by the filter's event colors, as Blizzard's GenerateMessage does with
--     lineColorPriority 3
--   * nameplates, your target, groupmates, threat (hidden in groups)
-- Nothing here comes from the game: it's what our logs and Blizzard's source say the game does.

SIM = {
    now = 0,
    FRAME = 1 / 60,
    queue = {},        -- heap of {t, prio, seq, fn}
    seq = 0,
    handlers = {},     -- event -> list of frames
    errors = {},
    printed = {},
    shows = {},        -- what FFT:Show was asked to draw (filled by the scenario's recorder)
    units = {},        -- token -> {guid, name, enemy, plate}
    target = nil,      -- token of your target
    inGroup = true,
    inCombat = false,
    clogOn = true,     -- C_CombatLog.AreFilteredEventsEnabled()
    spells = {},       -- id -> {name, harmful, helpful}
    cvars = {},
}

unpack = unpack or table.unpack

------------------------------------------------------------------------
-- Secret values
------------------------------------------------------------------------
-- A hidden value is a box around the real one: doing sums with it, comparing it, joining it into a
-- string or taking its length fails, as the game's do; printed, it reads "<secret>". Only the
-- simulator opens the box (SIM.Reveal).
local HIDDEN = {__tostring = function() return "<secret>" end}
local function Refuse() error("can't use a secret value here (simulator)", 2) end
for _, operation in ipairs({"__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__idiv",
    "__lt", "__le", "__concat", "__len"}) do
    HIDDEN[operation] = Refuse
end
function SIM.Secret(v) return setmetatable({v = v}, HIDDEN) end
function issecretvalue(v)
    if type(v) ~= "table" then return false end
    return getmetatable(v) == HIDDEN
end
function SIM.Reveal(v) if issecretvalue(v) then return v.v end return v end

------------------------------------------------------------------------
-- Time: a heap of things to happen. prio 0 = a game event, 1 = an addon's timer
------------------------------------------------------------------------
local function Less(a, b)
    if a.t ~= b.t then return a.t < b.t end
    if a.prio ~= b.prio then return a.prio < b.prio end
    return a.seq < b.seq
end

local function Push(item)
    local q = SIM.queue
    q[#q + 1] = item
    local i = #q
    while i > 1 do
        local p = i // 2
        if Less(q[i], q[p]) then q[i], q[p] = q[p], q[i]; i = p else break end
    end
end

local function Pop()
    local q = SIM.queue
    local top = q[1]
    if not top then return nil end
    q[1] = q[#q]
    q[#q] = nil
    local i, n = 1, #q
    while true do
        local l, r, s = 2 * i, 2 * i + 1, i
        if l <= n and Less(q[l], q[s]) then s = l end
        if r <= n and Less(q[r], q[s]) then s = r end
        if s == i then break end
        q[i], q[s] = q[s], q[i]
        i = s
    end
    return top
end

-- the frame a time falls in (game events happen at frame times)
function SIM.FrameOf(t) return math.floor(t / SIM.FRAME + 1e-6) * SIM.FRAME end

local function Schedule(t, prio, fn)
    SIM.seq = SIM.seq + 1
    Push({t = t, prio = prio, seq = SIM.seq, fn = fn})
end

-- a game event (or several, in fn) at time t, moved to its frame
function SIM.At(t, fn) Schedule(SIM.FrameOf(t), 0, fn) end

-- an addon's C_Timer: the first frame at or after the due time, and never this frame
local function TimerAt(delay, fn)
    local due = SIM.now + math.max(delay or 0, 0)
    local t = math.ceil(due / SIM.FRAME - 1e-6) * SIM.FRAME
    if t <= SIM.now + 1e-9 then t = SIM.now + SIM.FRAME end
    Schedule(SIM.FrameOf(t + 1e-9), 1, fn)
end

local function Run(fn, ...)
    local ok, err = xpcall(fn, debug.traceback, ...)
    if not ok then
        SIM.errors[#SIM.errors + 1] = ("%.3f %s"):format(SIM.now, tostring(err))
    end
end

function SIM.RunUntil(tEnd)
    while SIM.queue[1] and SIM.queue[1].t <= tEnd do
        local item = Pop()
        SIM.now = item.t
        Run(item.fn)
    end
    SIM.now = tEnd
end

function GetTime() return SIM.now end
function date() return "2026-11-07 12:00:00" end
function time() return 0 end

C_Timer = {}
function C_Timer.After(delay, fn) TimerAt(delay, fn) end
function C_Timer.NewTicker(interval, fn, iterations)
    local ticker = {cancelled = false, n = 0}
    local function tick()
        if ticker.cancelled then return end
        ticker.n = ticker.n + 1
        fn(ticker)
        if not iterations or ticker.n < iterations then TimerAt(interval, tick) end
    end
    TimerAt(interval, tick)
    function ticker:Cancel() self.cancelled = true end
    return ticker
end
C_Timer.NewTimer = function(delay, fn)
    local timer = {cancelled = false}
    TimerAt(delay, function() if not timer.cancelled then fn(timer) end end)
    function timer:Cancel() self.cancelled = true end
    return timer
end

------------------------------------------------------------------------
-- Frames. Any method in CamelCase that isn't here does nothing.
------------------------------------------------------------------------
local Methods = {}
local FrameMT = {}
FrameMT.__index = function(_, k)
    local m = Methods[k]
    if m then return m end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
end

local function NewFrame(kind, name)
    local f = setmetatable({__kind = kind, __shown = true, __scripts = {}, __events = {}}, FrameMT)
    if name then _G[name] = f end
    return f
end
SIM.NewFrame = NewFrame

function Methods:RegisterEvent(event)
    self.__events[event] = true
    SIM.handlers[event] = SIM.handlers[event] or {}
    for _, f in ipairs(SIM.handlers[event]) do if f == self then return end end -- once, as in game
    table.insert(SIM.handlers[event], self)
end
function Methods:RegisterUnitEvent(event, ...)
    self:RegisterEvent(event)
    self.__unitFilter = self.__unitFilter or {}
    self.__unitFilter[event] = {...}
end
function Methods:UnregisterEvent(event) self.__events[event] = nil end
function Methods:SetScript(name, fn) self.__scripts[name] = fn end
function Methods:GetScript(name) return self.__scripts[name] end
function Methods:HookScript(name, fn) -- as the game: after the script already there, if any
    local before = self.__scripts[name]
    self.__scripts[name] = before and function(...) before(...); fn(...) end or fn
end
function Methods:SetAlpha(a) self.__alpha = a end
function Methods:GetAlpha() return self.__alpha or 1 end
function Methods:Show()
    local was = self.__shown
    self.__shown = true
    if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function Methods:Hide() self.__shown = false end
function Methods:IsShown() return self.__shown end
function Methods:IsVisible() return self.__shown end
function Methods:SetShown(v) self.__shown = v and true or false end
function Methods:CreateFontString(name) return NewFrame("FontString", name) end
function Methods:CreateTexture(name) return NewFrame("Texture", name) end
function Methods:SetFont() return true end
function Methods:SetText(text) self.__text = text end
function Methods:GetText() return self.__text end
function Methods:SetFormattedText(fmt, ...)
    for i = 1, select("#", ...) do
        local a = select(i, ...)
        if type(a) == "table" and not issecretvalue(a) then error("a table passed to SetFormattedText") end
    end
    self.__fmt, self.__args = fmt, {...}
end
-- a nameplate's place (outdoors: readable; SIM.securePositions makes them secret, as in dungeons)
function Methods:GetCenter()
    if SIM.securePositions then return SIM.Secret(500), SIM.Secret(400) end
    return 500, 400
end
function Methods:GetTop()
    if SIM.securePositions then return SIM.Secret(420) end
    return 420
end
function Methods:GetBottom() return 380 end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetWidth() return 1920 end
function Methods:GetHeight() return 1080 end
function Methods:GetName() return nil end

function CreateFrame(kind, name) return NewFrame(kind, name) end
UIParent = NewFrame("Frame", "UIParent")

-- Fires an event to every frame listening, as the game does
function SIM.Fire(event, ...)
    for _, f in ipairs(SIM.handlers[event] or {}) do
        local onEvent = f.__scripts.OnEvent
        local units = f.__unitFilter and f.__unitFilter[event]
        local pass = true
        if units then
            pass = false
            local unit = ...
            for _, u in ipairs(units) do if u == unit then pass = true end end
        end
        if onEvent and f.__events[event] and pass then Run(onEvent, f, event, ...) end
    end
end

------------------------------------------------------------------------
-- Units
------------------------------------------------------------------------
-- SIM.AddUnit("nameplate1", {guid=, name=, enemy=true}): a mob with a nameplate
function SIM.AddUnit(token, info)
    SIM.units[token] = info
    if token:find("^nameplate") then info.plate = NewFrame("NamePlate") end
end

local function Resolve(token)
    if token == nil then return nil end
    if token == "player" then return SIM.units.player end
    if token == "target" then return SIM.target and SIM.units[SIM.target] end
    return SIM.units[token]
end

local function Compound(token) return type(token) == "string" and token:find("target$") and token ~= "target" end

function UnitExists(token)
    if Compound(token) then return SIM.inGroup and SIM.Secret(false) or false end
    return Resolve(token) ~= nil
end
function UnitGUID(token) local u = Resolve(token); return u and u.guid end
function UnitName(token) local u = Resolve(token); return u and u.name end
function UnitIsUnit(a, b)
    if Compound(a) or Compound(b) then
        if SIM.inGroup then return SIM.Secret(false) end
        return false
    end
    local ua, ub = Resolve(a), Resolve(b)
    return ua ~= nil and ua == ub
end
function UnitCanAttack(_, token) local u = Resolve(token); return u ~= nil and u.enemy == true end
function UnitIsOwnerOrControllerOfUnit() return false end
-- threat: hidden (secret) in groups, as seen in game
function UnitDetailedThreatSituation(who, token)
    if SIM.inGroup then return SIM.Secret(true), SIM.Secret(1), SIM.Secret(0), SIM.Secret(0), SIM.Secret(0) end
    return nil
end
function IsInGroup() return SIM.inGroup end
function IsInRaid() return SIM.inGroup and SIM.inRaid == true end -- (1.30.7) a party unless told
function GetNumGroupMembers() return SIM.inGroup and 40 or 0 end
function GetNumTotemSlots() return 4 end
function InCombatLockdown() return SIM.inCombat end

C_NamePlate = {}
function C_NamePlate.GetNamePlateForUnit(token)
    local u = Resolve(token)
    return u and u.plate
end

------------------------------------------------------------------------
-- Spells
------------------------------------------------------------------------
local function Spell(idOrName)
    if type(idOrName) == "number" then return SIM.spells[idOrName] end
    for _, s in pairs(SIM.spells) do if s.name == idOrName then return s end end
end
C_Spell = {}
function C_Spell.GetSpellName(x) local s = Spell(x); return s and s.name end
function C_Spell.IsSpellHarmful(x) local s = Spell(x); return s and s.harmful or false end
function C_Spell.IsSpellHelpful(x) local s = Spell(x); return s and s.helpful or false end

------------------------------------------------------------------------
-- Settings, sounds, odds and ends
------------------------------------------------------------------------
C_CVar = {}
function C_CVar.GetCVar(name) return SIM.cvars[name] or "1" end
function C_CVar.SetCVar(name, value) SIM.cvars[name] = tostring(value) end
function C_CVar.GetCVarDefault() return "1" end
C_Sound = {PlaySound = function() end}
SOUNDKIT = {}
C_AddOns = {IsAddOnLoaded = function() return true end}
C_RestrictedActions = {IsAddOnRestrictionActive = function() return false end}
C_CombatLog = {}
function C_CombatLog.AreFilteredEventsEnabled() return SIM.clogOn end
function C_CombatLog.SetFilteredEventsEnabled(v) SIM.clogOn = v and true or false end
function C_CombatLog.IsCombatLogRestricted() return false end
Enum = {
    PlayerSwingType = {MainHand = 0, OffHand = 1, Ranged = 2},
    CombatLogMessageOrder = {Newest = 0, Oldest = 1},
    AddOnRestrictionType = {Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4},
}
bit = {
    band = function(a, b) return a & b end,
    bor = function(a, b) return a | b end,
    bxor = function(a, b) return a ~ b end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function AbbreviateNumbers(n) return tostring(n) end
SlashCmdList = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
MISS, DODGE, PARRY, BLOCK, RESIST = "Miss", "Dodge", "Parry", "Block", "Resist"
EVADE, IMMUNE, DEFLECT, ABSORB, REFLECT = "Evade", "Immune", "Deflect", "Absorb", "Reflect"
INTERRUPTED = "Interrupted"
COMBAT_TEXT_BLOCK_REDUCED = "%s (Block)"
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    SIM.printed[#SIM.printed + 1] = table.concat(t, " ")
end

------------------------------------------------------------------------
-- The Combat Log (Blizzard_CombatLog's saved filters, and its messages)
------------------------------------------------------------------------
COMBATLOG_FILTER_MINE = 0x4511
COMBATLOG_FILTER_MY_PET = 0x3111
DEFAULT_COMBATLOG_FILTER_TEMPLATE = {settings = {}, colors = {}}
-- a new player's: Blizzard's "My actions" (source: you; what's done to you too)
Blizzard_CombatLog_Filters = {
    currentFilter = 1,
    filters = {
        {name = "My actions", settings = {lineColoring = true, lineColorPriority = 1}, colors = {},
            filters = {{sourceFlags = {[COMBATLOG_FILTER_MINE] = true}},
                {destFlags = {[COMBATLOG_FILTER_MINE] = true}}}},
    },
}

-- A line of yours for this Combat Log event, if the selected filter lets it through
-- (only your own events are ever sent here: the scenario knows whose each event is)
function SIM.ClogLine(event, missType)
    if not SIM.clogOn then return end
    local all = Blizzard_CombatLog_Filters
    local f = all.filters[all.currentFilter]
    if not f then return end
    local passes = false
    for _, sub in ipairs(f.filters or {}) do
        if not sub.eventList or sub.eventList[event] then passes = true end
    end
    if not passes then return end
    local key = event
    if missType and event:find("_MISSED$") then key = event .. "_" .. missType end
    -- (1.31.0) dispels and broken crowd control: the aura's type added (ACTION_SPELL_DISPEL_BUFF ...)
    if missType and (event == "SPELL_DISPEL" or event == "SPELL_STOLEN" or event:find("^SPELL_AURA_BROKEN")) then
        key = event .. "_" .. missType
    end
    local c = f.colors and f.colors.eventColoring and f.colors.eventColoring[key]
    local r, g, b = 0.5, 0.5, 0.5 -- CombatLogUtil.GetColorByEventType's default
    if c then r, g, b = c.r, c.g, c.b end
    SIM.Fire("COMBAT_LOG_MESSAGE", SIM.Secret("a line"), r, g, b, Enum.CombatLogMessageOrder.Newest)
end
