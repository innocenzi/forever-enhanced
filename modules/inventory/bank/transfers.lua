-- The transfer runner: the Deposit / Withdraw part of the bank feature (see
-- feature.lua), driving core/moves.lua with the planner's moves.
--
-- Opening the bank runs the automatic transfers turned on: "autoRefill" fills
-- the bags' partial stacks from the bank (but not those of items marked for the
-- bank), "autoDeposit" deposits the items marked for the bank. Both go in one
-- run: they never touch the same item, so their moves never conflict.
--
-- Other features withdraw exact quantities through Bank:WithdrawUpTo (e.g.
-- Planned recipes), whether or not the transfers part runs. Their job joins a
-- run already going, so every transfer shares one mover: a round never sends
-- two moves touching the same slot. The other jobs of the run leave its items
-- alone: the refill would top off the withdrawn stack, the deposit take it back.
--
-- With "autoSort", a transfer that moved items (automatic ones included) ends
-- with the bank's Clean Up (C_Container.SortBank). Item locking and Reserved
-- slots hook the sort, so locked items and reserved slots go back in place.

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

local Transfers = {}
Bank.Transfers = Transfers

local MAX_MOVES_PER_ITEM = 3

-- The running transfers: { { direction = "deposit" | "withdraw", mode, totals, onFinished }, ... }
local jobs = {}

local mover = ns:CreateMover({
    Plan = function()
        -- Exact quantities win: the other jobs leave their items alone (the
        -- refill would top off a withdrawn stack, the deposit take it back).
        local exact = {}
        for _, job in ipairs(jobs) do
            for itemID in pairs(job.totals or {}) do
                exact[itemID] = true
            end
        end
        local moves = {}
        for _, job in ipairs(jobs) do
            for _, move in ipairs(Transfers.Planner:Plan(job.direction, job.mode, job.totals, exact)) do
                table.insert(moves, move)
            end
        end
        return moves
    end,
    maxMovesPerKey = MAX_MOVES_PER_ITEM,
    OnFinished = function(movedCount)
        local finished = jobs
        jobs = {}
        local canSort = Bank:IsPartActive("transfers") and Bank:GetSetting("autoSort")
        if movedCount > 0 and canSort and C_Bank.CanViewBank(Enum.BankType.Character) then
            C_Container.SortBank(Enum.BankType.Character)
        end
        for _, job in ipairs(finished) do
            if job.onFinished then
                securecallfunction(job.onFinished)
            end
        end
    end,
})

-- Starts the given transfers, or adds them to the running one; false when the
-- bank is closed or there is nothing to start.
local function Start(newJobs)
    if #newJobs == 0 or not C_Bank.CanViewBank(Enum.BankType.Character) then
        return false
    end
    if mover:IsRunning() then
        for _, job in ipairs(newJobs) do
            table.insert(jobs, job)
        end
    else
        jobs = newJobs
    end
    mover:Start()
    return true
end

-- The automatic transfers turned on. Marked items are deposited only while the
-- bank mark is on (Item marks, loaded after this slice).
local function GetAutomaticJobs()
    local automatic = {}
    if Bank:GetSetting("autoRefill") then
        table.insert(automatic, { direction = "withdraw", mode = "refill" })
    end
    if Bank:GetSetting("autoDeposit") and ns:GetFeature("inventory", "marks"):IsDestinationActive("bank") then
        table.insert(automatic, { direction = "deposit", mode = "marked" })
    end
    return automatic
end

local automaticListener = ns:CreateEventListener({
    BANKFRAME_OPENED = function()
        Start(GetAutomaticJobs())
    end,
})

-- While the feature is active, whatever its parts: WithdrawUpTo runs without them.
local closeListener = ns:CreateEventListener({
    BANKFRAME_CLOSED = function()
        mover:Stop()
    end,
})

function Transfers:IsRunning()
    return mover:IsRunning()
end

-- Starts a transfer, unless one is running or the bank is closed.
function Transfers:Run(direction, mode)
    if not mover:IsRunning() then
        Start({ { direction = direction, mode = mode } })
    end
end

-- Runs with the feature's lifecycle (feature.lua).
function Transfers:Start()
    closeListener:Start()
end

function Transfers:Stop()
    closeListener:Stop()
    mover:Stop()
end

function Transfers:Enable()
    automaticListener:Start()
    self.Buttons:Enable()
end

function Transfers:Disable()
    automaticListener:Stop()
    mover:Stop()
    self.Buttons:Disable()
end

-- Public: at an open bank, withdraws what the bags lack of each item to hold
-- totals[itemID] ({ [itemID] = count }), as far as the bank and the bags' room
-- allow. onFinished() runs once the withdrawal is done (not when the bank closes
-- first). Returns whether the withdrawal was started.
function Bank:WithdrawUpTo(totals, onFinished)
    if not self:IsActive() then
        return false
    end
    return Start({ { direction = "withdraw", mode = "upTo", totals = totals, onFinished = onFinished } })
end
