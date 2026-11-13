-- Forever Floating Text fixed spots on screen (1.30.0: four): your damage and healing when not over a nameplate, the damage you
-- take with resource gains, alerts, and loot; (1.31.0) procs, whose texts stay still while they last.
-- Each is an offset from the middle of the screen, set by dragging a box
-- ("Move" in the options, or /fft move) or with the sliders.

local ADDON, ns = ...
local FFT = ns.FFT
local Print = ns.Print

FFT.SPOTS = {
    -- (1.30.0) your damage when it isn't shown over nameplates (or your target has none)
    damage = {
        x = "damageX", y = "damageY", frameName = "ForeverFloatingTextDamageSpot",
        label = "Damage and healing: drag to move, right-click to lock all", bg = {0.5, 0.2, 0.7},
        help = "drag the purple frame to where your damage and healing should show; right-click it to lock all.",
        test = function() if FFT.TestDamageSpot then FFT:TestDamageSpot() end end,
    },
    incoming = {
        x = "incomingX", y = "incomingY", frameName = "ForeverFloatingTextIncomingSpot",
        label = "Incoming and resources: drag to move, right-click to lock all", bg = {0.7, 0.15, 0.15},
        help = "drag the red frame to where incoming damage and resource gains should show; right-click it to lock all.",
        test = function() if FFT.TestIncoming then FFT:TestIncoming() end end,
    },
    alerts = {
        x = "alertsX", y = "alertsY", frameName = "ForeverFloatingTextAlertSpot",
        label = "Alerts: drag to move, right-click to lock all", bg = {0.75, 0.6, 0.1},
        help = "drag the yellow frame to where alerts such as \"Overpower!\" should show; right-click it to lock all.",
        test = function() if FFT.TestAlerts then FFT:TestAlerts() end end,
    },
    buffs = { -- (1.31.0) buffs and debuffs gained and faded, apart from the alerts (Alerts.lua ShowBuff)
        x = "buffsX", y = "buffsY", frameName = "ForeverFloatingTextBuffSpot",
        label = "Buffs: drag to move, right-click to lock all", bg = {0.2, 0.45, 0.85},
        help = "drag the blue frame to where buffs gained and faded should show; right-click it to lock all.",
        test = function() if FFT.TestBuffs then FFT:TestBuffs() end end,
    },
    procs = { -- (1.31.0) procs kept still until used (Procs.lua): Stormstrike reset, the game's notices
        x = "procsX", y = "procsY", frameName = "ForeverFloatingTextProcSpot",
        label = "Procs: drag to move, right-click to lock all", bg = {0.15, 0.6, 0.2},
        help = "drag the green frame to where procs such as \"Maelstrom Ready!\" should stay; right-click it to lock all.",
        test = function() if FFT.TestProcs then FFT:TestProcs() end end,
    },
    loot = { -- (1.30.0) items and money you loot (Loot.lua); (1.31.0) and your gains
        x = "lootX", y = "lootY", frameName = "ForeverFloatingTextLootSpot",
        label = "Loot and gains: drag to move, right-click to lock all", bg = {0.1, 0.55, 0.55},
        help = "drag the teal frame to where your loot, experience, honor and reputation should show; right-click it to lock all.",
        test = function() if FFT.TestLoot then FFT:TestLoot() end end,
    },
}

-- ns.spotSettings[kind] = {x = setting, y = setting}, filled by the options so the sliders follow
ns.spotSettings = {}

-- The spot as a point for FFT:Show (opts.anchorX / anchorY)
function FFT:SpotAnchor(kind)
    local spot, db = self.SPOTS[kind], self.db
    return UIParent:GetWidth() / 2 + db[spot.x], UIParent:GetHeight() / 2 + db[spot.y]
end

local movers = {}
local function Round(v) return math.floor(v + 0.5) end

local function Place(kind)
    local x, y = FFT:SpotAnchor(kind)
    movers[kind]:ClearAllPoints()
    movers[kind]:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x, y)
end

-- Saves where the box was dropped, through the settings so the sliders follow
local function Save(kind)
    local mover, spot = movers[kind], FFT.SPOTS[kind]
    local cx, bottom = mover:GetCenter(), mover:GetBottom()
    if not cx or not bottom then return end
    local x = Round(cx - UIParent:GetWidth() / 2)
    local y = Round(bottom - UIParent:GetHeight() / 2)
    local s = ns.spotSettings[kind]
    if s then
        s.x:SetValue(x)
        s.y:SetValue(y)
    else
        FFT.db[spot.x], FFT.db[spot.y] = x, y
    end
    Place(kind)
    if kind == "procs" and FFT.LayoutProcs then FFT:LayoutProcs() end -- (1.31.0) its rows stay: move them too
end

local function Create(kind)
    local spot = FFT.SPOTS[kind]
    local mover = CreateFrame("Frame", spot.frameName, UIParent)
    mover:SetSize(240, 26)
    mover:SetFrameStrata("DIALOG") -- above the options window, so it can be dragged with it open
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(spot.bg[1], spot.bg[2], spot.bg[3], 0.6)
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(spot.label)
    mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Save(kind)
        spot.test()
    end)
    mover:SetScript("OnMouseUp", function(self, button)
        -- (1.31.0) right-click locks every box, not only this one (the author: no right-clicking
        -- each one)
        if button == "RightButton" then FFT:LockAllMovers() end
    end)
    movers[kind] = mover
    return mover
