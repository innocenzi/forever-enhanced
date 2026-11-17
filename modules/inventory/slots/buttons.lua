-- Item buttons (core/itembuttons.lua): the reserved item's icon, faded, in its
-- empty slot (the "showIcon" setting), and the "Reserve this slot" entry of the
-- item menu, on items and on empty reserved slots.

local _, ns = ...

local L = ns.L
local Slots = ns:GetFeature("inventory", "slots")

local Buttons = {}
Slots.Buttons = Buttons

local ICON_ALPHA = 0.4
local ICON_INSET = 2

-- Per Blizzard item button: our frame holding the faded icon.
local ghosts = setmetatable({}, { __mode = "k" })

local function GetGhost(button)
    local ghost = ghosts[button]
    if not ghost then
        ghost = CreateFrame("Frame", nil, button)
        ghost:SetAllPoints()
        ghost:SetFrameLevel(button:GetFrameLevel() + 1)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetPoint("TOPLEFT", ICON_INSET, -ICON_INSET)
        ghost.icon:SetPoint("BOTTOMRIGHT", -ICON_INSET, ICON_INSET)
        ghost.icon:SetDesaturated(true)
        ghost.icon:SetAlpha(ICON_ALPHA)
        ghosts[button] = ghost
    end
    return ghost
end

function Buttons:HideAll()
    for _, ghost in pairs(ghosts) do
        ghost:Hide()
    end
end

local function GetReservedItem(itemLocation)
    return Slots:GetReservedItem(itemLocation:GetBagAndSlot())
end

ns:AddItemButtonHandler(Slots, {
    Update = function(button, itemLocation, guid)
        local itemID = not guid and Slots:GetSetting("showIcon") and GetReservedItem(itemLocation)
        if itemID then
            local ghost = GetGhost(button)
            ghost.icon:SetTexture(C_Item.GetItemIconByID(itemID))
            ghost:Show()
        elseif ghosts[button] then
            ghosts[button]:Hide()
        end
    end,
    EmptySlotItem = GetReservedItem,
    emptySlotEntries = true,
    -- Next to the lock: both keep an item where it is.
    menuOrder = 11,
    -- On an item, acts only while that item is still in its slot.
    AddMenuEntries = function(rootDescription, itemLocation, guid, itemID)
        itemID = itemID or C_Item.GetItemID(itemLocation)
        rootDescription:CreateCheckbox(L["inventory.slots.reserve"], function()
            return GetReservedItem(itemLocation) == itemID
        end, function()
            if ns.Containers:GetItemGUID(itemLocation) == guid then
                Slots:ToggleReservation(itemLocation, itemID)
            end
        end)
    end,
})
