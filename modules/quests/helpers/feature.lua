-- Quest Helpers: four parts, each behind its toggle. Tracking the nearest
-- quests is a feature of its own (quests.tracking).
--
-- "sparkles": keeps the game's sparkle on quest items the player can loot.
-- Picking a graphics preset switches it off; this switches it back on.
-- "objectives": item tooltips name the quests of the log that need the item,
-- with the player's progress (food or trade goods a quest asks for are
-- ordinary items, with nothing else to tell them apart).
-- "leftovers": quest items whose quests are all completed say so in their
-- tooltip, with a check mark in the bags ("leftoverMark"). The client has no
-- quest database: which quests use an item is learned as the player plays,
-- account-wide.
-- "hideAnnouncements": hides other players' Questie and Polestar announcements
-- in group chat (whether or not the player announces their own objectives).
--
-- Files of this slice:
--   feature.lua    registration, schema and lifecycle (this file)
--   locales.lua    strings
--   sparkle.lua    sparkles: the CVar behind the sparkle, set again after graphics changes
--   needs.lua      objectives, leftovers: the item objectives of the quest log, by item name
--   leftovers.lua  leftovers: which quests use each quest item, and the bag mark
--   tooltip.lua    objectives, leftovers: the tooltip lines
--   announcements.lua  hideAnnouncements: the group chat filter for Questie and Polestar announcements

local _, ns = ...

local Helpers = ns:RegisterFeature("quests", "helpers", {
    page = "quests",
    order = 1,
    settings = {
        { key = "objectives", type = "toggle", default = true },
        { key = "leftovers", type = "toggle", default = true },
        { key = "leftoverMark", type = "toggle", default = true, requires = { leftovers = true } },
        { key = "sparkles", type = "toggle", default = true },
        { key = "hideAnnouncements", type = "toggle", default = false },
    },
    presets = {
        minimal = {
            enabled = true,
            objectives = true,
            leftovers = true,
            leftoverMark = true,
            sparkles = true,
            hideAnnouncements = false,
        },
        enhanced = {
            enabled = true,
            objectives = true,
            leftovers = true,
            leftoverMark = true,
            sparkles = true,
            hideAnnouncements = true,
        },
    },
})

-- The objectives part: its tooltip lines read the shared objectives index.
local Objectives = {}

function Objectives:Enable()
    Helpers.Needs:Acquire("objectives")
end

function Objectives:Disable()
    Helpers.Needs:Release("objectives")
end

function Helpers:SyncParts()
    self:SyncPart("sparkles", self.Sparkle)
    self:SyncPart("objectives", Objectives)
    self:SyncPart("leftovers", self.Leftovers)
    self:SyncPart("hideAnnouncements", self.AnnouncementFilter)
end

function Helpers:OnEnable()
    self:SyncParts()
end

function Helpers:OnSettingChanged(key)
    self:SyncParts()
    if key == "leftoverMark" and self:IsPartActive("leftovers") then
        ns:RefreshItemButtons()
    end
end

function Helpers:OnDisable()
    self:SyncParts()
end
