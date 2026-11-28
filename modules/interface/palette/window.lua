-- The palette: the typed text over the matching commands, the picked one
-- highlighted, each with the key bound to it.
--
-- The text is an edit box with the keyboard focus while the palette shows:
-- it types, repeats held keys, selects, cuts and pastes on its own, and
-- every key stays its own except Enter, which passes through to the bindings
-- (SetPropagateKeyboardInput from OnKeyDown; measured: the bindings run it
-- after OnEnterPressed). An override binding of Enter, kept on the picked
-- command, makes the game run it from that key press: a binding command, a
-- click of a named button, or a click of our secure button casting a spell
-- (its attribute set as the command is picked). A command running our own
-- code (`run`) is
-- called from the key press instead, the palette closed first. Otherwise the
-- palette closes on the next frame, and its overrides go once Enter is
-- released (buttons may click on the release): measured, the release of a
-- key let through goes to the bindings too, never to the edit box, and
-- IsKeyDown tells instead. Clicking a row only picks it: a click can't reach
-- the bindings. The edit box losing the focus (a click elsewhere) closes the
-- palette.
--
-- Override bindings and key passthrough can't change in combat: combat
-- closes the palette as it starts (PLAYER_REGEN_DISABLED comes just before
-- the lockdown).

local _, ns = ...
local L = ns.L

local Palette = ns:GetFeature("interface", "palette")

local Window = {}
Palette.Window = Window

local WIDTH = 420
local INPUT_HEIGHT = 28
-- Between the typed text and the rows.
local INPUT_GAP = 4
-- From the left of the rows to the text, typed or listed.
local TEXT_INSET = 8
local ROW_HEIGHT = 22
local MAX_ROWS = 8
local PADDING = 8
local MAX_LETTERS = 60
local ENTER_KEYS = { ENTER = true, NUMPADENTER = true }
local RELEASE_TIMEOUT = 1
-- The secure button casting spell commands (click bindings need a global name).
local SPELL_BUTTON = "ForeverEnhancedPaletteSpellButton"

local frame, input, spellButton
local rows = {}
-- The commands offered as the palette opened, as Search entries: { key,
-- title, aliases, order, command }.
local entries = {}
local results = {}
local selected = 1
local offset = 0
-- Set from the key press that opened the palette until the next frame: the
-- character that key typed isn't ours.
local justOpened = false
-- Enter ran a binding or click command: the palette closes on the next frame.
local closing = false
-- After that, the Enter key whose release the overrides wait for, and until when.
local releaseKey
local releaseDeadline = 0
local releaseWatcher

local listener

-- The key bound to the command, as the Key Bindings show it, or "".
local function GetKeyText(command)
    local binding = command.binding or (command.click and "CLICK " .. command.click .. ":LeftButton")
    local key = binding and GetBindingKey(binding)
    return key and GetBindingText(key, 1) or ""
end

local function GetSelected()
    return results[selected]
end

-- Enter runs the picked command: the game's binding or click, from the key press.
local function SyncOverride()
    ClearOverrideBindings(frame)
    local entry = GetSelected()
    local command = entry and entry.command
    if not command or command.run then
        return
    end
    local click = command.click
    if command.spellID then
        spellButton:SetAttribute("spell", command.spellID)
        click = SPELL_BUTTON
    end
    for key in pairs(ENTER_KEYS) do
        if command.binding then
            SetOverrideBinding(frame, true, key, command.binding)
        else
            SetOverrideBindingClick(frame, true, key, click, "LeftButton")
        end
    end
end

