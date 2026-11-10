-- Quest Item Sparkles: keeps the game's sparkle on quest items the player can
-- loot. Picking a graphics preset switches it off; this switches it back on.
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   sparkle.lua  the CVar behind the sparkle, set again after graphics changes

local _, ns = ...

local Sparkles = ns:RegisterFeature("quests", "sparkles", { order = 3 })

function Sparkles:OnEnable()
    self.Sparkle:Enable()
end

function Sparkles:OnDisable()
    self.Sparkle:Disable()
end
