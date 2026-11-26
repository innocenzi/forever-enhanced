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

    world:Setting("map.pin.enabled"):SetValue(false)
    expect(not world:Chat("/way 10 20"), "unknown with the feature off")
    expect(SlashCmdList.FOREVERENHANCED_WAY == nil, "handler removed with the feature off")
    world:Setting("map.pin.enabled"):SetValue(true)
    expect(world:Chat("/way 10 20"), "known with the feature back on")
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

-- Map pins shared with the group ---------------------------------------------------------

local SHARE_PREFIX = "FEPin"

local function SharedPins(world)
    local sent = {}
    for _, record in ipairs(world.sentAddon) do
        if record.prefix == SHARE_PREFIX then
            table.insert(sent, record)
        end
    end
    return sent
end

local function ReceivePin(world, message, chatType, sender)
    world:ReceiveGroupAddon(SHARE_PREFIX, message, chatType or "PARTY", sender or "Arthas-Forever")
end

-- The player's pin at 45, 63 on Elwynn Forest, the map open on it, the mouse over the pin.
local function HoverPin(world)
    world:Chat("/way 45 63")
    world:OpenMap(1)
    world:NextFrame()
    return world:HoverMapPin()
end

local function AltClick(world)
    world.alt = true
    world:NextFrame()
    world:MapClick()
    world.alt = nil
    world:NextFrame()
end

