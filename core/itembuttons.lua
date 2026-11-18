-- Bag and bank item buttons: features draw their marks on them and take Alt
-- clicks through handlers registered here, like item tooltips (tooltips.lua).
--
-- A click shield is a transparent button laid over an item button. It takes
-- the mouse only when a click must be intercepted, so Blizzard's own click
-- handling (and item use) is never wrapped or called from addon code, which
-- would taint it:
--   * while Alt is held, over every item, when an active feature takes Alt
--     clicks: Alt Left Click goes to OnAltClick, Alt Right Click opens the
--     item menu (each active feature's AddMenuEntries), whose shield stays up
--     until it closes; also over empty slots standing for an item
--     (EmptySlotItem), with that item's tooltip and a menu of the entries
--     meant for them;
--   * over items an active feature guards (IsGuarded), e.g. locked items while
--     the cursor holds an item or a merchant, mail, trade or auction window is
--     open: no swapping them out, no right-click selling, attaching or posting.
-- The shield shows the item tooltip itself, so the sell cursor never appears.
--
-- Redraws are frequent (Blizzard redraws a bag on every bag change and quest
-- log change, the cursor changes shape over units), so the work is kept to what
-- can have changed:
--   * Alt and the protection only change shields: their own pass, no marks;
--   * Prepare runs once per change of what handlers draw (ns:RefreshItemButtons()
--     or a bag change), not once per redraw;
--   * a button's Update calls run again only when that change happened or the
--     button holds another item. Blizzard's redraws never touch our frames, so
--     marks left as they are stay right.

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
--   part                                the feature's part (toggle key) the handler
--                                       belongs to: it runs only while that part does
--   Prepare()                           gathers what Update calls share (e.g. a bag
--                                       scan): called before them after
--                                       ns:RefreshItemButtons() or a bag change only
--   Update(button, itemLocation, guid)  draws the feature's marks on the button
--                                       (guid is nil for an empty slot): called after
--                                       Prepare, or when the button holds another item
--   IsGuarded(guid, state)              shields the item without Alt; state.protect:
--                                       the cursor holds an item or a sink window is open
--   OnGuardedClick(itemLocation, mouseButton), OnGuardedDrag(itemLocation)
--                                       a click or drag on the shield that isn't an Alt action
--   OnAltClick(itemLocation)            Alt Left Click
--   AddMenuEntries(rootDescription, itemLocation, guid, itemID), menuOrder
--                                       entries of the Alt Right Click item menu, and
--                                       where they go in it (required with them): lower
--                                       first. Spaced by tens, entries that go together
--                                       under one ten: 10 lock, 11 reserved slot, 21-24
--                                       marks (junk, auction house, bank, mail), 30
--                                       Wowhead link, 40 note. itemID: only on an empty slot
--   EmptySlotItem(itemLocation)         the item ID an empty slot stands for, or nil:
--                                       under Alt it gets a shield showing that item's
--                                       tooltip, and Alt Right Click opens a menu of the
--                                       entries of handlers flagged emptySlotEntries
--                                       (called with a nil guid and that itemID)
local handlers = {}
-- The entries of handlers adding menu entries, by menuOrder.
local menuHandlers = {}

-- Only handlers of active features are called. Call ns:RefreshItemButtons() whenever
-- what a handler draws or guards changes (anything but the bags' contents, Alt and
-- the protection), and from the feature's OnEnable / OnDisable: nothing else
-- redraws marks of unchanged items.
-- Marks left by a disabled feature are its own to hide: Update is no longer called.
function ns:AddItemButtonHandler(feature, handler)
    local entry = { feature = feature, handler = handler }
    table.insert(handlers, entry)
    if handler.AddMenuEntries then
        assert(type(handler.menuOrder) == "number", "AddMenuEntries needs a menuOrder")
        for _, other in ipairs(menuHandlers) do
            assert(other.handler.menuOrder ~= handler.menuOrder, "menuOrder taken: " .. handler.menuOrder)
        end
        table.insert(menuHandlers, entry)
        table.sort(menuHandlers, function(a, b)
            return a.handler.menuOrder < b.handler.menuOrder
        end)
    end
end

-- The `field` functions of active features' handlers, in registration order.
local function GetActive(field)
    local methods = {}
    for _, entry in ipairs(handlers) do
        if entry.handler[field] and entry.feature:IsHandlerActive(entry.handler.part) then
            table.insert(methods, entry.handler[field])
        end
    end
    return methods
end

-- The AddMenuEntries functions of active features' handlers, by menuOrder;
-- for an empty slot, only those flagged emptySlotEntries.
local function GetMenuEntries(emptySlot)
    local methods = {}
    for _, entry in ipairs(menuHandlers) do
        if entry.feature:IsHandlerActive(entry.handler.part) and (not emptySlot or entry.handler.emptySlotEntries) then
            table.insert(methods, entry.handler.AddMenuEntries)
        end
    end
    return methods
end

-- Our state per Blizzard item button: { source, shield, guarded } and what its
-- marks were last drawn for: { context, bagID, slot, guid, emptySlotItem }.
-- Weak keys: we never stamp fields onto Blizzard frames.
local decorations = setmetatable({}, { __mode = "k" })

local hooksInstalled = false
local listening = false
-- The active handlers' functions: { updates, guards, emptySlotItems, takesAlt }, gathered on
-- first use after each ns:RefreshItemButtons().
local active
-- What marks are drawn with, made when Prepare runs: { afterBagChange }, kept
-- until ns:RefreshItemButtons() or a bag change. afterBagChange: made after the
-- bag changes BAG_UPDATE_DELAYED will report.
local context
-- A bag changed (BAG_UPDATE) since the last BAG_UPDATE_DELAYED.
local bagChangePending = false
-- What shields depend on: { alt, protect }, as last read.
local state = {}
-- The shield the item menu is open on: kept up until the menu closes, since
-- Blizzard closes a menu whose owner hides (releasing Alt would).
local menuShield

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

local function GetActiveHandlers()
    if not active then
        active = {
            updates = GetActive("Update"),
            guards = GetActive("IsGuarded"),
            emptySlotItems = GetActive("EmptySlotItem"),
            takesAlt = #GetActive("OnAltClick") > 0 or #GetActive("AddMenuEntries") > 0,
        }
    end
    return active
end

-- The current context, after the active handlers' Prepare when there is none.
local function GetContext()
    if not context then
        for _, Prepare in ipairs(GetActive("Prepare")) do
            securecallfunction(Prepare)
        end
        context = { afterBagChange = bagChangePending }
    end
    return context
end

-- Reads Alt and the protection; returns whether either changed.
local function ReadState()
    local alt, protect = IsAltKeyDown(), IsProtecting()
    local changed = alt ~= state.alt or protect ~= state.protect
    state.alt, state.protect = alt, protect
    return changed
end

local function GetItemLocation(button)
    return decorations[button].source.GetItemLocation(button)
end

-- Redraws the shields of the visible buttons when Alt or the protection
-- changed, or when `force`d. Defined with the shields below.
local SyncShields

-- The item menu: the item's name as a title, in Blizzard's gold title color to
-- stand apart from the entries, then each active feature's entries. Its shield
-- stays up while it's open. Returns false when no active feature adds entries.
-- An empty slot standing for an item gets that item's name and the entries
-- meant for empty slots.
local function OpenMenu(shield, itemLocation)
    local guid = ns.Containers:GetItemGUID(itemLocation)
    local itemID, title
    if guid then
        title = C_Item.GetItemName(itemLocation)
    else
        itemID = decorations[shield.itemButton].emptySlotItem
        if not itemID then
            return false
        end
        title = C_Item.GetItemNameByID(itemID)
    end
    local addEntries = GetMenuEntries(guid == nil)
    if #addEntries == 0 then
        return false
    end

    MenuUtil.CreateContextMenu(shield, function(_, rootDescription)
        -- Only the latest menu's release drops its shield.
        rootDescription:AddMenuReleasedCallback(function()
            if menuShield == shield then
                menuShield = nil
                SyncShields(true)
            end
        end)
        if title then -- an item's name is missing until its data loads
            rootDescription:CreateTitle(title)
        end
        for _, AddMenuEntries in ipairs(addEntries) do
            AddMenuEntries(rootDescription, itemLocation, guid, itemID)
        end
    end)
    menuShield = shield
    return true
end

local ShieldMixin = {}

function ShieldMixin:OnClick(mouseButton)
    local itemLocation = GetItemLocation(self.itemButton)

    if IsAltKeyDown() and mouseButton == "LeftButton" then
        if not decorations[self.itemButton].guid then
            return -- an empty slot standing for an item: nothing to click
        end
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

    if not decorations[self.itemButton].guarded then
        return -- kept up only for Alt or its menu
    end
    for _, OnGuardedClick in ipairs(GetActive("OnGuardedClick")) do
        OnGuardedClick(itemLocation, mouseButton)
    end
end

function ShieldMixin:OnReceiveDrag()
    if not decorations[self.itemButton].guarded then
        return
    end
    local itemLocation = GetItemLocation(self.itemButton)
    for _, OnGuardedDrag in ipairs(GetActive("OnGuardedDrag")) do
        OnGuardedDrag(itemLocation)
    end
end

ShieldMixin.OnDragStart = ShieldMixin.OnReceiveDrag

function ShieldMixin:OnEnter()
    -- A modifier released while the game was unfocused leaves shields up; drop them.
    SyncShields()
    if not self:IsShown() then
        return
    end

    local decoration = decorations[self.itemButton]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if decoration.guid then
        local bagID, slot = GetItemLocation(self.itemButton):GetBagAndSlot()
        GameTooltip:SetBagItem(bagID, slot)
    else
        GameTooltip:SetItemByID(decoration.emptySlotItem)
    end
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

local function IsGuarded(guid, guards)
    for _, Guards in ipairs(guards) do
        if securecallfunction(Guards, guid, state) then
            return true
        end
    end
    return false
end

-- The item an empty slot stands for, from the first active handler naming one.
local function GetEmptySlotItem(itemLocation)
    for _, EmptySlotItem in ipairs(GetActiveHandlers().emptySlotItems) do
        local itemID = securecallfunction(EmptySlotItem, itemLocation)
        if itemID then
            return itemID
        end
    end
end

-- Shows the button's shield as Alt, the protection and its item (as last drawn) need.
local function UpdateShield(button, decoration)
    local handlers = GetActiveHandlers()
    local guid = decoration.guid
    decoration.guarded = guid ~= nil and IsGuarded(guid, handlers.guards)
    local hasMenu = decoration.shield ~= nil and decoration.shield == menuShield
    local showShield
    if guid ~= nil then
        showShield = (state.alt and handlers.takesAlt) or decoration.guarded or hasMenu
    else
        showShield = decoration.emptySlotItem ~= nil and (state.alt or hasMenu)
    end
    if showShield and not decoration.shield then
        decoration.shield = CreateShield(button)
    end
    if decoration.shield then
        decoration.shield:SetShown(showShield)
    end
end

function SyncShields(force)
    if not ReadState() and not force then
        return
    end
    for button, decoration in pairs(decorations) do
        if button:IsVisible() then
            UpdateShield(button, decoration)
        end
    end
end

local function UpdateButton(button, source, drawContext)
    local decoration = decorations[button]
    if not decoration then
        decoration = {}
        decorations[button] = decoration
    end
    decoration.source = source

    local itemLocation = source.GetItemLocation(button)
    local guid = ns.Containers:GetItemGUID(itemLocation)
    local bagID, slot = itemLocation:GetBagAndSlot()
    if
        decoration.context ~= drawContext
        or decoration.guid ~= guid
        or decoration.bagID ~= bagID
        or decoration.slot ~= slot
    then
        decoration.context, decoration.guid, decoration.bagID, decoration.slot = drawContext, guid, bagID, slot
        decoration.emptySlotItem = not guid and GetEmptySlotItem(itemLocation) or nil
        -- One feature's error is reported without leaving the others' marks and guards undrawn.
        for _, Update in ipairs(GetActiveHandlers().updates) do
            securecallfunction(Update, button, itemLocation, guid)
        end
    end
    UpdateShield(button, decoration)
end

local function RefreshFrame(frame, source, drawContext)
    if frame:IsShown() then
        source.ForEachButton(frame, UpdateButton, source, drawContext)
    end
end

local function HasActiveHandler()
    for _, entry in ipairs(handlers) do
        if entry.feature:IsHandlerActive(entry.handler.part) then
            return true
        end
    end
    return false
end

-- Blizzard redrew the frame's buttons: our marks follow at once for the
-- buttons whose item changed.
local function OnFrameRefreshed(frame, source)
    if listening and HasActiveHandler() then
        SyncShields()
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
                ns:HookSecureFunc(frame, method, function(self)
                    OnFrameRefreshed(self, source)
                end)
            end
        end
    end
end

-- Redraws every visible item button: the marks of those whose item changed
-- since the context was made, or all of them with a new context.
local function RedrawAll()
    ReadState()
    local drawContext = GetContext()
    for _, source in ipairs(sources) do
        for _, frame in ipairs(source.frames) do
            RefreshFrame(frame, source, drawContext)
        end
    end
end

local function Refresh()
    ns:RefreshItemButtons()
end

local redrawQueued = false

local function RedrawQueued()
    redrawQueued = false
    if listening then
        ns:RefreshItemButtons()
    end
end

-- A window opened or closed: what marks draw depends on whether it's shown.
-- Blizzard shows and hides windows from PLAYER_INTERACTION_MANAGER_FRAME_SHOW
-- and _HIDE, in no set order with the window's own event (MAIL_SHOW came first:
-- MailFrame still hidden), so marks are redrawn at once and again next frame.
local function OnWindowToggled()
    Refresh()
    if not redrawQueued then
        redrawQueued = true
        C_Timer.After(0, RedrawQueued)
    end
