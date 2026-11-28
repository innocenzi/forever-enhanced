-- Side tab on the left edge of the bags (combined bags or the backpack), in the
-- style of the bank's page tabs, mirrored to face left. It toggles the saved
-- bank, and is hidden while Blizzard's bank is open.
--
-- With "openWithBags", the saved bank opens with the bags. Closing the bags
-- always closes it.

local _, ns = ...

local L = ns.L
local Bank = ns:GetFeature("inventory", "bank")

local Tab = {}
Bank.Tab = Tab

local TAB_ICON = "Interface/ICONS/INV_SideTab_Bank_c60"
local OPEN_BAG, CLOSE_BAG = "ContainerFrame.OpenBag", "ContainerFrame.CloseBag"

-- Bag frames the tab can hang on, by preference: the combined bags, else the backpack.
local HOST_FRAMES = { ContainerFrameCombinedBags, ContainerFrame1 }

local tab

local function GetHostFrame()
    for _, frame in ipairs(HOST_FRAMES) do
        if frame:IsShown() then
            return frame
        end
    end
end

-- The side tab art faces right: turn it around, icon offset included.
local function Mirror(sideTab)
    for _, region in ipairs({
        sideTab.Background,
        sideTab.Mask,
        sideTab.SelectedTexture,
        sideTab.TabGlow,
        sideTab.HighlightTexture,
    }) do
        region:SetRotation(math.pi)
    end
    local offsetX, offsetY = sideTab:GetIconAnchorOffsetsForTabArt()
    sideTab.GetFinalIconAnchorOffsets = function()
        return -offsetX, offsetY
    end
    sideTab:InitializeIconAnchoring()
end

local function CreateTab()
    tab = CreateFrame("Frame", nil, UIParent, "LargeSideTabButtonTemplate")
    tab:Hide()
    tab:SetFillToInterior(true)
    tab.Icon:SetTexture(TAB_ICON)
    tab.tooltipText = L["inventory.bank.tabTooltip"]
    Mirror(tab)
    tab:SetCustomOnMouseUpHandler(function(_, mouseButton, upInside)
        if mouseButton == "LeftButton" and upInside then
            Bank.View:Toggle()
        end
    end)
end

function Tab:Refresh()
    if not tab then
        return
    end
    local host = GetHostFrame()
    if not Bank:IsActive() or not host or Bank.Snapshot:IsBankOpen() then
        tab:Hide()
        return
    end
    tab:SetParent(host)
    tab:SetFrameLevel(host:GetFrameLevel() + 10)
    tab:ClearAllPoints()
    tab:SetPoint("TOPRIGHT", host, "TOPLEFT", 2, -60)
    tab:SetChecked(Bank.View:IsShown())
    tab:Show()
end

local function OnBagOpened(_, frame)
    if not tContains(HOST_FRAMES, frame) then
        return
    end
    Tab:Refresh()
    if Bank:GetSetting("openWithBags") then
        Bank.View:Open()
    end
end

local function OnBagClosed(_, frame)
    if not tContains(HOST_FRAMES, frame) then
        return
    end
    if not GetHostFrame() then
        Bank.View:Close()
    end
    Tab:Refresh()
end

function Tab:Enable()
    if not tab then
        CreateTab()
    end
    EventRegistry:RegisterCallback(OPEN_BAG, OnBagOpened, self)
    EventRegistry:RegisterCallback(CLOSE_BAG, OnBagClosed, self)
    self:Refresh()
end

function Tab:Disable()
    EventRegistry:UnregisterCallback(OPEN_BAG, self)
    EventRegistry:UnregisterCallback(CLOSE_BAG, self)
    self:Refresh()
end
