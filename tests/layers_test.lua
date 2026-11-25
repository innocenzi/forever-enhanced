-- Layer swaps: LayerSwap's wire format, reading the layer from creatures,
-- the player's own ask (search, burst, invite, move, leaving), hosting, and
-- turning things off. The player stands in Elwynn Forest (map 1), at 48.2,
-- 42.5 on its map, on layer 6843 (A, the first one seen) until moved to 7088.
-- Alice Smith and Bob are other players of the zone.

local LAYER_A = 6843
local LAYER_B = 7088
local ZONE_UID = 5

local function Set(world, key, value)
    world:Setting("map.layers." .. key):SetValue(value)
end

local function Layers(world)
    return world.ns:GetFeature("map", "layers")
end

local function Setup(world)
    world:StandAt(482, 425)
end

-- A creature of `server`'s layer coming into view, its GUID.
local function See(world, server)
    local guid = world:Creature(server, ZONE_UID)
    world:ShowNamePlate(guid)
    return guid
end

-- LayerSwap whispers sent since the last call, "target: message", in order.
local function Sent(world)
    local sent = {}
    for _, record in ipairs(world.sentAddon) do
        if record.prefix == "LayerSwap" then
            table.insert(sent, record.target .. ": " .. record.message)
        end
    end
    world.sentAddon = {}
    return table.concat(sent, ", ")
end

local function MenuEntry(world, key)
    return world:MenuEntry(world:OpenUnitMenu("MENU_UNIT_SELF"), world.L[key])
end

local function ClickSwap(world)
    world:ClickMenuEntry(assert(MenuEntry(world, "map.layers.swap"), "no Swap layer entry"))
end

local function ZoneTooltipLine(world)
    return world:HoverZoneText()[1]
end

local function Row(fullName, area)
    return { fullName = fullName, area = area or "Elwynn Forest" }
end

local function Receive(world, message, sender)
    world:ReceiveWhisperAddon(message, sender, "LayerSwap")
end

