-- Skill-up chance: the tooltip of a yellow or green recipe's skill-up arrow in
-- the profession window shows the chance that crafting it gives a skill point;
-- the world tooltip of a yellow or green herb or ore node, that gathering it does.
--
-- The client only tells the color: the chance is worked out from the recipe's
-- yellow and grey thresholds, generated from Forever's own game data
-- (tools/professions.ts), or from the node's required skill, and the player's
-- skill.
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   data.lua     generated: recipe spell ID -> { yellow, grey }
--   nodes.lua    herbs and ore nodes by name -> required skill
--   chance.lua   the chance of a recipe or a node
--   tooltip.lua  the chance in the arrow's and the node's tooltips

local _, ns = ...

local SkillUps = ns:RegisterFeature("professions", "skillups", {
    order = 2,
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

-- Nothing to undo on disable: the hooks check IsActive(), and the tooltips they
-- add to go away with the mouse.
function SkillUps:OnEnable()
    self.Tooltip:Start()
end
