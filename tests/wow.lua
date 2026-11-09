-- Fake Forever client: just enough of the WoW API for the addon to load and run
-- outside the game. Loaded fresh, in its own environment, for every test.
-- Returns `world`: the test's handle to drive and inspect the fake client.
--
-- The world has one bag (ID 0) of BAG_SIZE slots holding item GUID strings, a
-- cursor, a fake clock, and a server that applies sorts on demand and confirms
-- item swaps after SERVER_CONFIRM_SECONDS. It also has a quest log (entries
-- with a distance to the player and objectives), a quest watch list and a
-- combat flag, plus a player position (world.position) and the map pin
-- (world.waypoint). The player can be in a party and/or an instance group
-- (world.party, world.instanceGroup); group chat goes to world.sentChat and
-- incoming chat runs through the registered chat filters (world:ReceiveChat).
-- At a merchant, the player has world.money and gear to repair for
-- world.repairCost; sold items are credited after SERVER_CONFIRM_SECONDS.
--
-- The character bank is two purchased tabs (containers 6 and 7, of
-- world.bagSizes slots) out of world.maxBankTabs, with a bag in tab 2's bank bag
-- slot. Like the client, bank contents only exist while the bank is open.

local BAG_SIZE = 4
local SERVER_CONFIRM_SECONDS = 0.05

local world = {
    now = 0,
    frames = {},
    textures = {},
    fontStrings = {},
    timers = {},
    nextFrameCallbacks = {},
    settings = {},
    categories = {},
    eventRegistry = {},
    errors = {},
    warnings = {},
    prints = {},
    hiddenPopups = {},
    popups = {},
    sold = {},
    excludedFromJunkSell = {},
    sellPrices = {},
    sellAllJunkEnabled = true,
    sellAllJunkCalls = 0,
    money = 0,
    repairCost = 0,
    merchantCanRepair = true,
    guildRepair = { allowed = false, withdrawLimit = 0 },
    repairs = {},
    swapTimes = {},
    pickups = 0,
    alt = false,
    cursor = nil,
    bags = { [0] = { "G1", "G2", nil, "GJUNK" }, [6] = { "B1", nil, "B2" }, [7] = { nil, "B3" } },
    bagSizes = { [6] = 4, [7] = 2 },
    quality = { GJUNK = 0 },
    counts = { B2 = 20 },
    itemIDs = {},
    maxStacks = {},
    itemFamilies = {},
    bagFamilies = {},
    itemTypes = {},
    bankOpen = false,
    bankTabs = { 6, 7 },
    maxBankTabs = 3,
    bankBags = { [2] = "GBAG" },
    player = { guid = "Player-1-00000001", name = "Hylmew", class = "MAGE", realm = "Forever" },
    itemSearch = "",
    modifiedClicks = {},
    sortRequested = false,
    questLog = {},
    watches = {},
    superTracked = 0,
    inCombat = false,
    questSorts = 0,
    position = { x = 0, y = 0, continentID = 0 },
    onTaxi = false,
    party = false,
    instanceGroup = false,
    sentChat = {},
    chatFilters = {},
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

-- The client's bit library (Lua 5.1 has no bitwise operators).
bit = {
    band = function(a, b)
        local result, value = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then
                result = result + value
            end
            a, b, value = math.floor(a / 2), math.floor(b / 2), value * 2
        end
        return result
    end,
}

function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

-- hooksecurefunc([tbl,] name, hook): a global function when no table is given.
function hooksecurefunc(tbl, name, hook)
    if type(tbl) == "string" then
        tbl, name, hook = _G, tbl, name
    end
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
        WrapTextInColorCode = function(_, text)
            return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), text)
        end,
    }
end

RAID_CLASS_COLORS = { MAGE = CreateColor(0.25, 0.78, 0.92), WARRIOR = CreateColor(0.78, 0.61, 0.43) }

PAGE_NUMBER = "Page %d"
BANK_BAG = "Bank Bag"
BANK_BAG_PURCHASE = "Purchase Bank Bag"
BAGSLOTTEXT_COLON = "Bag Slots:"
INVTYPE_HEAD = "Head"

function CreateAtlasMarkup(atlas)
    return "|A:" .. atlas .. "|a"
end

function GetLocale()
    return TEST_LOCALE
end

-- world.loadedAddOns: load-on-demand Blizzard addons loaded so far.
world.loadedAddOns = {}
C_AddOns = {
    GetAddOnMetadata = function(_, field)
        return field == "Title" and "Forever Enhanced" or nil
    end,
    IsAddOnLoaded = function(name)
        return world.loadedAddOns[name] == true
    end,
}

-- Frames and textures ----------------------------------------------------------

local Region = {}
Region.__index = Region

local function NoOp() end
-- Cosmetic methods: nothing a test needs to observe.
for _, name in ipairs({
    "SetAllPoints",
    "RegisterForClicks",
    "RegisterForDrag",
    "SetHighlightTexture",
    "SetVertexColor",
    "SetFrameLevel",
    "SetToplevel",
    "EnableMouse",
    "SetHorizTile",
    "SetVertTile",
    "SetRotation",
    "SetJustifyH",
    "SetScale",
    "SetTextColor",
}) do
    Region[name] = NoOp
end

local function NewRegion(fields)
    fields.shown = true
    fields.events = {}
    fields.scripts = {}
    fields.hooks = {}
    return setmetatable(fields, Region)
end

-- Runs a script handler, then its hooks, like the client.
function Region:RunScript(name, ...)
    if self.scripts[name] then
        self.scripts[name](self, ...)
    end
    for _, hook in ipairs(self.hooks[name] or {}) do
        hook(self, ...)
    end
end

function Region:HookScript(name, hook)
    self.hooks[name] = self.hooks[name] or {}
    table.insert(self.hooks[name], hook)
end

function Region:SetParent(parent)
    self.parent = parent
end

function Region:SetWidth(width)
    self.width = width
end

function Region:SetHeight(height)
    self.height = height
end

function Region:SetTexture(texture)
    self.texture = texture
end

-- Edit boxes fire OnTextChanged (userInput false) when set from code.
function Region:SetText(text)
    self.text = text
    if self.frameType == "EditBox" then
        self:RunScript("OnTextChanged", false)
    end
end

function Region:GetText()
    return self.text or ""
end

function Region:CreateFontString()
    local fontString = NewRegion({ owner = self, frameType = "FontString" })
    table.insert(world.fontStrings, fontString)
    return fontString
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
    if not self.shown then
        self.shown = true
        self:RunScript("OnShow")
    end
