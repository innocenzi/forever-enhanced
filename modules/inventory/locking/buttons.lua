-- Item buttons: finds them, keeps their lock indicator up to date (see
-- indicators.lua), and lays a click shield over them when needed.
--
-- The shield is a transparent button laid over an item button. It takes the
-- mouse only when we must intercept a click, so Blizzard's own click handling
-- (and item use) is never wrapped or called from addon code, which would taint it:
--   * while Alt is held, over every item: Alt+Left-click toggles the lock;
--   * over locked items, while the cursor holds an item: no swapping it out;
--   * over locked items, while a merchant, mail, trade or auction window is
--     open: no right-click selling, attaching or posting.
-- The shield shows the item tooltip itself, so the sell cursor never appears.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local Buttons = {}
Locking.Buttons = Buttons

local SHIELD_LEVEL_OFFSET = 10

-- Windows where right-clicking a bag item would hand it over.
local SINK_FRAMES = { "MerchantFrame", "MailFrame", "TradeFrame", "AuctionHouseFrame" }

-- Item grids we decorate. Supporting another grid is one more entry.
local sources = {
    {
        name = "bags",
        GetFrames = function()
            local frames = { ContainerFrameCombinedBags }
            for _, frame in ipairs(ContainerFrameContainer.ContainerFrames) do
                table.insert(frames, frame)
            end
            return frames
        end,
        refreshMethods = { "UpdateItems" },
        ForEachButton = function(frame, func, ...)
            for _, button in frame:EnumerateValidItems() do
                if button then -- slots can be counted before their button exists
                    func(button, ...)
                end
            end
        end,
        GetItemLocation = function(button)
            return ItemLocation:CreateFromBagAndSlot(button:GetBagID(), button:GetID())
        end,
    },
    {
        name = "bank",
        GetFrames = function()
            return { BankPanel }
        end,
        refreshMethods = { "GenerateItemSlotsForSelectedTab", "RefreshAllItemsForSelectedTab" },
        ForEachButton = function(frame, func, ...)
            for button in frame:EnumerateValidItems() do
                func(button, ...)
            end
        end,
        GetItemLocation = function(button)
            return button:GetItemLocation()
        end,
    },
}

-- Our state per Blizzard item button: { source, shield }.
-- Weak keys: we never stamp fields onto Blizzard frames.
local decorations = setmetatable({}, { __mode = "k" })

local hooksInstalled = false
local lastContext

local function IsSinkOpen()
    for _, frameName in ipairs(SINK_FRAMES) do
        local frame = _G[frameName] -- AuctionHouseFrame is load-on-demand
        if frame and frame:IsShown() then
            return true
        end
    end
    return false
end

local function GetContext()
    return {
        alt = IsAltKeyDown(),
        protectLocked = CursorHasItem() or IsSinkOpen(),
    }
end

local function IsStale(context)
    return not lastContext or lastContext.alt ~= context.alt or lastContext.protectLocked ~= context.protectLocked
end

local function GetItemLocation(button)
    return decorations[button].source.GetItemLocation(button)
end

local ShieldMixin = {}

function ShieldMixin:OnClick(mouseButton)
    local itemLocation = GetItemLocation(self.itemButton)

    if mouseButton == "LeftButton" and IsAltKeyDown() then
        Locking:ToggleLock(itemLocation)
        if GameTooltip:IsOwned(self) then
            self:OnEnter()
        end
    elseif Locking:IsLocked(itemLocation) then
        local isSelling = mouseButton == "RightButton" and MerchantFrame:IsShown()
        ns:Error(isSelling and L["inventory.locking.cannotSell"] or L["inventory.locking.isLocked"])
    end
end

function ShieldMixin:OnReceiveDrag()
    if Locking:IsLocked(GetItemLocation(self.itemButton)) then
        ns:Error(L["inventory.locking.isLocked"])
    end
end

ShieldMixin.OnDragStart = ShieldMixin.OnReceiveDrag

