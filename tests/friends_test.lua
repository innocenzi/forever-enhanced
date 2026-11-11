-- Friends on the Map: who gets asked and how, answering friends only, the
-- pins on the shown map, pacing under the addon message throttle, and
-- turning things off, then the same for OpenMap's protocol. Alice is a character friend on the player's realm, Bob a
-- Battle.net friend on game account 7, Carol an offline character friend;
-- game account 9 is a Battle.net friend in the desktop app.

local ALICE = "Player-1-0000000A"
local BOB = "Player-2-0000000B"
local CAROL = "Player-1-0000000C"

local function Set(world, key, value)
    world:Setting("map.friends." .. key):SetValue(value)
end

local function AddFriends(world)
    world.friends = {
        { guid = ALICE, name = "Alice" },
        { guid = CAROL, name = "Carol", connected = false },
    }
    world.bnetFriends = {
        { { gameAccountID = 7, playerGuid = BOB } },
        { { gameAccountID = 9, playerGuid = "Player-3-00000009", clientProgram = "App" } },
    }
    world.players = {
        [ALICE] = { name = "Alice", realm = "Forever", class = "WARRIOR" },
        [BOB] = { name = "Bob", realm = "Elsewhere", class = "MAGE" },
    }
end

local function Setup(world)
    AddFriends(world)
    Set(world, "enabled", true)
end

-- The addon messages sent since the last call, as "target message" strings
-- ("Alice 1W", "#7 1W" for game account 7), sorted.
local function Sent(world)
    local sent = {}
    for _, record in ipairs(world.sentAddon) do
        local target = record.target or ("#" .. record.gameAccountID)
        table.insert(sent, target .. " " .. record.message)
    end
    world.sentAddon = {}
    table.sort(sent)
    return table.concat(sent, ", ")
end

local function Pins(world)
    local pins = {}
    for _, pin in ipairs(world:FriendPins()) do
        table.insert(pins, ("%s %.2f %.2f"):format(world.players[pin.guid].name, pin.x, pin.y))
    end
    return table.concat(pins, ", ")
end

test("is off until the player turns it on", function(world)
    AddFriends(world)
    world:OpenMap()
    world:ReceiveWhisperAddon("1W", "Alice-Forever")
    equal(Sent(world), "", "messages")
end)

test("opening the map asks online friends, each by its own channel", function(world)
    Setup(world)
    world:OpenMap()
    equal(Sent(world), "#7 1W, Alice 1W", "requests")

    world:CloseMap()
    world:Elapse(60)
    equal(Sent(world), "", "nothing once the map is closed")
    equal(world:TickerCount(), 0, "tickers")
end)

test("asks friends who answered again while the map stays open, the others only once", function(world)
    Setup(world)
    world:OpenMap()
    world:ReceiveWhisperAddon("1P:1:0.5000:0.5000", "Alice-Forever")
    Sent(world)

    world:Elapse(15)
    equal(Sent(world), "Alice 1W", "repeated request")

    world:CloseMap()
    world:OpenMap()
    equal(Sent(world), "Alice 1W", "next opening")
end)

test("asks a friend again once they come back online", function(world)
    Setup(world)
    world:OpenMap()
    world:CloseMap()
    Sent(world)

    world.bnetFriends[1][1].isOnline = false
    world:Fire("BN_FRIEND_INFO_CHANGED")
    world.bnetFriends[1][1].isOnline = true
    world:Fire("BN_FRIEND_INFO_CHANGED")
    world:OpenMap()
    equal(Sent(world), "#7 1W", "asked again")
end)

test("asks friends at once when turned on with the map open", function(world)
    AddFriends(world)
    world:OpenMap()
    Set(world, "enabled", true)
    equal(Sent(world), "#7 1W, Alice 1W", "requests")
end)

test("answers a friend's request with the player's position", function(world)
    Setup(world)
    world:StandAt(250, 500)
    world:ReceiveWhisperAddon("1W", "Alice-Forever")
    equal(Sent(world), "Alice 1P:1:0.2500:0.5000", "whispered answer")

    world:ReceiveGameData("1W", 7)
    equal(Sent(world), "#7 1P:1:0.2500:0.5000", "Battle.net answer")
end)

