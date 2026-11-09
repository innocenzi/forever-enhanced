-- Keeps locked items in their slot when bags or bank are sorted.
--
-- Blizzard's sort runs on the server and can't skip single items, so we let it
-- run and put locked items back afterwards:
--   1. Hooking the C_Container sort functions catches every way to start a sort
--      (bag button, portrait menu, bank, other addons). The hook runs before the
--      server moves anything, so it records where each locked item is.
--   2. Measured on Forever: the server busies and frees slots (ITEM_LOCK_CHANGED)
--      for ~100ms, then delivers all moves in one BAG_UPDATE_DELAYED. Slots are
--      freed *before* positions update, so only a bag update means positions
--      are current. The restore starts on the sort's bag update; a sort that
--      moved nothing sends none, and ends once lock changes settle.
--   3. Each round swaps every misplaced locked item home at once (swaps that
--      don't share a slot); the next round starts on the bag update that
--      follows, once those slots are free. Rounds re-read positions, so a late
--      server batch just costs one more round.
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
local MOVE_TIMEOUT_SECONDS = 1 -- fallback when a round's swaps never report back
local GIVE_UP_SECONDS = 20 -- abandon a restore that never finishes
local MAX_MOVES_PER_ITEM = 3

-- Active restore:
--   phase: "sorting" (waiting for the server sort) or "restoring" (our swaps in flight)
--   homes: { [guid] = { bagID, slot } }, moves: { [guid] = count }
--   pending: slots touched by the last round, timer, giveUpTimer
local session
local hooksInstalled = false
local containerIDs

local function GetContainerIDs()
    if not containerIDs then
        local seen = {}
        containerIDs = {}
        for _, bagID in pairs(Enum.BagIndex) do
            if not seen[bagID] then
                seen[bagID] = true
                table.insert(containerIDs, bagID)
            end
        end
    end
    return containerIDs
end

local function FindLockedItems()
    local found = {}
    for _, bagID in ipairs(GetContainerIDs()) do
        for slot = 1, C_Container.GetContainerNumSlots(bagID) do
            local guid = Locking.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot))
            if Locking:IsGUIDLocked(guid) then
                found[guid] = { bagID = bagID, slot = slot }
            end
        end
    end
    return found
end

local function SlotKey(location)
    return location.bagID .. ":" .. location.slot
end

local function IsSlotBusy(location)
    local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
    return info ~= nil and info.isLocked
end

local function ArePendingSlotsFree()
    for _, location in ipairs(session.pending) do
        if IsSlotBusy(location) then
            return false
        end
    end
    return not CursorHasItem()
end

local listener

local function EndSession()
    if not session then
        return
    end
    if session.timer then
        session.timer:Cancel()
    end
    session.giveUpTimer:Cancel()
    session = nil
    listener:Stop()
end

local RunRound

-- Runs the next round after `seconds` (0: next frame), replacing any scheduled one.
local function Schedule(seconds)
    if session.timer then
        session.timer:Cancel()
    end
    session.timer = C_Timer.NewTimer(seconds, RunRound)
end

local function Swap(from, to)
    C_Container.PickupContainerItem(from.bagID, from.slot)
    C_Container.PickupContainerItem(to.bagID, to.slot)
end

-- Swaps every misplaced locked item home, skipping swaps that would share a slot
-- or touch a busy one (they go in a later round).
function RunRound()
    session.timer = nil

    if CursorHasItem() then
        Schedule(MOVE_TIMEOUT_SECONDS)
        return
    end

    local current = FindLockedItems()
    local used, pending = {}, {}
    local misplaced = false

    for guid, home in pairs(session.homes) do
        local location = current[guid]
        local moves = session.moves[guid] or 0

        -- Gone (merged into another stack), home, or refusing to move: done with it.
        if not location or SlotKey(location) == SlotKey(home) or moves >= MAX_MOVES_PER_ITEM then
            session.homes[guid] = nil
        else
            misplaced = true
            local fromKey, toKey = SlotKey(location), SlotKey(home)
            if not used[fromKey] and not used[toKey] and not IsSlotBusy(location) and not IsSlotBusy(home) then
                used[fromKey], used[toKey] = true, true
                session.moves[guid] = moves + 1
                Swap(location, home)
                table.insert(pending, location)
                table.insert(pending, home)
            end
        end
    end

    if not misplaced then
        EndSession()
        return
    end

    session.phase = "restoring"
    session.pending = pending
    Schedule(MOVE_TIMEOUT_SECONDS)
end

-- Item positions are current: the sort (or our last round) has landed.
local function OnBagsUpdated()
    if session and (session.phase == "sorting" or ArePendingSlotsFree()) then
        Schedule(0)
    end
end

-- While the sort runs, each lock change pushes back the "moved nothing" check.
local function OnLocksChanged()
    if session and session.phase == "sorting" then
        Schedule(SORT_NO_MOVES_SECONDS)
    end
end

listener = ns.CreateEventListener({
    BAG_UPDATE_DELAYED = OnBagsUpdated,
    ITEM_LOCK_CHANGED = OnLocksChanged,
})

local function OnSortStarted()
    if not Locking:IsActive() or not Locking:GetSetting("keepInPlace") then
        return
    end

    -- A sort started while restoring keeps the original homes.
    if not session then
        local homes = FindLockedItems()
        if not next(homes) then
            return
        end
        session = {
            homes = homes,
            moves = {},
            pending = {},
            giveUpTimer = C_Timer.NewTimer(GIVE_UP_SECONDS, EndSession),
        }
        listener:Start()
    end

    session.phase = "sorting"
    Schedule(SORT_TIMEOUT_SECONDS)
end

-- hooksecurefunc hooks can't be removed: install once, OnSortStarted checks IsActive().
function Sorting:Enable()
    if hooksInstalled then
        return
    end
    hooksInstalled = true
    for _, name in ipairs(SORT_FUNCTIONS) do
        hooksecurefunc(C_Container, name, OnSortStarted)
    end
end

function Sorting:Disable()
    EndSession()
end
