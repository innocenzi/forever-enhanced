-- Drag handles: our own button laid over each window's title bar (its
-- TitleContainer, or a strip along the top that leaves the close button free).
-- Dragging it (with the "modifier" setting's key held) moves the window;
-- Shift Right Click puts the window back where Blizzard places it.
-- Handles are hidden while the feature is inactive.

local _, ns = ...

local Windows = ns:GetFeature("interface", "windows")

local Handles = {}
Windows.Handles = Handles

local STRIP_HEIGHT = 24
local CLOSE_BUTTON_WIDTH = 28

-- Per Blizzard frame: its handle.
local handles = setmetatable({}, { __mode = "k" })
-- Per handle: the frame it moves.
local targets = setmetatable({}, { __mode = "k" })

local MODIFIERS = {
    none = function()
        return true
    end,
    shift = function()
        return IsShiftKeyDown()
    end,
    ctrl = function()
        return IsControlKeyDown()
    end,
    alt = function()
        return IsAltKeyDown()
    end,
}

local function OnDragStart(handle)
    local frame = targets[handle]
    if not MODIFIERS[Windows:GetSetting("modifier")]() then
        return
    end
    if not Windows.Placement:CanMove(frame) then
        UIErrorsFrame:AddExternalErrorMessage(ERR_NOT_IN_COMBAT)
        return
    end
    Windows.Placement:StartMoving(frame)
end

-- Also on hide: a window closed mid-drag is dropped where it is.
local function OnDragStop(handle)
    Windows.Placement:StopMoving(targets[handle])
end

local function OnClick(handle, mouseButton)
    if mouseButton == "RightButton" and IsShiftKeyDown() then
        Windows.Placement:Reset(targets[handle])
    end
end

local function CreateHandle(frame)
    local handle = CreateFrame("Button", nil, frame)
    local title = frame.TitleContainer
    if title then
        handle:SetAllPoints(title)
        handle:SetFrameLevel(title:GetFrameLevel() + 1)
    else
        handle:SetPoint("TOPLEFT")
        handle:SetPoint("TOPRIGHT", -CLOSE_BUTTON_WIDTH, 0)
        handle:SetHeight(STRIP_HEIGHT)
        handle:SetFrameLevel(frame:GetFrameLevel() + 1)
    end
    handle:RegisterForDrag("LeftButton")
    handle:RegisterForClicks("RightButtonUp")
    handle:SetScript("OnDragStart", OnDragStart)
    handle:SetScript("OnDragStop", OnDragStop)
    handle:SetScript("OnHide", OnDragStop)
    handle:SetScript("OnClick", OnClick)
    targets[handle] = frame
    return handle
end

-- Gives the frame a handle, once (only while the feature is active).
function Handles:Attach(frame)
    if not handles[frame] then
        handles[frame] = CreateHandle(frame)
    end
end

function Handles:ShowAll()
    for _, handle in pairs(handles) do
        handle:Show()
    end
end

function Handles:HideAll()
    for _, handle in pairs(handles) do
        handle:Hide()
    end
end
