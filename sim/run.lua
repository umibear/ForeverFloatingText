-- Runs the raid simulator outside the browser, the same as sim.html (the same counts: its random
-- numbers are exact in any Lua since 1.28.1). From the addon's folder, with Lua 5.3:
--   lua5.3 sim/run.lua [others] [seed]   one fight, its report
--   lua5.3 sim/run.lua --check            CI: every fight in sim/baseline.lua must give exactly
--                                         its counts, and solo must show >= 98% and nothing wrong
--   lua5.3 sim/run.lua --update           print a new sim/baseline.lua (after a change that is
--                                         meant to change the counts; commit it with the change)

local READ = READ_FILE or function(path)
    local f = assert(io.open(path, "rb"), "can't open " .. path .. " (run from the addon's folder)")
    local text = f:read("*a")
    f:close()
    return text
end
local print = print -- the fake game's print (wowstub.lua) keeps the addon's chat messages instead

local function Fight(others, seed)
    ForeverFloatingTextDB, ForeverFloatingTextLog = nil, nil -- nothing carries over from the last fight
    for _, name in ipairs({"Core.lua", "Spots.lua", "Heals.lua", "Incoming.lua", "Alerts.lua", "Procs.lua"}) do
        _G["SRC_" .. name:gsub("%W", "_")] = READ(name)
    end
    SRC_wowstub_lua = READ("sim/wowstub.lua")
    SRC_scenario_lua = READ("sim/scenario.lua")
    SIM_CONFIG_SRC = ("return {others = %d, duration = 300, seed = %d, details = false, swingDelay = {0.449, 0.468}, patches = {}}")
        :format(others, seed)
    assert(load(SRC_wowstub_lua, "@wowstub.lua"))()
    local ok, report = xpcall(assert(load(SRC_scenario_lua, "@scenario.lua")), debug.traceback)
    if not ok then return nil, "ERROR " .. tostring(report) end
    if #SIM.errors > 0 then return report, ("%d Lua errors in the fight, the first: %s"):format(#SIM.errors, SIM.errors[1]) end
    return report
end

-- the counts of a report: your hits, shown, missed, others' shown as yours
local function Counts(report)
    local yours, shown, missed, wrong = report:match("your hits (%d+), shown (%d+) %([%d.]+%%%), missed (%d+), others' shown as yours (%d+)")
    if not yours then return nil end
    return {yours = tonumber(yours), shown = tonumber(shown), missed = tonumber(missed), wrong = tonumber(wrong)}
end

local args = arg or {}
local mode = args[1]
local status = 0

if mode == "--check" or mode == "--update" then
    local base = assert(load(READ("sim/baseline.lua"), "@baseline.lua"))()
    local lines = {}
    for _, run in ipairs(base.runs) do
        local report, err = Fight(run.others, run.seed)
        local c = report and Counts(report)
        local summary = report and report:match("^[^\n]+") or "?"
        if err or not c then
            print("FAIL  " .. (err or ("couldn't read the report: " .. tostring(report))))
            status = 1
        elseif mode == "--update" then
            lines[#lines + 1] = ("    {others = %d, seed = %d, yours = %d, shown = %d, missed = %d, wrong = %d},")
                :format(run.others, run.seed, c.yours, c.shown, c.missed, c.wrong)
        else
            local same = c.yours == run.yours and c.shown == run.shown and c.missed == run.missed and c.wrong == run.wrong
            print((same and "ok    " or "FAIL  ") .. summary)
            if not same then
                print(("      the baseline says: your hits %d, shown %d, missed %d, others' shown as yours %d")
                    :format(run.yours, run.shown, run.missed, run.wrong))
                status = 1
            end
            if run.others == 0 and (c.shown < 0.98 * c.yours or c.wrong > 0) then
                print("FAIL  solo must show at least 98% of your hits and none of anyone else's")
                status = 1
            end
        end
    end
    if mode == "--update" then
        print("-- Exact simulator counts (sim/run.lua --check). Update with sim/run.lua --update only when")
        print("-- a change is meant to change them, and commit it with that change.")
        print("return {runs = {")
        for _, l in ipairs(lines) do print(l) end
        print("}}")
    elseif status == 0 then
        print("baseline: all counts the same")
    end
else
    local report, err = Fight(tonumber(args[1]) or 0, tonumber(args[2]) or 1)
    if report then print(report) end
    if err then print(err); status = 1 end
end
if status ~= 0 and os and os.exit then os.exit(status) end
return status
