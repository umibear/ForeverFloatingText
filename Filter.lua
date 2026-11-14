-- Forever Floating Text: the addon's own Combat Log filter, written into Blizzard's saved filters as
-- you log out or reload. How its lines are then read is in Core.lua ("Combat Log mode").
-- (1.31.18) Moved here from Core.lua, which was at Lua's limit of 200 local variables a file.

local ADDON, ns = ...
local FFT = ns.FFT
local Print = ns.Print

------------------------------------------------------------------------
-- Our own Combat Log filter (1.15.1)
------------------------------------------------------------------------
-- A new player's Combat Log uses Blizzard's "My actions" filter: it also shows what's done to
-- you, and its event list leaves out spell misses and damage shields (Lightning Shield, Thorns)
-- (Blizzard_CombatLog_Filter_Defaults in Blizzard_CombatLog.lua). So the addon adds a filter of
-- its own, "Forever Floating Text": only your and your pet's/guardians' actions, misses and damage
-- shields included, each kind of event in its own color, and selects it.
-- When: only at PLAYER_LOGOUT (also fires on /reload). The filters are Blizzard_CombatLog's saved
-- variable; only Blizzard's code may apply them (C_CombatLog.ApplyFilterSettings has
-- restrictions), and it reads them fresh from disk at the next login. Filter settings changed by an addon and
-- applied during play break Blizzard's secure Combat Log processor.
local OWN_FILTER_NAME = "Forever Floating Text"
-- (1.27.0) the addon's name before; its filter is taken over and renamed at the next logout, so
-- the Combat Log keeps working from the first login without a second filter left behind
local OLD_FILTER_NAMES = {OwnCombatText = true}
local OWN_COLORS = {          -- each kind its own color; swings and others never share a damage color
    direct = {1.00, 0.80, 0.30}, tick = {0.80, 0.60, 1.00}, ranged = {0.85, 0.70, 0.50},
    miss = {0.60, 0.65, 0.80}, shield = {1.00, 0.60, 0.25},
    melee = {0.90, 0.90, 0.90}, meleeMiss = {0.60, 0.60, 0.60},
    heal = {0.35, 1.00, 0.45}, hot = {0.55, 0.88, 0.55}, interrupt = {1.00, 0.45, 0.10}, kill = {1.00, 1.00, 1.00},
    cast = {0.45, 0.80, 1.00}, -- (1.17.0) apart from all the others and Blizzard's 0.5 grey default
    -- (1.31.0) your dispels and the crowd control your hit broke, apart from all of the above
    purge = {0.30, 0.85, 1.00}, cleanse = {0.40, 0.95, 0.80}, steal = {0.60, 0.80, 1.00},
    dispelFailed = {0.55, 0.72, 0.82}, broke = {1.00, 0.35, 0.35},
}
-- 1.17.0: SPELL_CAST_SUCCESS, so every cast of yours has a line. A harmful spell that does no
-- damage (Sunder Armor, Hunter's Mark, Purge) brought none, and 4 such casts in a row made
-- ClogActive think the lines had stopped. Its lines never stand for a hit (kind "cast").
-- SPELL_LEECH / SPELL_PERIODIC_LEECH: Drain Life-type damage.
local OWN_EVENTS = {
    SPELL_CAST_SUCCESS = "cast", SPELL_LEECH = "direct", SPELL_PERIODIC_LEECH = "tick",
    SPELL_DAMAGE = "direct", SPELL_BUILDING_DAMAGE = "direct", SPELL_PERIODIC_DAMAGE = "tick",
    RANGE_DAMAGE = "ranged", DAMAGE_SHIELD = "shield", SWING_DAMAGE = "melee",
    SPELL_MISSED = "miss", SPELL_PERIODIC_MISSED = "miss", RANGE_MISSED = "miss",
    DAMAGE_SHIELD_MISSED = "miss", SWING_MISSED = "meleeMiss",
    SPELL_HEAL = "heal", SPELL_PERIODIC_HEAL = "hot", SPELL_INTERRUPT = "interrupt", PARTY_KILL = "kill",
    SPELL_DISPEL = "purge", SPELL_STOLEN = "steal", SPELL_DISPEL_FAILED = "dispelFailed", -- (1.31.0)
    SPELL_AURA_BROKEN = "broke", SPELL_AURA_BROKEN_SPELL = "broke",
}
-- (1.31.0) these lines are colored by the event with the aura's type added (the game's strings:
-- ACTION_SPELL_DISPEL_BUFF "dispelled", _DEBUFF "cleansed", ACTION_SPELL_STOLEN_BUFF, ...):
-- a buff dispelled is a Purge, a debuff a cleanse
FFT.OWN_AURA_EVENTS = { -- a table of FFT: Core.lua is at Lua's 200 locals
    SPELL_DISPEL_BUFF = "purge", SPELL_DISPEL_DEBUFF = "cleanse", SPELL_STOLEN_BUFF = "steal", SPELL_STOLEN_DEBUFF = "steal",
    SPELL_AURA_BROKEN_BUFF = "broke", SPELL_AURA_BROKEN_DEBUFF = "broke",
    SPELL_AURA_BROKEN_SPELL_BUFF = "broke", SPELL_AURA_BROKEN_SPELL_DEBUFF = "broke",
}
-- A miss's line is colored by the event name with its miss type added (always for SPELL_MISSED,
-- for the others with "full text" on: CombatLogProcessor:GenerateMessage), so color those too
local MISS_TYPES = {"ABSORB", "BLOCK", "DEFLECT", "DODGE", "EVADE", "IMMUNE", "MISS", "PARRY", "REFLECT", "RESIST"}

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

