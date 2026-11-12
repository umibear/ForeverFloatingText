-- Forever Floating Text alerts: the game's own spell alerts as text, "Overpower!", "Clearcasting!".
-- Also at this spot (1.22.1): entering / leaving combat, and your killing blows; (1.25.0) buffs and
-- debuffs you gain and lose.
--
-- SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(spellID): an action button lights up (a reactive ability
-- becomes usable). SPELL_ACTIVATION_OVERLAY_SHOW(spellID, ...): a proc's overlay appears.
-- Both are in Forever's API docs (SpellActivationOverlayDocumentation.lua) with no secrecy
-- flags. Which spells Forever lights up is the game's choice; whatever it lights up shows.
-- These alerts were part of Blizzard's own combat text over your character, which
-- "Show damage I take" turns off.

local ADDON, ns = ...
local FFT = ns.FFT
local Plain, Log = ns.Plain, ns.Log

local SAME_ALERT = 1.0 -- seconds: the glow and the overlay of one proc show once
local shownAt = {}     -- spell name -> time last shown

function FFT:Alert(spellID, source)
    local db = self.db
    if not (db and db.enabled and db.showAlerts) then return end
    spellID = Plain(spellID)
    if not spellID then return end
    local name = Plain(C_Spell.GetSpellName(spellID))
    if not name then return end
    local now = GetTime()
    if shownAt[name] and now - shownAt[name] < SAME_ALERT then return end
    shownAt[name] = now
    Log("alert %s (%s %d)", name, source, spellID)
    self:ShowAlert(name .. "!")
end

-- fmt / args (optional): SetFormattedText's, for a hidden value the game draws (a buff's name)
function FFT:ShowAlert(text, color, fmt, args)
    local db = self.db
    -- (1.23.1) its own font, outline and size, apart from the nameplate numbers; (1.31.0) a repeat
    -- within a second merges ("Purged x2", Spots.lua SpotText)
    return self:SpotText("alerts", text, color or FFT.Color("colorAlert"), db.alertFont, db.alertOutline, db.alertSize,
        fmt, args)
end

-- (1.31.0) Buffs and debuffs gained and faded at a spot of their own, apart from the alerts (the
-- author, 2026-11-12: "its getting quite spammy"), with a hide list. Its own font.
function FFT:ShowBuff(text, color, fmt, args)
    local db = self.db
    return self:SpotText("buffs", text, color, db.buffFont, db.buffOutline, db.buffSize, fmt, args)
end

