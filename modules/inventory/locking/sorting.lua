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
--   3. Locked items going home leave the slots the sort gave them, so the other
--      items of the sorted area close up behind them, in the sort's order (Reflow).
--      Each group of containers the sort fills as one (same bag type and
--      assignment, not ignored by cleanups) is filled in its own slot order. No
--      API says which, so it's read from the sorted layout: the order in which
--      items come before empty slots. A reserved slot (Reserved slots) its item
--      will fill, and the stack that feature moves there, are left to it; a
--      locked item going home to a reserved slot keeps it.
--   4. Two rounds of swaps put every item where it goes (Plan). Each round waits
--      for the server, and Blizzard redraws the bags after it: one swap per item
--      would take a round per item when each one's slot holds another misplaced
--      item (seen with nearly full bags). Items are told apart by what they are
--      (link and count), locked ones by GUID: the client merges a stack moved onto
--      a stack of the same item, which looks just like the swap we asked for.

local _, ns = ...

local Locking = ns:GetFeature("inventory", "locking")

local Sorting = {}
Locking.Sorting = Sorting

-- What each sort function sorts (the account bank isn't readable: locked items only).
local SORT_AREAS = { SortBags = "bags", SortBank = "bank", SortBankBags = "bank", SortAccountBankBags = false }
local SORT_TIMEOUT_SECONDS = 1 -- fallback when a sort reports nothing at all
-- Locks settled without a bag update: the sort moved nothing. Measured gap from the
-- last lock change to the sort's bag update is ~75ms; keep a wide margin, as firing
-- early would read stale positions (and nothing is visible when nothing moved).
local SORT_NO_MOVES_SECONDS = 0.3
local MAX_MOVES_PER_ITEM = 3

-- The slot orders a sort may fill a group of containers in.
local FILL_ORDERS = {
    { containersReversed = false, slotsReversed = false },
    { containersReversed = true, slotsReversed = true },
    { containersReversed = true, slotsReversed = false },
    { containersReversed = false, slotsReversed = true },
}

-- Bag flags assigning a bag to the items the sort puts there first.
local IGNORED_FLAGS = Enum.BagSlotFlags.DisableAutoSort + Enum.BagSlotFlags.ExcludeJunkSell
local ASSIGNMENT_FLAGS = {}
for _, flag in pairs(Enum.BagSlotFlags) do
    if bit.band(flag, IGNORED_FLAGS) == 0 then
        table.insert(ASSIGNMENT_FLAGS, flag)
    end
end
table.sort(ASSIGNMENT_FLAGS)

-- Where each locked item was before the sort: { [guid] = { bagID, slot } }.
local homes = {}
-- Areas sorted during this restore: { [area] = true }.
local sortedAreas = {}
-- The next round reads the layout a sort left.
local layoutPending = false
-- A sort of this restore moved items (its bag update came).
local sortMoved = false
-- What slots should end up holding: { { location, content } }.
local wanted = {}
-- Reserved slots their item fills (Reserved slots): { [slotKey] = itemID }.
local reserved = {}
-- The stacks Reserved slots moves to them: { [guid] = true }.
local pulled = {}
local hooksInstalled = false

local function SlotKey(location)
    return location.bagID .. ":" .. location.slot
end

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

-- What each slot holds: entries { location, content, itemID, guid, isLocked } in
-- container order, and the same by slot key. A locked item's content is its GUID.
local function ReadLayout()
    local entries, bySlot = {}, {}
    ns.Containers:ForEachSlot(ns.Containers.ALL_CONTAINER_IDS, function(bagID, slot)
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info then
            local guid = ns.Containers:GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot))
            local isLocked = Locking:IsGUIDLocked(guid)
            local entry = {
                location = { bagID = bagID, slot = slot },
                content = isLocked and guid or (info.hyperlink or info.itemID) .. "#" .. info.stackCount,
                itemID = info.itemID,
                guid = guid,
                isLocked = isLocked,
            }
            table.insert(entries, entry)
            bySlot[SlotKey(entry.location)] = entry
        end
    end)
    return entries, bySlot
end

-- The key shared by the bags the sort fills as one, or nil for a bag it skips.
local function GetBagSortKey(bagID)
    if bagID == Enum.BagIndex.Backpack then
        if C_Container.GetBackpackAutosortDisabled() then
            return nil
        end
    elseif C_Container.GetBagSlotFlag(bagID, Enum.BagSlotFlags.DisableAutoSort) then
        return nil
    end
    local _, family = C_Container.GetContainerNumFreeSlots(bagID)
    local key = bagID == Enum.BagIndex.ReagentBag and "reagents" or tostring(family or 0)
    if bagID ~= Enum.BagIndex.Backpack then
        for _, flag in ipairs(ASSIGNMENT_FLAGS) do
            if C_Container.GetBagSlotFlag(bagID, flag) then
                key = key .. "," .. flag
            end
        end
    end
    return key
