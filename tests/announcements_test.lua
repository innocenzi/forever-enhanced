-- Quest helpers, Hide quest addon announcements (Questie and Polestar): the
-- group chat filter and the chat bubbles, on its own or with Objective
-- announcements.

local function Set(world, key, value)
    world:Setting("quests.helpers." .. key):SetValue(value)
end

local LINK = "|cffffff00|Hquest:1:10|h[Wolves Across the Border]|h|r"

local MESSAGES = {
    "{rt1} Questie: 2/2 Young Wolf slain for " .. LINK .. "!",
    "{rt1} Questie : 2/2 Jeune loup tué pour " .. LINK .. " !",
    "{звезда} Questie: 2/2 Young Wolf slain for " .. LINK .. "!",
    "|TInterface\\Addons\\Questie\\Icons\\questie.png:0|t 2/2 Young Wolf slain for " .. LINK .. "!",
    "{rt1} Polestar: " .. LINK .. " is ready to turn in",
    "{rt1} Polestar : " .. LINK .. " est prête à rendre",
    "{звезда} Polestar: " .. LINK .. " Young Wolf 2/2",
    "|TInterface\\AddOns\\Polestar\\Media\\UI\\logo:0|t Polestar: " .. LINK .. " is ready to turn in",
}

-- The option is off by default.
local function HideAnnouncements(world)
    Set(world, "hideAnnouncements", true)
end

test("leaves quest addon announcements alone by default", function(world)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "shown")
    equal(#(world.chatFilters.CHAT_MSG_PARTY or {}), 0, "no filter")
end)

test("hides other players' quest addon announcements in group chat", function(world)
    HideAnnouncements(world)
    for _, message in ipairs(MESSAGES) do
        expect(world:ReceiveChat("CHAT_MSG_PARTY", message, "Arthas-Forever"), "hidden: " .. message)
    end
    expect(world:ReceiveChat("CHAT_MSG_RAID_LEADER", MESSAGES[1], "Jaina-Other"), "hidden in raids")
    expect(world:ReceiveChat("CHAT_MSG_INSTANCE_CHAT", MESSAGES[1], "Jaina-Other"), "hidden in instances")
end)

test("hides quest addon announcements whether or not the player announces", function(world)
    HideAnnouncements(world)
    expect(not world.ns:GetFeature("quests", "announce"):IsActive(), "announcements off")
    expect(world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "hidden")
    world:Setting("quests.announce.enabled"):SetValue(true)
    expect(world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "still hidden")
    equal(#world.chatFilters.CHAT_MSG_PARTY, 1, "one filter")
end)

test("keeps chat that only mentions these addons, and the player's own announcements", function(world)
    HideAnnouncements(world)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", "anyone using Questie: the addon?", "Arthas-Forever"), "mention")
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", "Polestar: is it any good?", "Arthas-Forever"), "Polestar mention")
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[5], "Hylmew-Forever"), "own Polestar line")
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Hylmew-Forever"), "own announcement")
end)

test("shows quest addon announcements again with the option off", function(world)
    HideAnnouncements(world)
    Set(world, "hideAnnouncements", false)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "shown")
    HideAnnouncements(world)
    expect(world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "hidden again")
    equal(#world.chatFilters.CHAT_MSG_PARTY, 1, "one filter")
end)

test("shows quest addon announcements again with the feature off", function(world)
    HideAnnouncements(world)
    Set(world, "enabled", false)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "shown")
    Set(world, "enabled", true)
    expect(world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "hidden again")
end)

test("keeps the option off across a feature restart", function(world)
    Set(world, "hideAnnouncements", false)
    Set(world, "enabled", false)
    Set(world, "enabled", true)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever"), "shown")
end)

test("hides the chat bubbles of other players' quest addon announcements", function(world)
    HideAnnouncements(world)
    for _, message in ipairs(MESSAGES) do
        world:ExpireChatBubbles()
        world:ReceiveChat("CHAT_MSG_PARTY", message, "Arthas-Forever")
        world:NextFrame()
        expect(not world:IsChatBubbleVisible(message), "hidden: " .. message)
    end
end)

test("keeps the bubbles of other chat and of the player's own announcements", function(world)
    HideAnnouncements(world)
    world:ReceiveChat("CHAT_MSG_PARTY", "anyone using Questie: the addon?", "Arthas-Forever")
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Hylmew-Forever")
    world:NextFrame()
    expect(world:IsChatBubbleVisible("anyone using Questie: the addon?"), "mention")
    expect(world:IsChatBubbleVisible(MESSAGES[1]), "own announcement")
end)

test("shows a hidden bubble again once the client reuses it", function(world)
    HideAnnouncements(world)
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    world:ExpireChatBubbles()
    world:NextFrame()
    world:ReceiveChat("CHAT_MSG_PARTY", "lfg deadmines", "Arthas-Forever")
    world:NextFrame()
    equal(#world.chatBubbles, 1, "reused")
    expect(world:IsChatBubbleVisible("lfg deadmines"), "shown")
end)

-- Measured: right after reusing a bubble, the client may hide it for a moment.
test("keeps a bubble hidden while the client hides it for a moment", function(world)
    HideAnnouncements(world)
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    local bubble = world.chatBubbles[1]
    bubble:Hide()
    world:NextFrame()
    world:Elapse(0.5)
    world:NextFrame()
    bubble:Show()
    world:NextFrame()
    expect(not world:IsChatBubbleVisible(MESSAGES[1]), "still hidden")
end)

test("shows a bubble again once the client has kept it hidden", function(world)
    HideAnnouncements(world)
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    world:ExpireChatBubbles()
    world:NextFrame()
    world:Elapse(3)
    world:NextFrame()
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Hylmew-Forever")
    world:NextFrame()
    equal(#world.chatBubbles, 1, "reused")
    expect(world:IsChatBubbleVisible(MESSAGES[1]), "the player's own announcement")
end)

test("stops looking for a bubble that never shows up", function(world)
    HideAnnouncements(world)
    world.bubblesForbidden = true
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    expect(world:IsChatBubbleVisible(MESSAGES[1]), "forbidden bubbles stay")
    world:Elapse(2)
    world.bubblesForbidden = false
    world:ExpireChatBubbles()
    world:ShowChatBubble(MESSAGES[1])
    world:NextFrame()
    expect(world:IsChatBubbleVisible(MESSAGES[1]), "a later bubble with the same text stays")
end)

test("shows hidden bubbles again when the option is turned off", function(world)
    HideAnnouncements(world)
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    Set(world, "hideAnnouncements", false)
    expect(world:IsChatBubbleVisible(MESSAGES[1]), "shown")
    world:ReceiveChat("CHAT_MSG_PARTY", MESSAGES[2], "Arthas-Forever")
    world:NextFrame()
    expect(world:IsChatBubbleVisible(MESSAGES[2]), "new ones stay")
end)
