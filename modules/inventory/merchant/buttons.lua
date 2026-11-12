-- Item buttons (core/itembuttons.lua), for the markJunk part: Blizzard's junk
-- coin, drawn on our own frame laid over the button where Blizzard draws its
-- own, on the items Sell All Junk Items would sell (core/junk.lua: not locked
-- or in an excluded bag); and the "Mark as junk" entry of the item menu.
-- Blizzard shows its coin on poor items only at merchants: with junkCoin
-- "merchant", marked items follow it; with "always", every junk item shows
-- ours, Blizzard's landing on top of it at merchants.

local _, ns = ...

local L = ns.L
local Merchant = ns:GetFeature("inventory", "merchant")

local Buttons = {}
Merchant.Buttons = Buttons

-- Blizzard's JunkIcon (ContainerFrameItemButtonTemplate).
local COIN_ATLAS = "bags-junkcoin"
local COIN_OFFSET_X = 1

-- Per Blizzard item button: our coin holder frame.
local holders = setmetatable({}, { __mode = "k" })

local function CreateHolder(button)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints()
    holder:SetFrameLevel(button:GetFrameLevel() + 1)
    local coin = holder:CreateTexture(nil, "OVERLAY", nil, 5)
    coin:SetAtlas(COIN_ATLAS, TextureKitConstants.UseAtlasSize)
    coin:SetPoint("TOPLEFT", COIN_OFFSET_X, 0)
    return holder
end

local function ShowCoin(button, shown)
    local holder = holders[button]
    if shown and not holder then
        holder = CreateHolder(button)
        holders[button] = holder
    end
    if holder then
        holder:SetShown(shown)
    end
end

-- Whether the item shows our coin.
local function ShowsCoin(itemLocation)
    local always = Merchant:GetSetting("junkCoin") == "always"
    if not always and not MerchantFrame:IsShown() then
        return false
    end
    if not ns:IsSoldAsJunk(itemLocation:GetBagAndSlot()) then
        return false
    end
    -- At merchants, Blizzard draws its own on poor items.
    return always or C_Item.GetItemQuality(itemLocation) ~= Enum.ItemQuality.Poor
end

function Buttons:HideAll()
    for _, holder in pairs(holders) do
        holder:Hide()
    end
end

ns:AddItemButtonHandler(Merchant, {
    part = "markJunk",
    Update = function(button, itemLocation, guid)
        ShowCoin(button, guid ~= nil and ShowsCoin(itemLocation))
    end,
    -- Poor quality items are junk already, items without a sell price can't be sold.
    AddMenuEntries = function(rootDescription, itemLocation)
        local info = C_Container.GetContainerItemInfo(itemLocation:GetBagAndSlot())
        if not info then
            return
        end
        local isPoor = info.quality == Enum.ItemQuality.Poor
        local checkbox = rootDescription:CreateCheckbox(L["inventory.merchant.markAsJunk"], function()
            return isPoor or Merchant:IsMarkedJunk(info.itemID)
        end, function()
            Merchant:ToggleMarkedJunk(info.itemID)
        end)
        checkbox:SetEnabled(not isPoor and not info.hasNoValue)
    end,
})