function ShieldMixin:OnEnter()
    -- A modifier released while the game was unfocused leaves shields up; drop them.
    if IsStale(GetContext()) then
        Buttons:Refresh()
        if not self:IsShown() then
            return
        end
    end

    local bagID, slot = GetItemLocation(self.itemButton):GetBagAndSlot()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(bagID, slot)
    GameTooltip:Show()
end

function ShieldMixin:OnLeave()
    GameTooltip_Hide()
end

local SHIELD_SCRIPTS = { "OnClick", "OnReceiveDrag", "OnDragStart", "OnEnter", "OnLeave" }

local function CreateShield(button)
    local shield = Mixin(CreateFrame("Button", nil, button), ShieldMixin)
    shield.itemButton = button
    shield:SetAllPoints()
    shield:SetFrameLevel(button:GetFrameLevel() + SHIELD_LEVEL_OFFSET)
    shield:RegisterForClicks("AnyUp")
    shield:RegisterForDrag("LeftButton")
    shield:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    for _, script in ipairs(SHIELD_SCRIPTS) do
        shield:SetScript(script, shield[script])
    end
    return shield
end

local function UpdateButton(button, source, context)
    local decoration = decorations[button]
    if not decoration then
        decoration = {}
        decorations[button] = decoration
    end
    decoration.source = source

    local guid = Locking.GetItemGUID(source.GetItemLocation(button))
    local locked = Locking:IsGUIDLocked(guid)

    Locking.Indicators:Update(button, locked and Locking:GetSetting("indicator") or "none")

    local showShield = guid ~= nil and (context.alt or (locked and context.protectLocked))
    if showShield and not decoration.shield then
        decoration.shield = CreateShield(button)
    end
    if decoration.shield then
        decoration.shield:SetShown(showShield)
    end
end

local function RefreshFrame(frame, source, context)
    if frame:IsShown() then
        source.ForEachButton(frame, UpdateButton, source, context)
    end
end

function Buttons:Refresh()
    if not Locking:IsActive() then
        return
    end

    local context = GetContext()
    lastContext = context
    for _, source in ipairs(sources) do
        for _, frame in ipairs(source.frames) do
            RefreshFrame(frame, source, context)
        end
    end
end

local function OnFrameRefreshed(frame, source)
    if Locking:IsActive() then
        RefreshFrame(frame, source, GetContext())
    end
end

-- hooksecurefunc hooks can't be removed: install once, and every hook checks IsActive().
local function InstallHooks()
    if hooksInstalled then
        return
    end
    hooksInstalled = true

    for _, source in ipairs(sources) do
        source.frames = source.GetFrames()
        for _, frame in ipairs(source.frames) do
            for _, method in ipairs(source.refreshMethods) do
                hooksecurefunc(frame, method, function(self)
                    OnFrameRefreshed(self, source)
                end)
            end
        end
    end
end

local function Refresh()
    Buttons:Refresh()
end

local listener = ns.CreateEventListener({
    MODIFIER_STATE_CHANGED = function(_, key)
        if key == "LALT" or key == "RALT" then
            Buttons:Refresh()
        end
    end,
    CURSOR_CHANGED = Refresh,
    BAG_UPDATE_DELAYED = Refresh,
    MERCHANT_SHOW = Refresh,
    MERCHANT_CLOSED = Refresh,
    MAIL_SHOW = Refresh,
    MAIL_CLOSED = Refresh,
    TRADE_SHOW = Refresh,
    TRADE_CLOSED = Refresh,
    AUCTION_HOUSE_SHOW = Refresh,
    AUCTION_HOUSE_CLOSED = Refresh,
})

function Buttons:Enable()
    InstallHooks()
    listener:Start()
    self:Refresh()
end

function Buttons:Disable()
    listener:Stop()
    lastContext = nil
    Locking.Indicators:HideAll()
    for _, decoration in pairs(decorations) do
        if decoration.shield then
            decoration.shield:Hide()
        end
    end
end