local function LastWarning(world)
    return world.warnings[#world.warnings]
end

local function LastError(world)
    return world.errors[#world.errors]
end

local function LastPrint(world)
    return world.prints[#world.prints]
end

-- Asks from layer A, with Alice Smith and Bob found in the zone.
local function AskFromA(world)
    Setup(world)
    See(world, LAYER_A)
    ClickSwap(world)
    world:AnswerWho({ Row("Alice Smith-Forever"), Row("Bob-Forever") })
    return Sent(world)
end

-- Wire format ---------------------------------------------------------------------------------

test("writes and reads LayerSwap's messages", function(world)
    local Protocol = Layers(world).Protocol
    equal(Protocol:EncodeAsk(1429, "7088-2", 0.482, 0.425), "inv layer <LS 1429 not 7088-2 48.2,42.5>", "ask")
    equal(Protocol:EncodeAsk(1429, nil, 0.482, 0.425), "inv layer <LS 1429 48.2,42.5>", "ask without layer")
    equal(Protocol:EncodeAsk(1429), "inv layer <LS 1429>", "ask without position")

    local ask = Protocol:ParseAsk("inv layer <LS 1429 not 7088-2 not 6843-8 48.2,42.5>")
    equal(ask.zone, "1429", "zone")
    equal(#ask.avoids, 2, "layers named")
    equal(ask.avoids[1], "7088-2", "layer left")
    equal(ask.avoids[2], "6843-8", "layer seen")
    equal(ask.x, 48.2, "x")
    equal(ask.y, 42.5, "y")
    ask = Protocol:ParseAsk("inv layer <LS 1431 want 6782-1753>")
    equal(ask.zone, "1431", "zone of a want")
    equal(ask.want, "6782-1753", "want")
    equal(#ask.avoids, 0, "no layer left")
    equal(Protocol:ParseAsk("inv layer <LS 1429>").zone, "1429", "zone alone")
    equal(Protocol:ParseAsk("inv layer"), nil, "an ask without zone")
    equal(Protocol:ParseAsk("heard Hylmew|-|-|-"), nil, "not an ask")

    equal(Protocol:EncodeHeard("Hylmew", "6843-8", 1, true), "heard Hylmew|6843-8|1|h", "heard")
    equal(Protocol:EncodeHeard("Hylmew", nil, 1, false), "heard Hylmew|-|1|-", "heard without layer")
    local reply = Protocol:ParseReply("heard Alice Smith|6843-8|1|h")
    equal(reply.kind, "heard", "reply")
    equal(reply.asker, "Alice Smith", "asker")
    equal(reply.layer, "6843-8", "layer")
    equal(reply.zone, "1", "zone")
    equal(reply.canInvite, true, "can invite")
    reply = Protocol:ParseReply("heard Hylmew|-|-|-")
    expect(reply.layer == nil and reply.zone == nil and not reply.canInvite, "unknowns")
    equal(Protocol:ParseReply("same").kind, "same", "same")
    equal(Protocol:ParseReply("claim Hylmew"), nil, "other notes")

    equal(Protocol:ParseCreatureGUID("Creature-0-6843-0-8-299-000000001A"), "6843-8", "creature")
    equal(Protocol:ParseCreatureGUID("Vehicle-0-6843-0-8-299-000000001A"), "6843-8", "vehicle")
    equal(Protocol:ParseCreatureGUID("Player-1-00000001"), nil, "player")
    equal(Protocol:ParseCreatureGUID(world:Secret("Creature-0-6843-0-8-299-000000001A")), nil, "secret")
    expect(Protocol:SameLayer("6843-8", "6843-2"), "same server, same layer")
    expect(not Protocol:SameLayer("6843-8", "7088-8"), "another server, another layer")
    equal(Protocol:SenderKey("Alice Smith-Forever"), "Alice Smith", "sender key")
end)

-- Reading the layer ---------------------------------------------------------------------------

test("shows the layer read from creatures in the zone name's tooltip", function(world)
    Setup(world)
    equal(ZoneTooltipLine(world), world.L["map.layers.unknown"], "unknown")
    local pet = world:Creature(LAYER_B, ZONE_UID)
    world.playerControlled[pet] = true
    world:ShowNamePlate(pet)
    equal(ZoneTooltipLine(world), world.L["map.layers.unknown"], "a pet doesn't count")
    See(world, LAYER_A)
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("A"), "layer A")
    world:Target(world:Creature(LAYER_A, ZONE_UID))
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("A"), "same layer")
end)

test("needs two creatures of another layer to change a known one", function(world)
    Setup(world)
    See(world, LAYER_A)
    See(world, LAYER_B)
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("A"), "one creature")
    world:Mouseover(world:Creature(LAYER_B, ZONE_UID))
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("B"), "two creatures")
end)

test("forgets the layer at a transfer, without the creatures still in view", function(world)
    Setup(world)
    local old = See(world, LAYER_A)
    world:Transfer()
    equal(ZoneTooltipLine(world), world.L["map.layers.unknown"], "unknown after the transfer")
    world:Target(old)
    equal(ZoneTooltipLine(world), world.L["map.layers.unknown"], "a creature in view at the transfer")
    See(world, LAYER_B)
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("B"), "a new creature")
end)

test("reads the creatures still in view once a border is behind", function(world)
    Setup(world)
    See(world, LAYER_A)
    world:Fire("ZONE_CHANGED_NEW_AREA")
    equal(ZoneTooltipLine(world), world.L["map.layers.unknown"], "at the border")
    world:Elapse(10)
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("A"), "after a while")
end)

test("keeps the letters of a zone's layers", function(world)
    Setup(world)
    See(world, LAYER_A)
    world:Transfer()
    See(world, LAYER_B)
    world:Transfer()
    See(world, LAYER_A)
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("A"), "back on A")
end)

-- Asking ----------------------------------------------------------------------------------------

