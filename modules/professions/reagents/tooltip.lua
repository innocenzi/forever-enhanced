-- Item tooltips of reagents, while Shift is held: the recipes using the item,
-- under each profession ("Bolt of Linen Cloth x2"), known ones first and in
-- white. Without Shift the client's own "Crafting Reagent" line is enough.
--
-- Tooltips whose owner rebuilds them (bags, bank, merchant, character slots)
-- follow Shift on their own; the others (chat links, action bar items) are
-- rebuilt when Shift changes, out of combat so our rebuild never runs where
-- the tooltip code meets protected frames.

local _, ns = ...

local Reagents = ns:GetFeature("professions", "reagents")

local Tooltip = {}
Reagents.Tooltip = Tooltip

local MAX_RECIPES = 8

-- The uses of the item to show, by skill line, and those skill lines in the
-- data's order (the generator sorts each item's uses by profession).
local function GroupUses(uses, playerSkillLines)
    local mine = Reagents:GetSetting("professions") == "mine"
    local groups, order = {}, {}
    for _, use in ipairs(uses) do
        local skillLine = use[2]
        if not mine or playerSkillLines[skillLine] then
            if not groups[skillLine] then
                groups[skillLine] = {}
                table.insert(order, skillLine)
            end
            table.insert(groups[skillLine], use)
        end
    end
    return groups, order
end

local function ProfessionName(skillLine)
    return C_TradeSkillUI.GetTradeSkillDisplayName(skillLine)
end

-- One entry per recipe name (the data holds a few same-named variants), known
-- if any variant is; known first, then by name.
local function SortedRecipes(uses, skillLine, playerSkillLines)
    local byName, recipes = {}, {}
    for _, use in ipairs(uses) do
        local spellID, quantity = use[1], use[3]
        local name = C_Spell.GetSpellName(spellID) or tostring(spellID)
        local known = Reagents.Known:IsKnown(spellID, skillLine, playerSkillLines)
        local recipe = byName[name]
        if recipe then
            recipe.known = recipe.known or known
        else
            recipe = { name = name, quantity = quantity, known = known }
            byName[name] = recipe
            table.insert(recipes, recipe)
        end
    end
    table.sort(recipes, function(a, b)
        if a.known ~= b.known then
            return a.known
        end
        return a.name < b.name
    end)
    return recipes
end

local function AddRecipes(tooltip, groups, order, playerSkillLines)
    tooltip:AddLine(" ")
    for _, skillLine in ipairs(order) do
        tooltip:AddLine(NORMAL_FONT_COLOR:WrapTextInColorCode(ProfessionName(skillLine)))
        local recipes = SortedRecipes(groups[skillLine], skillLine, playerSkillLines)
        for index = 1, math.min(#recipes, MAX_RECIPES) do
            local recipe = recipes[index]
            local color = recipe.known and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR
            local line = ns.L["professions.reagents.recipe"]:format(recipe.name, recipe.quantity)
            tooltip:AddLine(color:WrapTextInColorCode(line))
        end
        if #recipes > MAX_RECIPES then
            local line = ns.L["professions.reagents.more"]:format(#recipes - MAX_RECIPES)
            tooltip:AddLine(GRAY_FONT_COLOR:WrapTextInColorCode(line))
        end
    end
end

ns:AddItemTooltipHandler(Reagents, function(tooltip, data)
    local uses = data.id and Reagents.Data[data.id]
    if not uses or not IsShiftKeyDown() then
        return
    end
    local playerSkillLines = Reagents:GetPlayerSkillLines()
    local groups, order = GroupUses(uses, playerSkillLines)
    if #order > 0 then
        AddRecipes(tooltip, groups, order, playerSkillLines)
    end
end)

-- Rebuilds a shown reagent tooltip nothing else rebuilds.
local function Refresh(tooltip)
    if not tooltip:IsShown() or not tooltip:IsTooltipType(Enum.TooltipDataType.Item) then
        return
    end
    local owner = tooltip:GetOwner()
    if tooltip.UpdateTooltip or (owner and owner.UpdateTooltip) then
        return
    end
    local data = tooltip:GetPrimaryTooltipData()
    if data and data.id and Reagents.Data[data.id] then
        tooltip:RefreshData()
    end
end

local listener = ns:CreateEventListener({
    MODIFIER_STATE_CHANGED = function(_, key)
        if (key == "LSHIFT" or key == "RSHIFT") and not InCombatLockdown() then
            Refresh(GameTooltip)
            Refresh(ItemRefTooltip)
        end
    end,
})

function Tooltip:Start()
    listener:Start()
end

function Tooltip:Stop()
    listener:Stop()
end
