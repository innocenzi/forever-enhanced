-- Clear Map Pin on Arrival: range, re-arming, message, other continents,
-- instances, taxis and lifecycle. Distances are in yards; the pin is checked
-- every TICK_SECONDS. The default range is 30 yards.

local TICK_SECONDS = 0.5

local function Set(world, key, value)
    world:Setting("map.pin." .. key):SetValue(value)
end

-- The player starts far from a pin at (500, 500).
local function WithPin(world)
    world:StandAt(0, 0)
    world:SetWaypoint(500, 500)
    world:Elapse(TICK_SECONDS)
end

test("removes the pin when the player gets within range", function(world)
    WithPin(world)
    world:StandAt(500, 540)
    world:Elapse(TICK_SECONDS)
    expect(C_Map.HasUserWaypoint(), "pin kept out of range")

    world:StandAt(500, 520)
    world:Elapse(TICK_SECONDS)
    expect(not C_Map.HasUserWaypoint(), "pin removed within range")
    equal(#world.warnings, 1, "messages")
    equal(world.warnings[1], NAVIGATION_DESTINATION_REACHED_MESSAGE, "message")
end)

test("uses the chosen arrival distance", function(world)
    Set(world, "range", 50)
    WithPin(world)
    world:StandAt(540, 500)
    world:Elapse(TICK_SECONDS)
    expect(not C_Map.HasUserWaypoint(), "pin removed within 50 yards")
end)

test("a pin placed within range stays until the player leaves and comes back", function(world)
    world:StandAt(500, 505)
    world:SetWaypoint(500, 500)
    world:Elapse(TICK_SECONDS * 4)
    expect(C_Map.HasUserWaypoint(), "pin kept while never left")

    world:StandAt(500, 600)
    world:Elapse(TICK_SECONDS)
    world:StandAt(500, 505)
    world:Elapse(TICK_SECONDS)
    expect(not C_Map.HasUserWaypoint(), "pin removed on return")
end)

test("moving the pin under the player doesn't remove it", function(world)
    WithPin(world)
    world:StandAt(200, 200)
    world:SetWaypoint(200, 205)
    world:Elapse(TICK_SECONDS * 4)
    expect(C_Map.HasUserWaypoint(), "pin kept")
end)

test("raising the distance while near the pin doesn't remove it", function(world)
    WithPin(world)
    world:StandAt(500, 540)
    world:Elapse(TICK_SECONDS)
    Set(world, "range", 50)
    world:Elapse(TICK_SECONDS * 4)
    expect(C_Map.HasUserWaypoint(), "pin kept")
end)

test("shows no message when disabled", function(world)
    Set(world, "announce", false)
    WithPin(world)
    world:StandAt(500, 500)
    world:Elapse(TICK_SECONDS)
    expect(not C_Map.HasUserWaypoint(), "pin removed")
    equal(#world.warnings, 0, "messages")
end)

test("ignores a pin on another continent and positions in instances", function(world)
    world:StandAt(0, 0)
    world:SetWaypoint(500, 500, 2)
    world:Elapse(TICK_SECONDS)
    world:StandAt(500, 500)
    world:Elapse(TICK_SECONDS)
    expect(C_Map.HasUserWaypoint(), "pin on another continent kept")

    world:SetWaypoint(500, 500)
    world:StandAt(0, 0)
    world:Elapse(TICK_SECONDS)
    world:StandAt(500, 500, 0, 33)
    world:Elapse(TICK_SECONDS)
    expect(C_Map.HasUserWaypoint(), "pin kept while in an instance")
end)

test("a flight path over the pin doesn't remove it, landing near it does", function(world)
    WithPin(world)
    world.onTaxi = true
    world:StandAt(500, 500)
    world:Elapse(TICK_SECONDS)
    expect(C_Map.HasUserWaypoint(), "pin kept on taxi")

    world.onTaxi = false
    world:Elapse(TICK_SECONDS)
    expect(not C_Map.HasUserWaypoint(), "pin removed after landing")
end)

test("disabling the feature keeps the pin and stops checking", function(world)
    WithPin(world)
    world:Setting("map.pin.arrival"):SetValue(false)
    world:StandAt(500, 500)
    world:Elapse(TICK_SECONDS * 4)
    expect(C_Map.HasUserWaypoint(), "pin kept while disabled")

    world:Setting("map.pin.arrival"):SetValue(true)
    world:Elapse(TICK_SECONDS)
    expect(C_Map.HasUserWaypoint(), "pin under the player kept on enable")

    world:StandAt(0, 0)
    world:Elapse(TICK_SECONDS)
    world:StandAt(500, 500)
    world:Elapse(TICK_SECONDS)
    expect(not C_Map.HasUserWaypoint(), "pin removed on return")
end)
