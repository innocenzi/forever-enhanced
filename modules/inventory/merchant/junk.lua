-- Sells the junk Sell All Junk Items would sell (core/junk.lua: marked items
-- are added, locked items kept), through ns:SellJunk.

local _, ns = ...

local L = ns.L
local Merchant = ns:GetFeature("inventory", "merchant")

local Junk = {}
Merchant.Junk = Junk

local function GetSellValue(info)
    local sellPrice = select(11, C_Item.GetItemInfo(info.itemID))
    return (sellPrice or 0) * info.stackCount
end

-- Sells the junk and returns the money it should bring (0 when nothing is sold).
function Junk:Sell()
    if not Merchant:GetSetting("autoSellJunk") then
        return 0
    end

    local junk, keptCount, addedCount = ns:CollectJunk()
    if #junk == 0 then
        return 0
    end

    local value = 0
    for _, item in ipairs(junk) do
        value = value + GetSellValue(item.info)
    end
    ns:SellJunk(junk, keptCount, addedCount)

    Merchant:Announce(L["inventory.merchant.sold"]:format(#junk, GetMoneyString(value, true)))
    return value
end
