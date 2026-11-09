-- Fake Forever client: just enough of the WoW API for the addon to load and run
-- outside the game. Loaded fresh, in its own environment, for every test.
-- Returns `world`: the test's handle to drive and inspect the fake client.
--
-- The world has one bag (ID 0) of BAG_SIZE slots holding item GUID strings, a
-- cursor, a fake clock, and a server that applies sorts on demand and confirms
-- item swaps after SERVER_CONFIRM_SECONDS.

local BAG_SIZE = 4
local SERVER_CONFIRM_SECONDS = 0.05

local world = {
    now = 0,
    frames = {},
    textures = {},
    timers = {},
    nextFrameCallbacks = {},
    settings = {},
    categories = {},
    eventRegistry = {},
    errors = {},
    prints = {},
    hiddenPopups = {},
    popups = {},
    sold = {},
    excludedFromJunkSell = {},
    swapTimes = {},
    pickups = 0,
    alt = false,
    cursor = nil,
    bags = { [0] = { "G1", "G2", nil, "GJUNK" } },
    quality = { GJUNK = 0 },
    sortRequested = false,
    SERVER_CONFIRM_SECONDS = SERVER_CONFIRM_SECONDS,
}

-- Lua and core helpers -------------------------------------------------------

unpack = table.unpack or unpack

function Mixin(object, ...)
    for _, mixin in ipairs({ ... }) do
        for key, value in pairs(mixin) do
            object[key] = value
        end
    end
    return object
end

function tContains(tbl, value)
    for _, candidate in ipairs(tbl) do
        if candidate == value then
            return true
        end
    end
    return false
end

function hooksecurefunc(tbl, name, hook)
    local original = tbl[name]
    tbl[name] = function(...)
        local result = original(...)
        hook(...)
        return result
    end
end

function CreateColor(r, g, b, a)
    return {
        GetRGB = function()
            return r, g, b
        end,
        GetRGBA = function()
            return r, g, b, a or 1
        end,
    }
end

function CreateAtlasMarkup(atlas)
    return "|A:" .. atlas .. "|a"
end

function GetLocale()
    return TEST_LOCALE
end

C_AddOns = {
    GetAddOnMetadata = function(_, field)
        return field == "Title" and "Forever Enhanced" or nil
    end,
}

-- Frames and textures ----------------------------------------------------------

local Region = {}
Region.__index = Region

local function NoOp() end
for _, name in ipairs({
    "SetAllPoints",
    "RegisterForClicks",
    "RegisterForDrag",
    "SetHighlightTexture",
    "SetVertexColor",
    "SetFrameLevel",
}) do
    Region[name] = NoOp
end

function Region:RegisterEvent(event)
    self.events[event] = true
end

function Region:UnregisterEvent(event)
    self.events[event] = nil
end

function Region:UnregisterAllEvents()
    self.events = {}
end

function Region:SetScript(name, func)
    self.scripts[name] = func
end

function Region:Show()
    self.shown = true
end

function Region:Hide()
    self.shown = false
end

function Region:SetShown(shown)
    self.shown = not not shown
end

function Region:IsShown()
    return self.shown
end

function Region:GetFrameLevel()
    return 1
end

function Region:GetID()
    return self.id
end

function Region:ClearAllPoints()
    self.point = nil
end

function Region:SetPoint(point)
    self.point = self.point or point
end

function Region:SetSize(width, height)
    self.width, self.height = width, height
end

function Region:SetAtlas(atlas)
    self.atlas = atlas
end

function Region:SetDesaturated(desaturated)
    self.desaturated = desaturated
end

function Region:CreateTexture()
    local texture = setmetatable({ owner = self, shown = true, events = {}, scripts = {} }, Region)
    table.insert(world.textures, texture)
    return texture
end

function CreateFrame(_, _, parent)
    local frame = setmetatable({ parent = parent, shown = true, events = {}, scripts = {} }, Region)
    table.insert(world.frames, frame)
    return frame
end

-- Timers -----------------------------------------------------------------------

