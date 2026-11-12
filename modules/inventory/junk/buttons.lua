-- Item buttons (core/itembuttons.lua): Blizzard's junk coin on marked items
-- that would be sold (not locked), drawn on our own frame laid over the button,
-- where Blizzard draws it at merchants; and the "Mark as junk" menu entry.

local _, ns = ...

local L = ns.L
local Junk = ns:GetFeature("inventory", "junk")
local Locking = ns:GetFeature("inventory", "locking")

local Buttons = {}
Junk.Buttons = Buttons

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

function Buttons:HideAll()
    for _, holder in pairs(holders) do
        holder:Hide()
    end
end

ns:AddItemButtonHandler(Junk, {
    Update = function(button, itemLocation, guid)
        local marked = guid ~= nil and Junk:IsMarked(C_Item.GetItemID(itemLocation))
        ShowCoin(button, marked and not Locking:IsLocked(itemLocation))
    end,
    -- Poor quality items are junk already, items without a sell price can't be sold.
    AddMenuEntries = function(rootDescription, itemLocation)
        local info = C_Container.GetContainerItemInfo(itemLocation:GetBagAndSlot())
        if not info then
            return
        end
        local isPoor = info.quality == Enum.ItemQuality.Poor
        local checkbox = rootDescription:CreateCheckbox(L["inventory.junk.mark"], function()
            return isPoor or Junk:IsMarked(info.itemID)
        end, function()
            Junk:ToggleMarked(info.itemID)
        end)
        checkbox:SetEnabled(not isPoor and not info.hasNoValue)
    end,
})
