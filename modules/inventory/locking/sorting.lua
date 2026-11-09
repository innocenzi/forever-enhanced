-- Keeps locked items in their slot when bags or bank are sorted.
--
-- Blizzard's sort runs on the server and can't skip single items, so we let it
-- run and put locked items back afterwards, with the item mover (core/moves.lua):
--   1. Hooking the C_Container sort functions catches every way to start a sort
--      (bag button, portrait menu, bank, other addons). The hook runs before the
--      server moves anything, so it records where each locked item is.
--   2. Measured on Forever: the server busies and frees slots (ITEM_LOCK_CHANGED)
--      for ~100ms, then delivers all moves in one BAG_UPDATE_DELAYED. The restore
--      starts on the sort's bag update; a sort that moved nothing sends none, and
--      ends once lock changes settle.
--   3. Each round swaps every misplaced locked item home at once.
-- Each swap sends the displaced item to the slot the sort gave the locked item,
-- so one item per locked item may end up out of order.

local _, ns = ...

local Locking = ns:GetFeature("inventory", "locking")

local Sorting = {}
Locking.Sorting = Sorting

local SORT_FUNCTIONS = { "SortBags", "SortBank", "SortBankBags", "SortAccountBankBags" }
local SORT_TIMEOUT_SECONDS = 1 -- fallback when a sort reports nothing at all
-- Locks settled without a bag update: the sort moved nothing. Measured gap from the
-- last lock change to the sort's bag update is ~75ms; keep a wide margin, as firing
-- early would read stale positions (and nothing is visible when nothing moved).
local SORT_NO_MOVES_SECONDS = 0.3
local MAX_MOVES_PER_ITEM = 3

-- Where each locked item was before the sort: { [guid] = { bagID, slot } }.
local homes = {}
local hooksInstalled = false

local function FindLockedItems()
    local found = {}
    ns.Containers:ForEachSlot(ns.Containers.ALL_CONTAINER_IDS, function(bagID, slot)
        local guid = Locking:GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot))
        if Locking:IsGUIDLocked(guid) then
            found[guid] = { bagID = bagID, slot = slot }
        end
    end)
    return found
end

local function IsSameSlot(a, b)
    return a.bagID == b.bagID and a.slot == b.slot
end

-- One swap home per misplaced locked item. Items gone (merged into another
-- stack) or home are done.
local function Plan()
    local current = FindLockedItems()
    local moves = {}
    for guid, home in pairs(homes) do
        local location = current[guid]
        if not location or IsSameSlot(location, home) then
            homes[guid] = nil
        else
            table.insert(moves, { from = location, to = home, key = guid })
        end
    end
    return moves
end

local mover = ns:CreateMover({ Plan = Plan, maxMovesPerKey = MAX_MOVES_PER_ITEM })

-- While the sort runs, each lock change pushes back the "moved nothing" check.
local listener = ns:CreateEventListener({
    ITEM_LOCK_CHANGED = function()
        if mover:IsWaitingForServer() then
            mover:WaitForServer(SORT_NO_MOVES_SECONDS)
        end
    end,
})

local function OnSortStarted()
    if not Locking:IsActive() or not Locking:GetSetting("keepInPlace") then
        return
    end

    -- A sort started while restoring keeps the original homes.
    if not mover:IsRunning() then
        homes = FindLockedItems()
        if not next(homes) then
            return
        end
    end
    mover:WaitForServer(SORT_TIMEOUT_SECONDS)
end

-- hooksecurefunc hooks can't be removed: install once, OnSortStarted checks IsActive().
function Sorting:Enable()
    listener:Start()
    if hooksInstalled then
        return
    end
    hooksInstalled = true
    for _, name in ipairs(SORT_FUNCTIONS) do
        hooksecurefunc(C_Container, name, OnSortStarted)
    end
end

-- Stops a restore in progress, if any.
function Sorting:Cancel()
    mover:Stop()
end

function Sorting:Disable()
    listener:Stop()
    self:Cancel()
end
