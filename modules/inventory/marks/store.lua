-- Each marked item ID's destination ("junk" | "auction" | "bank"), per
-- character: one destination per item.

local _, ns = ...

local Marks = ns:GetFeature("inventory", "marks")

local function GetDestinations()
    local store = Marks:GetCharacterStore()
    store.destinations = store.destinations or {}
    return store.destinations
end

-- Public API: whether items can be marked for `destination` ("junk" | "auction"
-- | "bank"): its mark is on.
function Marks:IsDestinationActive(destination)
    return self:IsPartActive(destination)
end

-- Public API: where every copy of `itemID` goes, or nil. Only destinations whose
-- part (toggle) is active.
function Marks:GetDestination(itemID)
    local destination = itemID ~= nil and GetDestinations()[itemID] or nil
    if destination and self:IsDestinationActive(destination) then
        return destination
    end
end

-- Public API: whether every copy of `itemID` goes to `destination`.
function Marks:IsMarked(itemID, destination)
    return self:GetDestination(itemID) == destination
end

-- Marks `itemID` for `destination` in place of any other mark, or unmarks it.
function Marks:ToggleDestination(itemID, destination)
    local destinations = GetDestinations()
    destinations[itemID] = not self:IsMarked(itemID, destination) and destination or nil
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end
