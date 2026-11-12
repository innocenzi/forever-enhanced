-- Bag and bank item buttons: features draw their marks on them and take Alt
-- clicks through handlers registered here, like item tooltips (tooltips.lua).
--
-- A click shield is a transparent button laid over an item button. It takes
-- the mouse only when a click must be intercepted, so Blizzard's own click
-- handling (and item use) is never wrapped or called from addon code, which
-- would taint it:
--   * while Alt is held, over every item, when an active feature takes Alt
--     clicks: Alt Left Click goes to OnAltClick, Alt Right Click opens the
--     item menu (each active feature's AddMenuEntries);
--   * over items an active feature guards (IsGuarded), e.g. locked items while
--     the cursor holds an item or a merchant, mail, trade or auction window is
--     open: no swapping them out, no right-click selling, attaching or posting.
-- The shield shows the item tooltip itself, so the sell cursor never appears.

local _, ns = ...

local SHIELD_LEVEL_OFFSET = 10

-- Windows where right-clicking a bag item would hand it over.
local SINK_FRAMES = { "MerchantFrame", "MailFrame", "TradeFrame", "AuctionHouseFrame" }

-- Item grids we decorate. Supporting another grid is one more entry.
local sources = {
    { -- bags: combined bags and individual bag frames
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
    { -- bank tabs
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

-- { feature, handler } in registration order. Handler fields, all optional:
--   Update(button, itemLocation, guid)  draws the feature's marks on the button
--                                       (guid is nil for an empty slot)
--   IsGuarded(guid, context)            shields the item without Alt; context.protect:
--                                       the cursor holds an item or a sink window is open
--   OnGuardedClick(itemLocation, mouseButton), OnGuardedDrag(itemLocation)
--                                       a click or drag on the shield that isn't an Alt action
--   OnAltClick(itemLocation)            Alt Left Click
--   AddMenuEntries(rootDescription, itemLocation, guid)
--                                       entries of the Alt Right Click item menu
local handlers = {}

-- Only handlers of active features are called. Call ns:RefreshItemButtons() whenever
-- what a handler draws or guards changes, and from the feature's OnEnable / OnDisable.
-- Marks left by a disabled feature are its own to hide: Update is no longer called.
function ns:AddItemButtonHandler(feature, handler)
    table.insert(handlers, { feature = feature, handler = handler })
end

-- The `field` functions of active features' handlers, in registration order.
local function GetActive(field)
    local methods = {}
    for _, entry in ipairs(handlers) do
        if entry.handler[field] and entry.feature:IsActive() then
            table.insert(methods, entry.handler[field])
        end
    end
    return methods
end

-- Our state per Blizzard item button: { source, shield }.
-- Weak keys: we never stamp fields onto Blizzard frames.
local decorations = setmetatable({}, { __mode = "k" })

local hooksInstalled = false
local listening = false
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

local function IsProtecting()
    return CursorHasItem() or IsSinkOpen()
end

-- What the shields depend on, gathered once per refresh.
local function GetContext()
    return {
        alt = IsAltKeyDown(),
        protect = IsProtecting(),
        updates = GetActive("Update"),
        guards = GetActive("IsGuarded"),
        takesAlt = #GetActive("OnAltClick") > 0 or #GetActive("AddMenuEntries") > 0,
    }
end

-- Whether Alt or the protection changed since the last refresh.
local function IsStale()
    return not lastContext or lastContext.alt ~= IsAltKeyDown() or lastContext.protect ~= IsProtecting()
end

local function GetItemLocation(button)
    return decorations[button].source.GetItemLocation(button)
end

local function GetItemGUID(itemLocation)
    if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
        return C_Item.GetItemGUID(itemLocation)
    end
end

-- The item menu: the item's name as a title, in Blizzard's gold title color to
-- stand apart from the entries, then each active feature's entries.
-- Returns false when no active feature adds entries.
local function OpenMenu(shield, itemLocation)
    local addEntries = GetActive("AddMenuEntries")
    local guid = GetItemGUID(itemLocation)
    if #addEntries == 0 or not guid then
        return false
    end

    MenuUtil.CreateContextMenu(shield, function(_, rootDescription)
        rootDescription:CreateTitle(C_Item.GetItemName(itemLocation))
        for _, AddMenuEntries in ipairs(addEntries) do
            AddMenuEntries(rootDescription, itemLocation, guid)
        end
    end)
    return true
end

local ShieldMixin = {}

function ShieldMixin:OnClick(mouseButton)
    local itemLocation = GetItemLocation(self.itemButton)

    if IsAltKeyDown() and mouseButton == "LeftButton" then
        local altClicks = GetActive("OnAltClick")
        if #altClicks > 0 then
            for _, OnAltClick in ipairs(altClicks) do
                OnAltClick(itemLocation)
            end
            if GameTooltip:IsOwned(self) then
                self:OnEnter()
            end
            return
        end
    elseif IsAltKeyDown() and mouseButton == "RightButton" then
        if OpenMenu(self, itemLocation) then
            return
        end
    end

    for _, OnGuardedClick in ipairs(GetActive("OnGuardedClick")) do
        OnGuardedClick(itemLocation, mouseButton)
    end
end

function ShieldMixin:OnReceiveDrag()
    local itemLocation = GetItemLocation(self.itemButton)
    for _, OnGuardedDrag in ipairs(GetActive("OnGuardedDrag")) do
        OnGuardedDrag(itemLocation)
    end
end

ShieldMixin.OnDragStart = ShieldMixin.OnReceiveDrag

function ShieldMixin:OnEnter()
    -- A modifier released while the game was unfocused leaves shields up; drop them.
    if IsStale() then
        ns:RefreshItemButtons()
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

local function IsGuarded(guid, context)
    for _, Guards in ipairs(context.guards) do
        if Guards(guid, context) then
            return true
        end
    end
    return false
end

local function UpdateButton(button, source, context)
    local decoration = decorations[button]
    if not decoration then
        decoration = {}
        decorations[button] = decoration
    end
    decoration.source = source

    local itemLocation = source.GetItemLocation(button)
    local guid = GetItemGUID(itemLocation)
    for _, Update in ipairs(context.updates) do
        Update(button, itemLocation, guid)
    end

    local showShield = guid ~= nil and ((context.alt and context.takesAlt) or IsGuarded(guid, context))
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

local function HasActiveHandler()
    for _, entry in ipairs(handlers) do
        if entry.feature:IsActive() then
            return true
        end
    end
    return false
end

local function OnFrameRefreshed(frame, source)
    if HasActiveHandler() then
        RefreshFrame(frame, source, GetContext())
    end
end

-- hooksecurefunc hooks can't be removed: installed once, on the first refresh
-- with an active handler; every hook checks for one.
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
    ns:RefreshItemButtons()
end

local listener = ns:CreateEventListener({
    MODIFIER_STATE_CHANGED = function(_, key)
        if key == "LALT" or key == "RALT" then
            ns:RefreshItemButtons()
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

local function HideShields()
    for _, decoration in pairs(decorations) do
        if decoration.shield then
            decoration.shield:Hide()
        end
    end
end

-- Redraws every visible item button. Without an active handler, drops every
-- shield and stops listening.
function ns:RefreshItemButtons()
    if not HasActiveHandler() then
        if listening then
            listening = false
            listener:Stop()
            lastContext = nil
            HideShields()
        end
        return
    end

    InstallHooks()
    if not listening then
        listening = true
        listener:Start()
    end
    local context = GetContext()
    lastContext = context
    for _, source in ipairs(sources) do
        for _, frame in ipairs(source.frames) do
            RefreshFrame(frame, source, context)
        end
    end
end
