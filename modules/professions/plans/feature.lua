-- Planned recipes: a badge on a recipe's icon plans it for a number of crafts;
-- the next time the bank opens, the reagents the bags lack for every planned
-- recipe move from the bank to the bags, and the plans are forgotten, whether
-- or not the bank held everything.
--
-- The bank feature does the moving (Bank:WithdrawUpTo): it needs the bank
-- feature on, but not its Deposit and Withdraw buttons.
--
-- Files of this slice:
--   feature.lua     registration, schema, lifecycle and the plans (this file)
--   locales.lua     strings
--   button.lua      the plan button on the profession window and its dialog
--   withdrawal.lua  the withdrawal at the bank and its announcement

local _, ns = ...

local Plans = ns:RegisterFeature("professions", "plans", {
    order = 3,
    settings = {
        { key = "announce", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true, announce = true },
        enhanced = { enabled = true, announce = true },
    },
})

-- Per character: plans[recipeID] = { count = crafts, reagents = { [itemID] = quantity } },
-- the reagents read when the recipe was planned.
local function GetStore()
    local store = Plans:GetCharacterStore()
    store.plans = store.plans or {}
    return store.plans
end

-- The basic reagents of one craft of recipeID, { [itemID] = quantity }. A slot
-- taking several items (quality tiers) counts as its first one.
local function ReadReagents(recipeID)
    local reagents = {}
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents[1]
        if slot.reagentType == Enum.CraftingReagentType.Basic and reagent and reagent.itemID then
            reagents[reagent.itemID] = (reagents[reagent.itemID] or 0) + slot.quantityRequired
        end
    end
    return reagents
end

-- The number of crafts planned for recipeID, or nil.
function Plans:GetPlannedCount(recipeID)
    local plan = GetStore()[recipeID]
    return plan and plan.count
end

-- Plans `count` crafts of recipeID; 0 (or a recipe without reagents) cancels its plan.
function Plans:SetPlan(recipeID, count)
    local reagents = count > 0 and ReadReagents(recipeID) or {}
    GetStore()[recipeID] = next(reagents) and { count = count, reagents = reagents } or nil
    self.Button:Update()
end

function Plans:ClearPlans()
    wipe(GetStore())
    self.Button:Update()
end

-- What the bags should hold for every plan: { [itemID] = count }.
function Plans:GetTotals()
    local totals = {}
    for _, plan in pairs(GetStore()) do
        for itemID, quantity in pairs(plan.reagents) do
            totals[itemID] = (totals[itemID] or 0) + quantity * plan.count
        end
    end
    return totals
end

function Plans:OnEnable()
    self.Button:Start()
    self.Withdrawal:Start()
end

function Plans:OnDisable()
    self.Withdrawal:Stop()
    self.Button:Stop()
end
