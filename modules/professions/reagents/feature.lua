-- Reagents: while Shift is held, item tooltips list the recipes that use the
-- item, by profession, the ones this character knows first.
--
-- No client API maps an item to the recipes using it, and recipe lists can
-- only be read from the open profession window, so the recipes come from a
-- table generated from Forever's own game data (tools/professions.ts).
--
-- Files of this slice:
--   feature.lua  registration, schema, lifecycle and the player's professions (this file)
--   locales.lua  strings
--   data.lua     generated: item ID -> { spellID, skillLineID, quantity } records
--   known.lua    the recipes this character knows, read from the profession window
--   stock.lua    whether the bags hold all, some or none of a recipe's reagents
--   tooltip.lua  the tooltip lines, refreshed when Shift changes

local _, ns = ...

local Reagents = ns:RegisterFeature("professions", "reagents", {
    order = 1,
    settings = {
        { key = "professions", type = "dropdown", default = "all", options = { "all", "mine" } },
    },
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true },
    },
})

-- Skill line IDs of the professions this character has learned, as a set.
function Reagents:GetPlayerSkillLines()
    local skillLines = {}
    -- Primary, secondary, First Aid, Fishing and Cooking slots; nil when empty.
    for _, index in pairs({ GetProfessions() }) do
        local skillLine = select(7, GetProfessionInfo(index))
        if skillLine then
            skillLines[skillLine] = true
        end
    end
    return skillLines
end

function Reagents:OnEnable()
    self.Known:Start()
    self.Tooltip:Start()
end

function Reagents:OnDisable()
    self.Known:Stop()
    self.Tooltip:Stop()
end
