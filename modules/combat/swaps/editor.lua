-- The swaps editor: a window over the settings panel (opened by its Edit
-- button), one row per swap, each with the spell to replace and the spell to
-- show instead. Clicking a slot picks a spell from a menu of the spellbook's
-- tabs (the spellbook can't be open with the settings panel); a spell dropped
-- on it is taken too. After the saved rows comes one to add a swap, saved
-- once both its spells are in. It closes with Escape and with the settings panel.
-- It borrows the look of the action bars (slots) and of Blizzard's click
-- binding window (list, remove buttons).

local _, ns = ...

local L = ns.L

local Swaps = ns:GetFeature("combat", "swaps")

local Editor = {}
Swaps.Editor = Editor

local FRAME_NAME = "ForeverEnhancedSwapsEditor" -- UISpecialFrames needs a name
local WIDTH = 460
local HINT_LEFT = 66 -- right of the portrait
local PORTRAIT_BOTTOM = 58
local MARGIN = 12 -- between the window's edges and the list
local LIST_PADDING = 6
local ROW_HEIGHT = 50
local SLOT_SIZE = 40
local NAME_WIDTH = 124
local SIDES = { "original", "replacement" }
local MENU_HEIGHT = 400 -- longer spellbook tabs scroll

local frame
local rows = {}
-- The swap being added in the last row: { original, replacement }, either may be missing.
local adding = {}

local Refresh

-- Puts `spellID` on `side` of swap `index` (the add row past the saved ones),
-- if the swaps allow it, and saves.
local function Place(index, side, spellID)
    local list = Swaps:GetList()
    local isNew = list[index] == nil
    local checked = Swaps:GetList()
    checked[index] = isNew and adding or list[index]
    local problem = Swaps:CheckSpell(checked, index, side, spellID)
    if problem then
        ns:Error(L[problem])
        return
    end

    if isNew then
        adding[side] = spellID
        if adding.original and adding.replacement then
            table.insert(list, adding)
            adding = {}
            Swaps:SetList(list)
        end
    else
        list[index][side] = spellID
        Swaps:SetList(list)
    end
    Refresh()
end

local function Remove(index)
    local list = Swaps:GetList()
    if list[index] then
        table.remove(list, index)
        Swaps:SetList(list)
    else
        adding = {}
    end
    Refresh()
end

local function MenuText(icon, text)
    return ("|T%d:16:16:0:0:64:64:4:60:4:60|t %s"):format(icon, text)
end

-- The castable spells of spellbook tab `line`: { { spellID, name, icon } }.
local function GetTabSpells(line)
    local spells = {}
    for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
        local item = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
        if item and item.itemType == Enum.SpellBookItemType.Spell and not item.isPassive then
            table.insert(spells, { spellID = item.actionID, name = item.name, icon = item.iconID })
        end
    end
    return spells
end

-- One submenu per spellbook tab the spellbook shows.
local function GenerateSpellMenu(slot, rootDescription)
    for index = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(index)
        local spells = line and not line.shouldHide and not line.offSpecID and GetTabSpells(line) or {}
        if #spells > 0 then
            local tab = rootDescription:CreateButton(MenuText(line.iconID, line.name))
            tab:SetScrollMode(MENU_HEIGHT)
            for _, spell in ipairs(spells) do
                tab:CreateButton(MenuText(spell.icon, spell.name), function()
                    Place(slot.index, slot.side, spell.spellID)
                end)
            end
        end
    end
end

-- A spell dropped on the slot (or clicked on it from the cursor); otherwise
-- a click opens the spell menu.
local function OnPick(slot)
    local cursorType, _, _, spellID = GetCursorInfo()
    if not cursorType then
        MenuUtil.CreateContextMenu(slot, GenerateSpellMenu)
        return
    end
    ClearCursor()
    if cursorType ~= "spell" then
        ns:Error(L["combat.swaps.editor.notSpell"])
        return
    end
    Place(slot.index, slot.side, spellID)
end

local function OnEnter(slot)
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if slot.spellID then
        GameTooltip:SetSpellByID(slot.spellID)
    else
        GameTooltip:SetText(L["combat.swaps.editor." .. slot.side])
        GameTooltip:AddLine(L["combat.swaps.editor.pick"], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- An action bar slot: the spell's icon in the bar's frame, or an empty slot.
local function CreateSlot(row, index, side)
    local slot = CreateFrame("Button", nil, row)
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
    slot.index, slot.side = index, side

    local background = slot:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("UI-HUD-ActionBar-IconFrame-Background")
    background:SetAllPoints()
    slot.Empty = slot:CreateTexture(nil, "BACKGROUND", nil, 1)
    slot.Empty:SetAtlas("ui-hud-actionbar-iconframe-slot")
    slot.Empty:SetAllPoints()

    slot.Icon = slot:CreateTexture(nil, "ARTWORK")
    slot.Icon:SetAllPoints()
    local mask = slot:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetAllPoints(slot.Icon)
    slot.Icon:AddMaskTexture(mask)

    -- The bar's frame is a little wider than its button (46 by 45).
    local border = slot:CreateTexture(nil, "OVERLAY")
    border:SetAtlas("UI-HUD-ActionBar-IconFrame")
    border:SetSize(SLOT_SIZE * 46 / 45, SLOT_SIZE)
    border:SetPoint("TOPLEFT")
    local highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    highlight:SetAllPoints(border)
    slot.Add = slot:CreateTexture(nil, "HIGHLIGHT", nil, 1)
    slot.Add:SetAtlas("clickcast-icon-add")
    slot.Add:SetAllPoints()

    slot.Name = row:CreateFontString(nil, "ARTWORK")
    slot.Name:SetPoint("LEFT", slot, "RIGHT", 8, 0)
    slot.Name:SetWidth(NAME_WIDTH)
    slot.Name:SetJustifyH("LEFT")
    slot.Name:SetWordWrap(false)

    slot:RegisterForClicks("LeftButtonUp")
    slot:SetScript("OnClick", OnPick)
    slot:SetScript("OnReceiveDrag", OnPick)
    slot:SetScript("OnEnter", OnEnter)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    return slot
end

-- Blizzard's click binding delete button.
local function CreateRemoveButton(row, index)
    local button = CreateFrame("Button", nil, row, "UIMenuButtonStretchTemplate")
    button:SetSize(24, 22)
    button:SetPoint("RIGHT", -8, 0)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAtlas("groupfinder-icon-redx", true)
    icon:SetPoint("CENTER")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function()
        Remove(index)
    end)
    return button
end

local function CreateRow(index)
    local row = CreateFrame("Frame", nil, frame.List)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", LIST_PADDING, -LIST_PADDING - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", -LIST_PADDING, 0)
    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetColorTexture(1, 1, 1, 0.04)
        stripe:SetAllPoints()
    end

    row.original = CreateSlot(row, index, "original")
    row.original:SetPoint("LEFT", 6, 0)
    local arrow = row:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetSize(16, 16)
    arrow:SetPoint("LEFT", row.original.Name, "RIGHT", 4, 0)
    row.replacement = CreateSlot(row, index, "replacement")
    row.replacement:SetPoint("LEFT", arrow, "RIGHT", 10, 0)

    row.Remove = CreateRemoveButton(row, index)
    rows[index] = row
    return row
