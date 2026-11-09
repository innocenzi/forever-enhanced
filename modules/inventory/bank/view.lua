-- The saved bank frame: a read-only copy of Blizzard's Camelot bank frame
-- (Camelot/BankFrame.xml, BankFrameTemplate, BankPanelMixin), built from the
-- same templates and atlases, filled from a saved bank instead of the live one.
-- Items show their tooltip and take modified clicks (link, dressing room);
-- nothing can be picked up or used.
--
-- It is a UI panel like the bank (left area, closes on Escape), which needs a
-- global frame name. The panel manager does nothing in combat, so the frame is
-- then shown and hidden directly.

local _, ns = ...

local L = ns.L
local Bank = ns:GetFeature("inventory", "bank")

local View = {}
Bank.View = View

local FRAME_NAME = "ForeverEnhancedSavedBankFrame"

-- Blizzard's Camelot bank layout.
local FRAME_WIDTH, BASE_HEIGHT = 480, 460
local PANEL_WIDTH = 560 -- page tabs included (bankFrameWidthOverride)
local COLUMNS, SLOTS_PER_PAGE, BASE_ROWS = 8, 88, 6
local FIRST_X, FIRST_Y = 47, -63
local COLUMN_STEP, ROW_STEP = 50, 47 -- 37px buttons, 13px and 10px apart
local BAG_SCALE, BAG_FIRST_X, BAG_FIRST_Y, BAG_STEP = 0.75, 200, 115, 50
local PAGE_TAB_ICONS = {
    "Interface/ICONS/INV_SideTab_Bank_c60",
    "Interface/ICONS/ACHIEVEMENT_GUILDPERK_MOBILEBANKING",
    "Interface/ICONS/TRADE_ARCHAEOLOGY_CHESTOFTINYGLASSANIMALS",
    "Interface/ICONS/Ability_Racial_PackHobgoblin",
}

local frame, dropdown, emptyText, bagText, bagDivider
local itemButtons, bagButtons, pageTabs = {}, {}, {}
-- Per button: the saved item (or bank bag) it shows.
local shownItems = setmetatable({}, { __mode = "k" })
-- Per bank bag button: its "not purchased" padlock.
local bagLocks = setmetatable({}, { __mode = "k" })

local selectedKey
local currentPage = 1

-- Items and bank bags -----------------------------------------------------------

local function OnItemEnter(button)
    local item = shownItems[button]
    if not item then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if item.link then
        GameTooltip:SetHyperlink(item.link)
    elseif item.purchased ~= nil then -- empty bank bag slot
        GameTooltip:SetText(item.purchased and BANK_BAG or BANK_BAG_PURCHASE)
    end
    GameTooltip:Show()
end

local function OnItemClick(button)
    local item = shownItems[button]
    if item and item.link then
        HandleModifiedItemClick(item.link)
    end
end

local function CreateItemButton(atlas)
    local button = CreateFrame("ItemButton", nil, frame)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas(atlas)
    background:SetAllPoints()
    button:SetScript("OnEnter", OnItemEnter)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", OnItemClick)
    return button
end

local function GetItemButton(index)
    local button = itemButtons[index]
    if not button then
        button = CreateItemButton("bags-item-bankslot64")
        local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", FIRST_X + column * COLUMN_STEP, FIRST_Y - row * ROW_STEP)
        itemButtons[index] = button
    end
    return button
end

local function SetItem(button, item)
    shownItems[button] = item
    SetItemButtonTexture(button, item and item.icon)
    SetItemButtonCount(button, item and item.count or 0)
    SetItemButtonQuality(
        button,
        item and item.quality,
        item and (item.itemID or item.link),
        false,
        item and item.isBound
    )
    local normalAtlas = item and "bank-frame-bag-slotframe" or "bank-frame-item-slotframe"
    button:GetNormalTexture():SetAtlas(normalAtlas, TextureKitConstants.IgnoreAtlasSize)
    button:SetMatchesSearch(item == nil or Bank.Search:Matches(item))
end

