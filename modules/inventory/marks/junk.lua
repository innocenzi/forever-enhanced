-- Items marked as junk are junk for Sell All Junk Items and the merchant's
-- auto selling (core/junk.lua), which keep locked copies.

local _, ns = ...

local Marks = ns:GetFeature("inventory", "marks")

ns:AddJunkHandler(Marks, {
    part = "junk",
    IsJunk = function(_, info)
        return Marks:IsMarked(info.itemID, "junk")
    end,
})