test("never answers anyone but an online friend", function(world)
    Setup(world)
    world:ReceiveWhisperAddon("1W", "Mallory-Forever")
    world:ReceiveWhisperAddon("1W", "Carol-Forever")
    world:ReceiveGameData("1W", 9)
    world:ReceiveGameData("1W", 42)
    world:ReceiveWhisperAddon("1W", "Alice-Forever", "OtherAddon")
    equal(Sent(world), "", "messages")
end)

test("keeps answering while the friend watches, when the player moves or to stay shown", function(world)
    Setup(world)
    world:StandAt(250, 500)
    world:ReceiveWhisperAddon("1W", "Alice-Forever")
    Sent(world)

    world:Elapse(3)
    equal(Sent(world), "", "standing still")

    world:StandAt(300, 500)
    world:Elapse(3)
    equal(Sent(world), "Alice 1P:1:0.3000:0.5000", "moved")

    world:Elapse(15)
    equal(Sent(world), "Alice 1P:1:0.3000:0.5000", "keepalive")

    world:Elapse(30)
    Sent(world)
    world:Elapse(30)
    equal(Sent(world), "", "the friend stopped asking")
    equal(world:TickerCount(), 0, "tickers")
end)

test("answers hidden in an instance", function(world)
    Setup(world)
    world:StandAt(0, 0, 0, 36)
    world:ReceiveWhisperAddon("1W", "Alice-Forever")
    equal(Sent(world), "Alice 1H", "answer")
end)

test("stops sharing when share is turned off, and hides the player from watching friends", function(world)
    Setup(world)
    world:StandAt(250, 500)
    world:ReceiveWhisperAddon("1W", "Alice-Forever")
    Sent(world)

    Set(world, "share", false)
    equal(Sent(world), "Alice 1H", "hidden from Alice")

    world:ReceiveWhisperAddon("1W", "Alice-Forever")
    world:Elapse(60)
    equal(Sent(world), "", "no more answers")
end)

test("still shows friends with share turned off", function(world)
    Setup(world)
    Set(world, "share", false)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    equal(Pins(world), "Alice 0.25 0.50", "pins")
end)

test("draws friends on the shown map, through world coordinates", function(world)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    world:ReceiveGameData("1P:2:0.1000:0.2000", 7)
    equal(Pins(world), "Alice 0.25 0.50", "Elwynn Forest")

    world:ShowMap(2)
    equal(Pins(world), "Bob 0.10 0.20", "Durotar")

    world:ShowMap(4)
    equal(Pins(world), "", "Northshire, with Alice outside it")
    world:ReceiveWhisperAddon("1P:1:0.9000:0.1000", "Alice-Forever")
    equal(Pins(world), "Alice 0.50 0.50", "Northshire, with Alice inside it")
end)

test("removes a friend's pin when they're hidden or stop answering", function(world)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    world:ReceiveWhisperAddon("1H", "Alice-Forever")
    equal(Pins(world), "", "hidden")

    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    world:Elapse(30)
    equal(Pins(world), "Alice 0.25 0.50", "still fresh")
    world:Elapse(15)
    equal(Pins(world), "", "stale")
end)

test("removes a friend's pin when they go offline", function(world)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    world.friends[1].connected = false
    world:Fire("FRIENDLIST_UPDATE")
    equal(Pins(world), "", "pins")
end)

test("leaves group members to the game's own pins", function(world)
    Setup(world)
    world.groupGUIDs[ALICE] = true
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    equal(Pins(world), "", "pins")
end)

