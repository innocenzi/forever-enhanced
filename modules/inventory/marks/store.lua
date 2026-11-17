-- Each marked item ID's destinations, per character: a set of "junk" |
-- "auction" | "bank". Junk excludes the others; auction house and bank combine.
-- Older saves hold a single destination string, read as a set of one.

local _, ns = ...

local Marks = ns:GetFeature("inventory", "marks")

-- Destinations that exclude every other.
local EXCLUSIVE = { junk = true }

local function GetDestinations()
    local store = Marks:GetCharacterStore()
    store.destinations = store.destinations or {}
    return store.destinations
end

-- The set of destinations saved for `itemID`, or nil.
local function GetMarks(itemID)
    local destinations = GetDestinations()
    local marks = destinations[itemID]
    if type(marks) == "string" then
        marks = { [marks] = true }
        destinations[itemID] = marks
    end
    return marks
end

-- Public API: whether items can be marked for `destination` ("junk" | "auction"
-- | "bank"): its mark is on.
function Marks:IsDestinationActive(destination)
    return self:IsPartActive(destination)
end

-- Public API: whether every copy of `itemID` goes to `destination`, its mark
-- being on.
function Marks:IsMarked(itemID, destination)
    local marks = itemID ~= nil and GetMarks(itemID) or nil
    return marks ~= nil and marks[destination] == true and self:IsDestinationActive(destination)
end

-- Marks `itemID` for `destination`, or unmarks it. Junk replaces the other
-- marks, and they replace junk.
function Marks:ToggleDestination(itemID, destination)
    local marks = GetMarks(itemID) or {}
    if self:IsMarked(itemID, destination) then
        marks[destination] = nil
    else
        for other in pairs(marks) do
            if EXCLUSIVE[destination] or EXCLUSIVE[other] then
                marks[other] = nil
            end
        end
        marks[destination] = true
    end
    GetDestinations()[itemID] = next(marks) and marks or nil
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end
