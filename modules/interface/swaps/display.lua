-- While a replacement can be cast, the buttons showing its original show its
-- icon and a proc glow (our own frames over Blizzard's buttons). This follows
-- the same test as the cast itself, so it also works in combat.

local _, ns = ...

local Swaps = ns:GetFeature("interface", "swaps")
local Buttons = Swaps.Buttons

local Display = {}
Swaps.Display = Display

local visuals = setmetatable({}, { __mode = "k" }) -- Blizzard button -> our frame
local scheduled = false

local function GetVisual(button)
    local visual = visuals[button]
    if visual then
        return visual
    end
    visual = CreateFrame("Frame", nil, button)
    visual:SetAllPoints(button.icon or button)
    -- Under the button's cooldown swipe, over its icon.
    visual:SetFrameLevel(button:GetFrameLevel())
    visual.Icon = visual:CreateTexture(nil, "ARTWORK")
    visual.Icon:SetAllPoints()
    visual.Glow = CreateFrame("Frame", nil, visual, "ActionButtonSpellAlertTemplate")
    local width, height = button:GetSize()
    visual.Glow:SetSize(width * 1.4, height * 1.4)
    visual.Glow:SetPoint("CENTER", button, "CENTER")
    visual:Hide()
    visuals[button] = visual
    return visual
end

-- Tinted like Blizzard's icons (UpdateUsable): blue while short of energy.
local function Show(button, swap, usable)
    local visual = GetVisual(button)
    visual.Icon:SetTexture(C_Spell.GetSpellTexture(swap.replacement))
    if usable then
        visual.Icon:SetVertexColor(1, 1, 1)
    else
        visual.Icon:SetVertexColor(0.5, 0.5, 1)
    end
    if not visual:IsShown() then
        visual:Show()
        visual.Glow:Show()
        visual.Glow.ProcStartAnim:Play()
    end
end

local function Hide(button)
    local visual = visuals[button]
    if visual and visual:IsShown() then
        visual.Glow.ProcStartAnim:Stop()
        visual.Glow:Hide()
        visual:Hide()
    end
end

local function Update()
    scheduled = false
    for _, entry in ipairs(Buttons:Enumerate()) do
        local button = entry.button
        local swap = Buttons:GetShownSwap(button)
        -- Short of energy still counts, as Blizzard's buttons only dim then.
        local usable, noPower
        if swap then
            usable, noPower = Swaps:CanCastReplacement(swap)
        end
        if usable or noPower then
            Show(button, swap, usable)
        else
            Hide(button)
        end
    end
end

-- Blizzard's buttons update their `action` on the same events: look once
-- they did, once a frame.
local function ScheduleUpdate()
    if not scheduled then
        scheduled = true
        C_Timer.After(0, Update)
    end
end

local listener = ns:CreateEventListener({
    SPELL_UPDATE_USABLE = ScheduleUpdate,
    ACTION_USABLE_CHANGED = ScheduleUpdate,
    UNIT_AURA = function(_, unit)
        if unit == "player" then
            ScheduleUpdate()
        end
    end,
    -- Energy coming back may not change a slot's usability (Ambush sits on
    -- the Stealth bar, out of view): follow the power itself.
    UNIT_POWER_FREQUENT = function(_, unit)
        if unit == "player" then
            ScheduleUpdate()
        end
    end,
    ACTIONBAR_SLOT_CHANGED = ScheduleUpdate,
    ACTIONBAR_PAGE_CHANGED = ScheduleUpdate,
    UPDATE_BONUS_ACTIONBAR = ScheduleUpdate,
    UPDATE_SHAPESHIFT_FORM = ScheduleUpdate,
    UPDATE_OVERRIDE_ACTIONBAR = ScheduleUpdate,
    UPDATE_VEHICLE_ACTIONBAR = ScheduleUpdate,
    SPELLS_CHANGED = ScheduleUpdate,
})

function Display:Enable()
    listener:Start()
    ScheduleUpdate()
end

function Display:Refresh()
    ScheduleUpdate()
end

function Display:Disable()
    listener:Stop()
    for button in pairs(visuals) do
        Hide(button)
    end
end