end

-- The same for a bank tab, from its settings.
local function GetBankTabSortKey(tabData)
    local flags = tabData.depositFlags or 0
    if bit.band(flags, Enum.BagSlotFlags.DisableAutoSort) ~= 0 then
        return nil
    end
    local _, family = C_Container.GetContainerNumFreeSlots(tabData.ID)
    return (family or 0) .. "," .. (flags - bit.band(flags, IGNORED_FLAGS))
end

-- The area's groups of containers the sort fills as one: { { bagID, ... }, ... }.
local function GetGroups(area)
    local groups, byKey = {}, {}
    local function Add(bagID, key)
        if key and C_Container.GetContainerNumSlots(bagID) > 0 then
            if not byKey[key] then
                byKey[key] = {}
                table.insert(groups, byKey[key])
            end
            table.insert(byKey[key], bagID)
        end
    end
    if area == "bags" then
        for _, bagID in ipairs(ns.Containers.BAG_IDS) do
            Add(bagID, GetBagSortKey(bagID))
        end
    else
        for _, tabData in ipairs(C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character) or {}) do
            Add(tabData.ID, GetBankTabSortKey(tabData))
        end
    end
    return groups
end

local function ListSlots(containerIDs, order)
    local slots = {}
    local count = #containerIDs
    for i = 1, count do
        local bagID = containerIDs[order.containersReversed and count + 1 - i or i]
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for j = 1, numSlots do
            table.insert(slots, { bagID = bagID, slot = order.slotsReversed and numSlots + 1 - j or j })
        end
    end
    return slots
end

-- Empty slots coming before an item: none in the order the sort filled.
local function CountHoles(slots, bySlot)
    local holes, empty = 0, 0
    for _, location in ipairs(slots) do
        if bySlot[SlotKey(location)] then
            holes = holes + empty
            empty = 0
        else
            empty = empty + 1
        end
    end
    return holes
end

-- The group's slots in the order the sort filled them (the first order on a tie).
local function GetFillOrder(containerIDs, bySlot)
    local best, fewestHoles
    for _, order in ipairs(FILL_ORDERS) do
        local slots = ListSlots(containerIDs, order)
        local holes = CountHoles(slots, bySlot)
        if not fewestHoles or holes < fewestHoles then
            best, fewestHoles = slots, holes
        end
    end
    return best
end

-- Whether the entry is an item its reserved slot keeps, or the stack Reserved
-- slots moves there: the reflow leaves both to that feature.
local function IsLeftToSlots(key, entry)
    return not entry.isLocked and (reserved[key] == entry.itemID or pulled[entry.guid] == true)
end

-- The area's reserved slots its item fills (Reserved slots), unless a locked
-- item goes there: those holding it, and those the item will move to, taking
-- the stack Reserved slots takes (Slots:FindStackToMove).
local function FindReservedSlots(area, groups, bySlot, isWanted)
    local Slots = ns:GetFeature("inventory", "slots")
    local taken = {}
    for _, containerIDs in ipairs(groups) do
        ns.Containers:ForEachSlot(containerIDs, function(bagID, slot)
            local itemID = Slots:GetReservedItem(bagID, slot)
            local key = bagID .. ":" .. slot
            if not itemID or isWanted[key] then
                return
            end
            local entry = bySlot[key]
            if entry and not entry.isLocked and entry.itemID == itemID then
                reserved[key] = itemID
                return
            end
            local source = Slots:FindStackToMove(area, itemID, taken)
            if source then
                taken[SlotKey(source)] = true
                reserved[key] = itemID
                pulled[bySlot[SlotKey(source)].guid] = true
            end
        end)
    end
end

