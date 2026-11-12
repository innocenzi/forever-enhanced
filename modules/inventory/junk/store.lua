-- Marked item IDs, per character: every copy of a marked item is junk.

local _, ns = ...

local Junk = ns:GetFeature("inventory", "junk")

local function GetMarks()
    local store = Junk:GetCharacterStore()
    store.items = store.items or {}
    return store.items
end

-- Public API: whether every copy of `itemID` is junk. Always false while the feature is inactive.
function Junk:IsMarked(itemID)
    return self.active and itemID ~= nil and GetMarks()[itemID] == true
end

function Junk:ToggleMarked(itemID)
    local marks = GetMarks()
    marks[itemID] = not marks[itemID] or nil
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end
