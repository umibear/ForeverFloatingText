-- Forever Floating Text simulator: a raid boss fight, run through the addon's real code, and a report.
-- Loaded by sim.html after wowstub.lua, in a fresh Lua state for every run.
--
-- The fight: you (an Enhancement shaman, as the author plays) and N other players hit one boss. Every hit
-- is tagged behind the addon's back as yours or someone else's (its amount carries a hidden id);
-- the addon sees only what the game shows it. Then: which of your hits it showed, which it
-- missed, and which of others' it showed as yours.
--
-- Timings, all from the author's /fft debug logs (see NOTES.md) unless said otherwise:
--   your swing: PLAYER_SWING + its Combat Log line in one frame, its hit 0.449-0.468 s later,
--     now and then ~0.526 s (dungeon log 2026-11-07 16:31)
--   Flametongue: its line and its Fire hit in one frame, the swing's frame (4 of 5) or ~0.12 s
--     after (1 of 5) (solo log 2026-11-07 08:39); on every swing that lands
--   Earth Shock / Flame Shock: cast, cast line, damage line and hit in one frame
--   DoT ticks: line and hit together, the hit up to 0.035 s after (42 logged matches: never before)
--   Searing Totem: cast line, damage line, hit (dungeon log 2026-11-07 16:31, see below)
--   Windfury, Flurry, Stormstrike delaying the swing (2026-11-09 logs, see You)
-- Others' timings are rough class rhythms (a guess, not measured): what matters is that their
-- hits land at all sorts of moments on the same boss. The dungeon log backs that: hits came
-- 5.2 a second, their gaps as random arrivals would give (<=0.02 s 9%, <=0.08 s 34%, <=0.16 s
-- 56%), 9% of frames with a hit had two or more.

local CONFIG = assert(load(SIM_CONFIG_SRC))()
local OTHERS = CONFIG.others or 20
local DURATION = CONFIG.duration or 300
local SWING_DELAY = CONFIG.swingDelay or {0.449, 0.468}

------------------------------------------------------------------------
-- A repeatable random stream (the same seed gives the same fight)
------------------------------------------------------------------------
-- (1.28.1) Park-Miller in floating point: every step stays below 2^53, so it's exact and the same in
-- every Lua. The old one (state * 1103515245) overflowed the browser's 32-bit integers (fengari)
-- differently from real Lua's 64-bit ones, and GitHub's lua5.3 played other fights than sim.html.
local state = ((CONFIG.seed or 1) * 7919 + 13) % 2147483646 + 1.0
local function rnd()
    state = (state * 16807.0) % 2147483647.0
    return state / 2147483647.0
end
local function between(a, b) return a + (b - a) * rnd() end

