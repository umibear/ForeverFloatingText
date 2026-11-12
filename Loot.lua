-- Forever Floating Text loot (1.30.0): items and money you loot, at their own spot ("loot",
-- Spots.lua), from the game's own loot chat messages, read with its own message templates so any language works.
--
-- CHAT_MSG_LOOT / CHAT_MSG_MONEY (ChatInfoDocumentation.lua): the text isn't marked NeverSecret, so
-- the game may hide it (then the message is skipped). Whether and when it
-- does on Forever isn't known yet: each message is logged as readable or hidden while /fft debug
-- records, and a hidden one is skipped.
-- Templates (Ketho's BlizzardInterfaceResources, forever branch, GlobalStrings): LOOT_ITEM_SELF
-- "You receive loot: %s", _MULTIPLE "...: %sx%d", LOOT_ITEM_PUSHED_SELF(_MULTIPLE) "You receive
-- item: ..." (quest rewards and the like), LOOT_ITEM_CREATED_SELF "You create: %s." (skipped),
-- YOU_LOOT_MONEY "You loot %s", YOU_LOOT_MONEY_MOD "You loot %s (+%s)",
-- LOOT_MONEY_SPLIT "Your share of the loot is %s.", the money in it as GOLD_AMOUNT "%d Gold" etc.

local ADDON, ns = ...
local FFT = ns.FFT
local IsSecret, Log = ns.IsSecret, ns.Log

-- A template as a pattern: %s (or %1$s) is any text, %d (or %1$d) a number; everything else literal
local function ToPattern(template)
    if type(template) ~= "string" then return nil end
    local p = template:gsub("%%%d?%$?s", "\001"):gsub("%%%d?%$?d", "\002")
    p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    p = p:gsub("\001", "(.-)"):gsub("\002", "(%%d+)")
    return "^" .. p .. "$"
end
ns.ToPattern = ToPattern -- (1.31.0) Notices.lua reads the game's other chat messages the same way

-- in the order to try them: the longer forms first ("x%d", "(+%s)"), as "%s" alone takes them too
local ITEM_TEMPLATES = {"LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF",
    "LOOT_ITEM_PUSHED_SELF"}
local CREATED_TEMPLATES = {"LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF"}
local MONEY_TEMPLATES = {"YOU_LOOT_MONEY_MOD", "YOU_LOOT_MONEY", "LOOT_MONEY_SPLIT"}
local COIN = {{"GOLD_AMOUNT", 10000}, {"SILVER_AMOUNT", 100}, {"COPPER_AMOUNT", 1}}

local patterns -- name -> pattern, made at first use (the game's strings are there by then)
local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for _, list in ipairs({ITEM_TEMPLATES, CREATED_TEMPLATES, MONEY_TEMPLATES}) do
        for _, name in ipairs(list) do patterns[name] = ToPattern(_G[name]) end
    end
    for _, c in ipairs(COIN) do
        local t = _G[c[1]]
        patterns[c[1]] = type(t) == "string" and t:gsub("%%d", "(%%d+)") or nil
    end
    return patterns
end

-- The captures of the first template that matches, and its name
local function MatchAny(text, names)
    local p = Patterns()
    for _, name in ipairs(names) do
        if p[name] then
            local caps = {text:match(p[name])}
            if caps[1] then return caps, name end
        end
    end
end

-- A money text ("1 Gold, 23 Silver, 45 Copper") in copper, or nil
local function Copper(text)
    local p, total, any = Patterns(), 0, false
    for _, c in ipairs(COIN) do
        local n = p[c[1]] and text:match(p[c[1]])
        if n then total, any = total + tonumber(n) * c[2], true end
    end
    return any and total or nil
end

local function Show(text, color)
    local db = FFT.db
    -- (1.31.0) a repeat within a second merges ("+[Linen Cloth] x2" twice: "... x2 x2"), Spots.lua
    FFT:SpotText("loot", text, color or {1, 1, 1}, db.lootFont, db.lootOutline, db.lootSize)
end

-- an item's quality: from the game's item info, else from its link's color; nil if neither says
local function ItemInfo(link)
    if not (C_Item and C_Item.GetItemInfo) then return false end
    return pcall(C_Item.GetItemInfo, link)
end
-- (1.30.1) A link's color may be a quality token, "|cnIQ2:" (ColorManager.lua,
-- GetFormattedStringForItemQuality: "Named color token specifically for Item Qualities"), not
-- "|cffrrggbb". The author's 2026-11-11 08:15 log, 1119.332: a green item, quality 2 by
-- GetItemInfo, shown white by 1.30.0, which only read the "|cffrrggbb" form.
local function LinkColor(link)
    return link:match("^|c(%x%x%x%x%x%x%x%x)") and "hex" or link:match("^|cnIQ(%d+):") and "IQ"
        or link:match("^(|cn[^:]*:)") and "named" or "none"
end
local function Quality(link)
    local ok, _, _, quality = ItemInfo(link)
    if ok and type(quality) == "number" then return quality end
    local iq = link:match("^|cnIQ(%d+):")
    if iq then return tonumber(iq) end
    local color = link:match("|c(%x%x%x%x%x%x%x%x)")
    for q, c in pairs(ITEM_QUALITY_COLORS or {}) do
        if color and c.hex and c.hex:lower():find(color:lower(), 1, true) then return q end
    end
end
-- the color to draw a quality in: the game's own (ITEM_QUALITY_COLORS, "|cffrrggbb", with its color
-- overrides; ColorManager.lua), else the link's own color, else white
local function QualityColor(quality, link)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c and type(c.hex) == "string" and c.hex:match("^|c%x%x%x%x%x%x%x%x$") then return c.hex end
    return link:match("^(|c%x%x%x%x%x%x%x%x)") or link:match("^(|cn[^:|]*:)") or "|cffffffff"