local function OwnFilterIndex(saved)
    for i, f in ipairs(saved.filters) do
        if type(f) == "table" and f.name == OWN_FILTER_NAME then return i end
    end
    for i, f in ipairs(saved.filters) do
        if type(f) == "table" and OLD_FILTER_NAMES[f.name] then return i end
    end
end

-- Is the Combat Log using our filter now? (nil when it can't be told)
function FFT:OwnFilterInUse()
    local saved = _G.Blizzard_CombatLog_Filters
    if type(saved) ~= "table" or type(saved.filters) ~= "table" then return nil end
    local i = OwnFilterIndex(saved)
    return i ~= nil and saved.currentFilter == i
end

-- (1.31.18) Is the filter the game loaded the one this version writes: ours, selected, with every
-- event asked for? false right after installing (nothing written yet) and after an update that
-- adds events (1.31.0's dispels), until one /reload; nil when it can't be told.
function FFT:OwnFilterReady()
    local saved = _G.Blizzard_CombatLog_Filters
    if type(saved) ~= "table" or type(saved.filters) ~= "table" then return nil end
    local i = OwnFilterIndex(saved)
    if i == nil or saved.currentFilter ~= i then return false end
    local part = type(saved.filters[i].filters) == "table" and saved.filters[i].filters[1]
    local list = type(part) == "table" and part.eventList
    if type(list) ~= "table" then return false end
    for event in pairs(OWN_EVENTS) do
        if not list[event] then return false end
    end
    return true
end
-- Said once at login: until that /reload the addon works by a filter of Blizzard's or by the
-- fallback, and nothing told a new player so (only /fft status did).
function FFT:SetupReminder()
    C_Timer.After(8, function()
        if not (FFT.db.enabled and FFT.db.useCombatLog and FFT.db.ownClogFilter) or FFT:OwnFilterReady() ~= false then return end
        Print("type /reload once to finish the setup: the addon writes its own Combat Log filter as you "
            .. "reload or log out, and the game takes it at the next login. Until then fewer of your hits can be told.")
    end)
end

-- At PLAYER_LOGOUT only (see above)
function FFT:WriteOwnClogFilter()
    local saved = _G.Blizzard_CombatLog_Filters
    local mine, pet = _G.COMBATLOG_FILTER_MINE, _G.COMBATLOG_FILTER_MY_PET
    if type(saved) ~= "table" or type(saved.filters) ~= "table" or not mine or not pet then return end
    local index = OwnFilterIndex(saved)
    if not (FFT.db.enabled and FFT.db.useCombatLog and FFT.db.ownClogFilter) then
        -- turned off: give the Combat Log back the filter it had before ours
        if index and saved.currentFilter == index then
            local prev = FFT.db.clogPrevFilter
            saved.currentFilter = (type(prev) == "number" and prev ~= index and saved.filters[prev]) and prev or 1
        end
        return
    end
    if saved.currentFilter ~= index then FFT.db.clogPrevFilter = saved.currentFilter end
    index = index or (#saved.filters + 1)
    local filter = DeepCopy(_G.DEFAULT_COMBATLOG_FILTER_TEMPLATE or {})
    filter.name, filter.quickButtonName, filter.tooltip = OWN_FILTER_NAME, OWN_FILTER_NAME, OWN_FILTER_NAME
    filter.hasQuickButton = true
    filter.quickButtonDisplay = {solo = true, party = true, raid = true}
    filter.settings = type(filter.settings) == "table" and filter.settings or {}
    filter.settings.lineColoring = true
    filter.settings.lineColorPriority = 3 -- lines colored by event
    filter.settings.lineHighlighting = false
    filter.colors = type(filter.colors) == "table" and filter.colors or {}
    local coloring, events = {}, {}
    for event, kind in pairs(OWN_EVENTS) do
        local c = OWN_COLORS[kind]
        coloring[event] = {r = c[1], g = c[2], b = c[3], a = 1}
        events[event] = true
        if event:find("_MISSED$") then
            for _, missType in ipairs(MISS_TYPES) do
                coloring[event .. "_" .. missType] = {r = c[1], g = c[2], b = c[3], a = 1}
            end
        end
    end
    for event, kind in pairs(FFT.OWN_AURA_EVENTS) do -- (1.31.0) coloring only: not events of their own
        local c = OWN_COLORS[kind]
        coloring[event] = {r = c[1], g = c[2], b = c[3], a = 1}
    end
    filter.colors.eventColoring = coloring
    filter.colors.highlightedEvents = {}
    filter.filters = {{sourceFlags = {[mine] = true, [pet] = true}, eventList = events}}
    saved.filters[index] = filter
    saved.currentFilter = index
end