end

function Region:Hide()
    if self.shown then
        self.shown = false
        self:RunScript("OnHide")
    end
end

function Region:SetShown(shown)
    if shown then
        self:Show()
    else
        self:Hide()
    end
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

-- self.point: the first anchor's point; self.anchors: every anchor, like GetPoint.
function Region:ClearAllPoints()
    self.point = nil
    self.anchors = {}
end

-- The client keeps anchor offsets as 32-bit floats: GetPoint doesn't always
-- return the number given to SetPoint (e.g. one read back from saved variables).
local function ToFloat32(value)
    if not string.pack then
        return value
    end
    local stored = string.unpack("f", string.pack("f", value))
    return math.tointeger(stored) or stored
end

-- SetPoint(point [, relativeTo [, relativePoint]] [, x, y]), one anchor per point.
function Region:SetPoint(point, relativeTo, relativePoint, x, y)
    if type(relativeTo) == "number" then
        relativeTo, relativePoint, x, y = nil, nil, relativeTo, relativePoint
    end
    self.point = self.point or point
    self.anchors = self.anchors or {}
    local anchor = { point, relativeTo or self.parent, relativePoint or point, ToFloat32(x or 0), ToFloat32(y or 0) }
    for index, existing in ipairs(self.anchors) do
        if existing[1] == point then
            self.anchors[index] = anchor
            return
        end
    end
    table.insert(self.anchors, anchor)
end

function Region:GetNumPoints()
    return #(self.anchors or {})
end

function Region:GetPoint(index)
    local anchor = (self.anchors or {})[index or 1]
    if anchor then
        return unpack(anchor, 1, 5)
    end
end

function Region:GetWidth()
    return self.width or 0
end

function Region:GetHeight()
    return self.height or 0
end

-- A point's offset from the bottom left corner of a width x height rect.
local function PointOffset(point, width, height)
    local x = point:find("LEFT") and 0 or point:find("RIGHT") and width or width / 2
    local y = point:find("BOTTOM") and 0 or point:find("TOP") and height or height / 2
    return x, y
end

-- The frame's bottom left corner on screen, from its first anchor (UIParent is the screen).
function Region:GetBottomLeftCorner()
    if self == UIParent then
        return 0, 0
    end
    local point, relativeTo, relativePoint, x, y = self:GetPoint(1)
    if not point then
        return nil
    end
    local relativeLeft, relativeBottom = relativeTo:GetBottomLeftCorner()
    local relativeX, relativeY = PointOffset(relativePoint, relativeTo:GetWidth(), relativeTo:GetHeight())
    local ownX, ownY = PointOffset(point, self:GetWidth(), self:GetHeight())
    return relativeLeft + relativeX + x - ownX, relativeBottom + relativeY + y - ownY
end

function Region:GetLeft()
    return (self:GetBottomLeftCorner())
end

function Region:GetBottom()
    return select(2, self:GetBottomLeftCorner())
end

function Region:GetRight()
    local left = self:GetLeft()
    return left and left + self:GetWidth()
end

function Region:GetName()
    return self.name
end

function Region:GetAttribute(name)
    return (self.attributes or {})[name]
end

-- Tests mark frames protected (protected children make a frame protected).
function Region:IsProtected()
    return self.protected == true
end

function Region:SetMovable(movable)
    self.movable = movable
end

function Region:IsMovable()
    return self.movable == true
end

function Region:SetUserPlaced(userPlaced)
    self.userPlaced = userPlaced
end

function Region:IsUserPlaced()
    return self.userPlaced == true
end

-- Like the client: only movable frames move, and they become user-placed.
function Region:StartMoving()
    assert(self.movable, "StartMoving on a frame that isn't movable")
    assert(not (world.inCombat and self.protected), "ADDON_ACTION_BLOCKED: StartMoving")
    self.moving = true
    self.userPlaced = true
end

-- Drops the frame at world.dropAt, re-anchored to UIParent like the client does.
function Region:StopMovingOrSizing()
    if self.moving then
        self.moving = false
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", world.dropAt.x, world.dropAt.y)
    end
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
    local texture = NewRegion({ owner = self })
    table.insert(world.textures, texture)
    return texture
end

-- Item buttons.
function Region:GetNormalTexture()
    self.normalTexture = self.normalTexture or self:CreateTexture()
    return self.normalTexture
end

function Region:SetMatchesSearch(matches)
    self.matchesSearch = matches
end

function SetItemButtonTexture(button, texture)
    button.icon = texture
end

function SetItemButtonCount(button, count)
    button.count = count
end

function SetItemButtonQuality(button, quality)
    button.quality = quality
end

function HandleModifiedItemClick(link)
    table.insert(world.modifiedClicks, link)
end

TextureKitConstants = { UseAtlasSize = true, IgnoreAtlasSize = false }

-- Records the last context menu opened: world.contextMenu = { owner, generator }.
MenuUtil = {
    CreateContextMenu = function(owner, generator)
        world.contextMenu = { owner = owner, generator = generator }
    end,
}
NineSliceUtil = { ApplyLayoutByName = NoOp }

-- The Blizzard templates the addon uses: the parts it touches.
local templates = {
    NineSlicePanelTemplate = NoOp,
    UIPanelButtonTemplate = NoOp,
    BankPanelEdgeShadowTemplate = NoOp,
    SearchBoxTemplate = NoOp,
    PortraitFrameTemplate = function(frame)
        frame.TitleContainer = CreateFrame("Frame", nil, frame)
        function frame:SetTitle(title)
            self.title = title
        end
        function frame:SetPortraitToClassIcon(class)
            self.portraitClass = class
        end
    end,
    -- SidePanelTabButtonMixin
    LargeSideTabButtonTemplate = function(frame)
        for _, key in ipairs({ "Background", "Icon", "Mask", "SelectedTexture", "TabGlow", "HighlightTexture" }) do
            frame[key] = frame:CreateTexture()
        end
        function frame:SetChecked(checked)
            self.checked = checked
        end
        function frame:SetCustomOnMouseUpHandler(handler)
            self.customMouseUpHandler = handler
        end
        frame.SetFillToInterior = NoOp
        function frame:GetIconAnchorOffsetsForTabArt()
            return -3, 0
        end
        function frame:InitializeIconAnchoring()
            self.iconOffsetX = self:GetFinalIconAnchorOffsets()
        end
        frame.GetFinalIconAnchorOffsets = frame.GetIconAnchorOffsetsForTabArt
    end,
    WowStyle1DropdownTemplate = function(frame)
        function frame:SetupMenu(generator)
            self.menuGenerator = generator
        end
        frame.GenerateMenu = NoOp
    end,
}

