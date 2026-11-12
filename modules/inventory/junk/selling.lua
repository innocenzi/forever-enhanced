-- Marked items are junk for Sell All Junk Items and auto selling (core/junk.lua).

local _, ns = ...

local Junk = ns:GetFeature("inventory", "junk")

ns:AddJunkHandler(Junk, {
    IsJunk = function(_, info)
        return Junk:IsMarked(info.itemID)
    end,
})
