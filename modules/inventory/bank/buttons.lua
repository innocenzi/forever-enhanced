-- Deposit and Withdraw buttons in the bank's bottom strip, styled and sized
-- like the bank's gold Deposit/Withdraw buttons. Each opens a menu with the two
-- transfer modes, disabled while a transfer runs.

local _, ns = ...

local L = ns.L
local Transfers = ns:GetFeature("inventory", "bank").Transfers

local Buttons = {}
Transfers.Buttons = Buttons

local BUTTON_WIDTH, BUTTON_HEIGHT = 105, 21
local MODES = { "stacks", "all" }

local buttons

local function AddEntry(rootDescription, direction, mode)
    local entry = rootDescription:CreateButton(L["inventory.bank.transfers." .. mode], function()
        Transfers:Run(direction, mode)
    end)
    entry:SetEnabled(not Transfers:IsRunning())
end

-- Deposit also moves the items marked for the bank, while that mark is on
-- (Item marks, loaded after this slice).
local function GenerateMenu(direction)
    return function(_, rootDescription)
        for _, mode in ipairs(MODES) do
            AddEntry(rootDescription, direction, mode)
        end
        if direction == "deposit" and ns:GetFeature("inventory", "marks"):IsPartActive("bank") then
            AddEntry(rootDescription, direction, "marked")
        end
    end
end

local function CreateButton(direction)
    local button = CreateFrame("Button", nil, BankFrame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetText(L["inventory.bank.transfers." .. direction])
    button:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, GenerateMenu(direction))
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["inventory.bank.transfers." .. direction .. ".tooltip"])
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
    buttons = { deposit, withdraw }
end

function Buttons:Enable()
    if not buttons then
        CreateButtons()
    end
    for _, button in ipairs(buttons) do
        button:Show()
    end
end

function Buttons:Disable()
    for _, button in ipairs(buttons) do
        button:Hide()
    end
end