end

local function SyncShieldsOnly()
    SyncShields()
end

local listener = ns:CreateEventListener({
    MODIFIER_STATE_CHANGED = function(_, key)
        if key == "LALT" or key == "RALT" then
            SyncShields()
        end
    end,
    -- Fires whenever the cursor changes shape: only holding an item matters.
    CURSOR_CHANGED = SyncShieldsOnly,
    -- Only marks the context out of date: Blizzard's redraw or BAG_UPDATE_DELAYED
    -- makes a new one, once for all the bags that changed.
    BAG_UPDATE = function()
        context = nil
        bagChangePending = true
    end,
    -- Keeps a context Blizzard's redraws made since the bags changed.
    BAG_UPDATE_DELAYED = function()
        if context and not context.afterBagChange then
            context = nil
        end
        bagChangePending = false
        RedrawAll()
    end,
    -- The bag's "exclude from Sell All Junk" option: junk coins follow it.
    BAG_SLOT_FLAGS_UPDATED = Refresh,
    MERCHANT_SHOW = OnWindowToggled,
    MERCHANT_CLOSED = OnWindowToggled,
    MAIL_SHOW = OnWindowToggled,
    MAIL_CLOSED = OnWindowToggled,
    TRADE_SHOW = OnWindowToggled,
    TRADE_CLOSED = OnWindowToggled,
    AUCTION_HOUSE_SHOW = OnWindowToggled,
    AUCTION_HOUSE_CLOSED = OnWindowToggled,
    BANKFRAME_OPENED = OnWindowToggled,
    BANKFRAME_CLOSED = OnWindowToggled,
})

local function HideShields()
    for _, decoration in pairs(decorations) do
        if decoration.shield then
            decoration.shield:Hide()
        end
    end
end

-- Redraws every visible item button, Prepare first. Without an active handler,
-- drops every shield and stops listening.
function ns:RefreshItemButtons()
    active, context = nil, nil
    if not HasActiveHandler() then
        if listening then
            listening = false
            listener:Stop()
            state, bagChangePending = {}, false
            HideShields()
        end
        return
    end

    InstallHooks()
    if not listening then
        listening = true
        listener:Start()
    end
    RedrawAll()
end
