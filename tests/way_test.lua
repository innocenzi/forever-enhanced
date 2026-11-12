-- TomTom /way command: coordinates, zones, /wayb, /cway, tracking and
-- registration. Map 1 is Elwynn Forest (continent 0, where the player
-- starts), map 2 Durotar (continent 1), map 3 a dungeon, map 4 Northshire, a
-- starting area inside Elwynn Forest.

local function Pin()
    local point = C_Map.GetUserWaypoint()
    return point and point.uiMapID, point and point.position.x, point and point.position.y
end

local function ExpectPin(mapID, x, y, label)
    local pinMapID, pinX, pinY = Pin()
    equal(pinMapID, mapID, label .. " map")
    expect(math.abs(pinX - x) < 1e-9, ("%s x: expected %s, got %s"):format(label, x, pinX))
    expect(math.abs(pinY - y) < 1e-9, ("%s y: expected %s, got %s"):format(label, y, pinY))
end

local function LastPrint(world)
    return world.prints[#world.prints]
end

test("/way x y silently pins the player's map and tracks it", function(world)
    expect(world:Chat("/way 45 63"), "command known")
    ExpectPin(1, 0.45, 0.63, "pin")
    expect(C_SuperTrack.IsSuperTrackingUserWaypoint(), "tracked")
    equal(#world.prints, 0, "chat messages")
end)

test("reads every way of writing coordinates", function(world)
    world:Chat("/way 45.5 63.25")
    ExpectPin(1, 0.455, 0.6325, "decimals")
    world:Chat("/way 45.5, 63.25")
    ExpectPin(1, 0.455, 0.6325, "comma separated")
    world:Chat("/way 45,63")
    ExpectPin(1, 0.45, 0.63, "joined")
    world:Chat("/way 45,5 63,25")
    ExpectPin(1, 0.455, 0.6325, "decimal commas")
end)

test("/way finds a zone by name and ignores the description", function(world)
    world:Chat("/way durotar 52 41 Razor Hill")
    ExpectPin(2, 0.52, 0.41, "Durotar")
    world:Chat("/way 10 20 Goldshire 2")
    ExpectPin(1, 0.10, 0.20, "description with a number")

    world:Chat("/way ELWYNN forest 42 65")
    ExpectPin(1, 0.42, 0.65, "multi-word zone")
    world:Chat("/way Elwynn Forest, 40 60")
    ExpectPin(1, 0.40, 0.60, "zone followed by a comma")
end)

test("/way takes a map ID", function(world)
    world:Chat("/way #2 10 20")
    ExpectPin(2, 0.10, 0.20, "map 2")
end)

test("/way rejects unknown zones and maps without pins", function(world)
    world:Chat("/way Atlantis 10 20")
    expect(not C_Map.HasUserWaypoint(), "no pin for an unknown zone")
    equal(world.errors[#world.errors], world.L["map.pin.unknownZone"]:format("Atlantis"), "unknown zone error")

    world:Chat("/way #3 10 20")
    expect(not C_Map.HasUserWaypoint(), "no pin in a dungeon")
    equal(world.errors[#world.errors], MAP_PIN_INVALID_MAP, "invalid map error")
end)

test("/way shows how to use it when it can't read coordinates", function(world)
    for _, text in ipairs({ "/way", "/way Goldshire", "/way 150 20", "/way 45" }) do
        world.prints = {}
        world:Chat(text)
        expect(not C_Map.HasUserWaypoint(), "no pin for " .. text)
        equal(LastPrint(world):find(world.L["map.pin.usage"], 1, true) ~= nil, true, "usage for " .. text)
    end
end)

test("/way reset and /cway remove the pin", function(world)
    world:Chat("/way 45 63")
    world:Chat("/way reset")
    expect(not C_Map.HasUserWaypoint(), "removed by /way reset")
    equal(#world.prints, 0, "chat messages")

    world:Chat("/way 45 63")
    world:Chat("/cway")
    expect(not C_Map.HasUserWaypoint(), "removed by /cway")
end)

test("/wayb pins the player's position", function(world)
    world:StandAt(250, 750)
    world:Chat("/wayb Camp")
    ExpectPin(1, 0.25, 0.75, "position")

    C_Map.ClearUserWaypoint()
    world:StandAt(250, 750, 0, 33)
    world:Chat("/wayb")
    expect(not C_Map.HasUserWaypoint(), "no pin in an instance")
    equal(world.errors[#world.errors], MAP_PIN_INVALID_MAP, "invalid map error")
end)

test("pins the zone when the player stands in a starting area", function(world)
    world:StandAt(900, 100)
    equal(C_Map.GetBestMapForUnit("player"), 4, "player map")
    world:Chat("/way 45 63")
    ExpectPin(1, 0.45, 0.63, "/way")

    world:Chat("/wayb")
    ExpectPin(1, 0.9, 0.1, "/wayb")
end)

test("doesn't track the pin when tracking is off", function(world)
    world:Setting("map.pin.track"):SetValue(false)
    world:Chat("/way 45 63")
    expect(C_Map.HasUserWaypoint(), "pin set")
    expect(not C_SuperTrack.IsSuperTrackingUserWaypoint(), "not tracked")
end)

test("disabling the map pin feature removes the commands", function(world)
    world:Setting("map.pin.enabled"):SetValue(false)
    expect(not world:Chat("/way 10 20"), "unknown while disabled")
    expect(SlashCmdList.FOREVERENHANCED_WAY == nil, "handler removed")

    world:Setting("map.pin.enabled"):SetValue(true)
    expect(world:Chat("/way 10 20"), "known again")
end)

test("turning the commands off removes them", function(world)
    world:Chat("/way 45 63")
    world:Setting("map.pin.commands"):SetValue(false)
    for _, text in ipairs({ "/way 10 20", "/wayb", "/cway" }) do
        expect(not world:Chat(text), text .. " unknown while disabled")
    end
    expect(SlashCmdList.FOREVERENHANCED_WAY == nil, "handler removed")
    expect(SLASH_FOREVERENHANCED_WAY1 == nil, "command name removed")
    ExpectPin(1, 0.45, 0.63, "pin kept")

    world:Setting("map.pin.commands"):SetValue(true)
    expect(world:Chat("/way 10 20"), "known again")
    ExpectPin(1, 0.10, 0.20, "pin moved")
end)

test("leaves /way to another addon that registered it", function(world)
    world:Setting("map.pin.commands"):SetValue(false)
    local received
    world.env.SLASH_TOMTOM_WAY1 = "/way"
    SlashCmdList.TOMTOM_WAY = function(text)
        received = text
    end
    world:Setting("map.pin.commands"):SetValue(true)

    world:Chat("/way 45 63")
    equal(received, "45 63", "other addon's command ran")
    expect(not C_Map.HasUserWaypoint(), "no pin from us")
    expect(world:Chat("/cway"), "/cway still ours")

    -- Once the chat edit box imported it, toggling still leaves it alone.
    world:Setting("map.pin.commands"):SetValue(false)
    world:Setting("map.pin.commands"):SetValue(true)
    world:Chat("/way 1 2")
    equal(received, "1 2", "other addon's command still runs")
end)