local function Draw()
    local shown = math.max(1, math.min(#results, MAX_ROWS))
    for index, row in ipairs(rows) do
        local entry = results[offset + index]
        row:SetShown(index <= shown)
        row:EnableMouse(entry ~= nil)
        if entry then
            row.Title:SetText(entry.title)
            row.Title:SetTextColor(1, 1, 1)
            row.Key:SetText(GetKeyText(entry.command))
        else
            row.Title:SetText(L["interface.palette.noResults"])
            row.Title:SetTextColor(0.5, 0.5, 0.5)
            row.Key:SetText("")
        end
        row.Selected:SetShown(entry ~= nil and offset + index == selected)
    end
    frame:SetHeight(INPUT_HEIGHT + INPUT_GAP + shown * ROW_HEIGHT + PADDING * 2)
    frame.Placeholder:SetShown(input:GetText() == "")
end

local function Select(index)
    if #results == 0 then
        return
    end
    selected = (index - 1) % #results + 1
    if selected <= offset then
        offset = selected - 1
    elseif selected > offset + MAX_ROWS then
        offset = selected - MAX_ROWS
    end
    Draw()
    SyncOverride()
end

-- Ranks the commands for the typed text, the best one picked.
local function Update()
    results = Palette.Search:Rank(entries, input:GetText(), Palette.Store:GetLastRun())
    selected = 1
    offset = 0
    Draw()
    SyncOverride()
end

-- The key as bindings name it, with the modifiers held ("CTRL-K").
local function WithModifiers(key)
    return (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. key
end

local function IsPaletteKey(key)
    local pressed = WithModifiers(key)
    for _, bound in ipairs({ GetBindingKey(Palette.BINDING) }) do
        if bound == pressed then
            return true
        end
    end
    return false
end

local function HasModifier()
    return IsAltKeyDown() or IsControlKeyDown() or IsShiftKeyDown()
end

-- The overrides go once the Enter key that ran the command is up (or after
-- RELEASE_TIMEOUT, a release missed).
local function WatchRelease()
    if IsKeyDown(releaseKey) and GetTime() < releaseDeadline then
        return
    end
    Window:Close()
end

-- After Enter ran a binding or click command: the palette goes, the
-- overrides stay until the key is up.
local function HideForRelease()
    if not closing then
        return
    end
    frame:Hide() -- closing still set: the edit box losing the focus leaves the overrides
    closing = false
    releaseWatcher:Show()
end

-- Enter: the game runs a binding or click command once the key passes
-- through, our own code runs from here.
local function Run(key)
    local entry = GetSelected()
    if not entry then
        return false
    end
    Palette.Store:Remember(entry.key)
    if entry.command.run then
        Window:Close()
        securecallfunction(entry.command.run)
        return false
    end
    closing = true
    releaseKey = key
    releaseDeadline = GetTime() + RELEASE_TIMEOUT
    C_Timer.After(0, HideForRelease)
    return true
end

-- Held keys come again as they repeat.
local function OnKeyDown(self, key)
    local passThrough = false
    if closing then
        passThrough = false
    elseif ENTER_KEYS[key] and not HasModifier() then
        passThrough = Run(key)
    elseif IsPaletteKey(key) then
        Window:Close()
    elseif key == "UP" or (key == "TAB" and IsShiftKeyDown()) then
        Select(selected - 1)
    elseif key == "DOWN" or key == "TAB" then
        Select(selected + 1)
    end
    self:SetPropagateKeyboardInput(passThrough)
end

local function OnTextChanged(self, userInput)
    if not userInput then
        return
    end
    if justOpened then
        self:SetText("")
    end
    Update()
end

local function OnFocusLost()
    if Window:IsShown() and not closing then
        Window:Close()
    end
end

local function OnMouseWheel(_, delta)
    Select(selected - delta)
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, frame)
    local top = PADDING + INPUT_HEIGHT + INPUT_GAP + (index - 1) * ROW_HEIGHT
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -top)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -top)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local selectedTexture = row:CreateTexture(nil, "BACKGROUND")
    selectedTexture:SetAllPoints()
    selectedTexture:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    selectedTexture:SetBlendMode("ADD")
    row.Selected = selectedTexture

    local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("LEFT", row, "LEFT", TEXT_INSET, 0)
    title:SetJustifyH("LEFT")
    row.Title = title

    local key = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    key:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    key:SetJustifyH("RIGHT")
    row.Key = key
    title:SetPoint("RIGHT", key, "LEFT", -8, 0)

    -- Pointing at a row picks it; Enter runs it (a click can't reach the bindings).
    local function Pick()
        Select(offset + index)
    end
    row:SetScript("OnEnter", Pick)
    row:SetScript("OnClick", Pick)
    return row
end

local function Create()
    frame = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
    frame:Hide()
    frame:SetWidth(WIDTH)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -160)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", OnMouseWheel)

    -- The typed text, in the rows' font, centered in its band and lined up
    -- with the rows' titles.
    input = CreateFrame("EditBox", nil, frame)
    input:SetHeight(INPUT_HEIGHT)
    input:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    input:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -PADDING)
    input:SetFontObject(GameFontHighlight)
    input:SetTextInsets(TEXT_INSET, TEXT_INSET, 0, 0)
    input:SetAutoFocus(false)
    input:SetMaxLetters(MAX_LETTERS)
    input:SetScript("OnKeyDown", OnKeyDown)
    input:SetScript("OnTextChanged", OnTextChanged)
    input:SetScript("OnEscapePressed", function()
        Window:Close()
    end)
    input:SetScript("OnEditFocusLost", OnFocusLost)

    local placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", input, "LEFT", TEXT_INSET + 2, 0)
    placeholder:SetText(L["interface.palette.placeholder"])
    frame.Placeholder = placeholder

    for index = 1, MAX_ROWS do
        rows[index] = CreateRow(index)
    end

    releaseWatcher = CreateFrame("Frame", nil, UIParent)
    releaseWatcher:Hide()
    releaseWatcher:SetScript("OnUpdate", WatchRelease)

    -- Built out of combat, as the palette only opens then; never shown: a
    -- click binding needs no visible button. Casts on Enter going down.
    spellButton = CreateFrame("Button", SPELL_BUTTON, UIParent, "SecureActionButtonTemplate")
    spellButton:RegisterForClicks("LeftButtonDown")
    spellButton:SetAttribute("useOnKeyDown", true)
    spellButton:SetAttribute("type", "spell")
