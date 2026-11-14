-- The skill-up arrow of a recipe in the profession window's list
-- (ProfessionsRecipeListRecipeMixin, Blizzard_ProfessionsTemplates) shows
-- GameTooltip with one line, "High chance of gaining skill", added through
-- GameTooltip_AddNormalLine before the tooltip is shown. A post-hook of that
-- function appends the chance to that line when the tooltip's owner is such an
-- arrow.
--
-- The row sets the arrow's scripts again on every update, so a hook on the
-- arrow itself wouldn't last; the global post-hook only reads the row.
--
-- A herb or ore node's world tooltip (object tooltip data: its name, then the
-- profession colored by difficulty) gets the chance appended to the profession
-- line, from a tooltip post-call. Either line can be secret (a secret string
-- can't index a table): such a tooltip gets nothing.
--
-- A line changes through its font string (<tooltip name>TextLeft<n>, from
-- SharedTooltipTemplates), which keeps its color.

local _, ns = ...

local SkillUps = ns:GetFeature("professions", "skillups")

local Tooltip = {}
SkillUps.Tooltip = Tooltip

-- The recipe the row shows, when the tooltip's owner is a recipe row's
-- skill-up arrow: the highest learned rank, like the row.
local function ArrowRecipe(tooltip)
    local owner = tooltip:GetOwner()
    if not owner or owner:IsForbidden() then
        return nil
    end
    local row = owner:GetParent()
    if not row or row.SkillUps ~= owner or not row.GetElementData then
        return nil
    end
    local recipeInfo = row:GetElementData():GetData().recipeInfo
    return recipeInfo and (Professions.GetHighestLearnedRecipe(recipeInfo) or recipeInfo)
end

-- Appends the chance to the tooltip's line `index`, whose text is `text`.
local function AppendChance(tooltip, index, text, chance)
    local name = tooltip:GetName()
    local fontString = name and _G[name .. "TextLeft" .. index]
    if fontString then
        fontString:SetText(ns.L["professions.skillups.chance"]:format(text, math.floor(chance * 100 + 0.5)))
    end
end

local function AddChance(tooltip, text)
    if not SkillUps:IsActive() or tooltip ~= GameTooltip then
        return
    end
    local recipeInfo = ArrowRecipe(tooltip)
    local chance = recipeInfo and SkillUps.Chance:Get(recipeInfo)
    if chance then
        AppendChance(tooltip, tooltip:NumLines(), text, chance)
    end
end

local function IsReadable(text)
    return type(text) == "string" and not issecretvalue(text)
end

local function AddNodeChance(tooltip, data)
    if not SkillUps:IsActive() then
        return
    end
    local lines = data and data.lines
    local name = lines and lines[1] and lines[1].leftText
    local profession = lines and lines[2] and lines[2].leftText
    local chance = IsReadable(name) and IsReadable(profession) and SkillUps.Chance:GetNode(name)
    if chance then
        AppendChance(tooltip, 2, profession, chance)
    end
end

local hooked = false

function Tooltip:Start()
    if not hooked then
        hooked = true
        hooksecurefunc("GameTooltip_AddNormalLine", AddChance)
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, AddNodeChance)
    end
end