end

local function ShowSpell(slot, spellID)
    slot.spellID = spellID
    slot.Icon:SetTexture(spellID and C_Spell.GetSpellTexture(spellID))
    slot.Empty:SetShown(not spellID)
    slot.Add:SetShown(not spellID)
    slot.Name:SetFontObject(spellID and GameFontNormal or GameFontDisable)
    slot.Name:SetText(spellID and C_Spell.GetSpellName(spellID) or L["combat.swaps.editor." .. slot.side])
end

function Refresh()
    local list = Swaps:GetList()
    -- The saved swaps, then the add row while there's room.
    local count = math.min(#list + 1, Swaps.MAX_SWAPS)
    for index = 1, count do
        local row = rows[index] or CreateRow(index)
        local swap = list[index] or adding
        for _, side in ipairs(SIDES) do
            ShowSpell(row[side], swap[side])
        end
        row.Remove:SetShown(swap.original ~= nil or swap.replacement ~= nil)
        row:Show()
    end
    for index = count + 1, #rows do
        rows[index]:Hide()
    end

    local listHeight = count * ROW_HEIGHT + 2 * LIST_PADDING
    frame.List:SetHeight(listHeight)
    frame:SetHeight(frame.listTop + listHeight + MARGIN)
end

local function Create()
    frame = CreateFrame("Frame", FRAME_NAME, SettingsPanel, "PortraitFrameTemplate")
    frame:Hide()
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetTitle(L["combat.swaps.title"])
    frame:SetPortraitToClassIcon(select(2, UnitClass("player")))
    table.insert(UISpecialFrames, FRAME_NAME)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", HINT_LEFT, -32)
    hint:SetWidth(WIDTH - HINT_LEFT - 16)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["combat.swaps.editor.hint"])
    frame.listTop = math.max(PORTRAIT_BOTTOM, 32 + hint:GetStringHeight()) + 10

    -- Blizzard's click binding list.
    frame.List = CreateFrame("Frame", nil, frame, "TooltipBackdropTemplate")
    frame.List:SetPoint("TOPLEFT", MARGIN, -frame.listTop)
    frame.List:SetPoint("RIGHT", -MARGIN, 0)
    frame.List:SetBackdropBorderColor(0.4, 0.4, 0.4)
    frame.List:SetBackdropColor(0, 0, 0)

    frame.Rows = rows
    frame:SetScript("OnShow", Refresh)
    frame:SetScript("OnHide", function()
        adding = {}
    end)
end

function Editor:Toggle()
    if not frame then
        Create()
    end
    frame:SetShown(not frame:IsShown())
end

function Editor:Hide()
    if frame then
        frame:Hide()
    end
end
