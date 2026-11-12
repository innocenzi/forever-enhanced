-- Skill-up chance: the tooltip of a yellow or green recipe's skill-up arrow in
-- the profession window shows the chance that crafting it gives a skill point.
--
-- The client only tells the recipe's color: the chance is worked out from the
-- recipe's yellow and grey thresholds, generated from Forever's own game data
-- (tools/professions.ts), and the player's skill.
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   data.lua     generated: recipe spell ID -> { yellow, grey }
--   chance.lua   the chance of a recipe
--   tooltip.lua  the line under Blizzard's in the arrow's tooltip

local _, ns = ...

local SkillUps = ns:RegisterFeature("professions", "skillups", {
    order = 2,
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

-- Nothing to undo on disable: the hook checks IsActive(), and the tooltip it
-- adds to goes away with the mouse.
function SkillUps:OnEnable()
    self.Tooltip:Start()
end