function CreateFrame(frameType, name, parent, template)
    local frame = NewRegion({ frameType = frameType, name = name, parent = parent, template = template })
    if template then
        assert(templates[template], "unknown template " .. template)(frame)
    end
    if name then
        _G[name] = frame
    end
    table.insert(world.frames, frame)
    return frame
end

UIParent = CreateFrame("Frame")
UIParent:SetSize(1920, 1080)

-- UI panels. The panel manager does nothing in combat (CheckProtectedFunctionsAllowed).
-- Every re-layout re-anchors each open panel (ignoring where the player put it),
-- the one being shown included, before it is shown.
UIPanelWindows = {}
UISpecialFrames = {}
world.PANEL_ANCHOR = { "TOPLEFT", "TOPLEFT", 16, -116 }

function RegisterUIPanel(frame, attributes)
    UIPanelWindows[assert(frame.name, "UI panels need a name")] = attributes
end

function UpdateUIPanelPositions(shownFrame)
    local point, relativePoint, x, y = unpack(world.PANEL_ANCHOR)
    for name, attributes in pairs(UIPanelWindows) do
        local frame = _G[name]
        if frame and attributes.area ~= "full" and (frame:IsShown() or frame == shownFrame) then
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, relativePoint, x, y)
        end
    end
end

function ShowUIPanel(frame)
    if not world.inCombat then
        UpdateUIPanelPositions(frame)
        frame:Show()
    end
end

function HideUIPanel(frame)
    if not world.inCombat then
        frame:Hide()
        UpdateUIPanelPositions()
    end
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
    NewTicker = function(seconds, callback)
        local ticker = C_Timer.NewTimer(seconds, callback)
        ticker.interval = seconds
        return ticker
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

function Setting:GetDefaultValue()
    return self.default
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

MinimalSliderWithSteppersMixin = { Label = { Right = 3 } }

