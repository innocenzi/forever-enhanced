-- Tracking: when the player tracks a recipe in the profession window (Shift
-- Left Click on its row in the list, or the "Track recipe" checkbox), the
-- picker opens on what they clicked; Okay counts that many crafts, Cancel
-- leaves Blizzard's plain tracking. Untracking a recipe, however done, forgets
-- its count. Each craft of a counted recipe counts one down; the last one
-- untracks it.
--
-- TRACKED_RECIPE_UPDATE doesn't tell recrafts apart: the recipe's own
-- tracking (IsRecipeTracked(recipeID, false)) does.

local _, ns = ...

local Plans = ns:GetFeature("professions", "plans")

local Tracking = {}
Plans.Tracking = Tracking

-- What the player clicked to track recipeID: its row in the profession
-- window's list, or the form's checkbox; nil when the window is closed or the
-- mouse is elsewhere (another addon tracked it).
local function GetClickedControl(recipeID)
    if not ProfessionsFrame or not ProfessionsFrame:IsVisible() then
        return nil
    end
    local form = ProfessionsFrame.CraftingPage.SchematicForm
    local checkbox = form.TrackRecipeCheckbox
    for _, focus in ipairs(GetMouseFoci()) do
        if focus == checkbox then
            -- On a recraft, the checkbox tracks the recraft.
            local recrafting = form.transaction ~= nil and form.transaction:IsRecraft()
            return not recrafting and checkbox or nil
        end
        local node = focus.GetElementData and focus:GetElementData()
        local data = type(node) == "table" and node.GetData and node:GetData()
        if type(data) == "table" and data.recipeInfo and data.recipeInfo.recipeID == recipeID then
            return focus
        end
    end
end

-- The count the picker starts from: the counted one, else the window's craft
-- count (0 while the bags lack reagents), at least 1.
local function GetStartCount(recipeID)
    return Plans:GetCount(recipeID) or math.max(ProfessionsFrame.CraftingPage.CreateMultipleInputBox:GetValue() or 0, 1)
end

local function OnTracked(recipeID)
    local control = GetClickedControl(recipeID)
    if not control then
        return
    end
    Plans:AskCount(recipeID, control, GetStartCount(recipeID))
end

-- One craft of recipeID made: its count goes down, and the last one untracks it.
local function OnCrafted(recipeID)
    local count = Plans:GetCount(recipeID)
    if not count then
        return
    end
    if count > 1 then
        Plans:SetCount(recipeID, count - 1)
        return
    end
    Plans:SetCount(recipeID, 0)
    ns:ShieldObjectiveTracker(function()
        C_TradeSkillUI.SetRecipeTracked(recipeID, false, false)
    end)
end

local listener = ns:CreateEventListener({
    TRACKED_RECIPE_UPDATE = function(_, recipeID, tracked)
        if not C_TradeSkillUI.IsRecipeTracked(recipeID, false) then
            Plans:SetCount(recipeID, 0)
        elseif tracked then
            OnTracked(recipeID)
        end
    end,
    -- Recipes are spells: a recipe's ID is its spell's.
    UNIT_SPELLCAST_SUCCEEDED = function(_, unit, _, spellID)
        if unit == "player" then
            OnCrafted(spellID)
        end
    end,
})

function Tracking:Start()
    listener:Start()
end

function Tracking:Stop()
    listener:Stop()
end
