-- The spells editor: a window over the settings panel (opened by its button)
-- with the character's chosen spells as action bar slots, then an empty slot
-- to add one. Clicking the empty slot picks a spell from a menu of the
-- spellbook's tabs (the spellbook can't be open with the settings panel); a
-- spell dropped on any slot is added too. Right Click removes a spell. It
-- closes with Escape and with the settings panel, and moves like the other
-- windows (interface.windows).

local _, ns = ...

local L = ns.L

local Errors = ns:GetFeature("combat", "errors")

local Editor = {}
Errors.Editor = Editor

local FRAME_NAME = "ForeverEnhancedErrorsEditor" -- UISpecialFrames needs a name
local COLUMNS = 8
local SLOT_SIZE = 36
local SLOT_GAP = 6
local MARGIN = 12 -- between the window's edges and the grid
local GRID_PADDING = 8
local WIDTH = 2 * MARGIN + 2 * GRID_PADDING + COLUMNS * SLOT_SIZE + (COLUMNS - 1) * SLOT_GAP
local HINT_LEFT = 66 -- right of the portrait
local PORTRAIT_BOTTOM = 58
local MENU_HEIGHT = 400 -- longer spellbook tabs scroll

local frame
local slots = {}

local Refresh

local function Add(spellID)
    local name = C_Spell.GetSpellName(spellID)
    if not name then
        ns:Error(L["combat.errors.editor.notSpell"])
        return
    end
    local spells = Errors:GetSpells()
    for _, chosen in ipairs(spells) do
        if C_Spell.GetSpellName(chosen) == name then
            ns:Error(L["combat.errors.editor.alreadyChosen"])
            return
        end
    end
    if #spells >= Errors.MAX_SPELLS then
        return
    end
    table.insert(spells, spellID)
    Errors:SetSpells(spells)
    Refresh()
end

local function Remove(index)
    local spells = Errors:GetSpells()
    table.remove(spells, index)
    Errors:SetSpells(spells)
    GameTooltip_Hide()
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
local function GenerateSpellMenu(_, rootDescription)
    for index = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(index)
        local spells = line and not line.shouldHide and not line.offSpecID and GetTabSpells(line) or {}
        if #spells > 0 then
            local tab = rootDescription:CreateButton(MenuText(line.iconID, line.name))
            tab:SetScrollMode(MENU_HEIGHT)
            for _, spell in ipairs(spells) do
                tab:CreateButton(MenuText(spell.icon, spell.name), function()
                    Add(spell.spellID)
                end)
            end
        end
    end
end

-- A spell dropped on the slot (or clicked on it from the cursor) is added;
-- otherwise Right Click removes the slot's spell, and a click on the empty
-- slot opens the spell menu.
local function OnPick(slot, button)
    local cursorType, _, _, spellID = GetCursorInfo()
    if cursorType then
        ClearCursor()
        if cursorType ~= "spell" then
            ns:Error(L["combat.errors.editor.notSpell"])
            return
        end
        Add(spellID)
    elseif button == "RightButton" then
        if slot.spellID then
            Remove(slot.index)
        end
    elseif not slot.spellID then
        MenuUtil.CreateContextMenu(slot, GenerateSpellMenu)
    end
end

local function OnEnter(slot)
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if slot.spellID then
        GameTooltip:SetSpellByID(slot.spellID)
        GameTooltip_AddInstructionLine(GameTooltip, L["combat.errors.editor.remove"])
    else
        GameTooltip:SetText(L["combat.errors.editor.add"])
        GameTooltip:AddLine(L["combat.errors.editor.pick"], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- An action bar slot: the spell's icon in the bar's frame, or an empty slot.
local function CreateSlot(index)
    local slot = CreateFrame("Button", nil, frame.Grid)
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
    slot.index = index
    local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS)
    slot:SetPoint(
        "TOPLEFT",
        GRID_PADDING + column * (SLOT_SIZE + SLOT_GAP),
        -GRID_PADDING - row * (SLOT_SIZE + SLOT_GAP)
    )

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

    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:SetScript("OnClick", OnPick)
    slot:SetScript("OnReceiveDrag", OnPick)
    slot:SetScript("OnEnter", OnEnter)
    slot:SetScript("OnLeave", GameTooltip_Hide)
    slots[index] = slot
    return slot
end

local function ShowSpell(slot, spellID)
    slot.spellID = spellID
    slot.Icon:SetTexture(spellID and C_Spell.GetSpellTexture(spellID))
    slot.Empty:SetShown(not spellID)
    slot.Add:SetShown(not spellID)
end

function Refresh()
    local spells = Errors:GetSpells()
    -- The chosen spells, then the add slot while there's room.
    local count = math.min(#spells + 1, Errors.MAX_SPELLS)
    for index = 1, count do
        local slot = slots[index] or CreateSlot(index)
        ShowSpell(slot, spells[index])
        slot:Show()
    end
    for index = count + 1, #slots do
        slots[index]:Hide()
    end

    local rows = math.ceil(count / COLUMNS)
    local gridHeight = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP + 2 * GRID_PADDING
    frame.Grid:SetHeight(gridHeight)
    frame:SetHeight(frame.gridTop + gridHeight + MARGIN)
end

local function Create()
    frame = CreateFrame("Frame", FRAME_NAME, SettingsPanel, "PortraitFrameTemplate")
    frame:Hide()
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetTitle(L["combat.errors.title"])
    frame:SetPortraitToClassIcon(select(2, UnitClass("player")))
    table.insert(UISpecialFrames, FRAME_NAME)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", HINT_LEFT, -32)
    hint:SetWidth(WIDTH - HINT_LEFT - 16)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["combat.errors.editor.hint"])
    frame.gridTop = math.max(PORTRAIT_BOTTOM, 32 + hint:GetStringHeight()) + 10

    -- Blizzard's click binding list.
    frame.Grid = CreateFrame("Frame", nil, frame, "TooltipBackdropTemplate")
    frame.Grid:SetPoint("TOPLEFT", MARGIN, -frame.gridTop)
    frame.Grid:SetPoint("RIGHT", -MARGIN, 0)
    frame.Grid:SetBackdropBorderColor(0.4, 0.4, 0.4)
    frame.Grid:SetBackdropColor(0, 0, 0)

    frame.Slots = slots
    frame:SetScript("OnShow", Refresh)
    ns:GetFeature("interface", "windows"):AddWindow(frame)
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
