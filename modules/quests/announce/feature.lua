-- Objective Announcements: tells the group when one of the player's quest
-- objectives is completed, with a message the player writes (like Questie),
-- and optionally hides other players' Questie announcements.
--
-- Files of this slice:
--   feature.lua     registration, schema and lifecycle (this file)
--   locales.lua     strings, including the default message
--   message.lua     fills the message template and sends it
--   objectives.lua  watches the quest log for objectives that get completed
--   questie.lua     the group chat filter for Questie announcements

local _, ns = ...

local Announce = ns:RegisterFeature("quests", "announce", {
    order = 2,
    -- It speaks in group chat: the player opts in.
    enabledByDefault = false,
    settings = {
        -- Default from the locale (quests.announce.template.default).
        { key = "template", type = "text" },
        { key = "channel", type = "dropdown", default = "instance", options = { "instance", "party" } },
        { key = "solo", type = "toggle", default = false },
        { key = "hideQuestie", type = "toggle", default = false },
    },
})

function Announce:OnEnable()
    self.Objectives:Enable()
    self.QuestieFilter:SetEnabled(self:GetSetting("hideQuestie"))
end

function Announce:OnDisable()
    self.Objectives:Disable()
    self.QuestieFilter:SetEnabled(false)
end

function Announce:OnSettingChanged(key, value)
    if key == "hideQuestie" then
        self.QuestieFilter:SetEnabled(value)
    end
end
