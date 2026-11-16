-- The search part's box, at the top right of the merchant's items tab: beside
-- the filter dropdown when the client shows it, in its place otherwise. It
-- isn't tied to the bags' search box: the bags show what the player owns, the
-- merchant what they can buy.

local _, ns = ...

local Merchant = ns:GetFeature("inventory", "merchant")
local Search = Merchant.Search

local Box = {}
Search.Box = Box

local WIDTH = 130
-- Narrower beside the filter dropdown, to clear the portrait.
local WIDTH_BESIDE_FILTER = 100
local HEIGHT = 20

local box

function Box:Create()
    if box then
        return
    end
    box = CreateFrame("EditBox", nil, MerchantFrame, "SearchBoxTemplate")
    box:SetHeight(HEIGHT)
    box:Hide()
    box:HookScript("OnTextChanged", function(editBox)
        Search:SetText(editBox:GetText())
    end)
end

-- Shows the box on the items tab while the part runs, and places it.
function Box:Update()
    if not box then
        return
    end
    box:SetShown(Merchant:IsPartActive("search") and MerchantFrame.selectedTab == 1)
    box:ClearAllPoints()
    local filter = MerchantFrame.FilterDropdown
    if filter:IsShown() then
        box:SetWidth(WIDTH_BESIDE_FILTER)
        box:SetPoint("RIGHT", filter, "LEFT", -8, 0)
    else
        box:SetWidth(WIDTH)
        box:SetPoint("TOPRIGHT", -12, -33)
    end
end

function Box:Clear()
    if box then
        box:SetText("")
        box:ClearFocus()
    end
end
