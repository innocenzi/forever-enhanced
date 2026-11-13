-- Quest Helpers: five parts, each behind its toggle.
--
-- "nearby": keeps the quests nearest to the player in the objective tracker
-- and untracks the farthest ones as the player moves. It takes over the
-- objective tracker: the player opts in.
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
--   ranking.lua    nearby: which quests should be tracked, closest first, and their order
--   watches.lua    nearby: the watch list: applying and ordering it, manual tracks, dismissals
--   refresh.lua    nearby: events and ticker, coalesced into one evaluation per frame
--   sparkle.lua    sparkles: the CVar behind the sparkle, set again after graphics changes
--   needs.lua      objectives, leftovers: the item objectives of the quest log, by item name
--   leftovers.lua  leftovers: which quests use each quest item, and the bag mark
--   tooltip.lua    objectives, leftovers: the tooltip lines
--   announcements.lua  hideAnnouncements: the group chat filter for Questie and Polestar announcements

local _, ns = ...

local Helpers = ns:RegisterFeature("quests", "helpers", {
    order = 1,
    settings = {
        { key = "objectives", type = "toggle", default = true },
        { key = "leftovers", type = "toggle", default = true },
        { key = "leftoverMark", type = "toggle", default = true, requires = { leftovers = true } },
        { key = "sparkles", type = "toggle", default = true },
        { key = "nearby", type = "toggle", default = false },
        {
            key = "scope",
            type = "dropdown",
            default = "closest",
            options = { "closest", "range", "zone" },
            requires = { nearby = true },
        },
        {
            key = "range",
            type = "slider",
            default = 500,
            min = 100,
            max = 2000,
            step = 50,
            requires = { scope = "range" },
        },
        { key = "count", type = "slider", default = 5, min = 1, max = 25, step = 1, requires = { nearby = true } },
        { key = "sort", type = "toggle", default = false, requires = { nearby = true } },
        { key = "dungeons", type = "toggle", default = true, requires = { nearby = true } },
        { key = "keepManual", type = "toggle", default = false, requires = { nearby = true } },
        { key = "hideAnnouncements", type = "toggle", default = false },
    },
    presets = {
        minimal = {
            enabled = true,
            objectives = true,
            leftovers = true,
            leftoverMark = true,
            sparkles = true,
            nearby = false,
            hideAnnouncements = false,
        },
        enhanced = {
            enabled = true,
            objectives = true,
            leftovers = true,
            leftoverMark = true,
            sparkles = true,
            nearby = true,
            hideAnnouncements = true,
        },
    },
})

-- The nearby quests part: Refresh checks Helpers:IsPartActive("nearby").
local Nearby = {}

function Nearby:Enable()
    Helpers.Refresh:Enable()
end

function Nearby:Disable()
    Helpers.Refresh:Disable()
    Helpers.Watches:Reset()
end

-- The objectives part: its tooltip lines read the shared objectives index.
local Objectives = {}

function Objectives:Enable()
    Helpers.Needs:Acquire("objectives")
end

function Objectives:Disable()
    Helpers.Needs:Release("objectives")
end

function Helpers:SyncParts()
    self:SyncPart("nearby", Nearby)
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
    if self:IsPartActive("nearby") then
        self.Refresh:Request()
    end
    if key == "leftoverMark" and self:IsPartActive("leftovers") then
        ns:RefreshItemButtons()
    end
end

function Helpers:OnDisable()
    self:SyncParts()
end