------------------------------------------------------------------------
-- The addon, loaded as the game would (Options.lua left out: it's only the settings window)
------------------------------------------------------------------------
local function Patch(src, patches)
    for _, p in ipairs(patches or {}) do
        local i, j = src:find(p[1], 1, true)
        if not i then error("patch not found in Core.lua: " .. p[1]) end
        src = src:sub(1, i - 1) .. p[2] .. src:sub(j + 1)
    end
    return src
end

local ns = {}
local ADDON_FILES = {
    {"Core.lua", Patch(SRC_Core_lua, CONFIG.patches)},
    {"Spots.lua", SRC_Spots_lua},
    {"Heals.lua", SRC_Heals_lua},
    {"Incoming.lua", SRC_Incoming_lua},
    {"Alerts.lua", SRC_Alerts_lua},
    {"Procs.lua", SRC_Procs_lua},
}

-- what you knew before this fight (learned in earlier fights; the author's saved settings have these)
ForeverFloatingTextDB = {}
if CONFIG.learned ~= false then
    ForeverFloatingTextDB.spellSchools = {["Earth Shock"] = 8, ["Flame Shock"] = 4}
    ForeverFloatingTextDB.dotPeriods = {["Flame Shock"] = {period = 3, ticks = 4, school = 4}}
    ForeverFloatingTextDB.minionSchools = {[3606] = 4}
    ForeverFloatingTextDB.learnVersion = 2
end
for k, v in pairs(CONFIG.settings or {}) do ForeverFloatingTextDB[k] = v end

for _, f in ipairs(ADDON_FILES) do
    local chunk = assert(load(f[2], "@" .. f[1]))
    chunk("ForeverFloatingText", ns)
end
local FFT = ns.FFT

------------------------------------------------------------------------
-- The world
------------------------------------------------------------------------
SIM.inGroup = (OTHERS > 0) or CONFIG.inGroup == true
SIM.inRaid = OTHERS > 4 -- (1.30.7) more than a party of five
SIM.units.player = {guid = "Player-1-0001", name = "Name"}
SIM.AddUnit("nameplate1", {guid = "Creature-0-1-1-1-1-BOSS", name = "Boss", enemy = true})
SIM.target = "nameplate1"
SIM.spells[8042] = {name = "Earth Shock", harmful = true}
SIM.spells[8050] = {name = "Flame Shock", harmful = true}
SIM.spells[3599] = {name = "Searing Totem"}
SIM.spells[3606] = {name = "Attack", harmful = true}
SIM.spells[17364] = {name = "Stormstrike", harmful = true}

local BOSS = "nameplate1"
local truth = {}       -- id -> {who = "you" | "other", kind}
local nextId = 0
local function NewId(who, kind)
    nextId = nextId + 1
    truth[nextId] = {who = who, kind = kind, t = SIM.now}
    return nextId
end
local function Amount(id) if SIM.inGroup then return SIM.Secret(id) end return id end

-- a hit (or not) on the boss, as UNIT_COMBAT. outcome: "hit", "crit", "glancing", or a miss word
local function Combat(id, school, outcome)
    truth[id].at = SIM.now -- when the hit came (CONFIG.listMissed)
    if outcome == "hit" or outcome == "crit" or outcome == "glancing" then
        local flag = outcome == "crit" and "CRITICAL" or outcome == "glancing" and "GLANCING" or ""
        SIM.Fire("UNIT_COMBAT", BOSS, "WOUND", flag, Amount(id), school)
    else
        truth[id].miss = true
        SIM.Fire("UNIT_COMBAT", BOSS, outcome, "", Amount(0), school)
    end
end

local function MeleeOutcome(glance)
    local r = rnd()
    if r < 0.06 then return "MISS" end
    if r < 0.10 then return "DODGE" end
    if r < 0.10 + (glance or 0.25) then return "glancing" end
    if r < 0.45 then return "crit" end
    return "hit"
end
local function SpellOutcome()
    local r = rnd()
    if r < 0.04 then return "RESIST" end
    if r < 0.14 then return "crit" end
    return "hit"
end
local function Landed(o) return o == "hit" or o == "crit" or o == "glancing" end

------------------------------------------------------------------------
-- You
------------------------------------------------------------------------
local castN = 0
local lastCastAt = -100 -- (1.28.0) any cast of yours before a swing's hit delays that hit
local function Cast(spellID)
    lastCastAt = SIM.now
    castN = castN + 1
    local guid = "Cast-3-0-0-" .. spellID .. "-" .. castN
    SIM.Fire("UNIT_SPELLCAST_SENT", "player", "Boss", guid, spellID)
    SIM.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, spellID)
    SIM.ClogLine("SPELL_CAST_SUCCESS")
end

local FIGHT_START = 3

-- (1.28.0) What the author's 2026-11-09 logs showed, on unless CONFIG.enhancement == false:
--   Flurry: after a crit of yours the next 3 swings hit 0.415 s after PLAYER_SWING (0.415-0.416)
--   Stormstrike with a swing (in its frame or up to 0.44 s after, before the hit): its line and
--     physical hit in the cast's frame; the swing's hit then at 0.993-0.999 s
--   Windfury: on a swing that lands, 20%: two damage lines in the swing's frame, the two attacks'
--     hits 0.228-0.233 and 0.494-0.505 s later (a miss brings its miss line with it), the swing's
--     own hit 0.958-0.963 s after the lines
-- The rates (Stormstrike on 30% of swings, Windfury 20%) are rough, not measured.
local ENHANCEMENT = CONFIG.enhancement ~= false
local flurry = 0 -- swings left with Flurry's shorter delay
-- (1.29.1) CONFIG.weapon = "3.10": the author's newer weapon (2026-11-10 18:53 and 19:58 logs, solo,
-- with the game's file). Its swings hit after one of three delays at random (0.360-0.373: 20,
-- 0.464-0.468: 16, 0.728-0.734: 12), with Flurry ("2.77s") 0.320 / 0.414 / 0.651. Windfury's first
-- attack at half of a plain delay (0.18, 0.23, 0.37), the second at 0.50, or 0.755 when the swing's
-- own delay is the long one (all three such cases), the swing's own hit 0.50 / 0.755 plus its delay
-- after the lines. A cast before the hit: 0.997 s, or 1.495 for the long delay (Flurry 0.887 / 1.334).
local NEW_WEAPON = CONFIG.weapon == "3.10"
local NEW_DELAYS = {0.366, 0.464, 0.731}
local NEW_FLURRY = {0.320, 0.414, 0.651}
local function NewWeaponDelay()
    local r = rnd()
    return r < 0.42 and 1 or r < 0.75 and 2 or 3