-- The group's items, in the sort's order, take its slots no locked item goes
-- back to and no reserved item fills.
local function Reflow(containerIDs, bySlot, isWanted)
    local contents, free = {}, {}
    for _, location in ipairs(GetFillOrder(containerIDs, bySlot)) do
        local key = SlotKey(location)
        local entry = bySlot[key]
        if entry and not entry.isLocked and not IsLeftToSlots(key, entry) then
            table.insert(contents, entry.content)
        end
        if not isWanted[key] and not reserved[key] then
            table.insert(free, location)
        end
    end
    for i = 1, math.min(#contents, #free) do
        table.insert(wanted, { location = free[i], content = contents[i] })
    end
end

-- Locked items go home and, once a sort moved items, the others close up behind them.
local function BuildWanted(bySlot)
    wanted, reserved, pulled = {}, {}, {}
    local isWanted = {}
    for guid, home in pairs(homes) do
        table.insert(wanted, { location = home, content = guid })
        isWanted[SlotKey(home)] = true
    end
    if not sortMoved then
        return
    end
    for area in pairs(sortedAreas) do
        local groups = GetGroups(area)
        FindReservedSlots(area, groups, bySlot, isWanted)
        for _, containerIDs in ipairs(groups) do
            Reflow(containerIDs, bySlot, isWanted)
        end
    end
end

local function IsSameSlot(a, b)
    return a.bagID == b.bagID and a.slot == b.slot
end

-- The moves putting `items` where they go: a chain (each one's target holds the
-- next one, the last one's holds no misplaced item) or a cycle (the last one's
-- holds the first). Their slots form a cycle: what slots[i] holds goes to
-- slots[i + 1], what the last one holds to slots[1]. Two slots just swap.
-- Otherwise this round swaps slots[j + 1] and slots[n + 1 - j], leaving swaps of
-- two slots for the next round: any order is put right in two rounds.
local function AddMoves(moves, items)
    local slots = {}
    for _, item in ipairs(items) do
        table.insert(slots, item.location)
    end
    local lastTarget = items[#items].target
    if not IsSameSlot(lastTarget, slots[1]) then
        table.insert(slots, lastTarget)
    end
    local n = #slots
    if n == 2 then
        table.insert(moves, { from = slots[1], to = slots[2], key = items[1].key })
        return
    end
    for j = 1, math.floor((n - 1) / 2) do
        table.insert(moves, { from = slots[j + 1], to = slots[n + 1 - j], key = items[j + 1].key })
    end
end

-- This round's swaps putting misplaced items where they go. Wanted contents
-- found nowhere (an item gone, or merged into another stack) are dropped.
local function Plan()
    local entries, bySlot = ReadLayout()
    if layoutPending then
        layoutPending = false
        BuildWanted(bySlot)
    end

    local wantedAt = {}
    for _, want in ipairs(wanted) do
        wantedAt[SlotKey(want.location)] = want.content
    end
    -- Where each content can be taken from: slots not holding what they should,
    -- in container order, but for what Reserved slots moves.
    local sources = {}
    for _, entry in ipairs(entries) do
        local key = SlotKey(entry.location)
        if wantedAt[key] ~= entry.content and not IsLeftToSlots(key, entry) then
            sources[entry.content] = sources[entry.content] or {}
            table.insert(sources[entry.content], entry.location)
        end
    end

    -- Misplaced items by the slot they're in, and the slots they go to.
    local misplaced, isTarget, kept = {}, {}, {}
    for _, want in ipairs(wanted) do
        local key = SlotKey(want.location)
        local entry = bySlot[key]
        if entry and entry.content == want.content then
            table.insert(kept, want)
        else
            local source = sources[want.content] and table.remove(sources[want.content], 1)
            if source then
                misplaced[SlotKey(source)] = { location = source, target = want.location, key = key }
                isTarget[key] = true
                table.insert(kept, want)
            end
        end
    end
    wanted = kept

    local moves, seen = {}, {}
    local function Follow(item)
        local items = {}
        while item and not seen[item] do
            seen[item] = true
            table.insert(items, item)
            item = misplaced[SlotKey(item.target)]
        end
        if #items > 0 then
            AddMoves(moves, items)
        end
    end
    -- Chains start from a slot nothing goes to; the items left form cycles.
    for key, item in pairs(misplaced) do
        if not isTarget[key] then
            Follow(item)
        end
    end
    for _, item in pairs(misplaced) do
        Follow(item)
    end
    return moves
end

local mover = ns:CreateMover({ Plan = Plan, maxMovesPerKey = MAX_MOVES_PER_ITEM })

local listener = ns:CreateEventListener({
    -- While the sort runs, each lock change pushes back the "moved nothing" check.
    ITEM_LOCK_CHANGED = function()
        if mover:IsWaitingForServer() then
            mover:WaitForServer(SORT_NO_MOVES_SECONDS)
        end
    end,
    BAG_UPDATE_DELAYED = function()
        if mover:IsWaitingForServer() then
            sortMoved = true
        end
    end,
})

local function OnSortStarted(area)
    if not Locking:IsActive() or not Locking:GetSetting("keepInPlace") then
        return
    end

    -- A sort started while restoring keeps the original homes.
    if not mover:IsRunning() then
        homes = FindLockedItems()
        if not next(homes) then
            return
        end
        sortedAreas, sortMoved, wanted = {}, false, {}
    end
    if area then
        sortedAreas[area] = true
    end
    layoutPending = true
    mover:WaitForServer(SORT_TIMEOUT_SECONDS)
end

-- hooksecurefunc hooks can't be removed: install once, OnSortStarted checks IsActive().
function Sorting:Enable()
    listener:Start()
    if hooksInstalled then
        return
    end
    hooksInstalled = true
    for name, area in pairs(SORT_AREAS) do
        ns:HookSecureFunc(C_Container, name, function()
            OnSortStarted(area or nil)
        end)
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
