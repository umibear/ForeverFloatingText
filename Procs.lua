-- Forever Floating Text procs (1.31.0): procs at their own spot ("procs", Spots.lua), kept still
-- on screen while they last instead of scrolling away: "Stormstrike!" after its cooldown is reset
-- (Alerts.lua), and the game's own proc notices such as "Maelstrom Ready!". One row per proc, the
-- newest at the top; a proc shown again only refreshes its row.
--
-- The game's proc notices: COMBAT_TEXT_UPDATE "SPELL_CAST", its value the spell's name. Blizzard's
-- CombatText.lua draws it as "<name>" in 0.1 1 0.1, always (CombatTextConstants.lua: show = 1, no
-- CVar); the addon hides that frame, so these notices were never seen while it was on. The name is
-- secret, so every notice the game sends shows and none can be told apart.
-- The author's 2026-11-12 09:01 recording, solo, with the game's file: Maelstrom Weapon (talent,
-- spell 408505) stacks to 5, and at the 5th the game applies "Maelstrom Ready!" (408501) and logs a
-- SPELL_CAST_SUCCESS of it, in the 5th stack's moment. The feed's SPELL_CAST came in that frame 9 of
-- 9 times, and only then. A Lightning Bolt removed it 9 of 9 times, in the bolt's frame, 0.43-15.5 s
-- after (once into the next fight); no UNIT_SPELLCAST_SUCCEEDED of yours comes for 408501.
-- The notice ends at the first harmful or helpful cast of yours whose frame also brings an aura of
-- yours removed (UNIT_AURA "player"; in combat the removal itself is hidden, but that it happened
-- isn't): a cast that used the proc up. Not Stormstrike: it once took Flurry's last charge in its own
-- frame (same recording). At most PROC_MAX: the proc can't be read, so a notice never stays for good;
-- (1.31.6) except Maelstrom's, whose 30 s are extended while Ready! is on you or unreadable (MAELSTROM_READY below).

local ADDON, ns = ...
local FFT = ns.FFT
local Plain, Log, S, IsSecret = ns.Plain, ns.Log, ns.S, ns.IsSecret

-- seconds a game notice nothing used up stays: a cap, not the buff's real duration, which can't
-- be read in combat and isn't in the logs yet (the longest seen: 15.5 s, used up)
local PROC_MAX = 30
-- (1.31.6) Maelstrom (the game's files: "Maelstrom Ready!" 408501, "Maelstrom Weapon" 408505). The
-- author, 2026-11-12: Ready! stays while swings refresh the stacks ("melee refreshes stacks"), but the
-- text went at 30 s from when it showed, with Ready! still up. So for a player seen with Maelstrom
-- the notice's 30 s are extended while Ready! is found on you, or while your buffs can't be read
-- (in combat), until used. (1.31.7) Not ended by Ready! missing: in game (2026-11-12 18:19 log,
-- 123765.513) GetPlayerAuraBySpellID(408501) found nothing after a fight while the game's file had
-- Ready! on to its end, 7 s later; that ended the text after every fight. Which ID (or name) the
-- client gives Ready! isn't known yet: LogBuffs below records it.
local MAELSTROM_READY, MAELSTROM_WEAPON = 408501, 408505
local HELD_MAX = 300         -- seconds a Maelstrom notice stays at most, unread, in a fight that never ends
-- true / false while the game lets your buffs be read, nil while it doesn't (in combat)
local function HasAura(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then -- asked first: a read while hidden fails (Alerts.lua LearnAuras)
        local asked, hidden = pcall(C_Secrets.ShouldAurasBeSecret)
        if not asked or Plain(hidden) == true or IsSecret(hidden) then return nil end
    end
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or IsSecret(a) then return nil end
    return a ~= nil
end
-- a Maelstrom player: once seen with either buff while readable (saved)
local function MaelstromSeen()
    local db = FFT.db
    if not db then return false end
    if not db.maelstromSeen and (HasAura(MAELSTROM_READY) or HasAura(MAELSTROM_WEAPON)) then
        db.maelstromSeen = true
        Log("Maelstrom Weapon seen on you: its proc notice now follows the buff")
    end
    return db.maelstromSeen == true
end
-- (1.31.7, log only) your buffs by name and spell ID, and what the lookups by ID say, while readable
local function LogBuffs(why)
    if not (ns.IsLogging and ns.IsLogging()) then return end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) or HasAura(MAELSTROM_WEAPON) == nil then
        Log("buffs at %s: can't be read now", why)
        return
    end
    local parts = {}
    pcall(function()
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if a == nil or IsSecret(a) or type(a) ~= "table" then break end
            parts[#parts + 1] = ("%s (spell %s)"):format(S(a.name), S(a.spellId))
        end
    end)
    Log("buffs at %s: %s; by ID: 408501 %s, 408505 %s", why, table.concat(parts, ", "),
        tostring(HasAura(MAELSTROM_READY)), tostring(HasAura(MAELSTROM_WEAPON)))
end
-- the game notice's time is up: more seconds to stay and why, or nil to end it
local function GameStays(r)
    LogBuffs("proc game's time up")
    if not MaelstromSeen() then return nil end
    local up = HasAura(MAELSTROM_READY)
    if up == true then return PROC_MAX, "Maelstrom Ready! still on you" end
    if up == false then return nil end
    if GetTime() - r.shownAt >= HELD_MAX then return nil end
    return PROC_MAX, "your buffs can't be read now"
end
local SAME_FRAME = 0.002     -- events of one frame share one GetTime()
local FADE = 0.3             -- seconds a row takes to fade when its proc ends
local ROW_GAP = 1.15         -- rows this many text sizes apart

local frame                  -- holds the rows, at the procs spot; always shown (an empty one draws nothing)
local fader                  -- runs only while a row fades: rows that just stay need nothing each frame
local rows = {}              -- shown rows, newest first: {key, text, ends, fading, timer}
local pool = {}              -- spare font strings

-- (1.31.0 draft, the author's first try in game, 2026-11-12 09:35) the fading ran on the rows'
-- own frame and hid it as soon as nothing faded: "Maelstrom Ready!" was drawn for one frame
-- (its notice came at 92311.523 and 92326.322, and the Lightning Bolts ended it 1.54 / 4.52 s
-- later). So the fading has a frame of its own, and hiding it never hides a row.
local function Frame()
    if frame then return frame end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("HIGH") -- as the other spots' texts (Core.lua holder)
    frame:SetFrameLevel(20)
    fader = CreateFrame("Frame", nil, UIParent)
    fader:SetScript("OnUpdate", function(_, elapsed)
        local any = false
        for i = #rows, 1, -1 do
            local r = rows[i]
            if r.fading then
                r.fading = r.fading - elapsed
                if r.fading <= 0 then
                    r.text:Hide()
                    pool[#pool + 1] = r.text
                    table.remove(rows, i)
                    FFT:LayoutProcs()
                else
                    r.text:SetAlpha(r.fading / FADE)
                    any = true
                end
            end
        end
        if not any then fader:Hide() end
    end)
    fader:Hide()
    FFT.procFrames = {rows = frame, fader = fader} -- for the test suite
    return frame
end

function FFT:LayoutProcs()
    local db = self.db
    if not frame then return end
    local x, y = self:SpotAnchor("procs")
    local size = db.procSize or FFT.DEFAULTS.procSize
    for i, r in ipairs(rows) do
        r.text:ClearAllPoints()
        r.text:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y - (i - 1) * size * ROW_GAP)
    end
end

local function Find(key)
    for i, r in ipairs(rows) do if r.key == key then return r, i end end
end

-- The row's end in `seconds`; the game's notice may stay on (GameStays)
local function Arm(r, key, seconds)
    r.ends = GetTime() + seconds
    if r.timer then r.timer:Cancel() end
    local ends = r.ends
    r.timer = C_Timer.NewTimer(seconds, function()
        if r.ends ~= ends then return end
        local more, why
        if key == "game" then more, why = GameStays(r) end
        if not more then return FFT:ProcEnd(key, "its time is up") end
        Log("proc %s stays (%s, %.0f s after it showed)", key, why, GetTime() - r.shownAt)
        Arm(r, key, more)
    end)
end

-- Shows a proc until FFT:ProcEnd(key) or `seconds`. text, or fmt + args (hidden values too).
function FFT:ProcShow(key, color, text, fmt, args, seconds)
    local db = self.db
    if not (db and db.enabled) then return end
    local r, i = Find(key)
    if r then
        table.remove(rows, i)
    else
        local t = table.remove(pool) or Frame():CreateFontString(nil, "OVERLAY")
        r = {key = key, text = t}
    end
    table.insert(rows, 1, r)
    local t = r.text
    local font, size = db.procFont or FFT.DEFAULTS.procFont, db.procSize or FFT.DEFAULTS.procSize
    if not t:SetFont(font, size, db.procOutline or "") then t:SetFont(STANDARD_TEXT_FONT, size, db.procOutline or "") end
    t:SetTextColor(color[1], color[2], color[3])
    if fmt then t:SetFormattedText(fmt, unpack(args)) else t:SetText(text) end
    t:SetAlpha(1)
    t:Show()
    r.fading = nil
    r.shownAt = GetTime()
    Arm(r, key, seconds or PROC_MAX)
    Frame():Show()
    self:LayoutProcs()
    local x, y = self:SpotAnchor("procs")
    Log("proc %s shown at %.0f, %.0f (stays %.0f s at most)", key, x, y, seconds or PROC_MAX)
end

function FFT:ProcEnd(key, why)
    local r = Find(key)
    if not r or r.fading then return end
    Log("proc %s ends (%s, %.2f s after it showed)", key, why or "?", GetTime() - r.shownAt)
    if r.timer then r.timer:Cancel(); r.timer = nil end
    r.fading = FADE
    Frame()
    fader:Show()
end

-- for the test suite: the keys shown now, newest first
function FFT:ProcsUp()
    local out = {}
    for _, r in ipairs(rows) do if not r.fading then out[#out + 1] = r.key end end
    return out
end

-- The game's notice (Incoming.lua OnCombatText, kind SPELL_CAST)
function FFT:OnProcNotice()
    local db = self.db
    local t = GetTime()
    if self.NoteProcCast then self.NoteProcCast(t) end -- Core.lua: its cast line isn't a totem's
    if not (C_CombatText and C_CombatText.GetCurrentEventInfo) then return end
    local ok, name = pcall(C_CombatText.GetCurrentEventInfo)
    if not ok then return end
    if not IsSecret(name) and type(name) ~= "string" then return end -- nothing to name
    Log("proc notice <%s>", S(name))
    if not (db.enabled and db.showGameProcs) then return end
    self:ProcShow("game", FFT.Color("colorProc"), nil, "%s", {name}, PROC_MAX)
end

-- What may use the game's notice up: a cast of yours and an aura of yours removed, one frame.
-- (1.31.2) Not when that aura was a form the cast took you out of: casting from Ghost Wolf ends it
-- in the cast's moment. The game's files of the author's recordings: Flame Shock 6 times, Earth Shock
-- 4, Stormstrike and totems more, each with Ghost Wolf removed in the cast's moment; a Shock pull from
-- Ghost Wolf had ended "Maelstrom Ready!" with all 5 stacks still up. The form is read
-- (GetShapeshiftFormID, Ghost Wolf 16) before the cast's frame and on the next frame. Hidden in
-- combat is how many auras went, so a spell you were seen casting with a cast bar (one the proc
-- can make instant, as Lightning Bolt) still ends it out of a form.
local lastUse, lastRemoval = {t = -100}, -100
local form = {now = 0, t = -100, before = 0} -- before: the form as last seen before the frame of t
local function SeeForm()
    local ok, f = pcall(GetShapeshiftFormID or function() return 0 end)
    f = ok and Plain(f)
    if type(f) ~= "number" then f = 0 end
    local t = GetTime()
    if t - form.t > SAME_FRAME then form.before = form.now end
    form.now, form.t = f, t
end
local function CastBars()
    local db = FFT.db
    if not db then return {} end
    db.castBarSpells = db.castBarSpells or {} -- spell name -> true: seen with a cast bar
    return db.castBarSpells
end
local function Used()
    if math.abs(lastUse.t - lastRemoval) > SAME_FRAME then return end
    local use = lastUse
    if use.looked then return end -- one look per cast (a frame may bring several removals)
    use.looked = true
    local why = ("your %s and an aura of yours removed with it"):format(use.name)
    SeeForm()
    local wasIn = form.before
    if wasIn == 0 or CastBars()[use.name] then return FFT:ProcEnd("game", why) end
    C_Timer.After(0, function()
        SeeForm()
        if form.now ~= 0 then return FFT:ProcEnd("game", why) end
        Log("proc game stays: your %s took you out of form %d, the aura removed with it", use.name, wasIn)
    end)
end

-- (1.31.6) The feed's SPELL_AURA_END (Alerts.lua OnAuraNotice) counts as a removal too. The author's
-- 09:01 / 09:35 recordings: a Lightning Bolt using the proc came with the feed's "aura ended" in its
-- frame 11 of 11; once (90392.630) UNIT_AURA's removal came only 0.10 s later, a frame of its own
-- (the game's file: "Maelstrom Ready!" removed and the stacks down to 4 at the cast, Maelstrom
-- Weapon removed 0.10 s after), so the text stayed while the stacks built up again, until PROC_MAX.
function FFT.NoteProcAuraRemoved()
    if #rows == 0 then return end
    lastRemoval = GetTime()
    Used()
end

local watch = CreateFrame("Frame")
watch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
watch:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
watch:RegisterUnitEvent("UNIT_AURA", "player")
watch:RegisterEvent("PLAYER_REGEN_ENABLED")
watch:SetScript("OnEvent", function(_, event, _, a2, a3)
    if event == "UNIT_SPELLCAST_START" then
        local name = Plain(a3) and Plain(C_Spell.GetSpellName(Plain(a3)))
        if type(name) == "string" then CastBars()[name] = true end
        return
    end
    if event == "UNIT_AURA" or event == "UNIT_SPELLCAST_SUCCEEDED" then
        SeeForm()
        -- a form may be set after its aura: looked at again next frame, once per frame
        if event == "UNIT_AURA" and not form.again then
            form.again = true
            C_Timer.After(0, function() form.again = false; SeeForm() end)
        end
    end
    if event == "PLAYER_REGEN_ENABLED" then
        -- stacks stay after a fight: learned there (0.5 s after, as Alerts.lua reads your buffs: right
        -- at PLAYER_REGEN_ENABLED they may still be hidden)
        C_Timer.After(0.5, function()
            MaelstromSeen()
            if Find("game") then LogBuffs("after combat, proc game up") end
        end)
        if #rows == 0 then return end
        FFT:ProcEnd("stormstrike", "you left combat") -- it stays ready, but it's no proc any more
        return
    end
    if #rows == 0 then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = Plain(a3)
        if not id then return end
        local name = Plain(C_Spell.GetSpellName(id))
        if name == "Stormstrike" then FFT:ProcEnd("stormstrike", "you cast it") return end -- English: Alerts.lua
        if not (Plain(C_Spell.IsSpellHarmful(id)) or Plain(C_Spell.IsSpellHelpful(id))) then return end
        lastUse = {t = GetTime(), name = type(name) == "string" and name or "cast"}
        Used()
        return
    end
    -- UNIT_AURA: removed is a table of ids, or hidden as a whole in combat (then something was)
    local info = a2
    if IsSecret(info) or type(info) ~= "table" then return end
    local removed = info.removedAuraInstanceIDs
    if IsSecret(removed) or (type(removed) == "table" and #removed > 0) then
        lastRemoval = GetTime()
        Used()
    end
end)

------------------------------------------------------------------------
-- (1.31.0) Reactive abilities and the game's highlights, (the feed's
-- SPELL_ACTIVE as "<%s>", unless a button glow came within 0.5 s; the glow by its spell's name;
-- Overpower, Revenge, Riposte, Counterattack, Execute, Hammer of Wrath when the game says they can
-- be cast). None of these is in the author's logs yet (a shaman has no reactive
-- ability, and the game lit up no button in any of them): each is the game's own word.
------------------------------------------------------------------------
local lastSpellRowAt = -100 -- a usable ability or a highlight shown: the feed's notice for it says nothing more

local function SpellRow(name, color, seconds)
    lastSpellRowAt = GetTime()
    FFT:ProcShow("spell:" .. name, color, FFT.SpellIconText(name) .. name .. "!", nil, nil, seconds)
end

-- The feed's SPELL_ACTIVE (Blizzard's "Reactives", CombatText.lua: "<name>", gold, drawn as a crit).
-- Its name is secret; the game sends no end, so it stays REACTIVE_SECONDS (the window an ability
-- opened by a dodge or parry has, as their tooltips give it). Said a moment later, so a usable
-- ability's or a highlight's row for the same moment comes first and this one is left out.
local REACTIVE_SECONDS = 5
function FFT:OnReactiveNotice()
    local db = self.db
    if not (C_CombatText and C_CombatText.GetCurrentEventInfo) then return end
    local ok, name = pcall(C_CombatText.GetCurrentEventInfo)
    if not ok then return end
    if not IsSecret(name) and type(name) ~= "string" then return end
    Log("reactive notice <%s>", S(name))
    if not (db.enabled and db.showReactives) then return end
    local t = GetTime()
    C_Timer.After(0.3, function()
        if math.abs(lastSpellRowAt - t) <= 0.5 then return Log("  reactive notice: its ability's row is up") end
        FFT:ProcShow("reactive", FFT.Color("colorReactive"), nil, "%s", {name}, REACTIVE_SECONDS)
    end)
end

-- The game lights up a button (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW) or shows a proc's overlay
-- (SPELL_ACTIVATION_OVERLAY_SHOW), its spell ID plain (SpellActivationOverlayDocumentation.lua):
-- "<name>!" kept until the game's _HIDE for it. Before 1.31.0 a scrolling alert.
local fromOverlay = {} -- row key -> true: rows an overlay put up (an _HIDE with no spell ends all)
function FFT:HighlightShow(spellID, glow)
    local db = self.db
    if not (db and db.enabled and db.showAlerts) then return false end
    local name = Plain(spellID) and Plain(C_Spell.GetSpellName(spellID))
    if type(name) ~= "string" then return false end
    -- a highlight of an ability is gold as the reactive ones, a proc's overlay (a buff) blue
    SpellRow(name, FFT.Color(glow and "colorReactive" or "colorProc"), PROC_MAX)
    if not glow then fromOverlay["spell:" .. name] = true end
    return true
end
function FFT:HighlightHide(spellID, glow)
    local id = Plain(spellID)
    if id == nil and not glow then
        for key in pairs(fromOverlay) do self:ProcEnd(key, "the game's overlays went off") end
        fromOverlay = {}
        return
    end
    local name = id and Plain(C_Spell.GetSpellName(id))
    if type(name) ~= "string" then return end
    fromOverlay["spell:" .. name] = nil
    self:ProcEnd("spell:" .. name, glow and "the game's button glow went off" or "the game's overlay went off")
end

-- Abilities usable only just after something happens, kept while the game says they can be cast
-- (C_Spell.IsSpellUsable: no secrecy flag, SpellDocumentation.lua). By name
-- (the rank you know), shown only when it turns usable after the game was seen to say no with power
-- to spare (else its answer doesn't depend on the moment), kept while power runs short. An ability
-- this game doesn't have or you don't know never turns usable. {first rank's ID, class}
local REACTIVE_SPELLS = {
    {7384, "WARRIOR"},   -- Overpower: your target dodged
    {6572, "WARRIOR"},   -- Revenge: you blocked, dodged or parried
    {5308, "WARRIOR"},   -- Execute: your target is low on health
    {34428, "WARRIOR"},  -- Victory Rush: you killed an enemy (if the game has it)
    {14251, "ROGUE"},    -- Riposte: you parried
    {19306, "HUNTER"},   -- Counterattack: you parried
    {1495, "HUNTER"},    -- Mongoose Bite: your target dodged
    {24275, "PALADIN"},  -- Hammer of Wrath: your target is low on health
}
local usableNow, usableLearned = {}, {}
local lookPending = false
local function LookUsable()
    lookPending = false
    local db = FFT.db
    if not (db and db.enabled and db.showReactives and C_Spell and C_Spell.IsSpellUsable and UnitClass) then return end
    local _, class = UnitClass("player")
    for _, e in ipairs(REACTIVE_SPELLS) do
        if Plain(class) == e[2] then
            local name = Plain(C_Spell.GetSpellName(e[1]))
            if type(name) == "string" then
                local ok, yes, noPower = pcall(C_Spell.IsSpellUsable, name)
                yes, noPower = ok and Plain(yes), ok and Plain(noPower)
                if yes == true then
                    if not usableNow[name] and usableLearned[name] then
                        Log("%s usable (the game says so)", name)
                        SpellRow(name, FFT.Color("colorReactive"), 600)
                    end
                    usableNow[name] = true
                elseif yes == false and not noPower then
                    usableLearned[name] = true
                    if usableNow[name] then FFT:ProcEnd("spell:" .. name, "the game says it can't be cast now") end
                    usableNow[name] = nil
                end
            end
        end
    end
end

local usable = CreateFrame("Frame")
usable:RegisterEvent("SPELL_UPDATE_USABLE")
usable:RegisterEvent("PLAYER_TARGET_CHANGED")
usable:RegisterUnitEvent("UNIT_HEALTH", "target")
usable:SetScript("OnEvent", function()
    -- (1.31.3) a class with none of these abilities stops listening: UNIT_HEALTH "target" comes
    -- with every hit anyone lands on your target. UnitClass is asked here, not at load.
    -- the second value, the class token ("SHAMAN"): `UnitClass and UnitClass(...)` would keep only the first
    local class = Plain(UnitClass and select(2, UnitClass("player")))
    if type(class) == "string" then
        local any = false
        for _, e in ipairs(REACTIVE_SPELLS) do if e[2] == class then any = true end end
        if not any then
            usable:UnregisterEvent("SPELL_UPDATE_USABLE")
            usable:UnregisterEvent("PLAYER_TARGET_CHANGED")
            usable:UnregisterEvent("UNIT_HEALTH")
            return
        end
    end
    -- the game sends these in bursts: look once, at the end of the frame
    if lookPending then return end
    lookPending = true
    C_Timer.After(0, LookUsable)
end)

function FFT:TestProcs()
    C_Timer.After(0.2, function() FFT:ProcShow("game", FFT.Color("colorProc"), "Maelstrom Ready!", nil, nil, 4) end)
    C_Timer.After(0.8, function() FFT:ProcShow("stormstrike", FFT.Color("colorStormstrike"), "Stormstrike!", nil, nil, 3) end)
    C_Timer.After(1.4, function() FFT:ProcShow("test", FFT.Color("colorReactive"), "Overpower!", nil, nil, 2) end)
    C_Timer.After(2.0, function() FFT:ProcShow("test2", FFT.Color("colorCrowdControl"), LOSS_OF_CONTROL_DISPLAY_STUN or "Stunned", nil, nil, 2) end)
end
