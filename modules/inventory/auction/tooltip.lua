-- The tooltip lines, right under the sell price and drawn like it. Like the sell
-- price, the price is the whole stack's for a stack in the bags or bank:
-- "Auction price (3 days ago): 24g" and, while Shift is held, "Auction unit
-- price: 1g 20s". Bound items can't be sold there and show nothing, nor do
-- comparison tooltips, which have no sell price either.
--
-- Only bag and bank items have a stack, and their buttons rebuild the tooltip
-- when Shift changes: no refresh of our own.

local _, ns = ...

local Auction = ns:GetFeature("inventory", "auction")
local Store = Auction.Store

local HOUR = 60 * 60
local DAY = 24 * HOUR

-- "3 days ago", or nil while the price is less than an hour old.
local function FormatAge(seconds)
    if seconds >= DAY then
        return ns.L["inventory.auction.daysAgo"]:format(math.floor(seconds / DAY))
    elseif seconds >= HOUR then
        return ns.L["inventory.auction.hoursAgo"]:format(math.floor(seconds / HOUR))
    end
end

-- Like the client's sell price line (GameTooltip_OnTooltipAddMoney).
local function FormatMoney(copper)
    return MoneyFormatterUtil.FormatMoney(copper, GameTooltipMoneyFormat)
end

-- How many items the tooltip's item is (1 outside bags and bank), or nil when
-- it is bound. A buyback item has a GUID, but its location is neither a bag
-- slot nor an equipment slot, which the item location APIs reject (IsValid
-- included: it calls C_Item.DoesItemExist).
local function StackCount(data)
    local location = data.guid and C_Item.GetItemLocation(data.guid)
    if not location or not location:HasAnyLocation() then
        return 1
    end
    if C_Item.IsBound(location) then
        return nil
    end
    return C_Item.GetStackCount(location)
end

ns:AddItemTooltipHandler(Auction, function(tooltip, data)
    if tooltip.isShopping then
        return
    end
    local price, seen = Store:GetPrice(data.id)
    if not price then
        return
    end
    local count = StackCount(data)
    if not count then
        return
    end

    local total = FormatMoney(price * count)
    local age = Auction:GetSetting("age") and FormatAge(GetServerTime() - seen)
    if age then
        local text = GRAY_FONT_COLOR:WrapTextInColorCode(age)
        GameTooltip_AddHighlightLine(tooltip, ns.L["inventory.auction.priceAge"]:format(text, total))
    else
        GameTooltip_AddHighlightLine(tooltip, ns.L["inventory.auction.price"]:format(total))
    end
    if count > 1 and Auction:GetSetting("unit") and IsShiftKeyDown() then
        GameTooltip_AddHighlightLine(tooltip, ns.L["inventory.auction.unitPrice"]:format(FormatMoney(price)))
    end
end, { price = true })
