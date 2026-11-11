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
-- incoming chat fires its event, shows a chat bubble and runs through the
-- registered chat filters (world:ReceiveChat). Like the client, bubbles are
-- reused once hidden, and forbidden to addons while world.bubblesForbidden (in
-- dungeons and raids).
-- At a merchant, the player has world.money and gear to repair for
-- world.repairCost; sold items are credited after SERVER_CONFIRM_SECONDS.
--
-- The character bank is two purchased tabs (containers 6 and 7, of
-- world.bagSizes slots) out of world.maxBankTabs, with a bag in tab 2's bank bag
-- slot. Like the client, bank contents only exist while the bank is open.
--
-- The player can target a unit (world.target, a GUID) that may have a
-- nameplate (world.namePlates). Like Forever, combo points are held per unit
-- (world.comboPoints, by GUID): a unit keeps its points when the player
-- targets another or builds points on another.
--
-- Console variables live in world.cvars. The soft interact target (what the
-- Interact Key would act on) is world.softInteract, picked from
-- world.nearbyObject while the soft target CVars allow it.
--
-- Slash commands are registered like in the client (SlashCmdList, SLASH_<KEY>n)
-- and run from world:Chat, which first imports them into hash_SlashCmdList.

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
    blockDrops = false,
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
    player = { guid = "Player-1-00000001", name = "Hylmew", class = "MAGE", realm = "Forever", level = 12 },
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
    chatBubbles = {},
    bubblesForbidden = false,
    target = nil,
    comboPoints = {},
    namePlates = {},
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
-- The format of item objectives: the French one is the game's ("%1$s :
-- %2$d/%3$d", modelled with a no-break space before the colon); the English
-- one matches the tracker's "3/10 Crispy Bat Wing".
QUEST_ITEMS_NEEDED = ({ enUS = "%2$d/%3$d %1$s", frFR = "%1$s\194\160: %2$d/%3$d" })[TEST_LOCALE]

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
    "SetTextColor",
    "HighlightText",
    "SetMaxLetters",
    "SetBlendMode",
    "SetIgnoreParentAlpha",
    "SetWordWrap",
    "SetFontObject",
    "SetColorTexture",
    "AddMaskTexture",
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

function Region:GetParent()
    return self.parent
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

function Region:SetAlpha(alpha)
    self.alpha = alpha
end

function Region:GetAlpha()
    return self.alpha or 1
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

-- Shown along with all its parents.
function Region:IsVisible()
    return self.shown and (self.parent == nil or self.parent:IsVisible())
end

function Region:SetScale(scale)
    self.scale = scale
end

function Region:GetEffectiveScale()
    local scale = self.scale or 1
    return self.parent and scale * self.parent:GetEffectiveScale() or scale
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

-- Nameplate regions can't be measured in combat (the client errors), nor
-- anything inside them.
local function CheckMeasurable(region)
    local ancestor = region
    while ancestor do
        assert(
            not (world.inCombat and ancestor.restrictedInCombat),
            "Action[FrameMeasurement] failed because[Can't measure restricted regions]"
        )
        ancestor = ancestor.parent or ancestor.owner
    end
end

-- A point's offset from the bottom left corner of a width x height rect.
local function PointOffset(point, width, height)
    local x = point:find("LEFT") and 0 or point:find("RIGHT") and width or width / 2
    local y = point:find("BOTTOM") and 0 or point:find("TOP") and height or height / 2
    return x, y
end

-- What a point fixes on each axis: "min", "max" or "center".
local function PointParts(point)
    local x = point:find("LEFT") and "min" or point:find("RIGHT") and "max" or "center"
    local y = point:find("BOTTOM") and "min" or point:find("TOP") and "max" or "center"
    return x, y
end

-- Start and size on one axis: two fixed parts give both, one takes the
-- region's own size.
local function SolveAxis(fixed, size)
    local min, max, center = fixed.min, fixed.max, fixed.center
    if min and max then
        return min, max - min
    elseif min and center then
        return min, 2 * (center - min)
    elseif max and center then
        return 2 * center - max, 2 * (max - center)
    elseif min then
        return min, size
    elseif max then
        return max - size, size
    end
    return center - size / 2, size
end

-- The region's rect on screen (left, bottom, width, height) from all its
-- anchors, like the client's layout (UIParent is the screen; scales aren't
-- applied). Fake only, and never restricted: for tests to look at.
function Region:GetScreenRect()
    if self == UIParent then
        return 0, 0, self.width, self.height
    end
    if self:GetNumPoints() == 0 then
        return nil
    end
    local xs, ys = {}, {}
    for _, anchor in ipairs(self.anchors) do
        local point, relativeTo, relativePoint, x, y = unpack(anchor, 1, 5)
        local relativeLeft, relativeBottom, relativeWidth, relativeHeight
        if relativeTo then
            relativeLeft, relativeBottom, relativeWidth, relativeHeight = relativeTo:GetScreenRect()
        end
        if not relativeLeft then
            return nil
        end
        local relativeX, relativeY = PointOffset(relativePoint, relativeWidth, relativeHeight)
        local xPart, yPart = PointParts(point)
        xs[xPart] = relativeLeft + relativeX + x
        ys[yPart] = relativeBottom + relativeY + y
    end
    local left, width = SolveAxis(xs, self.width or 0)
    local bottom, height = SolveAxis(ys, self.height or 0)
    return left, bottom, width, height
end

-- The size its anchors give it, or else the size it was given.
function Region:GetWidth()
    CheckMeasurable(self)
    return select(3, self:GetScreenRect()) or self.width or 0
end

function Region:GetHeight()
    CheckMeasurable(self)
    return select(4, self:GetScreenRect()) or self.height or 0
end

-- The region's bottom left corner on screen. Fake only, like GetScreenRect.
function Region:GetBottomLeftCorner()
    local left, bottom = self:GetScreenRect()
    return left, bottom
end

function Region:GetLeft()
    CheckMeasurable(self)
    return (self:GetScreenRect())
end

function Region:GetBottom()
    CheckMeasurable(self)
    return select(2, self:GetScreenRect())
end

function Region:GetRight()
    CheckMeasurable(self)
    local left, _, width = self:GetScreenRect()
    return left and left + width
end

function Region:GetTop()
    CheckMeasurable(self)
    local _, bottom, _, height = self:GetScreenRect()
    return bottom and bottom + height
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

function Region:GetTexture()
    return self.texture
end

function Region:GetAtlas()
    return self.atlas
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
    -- RogueComboPointMixin: `animated` tells whether the last change played the fill animation.
    RogueComboPointTemplate = function(frame)
        function frame:Setup()
            self.active = false
            self:Show()
        end
        function frame:SetActive(active)
            if self.active ~= active then
                self.active = active
                self.animated = true
            end
        end
        function frame:SetActiveNoAnimation(active)
            self.active = active
            self.animated = false
        end
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
    -- Like the client, several templates apply in order ("A, B").
    for each in (template or ""):gmatch("[^,%s]+") do
        assert(templates[each], "unknown template " .. each)(frame)
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

-- Console variables ------------------------------------------------------------
-- world.cvars holds string values by lower-case name: like the client, names
-- are case-insensitive, and only known CVars can be set. Setting one fires
-- CVAR_UPDATE at once (the client's handlers run synchronously), with the name
-- as given. world.combatCVarWrites lists the names set during combat.

world.cvars = {
    outlinemodeshowlooteffectwhendisabled = "0",
    graphicsquality = "5",
    softtargetinteract = "1",
    softtargetinteractrange = "10",
    softtargetinteractarc = "0",
    softtargetinteractonlyinrange = "1",
    softtargeticongameobject = "0",
    softtargeticoninteract = "1",
    softtargetnameplateinteract = "0",
}
world.combatCVarWrites = {}

C_CVar = {
    GetCVar = function(name)
        return world.cvars[name:lower()]
    end,
    SetCVar = function(name, value)
        local key = name:lower()
        assert(world.cvars[key], "unknown cvar " .. name)
        value = tostring(value)
        world.cvars[key] = value
        if world.inCombat then
            table.insert(world.combatCVarWrites, name)
        end
        world:Fire("CVAR_UPDATE", name, value)
        if key:find("^softtarget") then
            world:QueueSoftInteractRefresh()
        end
    end,
}

-- Settings panel -----------------------------------------------------------------

local Setting = {}
Setting.__index = Setting

function Setting:SetValueChangedCallback(callback)
    self.callback = callback
end

function Setting:GetValue()
    if self.getValue then
        return self.getValue()
    end
    return self.tbl[self.key]
end

function Setting:SetValue(value)
    if self.setValue then
        -- Like Blizzard's, a proxy is only written when the value differs.
        if self.getValue() ~= value then
            self.setValue(value)
        end
    else
        self.tbl[self.key] = value
    end
    if self.callback then
        self.callback(self, value)
    end
end

function Setting:GetDefaultValue()
    return self.default
end

local Initializer = {}
Initializer.__index = Initializer

-- Like Blizzard's, the parent is kept in `parentInitializer`, which the settings
-- search reads outside the rows' secure calls (a value an addon wrote there
-- taints it); rows read it through GetParentInitializer.
function Initializer:SetParentInitializer(parent, predicate)
    self.parentInitializer = parent
    if predicate then
        self:AddModifyPredicate(predicate)
    end
end

function Initializer:GetParentInitializer()
    return self.parentInitializer
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

