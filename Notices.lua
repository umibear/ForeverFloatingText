-- Forever Floating Text notices (1.31.0), at the alerts spot; gains (experience, honor, reputation,
-- skill, currency) with your loot.
--  * Experience, honor, reputation, skill gains, currency: the game's own chat messages, read with
--    the game's own templates (as Loot.lua does). The texts aren't marked
--    NeverSecret (ChatInfoDocumentation.lua), so a hidden one is skipped and logged; loot messages,
--    read the same way, were readable 275 of 275 in the author's 2026-11-11 dungeon run.
--  * Crowd control on you: LOSS_OF_CONTROL_ADDED, C_LossOfControl.GetActiveLossOfControlData
--    (SecretWhenLossOfControlRestricted: hidden then, and its text is drawn as the game gives it),
--    "Stunned", "Shadow Locked" as LossOfControlFrame.lua writes them.
--  * Your dispels: lines of their own kinds in the addon's Combat Log filter (Core.lua OWN_EVENTS):
--    "Purged", "Cleansed", "Stolen", "Dispel failed", and your
--    hit breaking crowd control.
--  * Your target's emotes ("%s goes into a frenzy!"): CHAT_MSG_MONSTER_EMOTE from the unit you target.
--  * Cooldowns ready: your spells (C_Spell.GetSpellCooldown's isActive, NeverSecret) and items you
--    use (C_Container.GetItemCooldown, no secrecy flag), when the
--    cooldown lasted at least "cooldownMin" seconds.
-- None of these is in the author's logs yet.

local ADDON, ns = ...
local FFT = ns.FFT
local Plain, Log, S, IsSecret = ns.Plain, ns.Log, ns.S, ns.IsSecret

local function Alert(text, colorKey, fmt, args)
    FFT:ShowAlert(text, FFT.Color(colorKey), fmt, args)
end
-- (1.31.0) gains show with your loot (the author: "exp needs to go with loot")
local function Gain(text, colorKey)
    if FFT.ShowLootText then FFT.ShowLootText(text, colorKey and FFT.Color(colorKey)) end
end

------------------------------------------------------------------------
-- Gains, from chat messages
------------------------------------------------------------------------
-- longer forms first: "%s" alone would take them too
local GAINS = {
    CHAT_MSG_COMBAT_XP_GAIN = {setting = "showExperience", color = "colorExperience", templates = {
        "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION1_RAID", "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP",
        "COMBATLOG_XPGAIN_EXHAUSTION2_RAID", "COMBATLOG_XPGAIN_EXHAUSTION4_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION4_RAID",
        "COMBATLOG_XPGAIN_EXHAUSTION5_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION5_RAID", "COMBATLOG_XPGAIN_EXHAUSTION1",
        "COMBATLOG_XPGAIN_EXHAUSTION2", "COMBATLOG_XPGAIN_EXHAUSTION4", "COMBATLOG_XPGAIN_EXHAUSTION5",
        "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID", "COMBATLOG_XPGAIN_FIRSTPERSON",
        "COMBATLOG_XPGAIN_QUEST", "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP",
        "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID", "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED"}},
    CHAT_MSG_COMBAT_HONOR_GAIN = {setting = "showHonor", color = "colorHonor", templates = {
        "COMBATLOG_HONORGAIN", "COMBATLOG_HONORAWARD"}},
    CHAT_MSG_COMBAT_FACTION_CHANGE = {setting = "showReputation", color = "colorReputation", templates = {
        "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_BONUS",
        "FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE", "FACTION_STANDING_INCREASED_ACH_BONUS",
        "FACTION_STANDING_INCREASED_ACCOUNT_WIDE", "FACTION_STANDING_DECREASED_ACCOUNT_WIDE",
        "FACTION_STANDING_INCREASED", "FACTION_STANDING_DECREASED"}},
    CHAT_MSG_SKILL = {setting = "showSkills", color = "colorSkill", templates = {"SKILL_RANK_UP"}},
    CHAT_MSG_CURRENCY = {setting = "showCurrency", templates = {
        "CURRENCY_GAINED_MULTIPLE_OVERFLOW", "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE",
        "CURRENCY_GAINED"}},
}
local gainPatterns = {}
local function Match(text, templates)
    for _, name in ipairs(templates) do
        if gainPatterns[name] == nil then gainPatterns[name] = ns.ToPattern(_G[name]) or false end
        local p = gainPatterns[name]
        if p then
            local caps = {text:match(p)}
            if caps[1] then return caps, name end
        end
    end
end
local function FirstNumber(caps)
    for _, c in ipairs(caps) do if c:match("^%d+$") then return tonumber(c) end end
end

function FFT:OnGainMessage(event, text)
    local db = self.db
    local how = GAINS[event]
    if not (how and db and db.enabled and db[how.setting]) then return end
    if IsSecret(text) then return Log("gain message (%s): hidden, skipped", event) end
    if type(text) ~= "string" then return end
    local caps, name = Match(text, how.templates)
    if not caps then return Log("gain message (%s): readable, no template matched", event) end
    local n = FirstNumber(caps)
    Log("gain message (%s): readable, %s, %s", event, name, tostring(n))
    if event == "CHAT_MSG_COMBAT_XP_GAIN" and n then
        Gain(("+%d %s"):format(n, XP or "XP"), how.color)
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" and n then
        Gain(("+%d %s"):format(n, HONOR or "Honor"), how.color)
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" and n then
        Gain(("%s%d %s"):format(name:find("DECREASED") and "-" or "+", n, caps[1]), how.color)
    elseif event == "CHAT_MSG_SKILL" and n then
        Gain(("%s: %d"):format(caps[1], n), how.color)
    elseif event == "CHAT_MSG_CURRENCY" then
        local link, count = caps[1], tonumber(caps[2] or "")
        Gain(("+%s%s"):format(link, (count and count > 1) and (" x" .. count) or ""))
    end
end

local gains = CreateFrame("Frame")
for event in pairs(GAINS) do gains:RegisterEvent(event) end
gains:SetScript("OnEvent", function(_, event, text) FFT:OnGainMessage(event, text) end)

------------------------------------------------------------------------
-- Crowd control on you
------------------------------------------------------------------------
local lastCC = {}
local ccKeys = {} -- procs rows of crowd control now up
local CC_MAX = 30 -- seconds: a crowd control whose time the game hides and whose end never comes
function FFT:OnLossOfControl(unit, index)
    local db = self.db
    if not (db and db.enabled and db.showCrowdControl) then return end
    if IsSecret(unit) or unit ~= "player" or not C_LossOfControl then return end
    local get = C_LossOfControl.GetActiveLossOfControlDataByUnit
    local ok, data
    if get then ok, data = pcall(get, "player", index)
    else ok, data = pcall(C_LossOfControl.GetActiveLossOfControlData, index) end
    if not ok or data == nil then return end
    if IsSecret(data) or type(data) ~= "table" then return Log("crowd control on you: hidden, skipped") end
    local text = data.displayText
    if not IsSecret(text) and type(text) ~= "string" then return end
    -- a kick locks a school: "Shadow Locked" (LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL)
    if Plain(data.locType) == "SCHOOL_INTERRUPT" and Plain(data.lockoutSchool) and C_Spell.GetSchoolString then
        local okSchool, school = pcall(C_Spell.GetSchoolString, data.lockoutSchool)
        school = okSchool and Plain(school)
        if type(school) == "string" then
            text = (type(LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL) == "string" and LOSS_OF_CONTROL_DISPLAY_INTERRUPT_SCHOOL
                or "%s Locked"):format(school)
        end
    end
    local key = Plain(data.spellID) or (not IsSecret(text) and text) or "cc"
    local now = GetTime()
    if lastCC[key] and now - lastCC[key] < 0.3 then return end
    lastCC[key] = now
    Log("crowd control on you: %s (spell %s, %s)", S(text), S(data.spellID), S(data.locType))
    local icon = FFT.IconText(Plain(data.iconTexture))
    -- (1.31.0) at the procs spot, kept while it lasts (the game's own time left when readable, else
    -- until LOSS_OF_CONTROL_UPDATE says none is left), at most CC_MAX
    local left = Plain(data.timeRemaining) or Plain(data.duration)
    left = (type(left) == "number" and left > 0) and math.min(left, CC_MAX) or CC_MAX
    if FFT.ProcShow then
        ccKeys["cc:" .. tostring(key)] = true
        FFT:ProcShow("cc:" .. tostring(key), FFT.Color("colorCrowdControl"), nil, icon .. "%s", {text}, left)
    else
        Alert(nil, "colorCrowdControl", icon .. "%s", {text})
    end
end

local cc = CreateFrame("Frame")
cc:RegisterEvent("LOSS_OF_CONTROL_ADDED")
cc:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
cc:SetScript("OnEvent", function(_, event, unit, index)
    if event == "LOSS_OF_CONTROL_ADDED" then return FFT:OnLossOfControl(unit, index) end
    -- none left on you: every crowd control row goes (LossOfControlDocumentation.lua)
    if IsSecret(unit) or unit ~= "player" or not next(ccKeys) or not C_LossOfControl then return end
    local count = C_LossOfControl.GetActiveLossOfControlDataCountByUnit
    local ok, n = false, nil
    if count then ok, n = pcall(count, "player")
    elseif C_LossOfControl.GetActiveLossOfControlDataCount then ok, n = pcall(C_LossOfControl.GetActiveLossOfControlDataCount) end
    if ok and Plain(n) == 0 then
        for key in pairs(ccKeys) do FFT:ProcEnd(key, "you're back in control") end
        ccKeys = {}
    end
end)

------------------------------------------------------------------------
-- Your dispels (Core.lua: a Combat Log line of one of these kinds)
------------------------------------------------------------------------
local DISPEL_TEXT = {purge = "Purged", cleanse = "Cleansed", steal = "Stolen", dispelFailed = "Dispel failed",
    broke = "Broke crowd control"}
local lastCast = {t = -100}
local dispelShownAt = {}
function FFT:OnDispelLine(kind)
    local db = self.db
    if not (db and db.enabled and db.showDispels and DISPEL_TEXT[kind]) then return end
    local now = GetTime()
    if dispelShownAt[kind] and now - dispelShownAt[kind] < 0.05 then return end -- one per moment (Purge took two)
    dispelShownAt[kind] = now
    local icon = now - lastCast.t <= 1.0 and FFT.SpellIconText(lastCast.id) or ""
    Log("your %s line (%s)", kind, lastCast.name and now - lastCast.t <= 1.0 and ("after your " .. lastCast.name) or "no cast of yours just before")
    Alert(icon .. DISPEL_TEXT[kind], kind == "broke" and "colorCrowdControl" or "colorDispel")
end

------------------------------------------------------------------------
-- Your target's emotes
------------------------------------------------------------------------
function FFT:OnMonsterEmote(text, source)
    local db = self.db
    if not (db and db.enabled and db.showEmotes) then return end
    if IsSecret(text) or IsSecret(source) or type(text) ~= "string" or type(source) ~= "string" then return end
    local ok, target = pcall(UnitName, "target")
    target = ok and Plain(target)
    if target ~= source then return end
    local shown = text:gsub("%%s", function() return source end)
    Log("emote of your target: %s", shown)
    Alert(shown, "colorEmote")
end

local emotes = CreateFrame("Frame")
emotes:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
emotes:SetScript("OnEvent", function(_, _, text, source) FFT:OnMonsterEmote(text, source) end)

------------------------------------------------------------------------
-- Cooldowns ready
------------------------------------------------------------------------
-- A spell: looked at once its global cooldown is over (1.6 s after the cast: at the cast it may read
-- "on the GCD"); still on its cooldown then, it's watched until the game says it isn't (on every
-- SPELL_UPDATE_COOLDOWN). Shown if it lasted cooldownMin or longer: start and duration may be
-- hidden, so the time is your own, from the cast.
-- (1.31.2) Also looked at every 0.1 s while one is watched: the game sends SPELL_UPDATE_COOLDOWN
-- when a cooldown starts, not when it ends. In the author's 2026-11-12 15:06 log each "ready" came
-- at the next cast of anything: Flame Shock 17-33 s after its cast, Frost Shock 12-40 s, Earth
-- Shock 19-38 s, Stormstrike 10-13 s, Blood Fury 122 s, while the game's file has Shocks cast again
-- 6.45 s apart. And "on the GCD" counts as over: the game reports the longer of the spell's own
-- cooldown and the GCD, so the GCD outlasting it means its own is done (Stormstrike, 2026-11-10
-- 07:48 log). Read only after the GCD of its own cast (below), so never the cast's own GCD.
local POLL = 0.1
local WATCH_MAX = 900 -- seconds: a spell whose cooldown can't be read any more stops being watched
local watched = {} -- spellID -> {t, name}
local ticker
local function Ready(name, icon, took)
    Log("cooldown ready: %s (%.1f s)", name, took)
    Alert(icon .. ("%s ready!"):format(name), "colorCooldown")
end
local function SpellCooldown(id)
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or IsSecret(info) or type(info) ~= "table" then return nil end
    return Plain(info.isActive), Plain(info.isOnGCD)
end
local function LookCooldowns()
    local db = FFT.db
    for id, w in pairs(watched) do
        local active, gcd = SpellCooldown(id)
        local took = GetTime() - w.t
        if active == false or (active == true and gcd == true) then
            watched[id] = nil
            if db and db.enabled and db.showCooldowns and took >= (db.cooldownMin or 5) then
                Ready(w.name, FFT.SpellIconText(id), took)
            end
        elseif took > WATCH_MAX then
            watched[id] = nil
        end
    end
    if ticker and not next(watched) then ticker:Cancel(); ticker = nil end
end
local function OnSpellCast(id)
    local name = Plain(C_Spell.GetSpellName(id))
    if type(name) ~= "string" then return end
    lastCast = {t = GetTime(), id = id, name = name}
    watched[id] = nil -- cast again: it was ready; its new cooldown is looked at below
    local db = FFT.db
    if not (db and db.enabled and db.showCooldowns) then return end
    local t = GetTime()
    C_Timer.After(1.6, function()
        local active, gcd = SpellCooldown(id)
        if active == true and gcd ~= true then
            watched[id] = {t = t, name = name}
            if not ticker then ticker = C_Timer.NewTicker(POLL, LookCooldowns) end
        end
    end)
end

-- An item you use: your action buttons, bags and equipped items (hooks after the game's own call)
local function OnItemUsed(itemID)
    itemID = Plain(itemID)
    local db = FFT.db
    if type(itemID) ~= "number" or not (db and db.enabled and db.showCooldowns) then return end
    if not (C_Container and C_Container.GetItemCooldown) then return end
    C_Timer.After(1.0, function()
        local ok, start, duration, enable = pcall(C_Container.GetItemCooldown, itemID)
        start, duration, enable = ok and Plain(start), ok and Plain(duration), ok and Plain(enable)
        if type(start) ~= "number" or type(duration) ~= "number" or enable ~= 1 then return end
        if duration < (FFT.db.cooldownMin or 5) or start <= 0 then return end
        local left = start + duration - GetTime()
        if left <= 0 then return end
        C_Timer.After(left, function()
            if not (C_Item and C_Item.GetItemNameByID and C_Item.GetItemIconByID) then return end
            local okName, name = pcall(C_Item.GetItemNameByID, itemID)
            name = okName and Plain(name)
            if type(name) ~= "string" then return end
            local okIcon, icon = pcall(C_Item.GetItemIconByID, itemID)
            Ready(name, okIcon and FFT.IconText(Plain(icon)) or "", duration)
        end)
    end)
end
if hooksecurefunc then
    if UseAction then
        hooksecurefunc("UseAction", function(slot)
            local ok, kind, id = pcall(GetActionInfo, slot)
            if ok and Plain(kind) == "item" then OnItemUsed(id) end
        end)
    end
    if UseInventoryItem then
        hooksecurefunc("UseInventoryItem", function(slot)
            local ok, id = pcall(GetInventoryItemID, "player", slot)
            if ok then OnItemUsed(id) end
        end)
    end
    if C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
            local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
            if ok then OnItemUsed(id) end
        end)
    end
end

local cooldowns = CreateFrame("Frame")
cooldowns:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
cooldowns:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cooldowns:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local id = Plain(spellID)
        if id then OnSpellCast(id) end
    elseif next(watched) then
        LookCooldowns()
    end
end)

function FFT:TestNotices()
    local db = self.db
    if db.showCooldowns then C_Timer.After(0.9, function() Alert("Grounding Totem ready!", "colorCooldown") end) end
end
