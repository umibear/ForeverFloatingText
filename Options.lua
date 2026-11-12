-- Forever Floating Text options (Esc > Options > AddOns > Forever Floating Text, or /fft)
-- and the copy window for /fft copy.
--
-- (1.23.0) Reviewed with the author: the settings that are how the addon works (the Combat Log and its
-- own filter, the fallback's match window, hiding Blizzard's numbers) are no longer offered;
-- Core.lua FFT.LOCKED keeps them at their defaults. Names follow the game's own settings style.

local ADDON, ns = ...

local FONTS = {
    {"Fonts\\ARIALN.TTF",   "Arial Narrow"},
    {"Fonts\\FRIZQT__.TTF", "Friz Quadrata"},
    {"Fonts\\MORPHEUS.TTF", "Morpheus"},
    {"Fonts\\SKURRI.TTF",   "Skurri"},
}
local OUTLINES = {
    {"",             "None"},
    {"OUTLINE",      "Thin"},
    {"THICKOUTLINE", "Thick"},
}
local SCOPES = {
    {"mine",   "All my damage",       "Your and your pet's damage on every enemy nameplate. Other players' damage is never shown."},
    {"target", "Current target only", "Your and your pet's damage on your current target only."},
    {"all",    "Everyone's damage",   "Every hit on every enemy nameplate, including other players'."},
}
local DAMAGE_WHERE = { -- (1.30.0)
    {"plates", "Over nameplates", "Each number over the enemy it hit."},
    {"spot",   "Scrolling area",  "All your damage in one place on screen, at the position below."},
}
-- (1.30.0) the game's own quality names (ITEM_QUALITY0_DESC "Poor" ...), stored as a string
local LOOT_QUALITIES = {}
for q = 0, 4 do
    LOOT_QUALITIES[#LOOT_QUALITIES + 1] = {tostring(q), _G["ITEM_QUALITY" .. q .. "_DESC"] or tostring(q)}
end
-- SOUNDKIT keys, as in Forever's SoundKitConstants.lua
local CRIT_SOUNDS = {
    {"none",         "None"},
    {"RAID_WARNING", "Raid warning"},
    {"READY_CHECK",  "Ready check"},
    {"TELL_MESSAGE", "Whisper"},
}
local STYLES = {
    {"up",       "Scroll up"},
    {"fountain", "Fountain"},
}

local function ListOptions(list)
    return function()
        local container = Settings.CreateControlTextContainer()
        for _, item in ipairs(list) do
            container:Add(item[1], item[2], item[3])
        end
        return container:GetData()
    end
end

local function SliderOptions(min, max, step, fmt)
    local options = Settings.CreateSliderOptions(min, max, step)
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
            return fmt:format(v)
        end)
    end
    return options
end

