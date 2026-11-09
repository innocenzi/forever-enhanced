-- Nearby Quests: ranking, scopes, manual tracks, dismissals, combat, lifecycle.
-- Distances are in yards. An evaluation runs on the frame after a request, and
-- the ticker requests one every 2 seconds.

local TICK_SECONDS = 2

local function Set(world, key, value)
    world:Setting("quests.nearby." .. key):SetValue(value)
end

-- Five quests at 100, 300, 200, 50 and 400 yards; quest 5 is watched.
local function WithQuests(world)
    world:SetQuests({
        { questID = 1, distance = 100 },
        { questID = 2, distance = 300 },
        { questID = 3, distance = 200 },
        { questID = 4, distance = 50 },
        { questID = 5, distance = 400 },
    })
    world.watches = { 5 }
end

local function Pins(world)
    return world.env.ForeverEnhancedCharacterDB.quests.nearby.pins
end

test("tracks the closest quests and untracks the farthest", function(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    equal(world:Watched(), "1 4", "watched")
    expect(world.questSorts > 0, "tracker re-sorted")

    world:MoveTo({ [2] = 10, [3] = 20 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "2 3", "watched after moving")
end)

test("does nothing when the tracked quests are already the right ones", function(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    local sorts = world.questSorts
    world:Elapse(TICK_SECONDS)
    equal(world.questSorts, sorts, "tracker sorts")
end)

test("within range, tracks only quests closer than the distance", function(world)
    WithQuests(world)
    Set(world, "scope", "range")
    Set(world, "range", 150)
    world:NextFrame()
    equal(world:Watched(), "1 4", "watched")

    Set(world, "count", 1)
    world:NextFrame()
    equal(world:Watched(), "4", "capped by the count")
end)

test("in the current zone, tracks only quests on the player's map", function(world)
    WithQuests(world)
    world.questLog[2].onMap = true
    world.questLog[5].onMap = true
    Set(world, "scope", "zone")
    world:NextFrame()
    equal(world:Watched(), "2 5", "watched")
end)

test("ignores quests that can't be tracked or have no location", function(world)
    world:SetQuests({
        { isHeader = true },
        { questID = 1, distance = 10, isTask = true },
        { questID = 2, distance = 10, isBounty = true },
        { questID = 3, distance = 10, isWorldQuest = true },
        { questID = 4, distance = 10, isHidden = true },
        { questID = 5, distance = 10, offContinent = true },
        { questID = 6 },
        { questID = 7, distance = 500 },
    })
    world:NextFrame()
    equal(world:Watched(), "7", "watched")
end)

test("leaves the tracker alone when no quest has a location", function(world)
    WithQuests(world)
    for _, quest in ipairs(world.questLog) do
        quest.distance = nil
    end
    world:NextFrame()
    equal(world:Watched(), "5", "watched")
end)

test("untracks everything when no quest is within range", function(world)
    WithQuests(world)
    Set(world, "scope", "range")
    Set(world, "range", 100)
    world:MoveTo({ [1] = 1000, [4] = 1000 })
    world:NextFrame()
    equal(world:Watched(), "", "watched")
end)

test("a tracked quest isn't replaced by one only slightly closer", function(world)
    world:SetQuests({ { questID = 1, distance = 100 }, { questID = 2, distance = 120 } })
    Set(world, "count", 1)
    world:NextFrame()
    equal(world:Watched(), "1", "closest tracked")

    world:MoveTo({ [1] = 100, [2] = 90 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1", "kept when the other is slightly closer")

    world:MoveTo({ [2] = 80 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "2", "replaced when the other is clearly closer")
end)

test("never untracks the super-tracked quest", function(world)
    WithQuests(world)
    world.superTracked = 5
    Set(world, "count", 1)
    world:NextFrame()
    equal(world:Watched(), "4 5", "watched")
end)

test("untracks far quests the player tracked, by default", function(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:TrackQuest(2)
    world:NextFrame()
    equal(world:Watched(), "1 4", "watched")
end)

test("keeps quests the player tracked when asked to, across sessions", function(world)
    WithQuests(world)
    Set(world, "keepManual", true)
    Set(world, "count", 2)
    world:NextFrame()
    equal(world:Watched(), "1 4", "quest 5 wasn't tracked by the player in this session")

    world:TrackQuest(2)
    world:NextFrame()
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1 2 4", "manual track kept")
    equal(Pins(world)[2], true, "pin saved per character")

    world:UntrackQuest(2)
    world:NextFrame()
    equal(Pins(world)[2], nil, "pin dropped when untracked")
end)

test("a quest Blizzard watches on accept isn't kept as a manual track", function(world)
    WithQuests(world)
    Set(world, "keepManual", true)
    Set(world, "count", 2)
    world:NextFrame()
    world:AcceptQuest({ questID = 6, distance = 1000 })
    world:NextFrame()
    equal(world:Watched(), "1 4", "far new quest untracked")
    equal(Pins(world)[6], nil, "not pinned")
end)

test("a quest the player untracks stays out until they change zone", function(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:UntrackQuest(4)
    world:NextFrame()
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1 3", "dismissed quest stays out, the next one fills in")

    world:Fire("ZONE_CHANGED_NEW_AREA")
    world:NextFrame()
    equal(world:Watched(), "1 4", "back after a zone change")
end)

test("tracking a dismissed quest again brings it back", function(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:UntrackQuest(4)
    world:NextFrame()
    world:TrackQuest(4)
    world:NextFrame()
    equal(world:Watched(), "1 4", "watched")
end)

test("waits for the end of combat to change the tracker", function(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world.inCombat = true
    world:MoveTo({ [2] = 10 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1 4", "unchanged in combat")

    world.inCombat = false
    world:Fire("PLAYER_REGEN_ENABLED")
    world:NextFrame()
    equal(world:Watched(), "2 4", "updated after combat")
end)

test("turning the feature off stops updates and leaves the tracker as it is", function(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:Setting("quests.nearby.enabled"):SetValue(false)
    world:MoveTo({ [2] = 10, [3] = 20 })
    world:Elapse(TICK_SECONDS)
    world:TrackQuest(5)
    world:NextFrame()
    equal(world:Watched(), "1 4 5", "untouched while off")

    world:Setting("quests.nearby.enabled"):SetValue(true)
    world:NextFrame()
    equal(world:Watched(), "2 3", "updated when back on")
end)