Settings = {
    VarType = { Boolean = "boolean", String = "string", Number = "number" },
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
        local setting = setmetatable({ key = key, tbl = tbl, name = name, default = default }, Setting)
        world.settings[variable] = setting
        return setting
    end,
    CreateCheckbox = function(category, setting, tooltip)
        return AddInitializer(category, { setting = setting, tooltip = tooltip })
    end,
    CreateDropdown = function(category, setting, getOptions, tooltip)
        return AddInitializer(category, { setting = setting, tooltip = tooltip, options = getOptions() })
    end,
    CreateSliderOptions = function(minValue, maxValue, step)
        return {
            minValue = minValue,
            maxValue = maxValue,
            step = step,
            SetLabelFormatter = function(self, _, formatter)
                self.formatter = formatter
            end,
        }
    end,
    CreateSlider = function(category, setting, sliderOptions, tooltip)
        return AddInitializer(category, { setting = setting, tooltip = tooltip, slider = sliderOptions })
    end,
    -- A custom row (our text control): created, then registered to the category.
    CreateControlInitializer = function(template, setting, options, tooltip)
        assert(template, "missing template")
        return setmetatable(
            { template = template, setting = setting, options = options, tooltip = tooltip },
            Initializer
        )
    end,
    RegisterInitializer = function(category, initializer)
        table.insert(category.items, initializer)
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
    BagIndex = {
        Characterbanktab = -2,
        Backpack = 0,
        CharacterBankTab_1 = 6,
        CharacterBankTab_2 = 7,
        CharacterBankTab_3 = 8,
    },
    BankType = { Character = 0, Account = 2 },
    BagSlotFlags = { ExcludeJunkSell = 64 },
    ItemQuality = { Poor = 0 },
    TooltipDataType = { Item = 0 },
    CraftingReagentType = { Optional = 0, Basic = 1, Finishing = 2 },
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

-- Bank bag slots: slot N of Characterbanktab holds the bag of bank tab N.
local function ItemAt(location)
    if location.bagID == Enum.BagIndex.Characterbanktab then
        return world.bankBags[location.slot]
    end
    local bag = world.bags[location.bagID]
    return bag and bag[location.slot]
end

local function ItemLink(guid)
    return "|cffffffff|Hitem:" .. guid .. "|h[" .. guid .. "]|h|r"
end

local function ItemIcon(guid)
    return "icon:" .. guid
end

local function ItemQuality(guid)
    return world.quality[guid] or 2
end

-- Stacks: world.itemIDs[guid] (default: the GUID), world.counts[guid] (default
-- 1) and world.maxStacks[itemID] (default 1: not stackable).
local function ItemID(guid)
    return world.itemIDs[guid] or guid
end

local function StackCount(guid)
    return world.counts[guid] or 1
end

local function MaxStack(guid)
    return world.maxStacks[ItemID(guid)] or 1
end

C_Item = {
    DoesItemExist = function(location)
        return ItemAt(location) ~= nil
    end,
    GetItemGUID = ItemAt,
    GetItemLink = function(location)
        return ItemLink(ItemAt(location))
    end,
    GetItemIcon = function(location)
        return ItemIcon(ItemAt(location))
    end,
    GetItemQuality = function(location)
        return ItemQuality(ItemAt(location))
    end,
    GetItemMaxStackSize = function(location)
        return MaxStack(ItemAt(location))
    end,
    -- Bag type flags of the item (world.itemFamilies[itemID]), 0 for any bag.
    GetItemFamily = function(itemID)
        return world.itemFamilies[itemID] or 0
    end,
    -- Without its include flags: the bags only.
    GetItemCount = function(itemID)
        local count = 0
        for _, guid in pairs(world.bags[0]) do
            if ItemID(guid) == itemID then
                count = count + StackCount(guid)
            end
        end
        return count
    end,
    -- world.itemTypes[guid] = { itemType, itemSubType, equipLoc }; items are their own IDs.
    GetItemInfoInstant = function(itemIDOrLink)
        local guid = itemIDOrLink:match("%[(.-)%]") or itemIDOrLink
        local itemType = world.itemTypes[guid] or { "Miscellaneous", "Other", "" }
        return guid, itemType[1], itemType[2], itemType[3]
    end,
    -- Only the sell price (11th return) is modelled: world.sellPrices[itemID], default 0.
    GetItemInfo = function(itemID)
        return itemID, nil, nil, nil, nil, nil, nil, nil, nil, nil, world.sellPrices[itemID] or 0
    end,
}

-- Merchant ------------------------------------------------------------------------------------
-- The player has world.money copper. Selling an item removes it from the bag at once
-- (world.sold); the server credits its price later and fires PLAYER_MONEY.

local function SellItem(bagID, slot)
    local guid = world.bags[bagID][slot]
    table.insert(world.sold, guid)
    world.bags[bagID][slot] = nil
    local price = (world.sellPrices[ItemID(guid)] or 0) * StackCount(guid)
    C_Timer.NewTimer(SERVER_CONFIRM_SECONDS, function()
        world.money = world.money + price
        world:Fire("PLAYER_MONEY")
    end)
end

C_MerchantFrame = {
    IsSellAllJunkEnabled = function()
        return world.sellAllJunkEnabled
    end,
    -- Sells every poor-quality item of the bags not excluded from Sell All Junk.
    SellAllJunkItems = function()
        assert(MerchantFrame.shown, "SellAllJunkItems outside a merchant")
        world.sellAllJunkCalls = world.sellAllJunkCalls + 1
        if world.excludedFromJunkSell[0] then
            return
        end
        for slot = 1, BAG_SIZE do
            local guid = world.bags[0][slot]
            if guid and ItemQuality(guid) == Enum.ItemQuality.Poor then
                SellItem(0, slot)
            end
        end
    end,
}

function GetMoney()
    return world.money
end

-- Plain copper amounts are enough to compare messages.
function GetMoneyString(money)
    return tostring(money) .. "c"
end

function CanMerchantRepair()
    return MerchantFrame.shown and world.merchantCanRepair
end

function GetRepairAllCost()
    return world.repairCost, world.repairCost > 0
end

function CanGuildBankRepair()
    return world.guildRepair.allowed
end

function GetGuildBankWithdrawMoney()
    return world.guildRepair.withdrawLimit
end

-- world.repairs logs "guild <cost>" or "player <cost>". The player must afford it.
function RepairAllItems(guildBank)
    assert(CanMerchantRepair(), "RepairAllItems without a repair merchant")
    local cost = world.repairCost
    if guildBank then
        table.insert(world.repairs, "guild " .. cost)
    else
        assert(world.money >= cost, "RepairAllItems without enough money")
        world.money = world.money - cost
        table.insert(world.repairs, "player " .. cost)
    end
    world.repairCost = 0
end

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

function IsShiftKeyDown()
    return world.shift == true
end

function IsControlKeyDown()
    return world.ctrl == true
end

local function IsBankTab(bagID)
    return bagID >= Enum.BagIndex.CharacterBankTab_1 and bagID <= Enum.BagIndex.CharacterBankTab_3
end

C_Container = {
    GetContainerNumSlots = function(bagID)
        if not world.bags[bagID] or (IsBankTab(bagID) and not world.bankOpen) then
            return 0
        end
        return world.bagSizes[bagID] or BAG_SIZE
    end,
    GetContainerItemInfo = function(bagID, slot)
        if IsBankTab(bagID) and not world.bankOpen then
            return nil
        end
        local guid = world.bags[bagID][slot]
        return guid
            and {
                quality = ItemQuality(guid),
                hasNoValue = false,
                isLocked = false,
                isBound = false,
                hyperlink = ItemLink(guid),
                itemName = guid,
                itemID = ItemID(guid),
                iconFileID = ItemIcon(guid),
                stackCount = StackCount(guid),
            }
    end,
    -- Free slots and the bag type flags of the bag (world.bagFamilies), 0 for a normal bag.
    GetContainerNumFreeSlots = function(bagID)
        local free = 0
        for slot = 1, C_Container.GetContainerNumSlots(bagID) do
            if not world.bags[bagID][slot] then
                free = free + 1
            end
        end
        return free, world.bagFamilies[bagID] or 0
    end,
    -- Blizzard's bag search box calls this on every change.
    SetItemSearch = function(text)
        world.itemSearch = text
        world:Fire("INVENTORY_SEARCH_UPDATE")
    end,
    -- Empty cursor: pick up. Holding an item, onto its own slot: put it back.
    -- Onto the same item with room: merge up to the max stack, the rest stays in
    -- the source slot. Otherwise swap. Moves are confirmed by the server later.
    PickupContainerItem = function(bagID, slot)
        world.pickups = world.pickups + 1
        local from = world.cursor
        if not from then
            world.cursor = ItemLocation:CreateFromBagAndSlot(bagID, slot)
            world:Fire("CURSOR_CHANGED")
            return
        end

        world.cursor = nil
        if from.bagID ~= bagID or from.slot ~= slot then
            local bags = world.bags
            local moving, target = bags[from.bagID][from.slot], bags[bagID][slot]
            local room = target and ItemID(target) == ItemID(moving) and MaxStack(target) - StackCount(target) or 0
            if room > 0 then
                local moved = math.min(room, StackCount(moving))
                world.counts[target] = StackCount(target) + moved
                if moved == StackCount(moving) then
                    bags[from.bagID][from.slot] = nil
                    world.counts[moving] = nil
                else
                    world.counts[moving] = StackCount(moving) - moved
                end
            else
                bags[from.bagID][from.slot], bags[bagID][slot] = target, moving
                table.insert(world.swapTimes, world.now)
            end
            C_Timer.NewTimer(SERVER_CONFIRM_SECONDS, function()
                world:Fire("BAG_UPDATE_DELAYED")
            end)
        end
        world:Fire("CURSOR_CHANGED")
    end,
    -- Only selling (merchant open) is modelled: the item leaves the bag.
    UseContainerItem = function(bagID, slot)
        assert(MerchantFrame.shown, "UseContainerItem outside a merchant")
        SellItem(bagID, slot)
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

-- Quests ----------------------------------------------------------------------------------
-- world.questLog entries: { questID, title, distance (yards, nil = no location),
-- offContinent, onMap, isHeader, isHidden, isTask, isBounty, isWorldQuest,
-- objectives = { { text, finished, numFulfilled, numRequired }, ... } }.

local function FindQuest(questID)
    for _, quest in ipairs(world.questLog) do
        if quest.questID == questID then
            return quest
        end
    end
end

local function WatchIndex(questID)
    for index, watched in ipairs(world.watches) do
        if watched == questID then
            return index
        end
    end
end

Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 25 } }