local function NewSetting(variable, varType, fields)
    assert(not world.settings[variable], "duplicate setting variable " .. variable)
    assert(type(fields.name) == "string" and type(fields.default) == varType, "malformed setting " .. variable)
    local setting = setmetatable(fields, Setting)
    world.settings[variable] = setting
    return setting
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
        if tbl[key] == nil then
            tbl[key] = default
        end
        return NewSetting(variable, varType, { key = key, tbl = tbl, name = name, default = default })
    end,
    -- A setting over get/set functions instead of a saved table (e.g. the preset picker).
    RegisterProxySetting = function(_, variable, varType, name, default, getValue, setValue)
        return NewSetting(
            variable,
            varType,
            { name = name, default = default, getValue = getValue, setValue = setValue }
        )
    end,
    -- Blizzard's builders: rows with Blizzard's templates, whose frames its own pages reuse.
    CreateCheckbox = function(category, setting, tooltip)
        return AddInitializer(
            category,
            { template = "SettingsCheckboxControlTemplate", setting = setting, tooltip = tooltip }
        )
    end,
    CreateDropdown = function(category, setting, getOptions, tooltip)
        return AddInitializer(category, {
            template = "SettingsDropdownControlTemplate",
            setting = setting,
            tooltip = tooltip,
            options = getOptions(),
        })
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
        return AddInitializer(category, {
            template = "SettingsSliderControlTemplate",
            setting = setting,
            tooltip = tooltip,
            slider = sliderOptions,
        })
    end,
    -- A row with any template: created, then registered to the category. `options`
    -- is what the template's control reads: a function returning a dropdown's
    -- options (kept here as the options it returns), or a slider's options.
    CreateControlInitializer = function(template, setting, options, tooltip)
        assert(template, "missing template")
        local initializer = { template = template, setting = setting, tooltip = tooltip }
        if type(options) == "function" then
            initializer.options = options()
        elseif options then
            initializer.slider = options
        end
        return setmetatable(initializer, Initializer)
    end,
    CreateSettingInitializerData = function(setting, options, tooltip)
        return { setting = setting, name = setting.name, options = options or {}, tooltip = tooltip }
    end,
    CreateSettingInitializer = function(template, data)
        assert(template, "missing template")
        return setmetatable(
            { template = template, setting = data.setting, tooltip = data.tooltip, data = data },
            Initializer
        )
    end,
    -- A row without a setting (headers, buttons): `data` is what its template reads.
    CreateElementInitializer = function(template, data)
        assert(template, "missing template")
        return setmetatable(
            { template = template, header = data.name, tooltip = data.tooltip, data = data },
            Initializer
        )
    end,
    RegisterInitializer = function(category, initializer)
        table.insert(category.items, initializer)
    end,
    CreateControlTextContainer = function()
        local data = {}
        return {
            Add = function(_, value, label, tooltip)
                table.insert(data, { value = value, label = label, tooltip = tooltip })
            end,
            GetData = function()
                return data
            end,
        }
    end,
}

function CreateSettingsListSectionHeaderInitializer(name, tooltip)
    return { template = "SettingsListSectionHeaderTemplate", header = name, tooltip = tooltip }
end

-- Items, bags and cursor ------------------------------------------------------------

