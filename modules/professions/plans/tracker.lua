-- The counted recipes in Blizzard's recipe tracker (ProfessionsRecipeTracker,
-- Blizzard_ObjectiveTracker): a counted recipe's header reads "<name> x<count>"
-- and its reagent lines "have / needed for every craft", done (green, checked,
-- no dash) once the bags hold that many. Its right-click menu gets "Set number
-- of crafts".
--
-- Blizzard draws a recipe's block in AddRecipe; a post-hook redraws it, and a
-- count change redraws it at once (Refresh), never asking the tracker to
-- update. Both only call methods of Blizzard's regions and read its fields:
-- code of ours writing the tracker's tables would run its updates tainted.
--
-- Lines are pooled across the tracker's modules, and Blizzard only redraws a
-- line's dash and color when they differ from the ones it drew last (its
-- dashStyle and colorStyle fields): a line we drew differently and Blizzard
-- frees would show our look in the next objective that takes it. So every
-- layout starts (BeginLayout, before anything is freed) by drawing the lines
-- we changed back the way Blizzard last drew them.

local _, ns = ...

local Plans = ns:GetFeature("professions", "plans")

local Tracker = {}
Plans.Tracker = Tracker

local TRACKER_ADDON = "Blizzard_ObjectiveTracker"
local MENU_TAG = "MENU_PROFESSIONS_RECIPE_TRACKER"
local CHECK_ATLAS = "ui-questtracker-tracker-check"

-- Lines and blocks drawn with a count since Blizzard last drew them: drawn[region] = true.
local drawnLines = setmetatable({}, { __mode = "k" })
local drawnBlocks = setmetatable({}, { __mode = "k" })

local installed = false

local function SetColor(fontString, colorStyle, highlighted)
    if highlighted and colorStyle.reverse then
        colorStyle = colorStyle.reverse
    end
    fontString:SetTextColor(colorStyle.r, colorStyle.g, colorStyle.b)
end

local function SetDone(line, done)
    line.Dash:SetShown(not done)
    line.Icon:SetShown(done)
    if done then
        line.Icon:SetAtlas(CHECK_ATLAS, false)
    end
end

-- A drawn line as Blizzard last drew it: recipe lines are done exactly when
-- their dash is hidden.
local function RestoreLine(line)
    drawnLines[line] = nil
    local done = line.dashStyle ~= OBJECTIVE_DASH_STYLE_SHOW
    SetDone(line, done)
    local parent = line:GetParent()
    SetColor(line.Text, line.Text.colorStyle or OBJECTIVE_TRACKER_COLOR.Normal, parent and parent.isHighlighted)
end

local function GetReagentName(reagent)
    if reagent.itemID then
        return C_Item.GetItemNameByID(reagent.itemID)
    elseif reagent.currencyID then
        local info = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
        return info and info.name
    end
end

-- Draws recipeID's block for `count` crafts the way AddRecipe draws one craft;
-- without a count, exactly as AddRecipe drew it. Modifying slots and variable
-- quantities stay Blizzard's.
local function Draw(block, recipeID, count)
    local schematic = ProfessionsUtil.GetRecipeSchematic(recipeID, false)
    local counted = count ~= nil
    count = count or 1
    drawnBlocks[block] = counted or nil
    block.HeaderText:SetText(
        counted and ns.L["professions.plans.header"]:format(schematic.name, count) or schematic.name
    )
    for slotIndex, slot in ipairs(schematic.reagentSlotSchematics) do
        local reagent = slot.reagents[1]
        local line = block:GetExistingLine(slotIndex)
        local name = reagent and GetReagentName(reagent)
        if
            line
            and name
            and ProfessionsUtil.IsReagentSlotBasicRequired(slot)
            and not slot:IsVariableQuantityReagent(reagent)
        then
            local needed = slot:GetQuantityRequired(reagent) * count
            local have = ProfessionsUtil.AccumulateReagentsInPossession(slot.reagents)
            local done = have >= needed
            drawnLines[line] = counted or nil
            line.Text:SetText(
                PROFESSIONS_TRACKER_REAGENT_FORMAT:format(
                    PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT:format(have, needed),
                    name
                )
            )
            SetColor(line.Text, OBJECTIVE_TRACKER_COLOR[done and "Complete" or "Normal"], block.isHighlighted)
            SetDone(line, done)
        end
    end
end

-- The shown block of a recipe (not a recraft: their IDs are negative), or nil.
local function GetBlock(recipeID)
    return ProfessionsRecipeTracker:GetExistingBlock(recipeID)
end

-- Whether `frame` is the shown block of a recipe (pooled blocks keep their last ID).
local function IsRecipeBlock(frame)
    local id = frame.id
    return type(id) == "number" and id > 0 and GetBlock(id) == frame
end

local function RestoreAll()
    for line in pairs(drawnLines) do
        RestoreLine(line)
    end
end

-- Redraws the blocks of counted recipes for their count, and those drawn with
-- a count before back as Blizzard drew them.
function Tracker:Refresh()
    if not installed then
        return
    end
    local blocks = {}
    for block in pairs(drawnBlocks) do
        blocks[block] = true
    end
    if Plans:IsActive() then
        for _, recipeID in ipairs(Plans:GetCountedRecipes()) do
            local block = GetBlock(recipeID)
            if block then
                blocks[block] = true
            end
        end
    end
    for block in pairs(blocks) do
        if IsRecipeBlock(block) then
            Draw(block, block.id, Plans:IsActive() and Plans:GetCount(block.id) or nil)
        else
            drawnBlocks[block] = nil
        end
    end
    -- Lines no longer in a counted block (a reagent slot gone).
    for line in pairs(drawnLines) do
        if not drawnBlocks[line:GetParent()] then
            RestoreLine(line)
        end
    end
end

-- The recipe block under the mouse, or nil: the menu doesn't say which block it's for.
local function GetBlockUnderMouse()
    for _, focus in ipairs(GetMouseFoci()) do
        local frame = focus
        while frame do
            if IsRecipeBlock(frame) then
                return frame
            end
            frame = frame:GetParent()
        end
    end
end

local function AddMenuEntry(_, rootDescription)
    if not Plans:IsActive() then
        return
    end
    local block = GetBlockUnderMouse()
    if not block then
        return
    end
    local recipeID = block.id
    rootDescription:CreateButton(ns.L["professions.plans.setCount"], function()
        Plans:AskCount(recipeID, block, Plans:GetCount(recipeID) or 1)
    end)
end

local function Install()
    installed = true
    ns:HookSecureFunc(ProfessionsRecipeTracker, "BeginLayout", function()
        RestoreAll()
        wipe(drawnBlocks)
    end)
    ns:HookSecureFunc(ProfessionsRecipeTracker, "AddRecipe", function(_, recipeID, isRecraft)
        if not Plans:IsActive() or isRecraft then
            return
        end
        local count = Plans:GetCount(recipeID)
        local block = count and GetBlock(recipeID)
        if block then
            Draw(block, recipeID, count)
        end
    end)
    Menu.ModifyMenu(MENU_TAG, AddMenuEntry)
end

local loadListener = ns:CreateEventListener({
    ADDON_LOADED = function(self, addonName)
        if addonName == TRACKER_ADDON then
            self:Stop()
            Install()
            Tracker:Refresh()
        end
    end,
})

function Tracker:Start()
    if not installed then
        if C_AddOns.IsAddOnLoaded(TRACKER_ADDON) then
            Install()
        else
            loadListener:Start()
        end
    end
    self:Refresh()
end

function Tracker:Stop()
    loadListener:Stop()
    self:Refresh()
end