end

-- (1.31.0) While any box is out: a bar at the top of the screen with one button that locks them all
local lockBar
local function LockBar()
    if lockBar then return lockBar end
    lockBar = CreateFrame("Frame", "ForeverFloatingTextLockBar", UIParent)
    lockBar:SetSize(420, 34)
    lockBar:SetPoint("TOP", UIParent, "TOP", 0, -80)
    lockBar:SetFrameStrata("DIALOG")
    local bg = lockBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.75)
    local label = lockBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 12, 0)
    label:SetText("Forever Floating Text: drag the boxes")
    local button = CreateFrame("Button", nil, lockBar, "UIPanelButtonTemplate")
    button:SetSize(90, 22)
    button:SetPoint("RIGHT", -8, 0)
    button:SetText("Lock all")
    button:SetScript("OnClick", function() FFT:LockAllMovers() end)
    lockBar.button = button
    lockBar:Hide()
    return lockBar
end
local function UpdateLockBar()
    local any = false
    for _, m in pairs(movers) do if m:IsShown() then any = true end end
    if any then LockBar():Show() elseif lockBar then lockBar:Hide() end
end

-- show = true / false, or nil to flip; quiet: no line in chat (all boxes at once say one)
function FFT:ToggleMover(kind, show, quiet)
    local mover = movers[kind] or Create(kind)
    if show == nil then show = not mover:IsShown() end
    if show then
        Place(kind)
        mover:Show()
        if not quiet then Print(self.SPOTS[kind].help) end
    else
        mover:Hide()
    end
    UpdateLockBar()
end

function FFT:LockAllMovers()
    for _, m in pairs(movers) do m:Hide() end
    UpdateLockBar()
end
function FFT:MoversShown()
    for _, m in pairs(movers) do if m:IsShown() then return true end end
    return false
end

-- /fft move: all boxes at once (or all away); /fft lock: all away.
-- (1.31.5) UnlockAllMovers is also the options' "Move frames" button: always out, never a flip.
function FFT:UnlockAllMovers()
    for kind in pairs(self.SPOTS) do self:ToggleMover(kind, true, true) end
    Print("drag the boxes to where each kind of text should show. Lock them all with the Lock all button, "
        .. "a right-click on any box, or /fft lock.")
end
function FFT:ToggleAllMovers()
    if self:MoversShown() then return self:LockAllMovers() end
    self:UnlockAllMovers()
end

-- kept for older calls
function FFT:ToggleHealSpotMover() self:ToggleMover("damage") end

-- (1.31.0) An icon before a text ("|T<file>:0|t "), when "Show icons" is on and the icon is a plain file ID or path; else "".
-- C_Spell.GetSpellTexture / C_Item.GetItemIconByID have no secrecy flags (Forever's API docs).
function FFT.IconText(texture)
    local db = FFT.db
    if not (db and db.showIcons) then return "" end
    if ns.IsSecret(texture) or (type(texture) ~= "number" and type(texture) ~= "string") then return "" end
    return ("|T%s:0|t "):format(tostring(texture))
end
function FFT.SpellIconText(spell)
    if spell == nil or ns.IsSecret(spell) or not (C_Spell and C_Spell.GetSpellTexture) then return "" end
    local ok, texture = pcall(C_Spell.GetSpellTexture, spell)
    return ok and FFT.IconText(texture) or ""
end

-- (1.31.0) A text at a fixed spot, in that spot's font. The same plain text again at the same spot
-- within MERGE_WINDOW while the first is still up becomes "text x2", "x3". A text the game hides (fmt + args) can't be compared, so it's never merged.
-- (1.31.9) "Still the same text" is told by its use count (FFT:Show counts each use of a font string),
-- never by GetText: SetText / SetFormattedText with a hidden value make the font string's text a
-- secret aspect, and GetText then returns a hidden value for good, plain texts set later too
-- (SimpleFontStringAPIDocumentation: SecretArgumentsAddAspect, SecretReturnsForAspect Text). Texts
-- are reused, so a "Windfury!" in one that had shown a buff's hidden name failed in game
-- (2026-11-13 03:09: "attempt to compare a secret string value", 22 times since 2026-11-12).
local MERGE_WINDOW = 1.0
local merges = {} -- spot -> {text, at, fs, uses, n, shown}
function FFT:SpotText(kind, text, color, font, outline, size, fmt, args)
    local x, y = self:SpotAnchor(kind)
    local now = GetTime()
    local m = merges[kind]
    if text and not fmt and m and m.text == text and now - m.at <= MERGE_WINDOW and m.fs and m.fs:IsShown()
        and m.fs.uses == m.uses then
        m.n, m.at = m.n + 1, now
        m.shown = ("%s x%d"):format(text, m.n)
        m.fs:SetText(m.shown)
        return m.fs
    end
    local fs = self:Show(nil, text, color, false,
        {anchorX = x, anchorY = y, key = kind, font = font, outline = outline, size = size, fmt = fmt, args = args})
    merges[kind] = (text and not fmt and fs) and {text = text, at = now, fs = fs, uses = fs.uses, n = 1, shown = text} or nil
    return fs
end
