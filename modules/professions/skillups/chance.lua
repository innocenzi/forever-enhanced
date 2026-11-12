-- The chance that crafting a recipe gives a skill point. Orange recipes always
-- do and grey ones never; in between, the chance falls evenly from yellow to
-- grey: (grey - skill) / (grey - yellow), so a recipe turning green (halfway)
-- has an even chance. The skill counts its bonuses (racial ones), like the
-- recipe's color.

local _, ns = ...

local SkillUps = ns:GetFeature("professions", "skillups")

local Chance = {}
SkillUps.Chance = Chance

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
    local yellow, grey = thresholds[1], thresholds[2]
    local profession = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeInfo.recipeID)
    local skill = profession.skillLevel + profession.skillModifier
    return math.max(0, math.min(1, (grey - skill) / (grey - yellow)))
end
