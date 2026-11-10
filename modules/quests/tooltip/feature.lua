-- Quest Objectives in Tooltips: item tooltips name the quests of the log that
-- need the item, with the player's progress (food or trade goods a quest asks
-- for are ordinary items, with nothing else to tell them apart).
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   needs.lua    the item objectives of the quest log, by item name
--   tooltip.lua  the tooltip lines

local _, ns = ...

local Tooltip = ns:RegisterFeature("quests", "tooltip", { order = 4 })

function Tooltip:OnEnable()
    self.Needs:Enable()
end

function Tooltip:OnDisable()
    self.Needs:Disable()
end