end

function Window:IsShown()
    return frame ~= nil and frame:IsShown()
end

-- The keys of the commands listed, best first, and the picked one's (for tests).
function Window:GetResults()
    local keys = {}
    for _, entry in ipairs(results) do
        table.insert(keys, entry.key)
    end
    local picked = GetSelected()
    return keys, picked and picked.key
end

function Window:Open()
    if self:IsShown() or InCombatLockdown() then
        return
    end
    if not frame then
        Create()
    end
    self:Close() -- overrides still waiting for a release
    closing = false
    input:SetText("")
    entries = Palette.Search:GetEntries()
    Update()
    frame:Show()
    input:SetFocus()
    justOpened = true
    C_Timer.After(0, function()
        justOpened = false
    end)
    listener:Start()
end

-- Closes the palette, or ends the wait for Enter's release: the overrides go.
function Window:Close()
    closing = false
    if not frame or not (frame:IsShown() or releaseWatcher:IsShown()) then
        return
    end
    listener:Stop()
    releaseWatcher:Hide()
    ClearOverrideBindings(frame)
    frame:Hide()
    input:ClearFocus()
    entries, results = {}, {}
end

function Window:Toggle()
    if self:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

listener = ns:CreateEventListener({
    PLAYER_REGEN_DISABLED = function()
        Window:Close()
    end,
    -- The palette takes the movement keys: moving by mouse (both buttons,
    -- click to move) leaves it.
    PLAYER_STARTED_MOVING = function()
        Window:Close()
    end,
    LOADING_SCREEN_ENABLED = function()
        Window:Close()
    end,
})