local function GetBagButton(index)
    local button = bagButtons[index]
    if not button then
        button = CreateItemButton("bank-frame-bag-slot-bg")
        button:SetScale(BAG_SCALE)
        button:GetNormalTexture():SetAtlas("bank-frame-bag-slotframe", TextureKitConstants.IgnoreAtlasSize)
        local lock = button:CreateTexture(nil, "ARTWORK", nil, 1)
        lock:SetAtlas("bankslot-icon-lock")
        lock:SetAllPoints()
        bagLocks[button] = lock
        if index == 1 then
            button:SetPoint("LEFT", frame, "BOTTOMLEFT", BAG_FIRST_X, BAG_FIRST_Y)
        else
            button:SetPoint("TOPLEFT", bagButtons[index - 1], "TOPLEFT", BAG_STEP, 0)
        end
        bagButtons[index] = button
    end
    return button
end

local function SetBag(button, bag)
    shownItems[button] = bag
    SetItemButtonTexture(button, bag.icon)
    SetItemButtonQuality(button, bag.quality, bag.link)
    bagLocks[button]:SetShown(not bag.purchased)
end

-- Page tabs -----------------------------------------------------------------------

local function GetPageTab(page)
    local tab = pageTabs[page]
    if not tab then
        tab = CreateFrame("Frame", nil, frame, "LargeSideTabButtonTemplate")
        tab:SetFillToInterior(true)
        tab.Icon:SetTexture(PAGE_TAB_ICONS[page] or PAGE_TAB_ICONS[1])
        tab.tooltipText = PAGE_NUMBER:format(page)
        tab:SetCustomOnMouseUpHandler(function(_, mouseButton, upInside)
            if mouseButton == "LeftButton" and upInside then
                View:ShowPage(page)
            end
        end)
        if page == 1 then
            tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
        else
            tab:SetPoint("TOPLEFT", pageTabs[page - 1], "BOTTOMLEFT", 0, -2)
        end
        pageTabs[page] = tab
    end
    return tab
end

-- Character menu ------------------------------------------------------------------

local function ColoredName(entry)
    local color = RAID_CLASS_COLORS[entry.class]
    return color and color:WrapTextInColorCode(entry.name) or entry.name
end

local function FindEntry(key)
    for _, entry in ipairs(Bank.Store:List()) do
        if entry.key == key then
            return entry
        end
    end
end

local function ConfirmForget(entry)
    StaticPopup_ShowCustomGenericConfirmation({
        text = L["inventory.bank.forgetConfirm"],
        text_arg1 = entry.name,
        callback = function()
            if not Bank:IsActive() then
                return
            end
            Bank.Store:Forget(entry.key)
            if selectedKey == entry.key then
                View:Select(Bank.Store:GetPlayerKey())
            else
                dropdown:GenerateMenu()
            end
        end,
    })
end

local function GenerateCharacterMenu(_, rootDescription)
    local alts = {}
    for _, entry in ipairs(Bank.Store:List()) do
        rootDescription:CreateRadio(ColoredName(entry), function()
            return entry.key == selectedKey
        end, function()
            View:Select(entry.key)
        end)
        if not entry.isPlayer then
            table.insert(alts, entry)
        end
    end

    if #alts > 0 then
        rootDescription:CreateDivider()
        local forget = rootDescription:CreateButton(L["inventory.bank.forget"])
        for _, entry in ipairs(alts) do
            forget:CreateButton(ColoredName(entry), function()
                ConfirmForget(entry)
            end)
        end
    end
end

-- Frame -----------------------------------------------------------------------------

local function CreateView()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "PortraitFrameTemplate")
    frame:Hide()
    frame:SetSize(FRAME_WIDTH, BASE_HEIGHT)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) -- where the panel manager puts it
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    RegisterUIPanel(frame, { area = "left", pushable = 6, width = PANEL_WIDTH })
    table.insert(UISpecialFrames, FRAME_NAME)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("bank-frame-background")
    background:SetHorizTile(true)
    background:SetVertTile(true)
    background:SetPoint("TOPLEFT", 0, -20)
    background:SetPoint("BOTTOMRIGHT", 0, 30)

    local inset = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    inset:SetPoint("TOPLEFT", 0, -20)
    inset:SetPoint("BOTTOMRIGHT", 0, 30)
    NineSliceUtil.ApplyLayoutByName(inset, "InsetFrameTemplate")

    local shadows = CreateFrame("Frame", nil, frame, "BankPanelEdgeShadowTemplate")
    shadows:SetPoint("TOPLEFT")
    shadows:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT")

    bagDivider = frame:CreateTexture(nil, "ARTWORK")
    bagDivider:SetAtlas("bank-divider", true)
    bagDivider:SetScale(0.48)
    bagDivider:SetPoint("BOTTOM", 0, 220)

    bagText = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    bagText:SetSize(120, 40)
    bagText:SetJustifyH("RIGHT")
    bagText:SetPoint("BOTTOMLEFT", 15, 67)
    bagText:SetText(BAGSLOTTEXT_COLON)

    emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    emptyText:SetWidth(FRAME_WIDTH - 80)
    emptyText:SetPoint("CENTER", inset)
    emptyText:SetText(L["inventory.bank.empty"])

    dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(160)
    dropdown:SetPoint("TOPLEFT", 60, -31)
    dropdown:SetupMenu(GenerateCharacterMenu)

    Bank.Search:CreateBox(frame):SetPoint("TOPRIGHT", -22, -33)

    frame:SetScript("OnShow", function()
        Bank.Tab:Refresh()
    end)
    frame:SetScript("OnHide", function()
        Bank.Tab:Refresh()
    end)
