-- Objective Announcements: completion detection, template, channels, solo
-- preview, lifecycle, and the Hide Questie Announcements chat filter. The
-- feature is off by default; every test but the first turns it on.

local function Set(world, key, value)
    world:Setting("quests.announce." .. key):SetValue(value)
end

test("is off by default", function(world)
    local quest = { questID = 1, title = "Wolves", objectives = { world:Objective("Wolf Pelt", 1) } }
    world:SetQuests({ quest })
    world.party = true
    world:Fire("QUEST_LOG_UPDATE")
    world:Progress(1, 1, 1)
    equal(#world.sentChat, 0, "nothing sent")
    expect(not world.ns:GetFeature("quests", "announce"):IsActive(), "inactive")
end)

local baseTest = test
local function test(name, func)
    baseTest(name, function(world)
        Set(world, "enabled", true)
        func(world)
    end)
end

local LINK = "|cffffff00|Hquest:1:10|h[Wolves Across the Border]|h|r"

-- Quest 1 with two objectives (0/2 wolves, 0/1 pelt), the player in a party.
-- The first QUEST_LOG_UPDATE records the log, like the client's at login.
local function WithQuest(world)
    world:SetQuests({
        {
            questID = 1,
            title = "Wolves Across the Border",
            objectives = { world:Objective("Young Wolf slain", 2), world:Objective("Wolf Pelt", 1) },
        },
    })
    world.party = true
    world:Fire("QUEST_LOG_UPDATE")
end

local function Sent(world)
    local messages = {}
    for index, sent in ipairs(world.sentChat) do
        messages[index] = sent.chatType .. ": " .. sent.message
    end
    return table.concat(messages, " | ")
end

local function Default(world, objective, current, total)
    return world.ns:GetFeature("quests", "announce").Message:Format(world.L["quests.announce.template.default"], {
        objective = objective,
        current = tostring(current),
        total = tostring(total),
        quest = LINK,
    })
end

test("announces a completed objective to the party with the default message", function(world)
    WithQuest(world)
    world:Progress(1, 1, 1)
    equal(Sent(world), "", "progress alone is not announced")

    world:Progress(1, 1, 2)
    equal(Sent(world), "PARTY: " .. Default(world, "Young Wolf slain", 2, 2), "sent")
    expect(Default(world, "x", 1, 1):find("x", 1, true), "the default message names the objective")
end)

test("announces each objective once while its quest stays in the log", function(world)
    WithQuest(world)
    world:Progress(1, 2, 1)
    world:Progress(1, 2, 0)
    world:Progress(1, 2, 1)
    world:Fire("QUEST_LOG_UPDATE")
    equal(#world.sentChat, 1, "announcements")

    world:Progress(1, 1, 2)
    equal(#world.sentChat, 2, "the other objective is announced")
end)

test("announces again after the quest is abandoned and taken back", function(world)
    WithQuest(world)
    world:Progress(1, 2, 1)
    local quest = world.questLog[1]
    world:SetQuests({})
    world:Fire("QUEST_REMOVED", 1)
    world:Fire("QUEST_LOG_UPDATE")

    quest.objectives = { world:Objective("Young Wolf slain", 2), world:Objective("Wolf Pelt", 1) }
    world:SetQuests({ quest })
    world:Fire("QUEST_LOG_UPDATE")
    world:Progress(1, 2, 1)
    equal(#world.sentChat, 2, "announcements")
end)

test("objectives already done are not announced", function(world)
    world.party = true
    world:SetQuests({
        { questID = 1, title = "Done Already", objectives = { world:Objective("Wolf Pelt", 1, 1) } },
    })
    world:Fire("QUEST_LOG_UPDATE")

    world:AcceptQuest({ questID = 2, title = "Accepted Done", objectives = { world:Objective("Bear Pelt", 1, 1) } })
    world:Fire("QUEST_LOG_UPDATE")
    equal(Sent(world), "", "nothing sent")
end)

test("waits for the quest data before recording a quest", function(world)
    world.party = true
    world:SetQuests({ { questID = 1, title = "Loading" } })
    world:Fire("QUEST_LOG_UPDATE")

    -- The data arrives with the objective already done: recorded, not announced.
    world.questLog[1].objectives = { world:Objective("Wolf Pelt", 1, 1) }
    world:Fire("QUEST_LOG_UPDATE")
    equal(Sent(world), "", "nothing sent")
end)

test("fills the variables of a custom message and keeps raid target icons", function(world)
    Set(world, "template", "{rt1} {objective}: {current}/{total} - {quest} {unknown}")
    WithQuest(world)
    world:Progress(1, 1, 2)
    equal(Sent(world), "PARTY: {rt1} Young Wolf slain: 2/2 - " .. LINK .. " {unknown}", "sent")
end)

test("strips the counter from either objective text form", function(world)
    Set(world, "template", "{objective}")
    WithQuest(world)
    world:Progress(1, 1, 2, "Young Wolf slain: 2/2")
    world:Progress(1, 2, 1, "1/1 Wolf Pelt")
    equal(Sent(world), "PARTY: Young Wolf slain | PARTY: Wolf Pelt", "sent")
end)

test("resolves grammar codes, which chat refuses", function(world)
    Set(world, "template", "{objective}")
    WithQuest(world)
    world:Progress(1, 1, 2, "2/2 |4Young Wolf:Young Wolves; slain")
    world:Progress(1, 2, 1, "Wolf Pelt: 1 |4pelt:pelts;")
    equal(Sent(world), "PARTY: Young Wolves slain | PARTY: Wolf Pelt: 1 pelt", "sent")
end)

test("drops the quest link when the message would be too long", function(world)
    Set(world, "template", ("x"):rep(220) .. " {quest}")
    WithQuest(world)
    world:Progress(1, 1, 2)
    equal(world.sentChat[1].message, ("x"):rep(220) .. " Wolves Across the Border", "title instead of the link")

    Set(world, "template", ("é"):rep(130))
    world:Progress(1, 2, 1)
    local message = world.sentChat[2].message
    equal(#message, 254, "cut to fit without splitting a character")
end)

test("prefers the instance group, unless set to the party only", function(world)
    WithQuest(world)
    world.instanceGroup = true
    world:Progress(1, 1, 2)
    equal(world.sentChat[1].chatType, "INSTANCE_CHAT", "instance group first")

    Set(world, "channel", "party")
    world:Progress(1, 2, 1)
    equal(world.sentChat[2].chatType, "PARTY", "party only")

    world.party = false
    world:AcceptQuest({ questID = 2, title = "Bears", objectives = { world:Objective("Bear Pelt", 1) } })
    world:Fire("QUEST_LOG_UPDATE")
    world:Progress(2, 1, 1)
    equal(#world.sentChat, 2, "nothing sent from an instance group without a party")
    equal(#world.prints, 0, "nothing shown either")
end)

test("stays quiet outside a group unless set to show the message", function(world)
    WithQuest(world)
    world.party = false
    world:Progress(1, 1, 2)
    equal(#world.sentChat + #world.prints, 0, "nothing sent or shown")

    Set(world, "solo", true)
    world:Progress(1, 2, 1)
    equal(#world.sentChat, 0, "nothing sent")
    equal(world.prints[1], Default(world, "Wolf Pelt", 1, 1), "shown to the player")
end)

test("disabling stops the announcements", function(world)
    WithQuest(world)
    Set(world, "enabled", false)
    world:Progress(1, 1, 2)
    Set(world, "enabled", true)
    world:Progress(1, 2, 1)
    equal(Sent(world), "PARTY: " .. Default(world, "Wolf Pelt", 1, 1), "only after enabling again")
end)

-- Hide Questie Announcements -----------------------------------------------------------

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