end
local function IsQuestItem(link)
    local ok, _, _, _, _, _, _, _, _, _, _, _, classID = ItemInfo(link)
    local quest = Enum and Enum.ItemClass and Enum.ItemClass.Questitem
    return ok and quest ~= nil and classID == quest
end

function FFT:OnLootMessage(event, text)
    local db = self.db
    if not (db and db.enabled and db.showLoot) then return end
    if event == "CHAT_MSG_MONEY" and not db.showMoney then return end
    if IsSecret(text) then
        Log("loot message (%s): hidden, skipped", event)
        return
    end
    if type(text) ~= "string" then return end
    if event == "CHAT_MSG_MONEY" then
        local caps, name = MatchAny(text, MONEY_TEMPLATES)
        local copper = 0
        for _, part in ipairs(caps or {}) do copper = copper + (Copper(part) or 0) end
        Log("loot message (money): readable, %s, %d copper", name or "no template matched", copper)
        if copper > 0 then
            Show("+" .. (GetMoneyString and GetMoneyString(copper) or (copper .. "c")))
        end
        return
    end
    -- items: not your own crafting, nor someone else's loot (their templates aren't these)
    if MatchAny(text, CREATED_TEMPLATES) then return Log("loot message (item): readable, created, not shown") end
    local caps, name = MatchAny(text, ITEM_TEMPLATES)
    if not caps then return Log("loot message (item): readable, not yours or no template matched") end
    local link, count
    for _, c in ipairs(caps) do
        if c:find("|H", 1, true) then link = c elseif c:match("^%d+$") then count = tonumber(c) end
    end
    if not link then return Log("loot message (item): readable, %s, no item link", name) end
    local quality = Quality(link)
    local shown = IsQuestItem(link) or quality == nil or quality >= (tonumber(db.lootMinQuality) or 1)
    Log("loot message (item): readable, %s, quality %s, link color %s, x%d, %s", name, tostring(quality),
        LinkColor(link), count or 1, shown and "shown" or "below the lowest quality shown")
    if not shown then return end
    local itemName = link:match("%[(.-)%]") or "?"
    local color = QualityColor(quality, link)
    Show(("+%s[%s]|r%s"):format(color, itemName, (count and count > 1) and (" x" .. count) or ""))
end

-- (1.31.0) for Notices.lua: currency you receive shows with your loot
FFT.ShowLootText = function(text, color) Show(text, color) end

function FFT:TestLoot()
    C_Timer.After(0.2, function() Show("+|cff1eff00[Sample Ring]|r") end)
    C_Timer.After(0.6, function() Show("+|cffffffff[Linen Cloth]|r x2") end)
    if self.db.showMoney then
        C_Timer.After(1.0, function() Show("+" .. (GetMoneyString and GetMoneyString(12345) or "1g 23s 45c")) end)
    end
    if self.db.showExperience then C_Timer.After(1.4, function() Show("+120 " .. (XP or "XP"), FFT.Color("colorExperience")) end) end
    if self.db.showReputation then C_Timer.After(1.8, function() Show("+25 Stormwind", FFT.Color("colorReputation")) end) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("CHAT_MSG_MONEY")
events:SetScript("OnEvent", function(_, event, text) FFT:OnLootMessage(event, text) end)