test("draws no one but online friends", function(world)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Mallory-Forever")
    world:ReceiveGameData("1P:1:0.2500:0.5000", 42)
    world:ReceiveWhisperAddon("1P:1:nope", "Alice-Forever")
    world:ReceiveWhisperAddon("2P:1:0.2500:0.5000", "Alice-Forever")
    equal(#world:FriendPins(), 0, "pins")
end)

test("names the friend and their zone in the pin's tooltip", function(world)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    world:FriendPins()[1].frame:OnMouseEnter()
    equal(world.tooltip, RAID_CLASS_COLORS.WARRIOR:WrapTextInColorCode("Alice"), "name")
    equal(world.tooltipLines[1], "Elwynn Forest", "zone")
end)

test("names a friend never met nearby from the friend lists", function(world)
    Setup(world)
    world.friends[1].className = "Guerrière"
    world.bnetFriends[1][1].characterName = "Bob"
    world.bnetFriends[1][1].classFilename = "MAGE"
    world.players = {}
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    world:ReceiveGameData("1P:1:0.2500:0.5000", 7)

    local alice, bob = world:FriendPins()[1], world:FriendPins()[2]
    alice.frame:OnMouseEnter()
    equal(world.tooltip, RAID_CLASS_COLORS.WARRIOR:WrapTextInColorCode("Alice"), "character friend")
    equal(world.tooltipLines[1], "Elwynn Forest", "character friend's zone")
    bob.frame:OnMouseEnter()
    equal(world.tooltip, RAID_CLASS_COLORS.MAGE:WrapTextInColorCode("Bob"), "Battle.net friend")
end)

test("asks many friends without hitting the addon message throttle", function(world)
    world.friends = {}
    for index = 1, 25 do
        table.insert(world.friends, { guid = ("Player-1-%08d"):format(index), name = "Friend" .. index })
    end
    Set(world, "enabled", true)
    world:OpenMap()
    world:Elapse(30)

    local asked = {}
    for _, record in ipairs(world.sentAddon) do
        equal(record.message, "1W", "message")
        expect(not asked[record.target], "asked twice: " .. record.target)
        asked[record.target] = true
    end
    for index = 1, 25 do
        expect(asked["Friend" .. index], "never asked: Friend" .. index)
    end
end)

test("turning it off removes the pins, hides the player and stops sending", function(world)
    Setup(world)
    world:StandAt(250, 500)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    world:ReceiveGameData("1W", 7)
    Sent(world)

    Set(world, "enabled", false)
    equal(#world:FriendPins(), 0, "pins")
    equal(next(WorldMapFrame.dataProviders), nil, "data providers")
    equal(Sent(world), "#7 1H", "hidden from Bob")

    world:ReceiveGameData("1W", 7)
    world:Elapse(60)
    equal(Sent(world), "", "messages")
    equal(world:TickerCount(), 0, "tickers")
end)

-- OpenMap's protocol ---------------------------------------------------------------------

local OPENMAP = "OpenMapLoc"

local function L1(mapID, x, y, class, level)
    return ("L1\t%d\t%.4f\t%.4f\t%s\t%d"):format(mapID, x, y, class or "WARRIOR", level or 20)
end

test("greets online friends in OpenMap's protocol only once turned on", function(world)
    Setup(world)
    equal(Sent(world), "", "off by default")

    Set(world, "openmap", true)
    equal(Sent(world), "#7 H1, Alice H1", "hellos")

    world.bnetFriends[1][1].isOnline = false
    world:Fire("BN_FRIEND_INFO_CHANGED")
    world.bnetFriends[1][1].isOnline = true
    world:Fire("BN_FRIEND_INFO_CHANGED")
    equal(Sent(world), "#7 H1", "hello to a friend back online")
end)

test("answers an OpenMap hello with the position while sharing", function(world)
    Setup(world)
    world:StandAt(250, 500)
    Set(world, "openmap", true)
    Sent(world)

    world:ReceiveWhisperAddon("H1", "Alice-Forever", OPENMAP)
    equal(Sent(world), "Alice " .. L1(1, 0.25, 0.5, "MAGE", 12), "sharing")

    Set(world, "share", false)
    world:ReceiveGameData("H1", 7, OPENMAP)
    equal(Sent(world), "#7 H2", "not sharing")
end)

test("sends the position to OpenMap users while moving, less often standing still", function(world)
    Setup(world)
    world:StandAt(250, 500)
    Set(world, "openmap", true)
    Sent(world)

    world:ReceiveWhisperAddon("H2", "Alice-Forever", OPENMAP)
    equal(Sent(world), "Alice " .. L1(1, 0.25, 0.5, "MAGE", 12), "a new OpenMap user")

    world:Elapse(10)
    equal(Sent(world), "", "standing still")

    world:StandAt(300, 500)
    world:Elapse(2)
    equal(Sent(world), "Alice " .. L1(1, 0.3, 0.5, "MAGE", 12), "moved")

    world:Elapse(58)
    equal(Sent(world), "", "standing still again")
    world:Elapse(2)
    equal(Sent(world), "Alice " .. L1(1, 0.3, 0.5, "MAGE", 12), "a minute later")

    Set(world, "share", false)
    world:Elapse(2)
    equal(Sent(world), "Alice L0", "stopped sharing")
    world:Elapse(120)
    equal(Sent(world), "", "nothing more")
end)

test("tells OpenMap users the player stopped sharing in an instance", function(world)
    Setup(world)
    world:StandAt(250, 500)
    Set(world, "openmap", true)
    world:ReceiveWhisperAddon("H2", "Alice-Forever", OPENMAP)
    Sent(world)

    world:StandAt(0, 0, 0, 36)
    world:Elapse(2)
    equal(Sent(world), "Alice L0", "in an instance")
end)

test("draws friends who use OpenMap until they stop sharing or go quiet", function(world)
    Setup(world)
    Set(world, "share", false)
    Set(world, "openmap", true)
    world:OpenMap(1)
    Sent(world)

    world:ReceiveWhisperAddon(L1(1, 0.25, 0.5), "Alice-Forever", OPENMAP)
    world:ReceiveGameData(L1(1, 0.1, 0.2, "MAGE"), 7, OPENMAP)
    equal(Pins(world), "Alice 0.25 0.50, Bob 0.10 0.20", "pins")

    world:Elapse(15)
    equal(Sent(world), "", "never asked in the addon's own protocol")

    world:ReceiveGameData("L0", 7, OPENMAP)
    equal(Pins(world), "Alice 0.25 0.50", "Bob stopped sharing")

    world:Elapse(130)
    equal(Pins(world), "Alice 0.25 0.50", "still fresh")
    world:Elapse(10)
    equal(Pins(world), "", "quiet")
end)

test("ignores OpenMap messages while turned off, and from anyone but friends", function(world)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon(L1(1, 0.25, 0.5), "Alice-Forever", OPENMAP)
    world:ReceiveWhisperAddon("H1", "Alice-Forever", OPENMAP)
    equal(#world:FriendPins(), 0, "pins while off")
    Sent(world)

    Set(world, "share", false)
    Set(world, "openmap", true)
    Sent(world)
    world:ReceiveWhisperAddon(L1(1, 0.25, 0.5), "Mallory-Forever", OPENMAP)
    world:ReceiveGameData("H1", 42, OPENMAP)
    world:ReceiveWhisperAddon("L1\t1\tnope\t0.5\tMAGE\t1", "Alice-Forever", OPENMAP)
    world:ReceiveWhisperAddon(L1(1, 1.5, 0.5), "Alice-Forever", OPENMAP)
    equal(#world:FriendPins(), 0, "pins")
    equal(Sent(world), "", "messages")
end)

test("leaves OpenMap's protocol to OpenMap when it's loaded", function(world)
    world.loadedAddOns.OpenMap = true
    Setup(world)
    Set(world, "openmap", true)
    world:ReceiveWhisperAddon("H1", "Alice-Forever", OPENMAP)
    equal(Sent(world), "", "messages")
    equal(world:TickerCount(), 0, "tickers")
end)

test("turning OpenMap off tells its users and removes their pins", function(world)
    Setup(world)
    world:StandAt(250, 500)
    Set(world, "openmap", true)
    world:OpenMap(1)
    world:ReceiveWhisperAddon(L1(1, 0.25, 0.5), "Alice-Forever", OPENMAP)
    Sent(world)

    Set(world, "openmap", false)
    equal(Sent(world), "Alice L0", "stopped sharing")
    equal(#world:FriendPins(), 0, "pins")

    world:ReceiveWhisperAddon(L1(1, 0.25, 0.5), "Alice-Forever", OPENMAP)
    world:CloseMap()
    world:Elapse(120)
    equal(Sent(world), "", "messages")
    equal(#world:FriendPins(), 0, "pins after")
    equal(world:TickerCount(), 0, "tickers")
end)
