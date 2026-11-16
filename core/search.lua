-- Item search for the boxes features add where the client's own search doesn't
-- reach (saved bank items, merchant items): an item matches by its name, item
-- type, subtype or equipment slot.

local _, ns = ...

local function Contains(haystack, text)
    return haystack ~= nil and haystack ~= "" and haystack:lower():find(text, 1, true) ~= nil
end

-- Whether the item matches `text` (lowercased; "" matches everything). `name`
-- may be nil while the item's data loads; `item` is an item ID or link, or nil.
function ns:MatchesItemSearch(text, name, item)
    if text == "" or Contains(name, text) then
        return true
    end
    if not item then
        return false
    end
    local _, itemType, itemSubType, equipLoc = C_Item.GetItemInfoInstant(item)
    return Contains(itemType, text) or Contains(itemSubType, text) or Contains(_G[equipLoc or ""], text)
end
