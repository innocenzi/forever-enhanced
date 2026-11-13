-- The transfer runner: the Deposit / Withdraw part of the bank feature (see
-- feature.lua), driving core/moves.lua with the planner's moves.
--
-- Opening the bank runs the automatic transfers turned on: "autoRefill" fills
-- the bags' partial stacks from the bank (but not those of items marked for the
-- bank), "autoDeposit" deposits the items marked for the bank. Both go in one
-- run: they never touch the same item, so their moves never conflict.

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

local Transfers = {}
Bank.Transfers = Transfers

local MAX_MOVES_PER_ITEM = 3

-- The running transfers: { { direction = "deposit" | "withdraw", mode }, ... }
local jobs = {}

local mover = ns:CreateMover({
    Plan = function()
        local moves = {}
        for _, job in ipairs(jobs) do
            for _, move in ipairs(Transfers.Planner:Plan(job.direction, job.mode)) do
                table.insert(moves, move)
            end
        end
        return moves
    end,
    maxMovesPerKey = MAX_MOVES_PER_ITEM,
})

-- Starts the given transfers, unless one is running or the bank is closed.
local function Start(newJobs)
    if #newJobs == 0 or mover:IsRunning() or not C_Bank.CanViewBank(Enum.BankType.Character) then
        return
    end
    jobs = newJobs
    mover:Start()
end

-- The automatic transfers turned on. Marked items are deposited only while the
-- bank mark is on (Item marks, loaded after this slice).
local function GetAutomaticJobs()
    local automatic = {}
    if Bank:GetSetting("autoRefill") then
        table.insert(automatic, { direction = "withdraw", mode = "refill" })
    end
    if Bank:GetSetting("autoDeposit") and ns:GetFeature("inventory", "marks"):IsPartActive("bank") then
        table.insert(automatic, { direction = "deposit", mode = "marked" })
    end
    return automatic
end

local listener = ns:CreateEventListener({
    BANKFRAME_OPENED = function()
        Start(GetAutomaticJobs())
    end,
    BANKFRAME_CLOSED = function()
        mover:Stop()
    end,
})

function Transfers:IsRunning()
    return mover:IsRunning()
end

-- Starts a transfer, unless one is running or the bank is closed.
function Transfers:Run(direction, mode)
    Start({ { direction = direction, mode = mode } })
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
