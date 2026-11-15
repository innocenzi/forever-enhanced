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
    expect(Contains(world.prints[#world.prints], "/fedebug"), "announced in chat")
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
