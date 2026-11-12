-- Forever Floating Text damage taken: what happens to you, at its own spot with its own font.
-- Power gains (1.22.0; periodic ones 1.24.0) are here too, at a spot of their own.
--
-- UNIT_COMBAT for "player": the action and flag names are the ones Blizzard's own
-- CombatFeedback.lua uses (WOUND with an amount; WOUND for 0 with ABSORB / BLOCK / RESIST,
-- else a miss; DODGE, PARRY, IMMUNE...). Their amounts may be hidden
-- (the author's logs: secret in groups and solo); a hidden amount is still drawn by the game.

local ADDON, ns = ...
local FFT = ns.FFT
local Plain, Log, S = ns.Plain, ns.Log, ns.S

-- UNIT_COMBAT actions on you that mean "it didn't land"; the words are the game's own strings
local AVOIDED = {
    MISS = true, DODGE = true, PARRY = true, BLOCK = true, RESIST = true,
    IMMUNE = true, EVADE = true, ABSORB = true, DEFLECT = true, REFLECT = true,
}

local function Options(fmt, args)
    local db = FFT.db
    local x, y = FFT:SpotAnchor("incoming")
    return {fmt = fmt, args = args, anchorX = x, anchorY = y, key = "incoming",
        font = db.incomingFont, outline = db.incomingOutline, size = db.incomingSize}
end

local function ShowWord(word)
    if not FFT.db.showIncomingMisses then return end
    FFT:Show(nil, word, FFT.Color("colorMiss"), false, Options())
end

function FFT:OnIncoming(action, flag, amount, school)
    local db = self.db
    if not (db.enabled and db.showIncoming) then return end
    action, flag = Plain(action), Plain(flag)
    if not action then return end
    Log("player %s %s %s school %s", action, S(flag), S(amount), S(school))

    if action == "WOUND" then
        if Plain(amount) == 0 then
            -- an attack that did nothing: the flag says how, else it missed
            ShowWord((flag and _G[flag]) or MISS)
            return
        end
        local color = db.incomingSchoolColors and ns.SchoolColor(school, true) or FFT.Color("colorIncoming")
        local crit = (flag == "CRITICAL" or flag == "CRUSHING")
        -- (1.18.0) partly blocked by your shield: "-123 (Block)", Blizzard's own string
        local fmt = (flag == "BLOCK_REDUCED" and db.markBlocked and COMBAT_TEXT_BLOCK_REDUCED)
            and ("-" .. COMBAT_TEXT_BLOCK_REDUCED) or "-%s"
        self:Show(nil, nil, color, crit, Options(fmt, {ns.FormatAmount(amount)}))
    elseif AVOIDED[action] then
        ShowWord(_G[action] or action)
    end
end

------------------------------------------------------------------------
-- (1.26.0) Who healed you. UNIT_COMBAT doesn't say; the COMBAT_TEXT_UPDATE feed does: its heal
-- kinds carry [healer, amount] (Blizzard's CombatText.lua: data = healer, arg3 = amount; drawn
-- "+420 [Name]"). Both secret even solo (2026-11-09 08:04 log), so the name is drawn, never read.
-- The feed's heal came in the heal's own moment (08:04 log, 14 of 14: 553561.739 feed, UNIT_COMBAT
-- in the same frame), so a heal on you takes the feed heal within HEALER_WINDOW of it. Your own
-- heals on you bring one too, so when more than one untaken feed heal is that close, which name
-- is whose can't be told and none is shown (precision over recall).
------------------------------------------------------------------------
-- kind -> true for a direct heal, false for a heal-over-time tick.
-- (1.26.1, the author) Names on direct heals only, as Blizzard's CombatText.lua (its "[Name]" is for HEAL
-- and HEAL_CRIT, never PERIODIC_*). Ticks are still
-- recorded: one close to a direct heal makes the name uncertain.
local HEAL_KINDS = {
    HEAL = true, HEAL_CRIT = true, HEAL_ABSORB = true, HEAL_CRIT_ABSORB = true,
    PERIODIC_HEAL = false, PERIODIC_HEAL_CRIT = false, PERIODIC_HEAL_ABSORB = false,
}
local HEALER_WINDOW = 0.1
local feedHeals = {} -- {t, name, taken}

