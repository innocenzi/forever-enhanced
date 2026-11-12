-- Deposit and Withdraw buttons in the bank's bottom strip, styled and sized
-- like the bank's gold Deposit/Withdraw buttons. Each opens a menu with the
-- transfer modes, disabled while a transfer runs or when they would move nothing.
-- A button with nothing to move is disabled, its tooltip saying so. It follows
-- the bags and the bank, and marks and locks, which have no event but redraw the
-- item buttons: our item button handler re-checks once a frame after that.

local _, ns = ...

local L = ns.L
local Bank = ns:GetFeature("inventory", "bank")
local Transfers = Bank.Transfers

local Buttons = {}
Transfers.Buttons = Buttons

local BUTTON_WIDTH, BUTTON_HEIGHT = 105, 21

-- Transfer modes per direction, in menu order.
local MODES = {
    deposit = { "all", "stacks" },
    withdraw = { "stacks", "all" },
}

-- Per direction: its button, once created.
local buttons
local updateRequested = false

-- The modes a direction's menu lists. Deposit also moves the items marked for
-- the bank, while that mark is on (Item marks, loaded after this slice).
local function GetModes(direction)
    local modes = { unpack(MODES[direction]) }
    if direction == "deposit" and ns:GetFeature("inventory", "marks"):IsPartActive("bank") then
        table.insert(modes, "marked")
    end
    return modes
end

local function HasMoves(direction, mode)
    return #Transfers.Planner:Plan(direction, mode) > 0
end

local function CanTransfer(direction)
    for _, mode in ipairs(GetModes(direction)) do
        if HasMoves(direction, mode) then
            return true
        end
    end
    return false
end

-- Only while they show: at the bank, with transfers on.
local function UpdateButtons()
    if not buttons.deposit:IsVisible() then
        return
    end
    for direction, button in pairs(buttons) do
        button:SetEnabled(CanTransfer(direction))
    end
end

local function RequestUpdate()
    if updateRequested then
        return
    end
    updateRequested = true
    C_Timer.After(0, function()
        updateRequested = false
        UpdateButtons()
    end)
end

local listener = ns:CreateEventListener({
    BANKFRAME_OPENED = UpdateButtons,
    BAG_UPDATE_DELAYED = UpdateButtons,
    PLAYERBANKSLOTS_CHANGED = UpdateButtons,
})

local function GenerateMenu(direction)
    return function(_, rootDescription)
        for _, mode in ipairs(GetModes(direction)) do
            local entry = rootDescription:CreateButton(L["inventory.bank.transfers." .. mode], function()
                Transfers:Run(direction, mode)
            end)
            entry:SetEnabled(not Transfers:IsRunning() and HasMoves(direction, mode))
        end
    end
end

local function CreateButton(direction)
    local button = CreateFrame("Button", nil, BankFrame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetText(L["inventory.bank.transfers." .. direction])
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, GenerateMenu(direction))
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["inventory.bank.transfers." .. direction .. ".tooltip"])
        if not self:IsEnabled() then
            GameTooltip_AddErrorLine(GameTooltip, L["inventory.bank.transfers." .. direction .. ".nothing"])
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

-- [Deposit][Withdraw] at the bottom left: the bank's money frame takes the right.
local function CreateButtons()
    local deposit = CreateButton("deposit")
    deposit:SetPoint("BOTTOMLEFT", BankFrame, "BOTTOMLEFT", 6, 4)
    local withdraw = CreateButton("withdraw")
    withdraw:SetPoint("LEFT", deposit, "RIGHT", 1, 0)
    buttons = { deposit = deposit, withdraw = withdraw }
end

function Buttons:Enable()
    if not buttons then
        CreateButtons()
    end
    for _, button in pairs(buttons) do
        button:Show()
    end
    listener:Start()
    UpdateButtons()
end

function Buttons:Disable()
    listener:Stop()
    for _, button in pairs(buttons) do
        button:Hide()
    end
end

ns:AddItemButtonHandler(Bank, {
    part = "transfers",
    Update = RequestUpdate,
})
