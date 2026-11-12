-- Objective Announcements: completion detection, template, channels, solo
-- preview and lifecycle. The feature is off by default; every test but the
-- first turns it on.

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