C_QuestLog = {
    GetNumQuestLogEntries = function()
        return #world.questLog, #world.questLog
    end,
    GetInfo = function(index)
        return world.questLog[index]
    end,
    IsWorldQuest = function(questID)
        return FindQuest(questID).isWorldQuest == true
    end,
    GetDistanceSqToQuest = function(questID)
        local quest = FindQuest(questID)
        if quest and quest.distance then
            return quest.distance * quest.distance, not quest.offContinent
        end
    end,
    GetQuestsOnMap = function()
        local pois = {}
        for _, quest in ipairs(world.questLog) do
            if quest.onMap then
                table.insert(pois, { questID = quest.questID })
            end
        end
        return pois
    end,
    GetQuestWatchType = function(questID)
        return WatchIndex(questID) and 0 or nil
    end,
    GetNumQuestWatches = function()
        return #world.watches
    end,
    GetQuestIDForQuestWatchIndex = function(index)
        return world.watches[index]
    end,
    -- Like the client, watch changes fire QUEST_WATCH_LIST_CHANGED synchronously.
    AddQuestWatch = function(questID)
        assert(not WatchIndex(questID), "quest already watched")
        assert(#world.watches < Constants.QuestWatchConsts.MAX_QUEST_WATCHES, "too many watches")
        table.insert(world.watches, questID)
        world:Fire("QUEST_WATCH_LIST_CHANGED", questID, true)
        return true
    end,
    RemoveQuestWatch = function(questID)
        table.remove(world.watches, assert(WatchIndex(questID), "quest not watched"))
        world:Fire("QUEST_WATCH_LIST_CHANGED", questID, false)
        return true
    end,
    SortQuestWatches = function()
        world.questSorts = world.questSorts + 1
    end,
    -- Nothing for a quest that isn't in the log or whose data hasn't loaded.
    GetQuestObjectives = function(questID)
        local quest = FindQuest(questID)
        return quest and quest.objectives
    end,
    GetTitleForQuestID = function(questID)
        local quest = FindQuest(questID)
        return quest and quest.title
    end,
}

function GetQuestLink(questID)
    local quest = FindQuest(questID)
    if quest and quest.title then
        return ("|cffffff00|Hquest:%d:10|h[%s]|h|r"):format(questID, quest.title)
    end
end

-- Group and chat ----------------------------------------------------------------------------

LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2

function IsInGroup(category)
    if category == LE_PARTY_CATEGORY_HOME then
        return world.party
    elseif category == LE_PARTY_CATEGORY_INSTANCE then
        return world.instanceGroup
    end
    return world.party or world.instanceGroup
end

-- "Name-Realm" -> "Name" for players of the player's realm.
function Ambiguate(fullName, context)
    assert(context == "none", "only the none context is modelled")
    local name, realm = fullName:match("^(.-)%-(.+)$")
    if name and realm == world.player.realm then
        return name
    end
    return fullName
end

C_ChatInfo = {
    SendChatMessage = function(message, chatType)
        assert(#message <= 255, "chat message too long")
        assert(not message:find("|4"), "chat refuses grammar codes")
        table.insert(world.sentChat, { message = message, chatType = chatType })
    end,
    ReplaceIconAndGroupExpressions = function(message)
        return message
    end,
}

-- world.chatFilters[event] = { filter, ... }, in registration order, without duplicates.
ChatFrameUtil = {
    AddMessageEventFilter = function(event, filter)
        world.chatFilters[event] = world.chatFilters[event] or {}
        if not tContains(world.chatFilters[event], filter) then
            table.insert(world.chatFilters[event], filter)
        end
    end,
    RemoveMessageEventFilter = function(event, filter)
        local filters = world.chatFilters[event] or {}
        for index = #filters, 1, -1 do
            if filters[index] == filter then
                table.remove(filters, index)
            end
        end
    end,
}

-- Bank -----------------------------------------------------------------------------------

C_Bank = {
    CanViewBank = function(bankType)
        return world.bankOpen and bankType == Enum.BankType.Character
    end,
    -- Index N is bank tab N; tabs 2 and up are the bank bag slots.
    FetchPurchasedBankTabData = function(bankType)
        assert(bankType == Enum.BankType.Character, "only the character bank is modelled")
        local tabs = {}
        for index, bagID in ipairs(world.bankTabs) do
            tabs[index] = { ID = bagID, bankType = bankType }
        end
        return tabs
    end,
    FetchMaxNumBankTabs = function()
        return world.maxBankTabs
    end,
}

-- Player ----------------------------------------------------------------------------------

function UnitGUID(unit)
    assert(unit == "player", "only the player is modelled")
    return world.player.guid
end

function UnitName()
    return world.player.name
end

function UnitClass()
    return world.player.class:lower(), world.player.class
end

function GetNormalizedRealmName()
    return world.player.realm
end

C_SuperTrack = {
    GetSuperTrackedQuestID = function()
        return world.superTracked
    end,
}

-- Maps are MAP_SIZE yards squares whose top left corner is the world origin of
-- their continent: map 1 is on continent 0, map 2 on continent 1.
local MAP_SIZE = 1000
local MAP_CONTINENTS = { [1] = 0, [2] = 1 }

C_Map = {
    GetBestMapForUnit = function()
        return 1
    end,
    SetUserWaypoint = function(point)
        world.waypoint = point
        world:Fire("USER_WAYPOINT_UPDATED")
        return true
    end,
    ClearUserWaypoint = function()
        world.waypoint = nil
        world:Fire("USER_WAYPOINT_UPDATED")
    end,
    HasUserWaypoint = function()
        return world.waypoint ~= nil
    end,
    GetUserWaypoint = function()
        return world.waypoint
    end,
    GetWorldPosFromMapPos = function(uiMapID, position)
        local continentID = MAP_CONTINENTS[uiMapID]
        if continentID then
            return continentID, { x = position.x * MAP_SIZE, y = position.y * MAP_SIZE }
        end
    end,
}

-- World coordinates in yards, in the order of the matching world position
-- fields (x, y); nothing in an instance, like the client.
function UnitPosition(unit)
    assert(unit == "player", "only the player is modelled")
    local position = world.position
    if not position.instanceID then
        return position.x, position.y, 0, position.continentID
    end
end

function UnitOnTaxi()
    return world.onTaxi
end

function InCombatLockdown()
    return world.inCombat
end

-- UI globals ---------------------------------------------------------------------------

GameTooltip = {
    SetOwner = NoOp,
    SetBagItem = NoOp,
    SetHyperlink = function(_, link)
        world.tooltip = link
    end,
    SetText = function(_, text)
        world.tooltip = text
    end,
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
    AddExternalWarningMessage = function(_, message)
        table.insert(world.warnings, message)
    end,
}

NAVIGATION_DESTINATION_REACHED_MESSAGE = "You have reached your destination."

DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, message)
        table.insert(world.prints, message)
    end,
}

