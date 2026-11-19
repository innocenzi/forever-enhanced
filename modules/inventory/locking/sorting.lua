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
--   3. Two rounds of swaps put every misplaced locked item home (Plan). Each
--      round waits for the server, and Blizzard redraws the bags after it: one
--      swap home per item would take a round per item when each one's home
--      holds another locked item (seen with nearly full bags).
-- The item a chain of locked items displaces ends in the slot the sort gave the
-- chain's first one, so one item per chain may end up out of order.

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
        local guid = ns.Containers:GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot))
        if Locking:IsGUIDLocked(guid) then
            found[guid] = { bagID = bagID, slot = slot }
        end
    end)
    return found
end

local function IsSameSlot(a, b)
    return a.bagID == b.bagID and a.slot == b.slot
end

local function SlotKey(location)
    return location.bagID .. ":" .. location.slot
end

-- The moves putting home `items`, a chain (each one's home holds the next one,
-- the last one's holds no misplaced item) or a cycle (the last one's holds the first).
-- Their slots form a cycle: what slots[i] holds goes to slots[i + 1], what the
-- last one holds to slots[1]. Two slots just swap. Otherwise this round swaps
-- slots[j + 1] and slots[n + 1 - j], leaving swaps of two slots for the next
-- round: any order of locked items is put back in two rounds.
local function AddMoves(moves, items)
    local slots = {}
    for _, item in ipairs(items) do
        table.insert(slots, item.location)
    end
    local lastHome = items[#items].home
    if not IsSameSlot(lastHome, slots[1]) then
        table.insert(slots, lastHome)
    end
    local n = #slots
    if n == 2 then
        table.insert(moves, { from = slots[1], to = slots[2], key = items[1].guid })
        return
    end
    for j = 1, math.floor((n - 1) / 2) do
        table.insert(moves, { from = slots[j + 1], to = slots[n + 1 - j], key = items[j + 1].guid })
    end
end

-- This round's swaps putting misplaced locked items home. Items gone (merged
-- into another stack) or home are done.
local function Plan()
    local current = FindLockedItems()
    -- Misplaced locked items by the slot they're in, and the slots they go to.
    local misplaced, isHome = {}, {}
    for guid, home in pairs(homes) do
        local location = current[guid]
        if not location or IsSameSlot(location, home) then
            homes[guid] = nil
        else
            misplaced[SlotKey(location)] = { guid = guid, location = location, home = home }
            isHome[SlotKey(home)] = true
        end
    end

    local moves, seen = {}, {}
    local function Follow(item)
        local items = {}
        while item and not seen[item] do
            seen[item] = true
            table.insert(items, item)
            item = misplaced[SlotKey(item.home)]
        end
        if #items > 0 then
            AddMoves(moves, items)
        end
    end
    -- Chains start from a slot no other item goes to; the items left form cycles.
    for key, item in pairs(misplaced) do
        if not isHome[key] then
            Follow(item)
        end
    end
    for _, item in pairs(misplaced) do
        Follow(item)
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
        ns:HookSecureFunc(C_Container, name, OnSortStarted)
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
