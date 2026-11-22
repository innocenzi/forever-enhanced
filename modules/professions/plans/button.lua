-- The plan button: a shopping cart badge on the top-right corner of the profession
-- window's recipe icon (Blizzard_Professions, load-on-demand), lit while the
-- recipe is planned. Left Click asks for the number of crafts (0 cancels),
-- starting from the planned count or the window's craft count; Right Click
-- cancels. On the icon, it fits whatever the length of the recipe's name (the
-- favorite star follows the name, to the panel's edge).
--
-- The button is a child of Blizzard's FavoriteButton, so it shows exactly when
-- the star does (learned recipes, not recrafts or inspections). The recipe
-- changes without the star hiding: the recipe list's selection event redraws
-- the button on the next frame, once the form shows the new recipe.

local _, ns = ...

local Plans = ns:GetFeature("professions", "plans")

local Button = {}
Plans.Button = Button

local PROFESSIONS_ADDON = "Blizzard_Professions"
local RECIPE_SELECTED = "ProfessionsRecipeListMixin.Event.OnRecipeSelected"
local DIALOG = "FOREVER_ENHANCED_PLAN_RECIPE"
local ICON_ATLAS = "perks-shoppingcart"
-- Like the bank's reagent mark (inventory/bank/reagents.lua).
local SIZE = 18
local BADGE_OFFSET = 5
local MAX_CRAFTS_DIGITS = 3

-- Created once Blizzard_Professions has loaded.
local button

local function GetForm()
    return ProfessionsFrame.CraftingPage.SchematicForm
end

-- The recipe the window shows, or nil.
local function GetRecipe()
    return GetForm():GetRecipeInfo()
end

local function Save(editBox, data)
    Plans:SetPlan(data.recipeID, tonumber(editBox:GetText()) or 0)
end

-- The text is set when shown: strings are in the player's language only after
-- the addon has loaded.
StaticPopupDialogs[DIALOG] = {
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    OnShow = function(dialog, data)
        local editBox = dialog:GetEditBox()
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(MAX_CRAFTS_DIGITS)
        editBox:SetText(tostring(data.count))
        editBox:HighlightText()
    end,
    OnAccept = function(dialog, data)
        Save(dialog:GetEditBox(), data)
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        Save(editBox, data)
        editBox:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
    hideOnEscape = 1,
    timeout = 0,
    whileDead = 1,
}

-- The count the dialog starts from: the planned one, else the window's craft
-- count (0 while the bags lack reagents), at least 1.
local function GetDefaultCount(recipeID)
    local planned = Plans:GetPlannedCount(recipeID)
    if planned then
        return planned
    end
    return math.max(ProfessionsFrame.CraftingPage.CreateMultipleInputBox:GetValue() or 0, 1)
end

local function OnClick(_, mouseButton)
    local recipe = GetRecipe()
    if not recipe then
        return
    end
    if mouseButton == "RightButton" then
        Plans:SetPlan(recipe.recipeID, 0)
        return
    end
    StaticPopupDialogs[DIALOG].text = ns.L["professions.plans.prompt"]
    StaticPopup_Show(DIALOG, recipe.name, nil, { recipeID = recipe.recipeID, count = GetDefaultCount(recipe.recipeID) })
end

local function OnEnter(self)
    local recipe = GetRecipe()
    local planned = recipe and Plans:GetPlannedCount(recipe.recipeID)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, ns.L["professions.plans.button"])
    if planned then
        GameTooltip_AddHighlightLine(GameTooltip, ns.L["professions.plans.planned"]:format(planned))
    end
    GameTooltip_AddNormalLine(GameTooltip, ns.L["professions.plans.button.tooltip"])
    GameTooltip_AddInstructionLine(GameTooltip, ns.L["professions.plans.leftClick"])
    if planned then
        GameTooltip_AddInstructionLine(GameTooltip, ns.L["professions.plans.rightClick"])
    end
    GameTooltip:Show()
end

local function Create()
    local form = GetForm()
    button = CreateFrame("Button", nil, form.FavoriteButton)
    button:SetSize(SIZE, SIZE)
    button:SetPoint("TOPRIGHT", form.OutputIcon, "TOPRIGHT", BADGE_OFFSET, BADGE_OFFSET)
    button:SetFrameLevel(form.OutputIcon:GetFrameLevel() + 2)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetAllPoints()
    button.Icon:SetAtlas(ICON_ATLAS)
    button:SetHighlightAtlas(ICON_ATLAS, "ADD")
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnShow", function()
        Button:Update()
    end)
end

-- Lights the button while the shown recipe is planned.
function Button:Update()
    if not button then
        return
    end
    button:SetShown(Plans:IsActive())
    local recipe = GetRecipe()
    local planned = recipe ~= nil and Plans:GetPlannedCount(recipe.recipeID) ~= nil
    button.Icon:SetDesaturated(not planned)
    button.Icon:SetAlpha(planned and 1 or 0.5)
    if GameTooltip:GetOwner() == button then
        OnEnter(button)
    end
end

local function OnRecipeSelected()
    C_Timer.After(0, function()
        Button:Update()
    end)
end

local loadListener = ns:CreateEventListener({
    ADDON_LOADED = function(self, addonName)
        if addonName == PROFESSIONS_ADDON then
            self:Stop()
            Create()
            Button:Update()
        end
    end,
})

function Button:Start()
    if not button then
        if C_AddOns.IsAddOnLoaded(PROFESSIONS_ADDON) then
            Create()
        else
            loadListener:Start()
        end
    end
    EventRegistry:RegisterCallback(RECIPE_SELECTED, OnRecipeSelected, self)
    self:Update()
end

function Button:Stop()
    loadListener:Stop()
    EventRegistry:UnregisterCallback(RECIPE_SELECTED, self)
    self:Update()
end
