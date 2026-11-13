-- Forever Floating Text: your own damage above enemy nameplates, for WoW Forever.
--
-- What the game gives addons on Forever:
--   UNIT_COMBAT(unit, action, flag, amount, schoolMask) for every unit with a token
--   (target, nameplateN...). It says what happened to the mob, but not who did it.
--   UnitDetailedThreatSituation("player", "nameplateN") - your threat on that mob. Blizzard
--   documents player-vs-nameplate threat queries as generally not secret, also in instances.
--
-- How "only my hits" works (1.15): the game's own Combat Log, with the addon's own filter, sends
-- a line for each of your (and your pet's and totems') actions in the moment it happens. Its text
-- can't be read, but its moment and color can: a hit is yours when one of your lines came with it
-- (see "Combat Log mode"). Your swings are matched by PLAYER_SWING.
-- When the Combat Log can't be used, the older ways take over: your threat on that mob rising
-- with the hit (readable solo), and your own swings, casts, DoT beats and totem attacks.
--
-- Heals are in Heals.lua.

local ADDON, ns = ...
local FFT = {}
ns.FFT = FFT
FFT.critAt = {} -- (1.31.11) plate -> when a crit of yours there was last shown

FFT.DEFAULTS = {
    enabled = true,
    font = "Fonts\\FRIZQT__.TTF", -- (1.27.2) the author's choices for new installs: Friz Quadrata,
    size = 20,                    -- thin outline, 20, crits 2x, interrupts 1.2x
    outline = "OUTLINE",
    critScale = 2,
    glancingScale = 0.75,  -- glancing swings, times the text size (Blizzard's own: 0.75); 1 = off
    markBlocked = true,    -- a partly blocked hit reads "123 (Block)", as Blizzard's does
    interruptScale = 1.2,  -- "Interrupted" size, times the text size
    duration = 1.2,
    distance = 40,
    offsetY = 10,
    style = "up",          -- "up" or "fountain"
    schoolColors = true,
    showMisses = false,
    shortNumbers = true,
    showPet = true,
    showInterrupts = true,
    showHeals = true,
    showHotTicks = true,
    showIncoming = true,   -- damage you take, at its own spot
    showIncomingHeals = true, -- heals others cast on you, at the same spot
    showHealerNames = true,   -- (1.26.0) "+420 [Name]": who healed you, from the combat text feed
    showAlerts = true,     -- the game's spell alerts ("Overpower!", procs) as text
    -- (1.23.1) alerts' own text, like the other fixed positions. Before: the nameplate font, outline
    -- and size times alertScale (1.4), so the nameplate size moved them too. An older DB is carried
    -- over at load. (1.27.2) Friz Quadrata, thin outline, as every text's default now.
    alertFont = "Fonts\\FRIZQT__.TTF",
    alertOutline = "OUTLINE",
    alertSize = 20,
    showCombatState = true, -- (1.22.1) "Entering Combat" / "Leaving Combat" at the alerts spot
    showKills = false,      -- (1.22.1) "Killing Blow!" at the alerts spot (yours and your pet's); (1.31.0) off
    showAuras = true,       -- (1.25.0) "<Ghost Wolf>" / "<Ghost Wolf> fades"; (1.31.0) at the buffs spot
    -- (1.31.0) the author, 2026-11-12, "its getting quite spammy": buffs at their own spot, their
    -- fades and your own totems' buffs off unless chosen (the totem was just placed), a hide list
    showAuraFades = false,
    showTotemBuffs = false,
    hiddenBuffs = {},      -- name -> true: /fft hide <buff>
    buffFont = "Fonts\\FRIZQT__.TTF",
    buffOutline = "OUTLINE",
    buffSize = 16,
    buffsX = -320,         -- left of the alerts (0, 240), a little lower
    buffsY = 200,
    showPeriodicPower = false, -- (1.31.0) Mana Spring and Blessing of Wisdom ticks every 2 s: off unless chosen
    layout2 = false,       -- (1.31.0) set once the new layout's defaults were put on an older DB
    showStormstrikeReset = true, -- (1.28.0) "Stormstrike!" when a dodge resets its cooldown
    showWindfury = true,    -- (1.30.1) "Windfury!" when a Windfury proc's first attack is shown as yours
    showLowWarnings = true, -- (1.28.7) "Health Low" / "Mana Low" (the game's words) at the alerts spot
    alertsX = 0,
    -- (1.30.4) 240, was 120: a mob in melee range has its plate mid-screen and its numbers rose
    -- through the alerts at 120 (the author's screenshot, 2026-11-11). Numbers start 10 above the
    -- plate and rise up to ~150 (distance 40, four stacked rows, crits); the plate's top was ~60
    -- above center there, so they reach ~210. Alerts at 240 rise to ~355, under a 768-high UI's 384.
    alertsY = 240,
    alertsSpot2 = false,   -- (1.30.4) set once the old default position (0, 120) has been moved up
    procColors2 = false,   -- (1.31.0) set once a 1.31.0 draft's saved green procs color has been moved on
    maelstromSeen = false, -- (1.31.6) set once Maelstrom Weapon was seen on you: its notice then follows the buff (Procs.lua)
    -- (1.31.0) procs kept still at their own spot until used (Procs.lua): "Stormstrike!" (above)
    -- and the game's own proc notices ("Maelstrom Ready!"). (1.31.5) At 120, below the alerts, where
    -- the author dragged them after playing (it was 350, above the alerts' rise from 240).
    showGameProcs = true,
    showReactives = true,  -- Overpower, Execute...: the game's "Reactives" notice, and while it says they can be cast
    -- (1.31.0) Notices.lua, at the alerts spot (gains with your loot)
    -- crowd control off: the game's own loss-of-control frame shows it, with its icon (the author,
    -- 2026-11-12, rooted: "now i just have duplicate")
    showCrowdControl = false, showDispels = true, showEmotes = true,
    ccOff2 = false,        -- set once an earlier 1.31.0 draft's saved "on" was turned off
    -- seconds a cooldown must last to be told when it's over; (1.31.3) 5, the author's choice after
    -- playing with it (10 before: Shocks and Stormstrike, ~6 s, weren't told)
    showCooldowns = true, cooldownMin = 5,
    cooldownMin5 = false,  -- set once a saved 10 (the old default) became 5
    showExperience = true, showHonor = true, showReputation = true, showSkills = true, showCurrency = true,
    showIcons = true,      -- an icon before procs and notices whose spell or item is known
    procFont = "Fonts\\FRIZQT__.TTF",
    procOutline = "OUTLINE",
    procSize = 22,
    procsX = 0,
    procsY = 120,
    minAmount = 0,         -- hide your damage and heal numbers below this (0 = off)
    critSound = "none",    -- a SOUNDKIT key, or "none"
    showIncomingMisses = true,
    incomingSchoolColors = false,
    incomingX = -220,      -- (1.31.5) the author's places, rounded: incoming, damage, procs, loot
    incomingY = -30,
    incomingFont = "Fonts\\FRIZQT__.TTF",
    incomingOutline = "OUTLINE",
    incomingSize = 16,
    -- (1.30.0) items and money you loot (Loot.lua), at their own spot, where the power spot was
    showLoot = true,
    showMoney = true,
    lootMinQuality = "1",  -- the lowest item quality shown: "0" Poor (gray) ... "4" Epic; quest items always
    lootX = 0,
    lootY = -180,
    lootFont = "Fonts\\FRIZQT__.TTF",
    lootOutline = "OUTLINE",
    lootSize = 16,
    -- (1.22.0) mana, rage and energy you gain (1.30.3: at the incoming spot)
    showPower = true,
    powerNames = true,     -- "+30 Mana": the name of your power bar now (UNIT_COMBAT doesn't say which)
    scope = "mine",        -- "mine", "target" or "all"
    -- (1.30.0) where your damage shows: "plates" (over the enemy's nameplate) or "spot" (a fixed
    -- scrolling area, in the nameplate text's font). Your target's damage when it has no nameplate
    -- always shows at the spot.
    damageWhere = "plates",
    damageX = 230,         -- right of your character (an older DB's heal spot place carries over)
    damageY = -30,
    hideBlizzard = true,
    matchWindow = 0.6,     -- seconds a hit and a threat rise may be apart
    useCombatLog = true,   -- tell your hits by the game's Combat Log when it can (1.15.0)
    ownClogFilter = true,  -- give the Combat Log a filter of the addon's own (1.15.1)
    fallbackV2 = true,     -- (1.21.0) without the Combat Log: only what it taught for sure (no guessing in groups)
    -- Colors, as the game's color swatches store them: "ffRRGGBB" (alpha, red, green, blue)
    colorPhysical = "ffffff00",
    colorHoly = "ffffe680",
    colorFire = "ffff8000",
    colorNature = "ff4dff4d",
    colorFrost = "ff80ffff",
    colorShadow = "ff994dff",
    colorArcane = "ffff80ff",
    colorAuto = "ffc7c7c7",
    colorMiss = "ffb3b3b3",
    colorHeal = "ff4dff4d",
    colorInterrupt = "ffff4d4d",
    colorIncoming = "ffff3333",
    colorPet = "ffffbf66",
    colorAlert = "ffffd100",
    colorPower = "ff69ccf0", -- Blizzard's own for ENERGIZE: 0.41 0.8 0.94 (CombatFeedback.lua)
    colorCombat = "ffff1a1a", -- Blizzard's own for ENTERING/LEAVING_COMBAT: 1 0.1 0.1 (CombatTextConstants.lua)
    colorKill = "ffffffff",
    colorBuff = "ff1aff1a",   -- Blizzard's own for SPELL_AURA_START / _END: 0.1 1 0.1 (CombatTextConstants.lua)
    colorDebuff = "ffff1a1a", -- and for the _HARMFUL ones: 1 0.1 0.1
    -- (1.31.0) the procs spot. Not Blizzard's green for SPELL_CAST (0.1 1 0.1): that is the buffs'
    -- green, and the author found the procs got lost among buff gains (2026-11-12). Stormstrike in
    -- the alerts' gold, as it was until 1.30.8; the game's notices a lightning blue.
    colorProc = "ff33bbff",
    colorStormstrike = "ffffd100",
    colorReactive = "ffffd100", -- Blizzard's own for SPELL_ACTIVE ("Reactives"): 1 0.82 0 (CombatTextConstants.lua)
    colorCrowdControl = "ffff4d4d", colorDispel = "ff4dd9ff", colorEmote = "ffffa64d", colorCooldown = "ffe6b3ff",
    colorExperience = "ffb380ff", colorHonor = "ffe6cc80", colorReputation = "ff8c8cff", colorSkill = "ff66b3ff",
}

-- (1.23.0) Settings the menu no longer offers: how the addon works, not a matter of taste (the author:
-- "aren't those kinda the core"). Put back to their defaults at every load, so a value changed
-- in an older version can't stay stuck where no menu reaches it.
--   useCombatLog, ownClogFilter: telling your hits by the Combat Log and its own filter. Off, the
--     fallback shows far fewer of yours in groups (NOTES.md "Fallback, measured"). "Enable" off
--     still gives the Combat Log its previous filter back (WriteOwnClogFilter).
--   fallbackV2: the fallback that shows only hits it's sure of (1.21.0); never was in the menu.
--   matchWindow: only the fallback's threat matching uses it; measured, not taste.
--   hideBlizzard: each feature already hides only its own Blizzard text while it's on, and
--     "Enable" off puts them all back, so this switch could only make numbers show twice.
FFT.LOCKED = {"useCombatLog", "ownClogFilter", "fallbackV2", "matchWindow", "hideBlizzard"}

-- schoolMask bit -> color setting
FFT.SCHOOL_KEYS = {
    [1] = "colorPhysical", [2] = "colorHoly", [4] = "colorFire", [8] = "colorNature",
    [16] = "colorFrost", [32] = "colorShadow", [64] = "colorArcane",
}
FFT.COLOR_KEYS = {"colorPhysical", "colorHoly", "colorFire", "colorNature", "colorFrost",
    "colorShadow", "colorArcane", "colorAuto", "colorMiss", "colorHeal", "colorInterrupt", "colorIncoming", "colorPet", "colorAlert", "colorPower", "colorCombat", "colorKill", "colorBuff", "colorDebuff", "colorProc", "colorStormstrike", "colorReactive",
    "colorCrowdControl", "colorDispel", "colorEmote", "colorCooldown", "colorExperience", "colorHonor", "colorReputation",
    "colorSkill"}

local WHITE = {1, 1, 1}
local db

-- A color setting as {r, g, b}; a broken value falls back to the default.
-- (1.23.3) Worked out once per saved value and kept: it was parsed from its text on every hit,
-- other players' too (9,738 times in a 300 s simulator fight with 39 others). A changed setting is
-- a different text, so it's worked out again. Callers only read the table, never change it.
local colorCache = {} -- key -> {hex = the saved text, c = {r, g, b}}
local function Color(key)
    local saved = db and db[key]
    local cached = colorCache[key]
    if cached and cached.hex == saved then return cached.c end
    local hex = saved
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x%x%x$") then hex = FFT.DEFAULTS[key] end
    local c = {tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255}
    colorCache[key] = {hex = saved, c = c}
    return c
end
FFT.Color = Color
-- An ability's hit arrives in the same frame as your cast (the author's logs); a physical hit with no cast of yours that moment is a swing.
local SAME_MOMENT = 0.05
local INTERRUPT_WINDOW = 0.5 -- your cast and the mob's interrupted cast this far apart
local lastCast = 0         -- when you last finished casting anything

-- UNIT_COMBAT actions that mean "it was attacked, but it didn't land"
local MISS_ACTIONS = {
    MISS = true, DODGE = true, PARRY = true, BLOCK = true, RESIST = true,
    IMMUNE = true, EVADE = true, ABSORB = true, DEFLECT = true, REFLECT = true,
}

local holder = CreateFrame("Frame", nil, UIParent)
holder:SetAllPoints()
holder:SetFrameStrata("HIGH")
-- (1.30.3) Texts at the fixed spots (alerts, incoming, loot, damage spot) draw in a child frame above
-- the numbers over nameplates: a mob in front of you has its plate mid-screen, and its numbers rose
-- through the alerts spot (the author's screenshot, 2026-11-11: "Windfury!" and buff names under two
-- damage numbers). One frame level for all made the order of overlapping texts undefined.
holder.top = CreateFrame("Frame", nil, holder)
holder.top:SetAllPoints()
holder.top:SetFrameLevel((holder:GetFrameLevel() or 0) + 10)
holder.top.pool = {}

local pool, active = {}, {}
local plateRecent = {}  -- key -> {t, n}: stack hits that land together
local plates = {}       -- nameplate frame -> {unit, last, rises = {}, pending = {}}

------------------------------------------------------------------------
-- Helpers. Comparing or doing math on a secret value throws, so check first.
------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Plain(v)
    if IsSecret(v) then return nil end
    return v
end

local function Print(msg)
    print("|cffff7f50Forever Floating Text|r: " .. msg)
end
FFT.Print = Print

local function PlateOf(unit)
    return C_NamePlate.GetNamePlateForUnit(unit)
end

-- (1.30.0) Your target without a nameplate (enemy nameplates off, or out of their range): the game
-- reports its hits as UNIT_COMBAT "target" too (with a plate both come, and the plate's is used).
-- It stands in for the plate as a key, a new one at every target change: a swing at the last target never takes a hit
-- on the new one (that mob has no token left to report its hit by: dropped, never misplaced).
-- Its numbers show at the damage spot (FFT.DamagePlace). Fields, not locals (Lua's 200 a file).
FFT.TARGET_KEY = {__index = {
    IsShown = function() return true end,
    GetCenter = function() return nil end, -- no place on screen (PlatePlace gives nil)
    GetTop = function() return nil end,
    GetEffectiveScale = function() return 1 end,
}}
-- the key for your current target with no plate (made when first asked), or nil if not an enemy
function FFT.TargetPseudo()
    if not Plain(UnitExists("target")) or Plain(UnitCanAttack("player", "target")) ~= true then return nil end
    FFT.targetKey = FFT.targetKey or setmetatable({fftTarget = true}, FFT.TARGET_KEY)
    return FFT.targetKey
end
-- your target's nameplate, or the key above when it has none
function FFT.TargetPlate()
    return PlateOf("target") or FFT.TargetPseudo()
end

------------------------------------------------------------------------
-- Debug recorder: /fft debug, then /fft copy
------------------------------------------------------------------------
-- The recording is also kept in the saved variable ForeverFloatingTextLog, which the game writes to
-- WTF/Account/<account>/SavedVariables/ForeverFloatingText.lua on /reload or logout (addons can't
-- write files otherwise). Recording carries on after a /reload until /fft debug turns it off.
local log, logging = {}, false
-- (1.30.6) 20,000 lines, from 5,000: solo a recording writes about 3 lines a second (27 minutes),
-- in a dungeon about 12 (2026-11-10 15:25 log: 5,351 lines in 449 s), so 5,000 held 7 minutes there
-- (1.31.14) 60,000: a crowded dungeon writes 14 lines a second (the author's 2026-11-13 20:11 log:
-- 20,273 lines in 23.7 minutes), so 20,000 lost the first 12 minutes of a 35-minute run
local SAVED_LINES = 60000
local function Log(fmt, ...)
    if not logging then return end
    local ok, line = pcall(string.format, "%.3f " .. fmt, GetTime(), ...)
    if not ok then line = ("%.3f (unprintable)"):format(GetTime()) end
    log[#log + 1] = line
    if #log > 400 then table.remove(log, 1) end
    local saved = ForeverFloatingTextLog and ForeverFloatingTextLog.lines
    if saved then
        saved[#saved + 1] = line
        -- (1.17.0) trimmed 500 at a time: removing the first of the kept lines moved all the others
        -- on every line logged
        if #saved > SAVED_LINES + 500 then
            local keep = {}
            for i = #saved - SAVED_LINES + 1, #saved do keep[#keep + 1] = saved[i] end
            ForeverFloatingTextLog.lines = keep
        end
    end
end

-- (1.31.13) A probe, log only, counted anew in each recording (FFT.Probe below; a field, not a
-- local: the file is at Lua's limit of 200 locals)
FFT.probe = {lines = 0}
local function StartSavedLog(reason)
    FFT.probe.lines = 0
    ForeverFloatingTextLog = ForeverFloatingTextLog or {}
    ForeverFloatingTextLog.lines = ForeverFloatingTextLog.lines or {}
    ForeverFloatingTextLog.recording = true
    local lines = ForeverFloatingTextLog.lines
    local ok, totemPlates = pcall(C_CVar.GetCVar, "nameplateShowFriendlyPlayerTotems")
    -- (1.30.7) raid or not too: some rules are for a party but not a raid (ExtraAttackLine)
    lines[#lines + 1] = ("=== %s %s, in group: %s, raid: %s, totem nameplates: %s ==="):format(reason,
        date("%Y-%m-%d %H:%M:%S"), tostring(IsInGroup()), tostring(IsInRaid()), ok and tostring(totemPlates) or "?")
end
local function S(v) -- printable form of a maybe-secret value
    if IsSecret(v) then return "<secret>" end
    return tostring(v)
end
-- (1.28.14) which hit a "show" / "drop" log line is about (its nameplate and moment): a swing's is
-- decided up to a second later, and several hits are decided at once, in another order
function FFT.Which(hit) -- (a field, not a local: the file is at Lua's limit of 200 locals)
    return hit.unit and (" [%s %.3f]"):format(hit.unit, hit.at) or ""
end

-- times: seconds after a cast. Finds the period P that puts the most of them on whole
-- beats (k*P, k >= 1). Needs at least 2 ticks on the beat, and 60% of what was seen.
-- Used for your HoTs (Heals.lua) and DoTs (below).
function ns.FindPeriod(times, minPeriod, tolerance)
    if #times < 2 then return nil end
    local candidates = {times[1]}
    for i = 2, #times do candidates[#candidates + 1] = times[i] - times[i - 1] end
    local best
    for _, p in ipairs(candidates) do
        if p >= minPeriod then
            local fits, maxK, sumP, ks = 0, 0, 0, {}
            for _, d in ipairs(times) do
                local k = math.floor(d / p + 0.5)
                if k >= 1 and math.abs(d - k * p) <= tolerance and not ks[k] then
                    ks[k] = true
                    fits, sumP = fits + 1, sumP + d / k
                    if k > maxK then maxK = k end
                end
            end
            -- a real HoT/DoT ticks one period after its cast: without that first tick it's
            -- more likely some other stream of hits that happens to line up
            if fits >= 2 and fits >= 0.6 * #times and ks[1] and (not best or fits > best.fits) then
                best = {fits = fits, period = sumP / fits, ticks = maxK}
            end
        end
    end
    return best
end

-- shared with Heals.lua
ns.IsSecret, ns.Plain, ns.Print, ns.PlateOf, ns.Log, ns.S = IsSecret, Plain, Print, PlateOf, Log, S
function ns.IsLogging() return logging end -- (1.24.1) probes that only log skip their work otherwise

------------------------------------------------------------------------
-- Threat: how much of it is yours (and your pet's) on a mob
------------------------------------------------------------------------
-- Returns the threat (nil if hidden), and true when there's no value at all: you're not on
-- the mob's threat list (yet). Seen in game in a group: no value until you're on the list,
-- then hidden, so a rise is never seen there; no value means unknown, not "not yours".
local function RawThreat(who, unit)
    if not UnitDetailedThreatSituation then return nil end
    local _, _, _, _, raw = UnitDetailedThreatSituation(who, unit)
    if IsSecret(raw) then return nil end
    if raw == nil then return 0, true end
    return raw
end

-- Returns my + pet threat on the mob, or nil if it can't be read
local function MyThreat(unit)
    local mine = RawThreat("player", unit)
    if not mine then return nil end
    if db.showPet and Plain(UnitExists("pet")) then
        local pet = RawThreat("pet", unit)
        if pet then mine = mine + pet end
    end
    return mine
end

local function PetThreat(unit)
    if not (db.showPet and Plain(UnitExists("pet"))) then return nil end
    return RawThreat("pet", unit)
end

local function PlateState(plate, unit)
    local st = plates[plate]
    if not st or st.unit ~= unit then
        st = {unit = unit, last = RawThreat("player", unit) or 0, lastPet = PetThreat(unit) or 0,
            rises = {}, pending = {}}
        plates[plate] = st
    end
    return st
end

-- Reads the threat now. Returns whether yours or your pet's rose since the last reading,
-- and whose: "player" (yours, or both) or "pet". Yours and your pet's are read separately,
-- so a hit vouched only by your pet's threat is your pet's.
local function ThreatRose(st)
    local cur, noEntry = RawThreat("player", st.unit)
    st.noEntry = noEntry
    if cur == nil then
        if not st.unreadable then Log("  %s threat hidden", st.unit) end
        st.unreadable = true
        return false
    end
    st.unreadable = false
    local pet = PetThreat(st.unit)
    local mine = cur > st.last
    local pets = pet ~= nil and pet > st.lastPet
    if mine or pets then
        Log("  %s threat: you %s -> %s (+%s), pet %s -> %s", st.unit, tostring(st.last), tostring(cur),
            tostring(cur - st.last), tostring(st.lastPet), tostring(pet))
    end
    st.last = cur
    if pet ~= nil then st.lastPet = pet end
    if mine then return true, "player" end
    if pets then return true, "pet" end
    return false
end

------------------------------------------------------------------------
-- Text display
------------------------------------------------------------------------
-- always: use the school colors even when "Use these colors for damage" is off (damage taken)
local function SchoolColor(mask, always)
    if not (db.schoolColors or always) then return WHITE end
    mask = Plain(mask)
    if not mask then return WHITE end
    if FFT.SCHOOL_KEYS[mask] then return Color(FFT.SCHOOL_KEYS[mask]) end
    local r, g, b, n = 0, 0, 0, 0 -- mixed schools: blend the colors
    for bitValue, key in pairs(FFT.SCHOOL_KEYS) do
        if bit.band(mask, bitValue) ~= 0 then
            local c = Color(key)
            r, g, b, n = r + c[1], g + c[2], b + c[3], n + 1
        end
    end
    if n == 0 then return WHITE end
    return {r / n, g / n, b / n}
end

ns.SchoolColor = SchoolColor

local function FormatAmount(amount)
    if IsSecret(amount) then return amount end -- display only, the game draws it
    if db.shortNumbers and AbbreviateNumbers and amount >= 10000 then
        return AbbreviateNumbers(amount)
    end
    return amount
end
ns.FormatAmount = FormatAmount

-- onTop: a text at a fixed spot (holder.top, drawn above the nameplate numbers)
local function GetText(onTop)
    local t = table.remove(onTop and holder.top.pool or pool)
    if not t then
        t = (onTop and holder.top or holder):CreateFontString(nil, "OVERLAY")
        t.onTop = onTop
    end
    return t
end

local function Release(t)
    t:Hide()
    t:ClearAllPoints()
    t.plate, t.anchorX, t.anchorY = nil, nil, nil
    table.insert(t.onTop and holder.top.pool or pool, t)
end

-- plate: a nameplate frame, or nil for mid-screen (test mode)
-- opts (optional): fmt + args for SetFormattedText (takes hidden values too),
--   anchorX/anchorY for a fixed spot on screen, key to stack texts by, scale for the size,
--   font/outline/size to use instead of the main text settings
function FFT:Show(plate, text, color, crit, opts)
    local t = GetText(plate == nil)
    local font = opts and opts.font or db.font
    local outline = opts and opts.outline or db.outline
    local base = opts and opts.size or db.size
    local size = base * (crit and db.critScale or 1) * (opts and opts.scale or 1)
    if not t:SetFont(font, size, outline) then
        t:SetFont(STANDARD_TEXT_FONT, size, outline)
    end
    t:SetTextColor(color[1], color[2], color[3])
    if opts and opts.fmt then
        t:SetFormattedText(opts.fmt, unpack(opts.args))
    else
        t:SetText(text)
    end
    t:SetTextScale(1)
    t:SetAlpha(1)
    t.uses = (t.uses or 0) + 1 -- (1.31.9) Spots.lua SpotText: still the same text? (GetText can be hidden)
    if opts and opts.anchorX then t.anchorX, t.anchorY = opts.anchorX, opts.anchorY end

    local now = GetTime()
    local key = plate or (opts and opts.key) or holder
    local r = plateRecent[key]
    if r and now - r.t < 0.25 then r.n = r.n + 1 else r = {n = 0}; plateRecent[key] = r end
    r.t = now

    t.plate = plate
    t.age = 0
    t.crit = crit
    t.popping = crit and true or false -- its size still to be put back after the crit pop
    t.x0 = math.random(-15, 15)
    t.y0 = (plate and db.offsetY or 0) + (r.n % 4) * base * 0.9
    t.dir = (math.random(0, 1) == 0) and -1 or 1
    t:Show()
    table.insert(active, t)
    self:Position(t, 0)
    FFT.StartAnimating()
    return t -- (1.31.0) Spots.lua FFT:SpotText merges a repeat into it
end

function FFT:Position(t, p)
    local x, y = t.x0, t.y0
    if db.style == "fountain" then
        x = x + t.dir * p * db.distance * 0.8
        y = y + math.sin(p * math.pi) * db.distance * 0.6 + p * db.distance * 0.2
    else
        y = y + p * db.distance
    end
    if t.plate then
        t:SetPoint("BOTTOM", t.plate, "TOP", x, y)
    elseif t.anchorX then
        t:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", t.anchorX + x, t.anchorY + y)
    else
        t:SetPoint("BOTTOM", UIParent, "CENTER", x, y + 100)
    end
end

-- (1.23.3) Runs only while a text is up, and sets size and alpha only while they change: the crit
-- pop's first 0.15 s (then size 1 once), and the fade over the last 30%. Show puts both at 1.
-- Before, every text set both every frame, and the script ran every frame with nothing up.
local animating = false
local function Animate(_, elapsed)
    local duration = db and db.duration or 1.2
    for i = #active, 1, -1 do
        local t = active[i]
        t.age = t.age + elapsed
        local p = t.age / duration
        if p >= 1 then
            table.remove(active, i)
            Release(t)
        else
            FFT:Position(t, p)
            if t.popping then
                if t.age < 0.15 then
                    t:SetTextScale(1 + 0.6 * (1 - t.age / 0.15)) -- crit pop
                else
                    t:SetTextScale(1)
                    t.popping = false
                end
            end
            if p >= 0.7 then t:SetAlpha(1 - (p - 0.7) / 0.3) end
        end
    end
    if #active == 0 then
        holder:SetScript("OnUpdate", nil)
        animating = false
    end
end

function FFT.StartAnimating()
    if animating then return end
    animating = true
    holder:SetScript("OnUpdate", Animate)
end

-- A plate going away (mob died, out of range): keep its texts where they were
-- A nameplate's place on screen (center x, top, scale to UIParent), or nil when it can't be used.
-- GetCenter/GetTop are SecretWhenAnchoringSecret (SimpleScriptRegionAPIDocumentation, Forever
-- 1.60.1), and in a dungeon nameplates' were: 1.15.4 did math on them there, which throws, and
-- every hit decided by the Combat Log was lost (dungeon log 2026-11-06 19:50).
-- (1.23.3) The reads are one fixed function and the checks plain ifs: before, each call made a new
-- function and a table, and it runs for every hit on a nameplate (others' too).
local function ReadPlace(plate)
    local x = plate:GetCenter()
    return x, plate:GetTop(), plate:GetEffectiveScale(), UIParent:GetEffectiveScale()
end

local function PlatePlace(plate)
    local ok, cx, top, scale, uiScale = pcall(ReadPlace, plate)
    if not ok then return nil end
    if IsSecret(cx) or IsSecret(top) or IsSecret(scale) or IsSecret(uiScale) then return nil end
    if cx == nil or top == nil or scale == nil or uiScale == nil then return nil end
    return cx, top, scale / uiScale
end

local function DetachPlate(plate)
    local cx, top, s = PlatePlace(plate)
    if not cx then return end -- (positions secret: the texts stay with the plate)
    for _, t in ipairs(active) do
        if t.plate == plate then
            t.plate = nil
            t.anchorX, t.anchorY = cx * s, top * s
            t:ClearAllPoints()
        end
    end
end

------------------------------------------------------------------------
-- Matching hits with threat rises
------------------------------------------------------------------------
-- Hide numbers below (0 = off); only a readable amount can be compared
function FFT:TooSmall(amount)
    local n = Plain(amount)
    return n ~= nil and db.minAmount > 0 and n < db.minAmount
end

local lastCritSound = 0
function FFT:CritSound()
    local kit = db.critSound ~= "none" and SOUNDKIT and SOUNDKIT[db.critSound]
    if not kit or GetTime() - lastCritSound < 0.3 then return end
    lastCritSound = GetTime()
    C_Sound.PlaySound(kit)
end

-- (1.18.0) Glancing and partly blocked hits look the way Blizzard's own floating text draws them
-- (Blizzard_FrameXML/Mainline/CombatFeedback.lua): a glancing hit at 0.75 of the size, a blocked
-- one as COMBAT_TEXT_BLOCK_REDUCED ("%s (Block)", GlobalStrings enUS, Ketho's forever branch).
-- UNIT_COMBAT's flag stays readable in groups and dungeons (2026-11-06 logs: 70 GLANCING,
-- 10 BLOCK_REDUCED, never secret); the game doesn't say how much was blocked.
local function HitOpts(hit, opts)
    local gs = db.glancingScale or 1
    if hit.glancing and gs ~= 1 then
        opts = opts or {}
        opts.scale = gs
    end
    if hit.blocked and db.markBlocked and COMBAT_TEXT_BLOCK_REDUCED then
        opts = opts or {}
        opts.fmt, opts.args = COMBAT_TEXT_BLOCK_REDUCED, {hit.text} -- takes a hidden amount too
    end
    return opts
end

-- (1.30.0) Where a damage number goes: over its nameplate, or at the damage spot (Spots.lua) when
-- that's chosen (db.damageWhere) or it has no plate (your target's key, FFT.TargetPseudo). Returns
-- the plate for FFT:Show (nil at the spot) and the options.
function FFT.ToSpot(plate) return db.damageWhere == "spot" or (plate ~= nil and plate.fftTarget == true) end
function FFT.DamagePlace(plate, opts)
    if not FFT.ToSpot(plate) then return plate, opts end
    opts = opts or {}
    opts.anchorX, opts.anchorY = FFT:SpotAnchor("damage")
    opts.key = "damage"
    return nil, opts
end

-- who: "pet" when only your pet's threat vouched for it
local function ShowHit(plate, hit, why, who)
    Log("  show %s (%s%s)%s", S(hit.text), why, who == "pet" and ", pet" or "", FFT.Which(hit))
    if hit.crit then FFT.critAt[plate] = GetTime() end -- (1.31.11) Flurry may start (SWING_QUICK.ExtraFit)
    local st = plates[plate]
    if st then st.lastMine = GetTime() end
    if who ~= "pet" and why:find("^threat") and FFT.LearnSchool then FFT.LearnSchool(plate, hit, GetTime()) end
    if FFT:TooSmall(hit.amount) then return end
    local color = hit.color
    if who == "pet" and db.schoolColors and not hit.miss then color = Color("colorPet") end
    local at, opts = FFT.DamagePlace(plate, HitOpts(hit))
    if not at or plate:IsShown() then
        FFT:Show(at, hit.text, color, hit.crit, opts)
        if hit.crit then FFT:CritSound() end
    else
        Log("  (not drawn: its nameplate isn't showing)")
    end
end

local function Prune(list, now)
    local w = db.matchWindow
    while list[1] and now - list[1].t > w do
        local old = table.remove(list, 1)
        if old.hit then Log("  drop %s (no threat rise)", S(old.hit.text)) end
    end
end

-- A threat rise arrived: it vouches the oldest waiting hit, and any hit from that same moment
local function OnRise(plate, st, now, who)
    Prune(st.pending, now)
    local first = st.pending[1]
    if first then
        local t0 = first.t
        while st.pending[1] and st.pending[1].t == t0 do
            ShowHit(plate, table.remove(st.pending, 1).hit, "threat after hit", who)
        end
    else
        st.rises[#st.rises + 1] = {t = now, who = who}
    end
end

-- Threat went hidden while hits waited for it to rise (seen in game: readable at the hit,
-- hidden a moment later). Then they get the same check as any hit while threat is hidden.
local function HandOver(plate, st)
    for _, p in ipairs(st.pending) do
        Log("  %s: threat went hidden, checking your actions", S(p.hit.text))
        FFT.CheckOwnActions(plate, p.hit, p.t, p.isTarget)
    end
    wipe(st.pending)
end

local function CheckLater(plate, st)
    C_Timer.After(db.matchWindow + 0.05, function()
        if plates[plate] ~= st then return end
        local rose, who = ThreatRose(st)
        if rose then OnRise(plate, st, GetTime(), who) end
        -- hidden, or still no value after your hit: threat can't tell, your actions can
        if st.unreadable or st.noEntry then return HandOver(plate, st) end
        Prune(st.pending, GetTime())
    end)
end

-- returns true if shown/queued, false if this hit can't be matched by threat
local function MatchByThreat(plate, st, hit, now, isTarget)
    local rose, who = ThreatRose(st)
    if rose then
        st.rises[#st.rises + 1] = {t = now, who = who}
    end
    if st.unreadable then return false end

    Prune(st.rises, now)
    local rise = st.rises[1]
    if rise then
        -- a rise from just before vouches this hit, and others from this same moment
        if rise.usedAt and rise.usedAt ~= now then
            table.remove(st.rises, 1)
            rise = st.rises[1]
        end
    end
    if rise then
        rise.usedAt = now
        ShowHit(plate, hit, "threat before hit", rise.who)
        return true
    end
    st.pending[#st.pending + 1] = {t = now, hit = hit, isTarget = isTarget}
    CheckLater(plate, st)
    return true
end


------------------------------------------------------------------------
-- Your own actions, for when threat is hidden (seen in a group: every amount and your
-- threat were secret) and for misses, which raise no threat anyway:
--   PLAYER_SWING (C_SwingTimer docs: "Auto attacks only ever apply to the current target")
--     - each swing accounts for one physical hit or miss on your target.
--   UNIT_SPELLCAST_SUCCEEDED for you - a hit in the same moment as your cast is the cast's
--     (instant abilities; the author's logs).
--   A spell that flies (Lightning Bolt) lands later: the next hit on the mob you cast at,
--     of the school that spell was seen to have, is its. Schools are learned from your
--     own hits while threat is readable.
------------------------------------------------------------------------
-- Your swing's hit arrives about 0.46s after PLAYER_SWING (0.43-0.47s in every confirmed case
-- seen in game, 1.60.1), never before. Hits sooner (0.17-0.38s) were a pet's.
local SWING_MIN, SWING_MAX = 0.40, 0.55
-- (1.28.0) from 0.39: Flurry's 0.415 s hits can show as 0.400 at 60 frames a second (the simulator
-- floored 9 of them to 0.3999 and dropped them); pets' hits were 0.38 s or sooner
SWING_MIN = 0.39
-- (1.23.2) In a form the hit comes sooner. Ghost Wolf (GetShapeshiftFormID() 16 =
-- SHAMAN_GHOST_WOLF_FORM, Blizzard_FrameXMLBase/Constants.lua): 0.331-0.396 s after PLAYER_SWING
-- in all 7 swings of the author's 2026-11-08 logs (08:31 and 08:33, solo: 0.331 x3, 0.396 x4), so every
-- one fell under SWING_MIN and was dropped. The delays come in steps of ~0.065 s (0.331, 0.396;
-- out of form 0.461, now and then 0.526). Other forms (a druid's) aren't measured: they keep the
-- normal timing until a log shows theirs.
-- (1.26.3) The weapon's swing time doesn't set the delay. 1.25.1 scaled these windows by
-- swingDuration / 3.30 (Flurry's 2.95 s swings hit after 0.415 s, 08:33 log), but with the author's +30%
-- attack speed buff (2026-11-09 09:59 log) "weapon 2.54s" swings still hit after 0.461 s (every one
-- of 20), and the 0.31-0.42 window dropped them all. Only Flurry shortens it: 0.415-0.416 s at 2.95 s
-- and at 2.27 s (buff and Flurry). The normal window takes both. Ghost Wolf with Flurry: 0.292 s
-- (08:33 log 555424.777), so its window starts at 0.28.
local SWING_NORMAL = {min = SWING_MIN, max = SWING_MAX, expected = 0.46}
local SWING_BY_FORM = {
    [16] = {min = 0.28, max = 0.43, expected = 0.36}, -- Ghost Wolf
}
-- (1.28.11) Events reach addons once a frame, so a measured delay is off by up to a frame. The
-- windows here were measured at a high frame rate and checked in the simulator at 60. At 30 frames
-- a second (the author's 2026-11-10 12:55 log) delays came in steps of 0.033 s: swings 0.433 / 0.467,
-- a Windfury hit exactly 0.200 s after its lines (the slot's edge) and its swing 0.900 s (0.89-1.01).
-- So below 60 frames a second each swing and Windfury window is widened at both ends by how much
-- longer a frame is than 1/60 s (0.017 s at 30, 0.033 s at 20; never more than 0.035).
-- GetFramerate: ClientDocumentation.lua, returns a number.
local function FrameSlack()
    if not GetFramerate then return 0 end
    local fps = Plain(GetFramerate())
    if type(fps) ~= "number" or fps <= 0 then return 0 end
    return math.max(0, math.min(1 / fps - 1 / 60, 0.035))
end

-- (1.28.14) Which swings hit sooner (Flurry) is learned by the weapon's swing time. The author's
-- 2026-11-10 15:25 dungeon log, each swing's own hit known from the game's combat log file: all 23
-- plain swings at "weapon 2.95s" hit after 0.408-0.417 s and all 22 at 3.30 s (and 3.68, 4.12:
-- slowed) after 0.459-0.468; with a cast 0.884-0.890 against 0.988-1.000. The swing time alone
-- can't say it (a +30% speed buff: 2.54 s and still 0.461, see above), so each swing time seen is
-- counted: a plain swing with one hit in its window, no cast, no proc, puts its delay on one side.
-- From 3 such swings with 4 of 5 on one side, a swing at that time expects that delay, and its
-- cast and Windfury windows are the narrow ones around it. In that log a Flurry swing's Dodge at
-- 0.416 s lost to a stranger's at 0.498 (17982.947: 0.46 was expected, both "as close"), and a
-- hit at 0.416 to one at 0.487 (18025.887). Kept for the session only.
local SWING_QUICK = {own = 0.415, extra = 0.472, proc = 0.91, split = 0.438}
SWING_QUICK.delays = {} -- "2.95" -> {quick = n, normal = n} (fields, not locals: Lua allows 200 a file)
function SWING_QUICK.Key(speed)
    speed = Plain(speed)
    return type(speed) == "number" and ("%.2f"):format(speed) or nil
end
-- true: hits sooner, false: at the usual delay, nil: not known yet
function SWING_QUICK.Is(key)
    local c = key and SWING_QUICK.delays[key]
    if not c then return nil end
    local n = c.quick + c.normal
    if n < 3 then return nil end
    if c.quick >= 0.8 * n then return true end
    if c.normal >= 0.8 * n then return false end
    return nil
end
function SWING_QUICK.Learn(sw, d)
    if not sw.speed or d < SWING_MIN or d > 0.49 then return end
    local c = SWING_QUICK.delays[sw.speed] or {quick = 0, normal = 0}
    SWING_QUICK.delays[sw.speed] = c
    local was = SWING_QUICK.Is(sw.speed)
    local side = d < SWING_QUICK.split and "quick" or "normal"
    c[side] = c[side] + 1
    if c.quick + c.normal > 40 then c.quick, c.normal = c.quick / 2, c.normal / 2 end -- newer swings count more
    local is = SWING_QUICK.Is(sw.speed)
    if is ~= was and is ~= nil then
        Log("  swings at weapon %ss hit after %s s (learned from %d)", sw.speed, is and "0.415" or "0.461", c.quick + c.normal)
    end
end

-- (1.29.0) A weapon's swings may hit after more than one delay. The author's 2026-11-10 18:53 log
-- (solo, a new weapon, "weapon 3.10s", the game's combat log file beside it, no one else on those
-- mobs): plain swings hit after 0.360-0.373 s (20), 0.464-0.468 (16) or 0.728-0.734 (12), in no
-- order and whatever came before; with the old weapon (3.30 s) always 0.461. Unarmed while
-- disarmed ("weapon 2.00s") 0.360-0.366. The two outer ones were outside the swing window, and 47
-- of the 50 hits dropped were these swings or the Windfury hits that follow the same delays.
-- So the delays are learned per swing time, outside a group only, from a plain swing whose only
-- physical hit on its mob came 0.15-0.80 s after it (no cast, no proc, the swing's own line
-- agreeing hit or miss: Sight), and from a plain swing taken in its window (ResolveSwing). One seen
-- 3 times is a delay of that weapon (`ForeverFloatingTextDB.swingAnims`, kept across sessions;
-- /fft forget clears it): a hit within 0.025 s of it is the swing's, in a group too.
SWING_QUICK.ANIM_TOL = 0.025
SWING_QUICK.ANIM_SEEN = 3
-- With a learned delay of 0.6 s or more ("long"), from the same log: a cast before its hit moved
-- it to 1.494 / 1.496 s (30209.011, Stormstrike in the swing's frame; 30282.250, Stormstrike
-- +0.570), where the others' moved to 0.996-0.998 as before; a Windfury proc's second attack came
-- 0.755 s after the lines, not 0.50 (30473.604, 30476.705), and the swing's own hit 0.755 s plus
-- that delay after them (1.477-1.482: 30352.727, 30473.604, 30476.705); otherwise 0.50 plus the
-- swing's delay (0.964 x3, 0.862 at 30458.068). The first attack came at half of a learned delay:
-- 0.179-0.182 (half of 0.366), 0.229-0.231, 0.361-0.366 (half of 0.732).
-- (1.29.1) The cast-delayed moment scales with the long delay as the delays do with Flurry: the
-- author's 2026-11-10 19:58 log (solo, the game's file; no one else on those mobs), Flurry swings
-- ("weapon 2.77s", delays learned 0.320 / 0.414 / 0.651, 0.89 of the plain ones) with Stormstrike
-- +0.596 (34136.259) and Earth Shock +0.481 (34151.090) hit 1.334 and 1.338 s after: 0.651 x
-- 1.495 / 0.732 = 1.330.
SWING_QUICK.CAST_LONG = 1.495
SWING_QUICK.CAST_LONG_RATIO = 1.495 / 0.732
SWING_QUICK.SLOT_LONG = 0.755
SWING_QUICK.LINES_LATE = 0.08 -- (1.31.13) a proc's lines this long after its swing may time its hits from the swing (ExtraAttackLine)
-- (1.29.1) Windfury's attacks don't speed up with Flurry, the swing's own hit does: with the old
-- weapon 0.23 / 0.50 with or without Flurry, the swing 0.96 or 0.91 (NOTES.md); in the 19:58 log a
-- Stormstrike's proc with Flurry up (34136.853) hit at 0.365 and 0.502, half of the plain 0.732 and
-- the usual second slot, while the last swing's (Flurry's) delays were 0.320 / 0.414 / 0.651. So
-- the slots go by the slowest delays learned for a swing time seen in the last minute (Flurry's are
-- quicker; a +30% speed buff left the delay as it was): SWING_QUICK.BaseAnims.
SWING_QUICK.recent = {} -- swing time -> when last seen
function SWING_QUICK.BaseAnims()
    local now, best = GetTime(), nil
    for key, t in pairs(SWING_QUICK.recent) do
        local anims = now - t <= 60 and SWING_QUICK.Anims(key)
        if anims and (not best or anims[#anims] > best[#best]) then best = anims end
    end
    return best
end
-- learned delays for this swing time (sorted), or nil
function SWING_QUICK.Anims(key)
    local list = key and db and db.swingAnims and db.swingAnims[key]
    if not list then return nil end
    local out = {}
    for _, c in ipairs(list) do if c.n >= SWING_QUICK.ANIM_SEEN then out[#out + 1] = c.d end end
    table.sort(out)
    return #out > 0 and out or nil
end
-- (1.31.11) The delays for a swing time not learned yet, from those learned at another swing time
-- seen in the last minute (the same weapon, faster or slower), scaled by the swing times: Flurry and
-- a 15% haste buff scale the delay as they scale the swing (the author's 2026-11-13 08:08 log, with
-- the game's file: 3.60 s 0.464, hasted 3.13 s 0.403, Flurry 2.41 s 0.309, 2.77 s 0.355: each
-- within 0.002 of 0.464 x its swing time / 3.60; the 2026-11-09 Flurry, 3.30 -> 2.95 s, 0.461 ->
-- 0.415). Not every speed-up does (a +30% buff in the 2026-11-09 09:59 log, 2.54 s, kept 0.461),
-- and that one stays in the plain window. Before, each new swing time waited for its own 3 swings
-- (a Flurry swing at 0.309 dropped until then). Learned ones always win.
function SWING_QUICK.DelaysFor(key)
    local own = SWING_QUICK.Anims(key)
    local s = tonumber(key)
    if own or not s then return own end
    local now, out = GetTime(), {}
    for k, t in pairs(SWING_QUICK.recent) do
        local ks = tonumber(k)
        if k ~= key and ks and now - t <= 60 and s / ks >= 0.6 and s / ks <= 1.6 then
            for _, d in ipairs(SWING_QUICK.Anims(k) or {}) do
                local scaled, dup = d * s / ks, false
                for _, o in ipairs(out) do if math.abs(o - scaled) <= 0.01 then dup = true end end
                if not dup then out[#out + 1] = scaled end
            end
        end
    end
    table.sort(out)
    return #out > 0 and out or nil
end
-- (1.31.13) A swing time whose learned delays all lie outside the plain window goes by them alone.
-- The author's 2026-11-13 10:28 dungeon log (party of five, the game's combat log file beside it;
-- weapon 3.60 s with a delay of 0.464, its Flurry swings 2.77 s with 0.355, learned solo). The
-- 2.77 s swings kept the plain window (0.39-0.55, expected 0.46) and the cast and proc windows
-- measured around 0.46 beside their own delay, and so:
--   - with a cast before its hit a 2.77 s swing's number came 0.763-0.769 s after it, 12 of 12
--     (0.355 x 2.15, the factor SWING_QUICK.ExtraFit uses; the casts 0.00-0.35 s after the swing,
--     those at 0.40-0.78 s left it at 0.355). The late window looked at 0.862-1.060: all 12 dropped,
--     and 8 strangers' hits shown for them (182625.646: its own at +0.763, one at +0.914 shown);
--   - a stranger's hit at +0.46 was "as close" as its own at +0.355, and both were dropped
--     (181899.720: +0.353 and +0.471; 181908.043: +0.357 and +0.469);
--   - after an enchant proc the window around the lines + 0.96 stayed open beside 0.50 + 0.355
--     (183545.919: a hit at the lines + 0.959 shown, not the author's).
-- So for such a swing time: the plain hit only at a learned delay, a cast-delayed one at the delay +
-- CastAdd (0.763), after a proc at 0.50 + the delay, and "expected" is a learned delay. Only once
-- the delays are well known: 10 sightings or more, and less than 2 of any delay not yet learned
-- (a weapon with several delays learns them one by one: in the 2026-11-10 18:53 log, replayed with
-- no such guard, 0.366 was learned first and two swings at 0.46 were lost). A swing time with a
-- learned delay inside the plain window is as before (3.60 s: 0.464), and so is one whose delays
-- are only scaled from another's (DelaysFor: the +30% speed buff of 2026-11-09 kept 0.461).
-- Replayed against the game's file: 661 -> 684 of the author's 775 hits shown, 59 -> 51 of others';
-- the 2026-11-11 dungeon log the same decisions.
function SWING_QUICK.Only(sw)
    local list = sw.speed and db and db.swingAnims and db.swingAnims[sw.speed]
    local own = list and SWING_QUICK.Anims(sw.speed)
    if not own then return end
    local seen, pending = 0, 0
    for _, c in ipairs(list) do
        if c.n >= SWING_QUICK.ANIM_SEEN then
            if c.d >= SWING_MIN and c.d <= SWING_MAX then return end
            seen = seen + c.n
        else
            pending = pending + c.n
        end
    end
    if seen < 10 or pending >= 2 then return end
    sw.only = true
    sw.expected, sw.own = own[1], own[1]
    sw.lateCenters = {}
    for _, a in ipairs(own) do sw.lateCenters[#sw.lateCenters + 1] = a + SWING_QUICK.CastAdd(a) end
end
function SWING_QUICK.Long(anims)
    return anims and anims[#anims] >= 0.6 and anims[#anims] or nil
end
-- the learned delay nearest d, if one is within tol
function SWING_QUICK.Near(anims, d, tol)
    local best
    for _, a in ipairs(anims or {}) do
        if math.abs(d - a) <= tol and (not best or math.abs(d - a) < math.abs(d - best)) then best = a end
    end
    return best
end
function SWING_QUICK.AddAnim(key, d, why)
    if not key or not db or IsInGroup() then return end
    db.swingAnims = db.swingAnims or {}
    local list = db.swingAnims[key] or {}
    db.swingAnims[key] = list
    local best
    for _, c in ipairs(list) do
        if math.abs(c.d - d) <= 0.02 and (not best or math.abs(c.d - d) < math.abs(best.d - d)) then best = c end
    end
    if not best then best = {d = d, n = 0}; list[#list + 1] = best end
    local was = best.n >= SWING_QUICK.ANIM_SEEN
    best.d = (best.d * best.n + d) / (best.n + 1)
    best.n = best.n + 1
    local total = 0
    for _, c in ipairs(list) do total = total + c.n end
    if total > 60 then -- newer swings count more
        for i = #list, 1, -1 do
            list[i].n = list[i].n / 2
            if list[i].n < 0.5 then table.remove(list, i) end
        end
    end
    if not was and best.n >= SWING_QUICK.ANIM_SEEN then
        Log("  swings at weapon %ss hit after %.3f s too (seen %d times, last as %s)", key, best.d, best.n, why)
    end
end

local function CurrentForm()
    if not GetShapeshiftFormID then return nil end
    local ok, form = pcall(GetShapeshiftFormID)
    form = ok and Plain(form) or nil
    return type(form) == "number" and form or nil
end
local FLIGHT_WINDOW = 2.5                    -- a spell this long in the air at most
local swings = {}                            -- {t, used}
local ownCasts = {}                          -- {t, name, plate, landed}
local anyCasts = {}                          -- (1.26.3) {t, name}: every cast of yours, harmful or not
local dots = {}                              -- plate -> spell name -> {t0, used, times, bySchool}
local DOT_TOLERANCE = 0.3                    -- a tick may be this far off its beat
local DOT_WATCH = 40                         -- seconds a cast's ticks are looked for

-- (1.30.0) Your target's nameplate came or went: what you
-- did at it under one key carries on under the other, so a swing made while it had no plate takes
-- its hit on the plate, and the killing blow reported after the plate went (a killed
-- target's plate can go before the blow is reported) still finds its swing.
function FFT.Rekey(from, to)
    if not from or not to or from == to then return end
    for _, sw in ipairs(swings) do if sw.plate == from then sw.plate = to end end
    for _, c in ipairs(ownCasts) do if c.plate == from then c.plate = to end end
    if dots[from] and not dots[to] then dots[to], dots[from] = dots[from], nil end
end
function FFT.IsTarget(unit)
    local ok, same = pcall(UnitIsUnit, unit, "target")
    return ok and Plain(same) == true
end

-- (1.30.5) Windfury Totem's extra swing. Since the 2026-11-11 patch the totem works beside the weapon
-- enchant; its proc on you is SPELL_EXTRA_ATTACKS 8516 "Windfury Totem" and an ordinary extra swing
-- (the game's file, 12:46 log), which comes as a second PLAYER_SWING with a plain swing line and the
-- feed's EXTRA_ATTACKS notice, 0.10-0.12 s after the first swing or in its frame. Of the pair's two
-- hits one comes at the plain delay and one ~1.46 s after the first swing: 1.461, 1.463, 1.408
-- (12:53 log 17851.842, 17893.051, 17943.139), with Flurry 1.303 (12:46 log 17417.305), 0.89 of it
-- as a Flurry swing's delays are; a Stormstrike 1.447 s after moved it to 1.988 (17989.289, the
-- 0.534 a cast adds). 1.30.4 dropped every one. Which of the pair is the first swing's isn't known
-- (no crit told them apart); both are yours, so the extra swing takes the late one.
-- Main hand only (a dual wielder's off-hand swing isn't an extra one), shamans only (timed on one;
-- other extra attacks, a trinket's, aren't measured). On a killing swing the extra swing never
-- comes, or its hit isn't taken.
-- (1.30.6) Never timed as a plain swing (0.39-0.55 s after itself): none of the pair's hits ever
-- came there, so with the swings 0.10 s apart only a stranger's hit could, and it was shown as
-- yours (sim/tests.lua).
-- (1.30.7) In a group as solo (1.30.5 looked there as for a plain swing, 1.30.6 not at all, for
-- want of a group log). The author's 2026-11-11 16:33 log, in a group with a warrior, the game's
-- file beside it: 3 pairs, the late hit 1.305 s (Flurry, 31198.247) and 1.463 s (31167.658) after
-- the first swing, as solo, both dropped by 1.30.6; a Stormstrike in the pair's own frame moved
-- the first swing's hit (+0.999) but not the late one; the warrior's own hit came 0.12 s after it
-- (+1.580), outside the window. And the first number is the first swing's: a crit swing's came
-- as a crit at +0.413 (31197.355).
SWING_QUICK.EXTRA = {gap = 0.15, at = 1.46, flurry = 1.30, before = 0.07, after = 0.05}
function SWING_QUICK.MarkExtra(sw, now)
    if sw.ranged or sw.form or sw.hand ~= 0 then return end
    local ok, _, class = pcall(UnitClass, "player")
    if not ok or Plain(class) ~= "SHAMAN" then return end
    for i = #swings - 1, 1, -1 do
        local first = swings[i]
        if now - first.t > SWING_QUICK.EXTRA.gap then return end
        if first.plate == sw.plate and first.hand == 0 and not first.form and not first.extraOf
            and not first.extra then
            first.extra = sw
            sw.extraOf = first
            local E, off = SWING_QUICK.EXTRA, now - first.t
            -- its delay from the first swing: Flurry's when the weapon's is learned as Flurry's,
            -- the plain one when learned plain, either when not learned
            local lo = (first.quick == false and E.at or E.flurry) - E.before
            local hi = (first.quick == true and E.flurry or E.at) + E.after
            local expected = first.quick and E.flurry or E.at
            sw.min, sw.max, sw.expected, sw.own = lo - off, hi - off, expected - off, expected - off
            sw.ownAnims, sw.ownSpeed = sw.anims, sw.speed -- (1.31.10) its own delays, for SWING_QUICK.ExtraFit
            sw.speed, sw.anims, sw.centers, sw.lateCenters = nil, nil, nil, nil -- nothing to learn
            sw.only = nil -- (1.31.13) the extra swing goes by SWING_QUICK.ExtraFit alone
            Log("  the extra swing of your swing %.3f s before (Windfury Totem)", off)
            if FFT.OnWindfury then FFT:OnWindfury() end
            return
        end
    end
end

function FFT:OnSwing(swingType, swingDuration)
    local now = GetTime()
    -- the swing goes to the target you have now, even if you switch before it lands.
    -- PLAYER_SWING(swingDuration, swingType) (SwingTimerDocumentation): swingType is
    -- Enum.PlayerSwingType MainHand 0, OffHand 1, Ranged 2. The matching goes by the swing's moment,
    -- not a timer, so the weapon's speed needs no setting.
    -- (1.23.2) the hit's timing goes by the form you swing in (SWING_BY_FORM)
    local form = CurrentForm()
    local timing = (form and SWING_BY_FORM[form]) or SWING_NORMAL
    swings[#swings + 1] = {t = now, plate = FFT.TargetPlate(), ranged = (Plain(swingType) == 2),
        form = form, min = timing.min, max = timing.max, expected = timing.expected,
        own = timing.expected, -- its own delay, for SWING_AFTER_CAST
        hand = Plain(swingType)}
    local sw = swings[#swings]
    if not form and not sw.ranged then
        sw.speed = SWING_QUICK.Key(swingDuration)
        sw.quick = SWING_QUICK.Is(sw.speed)
        if sw.quick then sw.expected, sw.own = SWING_QUICK.own, SWING_QUICK.own end
        -- (1.29.0) the delays this weapon's swings were seen to hit after (SWING_QUICK.Anims)
        sw.anims = SWING_QUICK.DelaysFor(sw.speed) -- (1.31.11) or scaled from another swing time
        sw.centers = sw.anims
        local long = SWING_QUICK.Long(sw.anims)
        sw.lateCenters = long and {long * SWING_QUICK.CAST_LONG_RATIO} or nil
        SWING_QUICK.Only(sw)
        if sw.speed then SWING_QUICK.recent[sw.speed] = sw.t end -- for Windfury's slots (BaseAnims)
    end
    while swings[1] and now - swings[1].t > 3 do table.remove(swings, 1) end
    -- the weapon's swing time is logged: what moves the delay is still being learned.
    -- (1.28.0) And the target's plate ("at nameplate3"), so sim/replay.lua knows which mob you swung
    -- at (before, it guessed, and in fights with several mobs dropped swings the game showed).
    local speed = Plain(swingDuration)
    speed = type(speed) == "number" and ("%.2fs"):format(speed) or S(swingDuration)
    local at = swings[#swings].plate and plates[swings[#swings].plate]
    at = at and at.unit and (", at " .. at.unit) or (swings[#swings].plate and ", at your target (no nameplate)" or ", at no plate")
    if form then
        Log("your swing (%s, weapon %s, form %d%s%s)", S(swingType), speed, form,
            SWING_BY_FORM[form] and "" or ": timing not measured, normal used", at)
    else
        Log("your swing (%s, weapon %s%s)", S(swingType), speed, at)
    end
    SWING_QUICK.MarkExtra(sw, now)
    FFT:NoteOwnAction()
end

-- Only spells the game calls harmful (C_Spell.IsSpellHarmful): a buff totem dropped just as
-- your Flame Shock ticked was once taken for the tick's cause (seen in game).
-- (1.28.0) Casts you asked for come with UNIT_SPELLCAST_SENT first; a spell an item or a talent
-- triggers doesn't (not confirmed by a log yet: a cast with no SENT is logged as such). In the
-- 2026-11-09 09:59 log a "Fireball" came in the swing's frame twice (560345.002, 560373.410) and
-- the swing still hit at 0.461 s: a proc, which doesn't delay the swing as Stormstrike does.
-- Confirmed in the 2026-11-09 14:54 log: "Fireball" came with no SENT 14 times of 14. Ghost Wolf, First
-- Aid and Leatherworking once each too, but those were this list being wiped every 100 entries
-- between a long cast's SENT and its end: entries now go by age (a minute), never all at once.
local sentGUIDs, sentN = {}, 0
function FFT:NoteCastSent(castGUID)
    castGUID = Plain(castGUID)
    if castGUID == nil then return end
    local now = GetTime()
    sentN = sentN + 1
    if sentN > 100 then
        sentN = 0
        for guid, t in pairs(sentGUIDs) do if now - t > 60 then sentGUIDs[guid] = nil end end
    end
    sentGUIDs[castGUID] = now
end

function FFT:OnOwnCast(spellID, castGUID)
    spellID = Plain(spellID)
    if not spellID then return end
    -- (1.26.3) every cast of yours, for SWING_AFTER_CAST: a Totemic Recall delayed a swing too.
    -- sent: true, false (no SENT came: triggered), or nil (can't tell: no readable GUID)
    local castName = Plain(C_Spell.GetSpellName(spellID))
    local t = GetTime()
    local guid = Plain(castGUID)
    local sent
    if guid ~= nil then sent = sentGUIDs[guid] ~= nil end
    anyCasts[#anyCasts + 1] = {t = t, name = type(castName) == "string" and castName or "cast", sent = sent}
    while anyCasts[1] and t - anyCasts[1].t > 3 do table.remove(anyCasts, 1) end
    if sent == false then Log("your cast %s came with no UNIT_SPELLCAST_SENT (triggered?)", S(castName)) end
    if not Plain(C_Spell.IsSpellHarmful(spellID)) then
        -- Log only, never matched. Helpful casts are logged by Heals.lua; the rest were missing:
        -- Searing Totem and Strength of Earth Totem left no cast line at all in the 1.13.0 log
        -- (2026-11-06, solo), while 7 regular Fire hits were dropped. Their times are needed to
        -- work out totem hits.
        if not Plain(C_Spell.IsSpellHelpful(spellID)) then
            Log("your cast %s (id %s, not harmful or helpful: not matched)",
                S(C_Spell.GetSpellName(spellID)), tostring(spellID))
        end
        return
    end
    local name = Plain(C_Spell.GetSpellName(spellID))
    if not name then return end
    local now = GetTime()
    local plate = FFT.TargetPlate()
    local at = plate and plates[plate]
    Log("your cast %s%s", name, at and at.unit and (" at " .. at.unit) or "") -- (1.28.0) the target, for replays
    FFT:NoteOwnAction()
    ownCasts[#ownCasts + 1] = {t = now, name = name, plate = plate, sent = sent}
    while ownCasts[1] and now - ownCasts[1].t > FLIGHT_WINDOW + 1 do table.remove(ownCasts, 1) end
    -- any of your spells on a mob may tick on it (Flame Shock, Rend...): a recast starts over
    if plate then
        dots[plate] = dots[plate] or {}
        -- a recast keeps the previous cast's ticks (its last tick can land with the recast)
        local prev = dots[plate][name]
        if prev then dots[plate][name .. "#prev"] = prev end
        dots[plate][name] = {name = name, t0 = now, used = {}, times = {}, bySchool = {}}
    end
end

function FFT:ForgetPlateDots(plate) dots[plate] = nil end

------------------------------------------------------------------------
-- Your totems, guardians and pet (1.14.0)
------------------------------------------------------------------------
-- Seen in game (probe log 2026-11-06 16:31, in a group, Combat restriction on):
--   - with the CVar nameplateShowFriendlyPlayerTotems = 1 your Searing Totem gets a nameplate
--     unit, and UnitIsOwnerOrControllerOfUnit("player", it) reads true (a groupmate's pet: false)
--   - each of its attacks fires UNIT_SPELLCAST_SUCCEEDED for that unit with a readable spellID
--     (3606), although the docs make cast info secret for units other than you and your pet
--   - all 9 Fire hits that were dropped landed 0.12-0.33s after one of those casts, one per cast
-- Your pet's casts are readable by the docs (SecretWhenUnitSpellCastRestricted exempts the pet).
-- Nothing here is about one class: any unit you own that casts is matched the same way.
-- One cast claims one hit of its spell's learned school in the window after it: on the mob it
-- targets when the game lets that be read, otherwise one hit on any mob.
-- 1.14.1: the window was 0.5s; the 1.14.0 log (16:42) had a hit 0.46s after its cast.
-- 1.14.2: the 1.14.1 log (16:47) had hits 0.64s and 0.66s after their casts (the totem's bolt
-- flies; farther mobs take longer), so 0.10-0.66s seen in all. Still far below the 2.3-2.9s
-- between Searing Totem's attacks, so one cast can't take the next one's hit.
local MINION_WINDOW = 1.0
local ownMinions = {}       -- nameplate unit token -> true: your totems/guardians with a plate
local minionCasts = {}      -- {t, id, name, unit, plate (its target's plate, or nil), claimed = {}, any}
local minionVotes = {}      -- spellID -> {school -> count, n = total}

-- Kept by spell ID, not name: Searing Totem's attack (3606) is just called "Attack" in
-- Forever (1.14.0 log), a name other minions' spells of other schools can have too.
local function MinionSchool(id) return db.minionSchools and db.minionSchools[id] end

function FFT:OnMinionPlateAdded(unit)
    local ok, owned = pcall(UnitIsOwnerOrControllerOfUnit, "player", unit)
    if ok and Plain(owned) == true then
        ownMinions[unit] = true
        Log("your minion %s: %s", unit, S(UnitName(unit)))
    else
        ownMinions[unit] = nil
    end
end

function FFT:OnMinionPlateRemoved(unit) ownMinions[unit] = nil end

-- The plate of the mob your minion targets, if the game lets that be read. Seen in game
-- (1.14.1 log, 16:47, open world): UnitIsUnit("nameplate3target", "target") read true while the
-- totem and you hit the same mob, but UnitIsUnit("nameplate3target", "nameplate2") read false
-- for that same mob, every time. So only "is it your target" can be told. The docs make
-- compound-token comparisons secret on addon-restricted maps (dungeons, raids).
-- Returns the plate, or nil and why not.
local function MinionTarget(unit)
    local tunit = unit .. "target"
    local ok, exists = pcall(UnitExists, tunit)
    if not ok then return nil, "error" end
    if IsSecret(exists) then return nil, "secret" end
    if not exists then return nil, "no target" end
    local ok2, same = pcall(UnitIsUnit, tunit, "target")
    if not ok2 then return nil, "error" end
    if IsSecret(same) then return nil, "secret" end
    local plate = same and FFT.TargetPlate()
    if plate then return plate, "your target" end
    local okName, tname = pcall(UnitName, tunit)
    return nil, ("not your target (it targets %s)"):format(okName and S(tname) or "?")
end

function FFT:OnMinionCast(unit, spellID)
    if unit ~= "pet" then
        if not ownMinions[unit] then return end
        -- your pet with a plate also casts as "pet": count it once
        local ok, isPet = pcall(UnitIsUnit, unit, "pet")
        if ok and Plain(isPet) == true then return end
    end
    spellID = Plain(spellID)
    if not spellID then
        Log("your minion %s cast <secret>: can't be matched", unit)
        return
    end
    -- for the log and the reason shown: "Searing Totem's Attack"
    local who = Plain(UnitName(unit)) or unit
    local name = who .. "'s " .. (Plain(C_Spell.GetSpellName(spellID)) or tostring(spellID))
    -- heals and buffs (Healing Stream Totem's ticks) aren't attacks
    if Plain(C_Spell.IsSpellHelpful(spellID)) == true then
        Log("your minion %s: %s (helpful, not matched)", unit, name)
        return
    end
    local now = GetTime()
    local plate, why = MinionTarget(unit)
    minionCasts[#minionCasts + 1] = {t = now, id = spellID, name = name, unit = unit, plate = plate, claimed = {}}
    while minionCasts[1] and now - minionCasts[1].t > MINION_WINDOW + 1 do table.remove(minionCasts, 1) end
    Log("your minion %s cast %s (id %s, school %s), target %s", unit, name, tostring(spellID),
        tostring(MinionSchool(spellID) or "not learned"), plate and why or ("unknown: " .. why))
end

-- A cast of your minion whose hit this can be (its school is known by now). Misses aren't
-- claimed: a miss comes as school 1 whoever caused it, and in the 1.14.1 log (16:47, 850.548)
-- someone's Miss took the totem's claim and its real Fire hit 0.06s later was dropped.
local function MinionFor(plate, hit, now)
    if hit.miss then return end
    for _, c in ipairs(minionCasts) do
        local dt = now - c.t
        if dt >= -SAME_MOMENT and dt <= MINION_WINDOW and not c.any and not c.claimed[plate]
            and (c.plate == nil or c.plate == plate) then
            local known = MinionSchool(c.id)
            if known and known == hit.school then return c, dt end
        end
    end
end

-- A minion spell's school is learned by votes, as for your flying spells: each cast votes with
-- the first hit after it that nothing else explained. 3 votes, at least 75% for one school.
-- Until then its hits are left out.
local function VoteMinion(plate, hit, now)
    if hit.miss or not hit.school then return end
    for _, c in ipairs(minionCasts) do
        local dt = now - c.t
        if not c.voted and not MinionSchool(c.id) and dt >= -SAME_MOMENT and dt <= MINION_WINDOW
            and (c.plate == nil or c.plate == plate) then
            c.voted = true
            local v = minionVotes[c.id] or {n = 0}
            minionVotes[c.id] = v
            v[hit.school] = (v[hit.school] or 0) + 1
            v.n = v.n + 1
            Log("  %s (minion): vote for school %d (%d of %d), %.2fs after its cast", c.name, hit.school,
                v[hit.school], v.n, dt)
            if v[hit.school] >= 3 and v[hit.school] >= 0.75 * v.n then
                db.minionSchools = db.minionSchools or {}
                db.minionSchools[c.id] = hit.school
                Log("  learned: %s (minion, id %d) hits as school %d (from %d casts)", c.name, c.id, hit.school, v.n)
            end
            return
        end
    end
end

-- Learned schools and DoT beats only belong to spells the game calls harmful. 1.12.0 could
-- learn them for buff totems; those are removed (by name, as they were saved).
function FFT:CleanLearned()
    for _, key in ipairs({"spellSchools", "dotPeriods"}) do
        local list = db[key]
        if list then
            for name in pairs(list) do
                local harmful = Plain(C_Spell.IsSpellHarmful(name))
                if harmful == false then
                    list[name] = nil
                    Log("removed what was learned for %s (not an attack)", name)
                end
            end
        end
    end
    -- 1.15.0: DoT rhythms learned while threat was hidden could be a groupmate's ticks (the Combat
    -- Log showed a hunter's Nature ticks learned as "Earth Shock", 0.98s, 27 ticks). Start over once.
    if (db.learnVersion or 0) < 2 then
        if db.dotPeriods then
            db.dotPeriods = nil
            Print("1.15.0: forgot the damage-over-time rhythms learned so far (some were other players' ticks).")
        end
        db.learnVersion = 2
    end
    -- 1.14.0 kept minion schools by spell name ("Attack"); from 1.14.1 they're by spell ID
    if db.minionSchools then
        for key in pairs(db.minionSchools) do
            if type(key) ~= "number" then db.minionSchools[key] = nil end
        end
    end
end

local function DotInfo(name) return db.dotPeriods and db.dotPeriods[name] end

-- Spells that fly (Lightning Bolt) learn their school while threat is hidden by votes: each
-- cast votes with the school of the first spell hit on its mob after it. 3 votes, at least
-- 75% of them for one school, and that's the spell's school.
local flightVotes = {} -- spell name -> {school -> count, n = total}

local function VoteFlight(plate, school, now)
    for _, c in ipairs(ownCasts) do
        local dt = now - c.t
        if c.plate == plate and not c.landed and not c.voted and dt > SAME_MOMENT and dt <= FLIGHT_WINDOW
            and not (db.spellSchools and db.spellSchools[c.name]) then
            c.voted = true
            local v = flightVotes[c.name] or {n = 0}
            flightVotes[c.name] = v
            v[school] = (v[school] or 0) + 1
            v.n = v.n + 1
            Log("  %s: vote for school %d (%d of %d)", c.name, school, v[school], v.n)
            if v[school] >= 3 and v[school] >= 0.75 * v.n then
                db.spellSchools = db.spellSchools or {}
                db.spellSchools[c.name] = school
                Log("  learned: %s hits as school %d (from %d casts)", c.name, school, v.n)
            end
            return
        end
    end
end

local function SpellSchool(name)
    return db.spellSchools and db.spellSchools[name]
end

-- A cast in this same moment, if any
-- A cast in this same moment whose hit this can be: a spell seen to hit as another school
-- isn't (a physical miss landing just as your Flame Shock does isn't the Flame Shock's)
-- plate given: one cast lands one hit per mob in its moment (two Nature hits in Earth Shock's
-- moment were seen in game: the other was someone's Serpent Sting tick)
local function SameMomentCast(now, school, plate)
    for i = #ownCasts, 1, -1 do
        local c = ownCasts[i]
        if math.abs(now - c.t) <= SAME_MOMENT and not (plate and c.claimed and c.claimed[plate]) then
            local known = SpellSchool(c.name)
            if not (known and school and known ~= school) then return c end
        end
    end
end

-- Your spell still in the air at this mob, whose known school matches
local function FlightFor(plate, school, now)
    for _, c in ipairs(ownCasts) do
        local dt = now - c.t
        if not c.landed and c.plate == plate and dt > SAME_MOMENT and dt <= FLIGHT_WINDOW
            and school and SpellSchool(c.name) == school then
            return c
        end
    end
end

-- The oldest of your swings at this mob whose hit could be this one
-- where your swing's hit lands: each swing's own `expected` (1.23.2, by form; 0.46 out of form)
local SWING_MARGIN = 0.008  -- (1.21.0) fallback: a rival hit this much farther still counts as as close

-- The oldest of your swings at this mob whose hit could be this one (not taken yet)
-- meleeOnly (Combat Log mode, 1.17.0): a ranged shot's hit isn't on the melee timing, and taken
-- here it would leave its own Combat Log line unused for someone else's hit; it goes by its line.
-- (1.23.4) A swing in the same frame as an attack of yours lands later. The author's 2026-11-08 12:02 log
-- (solo, Combat Log in use): at 481349.168 PLAYER_SWING (a "swing" line, so it hit), Stormstrike's
-- cast and its own school 1 hit all came in one frame; the swing's hit came at 481350.162, 0.994 s
-- after it, past SWING_MAX, and was dropped. As if the swing's animation waited for Stormstrike's:
-- 0.994 = 0.461 + 0.533. A Stormstrike 0.45 s before a swing didn't delay it (481355.547 ->
-- swing 481355.998 -> hit 481356.460, 0.462 s). Only that one case is measured, so the window is
-- one ~0.065 s step either side of it (the delays come in such steps, see SWING_BY_FORM), and it
-- opens only when no hit came in the swing's normal window: a swing has one hit, so a normal one
-- uses the swing up first (ResolveSwing runs at most 0.57 s after it, before this window opens).
-- Any harmful cast of yours in the swing's frame counts (ownCasts); whether a spell like Earth
-- Shock delays it too isn't seen yet, and the log line names the cast so a log can tell.
-- (1.25.1) Four more in the 2026-11-09 08:33 log, 0.993-0.999 s. And a Stormstrike 0.104 s *after*
-- the swing delayed it the same (555382.878 -> 555383.876, 0.998 s; dropped by 1.25.0), so a cast
-- up to SWING_CAST_AFTER after the swing counts too. The delay is the swing's own plus the cast's
-- ~0.534 s, one ~0.065 s step either side: 0.93-1.06 around 0.994.
-- (1.26.3) The 2026-11-09 09:59 log: any cast of yours before the swing's hit delays it, and to the
-- same ~0.995 s however late it came: Stormstrike in the frame (0.997, 0.994), +0.111 (0.996) and
-- +0.439 (0.995); Earth Shock +0.113 (0.998); Totemic Recall, not harmful, +0.294 (0.997). So every
-- cast counts (anyCasts), up to just before the swing's normal hit.
-- (1.28.13) The author's 2026-11-10 13:50 log (solo; the game's own combat log file beside it, no one
-- else on these mobs), 4 swings dropped, all delayed by a cast:
--   - A Flurry swing waits less: 0.886 s (12134.959, Earth Shock in its frame) and 0.887 s
--     (12137.976, Stormstrike +0.295), as its plain hit comes at 0.415 not 0.461. So the late window
--     reaches down to 0.862 (`before` 0.132; was 0.064, 0.93-1.06). Whether a swing has Flurry can't
--     be told: an attack speed buff shortens the swing's time too, and not the delay (NOTES.md).
--   - A Windfury swing waits too: a Stormstrike 0.808 s after the proc, before the swing's own hit
--     at 0.96, moved that hit to 1.491 s after the proc (12379.054; 1.489 in the 2026-11-09 09:59
--     log), with Flurry 1.385 (12108.084, Stormstrike +0.826). The same 0.534 more (SwingFor).
local SWING_AFTER_CAST = {extra = 0.534, before = 0.132, after = 0.066}
local SWING_CAST_FRAME = 0.002 -- events of one frame share one GetTime() (as SAME_FRAME below)
local SWING_CAST_AFTER = 0.45  -- seen up to 0.439; the swing's own hit comes at 0.46

-- your cast in this swing's frame or after it, up to `now`, if any (not a triggered one).
-- within (optional): how long after the swing it may come (a Windfury swing's hit comes later);
-- from (optional): and how long after it at the earliest
local function CastWithSwing(sw, now, within, from)
    for _, c in ipairs(anyCasts) do
        local d = c.t - sw.t
        if c.sent ~= false and d >= (from or -SWING_CAST_FRAME) and d <= (within or SWING_CAST_AFTER) and c.t <= now + SWING_CAST_FRAME then
            return c
        end
    end
end

-- (1.26.3) Windfury: once a proc of this swing is spotted (SwingProc, below with the Combat Log's
-- lines), the swing's own hit comes ~0.96 s after the proc, not in its normal window:
-- 0.958, 0.959, 0.963 s in the 2026-11-09 09:59 log (560324.482, 560419.562, 560467.586).
-- (1.28.0) In the 2026-11-09 14:54 group log, measured from the proc's lines: 0.956-0.961 s (12) and,
-- with Flurry (0.05 s sooner, as for a normal swing), 0.904-0.910 s (4); two others at 0.985 and
-- 1.068. So 0.89-1.01: both clusters, not the 1.068 (was -0.06/+0.07, 0.90-1.03)
local SWING_AFTER_PROC = {expected = 0.96, before = 0.07, after = 0.05}
-- (1.28.14) with the swing's own delay learned (sw.quick true or false, see SWING_QUICK) the cast
-- and Windfury windows are centered on its value and as narrow as their late side; not known, they
-- reach down to the Flurry value as before
function SWING_QUICK.CastExtra(sw) return sw.quick and SWING_QUICK.extra or SWING_AFTER_CAST.extra end
function SWING_QUICK.CastBefore(sw) return sw.quick == nil and SWING_AFTER_CAST.before or SWING_AFTER_CAST.after end
function SWING_QUICK.ProcExpected(sw) return sw.quick and SWING_QUICK.proc or SWING_AFTER_PROC.expected end
function SWING_QUICK.ProcBefore(sw) return sw.quick == nil and SWING_AFTER_PROC.before or SWING_AFTER_PROC.after end
local SwingProc -- function(sw, now): the proc's moment or nil (set in the Combat Log section)

-- (1.31.10) Where Windfury Totem's extra swing hits, now that the weapon enchant procs with it. The
-- author's 2026-11-13 03:27 log (solo, enchant and totem, the game's file beside it): of 8 pairs
-- that hit, 1.31.9 showed 2. One rule fits every pair measured on two weapons: the extra swing
-- hits where the first swing's would if a cast had delayed it (its delay x 2.15: 0.995 for 0.461,
-- 0.887 for 0.415, SWING_AFTER_CAST), plus the extra swing's own delay; with an enchant proc on the
-- first swing, from 0.50 s after the proc, as the first swing's own hit is (SwingFor). From the
-- learned delays (SWING_QUICK.Anims): 3.60 s weapon 0.464, its Flurry swings (2.77 s) 0.355.
--   plain:             0.464 x 2.15 + 0.464 = 1.461     seen 1.459 (156662.889)
--   enchant proc:      0.50 + 1.461 = 1.961             seen 1.953, 1.954 (156659.256, 156704.613)
--   Flurry, proc:      0.50 + 0.355 x 3.15 = 1.619      seen 1.612, 1.613 (156688.722, 156806.762)
--   first 3.60, extra 2.77 (Flurry from a crit in the pair's frame), Stormstrike there:
--                      0.464 x 2.15 + 0.355 = 1.353     seen 1.351 (156685.888)
--   2026-11-11 12:46 log, old weapon, Flurry 0.415: 1.307, seen 1.303-1.305
-- Not fitting, left out: 1.842 after a proc of one enchant attack (156735.656). The first swing's
-- delay is the one its hit showed when it has several (a cast-delayed one: any of them). A cast
-- from 0.53 s before the extra's hit delays it by its own delay x 1.15 (0.534 at 0.464: 12:53 log,
-- 17989.289, +0.527). Without learned delays, the 1.30.5 windows, moved by the proc too.
-- Returns "now" or "late" when the hit at d (after the extra swing) fits, false when not.
SWING_QUICK.CAST_RATIO = 1.15 -- a cast's added wait over the swing's delay (0.534 / 0.464, 0.472 / 0.415)
function SWING_QUICK.CastAdd(d)
    return d >= 0.6 and d * (SWING_QUICK.CAST_LONG_RATIO - 1) or d * SWING_QUICK.CAST_RATIO
end
-- (1.31.11) The author's 2026-11-13 08:08 log (solo, the game's file): 6 more kinds of pair.
--   Flurry started between the two swings, by a crit of the first swing, of an enchant attack or of
--   the extra itself: the extra hits on Flurry's delay, while its PLAYER_SWING still reads the slow
--   swing time (1.180, 1.677, 1.195, 1.694 for 0.403 x 2.15 + 0.309 = 1.175, + 0.50 = 1.675; with
--   Stormstrike 1.549; 03:27's 1.842 = 0.50 + 0.464 x 2.15 + 0.355 + 0.013). Flurry comes from a
--   crit and each of these had one of yours on that mob, so after one (FFT.critAt, or this hit's
--   own) the delays of a swing time seen in the last minute at 0.65-0.95 of the extra's are tried too.
--   A first swing delayed by a proc not seen (Stormstrike's Windfury whose one attack missed: no line
--   at the proc, its SPELL_MISSED 0.23 s later): the extra went from the first swing's own hit,
--   +0.866 (173709.412: 0.911 -> 1.773). So for a first swing whose hit came late, that moment too.
function SWING_QUICK.FlurryDelays(x)
    local s, now, out = tonumber(x.ownSpeed), GetTime(), {}
    if not s then return out end
    for k, t in pairs(SWING_QUICK.recent) do
        local r = (tonumber(k) or 0) / s
        if now - t <= 60 and r >= 0.65 and r <= 0.95 then
            for _, dd in ipairs(SWING_QUICK.DelaysFor(k) or {}) do out[#out + 1] = dd end
        end
    end
    return out
end
function SWING_QUICK.ExtraFit(x, now, d, slack, hit)
    local first, E = x.extraOf, SWING_QUICK.EXTRA
    local off = x.t - first.t
    local start = 0
    local procAt = SwingProc and SwingProc(first, now)
    if procAt then
        local fromSwing = first.hitsFromSwing and not first.hitsFromLines
        start = (fromSwing and 0 or (procAt - first.t)) + 0.50
    end
    local d1s, d2s = first.anims, x.ownAnims
    if d1s and first.hitD and not first.hitLate then
        local one = SWING_QUICK.Near(d1s, first.hitD - start, SWING_QUICK.ANIM_TOL + slack)
        if one then d1s = {one} end
    end
    local critAt = FFT.critAt[x.plate]
    if d2s and ((hit and hit.crit) or (critAt and critAt >= first.t - SWING_CAST_FRAME)) then
        local more = SWING_QUICK.FlurryDelays(x)
        if #more > 0 then
            local all = {}
            for _, dd in ipairs(d2s) do all[#all + 1] = dd end
            for _, dd in ipairs(more) do all[#all + 1] = dd end
            d2s = all
        end
    end
    -- each moment with 1.30.5's margins (0.07 before, 0.05 after): 1.408 in the 12:53 log (17943.139)
    -- is 0.044 s before 1.452; the 03:27 ones 0.002-0.008 s before theirs
    local function Near(list, at)
        for _, c in ipairs(list) do
            if at >= c - E.before - slack and at <= c + E.after + slack then return c end
        end
    end
    if d1s and d2s then
        local centers, lates = {}, {}
        for _, d1 in ipairs(d1s) do
            for _, d2 in ipairs(d2s) do
                local c = start + d1 + SWING_QUICK.CastAdd(d1) + d2 - off
                centers[#centers + 1] = c
                lates[#lates + 1] = {c = c, at = c + SWING_QUICK.CastAdd(d2)}
                if first.hitD and first.hitLate then -- from the first swing's own (late) hit
                    centers[#centers + 1] = first.hitD + SWING_QUICK.CastAdd(d1) + d2 - off
                end
            end
        end
        table.sort(centers)
        x.centers, x.expected, x.own = centers, centers[1], centers[1]
        x.min, x.max = centers[1] - E.before, centers[#centers] + E.after
        local nearC = Near(centers, d)
        for _, l in ipairs(lates) do
            local cast = CastWithSwing(x, now, l.c - 0.01, l.c - 0.53)
            if cast then
                x.waitLate, x.lateAt = x.waitLate or cast, l.at
                x.lateCenters = {l.at}
                if Near({l.at}, d) and (x.waitLate == cast or not x.cands) then return "late" end
            end
        end
        return nearC and "now" or false
    end
    -- not learned: 1.30.5's windows, from the proc when there is one
    local lo = (first.quick == false and E.at or E.flurry) - E.before + start - off
    local hi = (first.quick == true and E.flurry or E.at) + E.after + start - off
    local expected = (first.quick and E.flurry or E.at) + start - off
    x.min, x.max, x.expected, x.own = lo, hi, expected, expected
    local cast = CastWithSwing(x, now, expected - 0.01, expected - 0.53)
    if d >= lo - slack and d <= hi + slack then
        if cast then x.waitLate = x.waitLate or cast end
        return "now"
    end
    local late = expected + SWING_QUICK.CastExtra(x)
    if cast and (x.waitLate or not x.cands) and d >= late - SWING_QUICK.CastBefore(x) - slack
        and d <= late + SWING_AFTER_CAST.after + slack then
        x.waitLate = x.waitLate or cast
        return "late"
    end
    return false
end

-- (1.28.0) A cast of yours before the swing's hit opens its late window too, and the swing waits
-- for both: a hit in the late window is the swing's (the cast delayed it), and then a hit in its
-- normal window goes on to the other checks; with none late, the normal one is the swing's. Most
-- casts delay the hit (SWING_AFTER_CAST), but not every one: Fire Nova 0.364 s after a swing in the
-- 2026-11-07 16:45 dungeon log (412024.085) left it at 0.461 s. Closing the normal window at the
-- cast dropped that swing; leaving it open alone let others' hits at 0.4-0.5 s take delayed swings
-- (simulator, 5 others: 18). Returns the swing, the hit's delay, and whether it's the late window.
-- missed (optional, 1.28.14): is the hit asked about a miss; a swing whose own line says otherwise
-- isn't looked at (SWING_QUICK.Missed)
local function SwingFor(now, plate, meleeOnly, missed, hit)
    local slack = FrameSlack()
    for _, sw in ipairs(swings) do
        local d = now - sw.t
        local fits = true
        if missed ~= nil and SWING_QUICK.Missed and not sw.used and sw.plate == plate then
            local swMissed = SWING_QUICK.Missed(sw)
            fits = swMissed == nil or swMissed == missed
        end
        -- (1.31.10) Windfury Totem's extra swing goes by its own rule (SWING_QUICK.ExtraFit), never
        -- by the plain or proc windows: the enchant's lines are in its frame too
        local extraFit = sw.extraOf and fits and not sw.used and sw.plate == plate
            and SWING_QUICK.ExtraFit(sw, now, d, slack, hit)
        if extraFit then return sw, d, extraFit == "late" end
        local procAt = not sw.extraOf and fits and not sw.used and sw.plate == plate and not (meleeOnly and sw.ranged)
            and SwingProc and SwingProc(sw, now)
        if procAt then
            -- (1.28.11) from the swing itself when this proc's Windfury hits were all timed from
            -- the swing, not from its lines (see ExtraAttackLine)
            local fromSwing = sw.hitsFromSwing and not sw.hitsFromLines
            local late = (fromSwing and 0 or (procAt - sw.t)) + SWING_QUICK.ProcExpected(sw)
            -- (1.28.13) a cast of yours before that hit delays it again, as it does a plain swing's
            -- (1.28.14) only one from when that wait starts, 0.46 s before the hit (0.50 s after the
            -- proc): the two seen came 0.808 and 0.826 s after the proc. In the 2026-11-10 15:25
            -- dungeon log a Stormstrike 0.19 s after the proc (17824.851) left the hit at 0.959, and
            -- a hunter's shot 1.41 s after the proc was shown for it.
            -- (1.29.0) with learned delays: 0.50 s plus one of them after the proc, or 0.755 plus
            -- the long one (SWING_QUICK.SLOT_LONG)
            local alt
            if sw.anims then
                local base = fromSwing and 0 or (procAt - sw.t)
                alt = {}
                for _, a in ipairs(sw.anims) do
                    alt[#alt + 1] = base + (a >= 0.6 and SWING_QUICK.SLOT_LONG or 0.50) + a
                end
            end
            -- (1.31.13) a swing time that goes by its learned delays alone (SWING_QUICK.Only): only
            -- those moments, and a cast from 0.50 s after the proc up to the hit they give
            local only = sw.only and alt
            local cast
            if only then cast = CastWithSwing(sw, now, alt[#alt] - 0.01, alt[1] - sw.anims[1] - 0.07)
            else cast = CastWithSwing(sw, now, late - 0.01, late - 0.53) end
            local altHit = alt and SWING_QUICK.Near(alt, d, SWING_QUICK.ANIM_TOL + slack)
            if (not only and d >= late - SWING_QUICK.ProcBefore(sw) - slack and d <= late + SWING_AFTER_PROC.after + slack) or altHit then
                sw.min, sw.max, sw.expected = late - SWING_QUICK.ProcBefore(sw), late + SWING_AFTER_PROC.after, only and alt[1] or late
                if alt then
                    sw.centers = alt
                    for _, c in ipairs(alt) do sw.max = math.max(sw.max, c + SWING_QUICK.ANIM_TOL) end
                end
                sw.afterCast = "Windfury"
                if cast then
                    sw.waitLate = sw.waitLate or cast
                    sw.lateAt = only and (alt[1] + SWING_QUICK.CastAdd(sw.anims[1])) or late + SWING_QUICK.CastExtra(sw)
                end
                return sw, d, false
            end
            local later = only and (alt[1] + SWING_QUICK.CastAdd(sw.anims[1])) or late + SWING_QUICK.CastExtra(sw)
            if cast and (sw.waitLate or not sw.cands)
                and d >= later - (only and SWING_QUICK.ANIM_TOL or SWING_QUICK.CastBefore(sw)) - slack
                and d <= later + (only and SWING_QUICK.ANIM_TOL or SWING_AFTER_CAST.after) + slack then
                sw.min, sw.max, sw.expected = late - SWING_QUICK.ProcBefore(sw), late + SWING_AFTER_PROC.after, late
                sw.waitLate = sw.waitLate or cast
                sw.lateAt = later
                return sw, d, true
            end
        elseif not sw.extraOf and fits and not sw.used and sw.plate == plate and not (meleeOnly and sw.ranged) then
            -- (1.29.0) a cast up to the weapon's longest learned delay delays it too (Stormstrike
            -- +0.570 before a 0.73 s swing, 30282.250)
            local long = SWING_QUICK.Long(sw.anims)
            -- (1.31.13) going by its learned delays alone (SWING_QUICK.Only): a cast up to the last of
            -- them, a hit only at one of them, a late hit only at one's cast-delayed moment
            local cast = not sw.ranged and CastWithSwing(sw, now, long and long - 0.01 or (sw.only and sw.anims[#sw.anims]) or nil)
            local anim = sw.anims and SWING_QUICK.Near(sw.anims, d, SWING_QUICK.ANIM_TOL + slack)
            if (not sw.only and d >= sw.min - slack and d <= sw.max + slack) or anim then
                if cast then sw.waitLate = sw.waitLate or cast end
                return sw, d, false
            end
            -- (1.23.4) the later window, when your cast came before its hit (and before any hit in
            -- its normal window)
            local late = sw.own + SWING_QUICK.CastExtra(sw)
            local lateLong = cast and sw.lateCenters
                and SWING_QUICK.Near(sw.lateCenters, d, SWING_QUICK.ANIM_TOL + slack)
            if cast and (sw.waitLate or not sw.cands) and (lateLong or not sw.only and d >= late - SWING_QUICK.CastBefore(sw) - slack
                and d <= late + SWING_AFTER_CAST.after + slack) then
                sw.waitLate = sw.waitLate or cast
                return sw, d, true
            end
        end
    end
end

-- A tick of one of your DoTs on this mob: its learned school, on its learned beat.
-- tolerance: how far off the beat (DOT_TOLERANCE if not given)
local DOT_ON_BEAT = 0.12 -- Flame Shock ticks were 0.02-0.08s off the learned beat (in-game logs, 2026-11-06)
-- (1.21.0) Measured against the cast itself, a DoT ticks on an exact beat: all 29 Flame Shock tick
-- lines in the 2026-11-07 16:45 dungeon log came -0.011..+0.016 s from 3, 6, 9, 12 s after
-- UNIT_SPELLCAST_SUCCEEDED (13 casts). The "0.02-0.08 s off" above was off a learned period that
-- wasn't exact. A period learned from the Combat Log's tick lines is kept as exact.
local DOT_EXACT = 0.03
-- exactOnly: only DoTs whose period was learned exactly (from Combat Log lines), on that beat
local function DotFor(plate, school, now, tolerance, exactOnly)
    local list = dots[plate]
    if not list or not school then return end
    for _, d in pairs(list) do
        local name = d.name
        local info = DotInfo(name)
        local age = now - d.t0
        if info and info.school == school and age <= DOT_WATCH and (info.exact or not exactOnly) then
            local tol = info.exact and math.min(tolerance or DOT_TOLERANCE, DOT_EXACT) or (tolerance or DOT_TOLERANCE)
            local k = math.floor(age / info.period + 0.5)
            if k >= 1 and k <= info.ticks and math.abs(age - k * info.period) <= tol
                and not d.used[k] then
                d.used[k] = true
                return name, k
            end
        end
    end
end

------------------------------------------------------------------------
-- What the Combat Log teaches for when it's gone (1.21.0)
------------------------------------------------------------------------
-- While the Combat Log works, its lines say for sure which hits are yours. From those the addon
-- keeps two things about you, so that the fallback (no Combat Log, threat hidden in a group) can
-- go by facts instead of guesses:
--   - each DoT's exact period and tick count, from its tick lines (see DOT_EXACT);
--   - which school procs off your swing and how long after PLAYER_SWING its hit comes. Dungeon log
--     2026-11-07 16:45: 80 Flametongue hits 0.02-0.09 s after the swing (78 of them 0.02-0.05 s),
--     while only 3 Fire hits of others' landed in 0.02-0.05 s after one of the author's 93 swings.
-- Nothing is learned from guesses in a group: in the simulator that "learned" Earth Shock as a DoT
-- from a hunter's Serpent Sting ticks, and 16-21% of what the fallback showed in a 5-man wasn't yours.

-- The longest period that fits at least 90% of a DoT's tick ages (4 or more), snapped to half
-- seconds (tick periods are whole or half seconds); with the most ticks seen at it.
local function SnapHalf(p)
    local s = math.floor(p * 2 + 0.5) / 2
    if s > 0 and math.abs(s - p) <= DOT_EXACT then return s end
end

local function ExactPeriod(ages)
    if #ages < 4 then return end
    local best, bestTicks
    local tried = {}
    for _, a in ipairs(ages) do
        for k = 1, 8 do
            local p = SnapHalf(a / k)
            if p and p >= 1 and not tried[p] then
                tried[p] = true
                local fit, ticks = 0, 0
                for _, b in ipairs(ages) do
                    local kb = math.floor(b / p + 0.5)
                    if kb >= 1 and math.abs(b - kb * p) <= DOT_EXACT then
                        fit = fit + 1
                        if kb > ticks then ticks = kb end
                    end
                end
                if fit >= 0.9 * #ages and (not best or p > best) then best, bestTicks = p, ticks end
            end
        end
    end
    return best, bestTicks
end

local function LearnExactDot(name, school, age)
    db.dotAges = db.dotAges or {}
    local ages = db.dotAges[name] or {}
    db.dotAges[name] = ages
    ages[#ages + 1] = math.floor(age * 1000 + 0.5) / 1000
    while #ages > 40 do table.remove(ages, 1) end
    local period, ticks = ExactPeriod(ages)
    if not period then return end
    db.dotPeriods = db.dotPeriods or {}
    local old = db.dotPeriods[name]
    if not (old and old.exact and old.period == period and old.ticks >= ticks) then
        db.dotPeriods[name] = {period = period, ticks = math.max(ticks, (old and old.exact and old.period == period) and old.ticks or 0),
            school = school, exact = true}
        Log("  learned from the Combat Log: %s ticks every %.1fs, %d ticks (school %d)", name, period,
            db.dotPeriods[name].ticks, school)
    end
end

local PROC_MAX = 0.2 -- a swing's proc: its hit this soon after PLAYER_SWING (seen 0.02-0.16 s)
local function NoteSwingProc(school, dt)
    db.swingProcs = db.swingProcs or {}
    local p = db.swingProcs[school] or {}
    db.swingProcs[school] = p
    p[#p + 1] = math.floor(dt * 1000 + 0.5) / 1000
    while #p > 40 do table.remove(p, 1) end
end

-- The window after PLAYER_SWING where your proc of this school lands: the middle 90% of the
-- delays seen (at least 5), with a frame's room each side. nil while not known.
local function ProcWindow(school)
    local p = db.swingProcs and db.swingProcs[school]
    if not p or #p < 5 then return end
    local s = {}
    for i, v in ipairs(p) do s[i] = v end
    table.sort(s)
    local lo = s[math.max(1, math.floor(#s * 0.05 + 1))]
    local hi = s[math.max(1, math.ceil(#s * 0.95))]
    return math.max(0, lo - 0.01), hi + 0.01
end

-- Your swing at this mob whose proc this hit can be (one proc per swing)
local function ProcSwingFor(plate, school, now, hit)
    local lo, hi = ProcWindow(school)
    if not lo then return end
    for _, sw in ipairs(swings) do
        local dt = now - sw.t
        if not sw.ranged and not sw.procUsed and sw.plate == plate and dt >= lo and dt <= hi then
            return sw, dt
        end
    end
end

-- Tried and dropped (1.21.0 work, 2026-11-07): your totem's attack rhythm. Searing Totem attacked
-- every 2.42-2.46 s (16:45 log), and a chain of Fire hits on that beat looked like a way to find
-- its hits with no Combat Log: in the simulator a 5-man went from 68% to 90% shown. But in the
-- real log others' Fire hits kept the same 2.44 s beat as often as the author's (52 pairs vs 46: another
-- shaman's totem), and the rule took 26 of theirs to 16 of his. Two identical totems can't be told
-- apart by their beat.

-- Called for each hit a Combat Log line of yours stood for (not one taken while something was
-- in the air). line.periodic: the line's color is a periodic damage event's.
local function LearnFromLine(plate, hit, now, line)
    local school = (not hit.miss) and hit.school or nil
    if not school then return end
    if line.periodic then
        local list = dots[plate]
        if not list then return end
        for key, d in pairs(list) do
            local age = now - d.t0
            if not key:find("#prev", 1, true) and SpellSchool(d.name) == school and age > 0.5 and age <= DOT_WATCH then
                LearnExactDot(d.name, school, age)
            end
        end
        return
    end
    if school == 1 then return end
    for _, c in ipairs(ownCasts) do
        if math.abs(now - c.t) <= SAME_MOMENT then return end -- your cast's own hit
    end
    for _, sw in ipairs(swings) do
        local dt = now - sw.t
        if not sw.ranged and sw.plate == plate and dt >= 0 and dt <= PROC_MAX then
            return NoteSwingProc(school, dt)
        end
    end
end
FFT.LearnFromLine = LearnFromLine

-- While threat is readable: a hit of yours that no cast explains may be a tick of a spell you
-- cast on that mob. On a steady beat after the cast, it's learned as that spell's DoT.
-- hidden: threat is hidden, so anyone's hit could be among these. Then only a spell whose own
-- hit on this mob was seen (same moment, its school) learns, and it takes 3 ticks on the beat.
-- Returns the spell's name if this hit itself is one of those ticks (to show it).
local function LearnDot(plate, hit, now, hidden)
    local list = dots[plate]
    if not list then return end
    local tickOf
    for _, d in pairs(list) do
        local name = d.name
        local age = now - d.t0
        if age > 0.5 and age <= DOT_WATCH and (not hidden or d.confirmed) then
            local known = SpellSchool(name)
            local times
            if known then
                if known == hit.school then times = d.times end
            elseif not hidden then
                d.bySchool[hit.school] = d.bySchool[hit.school] or {}
                times = d.bySchool[hit.school]
            end
            if times then
                times[#times + 1] = age
                local found = ns.FindPeriod(times, 0.5, 0.2)
                if found and hidden and found.fits < 3 then found = nil end
                if found then
                    local k = math.floor(age / found.period + 0.5)
                    if k >= 1 and math.abs(age - k * found.period) <= 0.2 and not d.used[k] then
                        d.used[k] = true
                        tickOf = name
                    end
                    db.dotPeriods = db.dotPeriods or {}
                    local old = db.dotPeriods[name]
                    -- (1.21.0) a period learned from the Combat Log is a fact: a guess doesn't replace it
                    if not (old and old.exact) and (not old or math.abs(old.period - found.period) > 0.2 or found.ticks > old.ticks) then
                        db.dotPeriods[name] = {period = found.period, ticks = math.max(found.ticks, old and old.ticks or 0),
                            school = hit.school}
                        Log("  learned: %s ticks every %.2fs (school %d)%s", name, found.period, hit.school,
                            hidden and ", while threat was hidden" or "")
                    end
                end
            end
        end
    end
    return tickOf
end

-- While threat is readable: note which school your spells hit with, for the hidden times
local function LearnSchool(plate, hit, now)
    local school = hit.school
    if not school then return end
    -- right after your minion's cast the hit may be the minion's (your threat rises from your
    -- totem's damage too): too unclear to learn from
    for _, c in ipairs(minionCasts) do
        if now - c.t >= -SAME_MOMENT and now - c.t <= MINION_WINDOW then return end
    end
    local c = SameMomentCast(now, school)
    if not c then
        for _, f in ipairs(ownCasts) do
            local dt = now - f.t
            local known = SpellSchool(f.name)
            if not f.landed and f.plate == plate and dt > SAME_MOMENT and dt <= FLIGHT_WINDOW and school ~= 1
                and (known == nil or known == school) then
                c = f
                break
            end
        end
    end
    if not c then return LearnDot(plate, hit, now) end
    c.landed = true
    if c.plate == plate and dots[plate] and dots[plate][c.name] then dots[plate][c.name].confirmed = true end
    db.spellSchools = db.spellSchools or {}
    if db.spellSchools[c.name] ~= school then
        db.spellSchools[c.name] = school
        Log("  learned: %s hits as school %d", c.name, school)
    end
end
FFT.LearnSchool = LearnSchool

-- Is this hit (or miss) one of your own actions? Decided at the end of the frame, since a
-- cast and its hit can arrive in either order within one frame.
-- While threat is hidden: learn a spell's school from its own moment, but only when every hit
-- of that moment on the mob you cast at has the same school (Earth Shock landing with a
-- Flame Shock tick teaches nothing)
local function NoteMoment(c, plate, school)
    if c.plate ~= plate or not school then return end
    if dots[plate] and dots[plate][c.name] then dots[plate][c.name].confirmed = true end
    if SpellSchool(c.name) then return end
    if not c.momentSchools then
        c.momentSchools = {}
        C_Timer.After(0.05, function()
            local only, count = nil, 0
            for sch in pairs(c.momentSchools) do only, count = sch, count + 1 end
            if count == 1 then
                db.spellSchools = db.spellSchools or {}
                db.spellSchools[c.name] = only
                Log("  learned: %s hits as school %d (its own moment)", c.name, only)
            end
        end)
    end
    c.momentSchools[school] = true
end

-- Not a cast's or a swing's: a flying spell landing, a DoT tick, or someone else's
local function MatchRest(plate, hit, now)
    local school = hit.school
    -- (1.21.0, setting fallbackV2) only what the Combat Log taught for sure: see "What the Combat
    -- Log teaches for when it's gone"
    local v2 = db.fallbackV2
    if v2 and not hit.miss and school and school ~= 1 then
        local sw, dt = ProcSwingFor(plate, school, now, hit)
        if sw then
            sw.procUsed = true
            return ShowHit(plate, hit, ("your swing's proc, %.2fs after it"):format(dt))
        end
    end
    if school and school ~= 1 then
        local f = FlightFor(plate, school, now)
        if f then
            f.landed = true
            return ShowHit(plate, hit, ("your %s, %.1fs in flight"):format(f.name, now - f.t))
        end
    end
    -- A DoT tick right on its beat first: in the 1.14.1 log (16:47) a Flame Shock tick 0.04s off
    -- its beat landed inside the totem's window and was taken as the totem's, and the totem's
    -- real hit then was taken as the tick. Ticks further off the beat are checked after.
    if not hit.miss then
        local name, k = DotFor(plate, school, now, DOT_ON_BEAT, v2)
        if name then return ShowHit(plate, hit, ("your %s tick %d"):format(name, k)) end
    end
    -- before the flight votes, so your totem's hits don't teach your flying spells a school
    local m, dt = MinionFor(plate, hit, now)
    if m then
        if m.plate then m.claimed[plate] = true else m.any = true end
        if not db.showPet then
            Log("  drop %s (your %s, but pets are off)", S(hit.text), m.name)
            return
        end
        -- totems and guardians show in their spell's school color (the author's choice, 1.14.3); your
        -- pet keeps the pet color, as its other hits do
        return ShowHit(plate, hit, ("your %s (%s), %.2fs after its cast%s"):format(m.name, m.unit, dt,
            m.plate and ", its target" or ""), m.unit == "pet" and "pet" or nil)
    end
    if school and school ~= 1 then VoteFlight(plate, school, now) end
    if not hit.miss and not v2 then
        local name, k = DotFor(plate, school, now)
        if name then return ShowHit(plate, hit, ("your %s tick %d"):format(name, k)) end
        VoteMinion(plate, hit, now)
        -- not known yet: maybe it's teaching one of your DoTs its beat
        local learned = school and LearnDot(plate, hit, now, true)
        if learned then return ShowHit(plate, hit, ("your %s tick, just learned"):format(learned)) end
    end
    Log("  drop %s (not one of your actions)", S(hit.text))
end

------------------------------------------------------------------------
-- Combat Log mode (1.15.0): the game's own Combat Log says when you acted
------------------------------------------------------------------------
-- From Blizzard's Forever code (wow-ui-source forever 1.60.1.70790): Blizzard_CombatLogProcessor
-- turns every combat event that passes the Combat Log's current filter into
-- COMBAT_LOG_MESSAGE(text, r, g, b, order). The text can't be read, but r, g, b are plain numbers
-- (CombatLogSecureDocumentation), and the line's color comes from the filter's settings
-- (GenerateMessage: by source unit, or by event with lineColorPriority 3). The filters are
-- Blizzard_CombatLog's saved variable Blizzard_CombatLog_Filters, which addons can read.
-- Seen in game (1.14.5 probe log, 2026-11-06 17:10, in a group, Combat Log window hidden):
--   - C_CombatLog.SetFilteredEventsEnabled(true) from the addon turned the messages on
--   - with a filter of only your and your pet's/guardians' actions, a message came for each of
--     your casts, DoT ticks, Searing Totem's attacks and heals, and none for the hunter's hits
--   - a spell's, tick's or totem's message comes in the same moment as its UNIT_COMBAT hit
--     (at most 0.039s apart); a swing's comes with PLAYER_SWING, 0.46s before its hit
--   - it showed the old matching wrong twice: a hunter's Nature ticks taken as "Earth Shock
--     ticks", and a hunter's hit taken as a Lightning Bolt (no Combat Log message at either)
-- So: a hit is yours when one of your Combat Log messages came with it. Swings keep using
-- PLAYER_SWING. One message stands for one hit. Which mob it was can't be told: if two hits
-- land in the very same moment and only one is yours, either may be shown.
local CLOG_WINDOW = 0.06 -- a message and its hit: the same moment, or up to 0.039s apart (seen)
-- (1.19.0) A line never comes after its hit: in every log so far a matched line came in its hit's
-- frame (40 of 42) or before it (2: -0.007 s, -0.058 s), none after. Taking lines from after a hit
-- let someone else's hit 1-3 frames before yours take your line: in the raid simulator (sim/,
-- 39 others) that was 135 of 151 wrong numbers; with this rule, shown 52% -> 77%, wrong 48% -> 23%.
-- If a line ever does come after its hit, that hit is dropped (precision over recall).
local LINE_AFTER_HIT = 0.001 -- the same frame (one GetTime) counts as with the hit
local clogMsgs = {}      -- {t, kind = "damage" | "swing" | "other" | "any", used}
-- 1.15.2: a projectile's line comes when the game decides the hit, its number when it lands:
-- Searing Totem's lines came 0.07-0.37s before their hits (1.15.1 log, 18:30). A hit with no line
-- in its moment may take an earlier unused line, but only while something of yours of its school
-- is in the air (see InTheAir), so a groupmate's hit of another school can't take it.
local CLOG_LOOKBACK = 0.5
local clog = {why = "not checked yet", ownSinceMsg = 0}
local SAME_FRAME = 0.002 -- events of one frame share one GetTime()

-- (1.20.0) When each of your casts finished (UNIT_SPELLCAST_SUCCEEDED "player", any spell), to tell
-- your cast lines from your totem's or pet's: the filter sends SPELL_CAST_SUCCESS for both. In the
-- dungeon log (2026-11-07 16:31) every cast of yours came in the same frame as its cast line (27 of
-- 27); the other 36 cast lines came with none, every ~2.4 s: Searing Totem's attacks.
local ownCastTimes = {}
function FFT:NoteCastFinished()
    local now = GetTime()
    ownCastTimes[#ownCastTimes + 1] = now
    while ownCastTimes[1] and now - ownCastTimes[1] > 3 do table.remove(ownCastTimes, 1) end
end

-- What a Combat Log event name means for matching
local function EventKind(event)
    -- melee: a swing's own miss is kept apart from its hit (1.17.0, for pets' and extra attacks' lines)
    if event:find("^SWING_MISSED") then return "swingMiss" end
    if event:find("^SWING_") then return "swing" end
    if event:find("CAST_SUCCESS") then return "cast" end -- (1.17.0) never stands for a hit
    -- (1.31.0) your dispels and broken crowd control (OWN_EVENTS): never stand for a hit
    if event:find("DISPEL_FAILED") then return "dispelFailed" end
    if event:find("STOLEN") then return "steal" end
    if event:find("AURA_BROKEN") then return "broke" end
    if event:find("DISPEL_DEBUFF") then return "cleanse" end
    if event:find("DISPEL") then return "purge" end
    if event:find("MISSED") then return "miss" end   -- SPELL_MISSED_RESIST, DAMAGE_SHIELD_MISSED...
    if event:find("DURABILITY") then return "other" end
    if event:find("DAMAGE") or event:find("LEECH") then return "damage" end -- LEECH: Drain Life-type (1.17.0)
    if event:find("INTERRUPT") then return "interrupt" end -- (1.16.0)
    if event:find("PERIODIC_HEAL") then return "hot" end -- (1.15.6)
    if event:find("HEAL") then return "heal" end
    if event == "PARTY_KILL" then return "kill" end -- (1.22.1) your killing blow; never stands for a hit
    return "other"
end

-- Can a line of this kind stand for this hit? A miss line only for a miss, a damage line only
-- for a hit that did damage (1.15.3; "any" when the filter's colors can't tell the kinds).
-- (1.30.8) Never a glancing hit: only white swings glance. The game's file of the author's
-- 2026-11-11 dungeon run: 0 of 12,167 spell, DoT and ranged damage events glancing, 462 of 4,275
-- swings. There a groupmate's glancing swing took a Windfury line in its frame (40135.248) or in a
-- Windfury slot (40559.032), and the author's second Windfury attack was dropped each time.
local function KindFits(kind, hit)
    if kind == "any" then return true end
    if hit.miss then return kind == "miss" end
    return kind == "damage" and not hit.glancing
end

-- Which schools each line color has stood for, learned this session from moments with just one
-- hit and one line of yours: Thorns' "damage shield" color was always Nature, for example.
-- Used only to choose when hits outnumber your lines in a moment. Kept per session: it depends on
-- the character's spells.
local lineSchools = {} -- color key -> school -> count

local function LineKnows(m, school)
    local s = school and lineSchools[m.key]
    return s and (s[school] or 0) >= 2 or false
end

local function SameColor(c, r, g, b)
    return type(c) == "table" and type(c.r) == "number" and math.abs(c.r - r) < 0.02
        and math.abs(c.g - g) < 0.02 and math.abs(c.b - b) < 0.02
end

-- Works out, from the Combat Log's current filter, whether its messages can tell yours:
-- "mine" when it only passes your and your pet's/guardians' actions, "color" when it also passes
-- what's done to you but colors each line by its source, otherwise not usable. With lines colored
-- by event, the color also tells what kind of event it was.
function FFT:ClogCheckFilter()
    clog.mode, clog.byEvent, clog.mineColors = nil, nil, nil
    local all = _G.Blizzard_CombatLog_Filters
    local f = type(all) == "table" and type(all.filters) == "table" and all.filters[all.currentFilter]
    local mine, pet = _G.COMBATLOG_FILTER_MINE, _G.COMBATLOG_FILTER_MY_PET
    if type(f) ~= "table" or type(f.filters) ~= "table" or not mine or not pet then
        clog.why = "the game's Combat Log isn't loaded"
        return
    end
    local sourceOnly = true
    for _, sub in pairs(f.filters) do
        if type(sub) == "table" then
            local hasSource, hasDest = false, false
            for flag, on in pairs(type(sub.sourceFlags) == "table" and sub.sourceFlags or {}) do
                if on then
                    hasSource = true
                    if flag ~= mine and flag ~= pet then
                        clog.why = "the Combat Log filter shows other people's actions too"
                        return
                    end
                end
            end
            for _, on in pairs(type(sub.destFlags) == "table" and sub.destFlags or {}) do
                if on then hasDest = true end
            end
            -- (1.17.0) a part whose flag lists are there but all off passes no one else's actions:
            -- Blizzard's ApplyFilterSettings gives zero flags an empty event list with
            -- COMBATLOG_FILTER_MINE (its "HACK", Blizzard_CombatLogProcessor.lua). "My actions" has
            -- such a part. Only a part with no flag lists at all passes everyone's.
            if not hasSource and not hasDest and type(sub.sourceFlags) ~= "table" and type(sub.destFlags) ~= "table" then
                clog.why = "the Combat Log filter shows everyone's actions"
                return
            end
            if hasDest then sourceOnly = false end
        end
    end
    local settings = type(f.settings) == "table" and f.settings or {}
    local colors = type(f.colors) == "table" and f.colors or {}
    if sourceOnly then
        clog.mode = "mine"
    elseif settings.lineColoring and settings.lineColorPriority == 1 and type(colors.unitColoring) == "table" then
        local mc = {colors.unitColoring[mine], colors.unitColoring[pet]}
        for flag, c in pairs(colors.unitColoring) do
            if flag ~= mine and flag ~= pet and type(c) == "table" then
                for _, m in ipairs(mc) do
                    if SameColor(m, c.r, c.g, c.b) then
                        clog.why = "in the Combat Log your lines have the same color as others'"
                        return
                    end
                end
            end
        end
        clog.mode, clog.mineColors = "color", mc
    else
        clog.why = "the Combat Log filter also shows what's done to you, and its colors can't tell whose"
        return
    end
    -- lines colored by event: their color tells the event (with highlighting as the game does it)
    if sourceOnly and settings.lineColoring and settings.lineColorPriority == 3 and type(colors.eventColoring) == "table" then
        local byEvent = {}
        for event, c in pairs(colors.eventColoring) do
            if type(event) == "string" and type(c) == "table" and type(c.r) == "number" then
                local r, g, b = c.r, c.g, c.b
                if settings.lineHighlighting and type(colors.highlightedEvents) == "table" and colors.highlightedEvents[event] then
                    r, g, b = math.min(r * 1.5, 1), math.min(g * 1.5, 1), math.min(b * 1.5, 1)
                end
                byEvent[#byEvent + 1] = {r = r, g = g, b = b, kind = EventKind(event),
                    periodic = event:find("PERIODIC") ~= nil} -- (1.21.0) a DoT's tick
            end
        end
        clog.byEvent = byEvent
    end
    clog.why = nil
end

-- Turns the messages on (they go off whenever the Combat Log window hides)
function FFT:ClogStart()
    if not db.useCombatLog then clog.mode = nil; clog.why = "turned off in the options"; return end
    self:ClogCheckFilter()
    if not clog.mode then return end
    if Plain(C_CombatLog.AreFilteredEventsEnabled()) ~= true then
        local ok = pcall(C_CombatLog.SetFilteredEventsEnabled, true)
        Log("Combat Log messages turned on (%s)", ok and "ok" or "error")
    end
end

-- 1.17.0: kept on every 2 seconds. Before,
-- only at login and as a fight started: a Combat Log window hidden mid-fight (a chat tab clicked)
-- turned the lines off until the next fight, and every hit in between went to the fallback.
function FFT:ClogKeepOn()
    if not (db and db.enabled and db.useCombatLog and clog.mode) then return end
    if Plain(C_CombatLog.AreFilteredEventsEnabled()) == false then
        local ok = pcall(C_CombatLog.SetFilteredEventsEnabled, true)
        Log("Combat Log messages had gone off (its window hid?): turned back on (%s)", ok and "ok" or "error")
    end
end

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
FFT.DISPEL_KINDS = {purge = true, cleanse = true, steal = true, dispelFailed = true, broke = true}
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

-- At PLAYER_LOGOUT only (see above)
function FFT:WriteOwnClogFilter()
    local saved = _G.Blizzard_CombatLog_Filters
    local mine, pet = _G.COMBATLOG_FILTER_MINE, _G.COMBATLOG_FILTER_MY_PET
    if type(saved) ~= "table" or type(saved.filters) ~= "table" or not mine or not pet then return end
    local index = OwnFilterIndex(saved)
    if not (db.enabled and db.useCombatLog and db.ownClogFilter) then
        -- turned off: give the Combat Log back the filter it had before ours
        if index and saved.currentFilter == index then
            local prev = db.clogPrevFilter
            saved.currentFilter = (type(prev) == "number" and prev ~= index and saved.filters[prev]) and prev or 1
        end
        return
    end
    if saved.currentFilter ~= index then db.clogPrevFilter = saved.currentFilter end
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

function FFT:ClogActive()
    if not clog.mode then return false end
    if Plain(C_CombatLog.AreFilteredEventsEnabled()) ~= true then return false end
    -- messages stopped (somewhere the game restricts them?): 4 of your swings and attack casts in a
    -- row brought none, so the other ways of matching take over until one comes. Counted, not
    -- timed: in the 1.15.1 log a fight opened with Purge (no damage line) after a long quiet
    -- spell, and a time rule wrongly switched over. Your swings always bring a line.
    if clog.ownSinceMsg >= 4 then return false end
    return true
end

function FFT:ClogStatus()
    local pending = ""
    if db.useCombatLog and db.ownClogFilter and self:OwnFilterInUse() == false then
        pending = " The addon's own Combat Log filter (Forever Floating Text) takes over after your next /reload or login."
    end
    if not clog.mode then return "not used: " .. tostring(clog.why) .. "." .. pending end
    if not self:ClogActive() then
        if Plain(C_CombatLog.AreFilteredEventsEnabled()) ~= true then return "its messages are off (/fft clog turns them on)" end
        return "your last swings and casts brought no lines: matching by your swings, casts and threat meanwhile"
    end
    -- (1.17.1) say whether lines are colored by event: "only your actions" alone read like
    -- Blizzard's "My actions" filter in the 2026-11-07 log, though Forever Floating Text was in use
    local mode = clog.mode == "mine" and "the filter shows only your actions" or "your lines are told apart by their color"
    if clog.byEvent then mode = mode .. ", colored by event" end
    return ("in use (%s).%s"):format(mode, pending)
end

-- (1.21.2) Said in chat once per session, the first time a hit in a group goes to the fallback
-- while the Combat Log is meant to be used. Since 1.21.0 the fallback shows only hits it's sure of,
-- so fewer numbers show, and without a word that looks like the addon broke (the author chose this).
-- Not solo: there your threat still tells your hits. Not with the Combat Log turned off in the
-- options: that was chosen. The reason is ClogStatus's, the same /fft status gives.
local fallbackNoticed = false
function FFT:FallbackNotice()
    if fallbackNoticed or not db.useCombatLog or not IsInGroup() then return end
    fallbackNoticed = true
    local status = self:ClogStatus()
    Print("Combat Log: " .. status)
    Print("  " .. (db.fallbackV2 and "Until it's back, only hits that are surely yours show, so fewer numbers show."
        or "Until it's back, your hits are matched by your swings, casts and threat, less surely in a group.")
        .. " /fft clog checks it again, /fft status says more. (Said once per session.)")
    Log("fallback notice said: %s", status)
end

-- A Combat Log message: keep it if it's one of yours
-- Second value (1.21.0): true when every event of that color is periodic (a DoT's tick)
local function ClogKind(r, g, b)
    if not clog.byEvent then return "any", false end
    local kind, periodic
    for _, e in ipairs(clog.byEvent) do
        if SameColor(e, r, g, b) then
            if kind and kind ~= e.kind then return "any", false end
            kind = e.kind
            periodic = (periodic == nil or periodic) and e.periodic
        end
    end
    return kind or "any", periodic == true
end

-- 1.17.0: Blizzard replays old lines into its Combat Log window (Blizzard_CombatLog loading at login
-- or /reload, a filter button clicked, chat settings changed: RefilterEntries) as COMBAT_LOG_MESSAGE
-- too, one per frame, with order = Oldest (CombatLogSecureDocumentation: payload message, r, g, b,
-- order; CombatLogProcessor:ProcessCurrentEntry). They're history: taken as new, someone else's hit
-- could take one, so they're skipped. A secret order can't be told, so such a line counts as new (logged once).
local ORDER_OLDEST = (Enum and Enum.CombatLogMessageOrder and Enum.CombatLogMessageOrder.Oldest) or 1
local lastReplay = 0

-- (1.31.13) A probe for what isn't known yet, log only and only while /fft debug records: what is
-- a Combat Log line's text to an addon? COMBAT_LOG_MESSAGE's message is "a preformatted combat log
-- message protected by a |K string wrapper" (CombatLogSecureDocumentation.lua). Its type, whether
-- it is a secret value, its length and start when it isn't, and whether a font string takes it (one
-- made for this, never shown): the first 5 lines of a recording and (1.31.14) the first 2 of every
-- fight after, as the first answer scrolled out of the saved log (2026-11-13 20:11).
-- (1.31.14) The other probe is answered and gone: groupmates' casts do reach an addon in a dungeon
-- (UNIT_SPELLCAST_SUCCEEDED for party1-4), but only spells with a cast time, and with the spell
-- hidden. In the 20:11 log 125 came in 23.7 minutes: a priest's heals, a hunter's Aimed Shot, a
-- rogue's dynamite and poisons; no instant of the rogue's or the warrior's, so nothing that tells a
-- groupmate's melee hit from yours.
FFT.Probe = {}
function FFT.Probe.Line(text)
    local probe = FFT.probe
    if not logging or probe.lines >= 5 then return end
    probe.lines = probe.lines + 1
    local secret = IsSecret(text)
    local what = ""
    if not secret and type(text) == "string" then
        what = (", length %d, starts %q"):format(#text, text:sub(1, 60))
    end
    if not probe.fs then
        probe.fs = holder:CreateFontString(nil, "OVERLAY")
        probe.fs:SetFont(STANDARD_TEXT_FONT, 12, "")
        probe.fs:Hide()
    end
    local drawn = pcall(probe.fs.SetText, probe.fs, text)
    Log("probe: line text is a %s, secret %s%s; SetText %s", type(text), tostring(secret), what, drawn and "took it" or "refused it")
end

function FFT:OnClogMessage(r, g, b, order)
    if not clog.mode then return end
    if IsSecret(order) then
        if not clog.orderSecretSeen then Log("Combat Log line with a secret order: can't tell replayed ones") end
        clog.orderSecretSeen = true
    elseif order == ORDER_OLDEST then
        clog.replayed = (clog.replayed or 0) + 1
        local now = GetTime()
        if now - lastReplay > 2 then Log("Combat Log is replaying old lines (skipped)") end
        lastReplay = now
        return
    end
    r, g, b = Plain(r), Plain(g), Plain(b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
    if clog.mode == "color" and not (SameColor(clog.mineColors[1], r, g, b) or SameColor(clog.mineColors[2], r, g, b)) then
        return
    end
    local now = GetTime()
    clog.ownSinceMsg = 0
    local kind, periodic = ClogKind(r, g, b)
    local proc = kind == "cast" and FFT.procCastAt and math.abs(now - FFT.procCastAt) <= SAME_FRAME or nil
    if proc then FFT.procCastAt = nil end -- (1.31.0) one line for one notice (FFT.NoteProcCast)
    clogMsgs[#clogMsgs + 1] = {t = now, kind = kind, periodic = periodic, key = ("%.2f %.2f %.2f"):format(r, g, b),
        proc = proc}
    while clogMsgs[1] and now - clogMsgs[1].t > 2 do table.remove(clogMsgs, 1) end
    Log("your Combat Log line: %s (%.2f %.2f %.2f, order %s)", kind, r, g, b, S(order))
    -- (1.22.1) only when the color says PARTY_KILL for sure (filter colored by event): replayed
    -- lines were skipped above, and "any" (colors can't tell) never counts
    if kind == "kill" and self.OnKillingBlow then self:OnKillingBlow() end
    if FFT.DISPEL_KINDS[kind] and self.OnDispelLine then self:OnDispelLine(kind) end -- (1.31.0) Notices.lua
end

function FFT:NoteOwnAction() clog.ownSinceMsg = clog.ownSinceMsg + 1 end

-- (1.31.0) The game's proc notice (Procs.lua) at t: the game also logs the proc as a cast of yours
-- (SPELL_CAST_SUCCESS "Maelstrom Ready!", 408501, the author's 2026-11-12 09:01 file), so a cast line
-- comes in that frame with no cast of yours: what a totem's attack looks like in a dungeon
-- (MinionCastLine, TotemLinesOwed). That line is marked as the proc's, whichever comes first.
FFT.NoteProcCast = function(t)
    for i = #clogMsgs, 1, -1 do
        local m = clogMsgs[i]
        if math.abs(m.t - t) > SAME_FRAME then break end
        if m.kind == "cast" and not m.proc then m.proc = true; return end
    end
    FFT.procCastAt = t -- its line hasn't come yet
end

-- When the kind of a message can't be told, a swing's own message (it comes with PLAYER_SWING)
-- is set aside so it can't stand for someone else's hit in that moment
local function SetAsideSwingMessages()
    for _, sw in ipairs(swings) do
        if not sw.clogDone then
            sw.clogDone = true
            for _, m in ipairs(clogMsgs) do
                if not m.used and m.kind == "any" and math.abs(m.t - sw.t) <= 0.02 then
                    m.used = true
                    break
                end
            end
        end
    end
end

-- Heals.lua asks (1.15.6): is there an unused heal line of yours with this heal? Returns how far
-- apart they were and the line's kind ("heal", "hot", or "any" when colors can't tell), or nil.
-- A heal's line came 0.006-0.007s before its UNIT_COMBAT in the logs (2026-11-06, Healing Wave and
-- First Aid ticks), so the same window as for damage.
function FFT:ClogTakeHealLine(now)
    SetAsideSwingMessages()
    local best, bestD
    for _, m in ipairs(clogMsgs) do
        local d = math.abs(m.t - now)
        if not m.used and d <= CLOG_WINDOW and (m.kind == "heal" or m.kind == "hot" or m.kind == "any")
            and (not best or d < bestD) then
            best, bestD = m, d
        end
    end
    if not best then return nil end
    best.used = true
    return best.t - now, best.kind
end
FFT.CLOG_WINDOW = CLOG_WINDOW

-- Can the Combat Log's line colors tell event kinds apart (the filter colors lines by event)?
function FFT:ClogKindsKnown() return clog.byEvent ~= nil end

-- An unused interrupt line of yours near this moment (1.16.0); how far apart, or nil
function FFT:ClogTakeInterruptLine(now)
    local best, bestD
    for _, m in ipairs(clogMsgs) do
        local d = math.abs(m.t - now)
        if not m.used and d <= CLOG_WINDOW and m.kind == "interrupt" and (not best or d < bestD) then
            best, bestD = m, d
        end
    end
    if not best then return nil end
    best.used = true
    return best.t - now
end

-- Something of yours of this school still on its way: your totem's or pet's attack (its cast up
-- to 1.5s before: Searing Totem's cast-to-hit was up to 1.11s in the 1.15.1 log) or a spell of
-- yours not landed yet. Instant casts are marked landed when their hit is matched (MarkLanded).
-- (1.20.0) Is this school one your totems or pet were seen to attack with (learned by spell ID)?
local function IsMinionSchool(school)
    for _, s in pairs(db.minionSchools or {}) do
        if s == school then return true end
    end
    return false
end

-- (1.20.0) A cast line of yours with no cast of yours in its frame: your totem's or pet's attack,
-- seen without its nameplate (in dungeons there is none, so its late hits were dropped: 4 of 4
-- in the 2026-11-07 16:31 log, 0.07-0.18 s after their damage lines). Cast line to damage line was
-- 0-0.53 s there, damage line to hit 0-0.18 s; cast to hit up to 1.11 s before (1.15.1 log).
-- One such line stands for one late hit. Returns the line, or nil.
local function MinionCastLine(now)
    for _, m in ipairs(clogMsgs) do
        local dt = now - m.t
        if m.kind == "cast" and not m.airUsed and not m.proc and dt > 0 and dt <= 1.5 then
            local lines, own, used = 0, 0, 0
            for _, x in ipairs(clogMsgs) do
                -- (1.31.0) a game proc's cast line is neither yours nor a totem's (FFT.NoteProcCast)
                if x.kind == "cast" and not x.proc and math.abs(x.t - m.t) <= SAME_FRAME then
                    lines = lines + 1
                    if x.airUsed then used = used + 1 end
                end
            end
            for _, t in ipairs(ownCastTimes) do
                if math.abs(t - m.t) <= SAME_FRAME then own = own + 1 end
            end
            if lines - own > used then
                m.name = m.name or "totem's or pet's attack"
                return m
            end
        end
    end
end

local function InTheAir(school, now)
    if not school or school == 1 then return nil end
    for _, c in ipairs(minionCasts) do
        local dt = now - c.t
        if not c.clogUsed and dt >= 0 and dt <= 1.5 and MinionSchool(c.id) == school then return c end
    end
    -- only a school your totem or pet was seen to use: anyone's Fire hit could otherwise take it
    if IsMinionSchool(school) then
        local line = MinionCastLine(now)
        if line then return line end
    end
    for _, c in ipairs(ownCasts) do
        local dt = now - c.t
        if not c.landed and dt > SAME_MOMENT and dt <= FLIGHT_WINDOW and SpellSchool(c.name) == school then return c end
    end
end

-- A hit of yours was matched: what it was the hit of is no longer on its way
-- (1.31.13) In the cast's own moment only a hit that can be the cast's: not one of another school
-- than the spell was learned to hit as. The author's 2026-11-13 10:28 dungeon log, 183317.268: an
-- instant Lightning Bolt cast in the frame of a Flame Shock tick; the tick's hit marked the bolt
-- landed, so the bolt's own Nature hit (183317.464, its line 0.047 s before) found nothing in the
-- air and was dropped.
local function MarkLanded(school, now)
    for _, c in ipairs(ownCasts) do
        if not c.landed and math.abs(now - c.t) <= SAME_MOMENT then
            local known = SpellSchool(c.name)
            if not (school and known and known ~= school) then c.landed = true; return end
        end
    end
    if not school then return end
    for _, c in ipairs(ownCasts) do
        local dt = now - c.t
        if not c.landed and dt > SAME_MOMENT and dt <= FLIGHT_WINDOW and SpellSchool(c.name) == school then
            c.landed = true
            return
        end
    end
    -- (a totem's attack is only used up by a late match: a DoT tick of its school in its line's
    -- moment can't be told from the totem's own hit, and mustn't use it up)
end

-- The unused line of yours that can stand for this hit: one in its moment (the closest), or else
-- an earlier one while something of yours of its school is in the air (the oldest, as lines come
-- in the order of their hits). Returns the line, and what was in the air if that was needed.
-- (in its moment, a line whose color has stood for this hit's school goes first)
-- (1.28.14) A line from an earlier frame counts only while something of yours of the hit's school
-- is in the air, as the older lines below do. The author's 2026-11-10 15:25 dungeon log, with the
-- game's own combat log file saying whose each hit was: of 262 hits shown by a line, 249 had it in
-- their own frame (246 the author's, the other 3 hits in one frame with one of theirs) and 13 had
-- it 0.007-0.059 s before: 6 Searing Totem's (its attack was in the air) and 7 someone else's,
-- most of them taking a Windfury proc's lines, which wait 0.23 s for their own hits (17824.661:
-- two lines, a tank's damage shield 0.010 s and the tank's swing 0.037 s later shown, both Windfury hits
-- then dropped).
local function ClogFind(now, hit)
    SetAsideSwingMessages()
    local school = (not hit.miss) and hit.school or nil
    local best, bestD, bestKnows, bestEarly
    local air, asked
    for _, m in ipairs(clogMsgs) do
        local d = math.abs(m.t - now)
        if not m.used and d <= CLOG_WINDOW and m.t - now <= LINE_AFTER_HIT and KindFits(m.kind, hit) then
            local early = now - m.t > SAME_FRAME
            if early and not asked then
                asked = true
                air = (not hit.miss) and InTheAir(hit.school, now) or nil
            end
            if not early or air then
                local knows = LineKnows(m, school)
                if not best or (bestEarly and not early)
                    or (early == bestEarly and ((knows and not bestKnows) or (knows == bestKnows and d < bestD))) then
                    best, bestD, bestKnows, bestEarly = m, d, knows, early
                end
            end
        end
    end
    if best then return best, bestEarly and air or nil end
    if hit.miss then return nil end
    if not asked then air = InTheAir(hit.school, now) end
    if not air then return nil end
    for _, m in ipairs(clogMsgs) do
        local d = now - m.t
        -- (1.20.0) never a line from before that cast: it was some other hit's
        if not m.used and d > CLOG_WINDOW and d <= CLOG_LOOKBACK and KindFits(m.kind, hit)
            and not (air.t and m.t < air.t - SAME_FRAME) then
            return m, air
        end
    end
end

-- How many of your unused lines in this hit's moment could stand for it, and does one of them
-- know its school (for choosing, see ClogResolveFrame)
local function LinesInMoment(now, hit)
    local n, knows = 0, false
    local school = (not hit.miss) and hit.school or nil
    local air, asked
    for _, m in ipairs(clogMsgs) do
        local fits = not m.used and math.abs(m.t - now) <= CLOG_WINDOW and m.t - now <= LINE_AFTER_HIT
            and KindFits(m.kind, hit)
        if fits and now - m.t > SAME_FRAME then -- (1.28.14) from an earlier frame: see ClogFind
            if not asked then
                asked = true
                air = (not hit.miss) and InTheAir(hit.school, now) or nil
            end
            fits = air ~= nil
        end
        if fits then
            n = n + 1
            if LineKnows(m, school) then knows = true end
        end
    end
    return n, knows
end

------------------------------------------------------------------------
-- Lines that come long before their hits (1.17.0)
------------------------------------------------------------------------
-- Melee lines come when the game decides the blow, its hit with the animation later (your swing:
-- 0.46 s, these logs). So each melee line gets a role once its frame is over. One per PLAYER_SWING of
-- yours in that frame is your swing's (matched by the swing timer, as before); any other is an
-- "orphan": your pet's swing or an extra attack of yours (Windfury, Sword Specialization), which
-- send no PLAYER_SWING. Seen there: a Succubus's blows came 0.57-1.0 s after their lines; extra
-- attacks are predicted to land like swings (not yet seen in any log).
-- Also from there: a shot's (Auto Shot, wand) hit comes after its PLAYER_SWING (an estimate: not in the author's
-- logs yet). A proc on your swing could land with the swing's hit; the 1.17.0 solo log (2026-11-07 08:39, 382728-382741) says no for Flametongue: all 5 of its
-- hits came in the same frame as their line (4 in the swing's own frame, 1 at +0.12 s), 0.46 s
-- before the swing's hit, and matched by the plain rule. So late lines are taken only from shots.
local ORPHAN_MIN = 0.38         -- an estimate (no such hit in the author's logs yet)
local ORPHAN_LATE = 0.65        -- an extra attack: like your swing's 0.43-0.47 s, with room
local PET_LATE = 1.2            -- your pet's blow: an estimate
local SHOT_LATE = 2.0           -- a shot flies: an estimate

local function IsMelee(m) return m.kind == "swing" or m.kind == "swingMiss" end

local function MeleeRole(m)
    if m.role then return m.role end
    local own = 0
    for _, sw in ipairs(swings) do
        if not sw.ranged and math.abs(sw.t - m.t) <= SAME_FRAME then own = own + 1 end
    end
    for _, x in ipairs(clogMsgs) do
        if IsMelee(x) and math.abs(x.t - m.t) <= SAME_FRAME then
            if own > 0 then x.role, own = "own", own - 1 else x.role = "orphan" end
        end
    end
    return m.role or "orphan"
end

-- An unused line of yours from the frame of one of your shots at this mob, for a later hit on it.
-- Only ranged shots (1.17.1): a melee proc's hit comes with its line (Flametongue, see above).
-- Never a melee line and never one the hit's own moment could still claim.
local function SwingFrameLine(plate, hit, now)
    for _, sw in ipairs(swings) do
        local dt = now - sw.t
        if sw.ranged and sw.plate == plate and dt > CLOG_WINDOW and dt <= SHOT_LATE then
            for _, m in ipairs(clogMsgs) do
                if not m.used and not IsMelee(m) and KindFits(m.kind, hit) and math.abs(m.t - sw.t) <= 0.05
                    and now - m.t > CLOG_WINDOW then
                    return m, sw
                end
            end
        end
    end
end

-- Is your pet out and on this mob? Its target can be read as "your target", or by comparing tokens
-- where the game allows (compound tokens are secret on restricted maps: then only your target).
local function PetOn(plate, unit)
    if not Plain(UnitExists("pet")) then return false end
    if plate == FFT.TargetPlate() then return true end
    if not unit then return false end
    local ok, same = pcall(UnitIsUnit, "pettarget", unit)
    return ok and Plain(same) == true
end

-- An orphan melee line for a physical hit or a miss with no line of its own: the oldest one far
-- enough back. Returns the line and "pet" when it was your pet's, or nil for your extra attack.
-- Only on your target or your pet's: a pet's or an extra swing is at one of those.
local function OrphanSwingLine(plate, unit, hit, now)
    if not clog.byEvent then return nil end -- melee lines can only be told by their color
    if not (hit.miss or hit.school == 1) then return nil end
    local pet = PetOn(plate, unit)
    if not pet and plate ~= FFT.TargetPlate() then return nil end
    local late = pet and PET_LATE or ORPHAN_LATE
    local want = hit.miss and "swingMiss" or "swing"
    for _, m in ipairs(clogMsgs) do
        local gap = now - m.t
        if not m.used and m.kind == want and gap >= ORPHAN_MIN and gap <= late and MeleeRole(m) == "orphan" then
            return m, pet and "pet" or nil
        end
    end
end

-- Has something of yours hit with this school just now? Your spell in flight or its cast,
-- your DoT on this mob, your totem's attack. Schools as learned before (spellSchools, minionSchools).
local function RecentSchool(plate, school, now)
    if not school then return false end
    for _, c in ipairs(ownCasts) do
        if now - c.t <= FLIGHT_WINDOW and SpellSchool(c.name) == school then return true end
    end
    for _, c in ipairs(minionCasts) do
        local dt = now - c.t
        if dt >= -SAME_MOMENT and dt <= MINION_WINDOW and MinionSchool(c.id) == school then return true end
    end
    for _, d in pairs(dots[plate] or {}) do -- a recast's previous cast ("#prev") may still tick too
        if now - d.t0 <= DOT_WATCH and SpellSchool(d.name) == school then return true end
    end
    return false
end

-- Hits are decided together in batches: all that come within CLOG_WINDOW of the first one
-- (1.15.4; before, each frame on its own). When there are more hits than your lines, a hit whose
-- school matches something of yours goes first: in the 1.14.5 probe log (17:10, 334225.859) your
-- totem's Fire hit and the hunter's Nature hit came in one frame with one line of yours; in the
-- 1.15.3 log (19:10, 341434.343) a hunter's Physical hit took your Lightning Bolt's line one frame
-- (7ms) before the bolt's own Nature hit came, which then had none.
-- Each batch is decided once, CLOG_WINDOW after its first hit (1.23.3: no second look, see ClogDecide).
local clogPending = {}

-- Where a hit's nameplate was when the hit came. Deciding takes up to CLOG_WINDOW; if the plate is
-- gone by then (the mob died: plates go when units do), the number shows where it was, as
-- DetachPlate does for numbers already up.
local function PlateAnchor(plate)
    local cx, top, s = PlatePlace(plate)
    if not cx then return nil end -- secret in dungeons: such a number is then only logged
    return cx * s, top * s + (db.offsetY or 0)
end

-- who: "pet" for your pet's hit (its color)
local function ShowClogHit(p, why, who)
    if p.hit.crit then FFT.critAt[p.plate] = GetTime() end -- (1.31.11) also when not drawn
    if plates[p.plate] == p.st or FFT.ToSpot(p.plate) then return ShowHit(p.plate, p.hit, why, who) end
    if not p.ax then
        return Log("  yours, not drawn: %s (%s; its nameplate went away)%s", S(p.hit.text), why, FFT.Which(p.hit))
    end
    Log("  show %s (%s; its nameplate went away, shown where it was)%s", S(p.hit.text), why, FFT.Which(p.hit))
    if FFT:TooSmall(p.hit.amount) then return end
    local color = p.hit.color
    if who == "pet" and db.schoolColors and not p.hit.miss then color = Color("colorPet") end
    FFT:Show(nil, p.hit.text, color, p.hit.crit, HitOpts(p.hit, {anchorX = p.ax, anchorY = p.ay, key = p.plate}))
    if p.hit.crit then FFT:CritSound() end
end

-- (1.31.11) A killing blow brings the numbers of your swings still on their way at once: the author's
-- 2026-11-13 08:08 log (solo, the game's file), 5 physical hits 0.101-0.114 s after your kill line
-- (PARTY_KILL), each where a swing of yours at that mob had no hit yet (173598.076, 173644.218 x2,
-- 174089.713, 174165.566; dropped by 1.31.10). So such a hit, 0.08-0.13 s after a kill line, is
-- the oldest of those swings'. Outside a group only: there others' swings end the same way.
function SWING_QUICK.AfterKill(p)
    if IsInGroup() or p.hit.school ~= 1 then return nil end
    local kill
    for _, m in ipairs(clogMsgs) do
        local dt = p.now - m.t
        if m.kind == "kill" and dt >= 0.08 and dt <= 0.13 then kill = m end
    end
    if not kill then return nil end
    for _, sw in ipairs(swings) do
        if sw.plate == p.plate and not sw.used and not sw.cands and not sw.ranged and sw.t <= kill.t + SAME_FRAME then
            sw.used = true
            return sw, p.now - kill.t
        end
    end
end

-- (1.31.15) Windfury's hit that comes with its line: Windfury Totem's own, mostly. Beside its extra swing (SWING_QUICK.MarkExtra) the totem,
-- from rank 2, also strikes as a spell: SPELL_DAMAGE "Windfury Totem" (10608, physical) with no
-- SPELL_EXTRA_ATTACKS, 0.02-0.05 s after the swing's row or a Stormstrike's in the game's file.
-- The author's 2026-11-13 20:11 dungeon log (rank 2, the game's file beside it): 27 of them; to the
-- addon a "damage" line and a physical hit at the swing's mob in one frame, 0.017-0.050 s after
-- PLAYER_SWING (217719.310, 217840.394) or after a Stormstrike whose own hit came in its cast's
-- frame (217761.552). Shown as any hit with its line, and from now told as "Windfury!".
-- The weapon enchant's attack looks the same when it kills: its number then comes with its line
-- instead of 0.22 s later (the 2026-11-11 18:49 dungeon log, no totem there: swing 39620.065, kill
-- and damage lines and a physical crit at 39620.108, SPELL_DAMAGE "Windfury Weapon" in the game's
-- file). A Windfury proc either way, and one that had no alert before, its slot staying empty.
-- Not a tick's line (a physical DoT of yours ticks at any moment). Not a miss: Windfury's attacks
-- that miss tell nothing either, and a miss line there can be another
-- proc's (the same log: a triggered spell's SPELL_MISSED 0.02-0.03 s after its swing). Not while a
-- cast of yours that you sent could still be this hit's own (an instant whose hit comes a frame
-- late). Shamans only, as the extra swing: other classes' on-hit effects aren't measured.
SWING_QUICK.TOTEM_HIT = {from = 0.010, to = 0.070}
function SWING_QUICK.TotemHit(p, m)
    local hit, W = p.hit, SWING_QUICK.TOTEM_HIT
    if hit.miss or hit.school ~= 1 or m.kind ~= "damage" or m.periodic or math.abs(m.t - p.now) > SAME_FRAME then return false end
    local after = false
    for _, c in ipairs(ownCasts) do
        local dt = p.now - c.t
        if not c.landed and c.sent ~= false and math.abs(dt) <= SAME_MOMENT then
            local known = SpellSchool(c.name)
            if not (known and known ~= 1) then return false end -- this hit can be that cast's own
        end
        if c.landed and c.plate == p.plate and dt >= W.from and dt <= W.to then
            local known = SpellSchool(c.name) -- (a physical spell's school may not be learned: Stormstrike's isn't)
            if not known or known == 1 then after = true end
        end
    end
    for i = #swings, 1, -1 do
        local sw = swings[i]
        local dt = p.now - sw.t
        if dt > W.to then break end
        if dt >= W.from and sw.plate == p.plate and sw.hand == 0 and not sw.ranged and not sw.form then after = true end
    end
    if not after then return false end
    local ok, _, class = pcall(UnitClass, "player")
    return ok and Plain(class) == "SHAMAN"
end

local function ClogDecide(p)
    local lonely = p.alone and LinesInMoment(p.now, p.hit) == 1
    local m, air = ClogFind(p.now, p.hit)
    if m then
        m.used = true
        local school = (not p.hit.miss) and p.hit.school or nil
        local totem = false
        -- one hit and one line alone in their moment: that color stood for this school
        if lonely and not air and school and m.key then
            lineSchools[m.key] = lineSchools[m.key] or {}
            lineSchools[m.key][school] = (lineSchools[m.key][school] or 0) + 1
        end
        if air then
            m.byAir = true -- (1.29.1) a totem's line used by its hit no longer counts as owed (ProcLinesAt)
            if air.kind == "cast" then air.airUsed = true -- a cast line (MinionCastLine)
            elseif air.id then air.clogUsed = true else air.landed = true end
        else
            -- your totem's attack school is learned here too, from hits in their line's moment
            -- with no cast of yours in that moment (an instant spell's hit would be its own)
            local ownNow = false
            for _, c in ipairs(ownCasts) do
                if math.abs(p.now - c.t) <= SAME_MOMENT then ownNow = true end
            end
            if not ownNow and school then VoteMinion(p.plate, p.hit, p.now) end
            totem = SWING_QUICK.TotemHit(p, m) -- before MarkLanded: a cast still on its way counts
            MarkLanded(school, p.now)
            LearnFromLine(p.plate, p.hit, p.now, m) -- (1.21.0) facts for the fallback
        end
        ShowClogHit(p, ("your Combat Log line, %+.3fs%s"):format(m.t - p.now,
            air and (", while your " .. (air.name or "spell") .. " was on its way") or ""))
        if totem then
            Log("  Windfury's hit with its line, just after your swing or cast (the totem's own, or an attack that killed)")
            if FFT.OnWindfury then FFT:OnWindfury() end
        end
        return
    end
    -- (1.17.0) a line from long before: a shot's from its frame, or a melee line
    -- of your pet's or an extra attack of yours
    local fm, sw = SwingFrameLine(p.plate, p.hit, p.now)
    if fm then
        fm.used = true
        return ShowClogHit(p, ("your Combat Log line from your shot %.2fs before"):format(p.now - sw.t))
    end
    local om, who = OrphanSwingLine(p.plate, p.st and p.st.unit, p.hit, p.now)
    if om then
        om.used = true
        local why = ("%s, its melee line %.2fs before"):format(who == "pet" and "your pet's swing" or
            "your extra attack", p.now - om.t)
        if who == "pet" and not db.showPet then return Log("  drop %s (%s, but pets are off)", S(p.hit.text), why) end
        return ShowClogHit(p, why, who)
    end
    -- (1.23.3) No second look 0.06 s later any more (it came with 1.15.4, when a line could still
    -- come after its hit). Since 1.19.0 only lines from before or with the hit count
    -- (LINE_AFTER_HIT), this first look is already CLOG_WINDOW after the hit, and a line is only
    -- ever used up, never freed: the second look could find nothing the first didn't. Simulator
    -- (sim/, 300 s, seeds 1-2, 0/5/10/39 others): the same hits shown and the same wrong ones in all
    -- 8 runs, and with 39 others 76% fewer timers (12,258 -> 2,898). Heals keep theirs (Heals.lua
    -- ByCombatLog): a heal's line may come just after the heal.
    local ksw, kd = SWING_QUICK.AfterKill(p)
    if ksw then
        return ShowClogHit(p, ("your %s, its number %.2fs after your killing blow"):format(
            ksw.extraOf and "extra swing (Windfury Totem)" or "swing", kd))
    end
    if logging then Log("  drop %s (no Combat Log line of yours with it)%s", S(p.hit.text), FFT.Which(p.hit)) end
end

-- When hits outnumber your lines in a moment, they choose in this order (1.15.3):
--   2 for each: its school fits a line's learned color school, or something of yours of its
--   school just now (RecentSchool); then 1 for a hit on your target.
-- In the 1.15.2 log (18:41, 670.836 and 731.942) a damage shield (Thorns, from a passing druid)
-- hit your target in the same frame as a hunter's Arcane / pet's Nature hit on another mob, with
-- one line of yours, and the first to arrive took it: the hunter's was shown, yours dropped.
-- (1.31.3) the order, as a field made once (a new function per batch before; and Lua's 200 locals)
FFT.ClogOrder = function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.order < b.order
end
local function ClogResolveFrame()
    local list = clogPending
    clogPending = {}
    -- (1.31.3) a hit alone in its batch has no one to be ordered against: its score (two more
    -- passes over your lines and casts) only ever sorted it. In a party most batches hold one hit.
    if #list == 1 then
        list[1].alone = true
        return ClogDecide(list[1])
    end
    local target = FFT.TargetPlate()
    for i, p in ipairs(list) do
        p.order = i
        p.alone = false
        local score = 0
        if not p.hit.miss and RecentSchool(p.plate, p.hit.school, p.now) then score = score + 2 end
        local _, knows = LinesInMoment(p.now, p.hit)
        if knows then score = score + 2 end
        if target and p.plate == target then score = score + 1 end
        p.score = score
    end
    table.sort(list, FFT.ClogOrder)
    for _, p in ipairs(list) do ClogDecide(p) end
end

-- from (optional, 1.28.8): a hit that waited as a swing's candidate; it keeps the plate's state and
-- place from when it came, not from now (the plate may show another mob by now)
local function ClogMatch(plate, hit, now, from)
    local st, ax, ay
    if from then
        st, ax, ay = from.st, from.ax, from.ay
    else
        st = plates[plate]
        ax, ay = PlateAnchor(plate)
    end
    clogPending[#clogPending + 1] = {plate = plate, hit = hit, now = now, st = st, ax = ax, ay = ay}
    if #clogPending == 1 then C_Timer.After(CLOG_WINDOW, ClogResolveFrame) end
end

-- When a swing's window closes, its hit is the one closest to where yours land; the others
-- in the window (a pet's, a hunter's) go on to the other checks
-- (1.28.0) With a cast before its hit (sw.waitLate), a hit in the late window wins: the cast
-- delayed the swing. Only with none there does a normal-window one count.
local function ResolveSwing(sw)
    local best, expected = nil, sw.expected
    local anyLate = false
    for _, cand in ipairs(sw.cands) do if cand.late then anyLate = true end end
    if anyLate then
        expected = sw.lateAt or (sw.only and sw.lateCenters and sw.lateCenters[1]) or (sw.own + SWING_QUICK.CastExtra(sw))
        sw.afterCast = sw.waitLate and sw.waitLate.name or sw.afterCast
    end
    local group = {}
    for _, cand in ipairs(sw.cands) do
        -- (1.29.0) not one whose own spell line has come by now (its line can come just after the
        -- hit): 2026-11-10 18:53 log, swing 30549.242, a Searing Totem's Miss with its miss line at
        -- +0.373 (a learned 0.366 delay) and the swing's Parry at +0.464; as close, both were dropped
        local own = SWING_QUICK.OwnLine and SWING_QUICK.OwnLine(cand.hit, cand.now)
        if (cand.late == true) == anyLate and not own then group[#group + 1] = cand end
    end
    -- (1.29.0) how far from where this swing's hit may land: the expected moment, or one of the
    -- weapon's learned delays (SWING_QUICK.Anims; with a cast, the long one's late moment)
    local centers = anyLate and sw.lateCenters or sw.centers
    local function Off(d)
        local off = math.abs(d - expected)
        for _, c in ipairs(centers or {}) do off = math.min(off, math.abs(d - c)) end
        return off
    end
    for _, cand in ipairs(group) do
        if not best or Off(cand.d) < Off(best.d) then best = cand end
    end
    sw.used = true
    -- (1.21.0) two hits about as close to where your swing's lands can't be told apart: neither is
    -- shown. Simulator (sim/, 300 s, seeds 1-2): with the Combat Log, 5-man wrong 2.6% -> 1.5%,
    -- 10 others 7.6% -> 5.5%, 39 others 24% -> 18%, and not one of your hits fewer shown.
    -- (1.30.7) Unless the swing has an extra one (Windfury Totem, SWING_QUICK.MarkExtra) whose own
    -- hit hasn't come: the pair's two numbers can come in one frame, and then both are yours and
    -- no late one follows. The author's 2026-11-11 16:33 log, 31010.490: both swings in one frame,
    -- two hits at 31010.950 (+0.460), nothing at +1.46, the mob theirs alone by the game's file;
    -- as close, both were dropped. Seen once in 10 pairs. Only two hits of one frame, and not in a
    -- raid, where two in a frame are more likely someone else's.
    local twin
    if best then
        -- (1.31.11) or in the next frame, as close or not: the 2026-11-13 08:08 log, 173613.319, the
        -- first swing's crit at proc + 0.899 and the extra's MISS 0.006 s later, both dropped as "as
        -- close"; at 60 frames a second the next frame is 0.017 s on, no longer "as close"
        for _, cand in ipairs(group) do
            if cand ~= best then
                local x = sw.extra
                local close = Off(cand.d) - Off(best.d) < SWING_MARGIN
                if x and #group == 2 and not x.used and not x.cands and not IsInRaid()
                    and math.abs(cand.now - best.now) <= 0.02 + FrameSlack() then -- the next frame at any rate
                    twin = cand
                    x.used = true
                    break
                elseif close then
                    Log("  %s: another hit as close to your swing's moment, can't tell which", S(best.hit.text))
                    best = nil
                    break
                end
            end
        end
    end
    -- (1.31.10) the delay its hit showed, for its extra swing's (SWING_QUICK.ExtraFit)
    if best then sw.hitD, sw.hitLate = best.d, anyLate end
    -- (1.28.14) a plain swing with one hit in its window teaches this weapon speed's delay
    if best and #sw.cands == 1 and not anyLate and not sw.waitLate and not sw.procAt and not sw.extraOf then
        SWING_QUICK.Learn(sw, best.d)
        SWING_QUICK.AddAnim(sw.speed, best.d, "your swing")
    end
    -- (1.28.8) A swing is decided up to ~1.1 s after its hit came (the late window). If the hit's
    -- nameplate went to another mob meanwhile, the number shows where the plate was (ShowClogHit),
    -- not over the new mob: before, only "is the plate showing" was checked.
    for _, cand in ipairs(sw.cands) do
        if cand == best then
            ShowClogHit(cand, ("your %s, %.2fs after it%s"):format(
                sw.extraOf and "extra swing (Windfury Totem)" or "swing", cand.d,
                sw.afterCast and (", later as your " .. sw.afterCast .. " came with it") or ""))
        elseif cand == twin then
            ShowClogHit(cand, ("your extra swing (Windfury Totem), with your swing's hit %.2fs after it"):format(cand.d))
        elseif FFT:ClogActive() then
            ClogMatch(cand.plate, cand.hit, cand.now, cand)
        elseif plates[cand.plate] == cand.st then
            MatchRest(cand.plate, cand.hit, cand.now)
        else
            Log("  drop %s (its nameplate went away before it was decided)%s", S(cand.hit.text), FFT.Which(cand.hit))
        end
    end
end

local function AddSwingCandidate(sw, plate, hit, now, d, late)
    sw.cands = sw.cands or {}
    local ax, ay = PlateAnchor(plate)
    sw.cands[#sw.cands + 1] = {plate = plate, hit = hit, now = now, d = d, late = late,
        st = plates[plate], ax = ax, ay = ay}
    if not sw.scheduled then
        sw.scheduled = true
        -- with a cast before its hit, decided when the late window closes (its number shows then)
        local closes = (sw.waitLate or late)
            and ((sw.lateAt or (sw.own + SWING_QUICK.CastExtra(sw))) + SWING_AFTER_CAST.after) or sw.max
        -- (1.29.0) the weapon's learned delays: with a cast, the long one's late moment; in a group
        -- the latest one too, so that a stranger's hit at an earlier one doesn't decide the swing
        -- before its own comes (solo the first hit decides at once, as before)
        if (sw.waitLate or late) and sw.lateCenters and not sw.procAt then
            closes = math.max(closes, sw.lateCenters[1] + SWING_QUICK.ANIM_TOL)
        elseif not (sw.waitLate or late) and sw.centers and IsInGroup() then
            closes = math.max(closes, sw.centers[#sw.centers] + SWING_QUICK.ANIM_TOL)
        end
        C_Timer.After(math.max(0, sw.t + closes + FrameSlack() + 0.02 - GetTime()), function() ResolveSwing(sw) end)
    end
end

------------------------------------------------------------------------
-- (1.26.3) Windfury's extra attacks. The author's 2026-11-09 09:59 log (solo, Windfury Weapon): a proc
-- brings "damage" lines of yours (the spell hit color) with no hit in their frame, in your swing's
-- frame or up to 0.23 s after it (with a Stormstrike there). Their physical hits on the swing's mob
-- come later, like a swing's: 0.228-0.232 s and 0.500-0.504 s after the lines (560324.482,
-- 560381.033, 560419.562, 560467.586). A Windfury attack that missed brought its "miss" line with
-- its MISS (560381.261), matched by the plain rule. The swing's own hit then comes ~0.96 s after
-- the proc (SWING_AFTER_PROC).
-- (1.28.0) The proc is spotted when its frame is over, not when its first attack lands: unused
-- damage lines in your swing's frame (or up to 0.45 s after it), or in your Stormstrike's frame,
-- beyond the lines your totem still owes. Then the swing's normal window is closed at once (in the
-- simulator with 5 others, others' hits in it took 18 delayed swings), each of the proc's lines
-- stands for one physical hit on that mob in one of the two measured slots, and the swing's own
-- hit is expected ~0.96 s after the proc. A totem attack brings one cast line and one damage line
-- 0-0.53 s later (NOTES.md), so a totem cast within 0.6 s before with no damage line since still
-- owes one; 1.26.3 refused every line after a totem cast instead, and lost real procs (the
-- simulator: Searing Totem attacks every ~2.4 s).
------------------------------------------------------------------------
-- seen 0.228-0.233 and 0.494-0.505 s after the lines solo; in a group (2026-11-09 14:54 log) 41 of 42
-- taken came at 0.23 or 0.50 s, one at 0.27 (the old slot's edge, likely someone else's): narrowed
-- from 0.19-0.27 / 0.46-0.54
local EXTRA_SLOTS = {{0.20, 0.26}, {0.47, 0.53}}
local PROC_AFTER_SWING = 0.45 -- seen up to 0.230 s after the swing
-- (1.28.11) A Stormstrike's proc lines come in its frame or ~0.10 s after it, as a swing's do:
-- +0.102, +0.110, +0.114 in the kept logs, +0.134 at 30 frames a second (12:55 log, 8776.974: two
-- lines at 8777.108, hits 0.200 and 0.500 s after them, both dropped: only the cast's own frame was
-- looked at). And as for a swing, the hits are timed from the lines (12:55; 14:54 log 578654.864:
-- 0.230, 0.513) or from the cast (2026-11-09 14:12 log 575583.916: lines +0.110, hits 0.234 and
-- 0.501 s after the cast).
local PROC_AFTER_CAST = 0.2
-- (1.28.12) A swing that starts just after a proc (a Stormstrike's) waits for it too: its hit comes
-- ~0.96 s after the proc, as a proc swing's own does, not 0.46 s after the swing. The author's
-- 2026-11-10 13:21 log (solo): Stormstrike with a Windfury line at 10564.144, swing at 10564.509
-- (+0.365), its hit at 10565.104 = proc +0.960 (swing +0.595: dropped). And the 2026-11-09 14:54 log:
-- proc 578602.160, swing +0.123, hit at proc +0.955. A swing 0.455 s after a line with no hit
-- (09:59 log, 560375.500) hit at its usual 0.461, so up to 0.40 s before the swing.
-- What Windfury is, from the game's own combat log file of that fight (/combatlog, matched to the
-- addon's log within 0.001 s): one or two SPELL_DAMAGE "Windfury Weapon" events (physical) at the
-- moment of the swing or Stormstrike that set them off (15 of 16; once 0.118 s after the swing),
-- with no cast and no extra-attack event of their own. A Windfury attack that misses brings a
-- SPELL_MISSED "Windfury Weapon" at the moment its number would show (13:50 log, 12108.316, 0.232 s
-- after the proc); a proc with one line and no miss was one attack (13:21 log, 10320.702).
local PROC_BEFORE_SWING = 0.40
local TOTEM_LINE_AFTER = 0.6

local function OwnCastAt(t)
    for _, ct in ipairs(ownCastTimes) do
        if math.abs(ct - t) <= SAME_FRAME then return true end
    end
    return false
end

-- How many of the damage lines in the frame at t may be your totem's: its casts in the 0.6 s
-- before (by nameplate, or as cast lines with no cast of yours) whose damage line hasn't come in
-- another frame, up to now. Looked at again each time: a totem's line coming after the proc's
-- frame frees that frame's lines.
-- (1.30.8) A damage line in the frame of a cast of yours is that cast's, never the totem's: in the
-- author's 2026-11-11 dungeon run Searing Totem attacked (cast line 40439.005), the author's Stormstrike's
-- line came at 40439.024 and the totem's at 40439.193. The Stormstrike's line seemed to pay the
-- totem's debt, so the totem's line was taken for a Windfury proc: a groupmate's Deep Wound got it
-- ("Windfury!" shown) and the totem's fire hit (40439.389) was dropped.
local function TotemLinesOwed(t, now)
    local function LineSince(t0)
        for _, y in ipairs(clogMsgs) do
            if y.kind == "damage" and y.t >= t0 - SAME_FRAME and y.t <= now + SAME_FRAME
                and math.abs(y.t - t) > SAME_FRAME and not OwnCastAt(y.t) then
                return true
            end
        end
        return false
    end
    local byPlate, byLine = 0, 0
    for _, c in ipairs(minionCasts) do
        local dt = t - c.t
        if dt >= -SAME_FRAME and dt <= TOTEM_LINE_AFTER and not LineSince(c.t) then byPlate = byPlate + 1 end
    end
    for _, x in ipairs(clogMsgs) do
        local dt = t - x.t
        if x.kind == "cast" and not x.proc and dt >= -SAME_FRAME and dt <= TOTEM_LINE_AFTER and not OwnCastAt(x.t)
            and not LineSince(x.t) then -- (1.31.0) not a game proc's line (FFT.NoteProcCast)
            byLine = byLine + 1
        end
    end
    return math.max(byPlate, byLine) -- one attack can show both ways
end

-- The proc lines of one frame: its damage lines no hit took (or that a Windfury hit took),
-- beyond what your totem may own. Returns how many, once that frame is over (else nil).
local function ProcLinesAt(t, now)
    if now - t <= CLOG_WINDOW then return nil end
    -- (1.28.0) a hit from the line's moment still waiting to be decided may take it yet: in the
    -- dungeon log a Flametongue line looked unused in the very frame its hit's decision was due,
    -- and its swing was taken for a proc (replayed: 3 normal swings dropped)
    for _, p in ipairs(clogPending) do
        if p.now >= t - SAME_FRAME and p.now - t <= CLOG_WINDOW then return nil end
    end
    local k, paid = 0, 0
    for _, x in ipairs(clogMsgs) do
        if x.kind == "damage" and math.abs(x.t - t) <= SAME_FRAME then
            if not x.used or x.extra then k = k + 1 elseif x.byAir then paid = paid + 1 end
        end
    end
    -- (1.29.1) a totem line in this frame that its own hit already took has paid what the totem
    -- owed: the 2026-11-10 19:58 log, 34190.284, Stormstrike with two Windfury lines and Searing
    -- Totem's line in one frame, the totem's hit took its line 0.069 s later, and Windfury's second
    -- attack (0.501 s) was dropped as the totem's line still seemed owed
    return math.max(0, k - math.max(0, TotemLinesOwed(t, now) - paid))
end

-- Is this swing a Windfury proc's? The proc's moment, or nil. Once its frames are over.
SwingProc = function(sw, now)
    if sw.procAt then return sw.procAt end
    if sw.procAt == false or not clog.byEvent or sw.ranged then return nil end
    for _, m in ipairs(clogMsgs) do
        local after = m.t - sw.t
        -- from before the swing only a line a Windfury hit has taken: an unused line there may be
        -- anything's (a hit not seen), and would cost the swing its normal window
        if m.kind == "damage" and after <= PROC_AFTER_SWING and ((not m.used or m.extra) and after >= -SAME_FRAME
            or m.extra and after >= -PROC_BEFORE_SWING) then
            local n = ProcLinesAt(m.t, now)
            if n and n > 0 then
                sw.procAt = m.t
                return m.t
            end
        end
    end
    -- none once every frame that could hold one has been decided: not a proc swing
    if now - sw.t > PROC_AFTER_SWING + 2 * CLOG_WINDOW then sw.procAt = false end
    return nil
end

-- (1.28.14) A swing's line comes with PLAYER_SWING and its color says hit or miss (SWING_DAMAGE /
-- SWING_MISSED), 0.46 s before the number. So a swing that hit is never a miss on its mob, nor the
-- other way round. The author's 2026-11-10 15:25 dungeon log: swing 17982.947 with a miss line, its
-- Dodge at +0.416 dropped for someone's hit at +0.436; swing 17956.964 with a hit line, a stranger's
-- Miss 1.50 s later shown as its hit and its own hit (+0.998) left out.
-- Known only with event colors, for one melee swing in its frame whose melee lines agree.
SWING_QUICK.Missed = function(sw)
    if sw.lineKind == nil then
        if not clog.byEvent or sw.ranged then return nil end
        if GetTime() - sw.t <= SAME_FRAME then return nil end -- its frame isn't over
        local n, hits, misses = 0, 0, 0
        for _, x in ipairs(swings) do
            if math.abs(x.t - sw.t) <= SAME_FRAME then n = n + 1 end
        end
        for _, m in ipairs(clogMsgs) do
            if math.abs(m.t - sw.t) <= SAME_FRAME then
                if m.kind == "swing" then hits = hits + 1 elseif m.kind == "swingMiss" then misses = misses + 1 end
            end
        end
        if n ~= 1 or (hits > 0) == (misses > 0) then sw.lineKind = "unknown"
        else sw.lineKind = misses > 0 and "swingMiss" or "swing" end
    end
    if sw.lineKind == "unknown" then return nil end
    return sw.lineKind == "swingMiss"
end

-- anims (optional, 1.29.0): the weapon's learned swing delays; a Windfury attack may also come at
-- half of one, and the second at 0.755 s with a long one (SWING_QUICK.SLOT_LONG)
local function InSlot(gap, anims)
    local slack = FrameSlack()
    for _, s in ipairs(EXTRA_SLOTS) do
        if gap >= s[1] - slack and gap <= s[2] + slack then return true end
    end
    for _, a in ipairs(anims or {}) do
        if math.abs(gap - a / 2) <= 0.03 + slack then return true end
        if a >= 0.6 and math.abs(gap - SWING_QUICK.SLOT_LONG) <= 0.03 + slack then return true end
    end
    return false
end

-- An unused line of a proc for this physical hit: from your swing's proc on this mob, or from a
-- proc in your Stormstrike's frame (Windfury procs from it too, 560423.060 and 560461.639 in the
-- 09:59 log, its second attack 0.505 s and 0.500 s after; then no swing waits). Returns the line,
-- and what it was a proc of (the swing, or the cast).
-- (1.28.11) A swing's proc whose lines came after the swing's frame: its hits are timed from the
-- lines (13 such procs in the kept logs: 0.23, 0.50, the swing's own 0.956), or, now and then, from
-- the swing as if the lines had come with it. The author's 2026-11-10 12:33 log, solo: swing
-- 7407.949, two lines at +0.099, hits 0.229, 0.501 and the swing's own 0.911 s after the swing
-- (0.130, 0.402, 0.812 after the lines: all three dropped by 1.28.9). The same once in the
-- 2026-11-09 14:54 group log (578648.388: 0.228, 0.505, 0.914). What decides which isn't known, so
-- for such a proc a hit may fall in a slot measured from either moment; the third value returned
-- says which ("lines" / "swing"), and the swing's own hit follows what its Windfury hits showed
-- (SwingFor).
local function ExtraAttackLine(plate, hit, now)
    -- (1.30.8) a glancing hit is a white swing's, never a Windfury attack's (see KindFits)
    if hit.miss or hit.glancing or hit.school ~= 1 or not clog.byEvent then return nil end -- needs event colors
    -- Slots measured from the swing (or the cast) double the moments a stranger's hit can take a
    -- line. Simulator, 10 fights each, with and without them: solo your hits shown 98.9% -> 99.3%
    -- and nothing wrong; with 5 others +8 of yours for +13 of theirs, with 39 others -10 of yours
    -- and +11 of theirs. So 1.28.11 used them outside a group only.
    -- (1.30.7) In a party too, not in a raid: the author's logs of 2026-11-11 in a group of two
    -- say otherwise than the simulator's party. 3 of 63 procs were timed from the swing (15:38 log
    -- 28564.916, lines +0.106, hits +0.230 / +0.505; 29369; 16:56 log 32621.033, lines +0.113, hits
    -- +0.231 / +0.505 / +0.910, "Windfury Weapon" by the game's file), each losing all its numbers
    -- and "Windfury!". Replayed with these slots, against the game's files: 9 more hits shown in
    -- those logs, 8 the author's and one swing's own (28565.878) that may be the warrior's; the
    -- 2026-11-10 15:25 dungeon log (five players, 31 procs) unchanged. Simulator, 300 s, seeds 1-3:
    -- with 1 other +6 of yours and none of theirs, with 4 others +2 and +2; a raid as before.
    local bySwing = not IsInRaid()
    -- (1.31.13) And only when the lines came 0.08 s or more after the swing or the cast, as in the
    -- logs above (0.099-0.134 s). In a dungeon they come 0.03 s after it: the author's 2026-11-13
    -- 10:28 log, 45 of 54 procs 0.025-0.045 s after, 9 in its frame, and every attack timed from the
    -- lines (0.211-0.233 and 0.472-0.497 s, 80 of 80 by the game's file). There a slot from the swing
    -- only moved the first slot's start to 0.17 s after the lines: 8 hits taken, 7 of them
    -- strangers' (182177.122: a rogue's two instants 0.19 s after the lines, both attacks then
    -- dropped), and in the 2026-11-11 dungeon log 40901.612 / .632. Replayed against the game's
    -- files: +3 of the author's and -3 of others' in the first, -2 of others' in the second.
    -- a line of the proc at t, if one is left (its lines, less those a Windfury hit took).
    -- swingAt: the swing's moment when the lines came after its frame, else nil
    local function LineIn(t, swingAt, anims)
        local n = ProcLinesAt(t, now)
        if not n then return nil end
        local taken = 0
        for _, m in ipairs(clogMsgs) do
            if m.extra and math.abs(m.t - t) <= SAME_FRAME then taken = taken + 1 end
        end
        if n - taken <= 0 then return nil end
        for _, m in ipairs(clogMsgs) do
            if m.kind == "damage" and not m.used and math.abs(m.t - t) <= SAME_FRAME then
                if InSlot(now - m.t, anims) then return m, swingAt and "lines" or nil end
                if swingAt and InSlot(now - swingAt, anims) then return m, "swing" end
            end
        end
    end
    for _, sw in ipairs(swings) do
        if sw.plate == plate and SwingProc(sw, now) then
            local m, from = LineIn(sw.procAt, bySwing and sw.procAt - sw.t >= SWING_QUICK.LINES_LATE and sw.t or nil, SWING_QUICK.BaseAnims())
            if m then return m, sw, from end
        end
    end
    for _, c in ipairs(ownCasts) do
        -- (1.31.13) not after a spell learned to hit as another school (a melee attack sets Windfury
        -- off): that bolt's line, left unused 0.149 s after its cast, was read as a late proc line,
        -- and a stranger's physical hit 0.52 s later shown with "Windfury!" (183317.941)
        if c.plate == plate and now - c.t <= 0.6 + PROC_AFTER_CAST and (SpellSchool(c.name) or 1) == 1 then
            local m = LineIn(c.t, nil, SWING_QUICK.BaseAnims())
            if m then return m, c end
            -- (1.28.11) its lines after the cast's frame (see PROC_AFTER_CAST)
            local tried
            for _, x in ipairs(clogMsgs) do
                local after = x.t - c.t
                if x.kind == "damage" and not x.used and after > SAME_FRAME and after <= PROC_AFTER_CAST
                    and x.t ~= tried then
                    tried = x.t
                    local late, from = LineIn(x.t, bySwing and after >= SWING_QUICK.LINES_LATE and c.t or nil, SWING_QUICK.BaseAnims())
                    if late then return late, c, from end
                end
            end
        end
    end
end

-- (1.26.3) a spell's miss line ("miss", the spell miss color) in this miss's own moment: a swing's
-- miss never brings one (its line, "swingMiss", comes with PLAYER_SWING). In the 09:59 log a
-- Stormstrike parried 0.439 s after a swing (560455.369, its miss line with it) fell in the swing's
-- window and was taken as the swing's; the swing's own hit, delayed by that Stormstrike, then had
-- no swing left (560455.925).
-- (1.28.0) Likewise a hit with your damage line in its moment and a harmful cast of yours in its
-- frame is that cast's (Stormstrike's), never the swing's: one 0.439 s after a swing fell in the
-- swing's window, and its line, left unused, then looked like a Windfury proc (sim/tests.lua).
local function OwnMissLineNow(hit, now)
    local want = hit.miss and "miss" or "damage"
    if not hit.miss then
        local cast = false
        for _, c in ipairs(ownCasts) do
            if math.abs(c.t - now) <= SAME_FRAME then cast = true end
        end
        if not cast then return false end
    end
    for _, m in ipairs(clogMsgs) do
        if not m.used and m.kind == want and math.abs(m.t - now) <= SAME_FRAME then -- (1.28.14) its frame
            return true
        end
    end
    return false
end

SWING_QUICK.OwnLine = OwnMissLineNow -- for ResolveSwing, defined above it

-- (1.29.0) A physical hit no swing took teaches its swing's delay (SWING_QUICK.AddAnim) when it can
-- only be that swing's: outside a group, on the swing's mob 0.15-0.80 s after it, the swing's own
-- line saying hit or miss as this one is, no cast of yours from 0.6 s before the swing (a
-- Stormstrike's Windfury) until now, no proc of the swing, and no other hit for it. Not shown: it
-- only teaches (precision over recall), so a new weapon's first few such swings are dropped.
SWING_QUICK.Sight = function(plate, hit, now)
    if IsInGroup() or not clog.byEvent then return end
    for _, sw in ipairs(swings) do
        local d = now - sw.t
        if sw.plate == plate and sw.speed and not sw.used and d >= 0.15 and d <= 0.80 then
            -- (1.30.6) not a swing with an extra one (SWING_QUICK.MarkExtra): which hit is whose
            -- isn't known, and when the pair kills its one number comes sooner than any swing's
            -- (0.241 s, 2026-11-11 12:46 log 17419.548). With the swings 0.10 s apart that hit was
            -- kept as a delay of the weapon; three such and it would count as learned.
            if sw.extra or sw.extraOf then sw.sight = false; return end
            if sw.sight ~= nil or sw.cands then sw.sight = false; return end -- a second hit: neither teaches
            if SwingProc(sw, now) or CastWithSwing(sw, now, d + SWING_CAST_FRAME, -0.6)
                or SWING_QUICK.Missed(sw) ~= (hit.miss == true) then
                sw.sight = false
                return
            end
            sw.sight = d
            C_Timer.After(0.85 - d, function()
                if sw.sight and not sw.used then SWING_QUICK.AddAnim(sw.speed, sw.sight, "a swing's only hit") end
            end)
            return
        end
    end
end

-- Combat Log mode: a physical hit (or miss) may be your swing's; everything else needs one of
-- your Combat Log messages with it
local function ClogHit(plate, hit, now)
    -- (1.30.7) A hit in the frame of your harmful cast, with a damage line of yours in that frame,
    -- is the cast's own before it is a Windfury attack: one such hit for each cast. The author's
    -- 2026-11-11 15:38 log, 29098.123: Stormstrike 0.49 s after a proc, its hit taken as the
    -- proc's second attack, and the real one 0.018 s later (29098.141) found Stormstrike's line a
    -- frame old and was dropped. With slots from the swing in a party (ExtraAttackLine) the same
    -- happened in the 2026-11-10 15:25 dungeon log (17824.851, Stormstrike 0.219 s after the swing).
    if hit.school == 1 and not hit.miss and OwnMissLineNow(hit, now) then
        local casts, waiting = 0, 0
        for _, c in ipairs(ownCasts) do
            if math.abs(c.t - now) <= SAME_FRAME and c.plate == plate then casts = casts + 1 end
        end
        for _, p in ipairs(clogPending) do
            if p.plate == plate and p.hit.school == 1 and not p.hit.miss and math.abs(p.now - now) <= SAME_FRAME then
                waiting = waiting + 1
            end
        end
        if waiting < casts then return ClogMatch(plate, hit, now) end
    end
    local xm, of, from = ExtraAttackLine(plate, hit, now)
    if xm then
        xm.used, xm.extra = true, true
        -- which moment this proc's hits are timed from, for the swing's own hit (SwingFor)
        if from == "swing" then of.hitsFromSwing = (of.hitsFromSwing or 0) + 1
        elseif from == "lines" then of.hitsFromLines = (of.hitsFromLines or 0) + 1 end
        -- (1.30.1) "Windfury!" once per proc, at its first attack taken as yours: the moment the
        -- proc is certain (its line used by a hit in a Windfury slot). A proc whose attacks all
        -- miss gets none (precision over recall).
        -- (1.30.2) Keyed by the proc's lines' moment, not by the swing or cast: one proc's two attacks
        -- can be taken for two of them. The author's 2026-11-11 08:44 log: Stormstrike's proc at
        -- 2878.334, its first attack (2878.561) taken as the cast's, the second (2878.836) as a swing's
        -- that started at 2878.712 (PROC_BEFORE_SWING), and 1.30.1 showed "Windfury!" twice.
        if not (SWING_QUICK.windfuryAt and math.abs(xm.t - SWING_QUICK.windfuryAt) <= SAME_FRAME) then
            SWING_QUICK.windfuryAt = xm.t
            if FFT.OnWindfury then FFT:OnWindfury() end
        end
        return ShowHit(plate, hit, ("your extra attack (Windfury), its line %.2fs before%s"):format(now - xm.t,
            from == "swing" and (", %.2fs after your %s"):format(now - of.t, of.name or "swing") or ""))
    end
    if hit.school == 1 and not OwnMissLineNow(hit, now) then
        local sw, d, late = SwingFor(now, plate, true, hit.miss == true, hit)
        if sw then return AddSwingCandidate(sw, plate, hit, now, d, late) end
        SWING_QUICK.Sight(plate, hit, now)
    end
    ClogMatch(plate, hit, now)
end

local function MatchByOwnActions(plate, hit, now, isTarget)
    -- A miss's school says nothing about which spell missed: the game reports a spell's miss
    -- as school 1 (seen in game: a Flame Shock that missed came as MISS school 1, and no
    -- ticks followed). So misses skip the school check and teach no school.
    local school = (not hit.miss) and hit.school or nil
    -- every hit of a cast's moment on its mob counts toward learning its school, claimed or not
    if school then
        for _, other in ipairs(ownCasts) do
            if math.abs(now - other.t) <= SAME_MOMENT then NoteMoment(other, plate, school) end
        end
    end
    local c = SameMomentCast(now, school, plate)
    if c then
        c.landed = true
        c.claimed = c.claimed or {}
        c.claimed[plate] = true
        return ShowHit(plate, hit, "your " .. c.name)
    end
    if hit.school == 1 then
        local sw, d, late = SwingFor(now, plate)
        if sw then return AddSwingCandidate(sw, plate, hit, now, d, late) end
    end
    MatchRest(plate, hit, now)
end

local function CheckOwnActions(plate, hit, now, isTarget)
    C_Timer.After(0, function()
        if plate:IsShown() then MatchByOwnActions(plate, hit, now, isTarget) end
    end)
end
FFT.CheckOwnActions = CheckOwnActions

------------------------------------------------------------------------
-- Turning UNIT_COMBAT into text
------------------------------------------------------------------------
local function BuildHit(action, flag, amount, school)
    action, flag = Plain(action), Plain(flag)
    if not action then return nil end

    if action == "WOUND" then
        if Plain(amount) == 0 then
            if not db.showMisses then return nil end
            return {text = flag and _G[flag] or MISS, color = Color("colorMiss"), miss = true, school = Plain(school)}
        end
        local swing = Plain(school) == 1 and GetTime() - lastCast > SAME_MOMENT
        return {
            amount = amount,
            school = Plain(school),
            text = FormatAmount(amount),
            color = (swing and db.schoolColors) and Color("colorAuto") or SchoolColor(school),
            crit = (flag == "CRITICAL" or flag == "CRUSHING"),
            glancing = (flag == "GLANCING"),
            blocked = (flag == "BLOCK_REDUCED"),
        }
    elseif MISS_ACTIONS[action] then
        if not db.showMisses then return nil end
        return {text = _G[action] or action, color = Color("colorMiss"), miss = true, school = Plain(school)}
    end
    return nil -- heals, power gains etc. aren't shown
end

function FFT:OnUnitCombat(unit, action, flag, amount, school)
    if not db.enabled then return end
    if Plain(action) == "HEAL" then return self:OnHeal(unit, flag, amount) end
    if unit == "player" then
        -- (1.22.0) ENERGIZE: power you gain; Blizzard's CombatFeedback.lua draws it (amount, CRITICAL)
        if Plain(action) == "ENERGIZE" then return self:OnPowerGain(flag, amount) end
        return self:OnIncoming(action, flag, amount, school)
    end
    if IsSecret(unit) then return end
    local plate
    if unit == "target" then
        -- (1.30.0) only while your target has no nameplate: with one, the plate's report comes too
        if PlateOf("target") then return end
        plate = FFT.TargetPseudo()
    elseif unit:find("^nameplate") then
        plate = PlateOf(unit)
    end
    if not plate then return end
    if Plain(UnitCanAttack("player", unit)) == false then return end

    local hit = BuildHit(action, flag, amount, school)
    if hit then hit.unit, hit.at = unit, GetTime() end -- for the log (Which)
    -- (1.28.8) `if logging` here and at the other lines every stranger's hit reaches: Log returns at
    -- once when not recording, but its arguments (four S() calls) were worked out first, per hit
    if logging then Log("%s %s %s %s school %s", unit, S(action), S(flag), S(amount), S(school)) end
    if not hit then return end

    local isTarget = (plate == FFT.TargetPlate())
    if db.scope == "all" then
        return ShowHit(plate, hit, "all enemies")
    elseif db.scope == "target" and not isTarget then
        return
    end

    local now = GetTime()
    -- The game's Combat Log, when it can tell your actions, decides (see "Combat Log mode")
    if self:ClogActive() then return ClogHit(plate, hit, now) end
    self:FallbackNotice()
    -- A miss raises no threat: it's yours if it was your swing or your spell
    if hit.miss then return CheckOwnActions(plate, hit, now, isTarget) end

    local st = PlateState(plate, unit)
    if MatchByThreat(plate, st, hit, now, isTarget) then return end

    -- Threat hidden: only your own swings and spells
    CheckOwnActions(plate, hit, now, isTarget)
end

function FFT:OnThreatUpdate(unit)
    if IsSecret(unit) or not unit:find("^nameplate") then return end
    local plate = PlateOf(unit)
    local st = plate and plates[plate]
    if not st or st.unit ~= unit then return end
    local rose, who = ThreatRose(st)
    if rose then
        Log("%s threat rose (%s) to %s / pet %s", unit, who, S(st.last), S(st.lastPet))
        OnRise(plate, st, GetTime(), who)
    elseif st.unreadable and #st.pending > 0 then
        HandOver(plate, st)
    end
end

-- A mob's cast was interrupted. The game hides who did it (interruptedBy is secret for
-- mobs), so it's yours if you finished a cast just now and the mob is your target or
-- one you just hit.
function FFT:OnInterrupted(unit)
    if not (db.enabled and db.showInterrupts) then return end
    if IsSecret(unit) or not unit:find("^nameplate") then return end
    local plate = PlateOf(unit)
    if not plate then return end
    -- your own totem's plate gets "interrupted" too (seen in game, 1.13.2 probe log): only mobs
    if Plain(UnitCanAttack("player", unit)) == false then return end
    local now = GetTime()
    local st = plates[plate]
    -- 1.16.0: with the Combat Log in use, it's yours when an interrupt line of yours came with it.
    -- Seen in the logs (2026-11-06, e.g. 339035.520, 339055.014): your Earth Shock's interrupt
    -- line (1.00 0.45 0.10) came in the same moment as the mob's UNIT_SPELLCAST_INTERRUPTED, logged
    -- just after it, so this waits CLOG_WINDOW before deciding.
    if self:ClogActive() and self:ClogKindsKnown() then
        C_Timer.After(CLOG_WINDOW, function()
            local d = self:ClogTakeInterruptLine(now)
            if not d then
                return Log("%s interrupted: not yours (no interrupt line of yours)", unit)
            end
            Log("%s interrupted: yours (Combat Log line, %+.3fs)", unit, d)
            if plates[plate] == st and plate:IsShown() then
                local at, o = FFT.DamagePlace(plate, {scale = db.interruptScale}) -- (1.30.0) or at the damage spot
                self:Show(at, INTERRUPTED or "Interrupted", Color("colorInterrupt"), false, o)
            end
        end)
        return
    end
    local mine = now - lastCast <= INTERRUPT_WINDOW
        and (plate == FFT.TargetPlate() or (st and st.lastMine and now - st.lastMine <= 1))
    Log("%s interrupted, your last cast %.2fs ago: %s", unit, now - lastCast, mine and "yours" or "not yours")
    if mine then
        local at, o = FFT.DamagePlace(plate, {scale = db.interruptScale})
        self:Show(at, INTERRUPTED or "Interrupted", Color("colorInterrupt"), false, o)
    end
end

------------------------------------------------------------------------
-- Blizzard's own damage numbers
------------------------------------------------------------------------
-- Names and meanings from Forever 1.60.1's own CVar list (Ketho/BlizzardInterfaceResources,
-- branch "forever", Resources/CVars.lua). Only these four are about your numbers over mobs.
-- Blizzard's text over your own character (enableFloatingCombatText, SELF_CVAR below) is handled
-- apart: off while "Show damage I take" replaces it, or on with its frame hidden while a feature
-- reads the COMBAT_TEXT_UPDATE feed (FeedWanted).
local HEAL_CVAR = "floatingCombatTextCombatHealing_v2" -- "Display amount of healing you did to the target"
-- Its listed description is "values for effects on other players", but turning it off is what
-- removed Blizzard's "Interrupted" over mobs you interrupt (tested in game, 1.60.1).
local INTERRUPT_CVAR = "floatingCombatTextSpellMechanics_v2"
-- "Whether to show floating combat text for the player". Blizzard's combat text always shows
-- damage taken while it's on (DAMAGE has show = 1 in CombatTextConstants.lua), so it's the
-- only way to hide theirs; it also takes their low health/mana and ability alerts with it.
-- Turning it off removed Blizzard's damage taken under the character (tested in game, 1.60.1).
local SELF_CVAR = "enableFloatingCombatText"
-- Blizzard's "Energy Gains" over your character (CombatTextConstants.lua ENERGIZE, and
-- PERIODIC_ENERGIZE in Mainline/CombatTextConstantsOverrides.lua); not secure in Forever's CVar list.
-- (1.24.0) These, and SELF_CVAR, are also the source of the COMBAT_TEXT_UPDATE feed that brings
-- resource gains to addons, so all three stay on and Blizzard's frame is hidden instead. 1.22.0-1.23.4
-- set them to "0", and Mana Spring Totem's ticks never reached the addon: the 2026-11-09 07:36 log has
-- no ENERGIZE line at all (UNIT_COMBAT doesn't report periodic gains). So while "Show power gains" is
-- on they're kept "1", and Blizzard's text is hidden by hiding its CombatText frame (below).
-- (1.25.0) SELF_CVAR also stays "1" for "Show buffs gained / faded" (FeedWanted).
local ENERGY_CVARS = {
    floatingCombatTextEnergyGains_v2 = true,
    floatingCombatTextPeriodicEnergyGains_v2 = true,
}
-- (1.22.1) Blizzard's "Combat State" ("Entering Combat" over your character, CombatTextConstants.lua);
-- "0" by default and not secure in Forever's CVar list. Hidden only while ours is on.
local COMBAT_STATE_CVAR = "floatingCombatTextCombatState_v2"
local BLIZZARD_CVARS = {
    "floatingCombatTextCombatDamage_v2",             -- "Display damage numbers over hostile creatures when damaged"
    "floatingCombatTextCombatLogPeriodicSpells_v2",  -- "Display damage caused by periodic effects"
    "floatingCombatTextPetMeleeDamage_v2",           -- "Display pet melee damage in the world"
    "floatingCombatTextPetSpellDamage_v2",           -- "Display pet spell damage in the world"
    HEAL_CVAR,                                       -- hidden only while "Show my heals" is on
    INTERRUPT_CVAR,                                  -- hidden only while "Show my interrupts" is on
    SELF_CVAR,                                       -- hidden only while "Show damage I take" is on
    "floatingCombatTextEnergyGains_v2",              -- kept ON while "Show power gains" is on (the feed)
    "floatingCombatTextPeriodicEnergyGains_v2",      -- (the same)
    COMBAT_STATE_CVAR,                               -- hidden only while "Show entering / leaving combat" is on
}
local blizzardPending = false

local function WantHidden(cvar)
    if not (db.enabled and db.hideBlizzard) then return false end
    if cvar == HEAL_CVAR then return db.showHeals end
    if cvar == INTERRUPT_CVAR then return db.showInterrupts end
    if cvar == SELF_CVAR then return db.showIncoming end
    if ENERGY_CVARS[cvar] then return false end -- (1.24.0) never by CVar: they carry the feed
    if cvar == COMBAT_STATE_CVAR then return db.showCombatState end
    return true
end

-- (1.25.0) The features that read the COMBAT_TEXT_UPDATE feed: power gains, buffs on you and
-- (1.26.0) who healed you.
-- SELF_CVAR carries the whole feed; the energy CVars only the power kinds. Buff kinds came with
-- floatingCombatTextAuras_v2 at "0" (2026-11-09 08:04 log), so that one isn't touched.
local function FeedWanted()
    return db.enabled and (db.showPower or db.showAuras or db.showLowWarnings -- (1.28.7)
        or db.showGameProcs -- (1.31.0) the game's proc notices (Procs.lua)
        or db.showReactives -- (1.31.0) the game's reactive ability notices (Procs.lua)
        or (db.showIncoming and db.showIncomingHeals and db.showHealerNames)) -- (1.26.0)
end

-- "1" / "0" to set, nil to leave as the player had it. The feed wins over hiding: while a feature
-- needs it, SELF_CVAR stays "1" and Blizzard's text is hidden by its frame instead.
local function CVarTarget(cvar)
    if not db.enabled then return nil end
    if cvar == SELF_CVAR and FeedWanted() then return "1" end
    if ENERGY_CVARS[cvar] and db.showPower then return "1" end
    if WantHidden(cvar) then return "0" end
    return nil
end

-- (1.24.0) Blizzard's own text over your character, while SELF_CVAR is on only for the feed.
-- Hidden when "Show damage I take" replaces it, or when your own choice was "off" (the value
-- saved before the addon changed it). The same as SELF_CVAR "0" did, so its low health / mana
-- and ability alerts go with it, as before.
local function BlizzardSelfTextHidden()
    if not db.enabled then return false end
    if C_CVar.GetCVar(SELF_CVAR) ~= "1" then return false end -- nothing drawn anyway
    if db.hideBlizzard and db.showIncoming then return true end
    local own = db.savedCVars and db.savedCVars[SELF_CVAR]
    return FeedWanted() and own == "0"
end

-- Blizzard's text for the kinds the addon shows itself, when its frame stays visible: their `show`
-- is cleared (CombatTextTypeInfo, CombatTextConstants.lua and Mainline/CombatTextConstantsOverrides.lua),
-- Blizzard's UpdateDisplayedMessages sets `show` again from the CVar, so this runs
-- after it too. kind -> the setting that replaces it.
local OWN_KINDS = {
    ENERGIZE = "showPower", PERIODIC_ENERGIZE = "showPower",
    SPELL_AURA_START = "showAuras", SPELL_AURA_START_HARMFUL = "showAuras",
    SPELL_AURA_END = "showAuras", SPELL_AURA_END_HARMFUL = "showAuras",
    SPELL_CAST = "showGameProcs", -- (1.31.0) "<Maelstrom Ready!>": shown at the procs spot instead
    SPELL_ACTIVE = "showReactives", -- (1.31.0) "<Overpower>": the same
}
local function HideBlizzardKinds()
    local types = _G.CombatTextTypeInfo
    if type(types) ~= "table" then return end
    -- (1.28.9) Only ever cleared, never set. Before, a kind whose feature was off got `show = 1`
    -- back from here when its CVar was "1": a value written by an addon, and Blizzard's OnEvent,
    -- having read it, ran tainted and failed on the hidden values it then handled. Seen in game
    -- 2026-11-10 (buffs off, floatingCombatTextAuras_v2 1, a buff gained): "CombatText.lua:364:
    -- attempt to compare local 'lowestMessage' (a secret number value, while execution tainted by
    -- 'ForeverFloatingText')". A cleared `show` did no such thing (12:33 log, no error). So a kind
    -- whose feature is turned off stays hidden until Blizzard sets it again itself
    -- (UpdateDisplayedMessages: at load, or when its combat text is switched on).
    for kind, setting in pairs(OWN_KINDS) do
        local info = types[kind]
        if type(info) == "table" and db.enabled and db.hideBlizzard and db[setting] and info.show ~= nil then
            info.show = nil
        end
    end
end

-- Called after the CVars change and when Blizzard_CombatText loads (it loads when SELF_CVAR is
-- turned on: Settings.LoadAddOnCVarWatcher in CombatOverrides.lua). Its OnEvent returns at once
-- while the frame isn't visible (CombatText.lua), so nothing of Blizzard's is drawn.
-- (1.28.7) Low health / mana: Blizzard's frame works them out itself on UNIT_HEALTH /
-- UNIT_POWER_UPDATE from UnitHealth / UnitPower (CombatText.lua: <= 20%, CombatTextConstants
-- LowHealthThreshold / LowManaThreshold, mana only), which are secret to addons (2026-11-09 08:04
-- log), and marks itself `lowHealth` / `lowMana` (1 or nil) as it crosses, only while visible.
-- So while "Show low health / mana" is on, the frame is kept shown at alpha 0 instead of hidden
-- (it draws, unseen) and a post-hook of its OnEvent shows the game's HEALTH_LOW / MANA_LOW
-- ("Health Low" / "Mana Low") at the alerts spot when a mark turns on. Not yet seen in game.
local ctHooked, ctHiddenByUs = false, false
local function MuteNotHide() return db.enabled and db.showLowWarnings end
local LOW_MARKS = {
    {field = "lowHealth", text = function() return HEALTH_LOW or "Health Low" end},
    {field = "lowMana", text = function() return MANA_LOW or "Mana Low" end},
}
local LOW_AGAIN = 5 -- seconds: hovering at 20% doesn't repeat it
local lowWas, lowShownAt = {}, {}
local function CheckLowMarks(f)
    for _, m in ipairs(LOW_MARKS) do
        local v = rawget(f, m.field)
        if not IsSecret(v) then
            local on = v ~= nil and v ~= false
            if on and not lowWas[m.field] then
                local now = GetTime()
                -- (1.31.6) not while dead or a ghost: at 0 the marks stay on (the author, 2026-11-12:
                -- "now that i died, i see mana low health low"); UnitIsDeadOrGhost isn't secret (UnitDocumentation.lua)
                local asked, dead = pcall(UnitIsDeadOrGhost, "player")
                dead = asked and Plain(dead) == true
                local shown = not dead and ctHiddenByUs and MuteNotHide() and FFT.ShowAlert
                    and not (lowShownAt[m.field] and now - lowShownAt[m.field] < LOW_AGAIN)
                Log("Blizzard's combat text: %s on%s", m.field, shown and ", shown" or dead and ", you're dead" or "")
                if shown then
                    lowShownAt[m.field] = now
                    -- (1.31.12) a brief alert as you cross 20%, gone with the other alerts, as Blizzard's
                    -- own (CombatText.lua: one HEALTH_LOW / MANA_LOW message per crossing, scrolling and
                    -- fading as any). 1.31.0-1.31.11 kept it at the procs spot while under 20% (up to
                    -- 600 s); the author, 2026-11-13: it should just show briefly.
                    FFT:ShowAlert(m.text(), {1, 0.1, 0.1}) -- Blizzard's color for them
                end
            elseif not on and lowWas[m.field] then
                Log("Blizzard's combat text: %s off", m.field)
            end
            lowWas[m.field] = on
        end
    end
end
-- (1.31.6) Back alive (DeathInfoDocumentation.lua: PLAYER_ALIVE, PLAYER_UNGHOST), a mark still on
-- shows again at the next health / mana update. (Dying put the kept warnings away until 1.31.12;
-- they are brief now.) In a do block: this file is at Lua's limit of 200 locals.
do
    local death = CreateFrame("Frame")
    death:RegisterEvent("PLAYER_ALIVE") -- also when released as a ghost: then still dead
    death:RegisterEvent("PLAYER_UNGHOST")
    death:SetScript("OnEvent", function()
        local ok, dead = pcall(UnitIsDeadOrGhost, "player")
        if ok and Plain(dead) == false then wipe(lowWas) end
    end)
end
function FFT:ApplyBlizzardCombatTextFrame()
    local frame = _G.CombatText
    if type(frame) ~= "table" or type(frame.Hide) ~= "function" then return end
    if not ctHooked then
        ctHooked = true
        frame:HookScript("OnShow", function(f)
            if db and BlizzardSelfTextHidden() then
                if MuteNotHide() then f:SetAlpha(0) else f:Hide() end
                ctHiddenByUs = true
            end
        end)
        frame:HookScript("OnEvent", function(f, event)
            if db and (event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE") then CheckLowMarks(f) end
        end)
        if type(frame.UpdateDisplayedMessages) == "function" then
            hooksecurefunc(frame, "UpdateDisplayedMessages", function() if db then HideBlizzardKinds() end end)
        end
    end
    if BlizzardSelfTextHidden() then
        if MuteNotHide() then
            frame:SetAlpha(0)
            if not frame:IsShown() then frame:Show() end
        else
            if frame:IsShown() then frame:Hide() end
            frame:SetAlpha(1)
        end
        ctHiddenByUs = true
    elseif ctHiddenByUs then
        ctHiddenByUs = false
        frame:SetAlpha(1)
        frame:Show()
    end
    HideBlizzardKinds()
end

-- C_CombatText reports for one unit, set by Blizzard's CombatText frame (UpdateDisplayedMessages
-- calls C_CombatText.SetActiveUnit). If that frame never set one, the addon sets "player".
function FFT:EnsureCombatTextUnit()
    if not (C_CombatText and C_CombatText.GetActiveUnit and C_CombatText.SetActiveUnit) then return end
    local ok, unit = pcall(C_CombatText.GetActiveUnit)
    unit = ok and Plain(unit) or nil
    if unit == nil and FeedWanted() then
        local set = pcall(C_CombatText.SetActiveUnit, "player")
        Log("combat text unit: none, set to player (%s)", set and "ok" or "failed")
    end
end

function FFT:CombatTextState()
    local unit
    if C_CombatText and C_CombatText.GetActiveUnit then
        local ok, u = pcall(C_CombatText.GetActiveUnit)
        unit = ok and u or nil
    end
    return ("%s %s, energy gains %s / periodic %s, Blizzard frame %s, unit %s"):format(SELF_CVAR,
        S(C_CVar.GetCVar(SELF_CVAR)), S(C_CVar.GetCVar("floatingCombatTextEnergyGains_v2")),
        S(C_CVar.GetCVar("floatingCombatTextPeriodicEnergyGains_v2")),
        type(_G.CombatText) ~= "table" and "not loaded" or (_G.CombatText:IsShown() and "shown" or "hidden"),
        S(unit))
end

-- Sets the ones we replace (saving the game's value first); puts back the rest
function FFT:ApplyBlizzardText()
    if InCombatLockdown() then blizzardPending = true; return end
    blizzardPending = false
    local saved = db.savedCVars or {}
    db.savedCVars = saved -- BlizzardSelfTextHidden reads the saved value
    local seen = {}
    for _, cvar in ipairs(BLIZZARD_CVARS) do
        seen[cvar] = true
        local value = C_CVar.GetCVar(cvar)
        if value ~= nil and not IsSecret(value) then
            local want = CVarTarget(cvar)
            if want then
                if saved[cvar] == nil then saved[cvar] = value end
                if value ~= want then C_CVar.SetCVar(cvar, want) end
            elseif saved[cvar] ~= nil then
                C_CVar.SetCVar(cvar, saved[cvar])
                saved[cvar] = nil
            end
        end
    end
    -- values saved by an older version for settings no longer hidden
    for cvar, value in pairs(saved) do
        if not seen[cvar] then C_CVar.SetCVar(cvar, value); saved[cvar] = nil end
    end
    db.savedCVars = next(saved) and saved or nil
    self:ApplyBlizzardCombatTextFrame()
    self:EnsureCombatTextUnit()
    Log("combat text settings applied: %s", self:CombatTextState())
    self:LogCombatTextCVars()
end

-- (1.27.1) At every logout (and /reload) Blizzard's settings go back to the player's own values,
-- and ApplyBlizzardText sets them again at the next login. So a player who disables or deletes
-- the addon has their own floating text back: the game saves settings after PLAYER_LOGOUT, and the
-- addon never runs again to undo them otherwise.
-- The saved values are kept: the next login's ApplyBlizzardText finds them already there.
-- Also in combat (a /reload mid-fight): these CVars aren't secure, and each set is guarded.
function FFT:RestoreBlizzardTextForLogout()
    for cvar, value in pairs(db.savedCVars or {}) do
        local ok, now = pcall(C_CVar.GetCVar, cvar)
        if ok and now ~= nil and not IsSecret(now) and now ~= value then pcall(C_CVar.SetCVar, cvar, value) end
    end
end

-- (1.24.1, probe) Blizzard's per-kind settings for its text over you (CombatTextConstants.lua
-- `cvar`). The energy kinds came only with their CVar on, so the feed may skip any kind whose CVar
-- is "0": the log says which were on. Kinds without a CVar (DAMAGE, HEAL, PERIODIC_HEAL,
-- SPLIT_DAMAGE, ABSORB_ADDED) have none to check. Read only; nothing is changed.
-- (1.26.2) Answered for two: buff and miss kinds came with Auras and DodgeParryMiss at "0"
-- (2026-11-09 08:04 log). Kept with the probe, since DamageReduction is "0" too and its kinds
-- (partial block / resist / absorb) aren't seen yet: if they never come, this says why to look.
local KIND_CVARS = {
    "floatingCombatTextAuras_v2", "floatingCombatTextDamageReduction_v2",
    "floatingCombatTextDodgeParryMiss_v2", "floatingCombatTextFriendlyHealers_v2",
    "floatingCombatTextReactives_v2", "floatingCombatTextRepChanges_v2",
    "floatingCombatTextHonorGains_v2", "floatingCombatTextLowManaHealth_v2",
    "floatingCombatTextComboPoints_v2",
}
function FFT:LogCombatTextCVars()
    if not logging then return end
    local parts = {}
    for _, cvar in ipairs(KIND_CVARS) do
        local ok, v = pcall(C_CVar.GetCVar, cvar)
        parts[#parts + 1] = cvar:gsub("^floatingCombatText", ""):gsub("_v2$", "") .. " " .. (ok and S(v) or "?")
    end
    Log("combat text kinds' settings: %s", table.concat(parts, ", "))
end

-- Settings "Reset" puts back to the game's own defaults: the four above, plus the
-- other world text settings from the same list that came up while testing.
-- All are in Forever's CVar list as not secure, so addons may set them.
local RESET_CVARS = {
    "floatingCombatTextCombatDamage_v2",
    "floatingCombatTextCombatLogPeriodicSpells_v2",
    "floatingCombatTextPetMeleeDamage_v2",
    "floatingCombatTextPetSpellDamage_v2",
    HEAL_CVAR,
    "floatingCombatTextSpellMechanics_v2",           -- "values for effects on other players"
    "floatingCombatTextSpellMechanicsOther_v2",      -- "... on other players' targets"
    "threatWorldText",                               -- "threat floaters in combat"
    SELF_CVAR,
}

-- Resets to the defaults the client reports (C_CVar.GetCVarDefault), then hides
-- Blizzard's damage numbers again if that option is on.
function FFT:ResetBlizzardCVars()
    if InCombatLockdown() then
        Print("can't change game settings during a fight; try again after it.")
        return
    end
    local before = {}
    for _, cvar in ipairs(RESET_CVARS) do
        local default = C_CVar.GetCVarDefault(cvar)
        local value = C_CVar.GetCVar(cvar)
        before[cvar] = value
        if default ~= nil and value ~= nil and value ~= default then
            C_CVar.SetCVar(cvar, default)
        end
    end
    db.savedCVars = nil
    self:ApplyBlizzardText()
    -- report only what ended up different (the hidden damage numbers are hidden again)
    local changed = {}
    for _, cvar in ipairs(RESET_CVARS) do
        local now = C_CVar.GetCVar(cvar)
        if before[cvar] ~= nil and now ~= before[cvar] then
            changed[#changed + 1] = ("%s %s -> %s"):format(cvar, before[cvar], now)
        end
    end
    if #changed == 0 then
        Print("game combat text settings were already at their defaults.")
    else
        Print("reset to game defaults:")
        for _, line in ipairs(changed) do Print("  " .. line) end
    end
    if db.enabled and db.hideBlizzard then
        Print("the ones this addon replaces stay hidden while their feature is on.")
    end
end

-- Your totems' hits are matched through their nameplates (OnMinionCast), so they need the CVar
-- nameplateShowFriendlyPlayerTotems = 1. The addon can't set it: Forever's CVar list marks it
-- secure, and C_CVar.SetCVar requires a non-secure CVar (CVarDocumentation: RequiresNonSecureCVar,
-- failing silently). A /console command typed by the player can. So at login, if it's off,
-- say so once. Only for characters with totem slots (GetNumTotemSlots), not a class check.
function FFT:TotemPlatesReminder()
    C_Timer.After(6, function() -- after the login chat spam, and after the Combat Log check at 5s
        if not (db.enabled and db.showPet) then return end
        -- the Combat Log tells your totems' hits by itself
        if FFT:ClogActive() then return end
        local slots = Plain(GetNumTotemSlots())
        if not slots or slots < 1 then return end
        if C_CVar.GetCVar("nameplateShowFriendlyPlayerTotems") == "1" then return end
        Print("totem nameplates are off, so your totems' hits aren't shown. "
            .. "To show them, type: /console nameplateShowFriendlyPlayerTotems 1")
    end)
end

-- (1.30.0) Enemy nameplates off (CVar nameplateShowEnemies; the game's own tutorial sets it,
-- Blizzard_Tutorial.lua): the game reports hits on your target only (FFT.TargetPseudo), so other
-- mobs' numbers can't show. A hunter's 2026-11-10 21:15 log: four fights with them off, nothing
-- shown and nothing said. Said once a session, at the first fight with them off.
function FFT.EnemyPlatesNotice()
    if FFT.platesNoticed then return end
    local ok, value = pcall(C_CVar.GetCVar, "nameplateShowEnemies")
    if not ok or value ~= "0" then return end
    FFT.platesNoticed = true
    Log("enemy nameplates are off: only your target's hits are reported")
    Print("enemy nameplates are off, so only your current target's damage can show, at the damage "
        .. "position (Damage options). Turn enemy nameplates on to see your damage on every enemy.")
end

-- /fft cvars: which of these settings the game has, their values and defaults
function FFT:ListCVars()
    for _, cvar in ipairs(RESET_CVARS) do
        local value = C_CVar.GetCVar(cvar)
        if value == nil then
            Print(cvar .. " = |cff888888(not in this client)|r")
        else
            Print(("%s = %s (default %s)"):format(cvar, S(value), S(C_CVar.GetCVarDefault(cvar))))
        end
    end
end

------------------------------------------------------------------------
-- Test, status, debug
------------------------------------------------------------------------
-- (1.30.0) a few numbers at the damage spot (Spots.lua), whichever placement is chosen
function FFT:TestDamageSpot()
    local samples = {{"1234", 1, false}, {"2468", 4, true}, {"512", 8, false}}
    for i, s in ipairs(samples) do
        C_Timer.After((i - 1) * 0.25, function()
            local x, y = FFT:SpotAnchor("damage")
            FFT:Show(nil, s[1], SchoolColor(s[2]), s[3], {anchorX = x, anchorY = y, key = "damage"})
        end)
    end
end

function FFT:Test()
    local plate = FFT.TargetPlate()
    local samples = {
        {"1234", 1, false}, {"2468", 4, true}, {"512", 16, false}, {"310", "auto", false},
        {"777", 32, false}, {"15.2K", 64, true}, {"321", 8, false}, {"999", 2, false},
    }
    for i, s in ipairs(samples) do
        C_Timer.After((i - 1) * 0.25, function()
            local color
            if s[2] == "auto" then
                color = db.schoolColors and Color("colorAuto") or WHITE
            else
                color = SchoolColor(s[2])
            end
            -- the auto attack sample is a glancing one, so its size shows
            -- (1.30.0) at the damage spot when that's chosen, or your target has no nameplate
            local at, opts = FFT.DamagePlace(plate, s[2] == "auto" and HitOpts({glancing = true}) or nil)
            FFT:Show(at, s[1], color, s[3], opts)
        end)
    end
    if db.showMisses then
        C_Timer.After(#samples * 0.25, function()
            local at, opts = FFT.DamagePlace(plate)
            FFT:Show(at, DODGE, Color("colorMiss"), false, opts)
        end)
    end
    if db.showHeals and FFT.TestHeals then FFT:TestHeals() end
    if db.showIncoming and FFT.TestIncoming then FFT:TestIncoming() end
    if db.showAlerts and FFT.TestAlerts then FFT:TestAlerts() end
    if db.showPower and FFT.TestPower then FFT:TestPower() end
    if db.showLoot and FFT.TestLoot then FFT:TestLoot() end
    if (db.showGameProcs or db.showStormstrikeReset) and FFT.TestProcs then FFT:TestProcs() end -- (1.31.0)
    if FFT.TestNotices then FFT:TestNotices() end -- (1.31.0)
end

local RESTRICTIONS = {"Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map"}

function FFT:Status()
    Print(("enabled: %s, show numbers on: %s, in group: %s"):format(
        tostring(db.enabled), db.scope, tostring(IsInGroup())))
    Print("Combat Log: " .. self:ClogStatus())
    -- your totems' hits can only be matched when their nameplates exist (see OnMinionCast)
    local totemPlates = C_CVar.GetCVar("nameplateShowFriendlyPlayerTotems")
    if self:ClogActive() then
        Print("totem nameplates: " .. tostring(totemPlates) .. " (not needed while the Combat Log is in use)")
    else
        Print("totem nameplates: " .. (totemPlates == "1" and "on (your totems' hits can be matched)" or
            "off, so your totems' hits are left out. To match them: /console nameplateShowFriendlyPlayerTotems 1"))
    end
    if UnitExists("target") then
        local threat = MyThreat("target")
        Print("your threat on target: " .. (threat and tostring(threat) or "hidden (using the fallback)"))
    end
    if C_RestrictedActions and Enum.AddOnRestrictionType then
        local on = {}
        for _, name in ipairs(RESTRICTIONS) do
            local v = Enum.AddOnRestrictionType[name]
            if v and Plain(C_RestrictedActions.IsAddOnRestrictionActive(v)) then on[#on + 1] = name end
        end
        Print("addon restrictions active: " .. (#on > 0 and table.concat(on, ", ") or "none"))
    end
    if db.showPower then
        Print("resource gains: " .. (FFT.PowerFeedText and FFT:PowerFeedText() or "?"))
    end
    if FeedWanted() then Print("combat text feed: " .. self:CombatTextState()) end
end

function FFT:ToggleDebug()
    logging = not logging
    if logging then
        wipe(log)
        StartSavedLog("recording started")
        Log("combat text: %s", self:CombatTextState())
        self:LogCombatTextCVars()
        Print("recording. Fight a bit, then /fft copy, or /reload to save it to the SavedVariables file.")
    else
        if ForeverFloatingTextLog then ForeverFloatingTextLog.recording = false end
        Print("recording stopped. /reload saves it to the SavedVariables file; /fft clearlog empties it.")
    end
end

function FFT:ClearLog()
    ForeverFloatingTextLog = {lines = {}, recording = logging}
    Print("saved log emptied.")
end

-- After a /reload, carry on recording if it was on
function FFT:ResumeLog()
    if ForeverFloatingTextLog and ForeverFloatingTextLog.recording then
        logging = true
        StartSavedLog("recording resumed after reload")
        Print("still recording (/fft debug stops it).")
    end
end

function FFT:CopyLog()
    if not ns.ShowCopyWindow then return end
    ns.ShowCopyWindow(#log > 0 and table.concat(log, "\n") or "Nothing recorded. Type /fft debug first.")
end

------------------------------------------------------------------------
-- Combat Log state, for the log and /fft clog (the matching itself is "Combat Log mode")
------------------------------------------------------------------------
-- (1.15.3: the 1.13.2-1.14.5 probe is gone. What it showed in game is written where it's used:
-- totems in "Your totems, guardians and pet", the Combat Log in "Combat Log mode".)
local function Try(f, ...) -- first return of f as text; "error" if it can't be called
    local ok, v = pcall(f, ...)
    if not ok then return "error" end
    return S(v)
end

local function ClogState()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and Try(C_AddOns.IsAddOnLoaded, "Blizzard_CombatLog") or "?"
    local enabled = C_CombatLog and Try(C_CombatLog.AreFilteredEventsEnabled) or "?"
    local restricted = C_CombatLog and Try(C_CombatLog.IsCombatLogRestricted) or "?"
    local frame = _G.ChatFrame2
    local shown = frame and Try(frame.IsShown, frame) or "no frame"
    return ("Blizzard_CombatLog loaded %s, messages on %s, restricted %s, Combat Log window shown %s, "
        .. "replayed old lines skipped %d"):format(loaded, enabled, restricted, shown, clog.replayed or 0)
end

function FFT:ClogStateText() return ClogState() end

-- /fft clog: check the Combat Log again, turn its messages on, and say how it stands
function FFT:ClogEnable()
    self:ClogStart()
    Print("Combat Log: " .. self:ClogStatus())
    Print("  " .. ClogState())
    Log("/fft clog: %s; %s", self:ClogStatus(), ClogState())
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_COMBAT")
events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("COMBAT_LOG_MESSAGE")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("PLAYER_SWING")
events:RegisterEvent("PLAYER_TARGET_CHANGED") -- (1.30.0) FFT.TargetPseudo
-- (1.24.0) resource gains on you, periodic ones too (Mana Spring Totem): see ENERGY_CVARS
events:RegisterEvent("COMBAT_TEXT_UPDATE")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")

-- Your minions' casts come for their own units (nameplateN, pet), so this listens to all units
local minionEvents = CreateFrame("Frame")
minionEvents:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
minionEvents:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if db and db.enabled and not IsSecret(unit) and unit ~= "player" then FFT:OnMinionCast(unit, spellID) end
end)

events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_COMBAT" then
        if db then FFT:OnUnitCombat(...) end
    elseif event == "COMBAT_TEXT_UPDATE" then
        if db and db.enabled and FFT.OnCombatText then FFT:OnCombatText(...) end
    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        if db then FFT:OnThreatUpdate(...) end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if db and not IsSecret(unit) then
            local plate = PlateOf(unit)
            if plate then plates[plate] = nil; PlateState(plate, unit) end
            if plate and FFT.targetKey and FFT.IsTarget(unit) then FFT.Rekey(FFT.targetKey, plate) end -- (1.30.0)
            FFT:OnMinionPlateAdded(unit)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        if not IsSecret(unit) then FFT:OnMinionPlateRemoved(unit) end
        local plate = not IsSecret(unit) and PlateOf(unit)
        if plate and db and FFT.IsTarget(unit) then FFT.Rekey(plate, FFT.TargetPseudo()) end -- (1.30.0)
        if plate then
            DetachPlate(plate)
            plates[plate] = nil
            FFT:ForgetPlateDots(plate)
        end
    elseif event == "ADDON_LOADED" then
        if ... == ADDON then
            ForeverFloatingTextDB = ForeverFloatingTextDB or {}
            db = ForeverFloatingTextDB
            if db.scope == "fighting" then db.scope = "mine" end -- from 1.0
            db.groupMode = nil
            db.grayAutoAttacks = nil -- 1.6: auto attacks now simply have their own color
            -- 1.23.1: alerts got their own text; keep how they looked (nameplate text x alertScale)
            if db.alertScale ~= nil and db.alertSize == nil then
                local base = type(db.size) == "number" and db.size or FFT.DEFAULTS.size
                local scale = type(db.alertScale) == "number" and db.alertScale or 1.4
                db.alertSize = math.max(8, math.min(40, math.floor(base * scale + 0.5)))
                if type(db.font) == "string" then db.alertFont = db.font end
                if type(db.outline) == "string" then db.alertOutline = db.outline end
            end
            db.alertScale = nil
            -- (1.30.0) five spots became three: heals without a nameplate show with your damage, and
            -- the damage spot (new) starts where the heal spot was; resource gains show with alerts
            if db.damageX == nil and type(db.healFallbackX) == "number" and type(db.healFallbackY) == "number" then
                db.damageX, db.damageY = db.healFallbackX, db.healFallbackY
            end
            for _, k in ipairs({"healFallbackX", "healFallbackY", "healFont", "healOutline", "healSize",
                "powerX", "powerY", "powerFont", "powerOutline", "powerSize"}) do db[k] = nil end
            for k, v in pairs(FFT.DEFAULTS) do
                if db[k] == nil then db[k] = v end
            end
            -- (1.30.4) the alerts spot still at the old default moves to the new one, once; a place
            -- the player chose (anything else, or 120 picked again later) stays
            if not db.alertsSpot2 then
                if db.alertsX == 0 and db.alertsY == 120 then db.alertsY = FFT.DEFAULTS.alertsY end
                db.alertsSpot2 = true
            end
            -- (1.31.0) the draft saved the buffs' green as the procs color: the new default, once
            if not db.procColors2 then
                if db.colorProc == "ff1aff1a" then db.colorProc = FFT.DEFAULTS.colorProc end
                db.procColors2 = true
            end
            -- (1.31.0) the new layout (the author's go, 2026-11-12): "Killing Blow!" off
            -- (the kill line doesn't say a mob from a player), once; turned on again, it stays
            if not db.layout2 then
                db.showKills = false
                db.layout2 = true
            end
            if not db.ccOff2 then -- (1.31.0) a draft saved crowd control on: off, once
                db.showCrowdControl = false
                db.ccOff2 = true
            end
            if not db.cooldownMin5 then -- (1.31.3) the old default 10 becomes the new one, once
                if db.cooldownMin == 10 then db.cooldownMin = FFT.DEFAULTS.cooldownMin end
                db.cooldownMin5 = true
            end
            for _, k in ipairs(FFT.LOCKED) do db[k] = FFT.DEFAULTS[k] end -- (1.23.0) not in the menu
            FFT.db = db
            if ns.CreateOptions then ns.CreateOptions(FFT) end
            FFT:ResumeLog()
        elseif ... == "Blizzard_CombatText" and db then
            -- (1.24.0) it loads when SELF_CVAR goes on; hide its text as the settings say
            FFT:ApplyBlizzardCombatTextFrame()
        end
    elseif event == "PLAYER_LOGIN" then
        FFT:ApplyBlizzardText()
        FFT:CleanLearned()
        FFT:TotemPlatesReminder()
        -- Blizzard_CombatLog (and its saved filters) may load a little after login
        FFT:ClogStart()
        C_Timer.After(5, function() FFT:ClogStart() end)
        C_Timer.NewTicker(2, function() FFT:ClogKeepOn() end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        lastCast = GetTime()
        FFT:NoteCastFinished()
        if db then
            local _, castGUID, spellID = ...
            FFT:OnOwnCast(spellID, castGUID)
            FFT:OnPlayerCast(castGUID, spellID)
        end
    elseif event == "PLAYER_SWING" then
        if db then
            local swingDuration, swingType = ...
            FFT:OnSwing(swingType, swingDuration)
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        if db then
            local _, target, castGUID = ...
            FFT:NoteCastSent(castGUID)
            FFT:OnCastSent(target, castGUID)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if db then FFT:OnInterrupted(...) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if blizzardPending then FFT:ApplyBlizzardText() end
        if db and FFT.OnCombatState then FFT:OnCombatState(false) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        FFT.targetKey = nil -- (1.30.0) a new key for the new target (FFT.TargetPseudo)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if db and FFT.OnCombatState then FFT:OnCombatState(true) end
        if db and db.enabled then FFT.EnemyPlatesNotice() end
        -- a fight starts: make sure the Combat Log's messages are on (hiding its window turns them off)
        if db then
            FFT:ClogStart()
            -- why not, when not (the 20:05 log only said "not in use", with no line of yours at all)
            Log("fight starts; Combat Log: %s%s", FFT:ClogStatus(),
                FFT:ClogActive() and "" or ("; " .. FFT:ClogStateText()))
            FFT.probe.lines = math.min(FFT.probe.lines, 3) -- (1.31.14) two more lines' text, each fight
        end
    elseif event == "COMBAT_LOG_MESSAGE" then
        if db and db.enabled then
            local text, r, g, b, order = ...
            FFT.Probe.Line(text)
            FFT:OnClogMessage(r, g, b, order)
        end
    elseif event == "PLAYER_LOGOUT" then
        -- also on /reload; the game saves Blizzard_CombatLog_Filters after this
        if db then
            pcall(FFT.WriteOwnClogFilter, FFT)
            pcall(FFT.RestoreBlizzardTextForLogout, FFT) -- (1.27.1) set again at the next login
        end
    end
end)

SLASH_FOREVERFLOATINGTEXT1 = "/fft"
SlashCmdList.FOREVERFLOATINGTEXT = function(msg)
    local rest = (msg or ""):match("^%s*%S+%s+(.-)%s*$") -- (1.31.0) a buff's name for /fft hide, as typed
    msg = (msg or ""):lower():match("^%s*(%S*)")
    if msg == "test" then
        FFT:Test()
    elseif msg == "status" then
        FFT:Status()
    elseif msg == "debug" then
        FFT:ToggleDebug()
    elseif msg == "reset" then
        FFT:ResetBlizzardCVars()
    elseif msg == "cvars" then
        FFT:ListCVars()
    elseif msg == "move" then
        FFT:ToggleAllMovers()
    elseif msg == "lock" then -- (1.31.0) every position box away at once
        FFT:LockAllMovers()
    elseif msg == "hide" or msg == "unhide" then -- (1.31.0) the buffs hide list (Alerts.lua)
        FFT:HideBuff(rest, msg == "hide")
    elseif msg == "clearlog" then
        FFT:ClearLog()
    elseif msg == "heals" then
        FFT:HealStatus()
    elseif msg == "forget" then
        FFT:ForgetHots()
        db.swingAnims = nil -- (1.29.0) the swing delays learned per weapon
        Print("forgot the swing delays learned per weapon")
    elseif msg == "copy" then
        FFT:CopyLog()
    elseif msg == "clog" then
        FFT:ClogEnable()
    elseif msg == "on" or msg == "off" then
        db.enabled = (msg == "on")
        FFT:ApplyBlizzardText()
        Print(db.enabled and "on" or "off")
    elseif msg == "help" then
        Print("/fft (options), /fft test, /fft status, /fft clog, /fft debug, /fft copy, /fft cvars, /fft reset, /fft heals, /fft forget, /fft move, /fft lock, /fft hide <buff>, /fft unhide <buff>, /fft clearlog, /fft on, /fft off")
    elseif ns.OpenOptions then
        ns.OpenOptions()
    end
end
