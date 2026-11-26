-- Alt Click on Blizzard's map pin (WaypointLocationPinTemplate) shares it
-- (sharing.lua). Blizzard's own click on it would track it, Alt or not, and
-- its canvas runs the map's handlers from the pin: nothing of ours goes into
-- the map (TAINT in map.seamless). So while Alt is held over the pin and it can
-- be shared, a frame of ours lies over it and stands in for it: it takes the
-- click, and the mouse with it (measured: with its motion off, it still took the
-- mouse from the pin, which then lost its tooltip, and the frame, shown only
-- while the pin had the mouse, went on and off every frame). It shows the pin's
-- highlight and tooltip, and stays while it has the mouse and Alt is held.
-- Without Alt, Blizzard's pin keeps the mouse: a post-hook on its OnEnter adds
-- the hint to its tooltip.

local _, ns = ...

local Pin = ns:GetFeature("map", "pin")

local MapButton = {}
Pin.MapButton = MapButton

local TEMPLATE = "WaypointLocationPinTemplate"

-- Blizzard's pins whose OnEnter we post-hooked (hooks can't be removed).
local hooked = setmetatable({}, { __mode = "k" })
-- The frame standing in for the pin, the one watching for it while the map
-- shows, and the pin it was last put over.
local button, watcher, anchoredTo
local active = false

local function OnPinEnter(pin)
    if active and GameTooltip:IsOwned(pin) and Pin:CanShare() then
        Pin:AddShareHint(GameTooltip)
        GameTooltip:Show()
    end
end

-- The map pin shown on Blizzard's map, or nil.
local function FindPin()
    for pin in WorldMapFrame:EnumeratePinsByTemplate(TEMPLATE) do
        if pin:IsShown() then
            return pin
        end
    end
    return nil
end

local function OnUpdate()
    local pin = FindPin()
    if pin and not hooked[pin] then
        hooked[pin] = true
        pin:HookScript("OnEnter", OnPinEnter)
    end
    local hovered = pin and (button:IsShown() and button:IsMouseMotionFocus() or pin:IsMouseMotionFocus())
    local wanted = hovered and IsAltKeyDown() and Pin:CanShare() or false
    if wanted and anchoredTo ~= pin then
        anchoredTo = pin
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", pin)
        button:SetPoint("BOTTOMRIGHT", pin)
    end
    if wanted and not button:IsShown() then
        button:SetFrameStrata(pin:GetFrameStrata())
        button:SetFrameLevel(pin:GetFrameLevel() + 1)
    end
    button:SetShown(wanted)
end

-- Blizzard's tooltip for the pin (WaypointLocationPinMixin:OnMouseEnter), with the hint.
local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -16, -4)
    GameTooltip_SetTitle(GameTooltip, MAP_PIN_SHARING)
    GameTooltip_AddNormalLine(GameTooltip, MAP_PIN_SHARING_TOOLTIP)
    GameTooltip_AddColoredLine(GameTooltip, MAP_PIN_REMOVE, GREEN_FONT_COLOR)
    Pin:AddShareHint(GameTooltip)
    GameTooltip:Show()
end

local function OnLeave(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function OnMouseUp(_, mouseButton, upInside)
    if mouseButton == "LeftButton" and upInside then
        Pin:Share()
    end
end

local function Install()
    button = CreateFrame("Frame", nil, WorldMapFrame)
    button:EnableMouse(true)
    button:SetPassThroughButtons("RightButton", "MiddleButton", "Button4", "Button5")
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", OnLeave)
    button:SetScript("OnMouseUp", OnMouseUp)
    button:Hide()
    -- (the pin's own highlight, hidden under the frame)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("Waypoint-MapPin-Highlight")
    highlight:SetBlendMode("ADD")
    highlight:SetPoint("TOPLEFT")
    highlight:SetPoint("BOTTOMRIGHT")
    watcher = CreateFrame("Frame", nil, WorldMapFrame)
    watcher:SetScript("OnUpdate", OnUpdate)
end

function MapButton:Enable()
    if not button then
        Install()
    end
    active = true
    watcher:Show()
end

function MapButton:Disable()
    active = false
    anchoredTo = nil
    if button then
        watcher:Hide()
        button:Hide()
    end
end
