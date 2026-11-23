-- The debug addon (debug/): persistent log, taint watches, errors and blocked actions.

local function Entries(world, tag)
    local found = {}
    for _, entry in ipairs(world.debug:GetEntries()) do
        if entry.tag == tag then
            table.insert(found, entry)
        end
    end
    return found
end

local function Contains(text, part)
    return text:find(part, 1, true) ~= nil
end

test("keeps the log across sessions in its saved variables", function(world)
    equal(ForeverEnhancedDebugDB.session, 4, "session")
    world.debug:Log("debug.test", "a", { b = 1 })
    world.debug:Log("debug.test", "a", { b = 1 })

    local entries = ForeverEnhancedDebugDB.entries
    equal(#entries, 2, "entries")
    equal(entries[1].tag, "old", "previous session's entry kept")
    equal(entries[2].session, 4, "new entry's session")
    equal(entries[2].text, "a {b=1}", "values serialized")
    equal(entries[2].count, 2, "repeats counted")

    local all, current = world.debug:FormatLog(false), world.debug:FormatLog(true)
    expect(Contains(all, "== session 3,") and Contains(all, "== session 4,"), "a header per session")
    expect(Contains(all, "debug.test: a {b=1} (x2)"), "repeats shown")
    expect(not Contains(current, "old"), "this session only")
end, {
    debugSavedVariables = function()
        return {
            session = 3,
            dropped = 0,
            entries = {
                { session = 3, date = 1700000000, time = 12, combat = false, tag = "old", text = "x", count = 1 },
            },
        }
    end,
})

test("drops the oldest entries past the cap", function(world)
    for index = 1, 5001 do
        world.debug:Log("debug.test", index)
    end
    local entries = world.debug:GetEntries()
    equal(#entries, 5000, "entries")
    equal(entries[1].text, "2", "oldest dropped")
    equal(ForeverEnhancedDebugDB.dropped, 1, "dropped count")
end)

test("logs a tainted tracker field once, with the events before it", function(world)
    world:Fire("QUEST_ACCEPTED", 123)
    QuestObjectiveTracker.wasDisplayedLastLayout = true
    world:Taint(QuestObjectiveTracker, "wasDisplayedLastLayout")
    world:RunFrames(1)
    world:RunFrames(1)

    local incidents = Entries(world, "taint.objectiveTracker")
    equal(#incidents, 1, "incidents")
    local text = incidents[1].text
    expect(Contains(text, "QuestObjectiveTracker.wasDisplayedLastLayout (ForeverEnhanced)"), "field and culprit")
    expect(Contains(text, "QUEST_ACCEPTED 123"), "events before it")
    expect(Contains(text, "zone=Elwynn Forest"), "context")
    equal(#world.prints, 0, "not announced in chat")
end)

test("announces incidents in chat once turned on with /fedebug chat", function(world)
    expect(world:Chat("/fedebug chat"), "command known")
    expect(ForeverEnhancedDebugDB.announce, "saved")
    world:Fire("ADDON_ACTION_BLOCKED", "ForeverEnhanced", "CastSpellByName")
    expect(Contains(world.prints[#world.prints], "/fedebug"), "announced in chat")

    world:Chat("/fedebug chat")
    local printed = #world.prints
    world:Fire("ADDON_ACTION_BLOCKED", "ForeverEnhanced", "UseContainerItem")
    equal(#world.prints, printed, "turned off again")
    equal(#Entries(world, "blocked"), 2, "both logged")
end)

test("logs the stack of tainted code marking the tracker dirty", function(world)
    world:Taint(ObjectiveTrackerFrame, "dirty")
    QuestObjectiveTracker:MarkDirty()
    world:RunFrames(1)

    local incidents = Entries(world, "taint.objectiveTracker")
    equal(#incidents, 1, "incidents (the scan doesn't log it again)")
    expect(
        Contains(incidents[1].text, "ObjectiveTrackerFrame.dirty tainted by ForeverEnhanced (after MarkDirty)"),
        "field"
    )
    expect(Contains(incidents[1].text, "[fake stack]"), "stack")
end)

test("watches Blizzard's UI panels, not ours", function(world)
    UIPanelWindows.ForeverEnhancedTestFrame = { area = "left" }
    world:Taint(UIPanelWindows, "ForeverEnhancedTestFrame")
    world:RunFrames(1)
    equal(#Entries(world, "taint.panelManager"), 0, "our panel ignored")

    UIPanelWindows.CharacterFrame = { area = "left" }
    world:Taint(UIPanelWindows.CharacterFrame, "area")
    world:RunFrames(1)
    equal(#Entries(world, "taint.panelManager"), 1, "Blizzard's panel")
end)

test("logs our errors caught by BugGrabber, once per message", function(world)
    local errors = {}
    world.env.BugGrabber = {
        GetDB = function()
            return errors
        end,
    }
    world:Fire("ADDON_LOADED", "!BugGrabber")
    local function Grab(message, stack)
        local err = { message = message, stack = stack }
        table.insert(errors, err)
        EventRegistry:TriggerEvent("BugGrabber.BugGrabbed", tostring(err))
    end

    Grab("Interface/AddOns/OtherAddon/file.lua:1: oops", "OtherAddon")
    Grab("GetAuraDataByIndex(): tainted by 'ForeverEnhanced'", "[Blizzard_MawBuffs]:4")
    Grab("GetAuraDataByIndex(): tainted by 'ForeverEnhanced'", "[Blizzard_MawBuffs]:4")

    local incidents = Entries(world, "error")
    equal(#incidents, 1, "incidents")
    expect(Contains(incidents[1].text, "Blizzard_MawBuffs"), "stack")
    equal(#Entries(world, "error.again"), 1, "repeat counted")
end)

test("logs our blocked actions", function(world)
    world:Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpellByName")
    world:Fire("ADDON_ACTION_BLOCKED", "ForeverEnhanced", "CastSpellByName")
    world:Fire("ADDON_ACTION_FORBIDDEN", "ForeverEnhanced", "UseContainerItem")

    local incidents = Entries(world, "blocked")
    equal(#incidents, 2, "incidents")
    expect(Contains(incidents[1].text, "blocked: CastSpellByName"), "blocked")
    expect(Contains(incidents[2].text, "forbidden: UseContainerItem"), "forbidden")
end)

-- The game shows the same message for them: logged apart, to tell who caused it.
test("logs other addons' and macros' blocked actions apart from ours", function(world)
    world:Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpellByName")
    world:Fire("ADDON_ACTION_BLOCKED", "OtherAddon", "CastSpellByName")
    world:Fire("MACRO_ACTION_BLOCKED", "TargetUnit")
    world:Fire("MACRO_ACTION_FORBIDDEN", "UseAction")

    local others = Entries(world, "blocked.other")
    equal(#others, 1, "other addons' incidents")
    expect(Contains(others[1].text, "blocked: CastSpellByName (OtherAddon)"), "culprit named")
    equal(#Entries(world, "blocked.other.again"), 1, "repeat counted")

    local macros = Entries(world, "blocked.macro")
    equal(#macros, 2, "macros' incidents")
    expect(Contains(macros[1].text, "blocked: TargetUnit (a macro)"), "blocked macro")
    expect(Contains(macros[2].text, "forbidden: UseAction (a macro)"), "forbidden macro")
    equal(#Entries(world, "blocked"), 0, "none of ours")
end)

-- The panel manager shows the blocked message with no event: its stack names the caller.
test("logs one blocked message per burst, whatever its callers", function(world)
    local calls = 0
    world.env.debugstack = function()
        calls = calls + 1
        return "[caller " .. calls .. "]"
    end
    world:EnterCombat()
    ShowUIPanel(CharacterFrame)
    ShowUIPanel(CharacterFrame)
    world:Elapse(2)
    ShowUIPanel(CharacterFrame)
    equal(#Entries(world, "blocked.message"), 1, "one incident for the burst")
    expect(Contains(Entries(world, "blocked.message")[1].text, "[caller 1]"), "first caller's stack")
    equal(Entries(world, "blocked.message.again")[1].count, 2, "repeats counted")

    world:Elapse(10)
    ShowUIPanel(CharacterFrame)
    equal(#Entries(world, "blocked.message"), 2, "a later burst logged again")
end)

test("exports the log as text at logout, for bun run debug-log", function(world)
    equal(ForeverEnhancedDebugDB.export, nil, "last export dropped at load")
    world.debug:Log("debug.test", "a")
    world:Fire("PLAYER_LOGOUT")

    local export = ForeverEnhancedDebugDB.export
    equal(export.session, world.debug:FormatLog(true), "this session")
    equal(export.all, world.debug:FormatLog(false), "every session")
    expect(Contains(export.all, "old") and not Contains(export.session, "old"), "sessions told apart")
end, {
    debugSavedVariables = function()
        return {
            session = 3,
            dropped = 0,
            export = { session = "stale", all = "stale" },
            entries = {
                { session = 3, date = 1700000000, time = 12, combat = false, tag = "old", text = "x", count = 1 },
            },
        }
    end,
})

test("runs probes after login, logging their errors", function(world)
    local ran = false
    world.debug:AtLogin("probe.test", function()
        ran = true
    end)
    world.debug:AtLogin("probe.test", function()
        error("broken probe")
    end)
    equal(ran, false, "not before the next frame")
    world:NextFrame()
    equal(ran, true, "ran")
    local logged = Entries(world, "probe.test")
    equal(#logged, 1, "error logged")
    expect(Contains(logged[1].text, "<probe failed:") and Contains(logged[1].text, "broken probe"), "error text")
end)

test("clears the log with /fedebug clear", function(world)
    world.debug:Log("debug.test", "a")
    expect(world:Chat("/fedebug clear"), "command known")
    equal(#Entries(world, "debug.test"), 0, "log cleared")
end)