-- world.eventRegistry[event] = { [owner] = callback }, nil once empty.
EventRegistry = {
    RegisterCallback = function(_, event, callback, owner)
        world.eventRegistry[event] = world.eventRegistry[event] or {}
        world.eventRegistry[event][owner] = callback
    end,
    UnregisterCallback = function(_, event, owner)
        local callbacks = world.eventRegistry[event]
        if callbacks then
            callbacks[owner] = nil
            if next(callbacks) == nil then
                world.eventRegistry[event] = nil
            end
        end
    end,
    TriggerEvent = function(_, event, ...)
        for owner, callback in pairs(world.eventRegistry[event] or {}) do
            callback(owner, ...)
        end
    end,
}

function StaticPopup_Hide(which)
    table.insert(world.hiddenPopups, which)
end

-- Records the popup data ({ text, text_arg1, text_arg2, callback }); tests accept it by calling callback.
function StaticPopup_ShowCustomGenericConfirmation(data)
    table.insert(world.popups, data)
end

-- Item tooltip post-calls, in registration order.
world.tooltipPostCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(dataType, callback)
        assert(dataType == Enum.TooltipDataType.Item, "only item tooltips are modelled")
        table.insert(world.tooltipPostCalls, callback)
    end,
}

NORMAL_FONT_COLOR = CreateColor(1, 0.82, 0)

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

ContainerFrameCombinedBags = CreateFrame("Frame", "ContainerFrameCombinedBags")
ContainerFrameCombinedBags:SetSize(400, 300)
function ContainerFrameCombinedBags:EnumerateValidItems()
    return ipairs(world.buttons)
end
ContainerFrameCombinedBags.UpdateItems = NoOp

-- Separate bag frames, used when bags aren't combined: the backpack, then a bag.
for index = 1, 2 do
    local frame = CreateFrame("Frame", "ContainerFrame" .. index)
    frame.shown = false
    frame:SetSize(200, 150)
    function frame:EnumerateValidItems()
        return pairs({})
    end
    frame.UpdateItems = NoOp
end

ContainerFrameContainer = { ContainerFrames = { ContainerFrame1, ContainerFrame2 } }

