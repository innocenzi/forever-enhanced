-- Quest helpers, nearby quests: ranking, scopes, manual tracks, dismissals, combat, lifecycle.
-- Distances are in yards. An evaluation runs on the frame after a request, and
-- the ticker requests one every 2 seconds.

local TICK_SECONDS = 2

local function Enable(world)
    world:Setting("quests.helpers.nearby"):SetValue(true)
end

local function Set(world, key, value)
    world:Setting("quests.helpers." .. key):SetValue(value)
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
    return world.env.ForeverEnhancedCharacterDB.quests.helpers.pins
end

test("leaves the tracker alone until enabled", function(world)
    WithQuests(world)
    world:NextFrame()
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "5", "watched")
end)

test("tracks the closest quests and untracks the farthest", function(world)
    Enable(world)
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
    Enable(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    local sorts = world.questSorts
    world:Elapse(TICK_SECONDS)
    equal(world.questSorts, sorts, "tracker sorts")
end)

test("within range, tracks only quests closer than the distance", function(world)
    Enable(world)
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
    Enable(world)
    WithQuests(world)
    world.questLog[2].onMap = true
    world.questLog[5].onMap = true
    Set(world, "scope", "zone")
    world:NextFrame()
    equal(world:Watched(), "2 5", "watched")
end)

test("in the current zone, leaves the tracker alone while the map has no quest data", function(world)
    Enable(world)
    WithQuests(world)
    world.mapQuestsUnavailable = true
    Set(world, "scope", "zone")
    world:NextFrame()
    equal(world:Watched(), "5", "watched")

    world.mapQuestsUnavailable = nil
    world.questLog[2].onMap = true
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "2", "watched once the data is in")
end)