test("asks the zone's players for another layer from the player's menu", function(world)
    Setup(world)
    See(world, LAYER_A)
    ClickSwap(world)
    local query = world.whoQueries[1]
    equal(query.text, 'z-"Elwynn Forest"', "search text")
    equal(query.filters.uiMapIDs[1], 1, "map")
    equal(#query.filters.classIDs, 0, "every class")
    equal(LastWarning(world), world.L["map.layers.asking"], "notice")
    expect(world.whoToUi, "the answer goes to the who list")
    equal(ZoneTooltipLine(world), world.L["map.layers.asking"], "tooltip")
    expect(MenuEntry(world, "map.layers.stop"), "Cancel layer swap")

    world:AnswerWho({ Row("Bob-Forever", "Westfall"), Row("Hylmew Fortbras-Forever"), Row("Alice Smith-Forever") })
    expect(not world.whoToUi, "who list released")
    equal(
        Sent(world),
        "Alice Smith-Forever: inv layer <LS 1 not 6843-5 48.2,42.5>, Bob-Forever: inv layer <LS 1 not 6843-5 48.2,42.5>",
        "the zone's players first, without the player"
    )
end)

test("asks from the key binding", function(world)
    Setup(world)
    world:Bind("F5", "FOREVERENHANCED_SWAPLAYER")
    world:PressKey("F5")
    equal(#world.whoQueries, 1, "the key searches")
    equal(world.env.BINDING_NAME_FOREVERENHANCED_SWAPLAYER, world.L["map.layers.swap"], "binding name")
    equal(world.env.BINDING_HEADER_FOREVERENHANCED, "Forever Enhanced", "binding header")
end)

test("shows nameplates for a moment to read an unknown layer before asking", function(world)
    Setup(world)
    ClickSwap(world)
    equal(world.cvars.nameplateshowall, "1", "all nameplates")
    equal(world.cvars.nameplateshowfriendlynpcs, "1", "friendly NPCs")
    world:AnswerWho({ Row("Alice Smith-Forever") })
    equal(Sent(world), "", "waits for the layer")
    See(world, LAYER_A)
    equal(world.cvars.nameplateshowall, "0", "put back")
    equal(world.cvars.nameplateshowenemies, "1", "the player's own value")
    equal(Sent(world), "Alice Smith-Forever: inv layer <LS 1 not 6843-5 48.2,42.5>", "asks with the layer")
end)

test("asks without the layer when no creature shows", function(world)
    Setup(world)
    ClickSwap(world)
    world:AnswerWho({ Row("Alice Smith-Forever") })
    world:Elapse(3)
    equal(Sent(world), "Alice Smith-Forever: inv layer <LS 1 48.2,42.5>", "ask")
    equal(world.cvars.nameplateshowall, "0", "nameplates put back")
end)

test("paces the asks", function(world)
    Setup(world)
    See(world, LAYER_A)
    ClickSwap(world)
    local rows = {}
    for index = 1, 12 do
        table.insert(rows, Row("Player" .. index .. "-Forever"))
    end
    world:AnswerWho(rows)
    equal(#world.sentAddon, 8, "a burst")
    world:Elapse(1)
    equal(#world.sentAddon, 9, "then one a second")
    world:Elapse(3)
    equal(#world.sentAddon, 12, "all of them")
end)

test("searches one class at a time once the zone fills the list", function(world)
    Setup(world)
    See(world, LAYER_A)
    local function Ask(count)
        ClickSwap(world)
        local rows = {}
        for index = 1, count do
            table.insert(rows, Row("Player" .. #world.whoQueries .. "x" .. index .. "-Forever"))
        end
        world:AnswerWho(rows)
        world:ClickMenuEntry(MenuEntry(world, "map.layers.stop"))
        world:Elapse(10)
        local classIDs = world.whoQueries[#world.whoQueries].filters.classIDs
        return classIDs[1] or 0
    end
    equal(Ask(50), 0, "the whole zone")
    equal(Ask(20), 1, "first class")
    equal(Ask(20), 2, "next class")
    world:Fire("ZONE_CHANGED_NEW_AREA")
    equal(Ask(20), 0, "the whole zone again in another zone")
end)

test("says so when nobody answers or nobody is found", function(world)
    Setup(world)
    See(world, LAYER_A)
    ClickSwap(world)
    world:Elapse(5)
    equal(LastPrint(world), world.L["map.layers.noAnswer"], "no answer")
    world:Elapse(10)
    ClickSwap(world)
    world:NextFrame()
    expect(not FriendsFrame:IsEventRegistered("WHO_LIST_UPDATE"), "the last search's lists stay muted")
    world:AnswerWho({ Row("Hylmew Fortbras-Forever") })
    expect(not FriendsFrame:IsShown(), "friends frame closed")
    equal(LastPrint(world), world.L["map.layers.nobody"], "nobody")
end)

test("says why a click doesn't ask", function(world)
    AskFromA(world)
    world:ClickMenuEntry(MenuEntry(world, "map.layers.stop"))
    ClickSwap(world)
    equal(LastError(world), world.L["map.layers.cooldown"], "too soon")
    equal(#world.whoQueries, 1, "no search")
end)

test("says in chat how many players were asked when no one invites", function(world)
    AskFromA(world)
    equal(LastWarning(world), world.L["map.layers.askingCount"]:format(2), "notice")
    Receive(world, "heard Hylmew Fortbras|7088-1|1|-", "Bob-Forever")
    world:Elapse(14)
    expect(MenuEntry(world, "map.layers.stop"), "still asking")
    world:Elapse(1)
    equal(LastPrint(world), world.L["map.layers.noHost"]:format(2, 1), "outcome")
    expect(MenuEntry(world, "map.layers.swap"), "over")
end)

test("keeps Blizzard's who lists closed on the search's answer", function(world)
    AskFromA(world)
    expect(not FriendsFrame:IsShown(), "friends frame")
    expect(not LFGWhoListFrame:IsShown(), "group finder's who list")
    world:NextFrame()
    expect(FriendsFrame:IsEventRegistered("WHO_LIST_UPDATE"), "the friends frame hears again")
    expect(LFGWhoListFrame:IsEventRegistered("WHO_LIST_UPDATE"), "the who list hears again")
    world:AnswerWho({})
    expect(FriendsFrame:IsShown(), "the player's own search still opens it")
end)

test("leaves a who list the player looks at alone", function(world)
    Setup(world)
    See(world, LAYER_A)
    LFGWhoListFrame:Show()
    ClickSwap(world)
    expect(LFGWhoListFrame:IsEventRegistered("WHO_LIST_UPDATE"), "still hears")
    world:AnswerWho({ Row("Alice Smith-Forever") })
    expect(world.whoToUi, "answers still go to the list")
    expect(not FriendsFrame:IsShown(), "the friends frame stays closed")
end)

test("doesn't ask in a group or an instance", function(world)
    Setup(world)
    world.party = true
    equal(MenuEntry(world, "map.layers.swap"), nil, "no entry in a group")
    world:Bind("F5", "FOREVERENHANCED_SWAPLAYER")
    world:PressKey("F5")
    equal(LastError(world), world.L["map.layers.inGroup"], "the key in a group")
    equal(#world.whoQueries, 0, "no search")
    world.party = false
    world:StandAt(0, 0, 0, 90)
    equal(MenuEntry(world, "map.layers.swap"), nil, "no entry in an instance")
end)

test("stops asking", function(world)
    AskFromA(world)
    world:ClickMenuEntry(MenuEntry(world, "map.layers.stop"))
    expect(MenuEntry(world, "map.layers.swap"), "Swap layer again")
    world:ReceiveInvite("Alice Smith")
    equal(world.acceptedInvite, nil, "an invite after the stop")
end)

test("accepts the invite of a player asked, then leaves once moved", function(world)
    AskFromA(world)
    world:ReceiveInvite("Alice Smith")
    equal(world.acceptedInvite, "Alice Smith", "accepted")
    equal(LastWarning(world), world.L["map.layers.invited"]:format("Alice Smith"), "notice")
    equal(#world.hiddenPopups, 0, "the dialog stays until the group is joined")
    world:Elapse(world.SERVER_CONFIRM_SECONDS)
    expect(world.party, "in the group")
    equal(MenuEntry(world, "map.layers.swap"), nil, "no Swap layer in the host's group")
    expect(tContains(world.hiddenPopups, "PARTY_INVITE"), "dialog hidden")
    equal(world.declinedInvite, nil, "not declined")

    world:Elapse(1.3)
    world:Transfer()
    See(world, LAYER_B)
    equal(LastPrint(world), world.L["map.layers.moved"]:format("B"), "outcome")
    expect(world.party, "still in the group")
    world:Elapse(3)
    equal(world.leftGroups, 1, "left")
    expect(MenuEntry(world, "map.layers.swap"), "ready again")
end)

test("reads the new layer after leaving the group", function(world)
    AskFromA(world)
    world:ReceiveInvite("Alice Smith")
    world:Elapse(world.SERVER_CONFIRM_SECONDS)
    world:Transfer()
    world:Elapse(4)
    equal(world.leftGroups, 1, "left")
    See(world, LAYER_B)
    equal(LastPrint(world), world.L["map.layers.moved"]:format("B"), "outcome")
end)

test("drops the rest of the asks once invited", function(world)
    Setup(world)
    See(world, LAYER_A)
    ClickSwap(world)
    local rows = {}
    for index = 1, 12 do
        table.insert(rows, Row("Player" .. index .. "-Forever"))
    end
    world:AnswerWho(rows)
    world:ReceiveInvite("Player1")
    world:Elapse(5)
    local asks = 0
    for _, record in ipairs(world.sentAddon) do
        asks = asks + (record.prefix == "LayerSwap" and 1 or 0)
    end
    equal(asks, 8, "the burst only")
end)

test("leaves the invite to the player when not accepting automatically", function(world)
    Set(world, "accept", false)
    AskFromA(world)
    world:ReceiveInvite("Alice Smith")
    equal(world.acceptedInvite, nil, "not accepted")
    equal(#world.hiddenPopups, 0, "dialog shown")
    AcceptGroup()
    world:Elapse(world.SERVER_CONFIRM_SECONDS)
    world:Transfer()
    world:Elapse(4)
    equal(world.leftGroups, 1, "left once moved")
end)

test("says the layer didn't change when the move lands on the layer left", function(world)
    Setup(world)
    ClickSwap(world)
    world:AnswerWho({ Row("Alice Smith-Forever") })
    See(world, LAYER_A)
    world:ReceiveInvite("Alice Smith")
    world:Elapse(world.SERVER_CONFIRM_SECONDS)
    world:Transfer()
    See(world, LAYER_A)
    equal(LastPrint(world), world.L["map.layers.notMoved"], "outcome")
end)

test("says so when the group ends before the move", function(world)
    AskFromA(world)
    world:ReceiveInvite("Alice Smith")
    world:Elapse(world.SERVER_CONFIRM_SECONDS)
    world:LeaveGroup()
    equal(LastPrint(world), world.L["map.layers.leftGroup"], "outcome")
    expect(MenuEntry(world, "map.layers.swap"), "over")
end)

test("gives up on an accepted invite that never joins", function(world)
    AskFromA(world)
    world:ReceiveInvite("Alice Smith")
    DeclineGroup()
    world:Elapse(10)
    equal(LastPrint(world), world.L["map.layers.canceled"], "outcome")
    expect(MenuEntry(world, "map.layers.swap"), "over")
end)

test("ignores invites from players not asked", function(world)
    AskFromA(world)
    world:ReceiveInvite("Mallory")
    equal(world.acceptedInvite, nil, "not accepted")
end)

test("leaves a host on the player's layer, and skips it next time", function(world)
    AskFromA(world)
    world:ReceiveInvite("Alice Smith")
    world:Elapse(world.SERVER_CONFIRM_SECONDS)
    world:Elapse(15)
    equal(world.leftGroups, 1, "left")
    equal(LastPrint(world), world.L["map.layers.sameLayer"]:format("Alice Smith"), "outcome")
    ClickSwap(world)
    world:AnswerWho({ Row("Alice Smith-Forever"), Row("Carol-Forever") })
    equal(Sent(world), "Carol-Forever: inv layer <LS 1 not 6843-5 48.2,42.5>", "Alice skipped")
end)

test("asks a host that doesn't know its layer again, without the layer", function(world)
    AskFromA(world)
    Receive(world, "heard Hylmew Fortbras|-|1|h", "Alice Smith-Forever")
    Receive(world, "heard Hylmew Fortbras|-|1|-", "Bob-Forever")
    world:Elapse(1)
    equal(Sent(world), "Alice Smith-Forever: inv layer <LS 1 48.2,42.5>", "asked again")
    Receive(world, "heard Hylmew Fortbras|-|1|h", "Alice Smith-Forever")
    world:Elapse(1)
    equal(Sent(world), "", "once")
end)

test("asks the hosts that answered before first", function(world)
    AskFromA(world)
    Receive(world, "same", "Bob-Forever")
    world:ClickMenuEntry(MenuEntry(world, "map.layers.stop"))
    world:Elapse(10)
    ClickSwap(world)
    world:AnswerWho({ Row("Alice Smith-Forever"), Row("Bob-Forever"), Row("Carol-Forever") })
    equal(
        Sent(world),
        "Bob-Forever: inv layer <LS 1 not 6843-5 48.2,42.5>, Carol-Forever: inv layer <LS 1 not 6843-5 48.2,42.5>",
        "Bob first; Alice asked lately without answering"
    )
end)

test("hides the game's line for a player asked who just logged off", function(world)
    AskFromA(world)
    local function Hidden(name)
        for _, filter in ipairs(world.chatFilters.CHAT_MSG_SYSTEM or {}) do
            if filter(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format(name)) then
                return true
            end
        end
        return false
    end
    expect(Hidden("Alice Smith-Forever"), "a player asked")
    expect(not Hidden("Zed"), "anyone else")
    world:Elapse(16)
    expect(not Hidden("Alice Smith-Forever"), "a while later")
end)

-- Hosting ----------------------------------------------------------------------------------------

local ASK_FROM_B = "inv layer <LS 1 not 7088-3 52.0,40.0>"

local function Host(world)
    Setup(world)
    Set(world, "host", true)
    See(world, LAYER_A)
end

test("doesn't host unless the player turns it on", function(world)
    Setup(world)
    See(world, LAYER_A)
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(Sent(world), "", "no reply")
    equal(#world.invites, 0, "no invite")
end)

test("invites a player of the zone asking from another layer", function(world)
    Host(world)
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(Sent(world), "Alice Smith-Forever: heard Alice Smith|6843-5|1|h", "reply")
    equal(world.invites[1], "Alice Smith", "invite")
end)

test("says so to a player asking from the same layer", function(world)
    Host(world)
    Receive(world, "inv layer <LS 1 not 6843-9 52.0,40.0>", "Alice Smith-Forever")
    equal(Sent(world), "Alice Smith-Forever: heard Alice Smith|6843-5|1|h, Alice Smith-Forever: same", "replies")
    equal(#world.invites, 0, "no invite")
end)

test("keeps the layer an asker leaves for its ask sent again without it", function(world)
    Host(world)
    Receive(world, "inv layer <LS 1 not 6843-9 52.0,40.0>", "Alice Smith-Forever")
    world:Elapse(1)
    Receive(world, "inv layer <LS 1 52.0,40.0>", "Alice Smith-Forever")
    equal(#world.invites, 0, "no invite")
end)

test("only answers askers it can move", function(world)
    Host(world)
    Receive(world, "inv layer <LS 5 not 7088-3 52.0,40.0>", "Alice Smith-Forever")
    equal(Sent(world), "", "another zone")
    Receive(world, "inv layer <LS 1 want 7088-3 52.0,40.0>", "Bob-Forever")
    equal(#world.invites, 0, "wants another layer")
    Receive(world, "inv layer <LS 1 not 7088-3 not 6843-2 52.0,40.0>", "Carol-Forever")
    equal(#world.invites, 0, "a layer the asker has seen")
    Receive(world, "inv layer", "Dan-Forever")
    equal(#world.invites, 0, "no zone")
end)

test("doesn't invite without knowing its own layer", function(world)
    Setup(world)
    Set(world, "host", true)
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(Sent(world), "Alice Smith-Forever: heard Alice Smith|-|1|h", "reply without layer")
    equal(#world.invites, 0, "no invite")
end)

test("doesn't invite while busy", function(world)
    Host(world)
    world:EnterCombat()
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(Sent(world), "Alice Smith-Forever: heard Alice Smith|6843-5|1|-", "in combat")
    world:LeaveCombat()
    world.lfgListed = true
    Receive(world, ASK_FROM_B, "Bob-Forever")
    equal(#world.invites, 0, "listed in the group finder")
    world.lfgListed = false
    world:JoinGroup("Zed")
    Receive(world, ASK_FROM_B, "Carol-Forever")
    equal(#world.invites, 0, "in someone else's group")
end)

test("invites a player once a minute, and six players in ten minutes", function(world)
    Host(world)
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(#world.invites, 1, "once")
    world:Elapse(61)
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(#world.invites, 2, "a minute later")
    for index = 1, 5 do
        world:Elapse(61)
        Receive(world, ASK_FROM_B, "Player" .. index .. "-Forever")
    end
    equal(#world.invites, 6, "six")
    world:Elapse(61)
    Receive(world, ASK_FROM_B, "Bob-Forever")
    equal(#world.invites, 6, "no seventh")
end)

test("doesn't invite again a guest that moved the player", function(world)
    Host(world)
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    world:GuestJoins("Alice Smith")
    world:Transfer()
    See(world, LAYER_A)
    world:GuestLeaves("Alice Smith")
    world:Elapse(61)
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(#world.invites, 1, "not invited again")

    Receive(world, ASK_FROM_B, "Bob-Forever")
    world:GuestJoins("Bob")
    world:Transfer(true)
    world:GuestLeaves("Bob")
    world:Elapse(61)
    See(world, LAYER_A)
    Receive(world, ASK_FROM_B, "Bob-Forever")
    equal(#world.invites, 3, "a world refresh is nobody's doing")
end)

-- Lifecycle ---------------------------------------------------------------------------------------

test("only shows the layer while LayerSwap is loaded", function(world)
    Setup(world)
    Set(world, "enabled", false)
    world.loadedAddOns.LayerSwap = true
    Set(world, "enabled", true)
    Set(world, "host", true)
    See(world, LAYER_A)
    equal(ZoneTooltipLine(world), world.L["map.layers.layer"]:format("A"), "layer shown")
    equal(MenuEntry(world, "map.layers.swap"), nil, "no menu entry")
    Receive(world, ASK_FROM_B, "Alice Smith-Forever")
    equal(Sent(world), "", "no reply")
    equal(#world.invites, 0, "no invite")
end)

test("turning it off puts everything back", function(world)
    Setup(world)
    ClickSwap(world)
    Set(world, "enabled", false)
    equal(world.cvars.nameplateshowall, "0", "nameplates put back")
    expect(not world.whoToUi, "who list released")
    equal(#(world.chatFilters.CHAT_MSG_SYSTEM or {}), 0, "chat filter removed")
    equal(MenuEntry(world, "map.layers.swap"), nil, "no menu entry")
    equal(ZoneTooltipLine(world), nil, "no tooltip line")
    world:AnswerWho({ Row("Alice Smith-Forever") })
    world:Elapse(5)
    equal(Sent(world), "", "no asks")
    equal(world:TickerCount(), 0, "tickers")
end)