end

local function Stormstrike()
    Cast(17364)
    local id = NewId("you", "Stormstrike")
    local o = MeleeOutcome(0) -- a special attack doesn't glance
    if o == "crit" then flurry = 3 end
    if Landed(o) then SIM.ClogLine("SPELL_DAMAGE") else SIM.ClogLine("SPELL_MISSED", o) end
    Combat(id, 1, o)
end

local function You()
    -- swings, 3.5 s two-hander
    local t = FIGHT_START + 0.3
    while t < FIGHT_START + DURATION do
        local ts = t
        SIM.At(ts, function()
            -- (1.25.1) reported as 3.30 s, the author's weapon (2026-11-09 08:33 log); Core only logs it
            -- (1.28.14) a Flurry swing reports 2.95 s (every one in the 2026-11-10 15:25 log)
            local hasted = CONFIG.enhancement ~= false and flurry > 0
            SIM.Fire("PLAYER_SWING", NEW_WEAPON and (hasted and 2.77 or 3.10) or (hasted and 2.95 or 3.30), 0)
            local o = MeleeOutcome()
            local id = NewId("you", "swing")
            if Landed(o) then SIM.ClogLine("SWING_DAMAGE") else SIM.ClogLine("SWING_MISSED", o) end
            -- dungeon log 2026-11-07 16:31: 30 of 31 at 0.449-0.468 s, one at 0.526 s
            local delay, which
            if NEW_WEAPON then
                which = NewWeaponDelay()
                delay = NEW_DELAYS[which] + between(-0.005, 0.005)
            else
                delay = rnd() < (CONFIG.swingLate or 0.03) and between(0.52, 0.53)
                    or between(SWING_DELAY[1], SWING_DELAY[2])
            end
            local long = which == 3
            local fast = false -- a Flurry swing
            local waitFrom = SIM.now - 0.002 -- a cast of yours from here until the hit delays it
            if ENHANCEMENT then
                if flurry > 0 then
                    flurry = flurry - 1
                    delay = NEW_WEAPON and NEW_FLURRY[which] + between(-0.004, 0.004) or between(0.414, 0.417)
                    fast = true
                end
                local r = rnd()
                if Landed(o) and r < 0.2 then
                    -- Windfury: its lines, its two attacks and the delayed swing later.
                    -- (1.28.11) The lines come in the swing's frame or ~0.10 s after it (the kept
                    -- logs: 29 and 15 of 44 procs), and everything is timed from the lines. But in
                    -- 2 of those 15 the lines came late and the hits were timed from the swing
                    -- (2026-11-10 12:33 log 7407.949; 2026-11-09 14:54 log 578648.388).
                    local kind = rnd()
                    local linesAfter = kind < 0.65 and 0 or between(0.099, 0.116)
                    local base = kind >= 0.95 and 0 or linesAfter
                    local function Lines() SIM.ClogLine("SPELL_DAMAGE"); SIM.ClogLine("SPELL_DAMAGE") end
                    if linesAfter == 0 then Lines() else SIM.At(SIM.now + linesAfter, Lines) end
                    local slots = NEW_WEAPON
                        and {NEW_DELAYS[NewWeaponDelay()] / 2 + between(-0.003, 0.003),
                            (long and 0.755 or 0.502) + between(-0.003, 0.003)}
                        or {between(0.228, 0.233), between(0.494, 0.505)}
                    for _, after in ipairs(slots) do
                        local wid = NewId("you", "Windfury")
                        local wo = MeleeOutcome(0)
                        SIM.At(SIM.now + base + after, function()
                            if not Landed(wo) then SIM.ClogLine("SPELL_MISSED", wo) end
                            Combat(wid, 1, wo)
                        end)
                    end
                    if NEW_WEAPON then
                        delay = base + (long and 0.755 or 0.50) + delay
                    else
                        delay = base + (fast and between(0.905, 0.911) or between(0.958, 0.963))
                    end
                    -- (1.28.14) a Windfury swing waits only for a cast from 0.50 s after the proc
                    -- (0.46 s before its hit): Stormstrike 0.19 s, Totemic Recall 0.22 s after the
                    -- proc and one in the swing's own frame left it at 0.96 (2026-11-10 15:25 log,
                    -- 17824.851, 17764.231, 17956.964); the delayed ones had it 0.81-0.83 s after
                    waitFrom = SIM.now + base + 0.5
                elseif r < 0.5 then
                    -- a Stormstrike before the swing's hit lands: the hit waits for it (below)
                    SIM.At(SIM.now + (rnd() < 0.5 and 0 or between(0.01, 0.44)), Stormstrike)
                end
                if o == "crit" then flurry = 3 end
            end
            if ENHANCEMENT then
                -- (1.28.13) Any cast of yours from the swing until its hit makes the hit wait: 0.534 s
                -- more (0.461 -> 0.995), on a Flurry swing 0.472 s (0.415 -> 0.887: 2026-11-10 13:50
                -- log, 12134.959 and 12137.976). A Windfury swing's too: 0.96 -> 1.49 s after the proc
                -- (12379.054; with Flurry 1.385, 12108.084). Before, proc swings never waited here.
                local swingAt = SIM.now
                SIM.At(swingAt + delay, function()
                    if NEW_WEAPON and lastCastAt >= waitFrom and SIM.now - swingAt < 0.8 then
                        -- a plain swing delayed by a cast: at a fixed moment after the swing
                        local at = long and (fast and 1.334 or 1.495) or (fast and 0.887 or 0.997)
                        SIM.At(swingAt + at + between(-0.003, 0.003), function() Combat(id, 1, o) end)
                    elseif lastCastAt >= waitFrom then
                        SIM.At(SIM.now + (fast and between(0.470, 0.474) or between(0.532, 0.538)),
                            function() Combat(id, 1, o) end)
                    else
                        Combat(id, 1, o)
                    end
                end)
            else
                SIM.At(SIM.now + delay, function() Combat(id, 1, o) end)
            end
            if Landed(o) then
                local ft = NewId("you", "Flametongue")
                local fo = SpellOutcome()
                local function Proc()
                    if Landed(fo) then SIM.ClogLine("SPELL_DAMAGE") else SIM.ClogLine("SPELL_MISSED", fo) end
                    Combat(ft, 4, fo)
                end
                -- dungeon log 2026-11-07 16:45: 78 of 80 0.02-0.05 s after PLAYER_SWING, 7 0.06-0.09 s
                SIM.At(SIM.now + (rnd() < 0.9 and between(0.02, 0.045) or between(0.06, 0.09)), Proc)
            end
        end)
        t = t + 3.5
    end
    -- shocks every 6 s, Flame Shock and Earth Shock taking turns (they share a cooldown)
    local n = 0
    t = FIGHT_START + 1.0
    while t < FIGHT_START + DURATION do
        n = n + 1
        local flame = (n % 2 == 1)
        local tc = t
        SIM.At(tc, function()
            Cast(flame and 8050 or 8042)
            local id = NewId("you", flame and "Flame Shock" or "Earth Shock")
            local o = SpellOutcome()
            if Landed(o) then SIM.ClogLine("SPELL_DAMAGE") else SIM.ClogLine("SPELL_MISSED", o) end
            Combat(id, flame and 4 or 8, o)
            if flame and Landed(o) then
                for k = 1, 4 do
                    -- 16:45 log: 29 of 29 tick lines -0.011..+0.016 s from 3k s after the cast
                    local tick = SIM.now + 3 * k + between(-0.011, 0.016)
                    local id2 = NewId("you", "Flame Shock tick")
                    -- (1.28.14) the hit in its line's frame: 20 of 20 ticks in the 2026-11-10 15:25
                    -- dungeon log, and every tick of the kept solo logs (it was "or up to 0.035 s
                    -- after" for 1 in 5: only Searing Totem's lines come before their hits)
                    rnd() -- (keeps the random numbers of everything else as they were)
                    local off = 0
                    SIM.At(tick, function() SIM.ClogLine("SPELL_PERIODIC_DAMAGE") end)
                    SIM.At(tick + off, function() Combat(id2, 4, "hit") end)
                end
            end
        end)
        t = t + 6 + between(0, 0.4)
    end
    -- Searing Totem: dropped before the pull, attacks every 2.5 s (no totem nameplate in a raid).
    -- Dungeon log 2026-11-07 16:31, 36 attacks: its cast line (no cast of yours in that frame),
    -- its damage line 0-0.53 s later, its hit after that line: same frame 12, 0.006-0.02 s 11,
    -- 0.026-0.059 s 9, 0.07-0.18 s 4.
    -- 16:45 log: attacks 2.42-2.46 s apart; cast to hit 0.1-0.6 s, and on one mob the same flight
    -- from one attack to the next within 0.013 s in 30 of 47 (a jump now and then)
    SIM.At(FIGHT_START - 1, function() Cast(3599) end)
    t = FIGHT_START + 0.8
    local flight = between(0.1, 0.5)
    while t < FIGHT_START + DURATION do
        local ta = t
        if rnd() < 0.15 then flight = between(0.1, 0.5) end
        local f = flight + between(-0.01, 0.01)
        SIM.At(ta, function()
            SIM.ClogLine("SPELL_CAST_SUCCESS") -- the totem's own cast
            local id = NewId("you", "Searing Totem")
            local o = SpellOutcome()
            local r = rnd()
            local late = r < 0.33 and 0 or r < 0.64 and between(0.006, 0.02)
                or r < 0.89 and between(0.026, 0.059) or between(0.07, 0.19)
            late = math.min(late, f)
            SIM.At(SIM.now + f - late, function()
                if Landed(o) then SIM.ClogLine("SPELL_DAMAGE") else SIM.ClogLine("SPELL_MISSED", o) end
            end)
            SIM.At(SIM.now + f, function() Combat(id, 4, o) end)
        end)
        t = t + between(2.42, 2.46)
    end
end

------------------------------------------------------------------------
-- The others: rough class rhythms on the same boss, random phases
------------------------------------------------------------------------
local function Stream(kind, school, every, jitter, outcome, startAt)
    local t = FIGHT_START + (startAt or between(0, every))
    while t < FIGHT_START + DURATION do
        local th = t
        SIM.At(th, function()
            local id = NewId("other", kind)
            Combat(id, school, outcome())
        end)
        t = t + every + between(-jitter, jitter)
    end
end
local function Melee() return MeleeOutcome() end
local function Hit() return rnd() < 0.15 and "crit" or "hit" end

local CLASSES = {
    warrior = function()
        Stream("warrior swing", 1, 3.3, 0.05, Melee)
        Stream("Heroic Strike", 1, 6, 1.5, Melee)
    end,
    rogue = function()
        Stream("rogue swing", 1, 2.6, 0.03, Melee)
        Stream("rogue off-hand", 1, 1.8, 0.03, Melee)
        Stream("Sinister Strike", 1, 3, 0.8, Melee)
    end,
    hunter = function()
        Stream("Auto Shot", 1, 3.0, 0.1, Melee)
        Stream("Serpent Sting tick", 8, 3, 0.02, Hit)
        Stream("Arcane Shot", 64, 6, 1, Hit)
    end,
    mage = function() Stream("Frostbolt", 16, 2.6, 0.3, SpellOutcome) end,
    firemage = function()
        Stream("Fireball", 4, 3.2, 0.3, SpellOutcome)
        Stream("Ignite tick", 4, 2, 0.02, Hit)
    end,
    warlock = function()
        Stream("Shadow Bolt", 32, 2.8, 0.3, SpellOutcome)
        Stream("Corruption tick", 32, 3, 0.02, Hit)
        Stream("Immolate tick", 4, 3, 0.02, Hit)
    end,
    priest = function()
        Stream("Mind Flay tick", 32, 1, 0.05, Hit)
        Stream("Shadow Word: Pain tick", 32, 3, 0.02, Hit)
    end,
    shaman = function()
        Stream("shaman swing", 1, 3.6, 0.03, Melee)
        Stream("their Flametongue", 4, 3.6, 0.03, Hit)
        Stream("their Earth Shock", 8, 6, 0.5, SpellOutcome)
        Stream("their Searing Totem", 4, 2.5, 0.02, Hit)
    end,
    druid = function()
        Stream("cat swing", 1, 1.0, 0.02, Melee)
        Stream("Shred", 1, 4, 1, Melee)
    end,
}
-- a raid's damage dealers, in the order they're added as OTHERS grows
local RAID = {"warrior", "mage", "rogue", "hunter", "warlock", "shaman", "firemage", "rogue", "warrior",
    "priest", "mage", "hunter", "warrior", "rogue", "warlock", "druid", "mage", "warrior", "rogue",
    "hunter", "firemage", "warlock", "warrior", "mage", "rogue", "shaman", "hunter", "warrior", "mage",
    "warlock", "rogue", "priest", "warrior", "hunter", "mage", "rogue", "warlock", "firemage", "warrior"}

------------------------------------------------------------------------
-- Watching what the addon draws
------------------------------------------------------------------------
local shows = {}
local realShow = FFT.Show
FFT.Show = function(self, plate, text, color, crit, opts)
    local v = text
    if opts and opts.args then v = opts.args[1] end
    local lines = ForeverFloatingTextLog and ForeverFloatingTextLog.lines
    shows[#shows + 1] = {t = SIM.now, id = SIM.Reveal(v), why = lines and lines[#lines] or "",
        scale = opts and opts.scale}
    return realShow(self, plate, text, color, crit, opts)
end

------------------------------------------------------------------------
-- Login, the pull, the fight
------------------------------------------------------------------------
SIM.Fire("ADDON_LOADED", "ForeverFloatingText")
FFT:WriteOwnClogFilter()          -- as the addon did at your last logout
SIM.Fire("PLAYER_LOGIN")
SlashCmdList.FOREVERFLOATINGTEXT("debug") -- the addon's own log, for the reasons in the report
SIM.At(1, function() SIM.Fire("NAME_PLATE_UNIT_ADDED", BOSS) end)
SIM.At(FIGHT_START - 0.2, function() SIM.inCombat = true; SIM.Fire("PLAYER_REGEN_DISABLED") end)
You()
for i = 1, math.min(OTHERS, #RAID) do CLASSES[RAID[i]]() end
-- clogOffAt: the Combat Log stops this many seconds into the fight (the filter switched, say);
-- before that the addon learns from it, and only hits from then on are counted
local COUNT_FROM = 0
if CONFIG.clogOffAt then
    COUNT_FROM = FIGHT_START + CONFIG.clogOffAt
    SIM.At(COUNT_FROM, function()
        if CONFIG.clogLoss == "filter" then
            -- (1.21.2) as in game: the Combat Log's filter switched to one showing everyone's
            -- actions (a part with no flag lists), the option still on
            local all = Blizzard_CombatLog_Filters
            all.filters[#all.filters + 1] = {name = "Everything", settings = {}, colors = {}, filters = {{}}}
            all.currentFilter = #all.filters
        else
            ForeverFloatingTextDB.useCombatLog = false
        end
        FFT:ClogStart()
    end)
end
SIM.RunUntil(FIGHT_START + DURATION + 3)
-- hits made before the switch don't count (their ids and shows are dropped here)
for id, h in pairs(truth) do if h.t < COUNT_FROM then truth[id] = nil end end
local COUNTED_SECONDS = FIGHT_START + DURATION - math.max(COUNT_FROM, FIGHT_START)

------------------------------------------------------------------------
-- The report
------------------------------------------------------------------------
local out = {}
local function P(fmt, ...) out[#out + 1] = fmt:format(...) end

local shownCount = {}
for _, s in ipairs(shows) do
    if type(s.id) == "number" and truth[s.id] then shownCount[s.id] = (shownCount[s.id] or 0) + 1 end
end

local yours, right, missedBy, kinds = 0, 0, {}, {}
for id, h in pairs(truth) do
    if h.who == "you" and not h.miss then
        yours = yours + 1
        kinds[h.kind] = kinds[h.kind] or {n = 0, shown = 0}
        kinds[h.kind].n = kinds[h.kind].n + 1
        if shownCount[id] then
            right = right + 1
            kinds[h.kind].shown = kinds[h.kind].shown + 1
        end
    end
end

local wrong, wrongWhy, wrongKind, doubles = 0, {}, {}, 0
local offsets = {} -- how far the line taken was from the other's hit, in frames
for _, s in ipairs(shows) do
    local h = type(s.id) == "number" and truth[s.id]
    if h and h.who == "other" then
        wrong = wrong + 1
        local why = s.why:match("show %S+ %((.*)%)$") or s.why
        local off = why:match("Combat Log line, ([%+%-]%d+%.%d+)s")
        if off then
            local f = math.floor(tonumber(off) / SIM.FRAME + 0.5)
            local key = f == 0 and "same frame" or ("%+d frames"):format(f)
            offsets[key] = (offsets[key] or 0) + 1
        end
        why = why:gsub("[%+%-]?%d+%.%d+", "#")
        wrongWhy[why] = (wrongWhy[why] or 0) + 1
        wrongKind[h.kind] = (wrongKind[h.kind] or 0) + 1
    end
end
for _, n in pairs(shownCount) do if n > 1 then doubles = doubles + n - 1 end end

local function Sorted(t)
    local list = {}
    for k, v in pairs(t) do list[#list + 1] = {k = k, v = v} end
    table.sort(list, function(a, b)
        local va = type(a.v) == "table" and a.v.n or a.v
        local vb = type(b.v) == "table" and b.v.n or b.v
        if va ~= vb then return va > vb end
        return a.k < b.k
    end)
    return list
end

local precision = (right + wrong) > 0 and 100 * right / (right + wrong) or 100
local recall = yours > 0 and 100 * right / yours or 100
local summary = ("%2d others, %ds, seed %d: your hits %d, shown %d (%.1f%%), missed %d, others' shown as yours %d (%.1f%% of what was shown)%s")
    :format(OTHERS, DURATION, CONFIG.seed or 1, yours, right, recall, yours - right, wrong, 100 - precision,
        doubles > 0 and (", shown twice " .. doubles) or "")
P("%s", summary)
if CONFIG.details then
    P("  your hits by kind:")
    for _, e in ipairs(Sorted(kinds)) do
        P("    %-18s %4d of %4d shown", e.k, e.v.shown, e.v.n)
    end
    if wrong > 0 then
        P("  others' hits shown as yours, by the reason the addon gave:")
        for _, e in ipairs(Sorted(wrongWhy)) do P("    %4d  %s", e.v, e.k) end
        P("  ... and whose they really were:")
        for _, e in ipairs(Sorted(wrongKind)) do P("    %4d  %s", e.v, e.k) end
        P("  ... taken lines, where the line was from the other's hit:")
        for _, e in ipairs(Sorted(offsets)) do P("    %4d  %s", e.v, e.k) end
    end
    local others = 0
    for _, h in pairs(truth) do if h.who == "other" then others = others + 1 end end
    P("  others' hits and misses on the boss: %.1f per second", others / COUNTED_SECONDS)
    P("  Combat Log: %s", FFT:ClogStatus())
    local learned = {}
    for name, d in pairs(ForeverFloatingTextDB.dotPeriods or {}) do
        learned[#learned + 1] = ("%s every %.2fs x%d%s"):format(name, d.period, d.ticks, d.exact and " (exact)" or "")
    end
    for school, p in pairs(ForeverFloatingTextDB.swingProcs or {}) do
        learned[#learned + 1] = ("swing proc school %d (%d seen)"):format(school, #p)
    end
    table.sort(learned)
    P("  learned: %s", table.concat(learned, "; "))
end
-- CONFIG.listMissed = n: your first n hits that weren't shown, each with what the addon logged
-- from its moment to 0.12 s after (to see why)
if CONFIG.listMissed then
    local missed = {}
    for id, h in pairs(truth) do
        if h.who == "you" and not h.miss and not shownCount[id] and h.at then missed[#missed + 1] = h end
    end
    table.sort(missed, function(a, b) return a.at < b.at end)
    P("  your hits not shown (first %d of %d):", math.min(CONFIG.listMissed, #missed), #missed)
    for i = 1, math.min(CONFIG.listMissed, #missed) do
        local h = missed[i]
        P("    %.3f %s", h.at, h.kind)
        for _, l in ipairs(ForeverFloatingTextLog.lines) do
            local t = tonumber(l:match("^(%d+%.%d+) "))
            if t and t >= h.at - 0.001 and t <= h.at + 0.12 and not l:find("WOUND") then P("        %s", l) end
        end
    end
end
if #SIM.errors > 0 then
    P("  LUA ERRORS (%d), first ones:", #SIM.errors)
    for i = 1, math.min(3, #SIM.errors) do P("    %s", SIM.errors[i]) end
end
return table.concat(out, "\n")
