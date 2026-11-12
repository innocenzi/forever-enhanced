-- Quest helpers, Hide Questie announcements: the group chat filter and the
-- chat bubbles, on its own or with Objective announcements.

local function Set(world, key, value)
    world:Setting("quests.helpers." .. key):SetValue(value)
end

local LINK = "|cffffff00|Hquest:1:10|h[Wolves Across the Border]|h|r"

local QUESTIE_MESSAGES = {
    "{rt1} Questie: 2/2 Young Wolf slain for " .. LINK .. "!",
    "{rt1} Questie : 2/2 Jeune loup tué pour " .. LINK .. " !",
    "{звезда} Questie: 2/2 Young Wolf slain for " .. LINK .. "!",
    "|TInterface\\Addons\\Questie\\Icons\\questie.png:0|t 2/2 Young Wolf slain for " .. LINK .. "!",
}

-- The option is off by default.
local function HideQuestie(world)
    Set(world, "hideQuestie", true)
end

test("leaves Questie announcements alone by default", function(world)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "shown")
    equal(#(world.chatFilters.CHAT_MSG_PARTY or {}), 0, "no filter")
end)

test("hides other players' Questie announcements in group chat", function(world)
    HideQuestie(world)
    for _, message in ipairs(QUESTIE_MESSAGES) do
        expect(world:ReceiveChat("CHAT_MSG_PARTY", message, "Arthas-Forever"), "hidden: " .. message)
    end
    expect(world:ReceiveChat("CHAT_MSG_RAID_LEADER", QUESTIE_MESSAGES[1], "Jaina-Other"), "hidden in raids")
    expect(world:ReceiveChat("CHAT_MSG_INSTANCE_CHAT", QUESTIE_MESSAGES[1], "Jaina-Other"), "hidden in instances")
end)

test("hides Questie announcements whether or not the player announces", function(world)
    HideQuestie(world)
    expect(not world.ns:GetFeature("quests", "announce"):IsActive(), "announcements off")
    expect(world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "hidden")
    world:Setting("quests.announce.enabled"):SetValue(true)
    expect(world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "still hidden")
    equal(#world.chatFilters.CHAT_MSG_PARTY, 1, "one filter")
end)

test("keeps chat that only mentions Questie, and the player's own announcements", function(world)
    HideQuestie(world)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", "anyone using Questie: the addon?", "Arthas-Forever"), "mention")
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Hylmew-Forever"), "own announcement")
end)

test("shows Questie announcements again with the option off", function(world)
    HideQuestie(world)
    Set(world, "hideQuestie", false)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "shown")
    HideQuestie(world)
    expect(world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "hidden again")
    equal(#world.chatFilters.CHAT_MSG_PARTY, 1, "one filter")
end)

test("shows Questie announcements again with the feature off", function(world)
    HideQuestie(world)
    Set(world, "enabled", false)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "shown")
    Set(world, "enabled", true)
    expect(world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "hidden again")
end)

test("keeps the option off across a feature restart", function(world)
    Set(world, "hideQuestie", false)
    Set(world, "enabled", false)
    Set(world, "enabled", true)
    expect(not world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever"), "shown")
end)

test("hides the chat bubbles of other players' Questie announcements", function(world)
    HideQuestie(world)
    for _, message in ipairs(QUESTIE_MESSAGES) do
        world:ExpireChatBubbles()
        world:ReceiveChat("CHAT_MSG_PARTY", message, "Arthas-Forever")
        world:NextFrame()
        expect(not world:IsChatBubbleVisible(message), "hidden: " .. message)
    end
end)

test("keeps the bubbles of other chat and of the player's own announcements", function(world)
    HideQuestie(world)
    world:ReceiveChat("CHAT_MSG_PARTY", "anyone using Questie: the addon?", "Arthas-Forever")
    world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Hylmew-Forever")
    world:NextFrame()
    expect(world:IsChatBubbleVisible("anyone using Questie: the addon?"), "mention")
    expect(world:IsChatBubbleVisible(QUESTIE_MESSAGES[1]), "own announcement")
end)

test("shows a hidden bubble again once the client reuses it", function(world)
    HideQuestie(world)
    world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    world:ExpireChatBubbles()
    world:NextFrame()
    world:ReceiveChat("CHAT_MSG_PARTY", "lfg deadmines", "Arthas-Forever")
    world:NextFrame()
    equal(#world.chatBubbles, 1, "reused")
    expect(world:IsChatBubbleVisible("lfg deadmines"), "shown")
end)

test("stops looking for a bubble that never shows up", function(world)
    HideQuestie(world)
    world.bubblesForbidden = true
    world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    expect(world:IsChatBubbleVisible(QUESTIE_MESSAGES[1]), "forbidden bubbles stay")
    world:Elapse(2)
    world.bubblesForbidden = false
    world:ExpireChatBubbles()
    world:ShowChatBubble(QUESTIE_MESSAGES[1])
    world:NextFrame()
    expect(world:IsChatBubbleVisible(QUESTIE_MESSAGES[1]), "a later bubble with the same text stays")
end)

test("shows hidden bubbles again when the option is turned off", function(world)
    HideQuestie(world)
    world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[1], "Arthas-Forever")
    world:NextFrame()
    Set(world, "hideQuestie", false)
    expect(world:IsChatBubbleVisible(QUESTIE_MESSAGES[1]), "shown")
    world:ReceiveChat("CHAT_MSG_PARTY", QUESTIE_MESSAGES[2], "Arthas-Forever")
    world:NextFrame()
    expect(world:IsChatBubbleVisible(QUESTIE_MESSAGES[2]), "new ones stay")
end)
