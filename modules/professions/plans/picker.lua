-- The number of crafts picker, built like the merchant's stack picker
-- (StackSplitFrame, Blizzard_FrameXML/Camelot/StackSplitFrame.xml): the count
-- between arrows, Okay and Cancel. The count is an edit box, focused on open:
-- typing replaces it, Enter accepts, Escape closes; the wheel and the arrows
-- step it. It closes when what it was opened on hides.
--
-- Our own frame, never Blizzard's StackSplitFrame: our code would write its
-- fields, and the bags' and merchant's splits would run tainted after that.

local _, ns = ...

local Plans = ns:GetFeature("professions", "plans")

local Picker = {}
Plans.Picker = Picker

-- UISpecialFrames closes it with Escape, by name.
local NAME = "ForeverEnhancedCraftCountPicker"
local WIDTH, HEIGHT = 172, 96
local ARROW_SIZE = 16
local BUTTON_WIDTH, BUTTON_HEIGHT = 64, 24
local COUNT_WIDTH, COUNT_HEIGHT = 80, 20

local frame
-- The open picker: { anchor, onAccept }.
local current

local function GetCount()
    return tonumber(frame.Count:GetText()) or 0
end

-- Enables the arrows that can step `count`.
local function UpdateArrows(count)
    frame.LeftButton:SetEnabled(count > 1)
    frame.RightButton:SetEnabled(count < Plans.MAX_COUNT)
end

-- Shows `count`, clamped to the picker's range.
local function SetCount(count)
    count = math.max(1, math.min(count, Plans.MAX_COUNT))
    frame.Count:SetText(tostring(count))
    UpdateArrows(count)
end

local function Step(delta)
    SetCount(GetCount() + delta)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

local function Accept()
    local accepted = current
    local count = GetCount()
    frame:Hide()
    if accepted then
        accepted.onAccept(count)
    end
end

local function CreateArrow(direction, offsetX)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(ARROW_SIZE, ARROW_SIZE)
    local point = direction == "Left" and "RIGHT" or "LEFT"
    button:SetPoint(point, frame, "CENTER", offsetX, 18)
    button:SetNormalTexture("Interface\\MoneyFrame\\Arrow-" .. direction .. "-Up")
    button:SetPushedTexture("Interface\\MoneyFrame\\Arrow-" .. direction .. "-Down")
    button:SetDisabledTexture("Interface\\MoneyFrame\\Arrow-" .. direction .. "-Disabled")
    button:SetScript("OnClick", function()
        Step(direction == "Left" and -1 or 1)
    end)
    return button
end

local function CreateButton(text, point, offsetX, onClick)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetPoint(point, frame, "BOTTOM", offsetX, 32)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function Create()
    frame = CreateFrame("Frame", NAME, UIParent)
    frame:Hide()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        Step(delta)
    end)
    frame:SetScript("OnHide", function()
        current = nil
    end)
    frame:SetScript("OnUpdate", function(self)
        if current and not current.anchor:IsVisible() then
            self:Hide()
        end
    end)
    table.insert(UISpecialFrames, NAME)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture("Interface\\MoneyFrame\\UI-MoneyFrame")
    background:SetTexCoord(0, 0.671875, 0, 0.75)

    local count = CreateFrame("EditBox", nil, frame)
    count:SetSize(COUNT_WIDTH, COUNT_HEIGHT)
    count:SetPoint("RIGHT", frame, "RIGHT", -50, 18)
    count:SetFontObject(GameFontHighlight)
    count:SetJustifyH("RIGHT")
    count:SetAutoFocus(false)
    count:SetNumeric(true)
    count:SetMaxLetters(#tostring(Plans.MAX_COUNT))
    count:SetScript("OnEnterPressed", Accept)
    count:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    count:SetScript("OnTextChanged", function(_, userInput)
        if userInput then
            UpdateArrows(GetCount())
        end
    end)
    frame.Count = count

    frame.LeftButton = CreateArrow("Left", -59)
    frame.RightButton = CreateArrow("Right", 64)
    frame.OkayButton = CreateButton(OKAY, "RIGHT", -3, Accept)
    frame.CancelButton = CreateButton(CANCEL, "LEFT", 5, function()
        frame:Hide()
    end)
end

-- Opens the picker above `anchor` at `count`; Okay calls onAccept(count) (0
-- when the player typed it). Opening it again moves it.
function Picker:Open(anchor, count, onAccept)
    if not frame then
        Create()
    end
    frame:Hide()
    current = { anchor = anchor, onAccept = onAccept }
    SetCount(count)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT")
    frame:Show()
    frame.Count:SetFocus()
    frame.Count:HighlightText()
end

function Picker:Close()
    if frame then
        frame:Hide()
    end
end
