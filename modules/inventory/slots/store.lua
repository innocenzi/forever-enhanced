-- Reservations, per character: { [bagID] = { [slot] = itemID } }. A slot a
-- smaller bag no longer has keeps its reservation for when it comes back.

local _, ns = ...

local Slots = ns:GetFeature("inventory", "slots")

local function GetReservations()
    local store = Slots:GetCharacterStore()
    store.reservations = store.reservations or {}
    return store.reservations
end

-- Public API: the item ID the slot is reserved for, or nil.
-- Always nil while the feature is inactive.
function Slots:GetReservedItem(bagID, slot)
    if not self.active then
        return nil
    end
    local bag = GetReservations()[bagID]
    return bag and bag[slot]
end

-- Calls func(bagID, slot, itemID) for every reservation in the given containers.
function Slots:ForEachReservation(containerIDs, func)
    local reservations = GetReservations()
    for _, bagID in ipairs(containerIDs) do
        for slot, itemID in pairs(reservations[bagID] or {}) do
            func(bagID, slot, itemID)
        end
    end
end

-- Reserves the slot for itemID, or frees it when it already is.
function Slots:ToggleReservation(itemLocation, itemID)
    local bagID, slot = itemLocation:GetBagAndSlot()
    local reservations = GetReservations()
    local bag = reservations[bagID] or {}
    bag[slot] = bag[slot] ~= itemID and itemID or nil
    reservations[bagID] = next(bag) and bag or nil
    ns:RefreshItemButtons()
    self.Restore:OnReservationsChanged()
end
