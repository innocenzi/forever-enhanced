-- Item buttons (core/itembuttons.lua): the dimming of the slots not holding the
-- item the tooltip shows, while Shift is held. It is our own frame laid over
-- each button, drawn like Blizzard's search overlay (searchOverlay,
-- ItemButtonTemplate: black at 80%), above other features' marks and under
-- core's click shields.
--
-- The shown item is read every frame while Shift is held only: moving to
-- another item, or the tooltip leaving items, then needs no hook on the tooltip.

local _, ns = ...

local Stacks = ns:GetFeature("inventory", "stacks")

local Buttons = {}
Stacks.Buttons = Buttons

local DIM_ALPHA = 0.8
-- Above other features' marks (+1), under core's click shields (+10).
local DIM_LEVEL_OFFSET = 3

-- Per Blizzard item button: the item ID it holds, false when empty. Weak keys.
local items = setmetatable({}, { __mode = "k" })
-- Per Blizzard item button: our dimming frame. Weak keys.
local overlays = setmetatable({}, { __mode = "k" })

-- The item ID the tooltip shows while Shift is held, nil otherwise.
local shownItem

local function CreateOverlay(button)
    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button:GetFrameLevel() + DIM_LEVEL_OFFSET)
    local texture = overlay:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetColorTexture(0, 0, 0, DIM_ALPHA)
    return overlay
end

local function Apply(button)
    local dim = shownItem ~= nil and items[button] ~= shownItem
    local overlay = overlays[button]
    if dim and not overlay then
        overlay = CreateOverlay(button)
        overlays[button] = overlay
    end
    if overlay then
        overlay:SetShown(dim)
    end
end

local function SetShownItem(itemID)
    if itemID == shownItem then
        return
    end
    shownItem = itemID
    for button in pairs(items) do
        Apply(button)
    end
end

-- The item ID the tooltip shows, or nil.
local function ReadTooltipItem()
    if not GameTooltip:IsShown() or not GameTooltip:IsTooltipType(Enum.TooltipDataType.Item) then
        return nil
    end
    local data = GameTooltip:GetPrimaryTooltipData()
    local itemID = data and data.id
    if itemID == nil or issecretvalue(itemID) then
        return nil
    end
    return itemID
end

-- Shown only while Shift is held: follows the tooltip every frame.
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function()
    SetShownItem(ReadTooltipItem())
end)

local function SyncShift()
    if IsShiftKeyDown() then
        driver:Show()
        SetShownItem(ReadTooltipItem())
    else
        driver:Hide()
        SetShownItem(nil)
    end
end

local listener = ns:CreateEventListener({
    MODIFIER_STATE_CHANGED = function(_, key)
        if key == "LSHIFT" or key == "RSHIFT" then
            SyncShift()
        end
    end,
})

function Buttons:Enable()
    listener:Start()
    SyncShift()
end

function Buttons:Disable()
    listener:Stop()
    driver:Hide()
    SetShownItem(nil)
end

ns:AddItemButtonHandler(Stacks, {
    Update = function(button, itemLocation, guid)
        items[button] = guid ~= nil and C_Item.GetItemID(itemLocation) or false
        Apply(button)
    end,
})
