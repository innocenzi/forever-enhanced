-- The tooltip lines, right under the sell price and drawn like it:
-- "Auction price (3 days ago): 1g 20s" and, while Shift is held for a stack in
-- the bags or bank, "Auction price x20: 24g". Bound items can't be sold there
-- and show nothing, nor do comparison tooltips, which have no sell price either.
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
-- it is bound.
local function StackCount(data)
    local location = data.guid and C_Item.GetItemLocation(data.guid)
    if not location then
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

    local age = Auction:GetSetting("age") and FormatAge(GetServerTime() - seen)
    if age then
        local text = GRAY_FONT_COLOR:WrapTextInColorCode(age)
        GameTooltip_AddHighlightLine(tooltip, ns.L["inventory.auction.priceAge"]:format(text, FormatMoney(price)))
    else
        GameTooltip_AddHighlightLine(tooltip, ns.L["inventory.auction.price"]:format(FormatMoney(price)))
    end
    if count > 1 and Auction:GetSetting("stack") and IsShiftKeyDown() then
        local line = ns.L["inventory.auction.stackPrice"]:format(count, FormatMoney(price * count))
        GameTooltip_AddHighlightLine(tooltip, line)
    end
end, { price = true })