local function NoteFeedHeal(kind)
    if not (C_CombatText and C_CombatText.GetCurrentEventInfo) then return end
    local ok, name = pcall(C_CombatText.GetCurrentEventInfo)
    local now = GetTime()
    while feedHeals[1] and now - feedHeals[1].t > 1 do table.remove(feedHeals, 1) end
    if not ok then return end
    -- a readable non-string (nil) has no name to draw; a secret one is kept as it is
    if not ns.IsSecret(name) and type(name) ~= "string" then name = nil end
    feedHeals[#feedHeals + 1] = {t = now, name = name, kind = kind, direct = HEAL_KINDS[kind]}
end

-- the healer of a heal on you at `at`, if exactly one feed heal goes with it
local function HealerFor(at)
    local found, count = nil, 0
    for _, f in ipairs(feedHeals) do
        if not f.taken and math.abs(f.t - at) <= HEALER_WINDOW then
            count = count + 1
            found = f
        end
    end
    if count ~= 1 then return nil, count end
    found.taken = true
    if not found.direct then return nil, 1, "a tick" end
    return found.name, 1
end

-- A heal on you from someone else. at: when the heal came (UNIT_COMBAT), for its healer's name
function FFT:ShowReceivedHeal(amount, flag, at)
    local db = self.db
    if not (db.enabled and db.showIncoming and db.showIncomingHeals) then return end
    local crit = (flag == "CRITICAL")
    local name, count, why
    if db.showHealerNames then name, count, why = HealerFor(at or GetTime()) end
    if name ~= nil then
        Log("  healer's name from the combat text feed")
        self:Show(nil, nil, FFT.Color("colorHeal"), crit, Options("+%s [%s]", {ns.FormatAmount(amount), name}))
    else
        if db.showHealerNames then Log("  no healer's name (%s)", why or ((count or 0) .. " feed heals with it")) end
        self:Show(nil, nil, FFT.Color("colorHeal"), crit, Options("+%s", {ns.FormatAmount(amount)}))
    end
end

------------------------------------------------------------------------
-- Power gains, at their own spot (under your character). They happen to you, so they're yours
-- however they came (your Life Tap or Bloodrage, another shaman's Mana Spring Totem). Only gains
-- the game reports count: natural regen isn't one.
--
-- Two sources:
-- * (1.24.0) COMBAT_TEXT_UPDATE "ENERGIZE" / "PERIODIC_ENERGIZE", then C_CombatText.GetCurrentEventInfo()
--   = amount, power token: what Blizzard's CombatText.lua draws ("+30 Mana").
--   Periodic gains (Mana Spring Totem) come only
--   here. Its returns may be secret (SecretReturns in CombatTextDocumentation.lua): drawn as is.
--   Needs the CVars Core.lua keeps on (ENERGY_CVARS).
-- * (1.22.0) UNIT_COMBAT "player" ENERGIZE (Blizzard's CombatFeedback.lua: amount, CRITICAL).
--   Not seen in any log so far; the 2026-11-09 07:36 log with Mana Spring Totem up has none.
-- One gain could come by both: once the feed has brought one, UNIT_COMBAT's are only logged; before
-- that, a UNIT_COMBAT gain waits FEED_WAIT and is dropped if the feed brought one meanwhile.
------------------------------------------------------------------------
local FEED_WAIT = 0.1
local feedCount, feedLast, feedLastAt = 0, nil, nil -- gains the feed brought this session

-- The power's name: the feed's token when readable (_G.MANA = "Mana", as Blizzard's CombatText.lua
-- does), else your power bar's now (UnitPowerType, no secrecy flags in Forever's
-- UnitDocumentation.lua). A druid in a form gaining mana is named wrong only in the second case.
local function PowerName(token)
    token = Plain(token)
    if type(token) ~= "string" then
        local ok, _, barToken = pcall(UnitPowerType, "player")
        token = ok and Plain(barToken)
    end
    local name = type(token) == "string" and _G[token]
    return type(name) == "string" and name or nil
end

-- (1.30.3) at the incoming spot in its font, with the rest of what happens to you (the author:
-- mana ticks among the alerts didn't feel right). 1.30.0-1.30.2 had them at the alerts spot; before, a
-- "power" spot of its own (1.22.0).
local function PowerOptions(fmt, args)
    return Options(fmt, args)
end

local function PowerFormat(token)
    local name = FFT.db.powerNames and PowerName(token)
    if not name then return "+%s" end
    return "+%s " .. (name:gsub("%%", "%%%%"))
end

-- Blizzard's CombatText.lua skips a gain of 0 ("If we didnt actually gain anything")
local function Gained(amount)
    local n = Plain(amount)
    if n == nil then return true end -- secret: the game draws it
    n = tonumber(n)
    return n ~= nil and n > 0
end

local function ShowGain(amount, crit, token)
    FFT:Show(nil, nil, FFT.Color("colorPower"), crit, PowerOptions(PowerFormat(token), {ns.FormatAmount(amount)}))
end

-- (1.24.1, probe) every other kind the feed brings, with each value or <secret>, only while
-- /fft debug records. To learn what's there before building anything on it: partial
-- block / resist / absorb amounts on you (BLOCK, RESIST, ABSORB and SPELL_ ones: damage, then the
-- part stopped), the healer's name (HEAL, HEAL_CRIT: name, amount). Return order as Blizzard's
-- CombatText.lua reads them (data, arg3, arg4).
-- (1.25.1) Kinds already seen are no longer logged (2026-11-09 08:04 and 08:33 logs, values all
-- secret): DAMAGE [amount], DAMAGE_CRIT [amount], MISS [], PERIODIC_HEAL / _CRIT [healer, amount].
-- (1.28.0) DODGE and PARRY are logged again: the feed says them at the real moment (UNIT_COMBAT for
-- you comes 0.6-0.8 s later), to line up Stormstrike's reset with your dodge or parry.
local PROBE_KNOWN = {DAMAGE = true, DAMAGE_CRIT = true, MISS = true,
    PERIODIC_HEAL = true, PERIODIC_HEAL_CRIT = true}
local function ProbeKind(kind)
    if not (ns.IsLogging and ns.IsLogging()) then return end
    if PROBE_KNOWN[Plain(kind)] then return end
    if not (C_CombatText and C_CombatText.GetCurrentEventInfo) then return end
    local function Pack(...) return select("#", ...), {...} end
    local n, res = Pack(pcall(C_CombatText.GetCurrentEventInfo))
    if not res[1] then return Log("combat text %s: no event info", S(kind)) end
    local parts = {}
    for i = 2, math.min(n, 6) do parts[#parts + 1] = S(res[i]) end -- nil shows as "nil"
    Log("combat text %s [%s]", S(kind), table.concat(parts, ", "))
end

-- (1.25.0) buffs and debuffs on you: Alerts.lua
local AURA_KINDS = {
    SPELL_AURA_START = true, SPELL_AURA_START_HARMFUL = true,
    SPELL_AURA_END = true, SPELL_AURA_END_HARMFUL = true,
}

function FFT:OnCombatText(kind)
    local raw = kind
    kind = Plain(kind)
    if AURA_KINDS[kind] then return self.OnAuraNotice and self:OnAuraNotice(kind) end
    if HEAL_KINDS[kind] ~= nil then return NoteFeedHeal(kind) end
    -- (1.31.0) the game's proc notice, "<Maelstrom Ready!>": Procs.lua (still logged by the probe)
    if kind == "SPELL_CAST" then ProbeKind(raw); return self.OnProcNotice and self:OnProcNotice() end
    if kind == "SPELL_ACTIVE" then ProbeKind(raw); return self.OnReactiveNotice and self:OnReactiveNotice() end
    if kind ~= "ENERGIZE" and kind ~= "PERIODIC_ENERGIZE" then return ProbeKind(raw) end
    if not (C_CombatText and C_CombatText.GetCurrentEventInfo) then return end
    local ok, amount, token = pcall(C_CombatText.GetCurrentEventInfo)
    if not ok then return Log("combat text %s: no event info", kind) end
    Log("combat text %s %s %s", kind, S(amount), S(token))
    local db = self.db
    if not db.showPower or not Gained(amount) then return end
    -- (1.31.0) Mana Spring, Blessing of Wisdom: a tick every 2 s, off unless chosen (the author: "spammy")
    if kind == "PERIODIC_ENERGIZE" and not db.showPeriodicPower then return end
    feedCount, feedLast, feedLastAt = feedCount + 1, kind, GetTime()
    ShowGain(amount, false, token)
end

function FFT:OnPowerGain(flag, amount)
    local db = self.db
    flag = Plain(flag)
    Log("player ENERGIZE %s %s", S(flag), S(amount))
    if not (db.enabled and db.showPower) or not Gained(amount) then return end
    if feedCount > 0 then return end -- the feed shows it
    local at = GetTime()
    C_Timer.After(FEED_WAIT, function()
        if feedLastAt and math.abs(feedLastAt - at) <= FEED_WAIT + 0.05 then
            return Log("  power gain shown from the combat text feed")
        end
        ShowGain(amount, flag == "CRITICAL")
    end)
end

-- Natural regen ("mana ticks") can't be shown: it's never reported as a gain, and UnitPower is
-- secret even solo (1.24.1 probe, 2026-11-09 08:04 and 08:33 logs: 129 of 129 secret), so a change
-- of your mana bar can't be computed. The probe was removed in 1.25.1.

-- for /fft status
function FFT:PowerFeedText()
    if feedCount == 0 then return "none from the combat text feed yet this session" end
    return ("%d from the combat text feed this session (last %s, %.0f s ago)"):format(
        feedCount, feedLast, GetTime() - feedLastAt)
end

function FFT:TestPower()
    local fmt = PowerFormat()
    C_Timer.After(0.2, function() FFT:Show(nil, nil, FFT.Color("colorPower"), false, PowerOptions(fmt, {25})) end)
    C_Timer.After(0.7, function() FFT:Show(nil, nil, FFT.Color("colorPower"), true, PowerOptions(fmt, {180})) end)
end

function FFT:TestIncoming()
    local db = self.db
    local samples = {
        {"-245", 1, false}, {"-812", 1, true}, {DODGE}, {"-130", 4, false}, {"+420", "heal", false},
    }
    for i, s in ipairs(samples) do
        C_Timer.After(0.3 + (i - 1) * 0.3, function()
            if not s[2] then
                FFT:Show(nil, s[1], FFT.Color("colorMiss"), false, Options())
            elseif s[2] == "heal" then
                local text = db.showHealerNames and (s[1] .. " [Healer]") or s[1]
                if db.showIncomingHeals then FFT:Show(nil, nil, FFT.Color("colorHeal"), false, Options("%s", {text})) end
            else
                local color = db.incomingSchoolColors and ns.SchoolColor(s[2], true) or FFT.Color("colorIncoming")
                FFT:Show(nil, nil, color, s[3], Options("%s", {s[1]}))
            end
        end)
    end
end
