-- Quest Helpers: three parts, each behind its toggle.
--
-- "nearby": keeps the quests nearest to the player in the objective tracker
-- and untracks the farthest ones as the player moves. It takes over the
-- objective tracker: the player opts in.
-- "sparkles": keeps the game's sparkle on quest items the player can loot.
-- Picking a graphics preset switches it off; this switches it back on.
-- "objectives": item tooltips name the quests of the log that need the item,
-- with the player's progress (food or trade goods a quest asks for are
-- ordinary items, with nothing else to tell them apart).
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   ranking.lua  nearby: which quests should be tracked, closest first
--   watches.lua  nearby: the watch list: applying it, manual tracks, dismissals
--   refresh.lua  nearby: events and ticker, coalesced into one evaluation per frame
--   sparkle.lua  sparkles: the CVar behind the sparkle, set again after graphics changes
--   needs.lua    objectives: the item objectives of the quest log, by item name
--   tooltip.lua  objectives: the tooltip lines

local _, ns = ...

local Helpers = ns:RegisterFeature("quests", "helpers", {
    order = 1,
    settings = {
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
        { key = "keepManual", type = "toggle", default = false, requires = { nearby = true } },
        { key = "sparkles", type = "toggle", default = true },
        { key = "objectives", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true, nearby = false },
        enhanced = { enabled = true, nearby = true, sparkles = true, objectives = true },
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

function Helpers:SyncParts()
    self:SyncPart("nearby", Nearby)
    self:SyncPart("sparkles", self.Sparkle)
    self:SyncPart("objectives", self.Needs)
end

function Helpers:OnEnable()
    self:SyncParts()
end

function Helpers:OnSettingChanged()
    self:SyncParts()
    if self:IsPartActive("nearby") then
        self.Refresh:Request()
    end
end

function Helpers:OnDisable()
    self:SyncParts()
end