C_Timer = {
    After = function(_, callback)
        table.insert(world.nextFrameCallbacks, callback)
    end,
    NewTimer = function(seconds, callback)
        local timer = { at = world.now + seconds, callback = callback }
        function timer:Cancel()
            self.cancelled = true
        end
        table.insert(world.timers, timer)
        return timer
    end,
}

-- Settings panel -----------------------------------------------------------------

local Setting = {}
Setting.__index = Setting

function Setting:SetValueChangedCallback(callback)
    self.callback = callback
end

function Setting:SetValue(value)
    self.tbl[self.key] = value
    if self.callback then
        self.callback(self, value)
    end
end

local Initializer = {}
Initializer.__index = Initializer

function Initializer:SetParentInitializer(parent, predicate)
    self.parent = parent
    self.predicate = predicate
end

function Initializer:AddModifyPredicate(predicate)
    self.predicate = predicate
end

local function NewCategory(name)
    local category = {
        name = name,
        items = {},
        GetID = function()
            return name
        end,
    }
    table.insert(world.categories, category)
    local layout = {
        AddInitializer = function(_, initializer)
            table.insert(category.items, initializer)
        end,
    }
    return category, layout
end

local function AddInitializer(category, initializer)
    setmetatable(initializer, Initializer)
    table.insert(category.items, initializer)
    return initializer
end

Settings = {
    VarType = { Boolean = "boolean", String = "string" },
    RegisterVerticalLayoutCategory = NewCategory,
    RegisterVerticalLayoutSubcategory = function(_, name)
        return NewCategory(name)
    end,
    RegisterAddOnCategory = function(category)
        category.registered = true
    end,
    RegisterAddOnSetting = function(_, variable, key, tbl, varType, name, default)
        assert(not world.settings[variable], "duplicate setting variable " .. variable)
        assert(type(name) == "string" and type(default) == varType, "malformed setting " .. variable)
        if tbl[key] == nil then
            tbl[key] = default
        end
        local setting = setmetatable({ key = key, tbl = tbl, name = name }, Setting)
        world.settings[variable] = setting
        return setting
    end,
    CreateCheckbox = function(category, setting, tooltip)
        return AddInitializer(category, { setting = setting, tooltip = tooltip })
    end,
    CreateDropdown = function(category, setting, getOptions, tooltip)
        return AddInitializer(category, { setting = setting, tooltip = tooltip, options = getOptions() })
    end,
    CreateControlTextContainer = function()
        local data = {}
        return {
            Add = function(_, value, label)
                table.insert(data, { value = value, label = label })
            end,
            GetData = function()
                return data
            end,
        }
    end,
}

function CreateSettingsListSectionHeaderInitializer(name, tooltip)
    return { header = name, tooltip = tooltip }
end

-- Items, bags and cursor ------------------------------------------------------------

Enum = {
    BagIndex = { Backpack = 0 },
    BagSlotFlags = { ExcludeJunkSell = 64 },
    ItemQuality = { Poor = 0 },
    TooltipDataType = { Item = 0 },
}
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 0

local ItemLocationMixin = {}
ItemLocationMixin.__index = ItemLocationMixin

function ItemLocationMixin:IsValid()
    return self.bagID ~= nil
end

function ItemLocationMixin:GetBagAndSlot()
    return self.bagID, self.slot
end

ItemLocation = {}

function ItemLocation:CreateFromBagAndSlot(bagID, slot)
    return setmetatable({ bagID = bagID, slot = slot }, ItemLocationMixin)
end

local function ItemAt(location)
    local bag = world.bags[location.bagID]
    return bag and bag[location.slot]
end

C_Item = {
    DoesItemExist = function(location)
        return ItemAt(location) ~= nil
    end,
    GetItemGUID = ItemAt,
    GetItemLink = function(location)
        return "[" .. ItemAt(location) .. "]"
    end,
}

C_Texture = {
    GetAtlasInfo = function(atlas)
        local sizes = {
            ["QuestSharing-Padlock"] = { width = 24, height = 29 },
            ["bankslot-icon-lock"] = { width = 54, height = 54 },
        }
        return sizes[atlas]
    end,
}

