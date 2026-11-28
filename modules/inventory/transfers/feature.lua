-- Bank transfers: at a banker, Deposit and Withdraw buttons move items between
-- the bags and the bank, either onto the other side's partial stacks only, or
-- every item the other side already holds (partial stacks first, then empty
-- slots). Deposit also moves the items marked for the bank (Item marks). Locked
-- items (Item Locking) never move. Opening the bank can refill the bags'
-- partial stacks ("autoRefill") and deposit the marked items ("autoDeposit").
-- With "autoSort", a transfer that moved items ends with the bank's Clean Up.
-- Other features withdraw exact quantities with Transfers:WithdrawUpTo, whether
-- or not this feature is on (runner.lua).
--
-- Files of this slice:
--   feature.lua    registration, schema and lifecycle (this file)
--   locales.lua    strings
--   runner.lua     the transfer runner, and Transfers:WithdrawUpTo
--   planner.lua    the moves a transfer still needs, from live positions
--   buttons.lua    Deposit / Withdraw buttons and their menus

local _, ns = ...

local Transfers = ns:RegisterFeature("inventory", "transfers", {
    page = "bank",
    order = 2,
    settings = {
        { key = "autoRefill", type = "toggle", default = false },
        { key = "autoDeposit", type = "toggle", default = false },
        { key = "autoSort", type = "toggle", default = false },
    },
    presets = {
        minimal = { enabled = true, autoRefill = false, autoDeposit = false, autoSort = true },
        enhanced = { enabled = true, autoRefill = true, autoDeposit = true, autoSort = true },
    },
})

function Transfers:OnEnable()
    self.Runner:Enable()
    self.Buttons:Enable()
end

function Transfers:OnDisable()
    self.Buttons:Disable()
    self.Runner:Disable()
end