-- Pages, as Blizzard's own implementation notes show (Blizzard_ImplementationReadme.lua):
-- a main category with subcategories, each setting registered on the page it's shown on.
function ns.CreateOptions(FFT)
    local db = FFT.db
    local main, mainLayout = Settings.RegisterVerticalLayoutCategory("Forever Floating Text")
    local page, layout -- the page being filled

    local function Page(category, categoryLayout) page, layout = category, categoryLayout end
    local function SubPage(name) Page(Settings.RegisterVerticalLayoutSubcategory(main, name)) end
    local function Setting(key, varType, name)
        return Settings.RegisterAddOnSetting(page, "OCT_" .. key, key, db, varType, name, FFT.DEFAULTS[key])
    end
    local function Header(name)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
    end
    local function Button(name, text, onClick, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer(name, text, onClick, tooltip, true))
    end
    local function Checkbox(key, name, tooltip, onChange)
        local s = Setting(key, Settings.VarType.Boolean, name)
        if onChange then s:SetValueChangedCallback(onChange) end
        Settings.CreateCheckbox(page, s, tooltip)
        return s
    end
    local function Slider(key, name, tooltip, min, max, step, fmt)
        local s = Setting(key, Settings.VarType.Number, name)
        Settings.CreateSlider(page, s, SliderOptions(min, max, step, fmt), tooltip)
        return s
    end
    local function Dropdown(key, name, tooltip, list)
        local s = Setting(key, Settings.VarType.String, name)
        Settings.CreateDropdown(page, s, ListOptions(list), tooltip)
        return s
    end
    local colorSettings = {}
    local function ColorSwatch(key, name, tooltip)
        -- the game's own color swatch: click it to open the color picker; stored as "ffRRGGBB"
        local s = Setting(key, Settings.VarType.String, name)
        layout:AddInitializer(Settings.CreateColorSwatchInitializer(s, nil, tooltip))
        colorSettings[key] = s
    end
    local function ApplyBlizzard() FFT:ApplyBlizzardText() end
    local function Preview()
        Button("Preview", "Test", function() FFT:Test() end,
            "Shows sample numbers on your target, or in the middle of the screen.")
    end
    -- The text settings and the drag-to-place position of a fixed spot (Spots.lua)
    local function SpotText(prefix, fontTip, sizeTip)
        Header("Text")
        Dropdown(prefix .. "Font", "Font", fontTip, FONTS)
        Dropdown(prefix .. "Outline", "Outline", nil, OUTLINES)
        Slider(prefix .. "Size", "Text size", sizeTip or ("Critical amounts are larger by the Critical size "
            .. "on the Text & Animation page."), 8, 40, 1, "%d")
    end
    local function SpotPosition(kind, xKey, yKey, frameColor)
        Header("Position")
        Button("Position", "Unlock", function() FFT:ToggleMover(kind) end,
            "Shows a " .. frameColor .. " frame you can drag into place. Click Lock all at the top of the "
            .. "screen, or right-click any frame, to lock them all. /fft move unlocks every position at once.")
        local x = Slider(xKey, "Horizontal offset", "Pixels from the center of the screen. Negative values are to the left.",
            -1200, 1200, 10, "%d")
        local y = Slider(yKey, "Vertical offset", "Pixels from the center of the screen. Negative values are below.",
            -700, 700, 10, "%d")
        ns.spotSettings[kind] = {x = x, y = y}
    end

    -- General
    Page(main, mainLayout)
    Header("General")
    Checkbox("enabled", "Enable Forever Floating Text",
        "Shows your own combat text. Turning it off restores the game's own combat text settings, "
        .. "and the Combat Log's previous filter after your next /reload.", ApplyBlizzard)
    Preview()
    -- (1.31.5, the author: /fft move as a button in the options too)
    Header("Positions")
    Button("Move frames", "Unlock all", function() FFT:UnlockAllMovers() end,
        "Shows a frame for each place text appears (damage, incoming, alerts, buffs, procs, loot) to drag "
        .. "into place. Click Lock all at the top of the screen, or right-click any frame, to lock them all. "
        .. "Each page's Position section unlocks just its own. Same as /fft move.")

    -- Damage
    SubPage("Damage")
    Header("Damage Done")
    Dropdown("scope", "Show damage", "Which hits are shown. With enemy nameplates off, the game "
        .. "reports hits on your current target only.", SCOPES)
    Checkbox("showPet", "Include pet damage", "Also show the damage your pet deals.")
    -- (1.30.0)
    Dropdown("damageWhere", "Damage position", "Over each enemy's nameplate, or in one scrolling area "
        .. "at the position below. Either way the addon needs enemy nameplates on to see hits on "
        .. "enemies other than your target; your target's damage when it has no nameplate always "
        .. "shows at the position below.", DAMAGE_WHERE)
    Header("Details")
    Checkbox("showMisses", "Show misses",
        "Your attacks that miss, or that are dodged, parried, blocked or resisted.")
    Checkbox("showInterrupts", "Show interrupts",
        "\"Interrupted\" over an enemy when your Earth Shock, Kick, Counterspell or similar stops its cast. "
        .. "The game's own \"Interrupted\" text is hidden meanwhile.", ApplyBlizzard)
    local sound = Dropdown("critSound", "Critical hit sound",
        "Plays when your hit or heal is critical. Selecting a sound plays it once.", CRIT_SOUNDS)
    sound:SetValueChangedCallback(function(_, value)
        if value ~= "none" and SOUNDKIT and SOUNDKIT[value] then C_Sound.PlaySound(SOUNDKIT[value]) end
    end)
    Preview()
    -- (1.30.0) the scrolling area; its text is the nameplate text's (Text & Animation page)
    SpotPosition("damage", "damageX", "damageY", "purple") -- your healing without a nameplate too
    Button("Preview", "Test", function() FFT:TestDamageSpot() end,
        "Shows sample damage at the position. Its font and size are the Text & Animation page's.")

    -- Healing
    SubPage("Healing")
    Header("Healing Done")
    Checkbox("showHeals", "Show healing done",
        "Above the friendly nameplate when it's shown; otherwise with your damage, at the damage "
        .. "position (Damage page), with the target's name. With the scrolling area chosen there, every heal "
        .. "goes there. Includes Chain Heal jumps. The game's own healing text is hidden meanwhile.", ApplyBlizzard)
    Checkbox("showHotTicks", "Show periodic healing",
        "Ticks of Renew, Rejuvenation, Healing Stream Totem and similar. Each spell's tick rhythm is "
        .. "learned the first time you use it outside a group; /fft heals lists what has been learned.")
    Button("Preview", "Test", function() if FFT.TestHeals then FFT:TestHeals() end end,
        "Shows two sample heals at the damage position.")

    -- Incoming
    SubPage("Incoming")
    Header("Incoming")
    Checkbox("showIncoming", "Show incoming damage",
        "Damage you take, at its own position. The game's own combat text over your character is turned off "
        .. "meanwhile: the game has no separate switch for its incoming damage, so its low health and low mana "
        .. "warnings go with it. If another addon shows incoming damage, turn it off there.", ApplyBlizzard)
    Checkbox("showIncomingMisses", "Show avoided attacks",
        "Attacks on you that miss, or that you dodge, parry, block, resist, absorb or are immune to.")
    Checkbox("showIncomingHeals", "Show incoming healing",
        "Heals other players cast on you, in the healing color. "
        .. "Your own heals on yourself are shown with your healing done.", ApplyBlizzard)
    Checkbox("showHealerNames", "Show who healed you",
        "\"+420 [Name]\" on direct heals, the way the game's own combat text does; heal-over-time ticks "
        .. "stay without a name. When two heals land on you at the same moment, which name goes with "
        .. "which can't be told, so they're shown without names.", ApplyBlizzard)
    Checkbox("incomingSchoolColors", "Color by spell school",
        "Use the spell school colors instead of the incoming damage color.")
    SpotText("incoming", "Its own font, separate from your other numbers. Resource gains show here too.")
    SpotPosition("incoming", "incomingX", "incomingY", "red")
    Button("Preview", "Test", function() FFT:TestIncoming() end, "Shows sample incoming damage at the position.")

    -- Resources (1.22.0)
    SubPage("Resources")
    Header("Resource Gains")
    Checkbox("showPower", "Show resource gains",
        "Mana, rage and energy the game reports as gained: Life Tap, Evocation, potions, Mana Spring Totem, "
        .. "Bloodrage, Thistle Tea and similar, from you or from others. Natural regeneration isn't reported. "
        .. "To get them, the game's floating combat text stays on while this (or buffs gained / faded) is on; the addon hides "
        .. "the game's own text over your character instead.", ApplyBlizzard)
    Checkbox("showPeriodicPower", "Show periodic resource gains",
        "Gains that come every few seconds: Mana Spring Totem, Blessing of Wisdom and the like. Off by default.")
    Checkbox("powerNames", "Show resource type",
        "\"+30 Mana\" instead of \"+30\". The type the game reports; when it's hidden, the type of your "
        .. "current power bar is used, so a shapeshifted druid gaining mana may be labeled wrong.")
    Button("Preview", "Test", function() FFT:TestPower() end,
        "Shows two sample gains at the incoming position (Incoming page), in its font.")

    -- Loot (1.30.0)
    SubPage("Loot & Gains")
    Header("Loot")
    Checkbox("showLoot", "Show loot",
        "Items you loot or receive, \"+[Linen Cloth] x2\", in their quality color. Read from the game's "
        .. "own loot messages; if the game hides one from addons (it may, in some places), it isn't shown.")
    Dropdown("lootMinQuality", "Lowest quality shown", "Items below this aren't shown. Quest items always are.",
        LOOT_QUALITIES)
    Checkbox("showMoney", "Show money", "Money you loot, or your share of it in a group.")
    -- (1.31.0) gains, at the same position (Notices.lua)
    Header("Gains")
    Checkbox("showExperience", "Show experience", "\"+120 XP\", from the game's own messages.")
    Checkbox("showHonor", "Show honor", "\"+15 Honor\".")
    Checkbox("showReputation", "Show reputation", "\"+25 Stormwind\", \"-10 Booty Bay\".")
    Checkbox("showSkills", "Show skill gains", "\"Mining: 76\".")
    Checkbox("showCurrency", "Show currency", "Currency you receive.")
    SpotText("loot", "Its own font, separate from your other numbers.")
    SpotPosition("loot", "lootX", "lootY", "teal")
    Button("Preview", "Test", function() FFT:TestLoot() end, "Shows sample loot at the position.")

    -- Alerts
    SubPage("Alerts")
    Header("Alerts")
    Checkbox("showCombatState", "Show combat state",
        "\"+Combat\" and \"-Combat\" as you enter and leave combat. "
        .. "The game's own combat state text is hidden meanwhile.", ApplyBlizzard)
    Checkbox("showKills", "Show killing blows",
        "\"Killing Blow!\" when you or your pet deal the killing blow, as reported by the game's Combat Log. "
        .. "The game doesn't say which enemy it was, nor whether a player or a creature, so with this on every "
        .. "kill shows. Off by default.")
    Checkbox("showWindfury", "Show Windfury procs",
        "\"Windfury!\" when Windfury gives you extra attacks, shown with the first of them. "
        .. "A proc whose extra attacks all miss isn't shown.")
    Checkbox("showDispels", "Show your dispels",
        "\"Purged\", \"Cleansed\", \"Stolen\", \"Dispel failed\", and \"Broke crowd control\" when your hit breaks "
        .. "one, from your own Combat Log lines. Starts after one /reload once this version runs: the addon "
        .. "writes its Combat Log filter as you log out, and the game takes it at the next login.")
    Checkbox("showEmotes", "Show your target's emotes", "\"Bristleback goes into a frenzy!\": your target's own emotes.")
    Checkbox("showCooldowns", "Show cooldowns ready",
        "\"Grounding Totem ready!\" when a spell of yours, or an item you used, can be used again.")
    Slider("cooldownMin", "Shortest cooldown", "Cooldowns shorter than this aren't told.", 3, 60, 1, "%ds")
    SpotText("alert", "Its own font, separate from your other numbers.", "The size of every alert.")
    SpotPosition("alerts", "alertsX", "alertsY", "yellow")
    Button("Preview", "Test", function() FFT:TestAlerts(); FFT:TestNotices() end, "Shows sample alerts at the position.")

    -- Buffs (1.31.0): their own position, apart from the alerts
    SubPage("Buffs")
    Header("Buffs and Debuffs")
    Checkbox("showAuras", "Show buffs gained",
        "\"<Lightning Shield>\" when a buff or debuff lands on you; buffs green, debuffs red. The game keeps the "
        .. "name hidden from addons in combat, so there every one shows. The game's own text for them is hidden "
        .. "meanwhile.", ApplyBlizzard)
    Checkbox("showAuraFades", "Show buffs faded", "\"<Lightning Shield> fades\" when one goes. Off by default.")
    Checkbox("showTotemBuffs", "Show your totems' buffs",
        "\"<Strength of Earth>\" when your own totem's buff reaches you. Off by default: you just placed the totem.")
    Header("Hide list")
    Button("Hidden buffs", "List", function() FFT:HideBuff() end,
        "Prints the buffs you chose not to see. Type /fft hide <buff name> to add one, /fft unhide <buff name> "
        .. "to take it off. Out of combat any buff can be left out; in combat only those the game names to addons "
        .. "(your totems' buffs and the like).")
    SpotText("buff", "Its own font, separate from your other numbers.")
    SpotPosition("buffs", "buffsX", "buffsY", "blue")
    Button("Preview", "Test", function() FFT:TestBuffs() end, "Shows two sample buffs at the position.")

    -- Procs (1.31.0): kept still at their own position while they last
    SubPage("Procs")
    Header("Procs")
    Checkbox("showStormstrikeReset", "Show Stormstrike reset",
        "\"Stormstrike!\" when Stormstrike's cooldown is reset (a shaman talent: when you dodge or parry), "
        .. "so you know you can use it again. Shown when the game reports it ready before its 6 second "
        .. "cooldown is over, and kept until you cast Stormstrike or leave combat (10 seconds at most).")
    Checkbox("showGameProcs", "Show the game's proc notices",
        "Notices the game gives for a proc, such as \"Maelstrom Ready!\" at five stacks of Maelstrom Weapon. "
        .. "Kept until a spell of yours uses it up (30 seconds at most). The game keeps the name hidden from "
        .. "addons, so every notice it sends shows. The game's own text for them is hidden meanwhile.",
        ApplyBlizzard)
    Checkbox("showReactives", "Show reactive abilities",
        "Abilities you can use only just after something happens: Overpower, Revenge, Execute, Victory Rush, "
        .. "Riposte, Counterattack, Mongoose Bite, Hammer of Wrath. Kept while the game says they can be cast. "
        .. "Also the game's own reactive notices (\"<Overpower>\"), kept 5 seconds: the game keeps their name "
        .. "hidden and doesn't say when they end. The game's own text for them is hidden meanwhile.", ApplyBlizzard)
    Checkbox("showAlerts", "Show highlighted spells",
        "Spells the game lights up for you, such as Overpower or Clearcasting: \"Clearcasting!\", kept until "
        .. "the game turns the highlight off.")
    Checkbox("showCrowdControl", "Show crowd control on you",
        "\"Stunned\", \"Silenced\", \"Shadow Locked\" and the like, in the game's own words, kept while it lasts. "
        .. "Off by default: the game shows it already, with its icon, in the middle of the screen. "
        .. "Where the game hides it from addons, nothing shows.")
    Checkbox("showLowWarnings", "Show low health / mana",
        "\"Health Low\" and \"Mana Low\", in the game's own words, kept while your health or mana is under 20%. "
        .. "The game works this out itself; the addon keeps its combat text running unseen to hear it.", ApplyBlizzard)
    SpotText("proc", "Its own font, separate from your other numbers.", "The size of every proc.")
    SpotPosition("procs", "procsX", "procsY", "green")
    Button("Preview", "Test", function() FFT:TestProcs() end, "Shows sample procs at the position.")

    -- Icons (1.31.0): procs and alerts whose spell or item is known
    Header("Icons")
    Checkbox("showIcons", "Show icons", "An icon before procs and alerts whose spell or item is known.")

    -- Text & animation
    SubPage("Text & Animation")
    Header("Text")
    Dropdown("font", "Font", "The font of your damage and healing numbers, over nameplates or in the scrolling area.", FONTS)
    Dropdown("outline", "Outline", nil, OUTLINES)
    Slider("size", "Text size", nil, 8, 40, 1, "%d")
    Slider("critScale", "Critical size", "Critical hits and heals, relative to the text size.", 1, 2.5, 0.1, "%.1fx")
    Slider("glancingScale", "Glancing size", "Your glancing blows, relative to the text size. "
        .. "The game's own combat text uses 0.75; 1.0 shows them at normal size.", 0.5, 1, 0.05, "%.2fx")
    Slider("interruptScale", "Interrupt size", "\"Interrupted\", relative to the text size.", 0.5, 2.5, 0.1, "%.1fx")
    Checkbox("markBlocked", "Mark blocked hits", "Partially blocked hits read \"123 (Block)\", as in the "
        .. "game's own combat text: yours on enemies and theirs on you. The game doesn't report the amount blocked.")
    Checkbox("shortNumbers", "Abbreviate large numbers", "12,345 is shown as 12.3K.")
    Slider("minAmount", "Minimum amount", "Your damage and healing below this amount are not shown. "
        .. "0 shows everything. Amounts the game keeps hidden (in some fights) are always shown.", 0, 2000, 10, "%d")
    Header("Animation")
    Dropdown("style", "Animation", nil, STYLES)
    Slider("duration", "Duration", "How long each number stays on screen.", 0.5, 3, 0.1, "%.1fs")
    Slider("distance", "Scroll distance", nil, 10, 120, 5, "%d")
    Slider("offsetY", "Nameplate offset", "Height above the nameplate.", 0, 60, 2, "%d")
    Preview()

    -- Colors
    SubPage("Colors")
    Header("Damage")
    Checkbox("schoolColors", "Color damage by spell school", "When off, all damage numbers are white.")
    ColorSwatch("colorAuto", "Auto attacks", "Your melee swings.")
    ColorSwatch("colorPet", "Pet", "Your pet's damage.")
    ColorSwatch("colorPhysical", "Physical", "Physical abilities: Stormstrike, Heroic Strike, Sinister Strike and similar.")
    ColorSwatch("colorHoly", "Holy")
    ColorSwatch("colorFire", "Fire")
    ColorSwatch("colorNature", "Nature")
    ColorSwatch("colorFrost", "Frost")
    ColorSwatch("colorShadow", "Shadow")
    ColorSwatch("colorArcane", "Arcane")
    Header("Other")
    ColorSwatch("colorIncoming", "Incoming damage", "Damage you take, unless it uses the spell school colors.")
    ColorSwatch("colorHeal", "Healing")
    ColorSwatch("colorMiss", "Misses")
    ColorSwatch("colorInterrupt", "Interrupts")
    ColorSwatch("colorAlert", "Ability alerts")
    ColorSwatch("colorPower", "Resource gains", "The default is the game's own.")
    ColorSwatch("colorCombat", "Combat state", "The default is the game's own.")
    ColorSwatch("colorKill", "Killing blows")
    ColorSwatch("colorBuff", "Buffs gained / faded", "The default is the game's own.")
    ColorSwatch("colorDebuff", "Debuffs gained / faded", "The default is the game's own.")
    ColorSwatch("colorStormstrike", "Stormstrike reset", "At the procs position.")
    ColorSwatch("colorProc", "Game proc notices", "\"Maelstrom Ready!\" and the like, at the procs position.")
    ColorSwatch("colorReactive", "Reactive abilities", "Overpower, Execute and the like, and lit-up buttons. The default is the game's own.")
    ColorSwatch("colorCrowdControl", "Crowd control on you", "And crowd control your hit broke.")
    ColorSwatch("colorDispel", "Your dispels")
    ColorSwatch("colorEmote", "Your target's emotes")
    ColorSwatch("colorCooldown", "Cooldowns ready")
    ColorSwatch("colorExperience", "Experience")
    ColorSwatch("colorHonor", "Honor")
    ColorSwatch("colorReputation", "Reputation")
    ColorSwatch("colorSkill", "Skill gains")
    Button("Colors", "Reset", function()
        for _, key in ipairs(FFT.COLOR_KEYS) do colorSettings[key]:SetValue(FFT.DEFAULTS[key]) end
    end, "Restores every color to its default.")
    Preview()

    -- Troubleshooting (was Advanced, 1.23.0: its switches are now fixed, see FFT.LOCKED)
    SubPage("Troubleshooting")
    Header("Troubleshooting")
    Button("Status", "Show", function() FFT:Status() end,
        "Prints in chat how your hits are being told apart and why. Same as /fft status.")
    Button("Combat Log", "Recheck", function() FFT:ClogEnable() end,
        "Checks the game's Combat Log filter again and turns its messages back on. Same as /fft clog.")
    Button("Game combat text settings", "Restore defaults", function() FFT:ResetBlizzardCVars() end,
        "Restores the game's own floating combat text settings to their defaults. The ones this addon "
        .. "replaces stay hidden while their feature is on. /fft cvars lists them.")

    Settings.RegisterAddOnCategory(main)
    ns.OpenOptions = function() Settings.OpenToCategory(main:GetID()) end
end

------------------------------------------------------------------------
-- Copy window for the debug log (chat can't be copied from)
------------------------------------------------------------------------
local copyFrame
function ns.ShowCopyWindow(text)
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "ForeverFloatingTextCopy", UIParent, "BasicFrameTemplateWithInset")
        copyFrame:SetSize(600, 400)
        copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("DIALOG")
        copyFrame:SetMovable(true)
        copyFrame:EnableMouse(true)
        copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
        if copyFrame.TitleText then copyFrame.TitleText:SetText("Forever Floating Text debug (Ctrl+A, Ctrl+C)") end

        local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -30)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(550)
        edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scroll:SetScrollChild(edit)
        copyFrame.edit = edit
    end
    copyFrame.edit:SetText(text)
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText()
end