C_Cursor = {
    GetCursorItem = function()
        return world.cursor
    end,
}

function CursorHasItem()
    return world.cursor ~= nil
end

function ClearCursor()
    world.cursor = nil
    world:Fire("CURSOR_CHANGED")
end

function IsAltKeyDown()
    return world.alt
end

C_Container = {
    GetContainerNumSlots = function(bagID)
        return world.bags[bagID] and BAG_SIZE or 0
    end,
    GetContainerItemInfo = function(bagID, slot)
        local guid = world.bags[bagID][slot]
        return guid and { quality = world.quality[guid] or 2, hasNoValue = false, isLocked = false }
    end,
    -- Empty cursor: pick up. Holding an item: swap it with the slot, confirmed by the server later.
    PickupContainerItem = function(bagID, slot)
        world.pickups = world.pickups + 1
        if not world.cursor then
            world.cursor = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        else
            local from = world.cursor
            local bags = world.bags
            bags[from.bagID][from.slot], bags[bagID][slot] = bags[bagID][slot], bags[from.bagID][from.slot]
            world.cursor = nil
            table.insert(world.swapTimes, world.now)
            C_Timer.NewTimer(SERVER_CONFIRM_SECONDS, function()
                world:Fire("BAG_UPDATE_DELAYED")
            end)
        end
        world:Fire("CURSOR_CHANGED")
    end,
    -- Only selling (merchant open) is modelled: the item leaves the bag.
    UseContainerItem = function(bagID, slot)
        assert(MerchantFrame.shown, "UseContainerItem outside a merchant")
        table.insert(world.sold, world.bags[bagID][slot])
        world.bags[bagID][slot] = nil
    end,
    -- The bag menu's "exclude from Sell All Junk" option.
    GetBackpackSellJunkDisabled = function()
        return world.excludedFromJunkSell[0] == true
    end,
    GetBagSlotFlag = function(bagID, flag)
        assert(flag == Enum.BagSlotFlags.ExcludeJunkSell, "unexpected bag flag")
        return world.excludedFromJunkSell[bagID] == true
    end,
    SortBags = function()
        world.sortRequested = true
    end,
    SortBank = NoOp,
    SortBankBags = NoOp,
    SortAccountBankBags = NoOp,
}

-- UI globals ---------------------------------------------------------------------------

GameTooltip = {
    SetOwner = NoOp,
    SetBagItem = NoOp,
    Show = NoOp,
    IsOwned = function()
        return false
    end,
}
GameTooltip_Hide = NoOp

UIErrorsFrame = {
    AddExternalErrorMessage = function(_, message)
        table.insert(world.errors, message)
    end,
}

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message)
        table.insert(world.prints, message)
    end,
}

EventRegistry = {
    RegisterCallback = function(_, event, callback)
        world.eventRegistry[event] = callback
    end,
    UnregisterCallback = function(_, event)
        world.eventRegistry[event] = nil
    end,
}

function StaticPopup_Hide(which)
    table.insert(world.hiddenPopups, which)
end

-- Records the popup data ({ text, text_arg1, text_arg2, callback }); tests accept it by calling callback.
function StaticPopup_ShowCustomGenericConfirmation(data)
    table.insert(world.popups, data)
end

TooltipDataProcessor = {
    AddTooltipPostCall = function(_, callback)
        world.tooltipPostCall = callback
    end,
}

-- Blizzard frames ------------------------------------------------------------------------

world.buttons = {}
for slot = 1, BAG_SIZE do
    local button = CreateFrame("Button")
    button.id = slot
    function button:GetBagID()
        return 0
    end
    world.buttons[slot] = button
end

ContainerFrameCombinedBags = CreateFrame("Frame")
function ContainerFrameCombinedBags:EnumerateValidItems()
    return ipairs(world.buttons)
end
ContainerFrameCombinedBags.UpdateItems = NoOp

ContainerFrameContainer = { ContainerFrames = {} }

BankPanel = CreateFrame("Frame")
BankPanel.shown = false
function BankPanel:EnumerateValidItems()
    return pairs({})
