-- Item buttons (core/itembuttons.lua): one handler per mark (its part), drawing
-- the destination's icon on our own frame laid over the button, top-left where
-- Blizzard draws its junk coin (an item has one destination, so they never
-- stack), and adding the mark's entry to the item menu; plus Alt Left Click,
-- when "altClick" picks a mark.
--
-- The junk coin is Blizzard's, on the items Sell All Junk Items would sell
-- (core/junk.lua: not locked or in an excluded bag). Blizzard shows its coin on
-- poor items only at merchants: with junkCoin "merchant", marked items follow
-- it; with "always", every junk item shows ours, Blizzard's landing on top of
-- it at merchants. The other icons hide on locked items too.

local _, ns = ...

local L = ns.L
local Marks = ns:GetFeature("inventory", "marks")
local Locking = ns:GetFeature("inventory", "locking")

local Buttons = {}
Marks.Buttons = Buttons

local isBag = {}
for _, bagID in ipairs(ns.Containers.BAG_IDS) do
    isBag[bagID] = true
end

local function IsPoor(info)
    return info.quality == Enum.ItemQuality.Poor
end

local function ShowsJunkCoin(itemLocation)
    local always = Marks:GetSetting("junkCoin") == "always"
    if not always and not MerchantFrame:IsShown() then
        return false
    end
    if not ns:IsSoldAsJunk(itemLocation:GetBagAndSlot()) then
        return false
    end
    -- At merchants, Blizzard draws its own on poor items.
    return always or C_Item.GetItemQuality(itemLocation) ~= Enum.ItemQuality.Poor
end

-- Per destination:
--   atlas, width, height, offsetX   the icon (width nil: the atlas size)
--   menuText                        locale key of the menu entry
--   bagsOnly                        no icon in the bank
--   ShowsIcon(itemLocation, guid)   replaces the default rule (marked, not locked)
--   CanMark(info)                   whether the item can take the mark
--   IsShownMarked(info)             the menu checkbox shows it marked anyway
local MARKS = {
    -- Blizzard's JunkIcon (ContainerFrameItemButtonTemplate).
    junk = {
        atlas = "bags-junkcoin",
        offsetX = 1,
        offsetY = 0,
        menuText = "inventory.marks.markAsJunk",
        ShowsIcon = ShowsJunkCoin,
        -- Poor items are junk already, items without a sell price can't be sold.
        CanMark = function(info)
            return not IsPoor(info) and not info.hasNoValue
        end,
        IsShownMarked = IsPoor,
    },
    auction = {
        atlas = "auctioneer",
        width = 16,
        height = 16,
        offsetX = 1,
        offsetY = -1,
        menuText = "inventory.marks.markForAuction",
        -- Poor items are junk; bound items can't be auctioned.
        CanMark = function(info)
            return not IsPoor(info) and not info.isBound
        end,
    },
    -- Bank-marked items in the bank are where they belong.
    bank = {
        atlas = "banker",
        width = 16,
        height = 16,
        offsetX = 1,
        offsetY = -1,
        menuText = "inventory.marks.markForBank",
        bagsOnly = true,
        CanMark = function(info)
            return not IsPoor(info)
        end,
    },
}

-- Per destination, per Blizzard item button: our icon holder frame.
local holders = {}

local function CreateHolder(button, mark)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints()
    holder:SetFrameLevel(button:GetFrameLevel() + 1)
    local icon = holder:CreateTexture(nil, "OVERLAY", nil, 5)
    if mark.width then
        icon:SetAtlas(mark.atlas)
        icon:SetSize(mark.width, mark.height)
    else
        icon:SetAtlas(mark.atlas, TextureKitConstants.UseAtlasSize)
    end
    icon:SetPoint("TOPLEFT", mark.offsetX, mark.offsetY)
    return holder
end

local function ShowIcon(destination, button, shown)
    local holder = holders[destination][button]
    if shown and not holder then
        holder = CreateHolder(button, MARKS[destination])
        holders[destination][button] = holder
    end
    if holder then
        holder:SetShown(shown)
    end
end

local function ShowsIcon(destination, itemLocation, guid)
    local mark = MARKS[destination]
    if guid == nil then
        return false
    end
    if mark.ShowsIcon then
        return mark.ShowsIcon(itemLocation, guid)
    end
    if Locking:IsGUIDLocked(guid) or (mark.bagsOnly and not isBag[itemLocation:GetBagAndSlot()]) then
        return false
    end
    return Marks:IsMarked(C_Item.GetItemID(itemLocation), destination)
end

function Buttons:HideAll(destination)
    for _, holder in pairs(holders[destination]) do
        holder:Hide()
    end
end

local function GetItemInfo(itemLocation)
    return C_Container.GetContainerItemInfo(itemLocation:GetBagAndSlot())
end

local function AddMenuEntry(destination, rootDescription, itemLocation)
    local info = GetItemInfo(itemLocation)
    if not info then
        return
    end
    local mark = MARKS[destination]
    local checkbox = rootDescription:CreateCheckbox(L[mark.menuText], function()
        return (mark.IsShownMarked and mark.IsShownMarked(info)) or Marks:IsMarked(info.itemID, destination)
    end, function()
        Marks:ToggleDestination(info.itemID, destination)
    end)
    checkbox:SetEnabled(mark.CanMark(info))
end

-- Public API: the mark Alt Left Click toggles, or nil when it locks (the default,
-- Item locking's) or that mark is off.
function Marks:GetAltClickDestination()
    local destination = self:IsActive() and self:GetSetting("altClick") or nil
    if destination and destination ~= "lock" and self:IsPartActive(destination) then
        return destination
    end
end

-- Alt Left Click toggles the mark "altClick" picks, if the item can take it.
local function OnAltClick(destination, itemLocation)
    local info = Marks:GetAltClickDestination() == destination and GetItemInfo(itemLocation)
    if info and MARKS[destination].CanMark(info) then
        Marks:ToggleDestination(info.itemID, destination)
    end
end

for _, destination in ipairs(Marks.DESTINATIONS) do
    assert(MARKS[destination], "no mark for destination: " .. destination)
    holders[destination] = setmetatable({}, { __mode = "k" })
    ns:AddItemButtonHandler(Marks, {
        part = destination,
        Update = function(button, itemLocation, guid)
            ShowIcon(destination, button, ShowsIcon(destination, itemLocation, guid))
        end,
        OnAltClick = function(itemLocation)
            OnAltClick(destination, itemLocation)
        end,
        AddMenuEntries = function(rootDescription, itemLocation)
            AddMenuEntry(destination, rootDescription, itemLocation)
        end,
    })
end
