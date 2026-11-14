-- Replays a recorded /fft debug log through the real addon code (1.26.3).
-- Set before loading: SRC_wowstub_lua, SRC_<addon file>_lua (as sim.html does), SRC_log (a saved
-- ForeverFloatingText.lua or a copy in sim/logs), REPLAY_FROM (text of the "=== recording started ..."
-- line to start at, or nil for the first). Returns a report: each hit on a mob and what the addon
-- decides now, and the counts then (from the log) and now.
-- What is replayed: PLAYER_SWING (with Ghost Wolf form), your Combat Log lines (by their colors),
-- your casts, UNIT_COMBAT on mobs and on you, fights starting. Not replayed: totem nameplates
-- (their casts still show as cast lines), heals, the combat text feed.

assert(load(SRC_wowstub_lua, "@wowstub.lua"))()
function hooksecurefunc() end
-- (1.28.14) recorded events keep their own times: two with one timestamp were one frame in game,
-- two 0.010 s apart were not (put on the 1/60 s grid they could fall into one, and a line then
-- looked as if it came in a hit's own frame). Timers still fire on the grid.
function SIM.FrameOf(t) return t end

local env = {}
assert(load(SRC_log, "@log", "t", env))()
-- logs recorded before the rename (1.27.0) use the addon's old name, OwnCombatText
local all = (env.ForeverFloatingTextLog or env.OwnCombatTextLog).lines
local first, last
for i, l in ipairs(all) do
    if l:find("^=== recording") then
        if first and not last then last = i - 1 end
        if not first and (not REPLAY_FROM or l:find(REPLAY_FROM, 1, true)) then first = i end
    end
end
assert(first, "recording not found")
last = last or #all
-- (1.28.11) solo or in a group, as the recording's first line says (some rules are for solo only);
-- REPLAY_FPS (optional): the frame rate it was recorded at, when not a high one (frames of 1/60 s
-- otherwise)
SIM.inGroup = all[first]:find("in group: true", 1, true) ~= nil
-- (1.30.7) a raid when the line says so (logs from 1.30.7); the older group logs were parties
SIM.inRaid = all[first]:find("raid: true", 1, true) ~= nil
-- (1.30.5) the class the recording was made on (the logs don't say): REPLAY_CLASS, else a shaman's
-- (all but the 2026-11-10 21:15 hunter's); some rules are for one class (SWING_QUICK.MarkExtra)
function UnitClass() local c = REPLAY_CLASS or "SHAMAN"; return c, c, 0 end
if REPLAY_FPS then
    SIM.FRAME = 1 / REPLAY_FPS
    function GetFramerate() return REPLAY_FPS end
end

local form
function GetShapeshiftFormID() return form end
-- the player's own settings, saved with the log (misses on or off change what lines are used up)
ForeverFloatingTextDB = env.ForeverFloatingTextDB or env.OwnCombatTextDB or {}
local ns = {}
for _, n in ipairs({"Core_lua", "Filter_lua", "GameSettings_lua", "Spots_lua", "Heals_lua", "Incoming_lua", "Alerts_lua", "Procs_lua"}) do
    assert(load(_G["SRC_" .. n], "@" .. n))("ForeverFloatingText", ns)
end
local FFT = ns.FFT
SIM.units.player = {guid = "Player-1-0001", name = "You"}

-- spells by name (harmful ones are logged by name only)
local ids, nextId = {}, 900000
local function SpellId(name, id, harmful, helpful)
    if id then
        SIM.spells[id] = SIM.spells[id] or {name = name, harmful = harmful, helpful = helpful}
        return id
    end
    if not ids[name] then
        nextId = nextId + 1
        ids[name] = nextId
        SIM.spells[nextId] = {name = name, harmful = harmful, helpful = helpful}
    end
    return ids[name]
end

local seenPlates = {}
local plateN = 0
-- a mob's plate; nameplate tokens are reused, so one that was your totem's becomes a mob's again
-- (a logged hit is always on an enemy: the addon logs only those)
local function Plate(unit)
    local u = SIM.units[unit]
    if seenPlates[unit] and not (u and u.owned) then return end
    if seenPlates[unit] then SIM.Fire("NAME_PLATE_UNIT_REMOVED", unit) end
    seenPlates[unit] = true
    plateN = plateN + 1
    SIM.AddUnit(unit, {guid = "Creature-0-1-1-1-1-" .. plateN, name = unit, enemy = true})
    SIM.Fire("NAME_PLATE_UNIT_ADDED", unit)
end

-- (1.28.0) your totems' nameplates and their attacks ("your minion nameplate3: Searing Totem II",
-- "your minion nameplate3 cast ... (id 6350, ...)"): without them some totem hits were dropped
-- that the game showed (2026-11-09 14:12 log: 86 replayed, 93 in game)
function UnitIsOwnerOrControllerOfUnit(_, unit)
    local u = SIM.units[unit]
    return u ~= nil and u.owned == true
end
local function Minion(unit, name)
    if seenPlates[unit] then SIM.Fire("NAME_PLATE_UNIT_REMOVED", unit) end
    seenPlates[unit] = true
    plateN = plateN + 1
    SIM.AddUnit(unit, {guid = "Creature-0-1-1-1-1-minion-" .. plateN, name = name, enemy = false, owned = true})
    SIM.Fire("NAME_PLATE_UNIT_ADDED", unit)
end

-- The game knows your spells at login; here a spell was only added when its cast replayed, so
-- CleanLearned took every learned spell for "not an attack" and removed its school and DoT rhythm
-- before the replay began. The author's 2026-11-13 10:28 dungeon log: "Lightning Bolt" lost its
-- school, and all 31 instant Lightning Bolts the game showed ("while your Lightning Bolt was on its
-- way") were dropped in the replay, their lines then read as Windfury procs.
for _, key in ipairs({"spellSchools", "dotPeriods"}) do
    for name in pairs(ForeverFloatingTextDB[key] or {}) do
        if type(name) == "string" then SpellId(name, nil, true, false) end
    end
end
SIM.Fire("ADDON_LOADED", "ForeverFloatingText")
FFT:WriteOwnClogFilter()
SIM.Fire("PLAYER_LOGIN")
SlashCmdList.FOREVERFLOATINGTEXT("debug")
SIM.target = "nameplate1"

-- Casts the game triggers (item and talent procs) come with no UNIT_SPELLCAST_SENT. Logs from
-- 1.28.0 say which ("your cast X came with no UNIT_SPELLCAST_SENT"); for older ones, these:
-- "Fireball" in the swing's frame didn't delay the swing (2026-11-09 09:59 log), a proc.
local triggered = {Fireball = true}
-- Each cast by its own log line, not by its name: in the 2026-11-13 10:28 log one Lightning Bolt of
-- 39 came with no SENT (182621.496), and all 39 replayed as triggered. The "came with no" line comes
-- just before its cast's line, with the same timestamp.
local noSentAt = {} -- spell name -> the timestamp of its last "came with no" line

-- (1.28.14) the recording's own time of each replayed hit, by its nameplate and replay time: the
-- "DEC" lines at the end of the report say what was decided for each (to compare with the game's
-- combat log file, which says whose each hit was)
local origOf = {}
local t0, lastAt = nil, 0
local before = {show = 0, drop = 0, hits = 0}
local castN = 0
for i = first + 1, last do
    local l = all[i]
    local ts, rest = l:match("^(%d+%.%d+) (.*)$")
    if ts then
        local t = tonumber(ts)
        t0 = t0 or (t - 3)
        local at = t - t0
        local function At(fn) SIM.At(at, fn); lastAt = at end
        if rest:find("^  show ") then before.show = before.show + 1
        elseif rest:find("^  drop ") then before.drop = before.drop + 1 end
        local mUnit, mName = rest:match("^your minion (nameplate%d+): (.+)$")
        if mUnit then At(function() Minion(mUnit, mName) end) end
        local cUnit, cName, cId = rest:match("^your minion (nameplate%d+) cast (.-) %(id (%d+)")
        if cUnit then
            local id = tonumber(cId)
            SIM.spells[id] = SIM.spells[id] or {name = cName:match("'s (.+)$") or cName, harmful = true}
            At(function()
                local u = SIM.units[cUnit]
                if not (u and u.owned) then Minion(cUnit, "totem") end
                castN = castN + 1
                SIM.Fire("UNIT_SPELLCAST_SUCCEEDED", cUnit, "Cast-3-0-0-" .. id .. "-" .. castN, id)
            end)
        end
        local unitThreat = rest:match("^  (nameplate%d+) threat hidden")
        if unitThreat then At(function() Plate(unitThreat); SIM.target = unitThreat end) end
        -- "your swing (0, weapon 2.54s...)"; logs before 1.23.4 say just "your swing (0)"
        local swType, speed = rest:match("^your swing %((%d), weapon ([%d.]+)s")
        if not swType then swType = rest:match("^your swing %((%d)%)"); speed = swType and "3.30" end
        if swType then
            local f = rest:find("form 16") and 16 or nil
            -- (1.28.0) logs name the mob swung at ("at nameplate3"); older ones don't
            local atUnit = rest:match("at (nameplate%d+)%)")
            At(function()
                if atUnit then Plate(atUnit); SIM.target = atUnit end
                form = f; SIM.Fire("PLAYER_SWING", tonumber(speed), tonumber(swType)); form = nil
            end)
        end
        local r, g, b = rest:match("^your Combat Log line: %S+ %(([%d.]+) ([%d.]+) ([%d.]+), order")
        if r then
            At(function()
                SIM.Fire("COMBAT_LOG_MESSAGE", SIM.Secret("a line"), tonumber(r), tonumber(g), tonumber(b),
                    Enum.CombatLogMessageOrder.Newest)
            end)
        end
        local noSent = rest:match("^your cast (.-) came with no UNIT_SPELLCAST_SENT")
        if noSent then noSentAt[noSent] = ts end
        local id, castName, castAt
        local plainName, plainId = rest:match("^your cast (.-) %(id (%d+), not")
        if plainName then
            id, castName = SpellId(plainName, tonumber(plainId), false, false), plainName
        elseif not rest:find("came with no UNIT_SPELLCAST_SENT", 1, true) then
            local harmName = rest:match("^your cast (.+)$")
            if harmName then
                -- (1.28.0) "your cast Stormstrike at nameplate3"
                local n, u = harmName:match("^(.-) at (nameplate%d+)$")
                if n then harmName, castAt = n, u end
                id, castName = SpellId(harmName, nil, true, false), harmName
            end
            local helpName = rest:match("^cast (.-) on ")
            if helpName then id, castName = SpellId(helpName, nil, false, true), helpName end
        end
        if id then
            local sent = not (triggered[castName] or noSentAt[castName] == ts)
            At(function()
                if castAt then Plate(castAt); SIM.target = castAt end
                castN = castN + 1
                local guid = "Cast-3-0-0-" .. id .. "-" .. castN
                if sent then SIM.Fire("UNIT_SPELLCAST_SENT", "player", "", guid, id) end
                SIM.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id)
            end)
        end
        -- (1.28.12) [%u_]: BLOCK_REDUCED hits weren't replayed, and their lines stayed unused
        local unit, action, flag, school = rest:match("^(nameplate%d+) (%u+) ([%u_]*) ?<secret> school (%d+)$")
        if unit then
            before.hits = before.hits + 1
            At(function()
                Plate(unit)
                local k = ("%s %.3f"):format(unit, GetTime())
                origOf[k] = origOf[k] or {}
                table.insert(origOf[k], ts)
                SIM.Fire("UNIT_COMBAT", unit, action, flag, SIM.Secret(action == "WOUND" and 100 or 0), tonumber(school))
            end)
        end
        local pAction, pFlag, pSchool = rest:match("^player (%u+) ([%u_]*) ?<secret> school (%d+)$")
        if pAction then
            At(function() SIM.Fire("UNIT_COMBAT", "player", pAction, pFlag, SIM.Secret(1), tonumber(pSchool)) end)
        end
        if rest:find("^fight starts") then
            At(function() SIM.inCombat = true; SIM.Fire("PLAYER_REGEN_DISABLED") end)
        end
    end
end
SIM.RunUntil(lastAt + 3)

local out, now = {}, {show = 0, drop = 0}
for _, l in ipairs(ForeverFloatingTextLog.lines) do
    if l:find("^%d+%.%d+ nameplate%d+ %u+") or l:find("^%d+%.%d+   show") or l:find("^%d+%.%d+   drop")
        or l:find("^%d+%.%d+ your swing") or l:find("^%d+%.%d+   swings at weapon") then -- (1.29.0) what's learned
        out[#out + 1] = l
    end
    if l:find("^%d+%.%d+   show") then now.show = now.show + 1 end
    if l:find("^%d+%.%d+   drop") then now.drop = now.drop + 1 end
end
if REPLAY_DECISIONS then
    for _, l in ipairs(ForeverFloatingTextLog.lines) do
        -- (1.31.25) the tag ends with the hit's school and kind ("1 CRITICAL"): a sixth column
        local dec, rest, key, kind = l:match("^%d+%.%d+   (%a+) (.-) %[(nameplate%d+ [%d.]+) ?([^%]]*)%]$")
        local orig = key and origOf[key] and table.remove(origOf[key], 1)
        if orig then out[#out + 1] = ("DEC\t%s\t%s\t%s\t%s\t%s"):format(dec, key:match("^%S+"), orig, rest, kind) end
    end
end
table.insert(out, 1, ("hits on mobs %d; in the log: shown %d, dropped %d; replayed now: shown %d, dropped %d")
    :format(before.hits, before.show, before.drop, now.show, now.drop))
for i = math.min(#SIM.errors, 5), 1, -1 do table.insert(out, 2, "ERROR " .. SIM.errors[i]) end
if #SIM.errors > 0 then table.insert(out, 2, ("%d errors in the replay"):format(#SIM.errors)) end
return table.concat(out, "\n")