end
BankPanel.GenerateItemSlotsForSelectedTab = NoOp
BankPanel.RefreshAllItemsForSelectedTab = NoOp

for _, name in ipairs({ "MerchantFrame", "MailFrame", "TradeFrame" }) do
    _G[name] = CreateFrame("Frame")
    _G[name].shown = false
end

-- World API for tests ------------------------------------------------------------------------

function world:Fire(event, ...)
    for _, frame in ipairs(self.frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

function world:NextFrame()
    local callbacks = self.nextFrameCallbacks
    self.nextFrameCallbacks = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end
end

-- Advances the clock by `seconds`, running due timers in order (and a frame after each).
function world:Elapse(seconds)
    local target = self.now + seconds
    while true do
        local nextTimer
        for _, timer in ipairs(self.timers) do
            if not timer.cancelled and not timer.ran and timer.at <= target then
                if not nextTimer or timer.at < nextTimer.at then
                    nextTimer = timer
                end
            end
        end
        if not nextTimer then
            self.now = target
            return
        end
        self.now = nextTimer.at
        nextTimer.ran = true
        nextTimer.callback()
        self:NextFrame()
    end
end

function world:Setting(path)
    return assert(self.settings["ForeverEnhanced." .. path], "no setting " .. path)
end

function world:SetAlt(down)
    self.alt = down
    self:Fire("MODIFIER_STATE_CHANGED", "LALT", down and 1 or 0)
end

-- Our click shield over a bag button, if one was ever created.
function world:Shield(slot)
    for _, frame in ipairs(self.frames) do
        if frame.parent == self.buttons[slot] and frame.itemButton then
            return frame
        end
    end
end

function world:IsShielded(slot)
    local shield = self:Shield(slot)
    return shield ~= nil and shield.shown
end

function world:ClickShield(slot, mouseButton)
    local shield = assert(self:Shield(slot), "no shield on slot " .. slot)
    shield.scripts.OnClick(shield, mouseButton)
end

function world:AltClick(slot)
    self:SetAlt(true)
    self:ClickShield(slot, "LeftButton")
    self:SetAlt(false)
end

-- Describes the lock indicator on a bag button: "" (never drawn), "hidden",
-- or "<atlas> <width>x<height> <anchor>[+shadow]".
function world:Indicator(slot)
    local holder
    for _, frame in ipairs(self.frames) do
        if frame.parent == self.buttons[slot] and not frame.itemButton then
            holder = frame
        end
    end
    if not holder then
        return ""
    end
    if not holder.shown then
        return "hidden"
    end

    local glyph, shadow
    for _, texture in ipairs(self.textures) do
        if texture.owner == holder and texture.atlas then
            if texture.desaturated then
                shadow = texture.shown and texture or nil
            else
                glyph = texture
            end
        end
    end
    return ("%s %dx%d %s%s"):format(
        glyph.atlas,
        math.floor(glyph.width),
        math.floor(glyph.height),
        glyph.point,
        shadow and "+shadow" or ""
    )
end

-- Applies a requested sort: new slot i receives the item of old slot permutation[i].
function world:ApplySort(permutation)
    assert(self.sortRequested, "no sort was requested")
    self.sortRequested = false
    local old = self.bags[0]
    local sorted = {}
    for slot = 1, BAG_SIZE do
        sorted[slot] = old[permutation[slot]]
    end
    self.bags[0] = sorted
end

function world:OpenMerchant()
    MerchantFrame.shown = true
    self:Fire("MERCHANT_SHOW")
end

-- Clicks the merchant's Sell All Junk button: Blizzard shows its confirmation, then notifies.
function world:ClickSellAllJunk()
    local onClicked = self.eventRegistry["MerchantFrame.SellAllJunkButtonClicked"]
    if onClicked then
        onClicked()
    end
end

function world:Bag()
    local bag = self.bags[0]
    local slots = {}
    for slot = 1, BAG_SIZE do
        slots[slot] = bag[slot] or "-"
    end
    return table.concat(slots, " ")
end

return world
