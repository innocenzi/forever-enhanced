-- Objective Announcements: tells the group when one of the player's quest
-- objectives is completed, with a message the player writes (like Questie).
-- Hiding other players' Questie announcements is Quest helpers' "hideQuestie".
--
-- Files of this slice:
--   feature.lua     registration, schema and lifecycle (this file)
--   locales.lua     strings, including the default message
--   message.lua     fills the message template and sends it
--   objectives.lua  watches the quest log for objectives that get completed

local _, ns = ...

local Announce = ns:RegisterFeature("quests", "announce", {
    order = 2,
    -- It speaks in group chat: the player opts in.
    enabledByDefault = false,
    settings = {
        -- Default from the locale (quests.announce.template.default).
        { key = "template", type = "text" },
        { key = "channel", type = "dropdown", default = "instance", options = { "instance", "party" } },
    },
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true },
    },
})

function Announce:OnEnable()
    self.Objectives:Enable()
end

function Announce:OnDisable()
    self.Objectives:Disable()
end
