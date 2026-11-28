-- Tracked recipes: tracking a recipe (Blizzard's Shift Left Click in the recipe
-- list, or its "Track recipe" checkbox) asks for a number of crafts. Blizzard's
-- recipe tracker then shows the reagents for that many, each craft counts one
-- down, and the last one untracks the recipe. Recipes tracked without a count
-- stay Blizzard's own. With "withdraw", every bank visit brings the bags up to
-- what the counted recipes still need.
--
-- The transfer buttons do the moving (Transfers:WithdrawUpTo), whether or not
-- they are on.
--
-- Files of this slice:
--   feature.lua     registration, schema, lifecycle and the counts (this file)
--   locales.lua     strings
--   picker.lua      the number of crafts picker, like the merchant's stack picker
--   tracker.lua     the counted reagents in Blizzard's recipe tracker, and its menu entry
--   tracking.lua    the picker on tracking, the count down on crafting
--   withdrawal.lua  the withdrawal at the bank and its announcement

local _, ns = ...

local Plans = ns:RegisterFeature("professions", "plans", {
    page = "professions",
    order = 3,
    settings = {
        { key = "withdraw", type = "toggle", default = true },
        { key = "announce", type = "toggle", default = true, requires = { withdraw = true } },
    },
})

-- The most crafts a recipe can count (three digits).
Plans.MAX_COUNT = 999

-- Per character: counts[recipeID] = crafts still to make, for tracked recipes
-- (never recrafts).
local function GetStore()
    local store = Plans:GetCharacterStore()
    store.plans = nil -- Planned recipes, before they were tracked.
    store.counts = store.counts or {}
    return store.counts
end

-- The number of crafts counted for recipeID, or nil (not tracked, or tracked without a count).
function Plans:GetCount(recipeID)
    return GetStore()[recipeID]
end

-- Counts `count` crafts of recipeID; 0 forgets its count.
function Plans:SetCount(recipeID, count)
    count = math.min(count, self.MAX_COUNT)
    local counts = GetStore()
    if (counts[recipeID] or 0) == count then
        return
    end
    counts[recipeID] = count > 0 and count or nil
    self.Tracker:Refresh()
end

-- Opens the picker on `anchor` at `start`; Okay counts that many crafts of
-- recipeID, if it's still tracked.
function Plans:AskCount(recipeID, anchor, start)
    self.Picker:Open(anchor, start, function(count)
        if C_TradeSkillUI.IsRecipeTracked(recipeID, false) then
            self:SetCount(recipeID, count)
        end
    end)
end

-- Recipes with a count, in no order.
function Plans:GetCountedRecipes()
    local recipeIDs = {}
    for recipeID in pairs(GetStore()) do
        table.insert(recipeIDs, recipeID)
    end
    return recipeIDs
end

-- What the bags should hold for every counted recipe: { [itemID] = count }.
-- A slot taking several items (quality tiers) counts as its first one.
function Plans:GetTotals()
    local totals = {}
    for recipeID, count in pairs(GetStore()) do
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
        for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
            local reagent = slot.reagents[1]
            if slot.reagentType == Enum.CraftingReagentType.Basic and reagent and reagent.itemID then
                totals[reagent.itemID] = (totals[reagent.itemID] or 0) + slot.quantityRequired * count
            end
        end
    end
    return totals
end

-- Counts of recipes untracked while the feature was off (or by another addon) are forgotten.
local function Prune()
    local counts = GetStore()
    for recipeID in pairs(counts) do
        if not C_TradeSkillUI.IsRecipeTracked(recipeID, false) then
            counts[recipeID] = nil
        end
    end
end

function Plans:OnEnable()
    Prune()
    self.Tracking:Start()
    self.Withdrawal:Start()
    self.Tracker:Start()
end

function Plans:OnDisable()
    self.Tracker:Stop()
    self.Withdrawal:Stop()
    self.Tracking:Stop()
    self.Picker:Close()
end
