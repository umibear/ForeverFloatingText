-- Forever Floating Text: Blizzard's own floating combat text. Which of its settings each feature
-- turns off while it replaces them (and puts back), the combat text feed kept on for the features
-- that read it, low health / mana from Blizzard's frame, and the notices about game settings.
-- (1.31.18) Moved here from Core.lua, which was at Lua's limit of 200 local variables a file.

local ADDON, ns = ...
local FFT = ns.FFT
local IsSecret, Plain, Print, Log, S = ns.IsSecret, ns.Plain, ns.Print, ns.Log, ns.S

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

local function WantHidden(cvar)
    if not (FFT.db.enabled and FFT.db.hideBlizzard) then return false end
    if cvar == HEAL_CVAR then return FFT.db.showHeals end
    if cvar == INTERRUPT_CVAR then return FFT.db.showInterrupts end
    if cvar == SELF_CVAR then return FFT.db.showIncoming end
    if ENERGY_CVARS[cvar] then return false end -- (1.24.0) never by CVar: they carry the feed
    if cvar == COMBAT_STATE_CVAR then return FFT.db.showCombatState end
    return true
end

-- (1.25.0) The features that read the COMBAT_TEXT_UPDATE feed: power gains, buffs on you and
-- (1.26.0) who healed you.
-- SELF_CVAR carries the whole feed; the energy CVars only the power kinds. Buff kinds came with
-- floatingCombatTextAuras_v2 at "0" (2026-11-09 08:04 log), so that one isn't touched.
local function FeedWanted()
    return FFT.db.enabled and (FFT.db.showPower or FFT.db.showAuras or FFT.db.showLowWarnings -- (1.28.7)
        or FFT.db.showGameProcs -- (1.31.0) the game's proc notices (Procs.lua)
        or FFT.db.showReactives -- (1.31.0) the game's reactive ability notices (Procs.lua)
        or (FFT.db.showIncoming and FFT.db.showIncomingHeals and FFT.db.showHealerNames)) -- (1.26.0)
end
FFT.FeedWanted = FeedWanted -- for /fft status (Core.lua)

-- "1" / "0" to set, nil to leave as the player had it. The feed wins over hiding: while a feature
-- needs it, SELF_CVAR stays "1" and Blizzard's text is hidden by its frame instead.
local function CVarTarget(cvar)
    if not FFT.db.enabled then return nil end
    if cvar == SELF_CVAR and FeedWanted() then return "1" end
    if ENERGY_CVARS[cvar] and FFT.db.showPower then return "1" end
    if WantHidden(cvar) then return "0" end
    return nil
end

-- (1.24.0) Blizzard's own text over your character, while SELF_CVAR is on only for the feed.
-- Hidden when "Show damage I take" replaces it, or when your own choice was "off" (the value
-- saved before the addon changed it). The same as SELF_CVAR "0" did, so its low health / mana
-- and ability alerts go with it, as before.
local function BlizzardSelfTextHidden()
    if not FFT.db.enabled then return false end
    if C_CVar.GetCVar(SELF_CVAR) ~= "1" then return false end -- nothing drawn anyway
    if FFT.db.hideBlizzard and FFT.db.showIncoming then return true end
    local own = FFT.db.savedCVars and FFT.db.savedCVars[SELF_CVAR]
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
        if type(info) == "table" and FFT.db.enabled and FFT.db.hideBlizzard and FFT.db[setting] and info.show ~= nil then
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
local function MuteNotHide() return FFT.db.enabled and FFT.db.showLowWarnings end
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
            if FFT.db and BlizzardSelfTextHidden() then
                if MuteNotHide() then f:SetAlpha(0) else f:Hide() end
                ctHiddenByUs = true
            end
        end)
        frame:HookScript("OnEvent", function(f, event)
            if FFT.db and (event == "UNIT_HEALTH" or event == "UNIT_POWER_UPDATE") then CheckLowMarks(f) end
        end)
        if type(frame.UpdateDisplayedMessages) == "function" then
            hooksecurefunc(frame, "UpdateDisplayedMessages", function() if FFT.db then HideBlizzardKinds() end end)
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
    if InCombatLockdown() then FFT.blizzardPending = true; return end
    FFT.blizzardPending = false
    local saved = FFT.db.savedCVars or {}
    FFT.db.savedCVars = saved -- BlizzardSelfTextHidden reads the saved value
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
    FFT.db.savedCVars = next(saved) and saved or nil
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
    for cvar, value in pairs(FFT.db.savedCVars or {}) do
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
    if not ns.IsLogging() then return end
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
    FFT.db.savedCVars = nil
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
    if FFT.db.enabled and FFT.db.hideBlizzard then
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
        if not (FFT.db.enabled and FFT.db.showPet) then return end
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