-- (1.25.0) Buffs and debuffs you gain and lose: COMBAT_TEXT_UPDATE SPELL_AURA_START / _END (and
-- _HARMFUL), name from C_CombatText.GetCurrentEventInfo(), drawn as Blizzard's CombatText.lua does:
-- "<name>" when gained, AURA_END ("<%s> fades", the game's string) when lost; its colors. The name
-- is secret even solo (2026-11-09 08:04 log: Ghost Wolf on 553459.914, off 553503.489), so every
-- aura shows and none can be left out by name. Needs the feed on (Core.lua FeedWanted).
local AURA_TEXT = {
    SPELL_AURA_START = {fmt = "<%s>", color = "colorBuff"},
    SPELL_AURA_START_HARMFUL = {fmt = "<%s>", color = "colorDebuff"},
    SPELL_AURA_END = {fades = true, color = "colorBuff"},
    SPELL_AURA_END_HARMFUL = {fades = true, color = "colorDebuff"},
}
local feedAuraAt = {} -- "added" / "removed" -> when the feed last brought one (UNIT_AURA below skips those)
function FFT:OnAuraNotice(kind)
    local db = self.db
    local how = AURA_TEXT[kind]
    if not how then return end
    feedAuraAt[how.fades and "removed" or "added"] = GetTime()
    if not (C_CombatText and C_CombatText.GetCurrentEventInfo) then return end
    local ok, name = pcall(C_CombatText.GetCurrentEventInfo)
    if not ok then return end
    Log("aura %s %s", kind, ns.S(name))
    if not (db.enabled and db.showAuras) then return end
    if not ns.IsSecret(name) and type(name) ~= "string" then return end -- nothing to name (no compare on a secret)
    local fmt = how.fmt
    if how.fades then
        if not db.showAuraFades then return end -- (1.31.0) off unless chosen
        fmt = type(AURA_END) == "string" and AURA_END or "<%s> fades"
    end
    self:ShowBuff(nil, FFT.Color(how.color), fmt, {name}) -- (1.31.0) at the buffs spot
end

-- (1.28.4) Your buffs the feed doesn't bring: totem buffs. The 2026-11-10 08:05 and 08:10 logs (out
-- of combat): totems placed and recalled brought no SPELL_AURA_START / _END in the feed, but UNIT_AURA
-- "player" (UnitAuraDocumentation.lua) brought each one: addedAuras with the buff's name ("Strength of
-- Earth", "Healing Stream", "Frost Resistance", "Grounding Totem", "Flametongue Totem"), readable,
-- isFromPlayerOrPlayerPet true, duration 0, in the cast's frame (Call of the Elements 0.10 s after),
-- and removedAuraInstanceIDs (only the id) when recalled or replaced by another totem of its element
-- (640191.271: Poison Cleansing Totem replaced Healing Stream). Poison Cleansing and Tremor gave no buff.
-- So: an aura of yours added or removed shows "<name>" / "<name> fades" like the feed's, unless the
-- feed brought an aura line within 0.06 s (its own buffs, Ghost Wolf, Lightning Shield: 640176.752,
-- the feed's END and UNIT_AURA's removal in one frame), so none shows twice. The fade needs the name
-- kept from when it was added (an id from before a /reload has none: nothing shown).
-- In combat its values are secret by the docs (SecretWhenAurasRestricted): see 1.28.6 below. Every
-- add and removal is logged (`UNIT_AURA player ...`).
-- (1.28.5) The 10:31 log (out of combat, totems shuffled, out of range and back): out of range the
-- buffs went (125.901) and came back with new ids when back in range (134.400), both shown. Two
-- misses: Grounding Totem's buff came "from nil, mine false" 0.12 s before its totem's plate
-- (159.203; "from player, mine true" in the 08:10 log), so neither it nor its fade showed; and a
-- buff from before the /reload faded with no name (117.923). So: "not yours" with no source counts
-- as yours in your cast's frame, and your buffs are read at load (and after a full update) so their
-- names are known when they fade (seen working in game: reload, then Totemic Recall).
-- (1.28.6) In combat (10:36 log, 410.792 Strength of Earth Totem, 416.670 Mana Spring Totem) the
-- whole addedAuras / removedAuraInstanceIDs is secret: only "something was added / removed" is
-- known, in the cast's frame. So out of combat the addon learns, per spell of yours, which buff its
-- cast adds and which it removes (one cast in the frame; with several, Call of the Elements', the
-- cast whose name starts with the buff's), kept in ForeverFloatingTextDB.auraCasts by the spell's
-- name (1.31.4; by ID before, see Learned). In combat, a
-- hidden add in your cast's frame (up to 0.15 s) shows the buff that cast was learned to add; a
-- hidden removal there fades the learned ones that are up. Nothing learned: nothing shown. A buff
-- lost in combat with no cast of yours (out of range) can't be told: no text; after combat your
-- buffs are read again.
local AURA_FEED_NEAR = 0.06   -- the feed's aura line this close: the feed shows it
local AURA_AFTER_CAST = 0.15  -- Call of the Elements' buffs came 0.10 s after the cast
local auraNames = {}          -- auraInstanceID -> name, for auras of yours shown as added
local upNames = {}            -- name -> true: your buffs up now (kept in combat too, by name)
local recentCasts = {}        -- your casts in the last moment: {t, id, name, usedAdd, usedRemove}

local function FeedNear(which, t)
    return feedAuraAt[which] and math.abs(feedAuraAt[which] - t) <= AURA_FEED_NEAR
end

local function CastsNear(t)
    local out = {}
    for _, c in ipairs(recentCasts) do
        if t - c.t >= 0 and t - c.t <= AURA_AFTER_CAST then out[#out + 1] = c end
    end
    return out
end
local function InCastFrame(t) return #CastsNear(t) > 0 end

local function AuraIsMine(a, t)
    local mine = Plain(a.isFromPlayerOrPlayerPet)
    if mine == true then return true end
    if mine == false then -- Grounding Totem's buff before its totem existed: no source at all
        return not ns.IsSecret(a.sourceUnit) and a.sourceUnit == nil and InCastFrame(t)
    end
    return ns.IsSecret(a.isFromPlayerOrPlayerPet) and InCastFrame(t)
end

-- (1.31.4) Kept by the spell's name, not its ID: each rank of a spell has an ID of its own (the
-- author's game files: Searing Totem 3606, Searing Totem III 6351), so a newly trained rank of a
-- totem had to be dropped out of combat again before its buff showed in combat. Entries saved by ID
-- before are moved to their name once (ranks of one spell merged); one whose name can't be read stays.
local converted = false
local function ConvertByName(saved)
    converted = true
    local moves = {} -- collected first: a table can't get new keys while it's being walked
    for key, l in pairs(saved) do
        local name = type(key) == "number" and Plain(C_Spell.GetSpellName(key))
        if type(name) == "string" and type(l) == "table" then moves[#moves + 1] = {key, name, l} end
    end
    for _, m in ipairs(moves) do
        local key, name, l = m[1], m[2], m[3]
        saved[key] = nil
        local into = saved[name]
        if not into then
            saved[name] = l
        else
            into.removes = into.removes or {}
            for removed in pairs(l.removes or {}) do into.removes[removed] = true end
            into.gives = into.gives or l.gives
            into.totem = into.totem or l.totem
        end
    end
end
local function Learned(cast, create)
    local db = FFT.db
    local key = cast and (type(cast.name) == "string" and cast.name or cast.id)
    if not db or not key then return nil end
    if db.auraCasts and not converted then ConvertByName(db.auraCasts) end
    if create then
        db.auraCasts = db.auraCasts or {}
        db.auraCasts[key] = db.auraCasts[key] or {removes = {}}
    end
    return db.auraCasts and db.auraCasts[key]
end

-- the one cast in the frame that the buff belongs to
local function CastFor(casts, buff)
    if #casts == 1 then return casts[1] end
    local found
    for _, c in ipairs(casts) do
        if type(c.name) == "string" and c.name:sub(1, #buff) == buff then
            if found then return nil end
            found = c
        end
    end
    return found
end

-- your buffs on you now, by id (out of combat; with hidden values nothing changes)
local function LearnAuras(why)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    -- (1.28.9) Not while the game hides auras: then the read doesn't return hidden values, it fails
    -- ("Auras cannot be accessed when secret while tainted", 2026-11-10 12:33 log, 7406.506: a new
    -- fight had started 0.03 s before the "after combat" read). So the game is asked first.
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local asked, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
        if asked and Plain(hidden) == true then
            Log("your buffs read (%s): auras are hidden now, kept as they were", why)
            return
        end
    end
    local ok, err = pcall(function()
        local names, up = {}, {}
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if a == nil then break end
            if ns.IsSecret(a) or type(a) ~= "table" or ns.IsSecret(a.name) or ns.IsSecret(a.auraInstanceID) then
                Log("your buffs read (%s): hidden, kept as they were", why)
                return
            end
            local id, name = Plain(a.auraInstanceID), Plain(a.name)
            if id and type(name) == "string" and Plain(a.isFromPlayerOrPlayerPet) == true then
                names[id], up[name] = name, true
            end
        end
        auraNames, upNames = names, up
        local n = 0
        for _ in pairs(names) do n = n + 1 end
        Log("your buffs read (%s): %d of yours", why, n)
    end)
    if not ok then Log("your buffs: read failed (%s)", tostring(err)) end
end

-- (1.31.0) What the player chose not to see: a buff on the hide list (/fft hide), and unless chosen
-- your own totems' buffs (UNIT_AURA brings them with duration 0, 2026-11-10 08:05 log; a cast that
-- was learned to add one keeps that, so in combat too). Names only: a hidden name can't be compared.
local totemBuffs = {} -- name -> true: buffs seen with duration 0 from your totems
local function LeftOut(name)
    local db = FFT.db
    if ns.IsSecret(name) or type(name) ~= "string" then return nil end
    for hidden in pairs(db.hiddenBuffs or {}) do -- any case, as typed
        if hidden:lower() == name:lower() then return "on the hide list" end
    end
    if totemBuffs[name] and not db.showTotemBuffs then return "your totem's" end
end

local function ShowGained(name, how)
    if not ns.IsSecret(name) then upNames[name] = true end
    local db = FFT.db
    if not (db and db.enabled and db.showAuras) then return end
    local out = LeftOut(name)
    if out then return Log("  aura added %s: not shown (%s)", ns.S(name), out) end
    Log("  show aura added %s (%s)", ns.S(name), how)
    FFT:ShowBuff(nil, FFT.Color("colorBuff"), "<%s>", {name})
end

local function ShowFaded(name, how)
    if not ns.IsSecret(name) then upNames[name] = nil end
    local db = FFT.db
    if not (db and db.enabled and db.showAuras and db.showAuraFades) then return end -- (1.31.0) fades: if chosen
    local out = LeftOut(name)
    if out then return Log("  aura faded %s: not shown (%s)", ns.S(name), out) end
    Log("  show aura faded %s (%s)", ns.S(name), how)
    FFT:ShowBuff(nil, FFT.Color("colorBuff"), type(AURA_END) == "string" and AURA_END or "<%s> fades", {name})
end

local function ShowAuraChanges(t, added, removed, full, hiddenAdd, hiddenRemove)
    local feedAdded, feedRemoved = FeedNear("added", t), FeedNear("removed", t)
    local casts = CastsNear(t)
    for _, a in ipairs(added) do
        local name = a.name
        if (ns.IsSecret(name) or type(name) == "string") and Plain(a.isHelpful) ~= false and AuraIsMine(a, t) then
            local id = Plain(a.auraInstanceID)
            if feedAdded then Log("  aura added: the feed's (its line within %.2f s)", AURA_FEED_NEAR)
            else
                if id then auraNames[id] = name end
                local totem = type(name) == "string" and Plain(a.duration) == 0 and not ns.IsSecret(a.duration)
                if totem then totemBuffs[name] = true end
                if type(name) == "string" then
                    local c = CastFor(casts, name)
                    local l = c and Learned(c, true)
                    if l and totem and not l.totem then l.totem = true end
                    if l and l.gives ~= name then
                        l.gives = name
                        Log("  learned: %s (spell %s) adds <%s>", ns.S(c.name), ns.S(c.id), name)
                    end
                end
                ShowGained(name, "UNIT_AURA")
            end
        end
    end
    for _, id in ipairs(removed) do
        local name = auraNames[id]
        auraNames[id] = nil
        if name ~= nil then
            if type(name) == "string" and #casts == 1 then
                local l = Learned(casts[1], true)
                if l and not l.removes[name] then
                    l.removes[name] = true
                    Log("  learned: %s (spell %s) removes <%s>", ns.S(casts[1].name), ns.S(casts[1].id), name)
                end
            end
            if feedRemoved then
                Log("  aura removed: the feed's (its line within %.2f s)", AURA_FEED_NEAR)
                if type(name) == "string" then upNames[name] = nil end
            else ShowFaded(name, "UNIT_AURA") end
        end
    end
    -- in combat: hidden, so only what your cast in this frame was learned to do
    if hiddenAdd and not feedAdded then
        for _, c in ipairs(casts) do
            local l = Learned(c)
            if not c.usedAdd and l and l.gives then
                c.usedAdd = true
                if l.totem then totemBuffs[l.gives] = true end
                ShowGained(l.gives, "hidden, learned for " .. ns.S(c.name))
            end
        end
    end
    if hiddenRemove and not feedRemoved then
        for _, c in ipairs(casts) do
            local l = Learned(c)
            if not c.usedRemove and l and l.removes then
                c.usedRemove = true
                for name in pairs(l.removes) do
                    if upNames[name] then ShowFaded(name, "hidden, learned for " .. ns.S(c.name)) end
                end
            end
        end
    end
    if full then LearnAuras("full update") end -- the game rebuilt the list: ids may be stale
end

-- (1.28.8) Most UNIT_AURA events only say an aura was updated (a tick, a refresh): those, and all
-- of them while "Show buffs gained / faded" is off, now end before any table is made. Before, each
-- made two tables and a function first. Names kept while it was off may be out of date, so your
-- buffs are read again at the first event after it's turned on.
local function OnlyUpdates(info)
    local a, r, f = info.addedAuras, info.removedAuraInstanceIDs, info.isFullUpdate
    return not ns.IsSecret(a) and a == nil and not ns.IsSecret(r) and r == nil
        and not ns.IsSecret(f) and not f
end
local aurasStale = false

local auraProbe = CreateFrame("Frame")
auraProbe:RegisterUnitEvent("UNIT_AURA", "player")
auraProbe:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
auraProbe:RegisterEvent("PLAYER_ENTERING_WORLD")
auraProbe:RegisterEvent("PLAYER_REGEN_ENABLED")
auraProbe:SetScript("OnEvent", function(_, event, _, info, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local t, id = GetTime(), Plain(spellID)
        for i = #recentCasts, 1, -1 do
            if t - recentCasts[i].t > 1 then table.remove(recentCasts, i) end
        end
        if id then recentCasts[#recentCasts + 1] = {t = t, id = id, name = Plain(C_Spell.GetSpellName(id))} end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then LearnAuras("at load") return end
    if event == "PLAYER_REGEN_ENABLED" then C_Timer.After(0.5, function() LearnAuras("after combat") end) return end
    local db = FFT.db
    if not (db and db.enabled and db.showAuras) then aurasStale = true return end
    if ns.IsSecret(info) or type(info) ~= "table" then return end
    local quick, nothing = pcall(OnlyUpdates, info)
    if quick and nothing then return end
    if aurasStale then aurasStale = false; LearnAuras("turned on") end
    local t = GetTime()
    local added, removed, hiddenAdd, hiddenRemove = {}, {}, false, false
    local ok, err = pcall(function()
        local a, r = info.addedAuras, info.removedAuraInstanceIDs
        if ns.IsSecret(a) then hiddenAdd = true
        elseif type(a) == "table" then
            for _, aura in ipairs(a) do
                if not ns.IsSecret(aura) and type(aura) == "table" then added[#added + 1] = aura else hiddenAdd = true end
            end
        end
        if ns.IsSecret(r) then hiddenRemove = true
        elseif type(r) == "table" then
            for _, id in ipairs(r) do
                local plain = Plain(id)
                if plain then removed[#removed + 1] = plain else hiddenRemove = true end
            end
        end
    end)
    if not ok then Log("UNIT_AURA player: read failed (%s)", tostring(err)) return end
    local full = Plain(info.isFullUpdate) == true
    if #added == 0 and #removed == 0 and not full and not hiddenAdd and not hiddenRemove then return end
    -- the feed's line may come before or after it in the frame: decide a moment later
    C_Timer.After(AURA_FEED_NEAR + 0.01, function()
        local done, why = pcall(ShowAuraChanges, t, added, removed, full, hiddenAdd, hiddenRemove)
        if not done then Log("UNIT_AURA player: failed (%s)", tostring(why)) end
    end)
end)

-- (1.28.3, probe, log only) what UNIT_AURA "player" brings, and what is readable, in and out of combat
local auraLog = CreateFrame("Frame")
auraLog:RegisterUnitEvent("UNIT_AURA", "player")
auraLog:SetScript("OnEvent", function(_, _, _, info)
    if not (ns.IsLogging and ns.IsLogging()) then return end
    local ok, err = pcall(function()
        if ns.IsSecret(info) or type(info) ~= "table" then Log("UNIT_AURA player: info %s", ns.S(info)) return end
        local secretAuras = C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()
        local parts = {}
        if Plain(info.isFullUpdate) == true then parts[#parts + 1] = "full update" end
        local added, removed = info.addedAuras, info.removedAuraInstanceIDs
        if ns.IsSecret(added) then parts[#parts + 1] = "added <secret>"
        elseif type(added) == "table" then
            for _, a in ipairs(added) do
                if ns.IsSecret(a) or type(a) ~= "table" then parts[#parts + 1] = "added " .. ns.S(a)
                else
                    parts[#parts + 1] = ("added %s (spell %s, id %s, from %s, mine %s, helpful %s, duration %s)"):format(
                        ns.S(a.name), ns.S(a.spellId), ns.S(a.auraInstanceID), ns.S(a.sourceUnit),
                        ns.S(a.isFromPlayerOrPlayerPet), ns.S(a.isHelpful), ns.S(a.duration))
                end
            end
        end
        if ns.IsSecret(removed) then parts[#parts + 1] = "removed <secret>"
        elseif type(removed) == "table" then
            for _, id in ipairs(removed) do parts[#parts + 1] = "removed id " .. ns.S(id) end
        end
        if #parts == 0 then return end -- only updated auras (ticks, refreshes): not logged
        Log("UNIT_AURA player (secret auras %s): %s", ns.S(secretAuras), table.concat(parts, "; "))
    end)
    if not ok then Log("UNIT_AURA player: probe failed (%s)", tostring(err)) end
end)

-- (1.22.1) Entering / leaving combat: PLAYER_REGEN_DISABLED / _ENABLED, as Blizzard's CombatText.lua
-- (ENTERING_COMBAT / LEAVING_COMBAT, red 1 0.1 0.1, CVar floatingCombatTextCombatState_v2). The
-- words are the game's own strings ("Entering Combat", "Leaving Combat"), so they're localized.
function FFT:OnCombatState(entering)
    local db = self.db
    if not (db and db.enabled and db.showCombatState) then return end
    -- (1.31.0) short: "+Combat" / "-Combat" (the game's COMBAT, "Combat")
    local word = type(COMBAT) == "string" and COMBAT or "Combat"
    local text = (entering and "+" or "-") .. word
    self:ShowAlert(text, FFT.Color("colorCombat"))
end

-- (1.22.1) Your killing blow: a PARTY_KILL line in the addon's own Combat Log filter (white, the
-- only event of that color there; Core "Our own Combat Log filter"). The filter passes only your
-- and your pet's actions, so the kill is yours or your pet's. Seen with the author's killing swings
-- (2026-11-07 11:18 at 277.490; 16:31 dungeon log). The line can't be read: which mob isn't known.
function FFT:OnKillingBlow()
    local db = self.db
    if not (db and db.enabled and db.showKills) then return end
    Log("killing blow (Combat Log kill line)")
    self:ShowAlert("Killing Blow!", FFT.Color("colorKill"))
end

-- (1.30.1) A Windfury proc of yours: Core.lua ClogHit calls this at the proc's first attack shown
-- as yours (its line in the proc's frame, the hit in a Windfury slot 0.23 / 0.50 s after). Seen in
-- the author's 2026-11-11 08:15 log: Stormstrike 1094.241, its lines at 1094.342, its attacks at
-- 1094.572 and 1094.847. The game has no Windfury text of its own; "Windfury!" isn't a game string.
function FFT:OnWindfury()
    local db = self.db
    Log("Windfury proc (alert %s)", (db and db.enabled and db.showWindfury) and "shown" or "off")
    if not (db and db.enabled and db.showWindfury) then return end
    self:ShowAlert("Windfury!")
end

function FFT:TestAlerts()
    C_Timer.After(0.2, function() FFT:ShowAlert("Overpower!") end)
    C_Timer.After(0.8, function() FFT:ShowAlert("Clearcasting!") end)
    if self.db.showCombatState then C_Timer.After(1.4, function() FFT:OnCombatState(true) end) end
    if self.db.showKills then C_Timer.After(2.0, function() FFT:OnKillingBlow() end) end
    if self.db.showWindfury then C_Timer.After(3.8, function() FFT:OnWindfury() end) end
    if self.db.showAuras then self:TestBuffs() end
end

function FFT:TestBuffs()
    C_Timer.After(0.2, function() FFT:ShowBuff(nil, FFT.Color("colorBuff"), "<%s>", {"Lightning Shield"}) end)
    C_Timer.After(0.8, function()
        FFT:ShowBuff(nil, FFT.Color("colorDebuff"), type(AURA_END) == "string" and AURA_END or "<%s> fades", {"Frost Nova"})
    end)
end

------------------------------------------------------------------------
-- (1.28.0) Stormstrike reset (the author's talent). C_Spell.GetSpellCooldown's isActive and isOnGCD
-- are NeverSecret (SpellSharedDocumentation.lua, SpellCooldownInfo); start and duration may be secret.
-- Seen in game: the 2026-11-09 14:12 log by timing (Stormstrikes 2.17-4.68 s apart), and the
-- 14:54-19:08 logs by the game's own cooldown reports. The talent resets it when you dodge or parry
-- (its tooltip, the author). Its cooldown is 6.0 s (the earliest "ready" with no reset: 6.004 s
-- after the cast); four "ready" reports came 3.49-4.56 s after it, and your dodge was logged 0.27-
-- 0.80 s after the reset (578346: +0.80; 578772: +0.40; 593246: +0.27): UNIT_COMBAT for you comes
-- late, as for hits on you (0.6-0.8 s after the combat text feed). Reset during a global cooldown,
-- it reads "active, on the GCD" until the GCD ends (578138: read 2.9 s after a Stormstrike, the next
-- one cast 5.80 s after the last, before its 6.0 s cooldown could have ended).
-- (1.28.2) But "on the GCD" also means the GCD simply outlasts what is left of its own cooldown:
-- in the 2026-11-10 07:48 log all 7 alerts were wrong, each read "active, on the GCD" 4.43-4.72 s
-- after a Stormstrike as an Earth / Flame Shock started its 1.5 s GCD (638898.514, 639286.889...),
-- with no dodge or parry of yours, and the next Stormstrike came 6.00-6.44 s after the last. So
-- "on the GCD" counts only up to 4.2 s after the cast (6.0 - 1.5 - 0.3 for timing): later it is
-- looked at again every 0.1 s, and only "not active" before 5.8 s counts (a reset during that GCD).
-- So: when the game reports Stormstrike ready 1.6 to 5.8 s after you cast it (or only on the
-- global cooldown, up to 4.2 s), its cooldown was reset: "Stormstrike!" at the procs spot, once per
-- Stormstrike, at the moment of the reset. Looked at on every SPELL_UPDATE_COOLDOWN (it fires at the reset), and
-- when you or your target dodge, parry or block. No cooldown info from the game: nothing shown.
-- The 1.28.0 draft looked only when UNIT_COMBAT reported your dodge, so its alerts came late. The
-- game sent no button glow for it in these logs; an alert from a glow and this one would show once.
-- (1.31.2) Also looked at every 0.1 s from 1.6 to 5.8 s after each Stormstrike: a reset during its
-- own global cooldown ends with that GCD, and the game sends no update then. The author's 2026-11-12
-- 15:38 log: Stormstrike 114106.756, your dodge 0.33 s after (the feed's DODGE), the mob dead at
-- 114108.457, and the reset found only at 114110.444 (3.69 s), at Skinning's cooldown update.
-- And not shown out of combat: it would stay its whole 10 s, as leaving combat (which ends it,
-- Procs.lua) had already happened.
------------------------------------------------------------------------
local STORMSTRIKE = "Stormstrike"
local SS_RESET_AFTER = 1.6   -- after its own global cooldown
local SS_RESET_BEFORE = 5.8  -- before its 6.0 s cooldown ends on its own
local SS_GCD_SURE = 4.2      -- "on the GCD" before this: its own cooldown would outlast a 1.5 s GCD
local stormstrikeID          -- learned from your own cast, else the name is used
local lastStormstrike = -100 -- when you last cast it
local alertedFor             -- the Stormstrike whose reset was shown
local recheckFor             -- the Stormstrike being looked at again until a late GCD ends
local lastActive             -- its isActive as last logged
local inFight = InCombatLockdown and InCombatLockdown() or false -- then PLAYER_REGEN_DISABLED / _ENABLED

local function Logging() return ns.IsLogging and ns.IsLogging() end

-- ready: true (off cooldown, or only the global one), false (on its cooldown), nil (can't tell)
local function StormstrikeCooldown()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil, "no C_Spell.GetSpellCooldown" end
    local ok, info = pcall(C_Spell.GetSpellCooldown, stormstrikeID or STORMSTRIKE)
    if not ok then return nil, "GetSpellCooldown failed" end
    if type(info) ~= "table" or ns.IsSecret(info) then return nil, "no cooldown info (" .. ns.S(info) .. ")" end
    local text = ("active %s, gcd %s, start %s, duration %s"):format(ns.S(info.isActive), ns.S(info.isOnGCD),
        ns.S(info.startTime), ns.S(info.duration))
    local active, gcd = Plain(info.isActive), Plain(info.isOnGCD)
    local ready
    if active == false then ready = true
    elseif active == true then ready = (gcd == true) end
    return ready, text, active
end

local function ProbeCooldown(why)
    if not Logging() then return end
    local _, text, active = StormstrikeCooldown()
    Log("Stormstrike cooldown (%s): %s", why, text)
    if active ~= nil then lastActive = active end
end

local function CheckReset(why)
    local since = GetTime() - lastStormstrike
    if since < SS_RESET_AFTER or since > SS_RESET_BEFORE or alertedFor == lastStormstrike then return end
    local ready, text, active = StormstrikeCooldown()
    if ready and active == true and since >= SS_GCD_SURE then
        -- only the GCD shows, but it may just outlast the cooldown's last 1.5 s: look again after it
        if recheckFor ~= lastStormstrike then
            recheckFor = lastStormstrike
            local cast = lastStormstrike
            local function Again()
                if lastStormstrike ~= cast or alertedFor == cast then return end
                if GetTime() - cast > SS_RESET_BEFORE then return end
                CheckReset("after the GCD")
                C_Timer.After(0.1, Again)
            end
            C_Timer.After(0.1, Again)
        end
        return
    end
    if not ready then return end
    alertedFor = lastStormstrike
    Log("Stormstrike reset: ready %.2f s after you cast it (%s; %s)", since, why, text)
    local db = FFT.db
    -- (1.31.0) at the procs spot, kept there until you cast Stormstrike or leave combat (Procs.lua);
    -- before, a scrolling alert. Its own setting only: no longer under "Show ability alerts".
    if not (db and db.enabled and db.showStormstrikeReset) then return end
    if not inFight then return Log("  out of combat: not shown") end
    -- Procs.lua is a new file in 1.31.0: after a /reload only, the game hasn't loaded it yet
    if not FFT.ProcShow then FFT:ShowAlert(STORMSTRIKE .. "!") return end
    FFT:ProcShow("stormstrike", FFT.Color("colorStormstrike"), FFT.SpellIconText(stormstrikeID or STORMSTRIKE) .. STORMSTRIKE .. "!",
        nil, nil, 10) -- 10 s if unused
end

-- a mob avoiding your attack: look again a moment later (cheap; the cooldown update is what counts)
local avoided = CreateFrame("Frame")
avoided:RegisterEvent("UNIT_COMBAT")
avoided:SetScript("OnEvent", function(_, _, unit, action)
    -- (1.28.8) only while a Stormstrike of yours is on cooldown: before, every miss, dodge or parry
    -- on any nameplate started a timer, for every class
    if GetTime() - lastStormstrike > SS_RESET_BEFORE then return end
    if ns.IsSecret(unit) or type(unit) ~= "string" or not unit:find("^nameplate") then return end
    action = Plain(action)
    if action == "DODGE" or action == "PARRY" or action == "MISS" then
        C_Timer.After(0.1, function() CheckReset("a mob's " .. action:lower()) end)
    end
end)

local probe = CreateFrame("Frame")
probe:RegisterEvent("SPELL_UPDATE_COOLDOWN")
probe:RegisterUnitEvent("UNIT_COMBAT", "player")
probe:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
probe:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
probe:RegisterEvent("PLAYER_REGEN_DISABLED")
probe:RegisterEvent("PLAYER_REGEN_ENABLED")
probe:RegisterEvent("PLAYER_LOGIN")
probe:RegisterEvent("SPELLS_CHANGED")

-- (1.31.3) Only a character that knows Stormstrike (an Enhancement talent) listens for its resets:
-- every nameplate's dodges and parries, every cooldown update, your own dodges. Asked with
-- C_SpellBook.IsSpellKnown (SpellBookDocumentation.lua, Forever's API list; IsPlayerSpell isn't in
-- it) at login and when your spells change (SPELLS_CHANGED: talents, respec). 17364 is the spell
-- in the author's logs ("Stormstrike cooldown (update, spell 17364)" with each cast). Can't tell,
-- or you cast it anyway: watched, as before.
local STORMSTRIKE_SPELL = 17364
local watching = true -- registered below, as the frames were before
local function Watch(on)
    if on == watching then return end
    watching = on
    if on then
        avoided:RegisterEvent("UNIT_COMBAT")
        probe:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        probe:RegisterUnitEvent("UNIT_COMBAT", "player")
    else
        avoided:UnregisterEvent("UNIT_COMBAT")
        probe:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        probe:UnregisterEvent("UNIT_COMBAT")
    end
    Log("Stormstrike resets: %s", on and "watched" or "not watched (you don't know Stormstrike)")
end
local function KnowsStormstrike()
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return true end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, stormstrikeID or STORMSTRIKE_SPELL)
    known = ok and Plain(known)
    if type(known) ~= "boolean" then return true end
    return known
end

probe:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inFight = event == "PLAYER_REGEN_DISABLED"
        return
    end
    if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" then return Watch(KnowsStormstrike()) end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = Plain(a3)
        if id and Plain(C_Spell.GetSpellName(id)) == STORMSTRIKE then
            stormstrikeID = stormstrikeID or id
            Watch(true)
            lastStormstrike = GetTime()
            local cast = lastStormstrike
            local function Look()
                if lastStormstrike ~= cast or alertedFor == cast then return end
                if GetTime() - cast > SS_RESET_BEFORE then return end
                CheckReset("looked again")
                C_Timer.After(0.1, Look)
            end
            C_Timer.After(SS_RESET_AFTER, Look)
        end
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        CheckReset("cooldown update")
        if Logging() then
            local _, text, active = StormstrikeCooldown()
            if active ~= nil and active ~= lastActive then
                Log("Stormstrike cooldown (update, spell %s): %s", ns.S(a1), text)
                lastActive = active
            end
        end
    elseif event == "UNIT_COMBAT" then
        local action = Plain(a2)
        if action == "DODGE" or action == "PARRY" or action == "BLOCK" then
            CheckReset("you " .. action:lower())
            ProbeCooldown("you " .. action:lower())
        end
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" and Logging() then
        Log("button glow off: spell %s (%s)", ns.S(a1), ns.S(Plain(a1) and C_Spell.GetSpellName(a1)))
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE") -- (1.31.0) Procs.lua keeps them until these
events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
events:SetScript("OnEvent", function(_, event, spellID)
    local glow = event:find("GLOW") ~= nil
    if event:find("HIDE$") then
        if event == "SPELL_ACTIVATION_OVERLAY_HIDE" and Logging() then
            Log("overlay off: spell %s (%s)", ns.S(spellID), ns.S(Plain(spellID) and C_Spell.GetSpellName(spellID)))
        end
        if FFT.HighlightHide then FFT:HighlightHide(spellID, glow) end
        return
    end
    if Logging() then -- (1.28.0, probe) every one the game sends, shown or not
        Log("%s on: spell %s (%s)", glow and "button glow" or "overlay",
            ns.S(spellID), ns.S(Plain(spellID) and C_Spell.GetSpellName(spellID)))
    end
    -- (1.31.0) at the procs spot, kept until the game's _HIDE (Procs.lua); without it, an alert
    if FFT.HighlightShow and FFT:HighlightShow(spellID, glow) then return end
    FFT:Alert(spellID, glow and "button glow" or "overlay")
end)

-- (1.31.0) /fft hide <buff>, /fft unhide <buff>, /fft hide (the list). Names as the game writes them,
-- any case. Works where the game lets the name be read: out of combat, and in combat for the buffs
-- your casts were learned to add (totems); a buff the game names only hidden still shows.
function FFT:HideBuff(name, hide)
    local db = self.db
    db.hiddenBuffs = db.hiddenBuffs or {}
    if not name or name == "" then
        local list = {}
        for n in pairs(db.hiddenBuffs) do list[#list + 1] = n end
        table.sort(list)
        ns.Print(#list > 0 and ("buffs not shown: " .. table.concat(list, ", "))
            or "no buffs hidden. /fft hide <buff name> hides one.")
        return
    end
    -- the name as the game writes it, when a buff of yours by that name was seen
    for n in pairs(upNames) do if n:lower() == name:lower() then name = n end end
    for n in pairs(totemBuffs) do if n:lower() == name:lower() then name = n end end
    for n in pairs(db.hiddenBuffs) do if n:lower() == name:lower() then name = n end end
    db.hiddenBuffs[name] = hide or nil
    ns.Print(("%s: %s"):format(name, hide and "not shown any more" or "shown again"))
end
