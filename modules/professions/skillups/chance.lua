-- The chance that crafting a recipe or gathering a node gives a skill point.
-- Orange ones always do and grey ones never; in between, the chance falls
-- evenly from yellow to grey: (grey - skill) / (grey - yellow), so a recipe
-- turning green (halfway) has an even chance. Gathering is assumed to follow
-- the same rule. The skill counts its bonuses (racial ones), like the colors.

local _, ns = ...

local SkillUps = ns:GetFeature("professions", "skillups")

local Chance = {}
SkillUps.Chance = Chance

local function Between(skill, yellow, grey)
    return math.max(0, math.min(1, (grey - skill) / (grey - yellow)))
end

-- The chance, from 0 to 1, of a yellow or green recipe (C_TradeSkillUI recipe
-- info); nil for other colors and recipes missing from our data.
function Chance:Get(recipeInfo)
    local difficulty = recipeInfo.relativeDifficulty
    if
        difficulty ~= Enum.TradeskillRelativeDifficulty.Medium
        and difficulty ~= Enum.TradeskillRelativeDifficulty.Easy
    then
        return nil
    end
    local thresholds = SkillUps.Data[recipeInfo.recipeID]
    if not thresholds then
        return nil
    end
    local profession = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeInfo.recipeID)
    return Between(profession.skillLevel + profession.skillModifier, thresholds[1], thresholds[2])
end

-- The player's skill in a profession, bonuses included; nil when not learned.
local function PlayerSkill(skillLine)
    for _, index in pairs({ GetProfessions() }) do
        local _, _, rank, _, _, _, line, modifier = GetProfessionInfo(index)
        if line == skillLine then
            return rank + modifier
        end
    end
    return nil
end

-- The chance, from 0 to 1, of a yellow or green node named `name` (game text);
-- nil for other colors, unknown nodes and professions the player lacks.
function Chance:GetNode(name)
    local node = SkillUps.Nodes:Get(name)
    local skill = node and PlayerSkill(node.skillLine)
    if not skill or skill < node.yellow or skill >= node.grey then
        return nil
    end
    return Between(skill, node.yellow, node.grey)
end
