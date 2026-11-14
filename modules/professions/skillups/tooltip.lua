-- The skill-up arrow of a recipe in the profession window's list
-- (ProfessionsRecipeListRecipeMixin, Blizzard_ProfessionsTemplates) shows
-- GameTooltip with one line, "High chance of gaining skill", added through
-- GameTooltip_AddNormalLine before the tooltip is shown. A post-hook of that
-- function adds the chance under it when the tooltip's owner is such an arrow.
--
-- The row sets the arrow's scripts again on every update, so a hook on the
-- arrow itself wouldn't last; the global post-hook only reads the row.
--
-- A herb or ore node's world tooltip (object tooltip data: its name, then the
-- profession colored by difficulty) gets the chance at the end, from a tooltip
-- post-call. The name can be secret (a secret string can't index a table):
-- such a tooltip gets nothing.

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

local function AddLine(tooltip, chance)
    local text = ns.L["professions.skillups.chance"]:format(math.floor(chance * 100 + 0.5))
    tooltip:AddLine(text, HIGHLIGHT_FONT_COLOR:GetRGB())
end

local function AddChance(tooltip)
    if not SkillUps:IsActive() or tooltip ~= GameTooltip then
        return
    end
    local recipeInfo = ArrowRecipe(tooltip)
    local chance = recipeInfo and SkillUps.Chance:Get(recipeInfo)
    if chance then
        AddLine(tooltip, chance)
    end
end

local function AddNodeChance(tooltip, data)
    if not SkillUps:IsActive() then
        return
    end
    local name = data and data.lines and data.lines[1] and data.lines[1].leftText
    local chance = type(name) == "string" and not issecretvalue(name) and SkillUps.Chance:GetNode(name)
    if chance then
        AddLine(tooltip, chance)
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