end

-- Saved items in bank order, empty slots included: items, slotCount.
local function FlattenTabs(record)
    local items, count = {}, 0
    for _, tab in ipairs(record and record.tabs or {}) do
        for slot = 1, tab.size do
            items[count + slot] = tab.items[slot]
        end
        count = count + tab.size
    end
    return items, count
end

local function RefreshItems(record)
    local items, slotCount = FlattenTabs(record)
    local pageCount = math.max(1, math.ceil(slotCount / SLOTS_PER_PAGE))
    currentPage = math.min(currentPage, pageCount)

    local firstSlot = (currentPage - 1) * SLOTS_PER_PAGE
    local shownCount = math.max(0, math.min(SLOTS_PER_PAGE, slotCount - firstSlot))
    local rows = math.ceil(shownCount / COLUMNS)
    frame:SetHeight(BASE_HEIGHT + math.max(0, rows - BASE_ROWS) * ROW_STEP)

    for index = 1, math.max(shownCount, #itemButtons) do
        local button = GetItemButton(index)
        if index <= shownCount then
            SetItem(button, items[firstSlot + index])
            button:Show()
        else
            shownItems[button] = nil
            button:Hide()
        end
    end

    for page = 1, math.max(pageCount, #pageTabs) do
        local tab = GetPageTab(page)
        tab:SetChecked(page == currentPage)
        tab:SetShown(page <= pageCount)
    end
end

local function RefreshBags(record)
    local bags = record and record.bags or {}
    local count = 0
    while bags[count + 2] do
        count = count + 1
        local button = GetBagButton(count)
        SetBag(button, bags[count + 1])
        button:Show()
    end
    for index = count + 1, #bagButtons do
        shownItems[bagButtons[index]] = nil
        bagButtons[index]:Hide()
    end
    bagText:SetShown(count > 0)
    bagDivider:SetShown(count > 0)
end

function View:Refresh()
    if not frame then
        return
    end
    local record = Bank.Store:Get(selectedKey)
    local entry = FindEntry(selectedKey)

    frame:SetTitle(L["inventory.bank.frameTitle"]:format(entry.name))
    frame:SetPortraitToClassIcon(entry.class)
    dropdown:GenerateMenu()

    RefreshItems(record)
    RefreshBags(record)
    emptyText:SetShown(record == nil)
end

function View:UpdateSearch()
    for _, button in ipairs(itemButtons) do
        local item = shownItems[button]
        if item then
            button:SetMatchesSearch(Bank.Search:Matches(item))
        end
    end
end

function View:IsShown()
    return frame ~= nil and frame:IsShown()
end

-- Opens on the player's saved bank. Never while Blizzard's bank is open.
function View:Open()
    if Bank.Snapshot:IsBankOpen() or self:IsShown() then
        return
    end
    if not frame then
        CreateView()
    end
    selectedKey = Bank.Store:GetPlayerKey()
    currentPage = 1
    Bank.Search:Sync()
    self:Refresh()
    ShowUIPanel(frame)
    if not frame:IsShown() then
        frame:Show()
    end
end

function View:Close()
    if self:IsShown() then
        HideUIPanel(frame)
        if frame:IsShown() then
            frame:Hide()
        end
    end
end

function View:Toggle()
    if self:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

function View:Select(key)
    selectedKey = key
    currentPage = 1
    self:Refresh()
end

function View:ShowPage(page)
    currentPage = page
    self:Refresh()
end
