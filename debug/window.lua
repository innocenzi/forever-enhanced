-- /fedebug: the log in a window, selected for Ctrl+C. /fedebug clear empties it.

local _, ns = ...

local FRAME_NAME = "ForeverEnhancedDebugFrame" -- UISpecialFrames needs a name
local WIDTH, HEIGHT = 820, 560

local frame
local shownText = ""
local currentOnly = false

local function Refresh()
    -- Doubled pipes keep color codes and links as plain text.
    shownText = ns:FormatLog(currentOnly):gsub("|", "||")
    frame.EditBox:SetText(shownText)
    frame.EditBox:SetFocus()
    frame.EditBox:HighlightText()
    frame.Scope:SetText(currentOnly and "All sessions" or "This session")
    C_Timer.After(0, function()
        frame.Scroll:SetVerticalScroll(frame.Scroll:GetVerticalScrollRange())
    end)
end

local function CreateButton(text, onClick)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function BuildFrame()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "PortraitFrameTemplate")
    frame:Hide()
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetTitle("Forever Enhanced Debug")
    frame:SetPortraitToAsset("Interface\\AddOns\\ForeverEnhanced\\media\\icon")
    table.insert(UISpecialFrames, FRAME_NAME)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", 66, -34)
    hint:SetText("Ctrl+C copies the selected log. It is kept across reloads and sessions.")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    frame.Scroll = scroll

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(WIDTH - 14 - 32)
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    -- Read-only: typing puts the log back.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(shownText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)
    frame.EditBox = editBox

    local refresh = CreateButton("Refresh", Refresh)
    refresh:SetPoint("BOTTOMRIGHT", -10, 10)
    local clear = CreateButton("Clear", function()
        ns:Clear()
        Refresh()
    end)
    clear:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
    local selectAll = CreateButton("Select all", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectAll:SetPoint("RIGHT", clear, "LEFT", -6, 0)
    local scope = CreateButton("This session", function()
        currentOnly = not currentOnly
        Refresh()
    end)
    scope:SetPoint("BOTTOMLEFT", 10, 10)
    frame.Scope = scope
end

SLASH_FOREVERENHANCEDDEBUG1 = "/fedebug"
SlashCmdList.FOREVERENHANCEDDEBUG = function(message)
    if strtrim(message):lower() == "clear" then
        ns:Clear()
        ns:Print("log cleared.")
        return
    end
    if not frame then
        BuildFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        Refresh()
    end
end
