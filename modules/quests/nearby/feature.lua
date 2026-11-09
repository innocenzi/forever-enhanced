-- Nearby Quests: keeps the quests nearest to the player in the objective
-- tracker and untracks the farthest ones as the player moves.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   ranking.lua  which quests should be tracked, closest first
--   watches.lua  the watch list: applying it, manual tracks, dismissals
--   refresh.lua  events and ticker, coalesced into one evaluation per frame

local _, ns = ...

local Nearby = ns:RegisterFeature("quests", "nearby", {
    order = 1,
    settings = {
        { key = "scope", type = "dropdown", default = "closest", options = { "closest", "range", "zone" } },
        {
            key = "range",
            type = "slider",
            default = 500,
            min = 100,
            max = 2000,
            step = 50,
            requires = { scope = "range" },
        },
        { key = "count", type = "slider", default = 5, min = 1, max = 25, step = 1 },
        { key = "keepManual", type = "toggle", default = false },
    },
})

function Nearby:OnEnable()
    self.Refresh:Enable()
end

function Nearby:OnDisable()
    self.Refresh:Disable()
    self.Watches:Reset()
end

function Nearby:OnSettingChanged()
    self.Refresh:Request()
end
