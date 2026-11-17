-- Each marked item ID's destinations, per character: a set of "junk" |
-- "auction" | "bank" | "mail". Junk excludes the others; auction house, bank
-- and mail combine. Older saves hold a single destination string, read as a
-- set of one. Items marked for mail also keep who they go to (recipients),
-- and the last recipient entered pre-fills the next.

local _, ns = ...

local Marks = ns:GetFeature("inventory", "marks")

-- Destinations that exclude every other.
local EXCLUSIVE = { junk = true }

local function GetStore()
    local store = Marks:GetCharacterStore()
    store.destinations = store.destinations or {}
    store.recipients = store.recipients or {}
    return store
end

local function GetDestinations()
    return GetStore().destinations
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
-- | "bank" | "mail"): its mark is on.
function Marks:IsDestinationActive(destination)
    return self:IsPartActive(destination)
end

-- Public API: whether every copy of `itemID` goes to `destination`, its mark
-- being on.
function Marks:IsMarked(itemID, destination)
    local marks = itemID ~= nil and GetMarks(itemID) or nil
    return marks ~= nil and marks[destination] == true and self:IsDestinationActive(destination)
end

-- Public API: who `itemID` is mailed to, or nil when it isn't marked for mail.
function Marks:GetRecipient(itemID)
    if self:IsMarked(itemID, "mail") then
        return GetStore().recipients[itemID]
    end
end

-- The recipient the mail dialog starts with: the last one entered, or nil.
function Marks:GetLastRecipient()
    return GetStore().lastRecipient
end

local function Save(itemID, marks)
    local store = GetStore()
    store.destinations[itemID] = next(marks) and marks or nil
    if not marks.mail then
        store.recipients[itemID] = nil
    end
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end

local function Add(marks, destination)
    for other in pairs(marks) do
        if EXCLUSIVE[destination] or EXCLUSIVE[other] then
            marks[other] = nil
        end
    end
    marks[destination] = true
end

-- Marks `itemID` for `destination`, or unmarks it. Junk replaces the other
-- marks, and they replace junk.
function Marks:ToggleDestination(itemID, destination)
    local marks = GetMarks(itemID) or {}
    if self:IsMarked(itemID, destination) then
        marks[destination] = nil
    else
        Add(marks, destination)
    end
    Save(itemID, marks)
end

-- Marks `itemID` for mail to `recipient`, who becomes the last recipient.
function Marks:MarkForMail(itemID, recipient)
    local store = GetStore()
    local marks = GetMarks(itemID) or {}
    Add(marks, "mail")
    store.recipients[itemID] = recipient
    store.lastRecipient = recipient
    Save(itemID, marks)
end
