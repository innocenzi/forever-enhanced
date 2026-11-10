-- The transfer runner: the Deposit / Withdraw part of the bank feature (see
-- feature.lua), driving core/moves.lua with the planner's moves.

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

local Transfers = {}
Bank.Transfers = Transfers

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

function Transfers:Enable()
    listener:Start()
    self.Buttons:Enable()
end

function Transfers:Disable()
    listener:Stop()
    mover:Stop()
    self.Buttons:Disable()
end