-- Re-anchors every open bag frame, wherever the player put it: the first one to
-- the screen at BAG_ANCHOR, each other one on top of the one before it.
world.BAG_ANCHOR = { "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 100 }
world.BAG_SPACING = 5
function UpdateContainerFrameAnchors()
    local point, relativePoint, x, y = unpack(world.BAG_ANCHOR)
    local previousBag
    for _, frame in ipairs({ ContainerFrameCombinedBags, unpack(ContainerFrameContainer.ContainerFrames) }) do
        if frame:IsShown() then
            frame:ClearAllPoints()
            if previousBag then
                frame:SetPoint("BOTTOMRIGHT", previousBag, "TOPRIGHT", 0, world.BAG_SPACING)
            else
                frame:SetPoint(point, UIParent, relativePoint, x, y)
            end
            previousBag = frame
        end
    end
end

ERR_NOT_IN_COMBAT = "You can't do that while in combat"

-- A few UI panels: CharacterFrame (left), CinematicFrame (full screen), LootFrame (Edit Mode).
for name, area in pairs({ CharacterFrame = "left", CinematicFrame = "full", LootFrame = "left" }) do
    local frame = CreateFrame("Frame", name, UIParent, "PortraitFrameTemplate")
    frame.shown = false
    RegisterUIPanel(frame, { area = area })
end

-- BagSearch_OnTextChanged
BagItemSearchBox = CreateFrame("EditBox")
BagItemSearchBox:SetScript("OnTextChanged", function(box)
    C_Container.SetItemSearch(box:GetText())
end)

BankFrame = CreateFrame("Frame")
BankFrame.shown = false

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
        if nextTimer.interval then
            nextTimer.at = nextTimer.at + nextTimer.interval
        else
            nextTimer.ran = true
        end
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

function world:CloseMerchant()
    MerchantFrame.shown = false
    self:Fire("MERCHANT_CLOSED")
end

-- Clicks the merchant's Sell All Junk button: Blizzard shows its confirmation, then notifies.
function world:ClickSellAllJunk()
    EventRegistry:TriggerEvent("MerchantFrame.SellAllJunkButtonClicked")
end

-- Replaces the quest log: { { questID = 1, distance = 100, ... }, ... } (see Quests above).
function world:SetQuests(quests)
    self.questLog = quests
end

-- Places the map pin at (x, y) yards on map 1 (or uiMapID), like a Ctrl Click on the map.
function world:SetWaypoint(x, y, uiMapID)
    C_Map.SetUserWaypoint({ uiMapID = uiMapID or 1, position = { x = x / MAP_SIZE, y = y / MAP_SIZE } })
end

-- Moves the player to (x, y) yards on continent 0 (or continentID), or into an instance.
function world:StandAt(x, y, continentID, instanceID)
    self.position = { x = x, y = y, continentID = continentID or 0, instanceID = instanceID }
end

-- The player moved: { [questID] = new distance }.
function world:MoveTo(distances)
    for questID, distance in pairs(distances) do
        FindQuest(questID).distance = distance
    end
end

-- The player tracks or untracks a quest from the quest log or the tracker.
function world:TrackQuest(questID)
    C_QuestLog.AddQuestWatch(questID)
end

function world:UntrackQuest(questID)
    C_QuestLog.RemoveQuestWatch(questID)
end

-- The player accepts a quest: Blizzard's autoQuestWatch watches it from its
-- own QUEST_ACCEPTED handler, which runs before ours.
function world:AcceptQuest(quest)
    table.insert(self.questLog, quest)
    C_QuestLog.AddQuestWatch(quest.questID)
    self:Fire("QUEST_ACCEPTED", quest.questID)
end

-- Objective `index` of a quest now has `numFulfilled` (and the objective text
-- `text`, if given; "<n>/<total> <name>" stays in sync otherwise), then the
-- client fires QUEST_LOG_UPDATE.
function world:Progress(questID, index, numFulfilled, text)
    local objective = FindQuest(questID).objectives[index]
    if not text and objective.name then
        text = ("%d/%d %s"):format(numFulfilled, objective.numRequired, objective.name)
    end
    objective.numFulfilled = numFulfilled
    objective.finished = numFulfilled >= objective.numRequired
    objective.text = text or objective.text
    self:Fire("QUEST_LOG_UPDATE")
end

-- A counted objective, like the client's: "0/8 Kobold Vermin slain".
function world:Objective(name, numRequired, numFulfilled)
    numFulfilled = numFulfilled or 0
    return {
        name = name,
        text = ("%d/%d %s"):format(numFulfilled, numRequired, name),
        finished = numFulfilled >= numRequired,
        numFulfilled = numFulfilled,
        numRequired = numRequired,
    }
end

-- A group chat message from `author` ("Name-Realm"); true when a filter hid it.
function world:ReceiveChat(event, message, author)
    for _, filter in ipairs(self.chatFilters[event] or {}) do
        if filter(DEFAULT_CHAT_FRAME, event, message, author) then
            return true
        end
    end
    return false
end

-- Watched quest IDs, sorted: "1 3 4".
function world:Watched()
    local watched = {}
    for index, questID in ipairs(self.watches) do
        watched[index] = questID
    end
    table.sort(watched)
    return table.concat(watched, " ")
end

function world:Bag()
    local bag = self.bags[0]
    local slots = {}
    for slot = 1, BAG_SIZE do
        slots[slot] = bag[slot] or "-"
    end
    return table.concat(slots, " ")
end

-- A container's slots with stack counts, open or not: "L1(15) - L3".
function world:Slots(bagID)
    local bag = self.bags[bagID]
    local slots = {}
    for slot = 1, self.bagSizes[bagID] or BAG_SIZE do
        local guid = bag[slot]
        local count = guid and StackCount(guid) or 1
        slots[slot] = guid and (count > 1 and ("%s(%d)"):format(guid, count) or guid) or "-"
    end
    return table.concat(slots, " ")
end

-- Professions: the player opens the professions window for the first time,
-- which loads Blizzard_ProfessionsTemplates and its reagent slot mixin.
function world:LoadProfessions()
    ProfessionsReagentSlotMixin = {
        -- The real Update fills the slot unless items are loading: the name
        -- ("0/1 Linen") is rewritten every time.
        Update = function(slot)
            if not slot.loading then
                local schematic = slot.reagentSlotSchematic
                slot.Name:SetText(("0/%d %s"):format(schematic.quantityRequired, schematic.reagents[1].itemID))
            end
        end,
        IsLoading = function(slot)
            return slot.loading == true
        end,
        GetReagentSlotSchematic = function(slot)
            return slot.reagentSlotSchematic
        end,
    }
    self.loadedAddOns.Blizzard_ProfessionsTemplates = true
    self:Fire("ADDON_LOADED", "Blizzard_ProfessionsTemplates")
end

-- A basic reagent: { reagents = { { itemID } }, quantityRequired, reagentType }.
function world:Reagent(itemID, quantityRequired)
    return {
        reagents = { { itemID = itemID } },
        quantityRequired = quantityRequired,
        reagentType = Enum.CraftingReagentType.Basic,
    }
end

-- A recipe shows a reagent slot: a pooled slot (reused when given), filled the
-- client's way. The mixin is copied into the slot when it is created.
function world:ShowReagentSlot(schematic, slot, loading)
    if not slot then
        slot = Mixin(CreateFrame("Frame"), ProfessionsReagentSlotMixin)
        slot.Name = slot:CreateFontString()
        slot.Button = CreateFrame("ItemButton", nil, slot)
    end
    slot.reagentSlotSchematic = schematic
    slot.loading = loading
    slot:Update()
    return slot
end

-- Text without its color codes.
local function StripColors(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The bank mark a reagent slot shows: "none", "icon", "count <n>" or
-- "line <text>" (the line under the name, without its color codes).
function world:ReagentMark(slot)
    local name = slot.Name:GetText()
    local line = name:match("\n(.*)$")
    if line then
        return "line " .. StripColors(line)
    end
    for _, frame in ipairs(self.frames) do
        if frame.parent == slot.Button and frame.shown then
            for _, texture in ipairs(self.textures) do
                if texture.owner == frame and texture.shown then
                    return "icon"
                end
            end
            for _, fontString in ipairs(self.fontStrings) do
                if fontString.owner == frame and fontString.shown then
                    return "count " .. fontString.text
                end
            end
        end
    end
    return "none"
end

-- Shows an item tooltip ({ guid, id }): the lines the post-calls added.
function world:ItemTooltip(data)
    local lines = {}
    local tooltip = {
        AddLine = function(_, text)
            table.insert(lines, StripColors(text))
        end,
    }
    for _, callback in ipairs(self.tooltipPostCalls) do
        callback(tooltip, data)
    end
    return lines
end

-- Bags: the combined bags frame fires Blizzard's OpenBag / CloseBag callbacks.
function world:OpenBags()
    if not ContainerFrameCombinedBags:IsShown() then
        ContainerFrameCombinedBags:Show()
        UpdateContainerFrameAnchors()
        EventRegistry:TriggerEvent("ContainerFrame.OpenBag", ContainerFrameCombinedBags)
    end
end

function world:CloseBags()
    if ContainerFrameCombinedBags:IsShown() then
        ContainerFrameCombinedBags:Hide()
        EventRegistry:TriggerEvent("ContainerFrame.CloseBag", ContainerFrameCombinedBags)
    end
end

-- Like the client: Blizzard's handler shows BankFrame, which opens the bags,
-- before addons see BANKFRAME_OPENED.
function world:OpenBank()
    self.bankOpen = true
    BankFrame:Show()
    self:OpenBags()
    self:Fire("BANKFRAME_OPENED")
end

function world:CloseBank()
    self.bankOpen = false
    BankFrame:Hide()
    self:CloseBags()
    self:Fire("BANKFRAME_CLOSED")
end

-- The player types in the bags' search box.
function world:SearchBags(text)
    BagItemSearchBox.text = text
    BagItemSearchBox:RunScript("OnTextChanged", true)
end

-- Saved Bank frames ---------------------------------------------------------------------

local function FindFrame(predicate)
    for _, frame in ipairs(world.frames) do
        if predicate(frame) then
            return frame
        end
    end
end

function world:SavedBank()
    return ForeverEnhancedSavedBankFrame
end

function world:IsSavedBankShown()
    local frame = self:SavedBank()
    return frame ~= nil and frame:IsShown()
end

-- The side tab on the bags.
function world:BankSideTab()
    return FindFrame(function(frame)
        return frame.template == "LargeSideTabButtonTemplate" and frame.parent ~= self:SavedBank()
    end)
end

function world:ClickSideTab(tab)
    tab.customMouseUpHandler(tab, "LeftButton", true)
end

local function FindTexture(owner, atlas)
    for _, texture in ipairs(world.textures) do
        if texture.owner == owner and texture.atlas == atlas then
            return texture
        end
    end
end

-- Shown item buttons of the saved bank: bank slots, or bank bag slots (bag background).
local function SavedBankButtons(isBag)
    local buttons = {}
    for _, frame in ipairs(world.frames) do
        if frame.frameType == "ItemButton" and frame.parent == world:SavedBank() and frame.shown then
            if (FindTexture(frame, "bank-frame-bag-slot-bg") ~= nil) == isBag then
                table.insert(buttons, frame)
            end
        end
    end
    return buttons
end

-- The saved bank's visible item slots: "B1 - B2(20) ~B3", "~" when dimmed by the search.
function world:SavedBankSlots()
    local slots = {}
    for _, button in ipairs(SavedBankButtons(false)) do
        local slot = button.icon and button.icon:gsub("^icon:", "") or "-"
        if button.count and button.count > 1 then
            slot = slot .. "(" .. button.count .. ")"
        end
        if button.matchesSearch == false then
            slot = "~" .. slot
        end
        table.insert(slots, slot)
    end
    return table.concat(slots, " ")
end

function world:SavedBankButton(index)
    return SavedBankButtons(false)[index]
end

-- The saved bank's bag slots: "GBAG -", "x" for a slot not purchased.
function world:SavedBankBags()
    local slots = {}
    for _, button in ipairs(SavedBankButtons(true)) do
        local slot = button.icon and button.icon:gsub("^icon:", "") or "-"
        table.insert(slots, FindTexture(button, "bankslot-icon-lock").shown and "x" or slot)
    end
    return table.concat(slots, " ")
end

-- Runs the character dropdown's menu generator: a list of
-- { kind = "radio" | "button" | "divider", text, isSelected(), select(), callback(), children }.
-- Menu descriptions record their entries: { kind = "radio" | "button" | "divider",
-- text, isSelected(), select(), callback(), enabled, children }.
local function NewMenuDescription()
    local description = { children = {}, enabled = true }
    function description:CreateRadio(text, isSelected, setSelected)
        local entry = { kind = "radio", text = text, isSelected = isSelected, select = setSelected }
        table.insert(self.children, entry)
        return entry
    end
    function description:CreateButton(text, callback)
        local entry = NewMenuDescription()
        entry.kind, entry.text, entry.callback = "button", text, callback
        table.insert(self.children, entry)
        return entry
    end
    function description:CreateDivider()
        table.insert(self.children, { kind = "divider" })
    end
    function description:SetEnabled(enabled)
        self.enabled = enabled
    end
    return description
end

-- Runs a menu generator: the list of its top-level entries.
local function RunMenuGenerator(owner, generator)
    local root = NewMenuDescription()
    generator(owner, root)
    return root.children
end

-- The saved bank's character dropdown menu.
function world:SavedBankMenu()
    local dropdown = FindFrame(function(frame)
        return frame.template == "WowStyle1DropdownTemplate"
    end)
    return RunMenuGenerator(dropdown, dropdown.menuGenerator)
end

-- Bank Transfers: the Deposit or Withdraw button on the bank frame.
function world:TransferButton(direction)
    return FindFrame(function(frame)
        return frame.template == "UIPanelButtonTemplate" and frame.text == self.L["inventory.transfers." .. direction]
    end)
end

-- Clicks the Deposit or Withdraw button: the entries of the menu it opens.
function world:TransferMenu(direction)
    local button = self:TransferButton(direction)
    button.scripts.OnClick(button, "LeftButton")
    return RunMenuGenerator(self.contextMenu.owner, self.contextMenu.generator)
end

-- Whether the saved bank shows this text.
function world:SavedBankShowsText(text)
    for _, fontString in ipairs(self.fontStrings) do
        if fontString.owner == self:SavedBank() and fontString.shown and fontString.text == text then
            return true
        end
    end
    return false
end

function world:SavedBankSearchBox()
    return FindFrame(function(frame)
        return frame.template == "SearchBoxTemplate"
    end)
end

-- Windows ------------------------------------------------------------------------------

-- Holds or releases "shift", "ctrl" or "alt".
function world:SetModifier(key, down)
    self[key] = down
end

-- Our drag handle on the frame's title bar, if one was ever created.
function world:TitleHandle(frame)
    return FindFrame(function(candidate)
        return candidate.parent == frame and candidate.scripts.OnDragStart ~= nil
    end)
end

-- Whether the player sees a drag handle on the frame's title bar.
function world:HasTitleHandle(frame)
    local handle = self:TitleHandle(frame)
    return handle ~= nil and handle.shown and frame:IsShown()
end

-- The player drags the frame's title bar and drops the frame at (x, y) from
-- UIParent's bottom left. Nothing happens without a visible handle.
function world:DragTitle(frame, x, y)
    if not self:HasTitleHandle(frame) then
        return
    end
    local handle = self:TitleHandle(frame)
    self.dropAt = { x = x, y = y }
    handle:RunScript("OnDragStart", "LeftButton")
    handle:RunScript("OnDragStop")
end

function world:ShiftRightClickTitle(frame)
    local handle = assert(self:TitleHandle(frame), "no title handle")
    self.shift = true
    handle:RunScript("OnClick", "RightButton")
    self.shift = false
end

-- Where the frame stands on screen: "left,bottom".
function world:Position(frame)
    local left, bottom = frame:GetBottomLeftCorner()
    return ("%s,%s"):format(left, bottom)
end

-- Opens the separate bags (bags not combined), the way the client lays them out.
function world:OpenSeparateBags()
    ContainerFrameCombinedBags:Hide()
    ContainerFrame1:Show()
    ContainerFrame2:Show()
    UpdateContainerFrameAnchors()
end

-- The frame's anchors: "TOPLEFT UIParent BOTTOMLEFT 300 400", joined with "; ".
function world:Anchor(frame)
    local parts = {}
    for index = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        local relativeName = relativeTo == UIParent and "UIParent" or tostring(relativeTo and relativeTo.name)
        table.insert(parts, ("%s %s %s %s %s"):format(point, relativeName, relativePoint, x, y))
    end
    return table.concat(parts, "; ")
end

return world
