-- Junk marks (the markJunk part): marked item IDs, per character, so every
-- copy of a marked item is junk for Sell All Junk Items and auto selling
-- (core/junk.lua). The coin and the menu entry are in buttons.lua.

local _, ns = ...

local Merchant = ns:GetFeature("inventory", "merchant")

local Marks = {}
Merchant.Marks = Marks

local function GetMarks()
    local store = Merchant:GetCharacterStore()
    store.junk = store.junk or {}
    return store.junk
end

-- Public API: whether every copy of `itemID` is junk. Always false while the part is inactive.
function Merchant:IsMarkedJunk(itemID)
    return self:IsPartActive("markJunk") and itemID ~= nil and GetMarks()[itemID] == true
end

function Merchant:ToggleMarkedJunk(itemID)
    local marks = GetMarks()
    marks[itemID] = not marks[itemID] or nil
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end

ns:AddJunkHandler(Merchant, {
    part = "markJunk",
    IsJunk = function(_, info)
        return Merchant:IsMarkedJunk(info.itemID)
    end,
})

function Marks:Enable()
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end

function Marks:Disable()
    Merchant.Buttons:HideAll()
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end