Enum = {
    SpellBookSpellBank = { Player = 0, Pet = 1 },
    SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
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
    PowerType = { ComboPoints = 4 },
    CraftingReagentType = { Optional = 0, Basic = 1, Finishing = 2 },
    QuestTag = { Group = 1, PvP = 41, Raid = 62, Dungeon = 81, Heroic = 85, Raid10 = 88, Raid25 = 89 },
    UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 },
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
    world.cursorAction = nil
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
        -- A drop the client blocks (ADDON_ACTION_BLOCKED): the item stays on the cursor.
        if world.blockDrops then
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
-- tagID (Enum.QuestTag, nil = untagged),
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
    -- Only the soft interact object is modelled (see Soft interact below).
    UnitIsRelatedToActiveQuest = function(unit)
        assert(unit == "softinteract", "only the soft interact object is modelled")
        return world.softInteract ~= nil and world.softInteract.quest == true
    end,
    GetNumQuestLogEntries = function()
        return #world.questLog, #world.questLog
    end,
    GetInfo = function(index)
        return world.questLog[index]
    end,
    IsWorldQuest = function(questID)
        return FindQuest(questID).isWorldQuest == true
    end,
    -- Nil for an untagged quest. The tag name stands in for the client's localized one.
    GetQuestTagInfo = function(questID)
        local quest = FindQuest(questID)
        if quest and quest.tagID then
            return { tagID = quest.tagID, tagName = tostring(quest.tagID) }
        end
    end,
    GetDistanceSqToQuest = function(questID)
        local quest = FindQuest(questID)
        if quest and quest.distance then
            return quest.distance * quest.distance, not quest.offContinent
        end
    end,
    -- Returns nothing while the client has no quest data for the map (seen
    -- after a zone change on a boat).
    GetQuestsOnMap = function()
        if world.mapQuestsUnavailable then
            return
        end
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
    -- Like the client, watch changes fire QUEST_WATCH_LIST_CHANGED synchronously,
    -- and a newly watched quest goes to the top of the list (measured in game).
    AddQuestWatch = function(questID)
        assert(not WatchIndex(questID), "quest already watched")
        assert(#world.watches < Constants.QuestWatchConsts.MAX_QUEST_WATCHES, "too many watches")
        table.insert(world.watches, 1, questID)
        world:Fire("QUEST_WATCH_LIST_CHANGED", questID, true)
        return true
    end,
    RemoveQuestWatch = function(questID)
        table.remove(world.watches, assert(WatchIndex(questID), "quest not watched"))
        world:Fire("QUEST_WATCH_LIST_CHANGED", questID, false)
        -- Blizzard's super tracking (Blizzard_QuestSuperTracking.lua) stops
        -- super-tracking a quest when it is untracked.
        if world.superTracked == questID then
            world.superTracked = 0
            world:Fire("SUPER_TRACKING_CHANGED")
        end
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

-- Bubbles shown with the player's chat bubble options.
C_ChatBubbles = {
    GetAllChatBubbles = function(includeForbidden)
        local bubbles = {}
        for _, bubble in ipairs(world.chatBubbles) do
            if includeForbidden or not bubble.forbidden then
                table.insert(bubbles, bubble)
            end
        end
        return bubbles
    end,
}

function GetTime()
    return world.now
end

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

function UnitLevel(unit)
    assert(unit == "player", "only the player is modelled")
    return world.player.level
end

function GetNormalizedRealmName()
    return world.player.realm
end

-- Target, combo points and nameplates ---------------------------------------------------

local COMBO_POINT_CLASSES = { ROGUE = true, DRUID = true }

function UnitPowerMax(unit, powerType)
    assert(unit == "player" and powerType == Enum.PowerType.ComboPoints, "only combo points are modelled")
    return COMBO_POINT_CLASSES[world.player.class] and 5 or 0
end

local function NamePlateToken(guid)
    for token, namePlate in pairs(world.namePlates) do
        if namePlate.guid == guid then
            return token
        end
    end
end

-- The shown nameplate of a nameplate token ("nameplate1"), or of the soft
-- interact object: nil while it has none, or when world.softInteractPlateByUnit
-- is false (then only its nameplate token finds it).
local function NamePlateOf(unit)
    if unit == "softinteract" then
        local object = world.softInteract
        local token = object and world.softInteractPlateByUnit ~= false and NamePlateToken(object.guid)
        return token and world.namePlates[token]
    end
    return assert(unit:match("^nameplate%d+$") and world.namePlates[unit], "unknown unit " .. unit)
end

function GetComboPoints(unit, target)
    assert(unit == "player", "only the player's points are modelled")
    return world.comboPoints[NamePlateOf(target).guid] or 0
end

C_NamePlate = {
    GetNamePlateForUnit = function(unit)
        local namePlate = NamePlateOf(unit)
        return namePlate and namePlate.frame
    end,
    GetNamePlates = function()
        local frames = {}
        for _, namePlate in pairs(world.namePlates) do
            table.insert(frames, namePlate.frame)
        end
        return frames
    end,
}

-- Soft interact -------------------------------------------------------------------------
-- world.nearbyObject: what the Interact Key would act on, set with
-- world:SoftInteract({ guid, gameObject (default true; false for an NPC),
-- cursor ("Mine", "GatherHerbs", "Quest", "LootAll", ...), unable (the cursor's
-- "Unable" variant: can't use it now), inRange, quest }) or nil.
-- Like the client, the game picks it as the "softinteract" unit
-- (world.softInteract) only while SoftTargetInteract allows the keyboard (2 or
-- 3), and gives it a nameplate while SoftTargetNameplateInteract is on (a world
-- object only with SoftTargetIconGameObject on too). The game picks again at
-- once when the player moves, and on the next frame after a soft target CVar
-- changes; nameplates follow on the next frame.

-- The soft interact object, or a nameplate's unit.
function UnitIsGameObject(unit)
    if unit == "softinteract" then
        return world.softInteract ~= nil and world.softInteract.gameObject
    end
    local namePlate = world.namePlates[unit]
    return namePlate ~= nil and namePlate.gameObject
end

function UnitIsInInteractRange(unit)
    assert(unit == "softinteract" and world.softInteract, "only the soft interact object is modelled")
    return world.softInteract.inRange == true
end

-- Cursor files have file IDs, like the client's (GetTexture returns the ID).
local fileIDs, fileCount = {}, 0
function GetFileIDFromPath(path)
    local key = path:lower()
    if not fileIDs[key] then
        fileCount = fileCount + 1
        fileIDs[key] = 100000 + fileCount
    end
    return fileIDs[key]
end

-- The cursor the object shows on mouseover: by file ID, or by atlas when
-- world.cursorAtlases is set ("Cursor_Crosshair_UnableMine_64"; then
-- GetTexture gives no cursor file).
function SetUnitCursorTexture(texture, unit)
    assert(unit == "softinteract", "only the soft interact object is modelled")
    local object = world.softInteract
    if not object then
        return false
    end
    local name = (object.unable and "Unable" or "") .. object.cursor
    if world.cursorAtlases then
        texture:SetTexture(nil)
        texture:SetAtlas("Cursor_Crosshair_" .. name .. "_64")
    else
        texture:SetTexture(GetFileIDFromPath("Interface\\Cursor\\" .. name))
    end
    return true
end

local function PickSoftInteract()
    local enabled = world.cvars.softtargetinteract == "2" or world.cvars.softtargetinteract == "3"
    local old, new = world.softInteract, enabled and world.nearbyObject or nil
    if old == new then
        return
    end
    if old and NamePlateToken(old.guid) then
        world:HideNamePlate(old.guid)
    end
    world.softInteract = new
    world:Fire("PLAYER_SOFT_INTERACT_CHANGED", old and old.guid, new and new.guid)
end

local function UpdateSoftInteractNamePlate()
    local object = world.softInteract
    local shown = object and NamePlateToken(object.guid)
    local wanted = object ~= nil
        and world.cvars.softtargetnameplateinteract ~= "0"
        and (not object.gameObject or world.cvars.softtargeticongameobject ~= "0")
    if wanted and not shown then
        world:ShowNamePlate(object.guid, object.gameObject)
    elseif shown and not wanted then
        world:HideNamePlate(object.guid)
    end
end

local softInteractRefreshQueued = false
function world:QueueSoftInteractRefresh()
    if softInteractRefreshQueued then
        return
    end
    softInteractRefreshQueued = true
    table.insert(self.nextFrameCallbacks, function()
        softInteractRefreshQueued = false
        PickSoftInteract()
        UpdateSoftInteractNamePlate()
    end)
end

local objectCount = 0
function world:SoftInteract(object)
    if object then
        objectCount = objectCount + 1
        object.guid = object.guid or ("GameObject-0-" .. objectCount)
        object.gameObject = object.gameObject ~= false
    end
    self.nearbyObject = object
    PickSoftInteract()
    self:QueueSoftInteractRefresh()
end

C_SuperTrack = {
    GetSuperTrackedQuestID = function()
        return world.superTracked
    end,
    SetSuperTrackedQuestID = function(questID)
        world.superTracked = questID
        world:Fire("SUPER_TRACKING_CHANGED")
    end,
    SetSuperTrackedUserWaypoint = function(superTracked)
        world.superTrackingWaypoint = superTracked
    end,
    IsSuperTrackingUserWaypoint = function()
        return world.superTrackingWaypoint == true
    end,
}

-- Maps are MAP_SIZE yards squares whose top left corner is the world origin of
-- their continent: map 1 is on continent 0, map 2 on continent 1.
local MAP_SIZE = 1000
local MAP_CONTINENTS = { [1] = 0, [2] = 1 }

-- The map tree under Azeroth (9): a zone on each continent, a dungeon, which
-- can't hold a pin, and Northshire, a starting area inside Elwynn Forest with its
-- own map. The player is on map 1 or 2 by continent, on 4 inside NORTHSHIRE (yards
-- on continent 0) and on 3 in an instance.
local MAPS = {
    [1] = { name = "Elwynn Forest", mapType = Enum.UIMapType.Zone, parentMapID = 10 },
    [2] = { name = "Durotar", mapType = Enum.UIMapType.Zone, parentMapID = 11 },
    [3] = { name = "The Deadmines", mapType = Enum.UIMapType.Dungeon, parentMapID = 1 },
    [4] = { name = "Northshire", mapType = Enum.UIMapType.Micro, parentMapID = 1 },
    [9] = { name = "Azeroth", mapType = Enum.UIMapType.World, parentMapID = 0 },
    [10] = { name = "Eastern Kingdoms", mapType = Enum.UIMapType.Continent, parentMapID = 9 },
    [11] = { name = "Kalimdor", mapType = Enum.UIMapType.Continent, parentMapID = 9 },
}

local NORTHSHIRE = { left = 800, top = 0, size = 200 }

local function InNorthshire(position)
    return not position.instanceID
        and position.continentID == 0
        and position.x >= NORTHSHIRE.left
        and position.x < NORTHSHIRE.left + NORTHSHIRE.size
        and position.y >= NORTHSHIRE.top
        and position.y < NORTHSHIRE.top + NORTHSHIRE.size
end

local function GetMapInfo(uiMapID)
    local map = MAPS[uiMapID]
    if map then
        return { mapID = uiMapID, name = map.name, mapType = map.mapType, parentMapID = map.parentMapID }
    end
end

local function IsDescendant(uiMapID, ancestorID)
    local parentID = MAPS[uiMapID].parentMapID
    while parentID ~= 0 do
        if parentID == ancestorID then
            return true
        end
        parentID = MAPS[parentID].parentMapID
    end
    return false
end

-- Every instance is a 5-player dungeon on map 3. Outside one, the client
-- names the continent.
function IsInInstance()
    if world.position.instanceID then
        return true, "party"
    end
    return false, "none"
end

function GetInstanceInfo()
    local position = world.position
    if position.instanceID then
        return MAPS[3].name, "party", 1, "Normal", 5, 0, false, position.instanceID
    end
    local continent = position.continentID == 1 and MAPS[11] or MAPS[10]
    return continent.name, "none", 0, "", 0, 0, false, position.continentID
end

C_Map = {
    GetBestMapForUnit = function()
        local position = world.position
        if position.instanceID then
            return 3
        end
        if InNorthshire(position) then
            return 4
        end
        return position.continentID == 1 and 2 or 1
    end,
    GetMapInfo = GetMapInfo,
    -- Sorted by map ID; direct children only unless allDescendants.
    GetMapChildrenInfo = function(uiMapID, mapType, allDescendants)
        local children = {}
        for childID, map in pairs(MAPS) do
            local related = map.parentMapID == uiMapID or (allDescendants and IsDescendant(childID, uiMapID))
            if related and (mapType == nil or map.mapType == mapType) then
                table.insert(children, GetMapInfo(childID))
            end
        end
        table.sort(children, function(a, b)
            return a.mapID < b.mapID
        end)
        return children
    end,
    CanSetUserWaypointOnMap = function(uiMapID)
        return MAPS[uiMapID] ~= nil and MAPS[uiMapID].mapType ~= Enum.UIMapType.Dungeon
    end,
    -- Nil off the player's continent and in an instance, like the client.
    GetPlayerMapPosition = function(uiMapID, unit)
        assert(unit == "player", "only the player is modelled")
        local position = world.position
        if not position.instanceID and MAP_CONTINENTS[uiMapID] == position.continentID then
            return { x = position.x / MAP_SIZE, y = position.y / MAP_SIZE }
        end
        if uiMapID == 4 and InNorthshire(position) then
            return {
                x = (position.x - NORTHSHIRE.left) / NORTHSHIRE.size,
                y = (position.y - NORTHSHIRE.top) / NORTHSHIRE.size,
            }
        end
    end,
    SetUserWaypoint = function(point)
        world.waypoint = point
        world:Fire("USER_WAYPOINT_UPDATED")
        return true
    end,
    ClearUserWaypoint = function()
        world.waypoint = nil
        world.superTrackingWaypoint = false
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

UiMapPoint = {
    CreateFromCoordinates = function(uiMapID, x, y)
        return { uiMapID = uiMapID, position = { x = x, y = y } }
    end,
}

MAP_PIN_INVALID_MAP = "Map pins can't be placed on this map."

function IsInInstance()
    if world.position.instanceID then
        return true, "party"
    end
    return false, "none"
end

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

-- Friends and addon messages -------------------------------------------------------------
-- world.friends: character friends { guid, name, className, connected } (name
-- without the realm for the player's realm, like the client; className
-- localized, as LocalizedClassList gives it). world.bnetFriends: Battle.net
-- friends, each a list of game accounts { gameAccountID, playerGuid, isOnline,
-- clientProgram, wowProjectID, characterName, classFilename }.
-- world.players[guid] = { name, realm, class } answers GetPlayerInfoByGUID (the
-- client's cache of players met this session), and world.groupGUIDs[guid] puts
-- one in the group.
--
-- Sent addon messages go to world.sentAddon ({ prefix, message, chatType,
-- target } for whispers, { prefix, message, gameAccountID } for Battle.net).
-- The client allows ADDON_MESSAGE_BURST messages per prefix, then one per
-- second, and returns AddonMessageThrottle past that.

local ADDON_MESSAGE_BURST = 10

world.friends = {}
world.bnetFriends = {}
world.players = {}
world.groupGUIDs = {}
world.sentAddon = {}
world.addonPrefixes = {}
world.addonAllowance = {}

BNET_CLIENT_WOW = "WoW"
WOW_PROJECT_ID = 16

Enum.SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 }

function GetTime()
    return world.now
end

-- The client's strsplit: splits on any character of `delimiters`, into at most
-- `pieces` parts (the last keeps the rest).
function strsplit(delimiters, text, pieces)
    local parts = {}
    local start = 1
    local pattern = "[" .. delimiters:gsub("%p", "%%%0") .. "]"
    while not pieces or #parts < pieces - 1 do
        local from, to = text:find(pattern, start)
        if not from then
            break
        end
        table.insert(parts, text:sub(start, from - 1))
        start = to + 1
    end
    table.insert(parts, text:sub(start))
    return table.unpack(parts)
end

function CreateVector2D(x, y)
    return { x = x, y = y }
end

function CreateFromMixins(...)
    return Mixin({}, ...)
end

local function SpendAllowance(prefix)
    local allowance = world.addonAllowance[prefix] or { tokens = ADDON_MESSAGE_BURST, at = world.now }
    allowance.tokens = math.min(ADDON_MESSAGE_BURST, allowance.tokens + (world.now - allowance.at))
    allowance.at = world.now
    world.addonAllowance[prefix] = allowance
    if allowance.tokens < 1 then
        return false
    end
    allowance.tokens = allowance.tokens - 1
    return true
end

local function SendAddon(prefix, record)
    assert(world.addonPrefixes[prefix], "unregistered prefix " .. prefix)
    assert(#record.message <= 255, "addon message too long")
    if not SpendAllowance(prefix) then
        return Enum.SendAddonMessageResult.AddonMessageThrottle
    end
    record.prefix = prefix
    table.insert(world.sentAddon, record)
    return Enum.SendAddonMessageResult.Success
end

C_ChatInfo.RegisterAddonMessagePrefix = function(prefix)
    assert(#prefix <= 16, "prefix too long")
    world.addonPrefixes[prefix] = true
    return true
end

C_ChatInfo.SendAddonMessage = function(prefix, message, chatType, target)
    assert(chatType == "WHISPER" and target, "only whispers are modelled")
    return SendAddon(prefix, { message = message, chatType = chatType, target = target })
end

C_FriendList = {
    GetNumFriends = function()
        return #world.friends
    end,
    GetFriendInfoByIndex = function(index)
        local friend = world.friends[index]
        if friend then
            return {
                name = friend.name,
                guid = friend.guid,
                className = friend.className,
                connected = friend.connected ~= false,
            }
        end
    end,
}

function BNGetNumFriends()
    local online = 0
    for _, accounts in ipairs(world.bnetFriends) do
        for _, account in ipairs(accounts) do
            if account.isOnline ~= false then
                online = online + 1
                break
            end
        end
    end
    return #world.bnetFriends, online
end

C_BattleNet = {
    GetFriendNumGameAccounts = function(friendIndex)
        return #world.bnetFriends[friendIndex]
    end,
    GetFriendGameAccountInfo = function(friendIndex, accountIndex)
        local account = world.bnetFriends[friendIndex][accountIndex]
        if account then
            return {
                gameAccountID = account.gameAccountID,
                playerGuid = account.playerGuid,
                isOnline = account.isOnline ~= false,
                clientProgram = account.clientProgram or BNET_CLIENT_WOW,
                wowProjectID = account.wowProjectID or WOW_PROJECT_ID,
                characterName = account.characterName,
                classFilename = account.classFilename,
            }
        end
    end,
    SendGameData = function(gameAccountID, prefix, data)
        return SendAddon(prefix, { message = data, gameAccountID = gameAccountID })
    end,
}

C_PartyInfo = {
    IsGUIDInGroup = function(guid)
        return world.groupGUIDs[guid] == true
    end,
}

function LocalizedClassList(isFemale)
    if isFemale then
        return { MAGE = "Magicienne", WARRIOR = "Guerrière" }
    end
    return { MAGE = "Mage", WARRIOR = "Guerrier" }
end

function GetPlayerInfoByGUID(guid)
    local player = world.players[guid]
    if player then
        return player.class:lower(), player.class, "Human", "Human", 2, player.name, player.realm
    end
end

-- World map ----------------------------------------------------------------------------------
-- WorldMapFrame is a map canvas showing WorldMapFrame.mapID. Like the canvas, it
-- refreshes its data providers when it opens, before their OnShow, and calls
-- their OnMapChanged when the shown map changes. Pins come from frame
-- templates, pooled per template; a new pin gets OnLoad from the canvas.

MapCanvasDataProviderMixin = {
    OnAdded = function(self, map)
        self.owningMap = map
    end,
    OnRemoved = function(self, map)
        assert(map == self.owningMap, "removed from another map")
        self.owningMap = nil
    end,
    RemoveAllData = NoOp,
    RefreshAllData = NoOp,
    OnShow = NoOp,
    OnHide = NoOp,
    GetMap = function(self)
        return self.owningMap
    end,
    OnMapChanged = function(self)
        self:RefreshAllData()
    end,
}

MapCanvasPinMixin = {
    OnLoad = NoOp,
    OnAcquired = NoOp,
    UseFrameLevelType = NoOp,
    SetScalingLimits = NoOp,
    SetPosition = function(self, x, y)
        self.position = { x = x, y = y }
    end,
}

templates.ForeverEnhancedFriendPinTemplate = function(frame)
    frame.Dot = frame:CreateTexture()
    Mixin(frame, ForeverEnhanced:GetFeature("map", "friends").Map.PinMixin)
end

WorldMapFrame = CreateFrame("Frame")
WorldMapFrame.shown = false
WorldMapFrame.dataProviders = {}
WorldMapFrame.pins = {}
WorldMapFrame.freePins = {}

function WorldMapFrame:AddDataProvider(provider)
    self.dataProviders[provider] = true
    provider:OnAdded(self)
end

function WorldMapFrame:RemoveDataProvider(provider)
    provider:RemoveAllData()
    self.dataProviders[provider] = nil
    provider:OnRemoved(self)
end

function WorldMapFrame:GetMapID()
    return self.mapID
end

function WorldMapFrame:AcquirePin(template, ...)
    self.freePins[template] = self.freePins[template] or {}
    local pin = table.remove(self.freePins[template])
    if not pin then
        pin = CreateFrame("Frame", nil, self, template)
        pin:OnLoad()
    end
    pin:Show()
    pin:OnAcquired(...)
    table.insert(self.pins, pin)
    return pin
end

function WorldMapFrame:RemoveAllPinsByTemplate(template)
    for index = #self.pins, 1, -1 do
        local pin = self.pins[index]
        if pin.template == template then
            table.remove(self.pins, index)
            pin:Hide()
            table.insert(self.freePins[template], pin)
        end
    end
end

WorldMapFrame:SetScript("OnShow", function(self)
    for provider in pairs(self.dataProviders) do
        provider:RefreshAllData(true)
    end
    for provider in pairs(self.dataProviders) do
        provider:OnShow()
    end
end)

WorldMapFrame:SetScript("OnHide", function(self)
    for provider in pairs(self.dataProviders) do
        provider:OnHide()
    end
end)

-- The map position of a world position (yards on a continent), like the
-- client: outside 0..1 when it's off the map, nil when the map is elsewhere.
C_Map.GetMapPosFromWorldPos = function(continentID, worldPosition, uiMapID)
    if MAP_CONTINENTS[uiMapID] == continentID then
        return uiMapID, { x = worldPosition.x / MAP_SIZE, y = worldPosition.y / MAP_SIZE }
    end
    if uiMapID == 4 and continentID == 0 then
        return uiMapID,
            {
                x = (worldPosition.x - NORTHSHIRE.left) / NORTHSHIRE.size,
                y = (worldPosition.y - NORTHSHIRE.top) / NORTHSHIRE.size,
            }
    end
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
        world.tooltipLines = {}
    end,
    AddLine = function(_, text)
        table.insert(world.tooltipLines, text)
    end,
    Show = NoOp,
    Hide = NoOp,
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

SOUNDKIT = setmetatable({}, {
    __index = function(_, name)
        return name
    end,
})

PlaySound = NoOp

-- Slash commands, as in the client: addons fill SlashCmdList and SLASH_<KEY>n, and
-- every chat line moves them into hash_SlashCmdList (keyed by the uppercase
-- command) and into the proxy table behind SlashCmdList.
SlashCmdList = setmetatable({}, { __index = {} })
hash_SlashCmdList = {}
hash_ChatTypeInfoList = {}

local function ImportSlashCommands()
    local proxy = getmetatable(SlashCmdList).__index
    for key, handler in pairs(SlashCmdList) do
        local i = 1
        local tag = _G["SLASH_" .. key .. i]
        while tag do
            hash_SlashCmdList[tag:upper()] = handler
            hash_ChatTypeInfoList[tag:upper()] = key
            i = i + 1
            tag = _G["SLASH_" .. key .. i]
        end
        proxy[key] = handler
    end
    wipe(SlashCmdList)
end

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

ACCEPT = "Accept"
CANCEL = "Cancel"

function strtrim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Named dialogs (StaticPopupDialogs): the last one shown is world.dialog. Its
-- edit box, when it has one, is a child EditBox; OnShow runs once shown, like the client.
StaticPopupDialogs = {}

function StaticPopup_Show(which, textArg1, textArg2, data)
    local info = assert(StaticPopupDialogs[which], "Dialog " .. which .. " does not exist.")
    local dialog = NewRegion({ frameType = "Frame", which = which, info = info, data = data })
    dialog.text = info.text:format(textArg1, textArg2)
    if info.hasEditBox then
        local editBox = NewRegion({ frameType = "EditBox", parent = dialog })
        function dialog.GetEditBox()
            return editBox
        end
    end
    world.dialog = dialog
    if info.OnShow then
        info.OnShow(dialog, data)
    end
    return dialog
end

function StaticPopup_StandardEditBoxOnEscapePressed(editBox)
    editBox:GetParent():Hide()
end

function StaticPopup_Hide(which)
    table.insert(world.hiddenPopups, which)
    if world.dialog and world.dialog.which == which then
        world.dialog:Hide()
    end
end

-- Records the popup data ({ text, text_arg1, text_arg2, callback }); tests accept it by calling callback.
function StaticPopup_ShowCustomGenericConfirmation(data)
    table.insert(world.popups, data)
end

function ReloadUI()
    world.reloaded = true
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

-- Runs the callbacks queued for the next frame, then the OnUpdate scripts of visible frames.
function world:NextFrame()
    local callbacks = self.nextFrameCallbacks
    self.nextFrameCallbacks = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end
    for _, frame in ipairs(self.frames) do
        if frame.scripts.OnUpdate and frame:IsVisible() then
            frame.scripts.OnUpdate(frame, 0)
        end
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

-- Like the client, PLAYER_REGEN_DISABLED fires just before the combat lockdown starts.
function world:EnterCombat()
    self:Fire("PLAYER_REGEN_DISABLED")
    self.inCombat = true
end

function world:LeaveCombat()
    self.inCombat = false
    self:Fire("PLAYER_REGEN_ENABLED")
end

-- Tickers still running, every feature's.
function world:TickerCount()
    local count = 0
    for _, timer in ipairs(self.timers) do
        if timer.interval and not timer.cancelled then
            count = count + 1
        end
    end
    return count
end

function world:Setting(path)
    return assert(self.settings["ForeverEnhanced." .. path], "no setting " .. path)
end

-- The settings panel's button row labeled `label`: its initializer (`data.buttonClick`,
-- `predicate`) and the category it's on.
-- The checkbox labeled `label` that has a button beside it.
function world:SettingsButton(label)
    for _, category in ipairs(self.categories) do
        for _, item in ipairs(category.items) do
            if item.data and item.data.OnButtonClick and item.data.name == label then
                return item, category
            end
        end
    end
    error("no settings button " .. tostring(label))
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

function world:AltRightClick(slot)
    self:SetAlt(true)
    self:ClickShield(slot, "RightButton")
    self:SetAlt(false)
end

-- The shown dialog (StaticPopup_Show), or nil.
function world:Dialog()
    local dialog = self.dialog
    return dialog and dialog.shown and dialog or nil
end

local function ShownDialog()
    return assert(world:Dialog(), "no dialog shown")
end

-- Replaces the text of the dialog's edit box, as the player typing.
function world:TypeInDialog(text)
    ShownDialog():GetEditBox().text = text
end

-- Enter in the dialog's edit box.
function world:PressEnterInDialog()
    local dialog = ShownDialog()
    dialog.info.EditBoxOnEnterPressed(dialog:GetEditBox(), dialog.data)
end

-- Clicks the dialog's first (accept) or second (cancel) button; both hide it.
function world:ClickDialogButton(index)
    local dialog = ShownDialog()
    local handler = index == 1 and dialog.info.OnAccept or dialog.info.OnCancel
    if handler then
        handler(dialog, dialog.data)
    end
    dialog:Hide()
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

-- An objective's text as the client words it, from QUEST_ITEMS_NEEDED: "3/10
-- Crispy Bat Wing", "Steak de loup : 3/10". WoW's format takes positional
-- arguments ("%2$d"), Lua's doesn't: substitute them here.
local function ObjectiveText(name, numFulfilled, numRequired)
    local args, nextArg = { name, numFulfilled, numRequired }, 0
    return (
        QUEST_ITEMS_NEEDED:gsub("%%(%d*)%$?[sd]", function(position)
            nextArg = nextArg + 1
            return tostring(args[tonumber(position) or nextArg])
        end)
    )
end

-- Objective `index` of a quest now has `numFulfilled` (and the objective text
-- `text`, if given; it stays in sync with the count otherwise), then the
-- client fires QUEST_LOG_UPDATE.
function world:Progress(questID, index, numFulfilled, text)
    local objective = FindQuest(questID).objectives[index]
    if not text and objective.name then
        text = ObjectiveText(objective.name, numFulfilled, objective.numRequired)
    end
    objective.numFulfilled = numFulfilled
    objective.finished = numFulfilled >= objective.numRequired
    objective.text = text or objective.text
    self:Fire("QUEST_LOG_UPDATE")
end

-- A counted objective, like the client's: "0/8 Kobold Vermin slain" ("Kobold
-- Vermin slain : 0/8" in French). `type` is the client's objective type
-- ("item", "monster", "object"...), "item" by default.
function world:Objective(name, numRequired, numFulfilled, type)
    numFulfilled = numFulfilled or 0
    return {
        name = name,
        type = type or "item",
        text = ObjectiveText(name, numFulfilled, numRequired),
        finished = numFulfilled >= numRequired,
        numFulfilled = numFulfilled,
        numRequired = numRequired,
    }
end

-- The player sends `text` from the chat edit box. Returns false when it names no
-- slash command (the client then prints its help hint).
function world:Chat(text)
    local command, message = text:match("^(/%S+)%s*(.-)$")
    ImportSlashCommands()
    local handler = hash_SlashCmdList[command:upper()]
    if not handler then
        return false
    end
    handler(strtrim(message))
    return true
end

-- A group chat message from `author` ("Name-Realm"); true when a filter hid it.
function world:ReceiveChat(event, message, author)
    self:Fire(event, message, author)
    self:ShowChatBubble(message)
    for _, filter in ipairs(self.chatFilters[event] or {}) do
        if filter(DEFAULT_CHAT_FRAME, event, message, author) then
            return true
        end
    end
    return false
end

-- Shows `message` in a chat bubble (a ChatBubbleTemplate under the client's
-- frame), reusing a hidden one like the client.
function world:ShowChatBubble(message)
    local bubble
    for _, candidate in ipairs(self.chatBubbles) do
        if not candidate:IsShown() and candidate.forbidden == self.bubblesForbidden then
            bubble = candidate
            break
        end
    end
    if not bubble then
        bubble = CreateFrame("Frame")
        bubble.forbidden = self.bubblesForbidden
        local content = CreateFrame("Frame", nil, bubble)
        content.String = content:CreateFontString()
        function bubble:GetChildren()
            return content
        end
        table.insert(self.chatBubbles, bubble)
    end
    bubble:GetChildren().String:SetText(message)
    bubble:Show()
end

-- Hides every bubble, as when their messages time out.
function world:ExpireChatBubbles()
    for _, bubble in ipairs(self.chatBubbles) do
        bubble:Hide()
    end
end

-- Whether the player sees a bubble with this text.
function world:IsChatBubbleVisible(message)
    for _, bubble in ipairs(self.chatBubbles) do
        local content = bubble:GetChildren()
        if bubble:IsShown() and content.String:GetText() == message and content:GetAlpha() > 0 then
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

-- Watched quest IDs in watch list order, the order the tracker shows: "4 1 3".
function world:WatchOrder()
    return table.concat(self.watches, " ")
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
    description.SetScrollMode = NoOp
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

-- The entries of the last context menu opened.
function world:ContextMenu()
    return RunMenuGenerator(self.contextMenu.owner, self.contextMenu.generator)
end

-- Bank transfers: the Deposit or Withdraw button on the bank frame.
function world:TransferButton(direction)
    return FindFrame(function(frame)
        return frame.template == "UIPanelButtonTemplate"
            and frame.text == self.L["inventory.bank.transfers." .. direction]
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

function world:Target(guid)
    self.target = guid
    self:Fire("PLAYER_TARGET_CHANGED")
end

-- Builds or spends points on the target; other units keep theirs.
function world:SetComboPoints(count)
    assert(self.target, "no target")
    self.comboPoints[self.target] = count > 0 and count or nil
    self:Fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

-- Plate frames are recycled, like the client's: a removed plate's frame is the
-- next one shown.
local freeNamePlates = {}
local namePlateCount = 0

world.CAST_BARS_HEIGHT = 10
world.CAST_BAR_SPACING = 2
world.HIGHLIGHT_OVERFLOW = 4

-- The unit frame stacks, from the bottom: the cast bar area (its cast bar
-- hidden until the unit casts), then the health bar, narrower to leave room
-- for the level badge on its right. Like the client's, its regions can't be
-- measured in combat.
local function NewNamePlate()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame.restrictedInCombat = true
    frame:SetSize(120, 40)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    local unitFrame = CreateFrame("Button", nil, frame)
    unitFrame:SetSize(120, 40)
    unitFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    local castBars = CreateFrame("Frame", nil, unitFrame)
    castBars:SetSize(120, world.CAST_BARS_HEIGHT)
    castBars:SetPoint("BOTTOMLEFT", unitFrame, "BOTTOMLEFT", 0, 0)
    castBars.castBar = CreateFrame("StatusBar", nil, castBars)
    castBars.castBar:Hide()
    local healthBars = CreateFrame("Frame", nil, unitFrame)
    healthBars:SetSize(96, 12)
    healthBars:SetPoint("BOTTOMLEFT", castBars, "TOPLEFT", 0, world.CAST_BAR_SPACING)
    -- The target highlight around the health bar's border, past its frame.
    healthBars.healthBar = CreateFrame("StatusBar", nil, healthBars)
    local highlight = healthBars.healthBar:CreateTexture()
    highlight:SetSize(96 + 2 * world.HIGHLIGHT_OVERFLOW, 12 + 2 * world.HIGHLIGHT_OVERFLOW)
    highlight:SetPoint("CENTER", healthBars, "CENTER", 0, 0)
    healthBars.healthBar.selectedBorder = highlight
    unitFrame.CastBarsContainer = castBars
    unitFrame.HealthBarsContainer = healthBars
    frame.UnitFrame = unitFrame
    -- NamePlateBaseMixin
    function frame:GetUnit()
        return self.unitToken
    end
    return frame
end

-- `gameObject`: the plate of a world object (the soft interact one).
function world:ShowNamePlate(guid, gameObject)
    namePlateCount = namePlateCount + 1
    local frame = table.remove(freeNamePlates) or NewNamePlate()
    local token = "nameplate" .. namePlateCount
    frame.unitToken = token
    self.namePlates[token] = { guid = guid, frame = frame, gameObject = gameObject == true }
    self:Fire("NAME_PLATE_UNIT_ADDED", token)
    return frame
end

function world:HideNamePlate(guid)
    local token = assert(NamePlateToken(guid), "no nameplate for " .. guid)
    self:Fire("NAME_PLATE_UNIT_REMOVED", token)
    local frame = self.namePlates[token].frame
    frame.unitToken = nil
    table.insert(freeNamePlates, frame)
    self.namePlates[token] = nil
end

-- Shows or hides the cast bar on the unit's plate, picked up on the next frame.
function world:SetCasting(guid, casting)
    local frame = assert(self.namePlates[NamePlateToken(guid)], "no nameplate for " .. guid).frame
    frame.UnitFrame.CastBarsContainer.castBar:SetShown(casting)
    self:NextFrame()
end

-- The shown combo point bars: frames holding RogueComboPointTemplate points.
local function ComboPointBars()
    local bars, seen = {}, {}
    for _, frame in ipairs(world.frames) do
        local bar = frame.template == "RogueComboPointTemplate" and frame.parent
        if bar and bar.shown and not seen[bar] then
            seen[bar] = true
            table.insert(bars, bar)
        end
    end
    return bars
end

-- How many combo point bars are shown, on any plate.
function world:ComboPointBarCount()
    return #ComboPointBars()
end

-- The combo point bar on the plate, or nil when it has none:
-- { slots (points shown), active (points filled), animated (the last change
-- played the fill animation) }, and the bar's frame.
function world:ComboPoints(plate)
    local bar
    for _, candidate in ipairs(ComboPointBars()) do
        if candidate.parent == plate then
            assert(not bar, "two combo point bars on one plate")
            bar = candidate
        end
    end
    if not bar then
        return nil
    end
    local state = { slots = 0, active = 0, animated = false }
    for _, frame in ipairs(self.frames) do
        if frame.template == "RogueComboPointTemplate" and frame.parent == bar and frame.shown then
            state.slots = state.slots + 1
            if frame.active then
                state.active = state.active + 1
            end
            state.animated = state.animated or frame.animated
        end
    end
    return state, bar
end

-- Opens the world map on uiMapID (the player's map by default).
function world:OpenMap(uiMapID)
    WorldMapFrame.mapID = uiMapID or C_Map.GetBestMapForUnit("player")
    WorldMapFrame:Show()
end

-- Switches the open map to uiMapID.
function world:ShowMap(uiMapID)
    WorldMapFrame.mapID = uiMapID
    for provider in pairs(WorldMapFrame.dataProviders) do
        provider:OnMapChanged()
    end
end

function world:CloseMap()
    WorldMapFrame:Hide()
end

-- The friend pins on the map: { guid, x, y }, sorted by GUID.
function world:FriendPins()
    local pins = {}
    for _, pin in ipairs(WorldMapFrame.pins) do
        if pin.template == "ForeverEnhancedFriendPinTemplate" then
            table.insert(pins, { guid = pin.guid, x = pin.position.x, y = pin.position.y, frame = pin })
        end
    end
    table.sort(pins, function(a, b)
        return a.guid < b.guid
    end)
    return pins
end

-- The prefix of the addon's own friends protocol, the default of the two below.
local FRIENDS_PREFIX = "FEFriends"

-- An addon message whispered by `sender` ("Name-Realm"), on the addon's prefix by default.
function world:ReceiveWhisperAddon(message, sender, prefix)
    self:Fire("CHAT_MSG_ADDON", prefix or FRIENDS_PREFIX, message, "WHISPER", sender, "", 0, 0, "", 0)
end

-- Battle.net game data from the friend playing on `gameAccountID`.
function world:ReceiveGameData(message, gameAccountID, prefix)
    self:Fire("BN_CHAT_MSG_ADDON", prefix or FRIENDS_PREFIX, message, "WHISPER", gameAccountID)
end

-- Secure frames, action bars and casting ---------------------------------------------------
-- Frames made from secure templates are protected: in combat, insecure code
-- can't show, hide or set attributes on them, nor change bindings or state
-- drivers (the client blocks the action). Restricted snippets (secure
-- handlers) can, and run in a small environment through frame handles.
--
-- The action bar is world.actionBar: { page (1-6), bonus (0, or the stance's
-- bonus bar, 1 for Stealth), vehicle }. Blizzard's main bar buttons
-- (ActionButton1-12) show slot (page - 1) * 12 + i, or the bonus bar's on page
-- 1; MultiBarBottomLeft shows slots 61-72. world.actions[slot] is the spell ID
-- in a slot. world.bindings maps keys to binding commands; override bindings
-- (world.overrides) take precedence, priority ones first.
--
-- Spells (world.spells, by ID, ranks pointing to their `base`) are cast by name
-- (the client casts the highest rank). A cast fails with UI_ERROR_MESSAGE when
-- the spell isn't usable (world.unusableSpells, world.noPowerSpells, by base
-- ID) or during the global cooldown (GLOBAL_COOLDOWN seconds after a cast).
-- Like the client, a refused cast reports its error at once. world.casts lists
-- the names cast; world.uiErrors the errors UIErrorsFrame showed.

local GLOBAL_COOLDOWN = 1.5
local NUM_ACTION_BUTTONS = 12

world.restricted = 0
world.actionBar = { page = 1, bonus = 0, vehicle = false }
world.actions = {}
world.bindings = {}
world.overrides = {}
world.stateDrivers = {}
world.casts = {}
world.uiErrors = {}
world.gcdUntil = -math.huge
world.lockActionBars = true
world.unusableSpells = { [8676] = true, [703] = true }
world.noPowerSpells = {}
world.cooldowns = {} -- spell (base) -> when its own cooldown ends

local SPELL_NAMES = {
    enUS = {
        [53] = "Backstab",
        [8676] = "Ambush",
        [1752] = "Sinister Strike",
        [703] = "Garrote",
        [1766] = "Kick",
        [674] = "Dual Wield",
    },
    frFR = {
        [53] = "Attaque sournoise",
        [8676] = "Embuscade",
        [1752] = "Attaque pernicieuse",
        [703] = "Garrot",
        [1766] = "Coup de pied",
        [674] = "Ambidextrie",
    },
}
world.spells = {
    [53] = { icon = 132090 },
    [2589] = { base = 53 },
    [8676] = { icon = 132282 },
    [1752] = { icon = 136189 },
    [703] = { icon = 132297 },
    [1766] = { icon = 132219 },
    [674] = { icon = 132147 },
}

-- The spellbook's tabs (skill lines), in order: { name, icon, hidden, spells }
-- with spells { spellID, passive }.
world.spellBook = {
    { name = "General", icon = 136243, spells = { { spellID = 674, passive = true }, { spellID = 1766 } } },
    {
        name = "Combat",
        icon = 132090,
        spells = { { spellID = 53 }, { spellID = 8676 }, { spellID = 1752 }, { spellID = 703 } },
    },
    { name = "Hidden", icon = 134400, hidden = true, spells = { { spellID = 1752 } } },
}

local function BaseSpell(spellID)
    local spell = world.spells[spellID]
    return spell and (spell.base or spellID)
end

local function AssertAllowed(action)
    assert(
        not (world.inCombat and world.restricted == 0),
        "ADDON_ACTION_BLOCKED: " .. action .. " is protected in combat"
    )
end

local function CheckSecure(frame, action)
    if frame.secure then
        AssertAllowed(action)
    end
end

local RegionShow, RegionHide = Region.Show, Region.Hide

function Region:Show()
    CheckSecure(self, "Show")
    RegionShow(self)
end

function Region:Hide()
    CheckSecure(self, "Hide")
    RegionHide(self)
end

function Region:SetAttribute(name, value)
    CheckSecure(self, "SetAttribute")
    self.attributes = self.attributes or {}
    self.attributes[name] = value
    self:RunScript("OnAttributeChanged", name, value)
end

function Region:IsEventRegistered(event)
    return self.events[event] == true
end

function Region:GetSize()
    return self:GetWidth(), self:GetHeight()
end

function Region:GetButtonState()
    return self.buttonState or "NORMAL"
end

-- Not protected: addons may set it in combat.
function Region:SetButtonState(state)
    self.buttonState = state
end

-- self.tint: "white" or "blue" for Blizzard's usable and short of power icon
-- colors, else { r, g, b }.
function Region:SetVertexColor(r, g, b)
    if r == 1 and g == 1 and b == 1 then
        self.tint = "white"
    elseif r == 0.5 and g == 0.5 and b == 1 then
        self.tint = "blue"
    else
        self.tint = { r, g, b }
    end
end

Region.SetPassThroughButtons = NoOp
Region.SetMouseMotionEnabled = NoOp

-- Runs a restricted snippet: `signature` names its arguments ("self,stateid,newstate",
-- or "self,..."), `self` being the frame's handle.
local RunSnippet

local function Handle(frame)
    local handle = {}
    function handle:GetName()
        return frame:GetName()
    end
    function handle:GetAttribute(name)
        return frame:GetAttribute(name)
    end
    function handle:SetAttribute(name, value)
        frame:SetAttribute(name, value)
    end
    function handle:Show()
        frame:Show()
    end
    function handle:Hide()
        frame:Hide()
    end
    function handle:ClearBindings()
        ClearOverrideBindings(frame)
    end
    function handle:SetBindingClick(priority, key, name, button)
        SetOverrideBindingClick(frame, priority, key, name, button)
    end
    function handle:RunAttribute(name, ...)
        return RunSnippet(frame, "self,...", assert(frame:GetAttribute(name), "no snippet " .. name), ...)
    end
    return handle
end

function RunSnippet(frame, signature, body, ...)
    local env = {
        tonumber = tonumber,
        tostring = tostring,
        select = select,
        format = string.format,
        math = math,
        string = string,
    }
    local source
    if signature:find("%.%.%.") then
        source = "local self = ...\nreturn (function(...)\n" .. body .. "\nend)(select(2, ...))"
    else
        source = "local " .. signature .. " = ...\n" .. body
    end
    local chunk = assert(load(source, "snippet", "t", env))
    world.restricted = world.restricted + 1
    local results = table.pack(pcall(chunk, Handle(frame), ...))
    world.restricted = world.restricted - 1
    assert(results[1], results[2])
    return table.unpack(results, 2, results.n)
end

-- SecureButton_GetModifiedAttribute, without modifiers: "<name>1" for the left
-- button, "<name>-<button>" for others, then the bare name.
local function ButtonAttribute(frame, name, button)
    local suffix = button == "LeftButton" and "1" or "-" .. button
    local value = frame:GetAttribute(name .. suffix)
    if value == nil then
        value = frame:GetAttribute(name)
    end
    return value
end

local function PerformAction(frame, actionType, button)
    if actionType == "spell" then
        CastSpellByName(ButtonAttribute(frame, "spell", button))
    elseif actionType ~= nil then
        error("unmodelled action type " .. tostring(actionType))
    end
end

-- SecureActionButton_OnClick, for clicks that aren't Blizzard's own mouse
-- presses: on key down with useOnKeyDown (the CVar, on) or pressAndHoldAction,
-- where `downbutton` remaps the down and `typerelease` acts on the release.
local function SecureActionButtonOnClick(frame, button, down)
    local pressAndHold = frame:GetAttribute("pressAndHoldAction")
    if down then
        local remapped = ButtonAttribute(frame, "downbutton", button) or button
        PerformAction(frame, ButtonAttribute(frame, "type", remapped), remapped)
    elseif pressAndHold then
        PerformAction(frame, ButtonAttribute(frame, "typerelease", button), button)
    end
end

templates.SecureActionButtonTemplate = function(frame)
    frame.secure = true
    frame.protected = true
    frame.scripts.OnClick = SecureActionButtonOnClick
end

templates.SecureHandlerStateTemplate = function(frame)
    frame.secure = true
    frame.protected = true
    function frame:Execute(body)
        RunSnippet(self, "self", body)
    end
    frame.scripts.OnAttributeChanged = function(self, name, value)
        local stateID = name:match("^state%-(.+)$")
        local body = stateID and self:GetAttribute("_onstate-" .. stateID)
        if body then
            RunSnippet(self, "self,stateid,newstate", body, stateID, value)
        end
    end
end

-- ActionButtonSpellAlertMixin: `ProcStartAnim.playing` tells whether the glow played.
templates.ActionButtonSpellAlertTemplate = function(frame)
    frame.ProcStartAnim = {
        Play = function(self)
            self.playing = true
        end,
        Stop = function(self)
            self.playing = false
        end,
    }
end

-- Macro conditions -----------------------------------------------------------------

local function ConditionHolds(condition)
    local name, argument = condition:match("^%s*(%a+):?(%d*)%s*$")
    argument = tonumber(argument)
    local bar = world.actionBar
    if name == "vehicleui" then
        return bar.vehicle
    elseif name == "possessbar" or name == "overridebar" or name == "shapeshift" then
        return false
    elseif name == "bonusbar" then
        return argument and bar.bonus == argument or (not argument and bar.bonus > 0)
    elseif name == "actionbar" then
        return bar.page == argument
    end
    error("unmodelled macro condition " .. condition)
end

function SecureCmdOptionParse(text)
    for clause in text:gmatch("[^;]+") do
        local groups, value = clause:match("^%s*(%[.*%])%s*(.-)%s*$")
        if not groups then
            return (clause:match("^%s*(.-)%s*$"))
        end
        for group in groups:gmatch("%[(.-)%]") do
            local holds = true
            for condition in group:gmatch("[^,]+") do
                holds = holds and ConditionHolds(condition)
            end
            if holds then
                return value
            end
        end
    end
    return nil
end

-- State drivers: like the client, registering one sets its state at once.
local function SetDriverState(frame, state, driver)
    local value = SecureCmdOptionParse(driver)
    if frame:GetAttribute("state-" .. state) ~= value then
        world.restricted = world.restricted + 1
        frame:SetAttribute("state-" .. state, value)
        world.restricted = world.restricted - 1
    end
end

function RegisterStateDriver(frame, state, driver)
    AssertAllowed("RegisterStateDriver")
    world.stateDrivers[frame] = world.stateDrivers[frame] or {}
    world.stateDrivers[frame][state] = driver
    SetDriverState(frame, state, driver)
end

function UnregisterStateDriver(frame, state)
    AssertAllowed("UnregisterStateDriver")
    if world.stateDrivers[frame] then
        world.stateDrivers[frame][state] = nil
    end
end

-- Bindings ---------------------------------------------------------------------------

function GetBindingKey(command)
    local keys = {}
    for key, bound in pairs(world.bindings) do
        if bound == command then
            table.insert(keys, key)
        end
    end
    table.sort(keys)
    return unpack(keys)
end

function SetOverrideBindingClick(owner, priority, key, name, button)
    AssertAllowed("SetOverrideBindingClick")
    for i = #world.overrides, 1, -1 do
        local override = world.overrides[i]
        if override.owner == owner and override.key == key then
            table.remove(world.overrides, i)
        end
    end
    if name then
        table.insert(world.overrides, {
            owner = owner,
            priority = priority,
            key = key,
            name = name,
            button = button or "LeftButton",
        })
    end
    world:Fire("UPDATE_BINDINGS")
end

function ClearOverrideBindings(owner)
    AssertAllowed("ClearOverrideBindings")
    for i = #world.overrides, 1, -1 do
        if world.overrides[i].owner == owner then
            table.remove(world.overrides, i)
        end
    end
    world:Fire("UPDATE_BINDINGS")
end

-- The override binding a key runs, or nil: priority ones first, then the latest.
local function OverrideFor(key)
    local found
    for _, override in ipairs(world.overrides) do
        if override.key == key and (not found or override.priority or not found.priority) then
            found = override
        end
    end
    return found
end

-- Spells and action slots ------------------------------------------------------------

local function SpellByName(name)
    for spellID in pairs(world.spells) do
        if C_Spell.GetSpellName(spellID) == name then
            return spellID
        end
    end
end

C_Spell = {
    GetSpellName = function(spellID)
        local base = BaseSpell(spellID)
        return base and SPELL_NAMES[TEST_LOCALE][base]
    end,
    GetSpellTexture = function(spellID)
        local base = BaseSpell(spellID)
        return base and world.spells[base].icon
    end,
    IsSpellUsable = function(spellID)
        local base = BaseSpell(spellID)
        if world.noPowerSpells[base] then
            return false, true
        end
        return not world.unusableSpells[base], false
    end,
    PickupSpell = function(spellID)
        AssertAllowed("PickupSpell")
        world.cursorAction = spellID
    end,
    -- Like the client, every spell shows the global cooldown (isOnGCD) after a
    -- cast, unless it's on a longer cooldown of its own.
    GetSpellCooldown = function(spellID)
        local base = BaseSpell(spellID)
        if not base then
            return nil
        end
        local own = world.cooldowns[base]
        if own and world.now < own then
            return { isActive = true, isOnGCD = false }
        end
        return { isActive = world.now < world.gcdUntil, isOnGCD = world.now < world.gcdUntil }
    end,
}

-- The spellbook's items are numbered across its tabs, in order.
local function SpellBookItem(slot)
    for _, line in ipairs(world.spellBook) do
        if slot <= #line.spells then
            return line.spells[slot]
        end
        slot = slot - #line.spells
    end
end

C_SpellBook = {
    GetNumSpellBookSkillLines = function()
        return #world.spellBook
    end,
    GetSpellBookSkillLineInfo = function(index)
        local line = world.spellBook[index]
        if not line then
            return nil
        end
        local offset = 0
        for previous = 1, index - 1 do
            offset = offset + #world.spellBook[previous].spells
        end
        return {
            name = line.name,
            iconID = line.icon,
            itemIndexOffset = offset,
            numSpellBookItems = #line.spells,
            isGuild = false,
            shouldHide = line.hidden == true,
        }
    end,
    GetSpellBookItemInfo = function(slot, bank)
        assert(bank == Enum.SpellBookSpellBank.Player, "unmodelled spell bank")
        local spell = SpellBookItem(slot)
        if not spell then
            return nil
        end
        return {
            actionID = spell.spellID,
            spellID = spell.spellID,
            itemType = Enum.SpellBookItemType.Spell,
            name = C_Spell.GetSpellName(spell.spellID),
            iconID = C_Spell.GetSpellTexture(spell.spellID),
            isPassive = spell.passive == true,
            isOffSpec = false,
        }
    end,
}

local CAST_REFUSED = "%s: Not yet recovered"
local CAST_ON_COOLDOWN = "Spell is not ready yet."

local function OnOwnCooldown(spellID)
    local own = world.cooldowns[BaseSpell(spellID)]
    return own ~= nil and world.now < own
end

function CastSpellByName(name)
    local spellID = assert(SpellByName(name), "unknown spell " .. tostring(name))
    local usable = C_Spell.IsSpellUsable(spellID)
    if not usable then
        world:Fire("UI_ERROR_MESSAGE", 0, CAST_REFUSED:format(name))
    elseif world.now < world.gcdUntil or OnOwnCooldown(spellID) then
        world:Fire("UI_ERROR_MESSAGE", 0, CAST_ON_COOLDOWN)
    else
        table.insert(world.casts, name)
        world.gcdUntil = world.now + GLOBAL_COOLDOWN
        -- The global cooldown starts.
        world:Fire("SPELL_UPDATE_COOLDOWN")
    end
end

function GetActionInfo(slot)
    if world.actions[slot] then
        return "spell", world.actions[slot]
    end
end

function PickupAction(slot)
    AssertAllowed("PickupAction")
    world.cursorAction = world.actions[slot]
    world.actions[slot] = nil
    world:Fire("ACTIONBAR_SLOT_CHANGED", slot)
end

function PlaceAction(slot)
    AssertAllowed("PlaceAction")
    world.actions[slot], world.cursorAction = world.cursorAction, world.actions[slot]
    world:Fire("ACTIONBAR_SLOT_CHANGED", slot)
end

Settings.GetValue = function(name)
    assert(name == "lockActionBars", "unmodelled setting " .. name)
    return world.lockActionBars
end

function IsModifiedClick(action)
    return world.modifiedClick == action
end

-- UIErrorsFrame shows the errors of refused casts (UI_ERROR_MESSAGE).
do
    local errorsFrame = CreateFrame("Frame")
    errorsFrame.AddExternalErrorMessage = UIErrorsFrame.AddExternalErrorMessage
    errorsFrame.AddExternalWarningMessage = UIErrorsFrame.AddExternalWarningMessage
    errorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
    errorsFrame:SetScript("OnEvent", function(_, _, _, message)
        table.insert(world.uiErrors, message)
    end)
    UIErrorsFrame = errorsFrame
end

-- Blizzard's action buttons ------------------------------------------------------------

-- A spell newly put on a bar is marked (world.newActions, by slot) and its
-- buttons show NewActionTexture until used or hovered.
world.newActions = {}

function GetNewActionHighlightMark(slot)
    return world.newActions[slot]
end

function ClearNewActionHighlight(slot)
    world.newActions[slot] = nil
end

local function ActionButton(name, bindingAction)
    local button = CreateFrame("CheckButton", name)
    button.protected = true
    button.bindingAction = bindingAction
    button.icon = button:CreateTexture()
    button.NewActionTexture = button:CreateTexture()
    button.NewActionTexture:Hide()
    button:SetSize(45, 45)
    function button:UpdateHighlightMark()
        self.NewActionTexture:SetShown(GetNewActionHighlightMark(self.action) == true)
    end
    return button
end

-- Blizzard's TryUseActionButton: casts the button's spell and clears its new mark.
local function UseActionButton(button)
    CastSpellByName(C_Spell.GetSpellName(world.actions[button.action]))
    if GetNewActionHighlightMark(button.action) then
        ClearNewActionHighlight(button.action)
        button:UpdateHighlightMark()
    end
end

for i = 1, NUM_ACTION_BUTTONS do
    ActionButton("ActionButton" .. i, "ACTIONBUTTON" .. i)
    ActionButton("MultiBarBottomLeftButton" .. i, "MULTIACTIONBAR1BUTTON" .. i).action = 60 + i
end

-- What ActionBarController does on a page or bonus bar change.
local function UpdateMainBar()
    local bar = world.actionBar
    local page = (bar.bonus > 0 and bar.page == 1) and 6 + bar.bonus or bar.page
    for i = 1, NUM_ACTION_BUTTONS do
        _G["ActionButton" .. i].action = (page - 1) * NUM_ACTION_BUTTONS + i
    end
end
UpdateMainBar()

local function UpdateStateDrivers()
    for frame, drivers in pairs(world.stateDrivers) do
        for state, driver in pairs(drivers) do
            SetDriverState(frame, state, driver)
        end
    end
end

-- Puts the spell in an action slot, like dragging it from the spellbook.
function world:PlaceSpell(slot, spellID)
    self.actions[slot] = spellID
    self:Fire("ACTIONBAR_SLOT_CHANGED", slot)
end

-- A trainer teaching the spell (a new rank keeps its name).
function world:LearnSpell(spellID)
    self:Fire("LEARNED_SPELL_IN_SKILL_LINE", spellID, 1, false)
end

-- Like learning a new rank: the game marks the slot new, and its buttons show it.
function world:MarkNewAction(slot)
    self.newActions[slot] = true
    for _, frame in ipairs(self.frames) do
        if frame.UpdateHighlightMark and frame.action == slot then
            frame:UpdateHighlightMark()
        end
    end
end

function world:Bind(key, command)
    self.bindings[key] = command
    self:Fire("UPDATE_BINDINGS")
end

-- Stealth and the like: the main bar shows the stance's bonus bar (0: none).
function world:SetBonusBar(bonus)
    self.actionBar.bonus = bonus
    UpdateMainBar()
    UpdateStateDrivers()
    self:Fire("UPDATE_BONUS_ACTIONBAR")
end

function world:SetActionBarPage(page)
    self.actionBar.page = page
    UpdateMainBar()
    UpdateStateDrivers()
    self:Fire("ACTIONBAR_PAGE_CHANGED")
end

function world:SetSpellUsable(spellID, usable)
    self.unusableSpells[BaseSpell(spellID)] = not usable or nil
    self:Fire("SPELL_UPDATE_USABLE")
end

-- Energy running short of (or back up to) the spell's cost: only the power
-- event fires, as for a spell on a bar page out of view.
function world:SetShortOfPower(spellID, short)
    self.noPowerSpells[BaseSpell(spellID)] = short or nil
    self:Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
end

-- One click of a frame (the mouse, or a click binding), with its pre and post clicks.
local function ClickFrame(frame, button, down)
    frame:RunScript("PreClick", button, down)
    frame:RunScript("OnClick", button, down)
    frame:RunScript("PostClick", button, down)
end

-- What the key runs now: "CLICK <frame>" for an override click binding, the
-- binding command otherwise (nil when unbound).
local function KeyTarget(key)
    local override = OverrideFor(key)
    return override and "CLICK " .. override.name or world.bindings[key]
end

-- A key going down or up. An override click binding clicks its frame; a
-- Blizzard action button binding runs ActionButtonDown / ActionButtonUp: the
-- button shows pushed while held and casts its slot's spell on the press
-- (ActionButtonUseKeyDown). Measured in game: when the key's binding changes
-- while it's held, the release goes nowhere, neither to the old binding nor to
-- the new one.
world.heldKeys = {}

local function SendKey(key, down)
    local target = KeyTarget(key)
    if down then
        world.heldKeys[key] = target
    else
        local held = world.heldKeys[key]
        world.heldKeys[key] = nil
        if held ~= target then
            return
        end
    end
    local override = OverrideFor(key)
    if override then
        ClickFrame(assert(_G[override.name], "no frame " .. override.name), override.button, down)
        return
    end
    for _, frame in ipairs(world.frames) do
        if target and frame.bindingAction == target then
            if down then
                if frame:GetButtonState() == "NORMAL" then
                    frame:SetButtonState("PUSHED")
                end
                if frame.action and world.actions[frame.action] then
                    UseActionButton(frame)
                end
            elseif frame:GetButtonState() == "PUSHED" then
                frame:SetButtonState("NORMAL")
            end
        end
    end
end

function world:KeyDown(key)
    SendKey(key, true)
end

function world:KeyUp(key)
    SendKey(key, false)
end

function world:PressKey(key)
    SendKey(key, true)
    SendKey(key, false)
end

-- A left click on whatever lies on top of the button: our overlay when shown.
function world:ClickButton(button)
    local target = button
    for _, frame in ipairs(self.frames) do
        if frame.parent == button and frame.secure and frame:IsShown() then
            target = frame
        end
    end
    if target == button then
        UseActionButton(button)
    else
        ClickFrame(target, "LeftButton", true)
        ClickFrame(target, "LeftButton", false)
    end
end

-- The replacement shown on the button: its icon, whether its glow played and
-- its tint (see SetVertexColor), or nil.
function world:SwapShown(button)
    for _, frame in ipairs(self.frames) do
        if frame.parent == button and frame.Glow and frame:IsShown() then
            return frame.Icon.texture, frame.Glow.ProcStartAnim.playing, frame.Icon.tint
        end
    end
end

-- The overlay frame (our secure button) on the button, shown or not.
function world:Overlay(button)
    for _, frame in ipairs(self.frames) do
        if frame.parent == button and frame.secure then
            return frame
        end
    end
end

-- Spell cooldowns, the cursor and the settings panel -----------------------------------

-- Puts the spell on its own cooldown for `seconds`. Like the client,
-- SPELL_UPDATE_COOLDOWN fires when it starts and when it ends.
function world:SetCooldown(spellID, seconds)
    self.cooldowns[BaseSpell(spellID)] = self.now + seconds
    self:Fire("SPELL_UPDATE_COOLDOWN")
    C_Timer.NewTimer(seconds, function()
        world:Fire("SPELL_UPDATE_COOLDOWN")
    end)
end

-- Like the client's: a spell on the cursor reports its ID fourth.
function GetCursorInfo()
    if world.cursorAction then
        return "spell", 1, "spell", world.cursorAction
    elseif world.cursor then
        return "item", world.cursor
    end
end

-- Picks a spell up, as from the spellbook.
function world:PickupSpell(spellID)
    C_Spell.PickupSpell(spellID)
end

SettingsPanel = CreateFrame("Frame", "SettingsPanel")

function GameTooltip:SetSpellByID(spellID)
    world.tooltip = spellID
end

templates.UIMenuButtonStretchTemplate = NoOp
-- TooltipBackdropTemplateMixin
templates.TooltipBackdropTemplate = function(frame)
    frame.SetBackdropColor = NoOp
    frame.SetBackdropBorderColor = NoOp
end

function Region:CreateMaskTexture()
    return NewRegion({ owner = self })
end

-- Wraps nothing: one line.
function Region:GetStringHeight()
    return 12
end
Region.SetFrameStrata = NoOp

return world
