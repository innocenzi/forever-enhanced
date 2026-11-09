-- Bank Transfers: at a banker, Deposit and Withdraw buttons move items between
-- the bags and the bank, either onto the other side's partial stacks only, or
-- every item the other side already holds (partial stacks first, then empty
-- slots). Locked items (Item Locking) never move.
--
-- Files of this slice:
--   feature.lua   registration, lifecycle and the transfer runner (this file)
--   locales.lua   strings
--   planner.lua   the moves still needed, from live positions
--   buttons.lua   Deposit / Withdraw buttons and their menus

local _, ns = ...

local Transfers = ns:RegisterFeature("inventory", "transfers", { order = 3 })

local MAX_MOVES_PER_ITEM = 3

-- The running transfer: direction ("deposit" | "withdraw") and mode ("stacks" | "all").
local direction, mode

local mover = ns:CreateMover({
    Plan = function()
        return Transfers.Planner:Plan(direction, mode)
    end,
    maxMovesPerKey = MAX_MOVES_PER_ITEM,
})

local listener = ns:CreateEventListener({
    BANKFRAME_CLOSED = function()
        mover:Stop()
    end,
})

function Transfers:IsRunning()
    return mover:IsRunning()
end

-- Starts a transfer, unless one is running or the bank is closed.
function Transfers:Run(newDirection, newMode)
    if mover:IsRunning() or not C_Bank.CanViewBank(Enum.BankType.Character) then
        return
    end
    direction, mode = newDirection, newMode
    mover:Start()
end

function Transfers:OnEnable()
    listener:Start()
    self.Buttons:Enable()
end

function Transfers:OnDisable()
    listener:Stop()
    mover:Stop()
    self.Buttons:Disable()
end
