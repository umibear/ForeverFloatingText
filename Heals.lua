-- Forever Floating Text heals: your heals, HoT ticks and Chain Heal jumps.
--
-- What the game gives (all confirmed in Forever's API docs):
--   UNIT_COMBAT(unit, "HEAL", flag, amount)  - a heal landed; no source, no spell.
--     Action and flag names as Blizzard's own CombatFeedback.lua uses them.
--   UNIT_SPELLCAST_SENT("player", target, castGUID, spellID) - who you cast on (by name).
--   UNIT_SPELLCAST_SUCCEEDED("player", castGUID, spellID)    - your cast finished.
--   C_Spell.IsSpellHelpful / C_Spell.GetSpellName.
--
-- Deciding which heals are yours, per moment (one frame of heal events):
--   1. Direct heal: within the match window after your helpful cast, landing on the unit
--      you cast on (or on anyone, for spells with no target). One cast, one moment;
--      every heal of that moment counts (Holy Nova, Prayer of Healing hit many at once).
--   2. Chain Heal jumps: in Classic it heals 3 targets in total, each jump 50% as effective
--      as the previous one (warcraft.wiki.gg, Chain Heal). So after its first heal, up to
--      2 later heals count, each on a different person and never bigger than the one before.
--      Chain Heal is recognised by name: the name of spell 1064 (Chain Heal rank 1,
--      wowclassicdb.com) as this client reports it, so every rank and language matches.
--   3. HoT ticks: no Forever spell data is available, so periods aren't hardcoded.
--      They're learned while you're solo: after you cast a helpful spell, heals on its
--      target that arrive on a steady beat are its ticks. Once learned (period and tick
--      count, saved per spell name), ticks on that beat count as yours, also in groups.

local ADDON, ns = ...
local FFT = ns.FFT
local IsSecret, Plain, Print, PlateOf, Log, S = ns.IsSecret, ns.Plain, ns.Print, ns.PlateOf, ns.Log, ns.S

local CHAIN_HEAL_ID = 1064
local CHAIN_JUMPS = 2        -- 3 targets in total
local CHAIN_WINDOW = 1.5     -- seconds after the first heal in which jumps may land
local BEAT_TOLERANCE = 0.25  -- seconds a tick may be off its beat
local AREA_TOLERANCE = 0.15  -- tighter for heals around you, which can land on anyone
local AMOUNT_TOLERANCE = 0.2 -- ticks of one cast heal about the same (+-20%)
local LEARN_TOLERANCE = 0.2  -- stricter, while learning
local OBSERVE_FOR = 120      -- seconds a solo cast on no one is watched for ticks (totems last long)
local OBSERVE_TARGETED = 30  -- seconds for a spell cast on someone (Rejuvenation 12s, Regrowth 21s)
local MIN_PERIOD = 0.5

local casts = {}        -- your recent helpful casts, newest last
local sentTargets = {}  -- castGUID -> target name from UNIT_SPELLCAST_SENT
local sentAt = {}       -- castGUID -> when, to forget casts that never finished
local sentCount = 0
local periodic = {}     -- running HoTs: key -> {name, guid, t0, period, ticks, area, used}
local observing = {}    -- spell name -> {t0, guid, times} while learning solo
local queue, queuedAt = {}, nil
local seenThisFrame = {} -- (1.26.2) token .. ":" .. amount -> how many such heals came this frame

local function db() return FFT.db end

------------------------------------------------------------------------
-- Names and units
------------------------------------------------------------------------
local chainHealName
local function ChainHealName()
    if chainHealName == nil then
        chainHealName = Plain(C_Spell.GetSpellName(CHAIN_HEAL_ID)) or false
    end
    return chainHealName or nil
end

local GROUP_TOKENS = {"player", "pet", "target", "focus", "mouseover"}
for i = 1, 4 do GROUP_TOKENS[#GROUP_TOKENS + 1] = "party" .. i end
for i = 1, 40 do GROUP_TOKENS[#GROUP_TOKENS + 1] = "raid" .. i end

-- The SENT event names the target; find that unit's GUID. nil if it can't be told.
-- Forever names have surnames: seen in game, the SENT target is "Name Surname" while UnitName
-- gives "Name". So a unit whose name is the SENT name's first word also matches, but only when
-- exactly one unit does.
local function GuidForName(target)
    target = Plain(target)
    if type(target) ~= "string" or target == "" then return nil end
    local first = target:match("^(%S+)%s")
    local byFirst, firstCount, seen = nil, 0, {}
    for _, token in ipairs(GROUP_TOKENS) do
        if Plain(UnitExists(token)) then
            local name, realm = UnitName(token)
            name, realm = Plain(name), Plain(realm)
            local guid = Plain(UnitGUID(token))
            if name and (name == target or (realm and realm ~= "" and name .. "-" .. realm == target)) then
                return guid
            end
            if name and first and name == first and guid and not seen[guid] then
                seen[guid] = true
                byFirst, firstCount = guid, firstCount + 1
            end
            if name and token == "player" then Log("  name check: you are \"%s\" (cast on \"%s\")", name, target) end
        end
    end
    if firstCount == 1 then return byFirst end
    return nil
end

local function PlayerGuid() return Plain(UnitGUID("player")) end

------------------------------------------------------------------------
-- Learning HoT periods (solo only)
------------------------------------------------------------------------
-- Shared with your DoTs (Core.lua): the period that puts the most ticks on whole beats
local function FindPeriod(times) return ns.FindPeriod(times, MIN_PERIOD, LEARN_TOLERANCE) end

local function Learned(name)
    local list = db().learnedHots
    return list and list[name]
end

local function RanOut(p, at) return at - p.t0 > p.period * (p.ticks + 0.5) end

local function StartPeriodic(name, guid, t0, info, area)
    -- (1.28.8) ones that ran out go here too: TickFor removed them, but it only runs without the
    -- Combat Log, so with it they stayed for the session and kept counting in HealScore
    for k, p in pairs(periodic) do
        if RanOut(p, t0) then periodic[k] = nil end
    end
    local key = name .. "@" .. (guid or "*")
    periodic[key] = {name = name, guid = guid, t0 = t0, period = info.period,
        ticks = info.ticks, area = area, used = {}, amount = nil}
end

local function Observe(name, guid, at)
    local o = observing[name]
    if not o or at - o.t0 > (o.area and OBSERVE_FOR or OBSERVE_TARGETED) then return false end
    if o.guid ~= guid then return false end
    o.times[#o.times + 1] = at - o.t0
    local found = FindPeriod(o.times)
    if not found then return false end

    local list = db().learnedHots or {}
    db().learnedHots = list
    local old = list[name]
    if old and math.abs(old.period - found.period) <= LEARN_TOLERANCE then
        if found.ticks > old.ticks then old.ticks = found.ticks end
        old.period = (old.period + found.period) / 2
    else
        list[name] = {period = found.period, ticks = found.ticks, area = o.area}
        Print(("learned %s: a tick every %.1fs. /fft heals lists what's learned."):format(name, found.period))
    end
    Log("  learned %s period %.2f ticks %d (from %d ticks)", name, list[name].period, list[name].ticks, #o.times)
    -- the rest of this cast's ticks count from now on; it's still being watched, so its
    -- tick count isn't known yet
    local open = {period = list[name].period, ticks = math.floor(OBSERVE_FOR / list[name].period)}
    StartPeriodic(name, (not o.area) and guid or nil, o.t0, open, o.area)
    -- and this heal itself, if it's on the beat
    local age = at - o.t0
    local k = math.floor(age / found.period + 0.5)
    if k >= 1 and math.abs(age - k * found.period) <= LEARN_TOLERANCE then
        local p = periodic[name .. "@" .. (((not o.area) and guid) or "*")]
        p.used[k .. ":" .. guid] = true
        return true
    end
end

------------------------------------------------------------------------
-- Your casts
------------------------------------------------------------------------
-- target: the name, "" for a spell cast on no one; false here when the game hides it
function FFT:OnCastSent(target, castGUID)
    if IsSecret(castGUID) or castGUID == nil then return end
    -- casts that never finished: forgotten by age (a minute). (1.28.8) Before, all were wiped every
    -- 50 casts, a long cast's own among them between its SENT and its end (as Core's sentGUIDs once)
    local now = GetTime()
    sentCount = sentCount + 1
    if sentCount > 50 then
        sentCount = 0
        for guid, t in pairs(sentAt) do
            if now - t > 60 then sentAt[guid], sentTargets[guid] = nil, nil end
        end
    end
    sentAt[castGUID] = now
    if IsSecret(target) then
        sentTargets[castGUID] = false
    else
        sentTargets[castGUID] = target or false
    end
end

function FFT:OnPlayerCast(castGUID, spellID)
    spellID = Plain(spellID)
    if not spellID or not Plain(C_Spell.IsSpellHelpful(spellID)) then return end
    local name = Plain(C_Spell.GetSpellName(spellID))
    if not name then return end
    local now = GetTime()

    local targetName = (not IsSecret(castGUID) and castGUID) and sentTargets[castGUID]
    if castGUID and not IsSecret(castGUID) then sentTargets[castGUID], sentAt[castGUID] = nil, nil end
    local guid = GuidForName(targetName)
    -- "" = cast on no one (totems, Prayer of Healing...): it heals around you.
    -- nil/false = target unknown: direct heals still count on anyone, ticks can't be followed.
    local area = (targetName == "")

    local c = {t = now, name = name, guid = guid, area = area,
        chain = (name == ChainHealName())}
    casts[#casts + 1] = c
    while casts[1] and now - casts[1].t > 5 do table.remove(casts, 1) end
    Log("cast %s on %s (%s)%s", name, S(targetName), guid or "unknown unit", c.chain and " chain" or "")

    local info = Learned(name)
    if info and db().showHotTicks then
        if info.area or area then
            StartPeriodic(name, nil, now, info, true)
        elseif guid then
            StartPeriodic(name, guid, now, info, false)
        end
    end
    if not IsInGroup() then
        -- solo: watch for this spell's ticks (on you when it had no target or an unknown one)
        observing[name] = {t0 = now, guid = (not area and guid) or PlayerGuid(), area = area, times = {}}
        C_Timer.After(db().matchWindow + 0.1, function()
            if not c.usedAt and not IsInGroup() then FFT:NoteHealKind(name, "none") end
        end)
    end
end

-- Solo, count whether a spell's cast heals at once. A learned HoT whose casts never
-- heal at once (Renew, Rejuvenation) then can't claim someone else's heal right after it.
function FFT:NoteHealKind(name, kind)
    local kinds = db().healKinds or {}
    db().healKinds = kinds
    local k = kinds[name] or {direct = 0, none = 0}
    kinds[name] = k
    k[kind] = k[kind] + 1
end

local function HealsAtOnce(name)
    local k = db().healKinds and db().healKinds[name]
    if not (Learned(name) and k) then return true end
    return k.direct > 0 or k.none < 3
end

------------------------------------------------------------------------
-- Which heals of a moment are yours
------------------------------------------------------------------------
local function DirectCast(list, at)
    for i = #casts, 1, -1 do
        local c = casts[i]
        local dt = at - c.t
        if dt >= 0 and dt <= db().matchWindow and not c.usedAt and HealsAtOnce(c.name) then
            if c.guid == nil then return c end
            for _, h in ipairs(list) do
                if h.guid == c.guid then return c end
            end
        end
    end
end

local function ChainJump(h, at)
    for i = #casts, 1, -1 do
        local c = casts[i]
        if c.chain and c.usedAt and c.jumpsLeft and c.jumpsLeft > 0
            and at >= c.usedAt and at - c.usedAt <= CHAIN_WINDOW
            and h.guid and not c.chainUnits[h.guid] then
            local amount = Plain(h.amount)
            if amount == nil or c.chainLast == nil or amount <= c.chainLast then
                c.jumpsLeft = c.jumpsLeft - 1
                c.chainUnits[h.guid] = true
                c.chainLast = amount or c.chainLast
                return c
            end
        end
    end
end

local function TickFor(h, at)
    if not db().showHotTicks then return end
    for key, p in pairs(periodic) do
        local age = at - p.t0
        if RanOut(p, at) then
            periodic[key] = nil
        elseif p.area or (h.guid and h.guid == p.guid) then
            local k = math.floor(age / p.period + 0.5)
            local usedKey = k .. ":" .. (h.guid or h.unit)
            local tolerance = p.area and AREA_TOLERANCE or BEAT_TOLERANCE
            local amount = Plain(h.amount)
            -- ticks of one cast heal about the same; a much bigger or smaller heal isn't one
            local sameSize = not (amount and p.amount and p.amount > 0)
                or math.abs(amount - p.amount) <= AMOUNT_TOLERANCE * p.amount
            if k >= 1 and k <= p.ticks and math.abs(age - k * p.period) <= tolerance
                and not p.used[usedKey] and sameSize then
                p.used[usedKey] = true
                if amount and not p.amount then p.amount = amount end
                return p, k
            end
        end
    end
end

------------------------------------------------------------------------
-- Display
------------------------------------------------------------------------
-- (1.30.0) Heals without a nameplate show with your damage, at the "damage" spot (Spots.lua), in the
-- damage numbers' font: your heals and your damage in one place. Before,
-- a spot of their own ("heal", 1.21.1, with its own font); the author compacted five spots to three.
local function SpotOptions(fmt, args)
    local x, y = FFT:SpotAnchor("damage")
    return {fmt = fmt, args = args, anchorX = x, anchorY = y, key = "damage"}
end

local function ShowHeal(h)
    if FFT:TooSmall(h.amount) then return end
    local crit = (h.flag == "CRITICAL")
    if crit then FFT:CritSound() end
    local amount = ns.FormatAmount(h.amount)
    -- over the friendly nameplate, unless your numbers go to the scrolling area (Damage options)
    if h.plate and h.plate:IsShown() and FFT.db.damageWhere ~= "spot" then
        FFT:Show(h.plate, nil, FFT.Color("colorHeal"), crit, {fmt = "+%s", args = {amount}})
        return
    end
    local opts = SpotOptions()
    if h.nameUnit and h.nameUnit ~= "player" then
        opts.fmt, opts.args = "+%s %s", {amount, (UnitName(h.nameUnit))}
    else
        opts.fmt, opts.args = "+%s", {amount}
    end
    FFT:Show(nil, nil, FFT.Color("colorHeal"), crit, opts)
end

-- Combat Log mode (1.15.6): a heal is yours when a heal line of yours came with it, as for damage
-- (Core.lua, "Combat Log mode"). The Forever Floating Text filter sends one for each of your heals and
-- heal-over-time ticks (Healing Wave, First Aid, totems...), in their own colors. A heal with no line
-- yet gets one more look after the window.
local function ByCombatLog(h, at, final)
    local d, kind = FFT:ClogTakeHealLine(at)
    if d then
        if kind == "hot" and not db().showHotTicks then
            return Log("%s heal %s %s: yours, a tick (ticks are off)", h.unit, S(h.amount), S(h.flag))
        end
        Log("%s heal %s %s: yours (Combat Log line, %+.3fs)", h.unit, S(h.amount), S(h.flag), d)
        return ShowHeal(h)
    end
    if not final then
        C_Timer.After(FFT.CLOG_WINDOW or 0.06, function() ByCombatLog(h, at, true) end)
        return
    end
    -- (1.28.8) every stranger's heal ends here: its S() calls only while recording
    if ns.IsLogging() then Log("%s heal %s %s: not yours (no Combat Log line of yours)", h.unit, S(h.amount), S(h.flag)) end
    if h.guid and h.guid == PlayerGuid() and FFT.ShowReceivedHeal then
        FFT:ShowReceivedHeal(h.amount, h.flag, at) -- (1.26.0) at: for the healer's name
    end
end

-- 2: you cast a helpful spell at this unit in the last 3 s (a cast's heal lands as it finishes);
-- 1: one of your heal-over-time spells is running on it; 0: neither, or the unit is unknown
local function HealScore(h, at)
    if not h.guid then return 0 end
    for i = #casts, 1, -1 do
        local c = casts[i]
        if c.guid == h.guid and at - c.t >= -0.1 and at - c.t <= 3 then return 2 end
    end
    for _, p in pairs(periodic) do
        if p.guid == h.guid and not RanOut(p, at) then return 1 end
    end
    return 0
end

local function Resolve()
    local at = queuedAt
    queuedAt = nil
    local list = queue
    queue = {}
    seenThisFrame = {}
    if not at then return end

    if FFT:ClogActive() then
        -- (1.17.0) when heals outnumber your heal lines in a moment, the first heal to arrive took
        -- the line, someone else's too. Now a heal on the one you just cast at goes first, then one
        -- on someone your heal-over-time is on, as damage hits choose by school and target.
        for i, h in ipairs(list) do h.order, h.score = i, HealScore(h, at) end
        table.sort(list, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.order < b.order
        end)
        for _, h in ipairs(list) do ByCombatLog(h, at, false) end
        return
    end

    local c = DirectCast(list, at)
    if c then
        c.usedAt = at
        if not IsInGroup() then FFT:NoteHealKind(c.name, "direct") end
        if c.chain then
            c.jumpsLeft, c.chainUnits = CHAIN_JUMPS, {}
            for _, h in ipairs(list) do
                if h.guid then c.chainUnits[h.guid] = true end
                if h.guid == c.guid then c.chainLast = Plain(h.amount) end
            end
        end
        for _, h in ipairs(list) do
            Log("%s heal %s %s: yours (%s)", h.unit, S(h.amount), S(h.flag), c.name)
            ShowHeal(h)
        end
        return
    end

    local solo = not IsInGroup()
    for _, h in ipairs(list) do
        local jump = ChainJump(h, at)
        local tick, k
        if not jump then tick, k = TickFor(h, at) end
        if jump then
            Log("%s heal %s: yours (%s jump, %.2fs after the first)", h.unit, S(h.amount), jump.name, at - jump.usedAt)
            ShowHeal(h)
        elseif tick then
            Log("%s heal %s: yours (%s tick %d)", h.unit, S(h.amount), tick.name, k)
            ShowHeal(h)
            -- solo, a cast seen ticking longer than before teaches its tick count
            local info = solo and Learned(tick.name)
            if info and k > info.ticks then info.ticks = k end
        else
            local learnedNow
            if solo and h.guid then
                for name in pairs(observing) do
                    if Observe(name, h.guid, at) then learnedNow = name end
                end
            end
            if learnedNow then
                Log("%s heal %s: yours (%s tick, just learned)", h.unit, S(h.amount), learnedNow)
                ShowHeal(h)
            else
                Log("%s heal %s %s: not yours", h.unit, S(h.amount), S(h.flag))
                -- someone else healed you: that goes with what happens to you
                if h.guid and h.guid == PlayerGuid() and FFT.ShowReceivedHeal then
                    FFT:ShowReceivedHeal(h.amount, h.flag, at)
                end
            end
        end
    end
end

-- A unit's own token. Other tokens (target, focus, mouseover, and compound ones like
-- "targettarget") are only more names for the same unit.
local OWN_TOKENS = {"^player$", "^pet$", "^party%d+$", "^partypet%d+$", "^raid%d+$", "^raidpet%d+$", "^nameplate%d+$"}
local function OwnToken(unit)
    for _, pattern in ipairs(OWN_TOKENS) do
        if unit:find(pattern) then return true end
    end
    return false
end

-- One heal fires UNIT_COMBAT once per token the unit has (party1, target, nameplate5...),
-- so they're gathered for the frame and merged by unit (its GUID).
-- 1.15.6: a heal came twice in a dungeon (log 2026-11-06 19:50, 343874.890: "party3" and
-- "targettarget"): there the GUID of a compound token is hidden (UnitGUID is
-- SecretWhenUnitIdentityRestricted), so the two couldn't be merged. Now compound tokens are left
-- out, and target/focus/mouseover count only when their GUID can be read to merge them.
function FFT:OnHeal(unit, flag, amount)
    if IsSecret(unit) then return end
    if not db().showHeals then
        -- your heals are off: every heal on you is just a heal you received
        if unit == "player" and FFT.ShowReceivedHeal then FFT:ShowReceivedHeal(amount, Plain(flag)) end
        return
    end
    local own = OwnToken(unit)
    if not own and unit ~= "target" and unit ~= "focus" and unit ~= "mouseover" then return end
    local guid = Plain(UnitGUID(unit))
    if not own and not guid then return end
    -- (1.26.2) Two heals on one unit in one frame are two heals. Merged by unit and amount only,
    -- they became one whenever the amounts were hidden ("?"): heals on you are secret even solo
    -- (2026-11-09 08:04 log), so a priest's heal landing with your Healing Stream tick was lost.
    -- Each token gets each heal once, in order, so the n-th heal of an amount on one token is
    -- merged only with the n-th of that amount on the unit's other tokens.
    local amountKey = tostring(Plain(amount) or "?")
    local seenKey = unit .. ":" .. amountKey
    local n = (seenThisFrame[seenKey] or 0) + 1
    seenThisFrame[seenKey] = n
    local key = (guid or unit) .. ":" .. amountKey .. ":" .. n
    local h = queue[key]
    if not h then
        h = {unit = unit, guid = guid, amount = amount, flag = Plain(flag)}
        queue[key] = h
        queue[#queue + 1] = h
    end
    if unit:find("^nameplate") then
        h.plate = h.plate or PlateOf(unit)
    elseif not h.nameUnit then
        h.nameUnit = unit -- party1 / raid3 / target: used for the name
    end
    if not queuedAt then
        queuedAt = GetTime()
        C_Timer.After(0, Resolve)
    end
end

------------------------------------------------------------------------
-- Commands and preview
------------------------------------------------------------------------
function FFT:HealStatus()
    local chain = ChainHealName()
    Print("Chain Heal: " .. (chain and ("recognised as \"" .. chain .. "\"") or
        ("spell " .. CHAIN_HEAL_ID .. " not found in this client, jumps won't show")))
    local list = db().learnedHots
    if not list or not next(list) then
        Print("no heal-over-time spells learned yet. Cast them while solo and they're learned from your ticks.")
    else
        for name, info in pairs(list) do
            Print(("%s: tick every %.2fs, up to %d ticks%s"):format(name, info.period, info.ticks,
                info.area and ", heals around you" or ""))
        end
    end
    local dotList = db().dotPeriods
    if not dotList or not next(dotList) then
        Print("no damage-over-time spells learned yet. They're learned from your ticks where your threat can be read (out in the world).")
    else
        for name, info in pairs(dotList) do
            Print(("%s (damage): tick every %.2fs, up to %d ticks, school %d"):format(name, info.period, info.ticks, info.school))
        end
    end
    local minionList = db().minionSchools
    if minionList and next(minionList) then
        for id, school in pairs(minionList) do
            local name = type(id) == "number" and ns.Plain(C_Spell.GetSpellName(id)) or tostring(id)
            Print(("%s, spell %s (your totem/pet): hits as school %d"):format(tostring(name), tostring(id), school))
        end
    end
end

function FFT:ForgetHots()
    db().learnedHots = nil
    db().healKinds = nil
    db().dotPeriods = nil
    db().spellSchools = nil
    db().minionSchools = nil
    wipe(periodic)
    wipe(observing)
    Print("forgot everything learned: heal-over-time and damage-over-time rhythms, spell schools.")
end

function FFT:TestHeals()
    C_Timer.After(0.5, function()
        FFT:Show(nil, nil, FFT.Color("colorHeal"), false, SpotOptions("+%s %s", {1500, "Friend"}))
    end)
    C_Timer.After(1.0, function()
        FFT:Show(nil, nil, FFT.Color("colorHeal"), true, SpotOptions("+%s", {3200}))
    end)
end