test("ignores quests that can't be tracked or have no location", function(world)
    Enable(world)
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

test("leaves out dungeon and raid quests outside instances when asked to", function(world)
    Enable(world)
    world:SetQuests({
        { questID = 1, distance = 10, tagID = Enum.QuestTag.Dungeon },
        { questID = 2, distance = 20, tagID = Enum.QuestTag.Raid },
        { questID = 3, distance = 30, tagID = Enum.QuestTag.Group },
        { questID = 4, distance = 40 },
    })
    world.watches = { 1 }
    Set(world, "count", 2)
    world:NextFrame()
    equal(world:Watched(), "1 2", "watched by default")

    Set(world, "dungeons", false)
    world:NextFrame()
    equal(world:Watched(), "3 4", "watched without dungeon quests")
end)

-- Inside the Deadmines (instance 36). Quest 1 has objectives on the instance's
-- map, quest 2 (untagged) sits under a header of its area, quest 3 belongs to
-- Wailing Caverns. Headers are matched by area, not by name: the client's
-- don't match the instance's ("La Prison" in the "Prison de Hurlevent"). No
-- quest has a distance here.
local function InDeadmines(world)
    world:SetQuests({
        { isHeader = true, title = "Westfall", areaID = 40 },
        { questID = 1, tagID = Enum.QuestTag.Dungeon, onMap = true },
        { questID = 4 },
        { isHeader = true, title = "Les Mortemines", areaID = 1581 },
        { questID = 2 },
        { isHeader = true, title = "Wailing Caverns", areaID = 718 },
        { questID = 3, tagID = Enum.QuestTag.Dungeon },
    })
    world.watches = { 4 }
    world:StandAt(0, 0, 0, 36)
    world:Fire("ZONE_CHANGED_NEW_AREA")
end

test("inside an instance, tracks its quests first", function(world)
    Enable(world)
    InDeadmines(world)
    world:NextFrame()
    equal(world:Watched(), "1 2", "watched inside the Deadmines")
end)

test("inside an instance, tracks only its dungeon quests when asked to", function(world)
    Enable(world)
    Set(world, "dungeons", false)
    InDeadmines(world)
    world:NextFrame()
    equal(world:Watched(), "1 2", "watched inside the Deadmines")

    world:StandAt(0, 0)
    world:MoveTo({ [1] = 10, [2] = 20, [3] = 30, [4] = 40 })
    world:Fire("ZONE_CHANGED_NEW_AREA")
    world:NextFrame()
    equal(world:Watched(), "2 4", "watched after leaving")
end)

test("inside an instance, tracks its quests in the current zone scope", function(world)
    Enable(world)
    Set(world, "scope", "zone")
    InDeadmines(world)
    world:NextFrame()
    equal(world:Watched(), "1 2", "watched inside the Deadmines")

    world.mapQuestsUnavailable = true
    world:Fire("ZONE_CHANGED_NEW_AREA")
    world:NextFrame()
    equal(world:Watched(), "2", "watched while the map has no quest data")
end)

test("inside an instance without a map, tracks the quests of its area", function(world)
    Enable(world)
    Set(world, "scope", "zone")
    world:SetQuests({
        { isHeader = true, title = "Hurlevent", areaID = 1519 },
        { questID = 1, distance = 10 },
        { isHeader = true, title = "La Prison", areaID = 717 },
        { questID = 2, tagID = Enum.QuestTag.Dungeon },
        { questID = 3, tagID = Enum.QuestTag.Dungeon },
    })
    world.watches = { 1 }
    world:StandAt(0, 0, 0, 34)
    world:Fire("ZONE_CHANGED_NEW_AREA")
    world:NextFrame()
    equal(world:Watched(), "2 3", "watched inside the Stockade")
end)

test("inside an instance, tracks the quests of its entrance's area", function(world)
    Enable(world)
    -- The quest log files Gnomeregan's quests under the Gnomeregan of Dun
    -- Morogh (133), not the instance's own area (721).
    world:SetQuests({
        { isHeader = true, title = "Dun Morogh", areaID = 1 },
        { questID = 1, distance = 10 },
        { isHeader = true, title = "Gnomeregan", areaID = 133 },
        { questID = 2, tagID = Enum.QuestTag.Dungeon },
    })
    world.watches = { 1 }
    world:StandAt(0, 0, 0, 90)
    world:Fire("ZONE_CHANGED_NEW_AREA")
    world:NextFrame()
    equal(world:Watched(), "2", "watched inside Gnomeregan")
end)

test("in the current zone, leaves the tracker alone while the client names the continent", function(world)
    Enable(world)
    WithQuests(world)
    for _, quest in ipairs(world.questLog) do
        quest.onMap = true
    end
    world.questLog[2].onMap = nil
    Set(world, "scope", "zone")
    world.onContinentMap = true
    world:NextFrame()
    equal(world:Watched(), "5", "watched on the continent's map")

    world.onContinentMap = nil
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1 3 4 5", "watched once the zone is known")
end)

test("leaves the tracker alone when no quest has a location", function(world)
    Enable(world)
    WithQuests(world)
    for _, quest in ipairs(world.questLog) do
        quest.distance = nil
    end
    world:NextFrame()
    equal(world:Watched(), "5", "watched")
end)

test("untracks everything when no quest is within range", function(world)
    Enable(world)
    WithQuests(world)
    Set(world, "scope", "range")
    Set(world, "range", 100)
    world:MoveTo({ [1] = 1000, [4] = 1000 })
    world:NextFrame()
    equal(world:Watched(), "", "watched")
end)

test("a tracked quest isn't replaced by one only slightly closer", function(world)
    Enable(world)
    world:SetQuests({ { questID = 1, distance = 100 }, { questID = 2, distance = 120 } })
    Set(world, "count", 1)
    world:NextFrame()
    equal(world:Watched(), "1", "closest tracked")

    world:MoveTo({ [1] = 100, [2] = 90 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1", "kept when the other is slightly closer")

    world:MoveTo({ [2] = 50 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "2", "replaced when the other is clearly closer")
end)

test("a tracked quest isn't replaced by one a few yards closer near objectives", function(world)
    Enable(world)
    world:SetQuests({ { questID = 1, distance = 0 }, { questID = 2, distance = 10 } })
    Set(world, "count", 1)
    world:NextFrame()
    equal(world:Watched(), "1", "closest tracked")

    world:MoveTo({ [1] = 15, [2] = 0 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1", "kept when the other is a few yards closer")
end)

test("never untracks the super-tracked quest", function(world)
    Enable(world)
    WithQuests(world)
    world.superTracked = 5
    Set(world, "count", 1)
    world:NextFrame()
    equal(world:Watched(), "4 5", "watched")
end)

test("leaves the tracker order to the game by default", function(world)
    Enable(world)
    WithQuests(world)
    Set(world, "count", 3)
    world:NextFrame()
    equal(world:WatchOrder(), "4 1 3", "order")

    world:MoveTo({ [3] = 10 })
    world:Elapse(TICK_SECONDS)
    equal(world:WatchOrder(), "4 1 3", "order after moving")
end)

test("sorts tracked quests by distance when asked to", function(world)
    Enable(world)
    Set(world, "sort", true)
    WithQuests(world)
    world.watches = { 3, 5 }
    Set(world, "count", 3)
    world:NextFrame()
    equal(world:WatchOrder(), "4 1 3", "closest first")

    world:MoveTo({ [3] = 10 })
    world:Elapse(TICK_SECONDS)
    equal(world:WatchOrder(), "3 4 1", "order after moving")
    equal(world.questSorts, 0, "tracker sorts by the game")
end)

test("sorting moves far quests below the closer ones, and keeps them there", function(world)
    Enable(world)
    Set(world, "sort", true)
    -- Seen in game: two far quests at similar distances above three closer ones.
    world:SetQuests({
        { questID = 1, distance = 3668 },
        { questID = 2, distance = 3278 },
        { questID = 3, distance = 2699 },
        { questID = 4, distance = 2422 },
        { questID = 5, distance = 2311 },
    })
    world.watches = { 1, 2, 3, 4, 5 }
    world:NextFrame()
    equal(world:WatchOrder(), "3 4 5 1 2", "closer quests first")

    for _ = 1, 3 do
        world:Elapse(TICK_SECONDS)
        equal(world:WatchOrder(), "3 4 5 1 2", "order kept on the next updates")
    end
end)

test("sorted quests at similar distances keep their places", function(world)
    Enable(world)
    Set(world, "sort", true)
    world:SetQuests({ { questID = 1, distance = 100 }, { questID = 2, distance = 120 } })
    world:NextFrame()
    equal(world:WatchOrder(), "1 2", "closest first")

    world:MoveTo({ [2] = 90 })
    world:Elapse(TICK_SECONDS)
    equal(world:WatchOrder(), "1 2", "kept when the other is slightly closer")

    world:MoveTo({ [2] = 50 })
    world:Elapse(TICK_SECONDS)
    equal(world:WatchOrder(), "2 1", "moved when the other is clearly closer")
end)

test("sorted quests near their objectives keep their places", function(world)
    Enable(world)
    Set(world, "sort", true)
    world:SetQuests({ { questID = 1, distance = 0 }, { questID = 2, distance = 10 } })
    world:NextFrame()
    equal(world:WatchOrder(), "1 2", "closest first")

    for _, distances in ipairs({ { [1] = 15, [2] = 0 }, { [1] = 0, [2] = 20 }, { [1] = 20, [2] = 5 } }) do
        world:MoveTo(distances)
        world:Elapse(TICK_SECONDS)
        equal(world:WatchOrder(), "1 2", "kept while walking between objectives")
    end
end)

test("sorting keeps the super-tracked quest first and super-tracked", function(world)
    Enable(world)
    Set(world, "sort", true)
    WithQuests(world)
    world.watches = { 1, 5 }
    world.superTracked = 5
    Set(world, "count", 2)
    world:NextFrame()
    equal(world:WatchOrder(), "5 4 1", "order")
    equal(world.superTracked, 5, "super-tracked")
end)

test("sorting doesn't count as the player's tracking changes", function(world)
    Enable(world)
    Set(world, "sort", true)
    Set(world, "keepManual", true)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:TrackQuest(2)
    world:NextFrame()
    equal(world:WatchOrder(), "4 1 2", "manual track last")

    world:MoveTo({ [2] = 10 })
    world:Elapse(TICK_SECONDS)
    equal(world:WatchOrder(), "2 4", "order after moving")
    expect(Pins(world)[2], "manual track still kept")

    world:Elapse(TICK_SECONDS)
    equal(world:WatchOrder(), "2 4", "re-tracked quests aren't dismissed")

    world:MoveTo({ [2] = 300 })
    world:Elapse(TICK_SECONDS)
    equal(world:WatchOrder(), "4 1 2", "manual track re-tracked last")
    expect(Pins(world)[2], "re-tracked manual track still kept")
end)

test("untracks far quests the player tracked, by default", function(world)
    Enable(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:TrackQuest(2)
    world:NextFrame()
    equal(world:Watched(), "1 4", "watched")
end)

test("keeps quests the player tracked when asked to, across sessions", function(world)
    Enable(world)
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
    Enable(world)
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
    Enable(world)
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
    Enable(world)
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
    Enable(world)
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
    Enable(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:Setting("quests.helpers.nearby"):SetValue(false)
    world:MoveTo({ [2] = 10, [3] = 20 })
    world:Elapse(TICK_SECONDS)
    world:TrackQuest(5)
    world:NextFrame()
    equal(world:Watched(), "1 4 5", "untouched while off")

    world:Setting("quests.helpers.nearby"):SetValue(true)
    world:NextFrame()
    equal(world:Watched(), "2 3", "updated when back on")
end)

test("turning the quest helpers off stops nearby tracking too", function(world)
    Enable(world)
    WithQuests(world)
    Set(world, "count", 2)
    world:NextFrame()
    world:Setting("quests.helpers.enabled"):SetValue(false)
    world:MoveTo({ [2] = 10, [3] = 20 })
    world:Elapse(TICK_SECONDS)
    equal(world:Watched(), "1 4", "untouched while off")

    world:Setting("quests.helpers.enabled"):SetValue(true)
    world:NextFrame()
    equal(world:Watched(), "2 3", "updated when back on")
end)