test("Alt Click on the map pin sends it to the group's addons, without tracking it", function(world)
    world.party = true
    HoverPin(world)
    local tracked = C_SuperTrack.IsSuperTrackingUserWaypoint()
    AltClick(world)
    local sent = SharedPins(world)
    equal(#sent, 1, "messages")
    equal(sent[1].message, "1P:1:4500:6300", "message")
    equal(sent[1].chatType, "PARTY", "channel")
    equal(C_SuperTrack.IsSuperTrackingUserWaypoint(), tracked, "tracking left alone")
    equal(LastPrint(world), world.L["map.pin.shared"], "said so")
    expect(tContains(world.sounds, SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE), "with Blizzard's sound")
    equal(#world.sentChat, 0, "nothing in chat")

    world:MapClick()
    equal(#SharedPins(world), 1, "a click without Alt doesn't share")
    equal(C_SuperTrack.IsSuperTrackingUserWaypoint(), not tracked, "it tracks, as Blizzard's")

    world.party, world.instanceGroup = false, true
    AltClick(world)
    equal(SharedPins(world)[2].chatType, "INSTANCE_CHAT", "instance groups")
end)

test("shows how to share the map pin in its tooltip while in a group", function(world)
    HoverPin(world)
    expect(not tContains(world.tooltipLines, world.L["map.pin.shareHint"]), "no hint alone")
    world.party = true
    world:HoverMapPin()
    equal(world.tooltip, MAP_PIN_SHARING, "Blizzard's tooltip")
    equal(world.tooltipLines[#world.tooltipLines], world.L["map.pin.shareHint"], "the hint, last")

    local pin = world:MapFrameUnderMouse("LeftButton", true)
    world.alt = true
    world:NextFrame()
    local standIn = world:MapFrameUnderMouse("LeftButton", true)
    expect(standIn ~= pin, "with Alt, a frame of ours takes the mouse")
    standIn:RunScript("OnEnter")
    equal(world.tooltip, MAP_PIN_SHARING, "the pin's tooltip")
    equal(world.tooltipLines[#world.tooltipLines], world.L["map.pin.shareHint"], "with the hint")
    world:NextFrame()
    world:NextFrame()
    equal(world:MapFrameUnderMouse("LeftButton", true), standIn, "kept while Alt is held")
    world.alt = nil
    world:NextFrame()
    equal(world:MapFrameUnderMouse("LeftButton", true), pin, "the pin's again without Alt")

    world:Setting("map.pin.share"):SetValue(false)
    world:HoverMapPin()
    expect(not tContains(world.tooltipLines, world.L["map.pin.shareHint"]), "no hint with sharing off")
end)

test("Alt Click on the map pin stays Blizzard's alone, with sharing off or out of a group", function(world)
    HoverPin(world)
    AltClick(world)
    equal(#SharedPins(world), 0, "not in a group")
    expect(C_SuperTrack.IsSuperTrackingUserWaypoint() ~= nil, "Blizzard's click")

    world.party = true
    world:Setting("map.pin.share"):SetValue(false)
    AltClick(world)
    equal(#SharedPins(world), 0, "sharing off")
    equal(#world.prints, 0, "nothing said")
end)

test("says so when the map pin can't be shared", function(world)
    world.party = true
    world.addonLockdown = true
    HoverPin(world)
    AltClick(world)
    equal(world.errors[#world.errors], world.L["map.pin.shareFailed"], "error")
    equal(#world.prints, 0, "nothing said")
end)

test("offers a group member's map pin, followed and tracked once accepted", function(world)
    ReceivePin(world, "1P:2:5200:4100")
    local dialog = world:Dialog()
    expect(dialog, "dialog shown")
    equal(dialog.text, world.L["map.pin.sharedPrompt"]:format("Arthas", "Durotar"), "dialog text")
    expect(not C_Map.HasUserWaypoint(), "no pin before accepting")

    world:ClickDialogButton(1)
    ExpectPin(2, 0.52, 0.41, "accepted pin")
    expect(C_SuperTrack.IsSuperTrackingUserWaypoint(), "tracked")
end)

test("declining a shared map pin keeps the player's own", function(world)
    world:Chat("/way 45 63")
    ReceivePin(world, "1P:2:5200:4100")
    world:ClickDialogButton(2)
    ExpectPin(1, 0.45, 0.63, "own pin")
end)

test("follows shared map pins without asking when accepting automatically", function(world)
    world:Setting("map.pin.autoAccept"):SetValue(true)
    ReceivePin(world, "1P:2:5200:4100", "RAID")
    expect(not world:Dialog(), "no dialog")
    ExpectPin(2, 0.52, 0.41, "pin")
    expect(C_SuperTrack.IsSuperTrackingUserWaypoint(), "tracked")
end)

test("ignores shared map pins it can't follow or that aren't from the group", function(world)
    world:Setting("map.pin.autoAccept"):SetValue(true)
    ReceivePin(world, "1P:2:5200:4100", "PARTY", "Hylmew Fortbras-Forever")
    ReceivePin(world, "1P:2:5200:4100", "WHISPER")
    ReceivePin(world, "1P:3:5200:4100")
    ReceivePin(world, "1P:2:52000:4100")
    ReceivePin(world, "2P:2:5200:4100")
    ReceivePin(world, world:Secret("1P:2:5200:4100"))
    ReceivePin(world, "1P:2:5200:4100", "PARTY", world:Secret("Arthas-Forever"))
    world:ReceiveGroupAddon("Other", "1P:2:5200:4100", "PARTY", "Arthas-Forever")
    expect(not C_Map.HasUserWaypoint(), "no pin")
end)

test("a map pin accepted in combat is followed once combat ends", function(world)
    world:EnterCombat()
    ReceivePin(world, "1P:2:5200:4100")
    world:ClickDialogButton(1)
    expect(not C_Map.HasUserWaypoint(), "no pin in combat")
    world:LeaveCombat()
    ExpectPin(2, 0.52, 0.41, "pin after combat")
end)

test("turning sharing off closes the offer and stops listening", function(world)
    ReceivePin(world, "1P:2:5200:4100")
    world:Setting("map.pin.share"):SetValue(false)
    expect(not world:Dialog(), "dialog closed")
    ReceivePin(world, "1P:2:5200:4100")
    expect(not world:Dialog(), "no dialog while off")

    world:Setting("map.pin.share"):SetValue(true)
    world:Setting("map.pin.autoAccept"):SetValue(true)
    world:EnterCombat()
    ReceivePin(world, "1P:2:5200:4100")
    world:Setting("map.pin.share"):SetValue(false)
    world:LeaveCombat()
    expect(not C_Map.HasUserWaypoint(), "waiting pin dropped")
end)
