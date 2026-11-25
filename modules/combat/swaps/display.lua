-- While a replacement can be cast, the buttons showing its original show its
-- icon and a proc glow: our own frames over Blizzard's buttons, which also work
-- in combat. Not while short of power nor on a cooldown, the global one
-- included: a key pressed then may cast the original (see feature.lua). Our
-- icon covers the button's cooldown swipe, which is the original's.

local _, ns = ...

local Swaps = ns:GetFeature("combat", "swaps")
local Buttons = Swaps.Buttons

local Display = {}
Swaps.Display = Display

-- Cooldown times are secret in combat and the end of the global cooldown has no
-- event of its own: look again this often (seconds) while one hides a
-- replacement.
local COOLDOWN_CHECK_INTERVAL = 0.05

-- How long (seconds) a cooldown must last to hide a replacement already shown:
-- a cast the server refuses (not behind the target) starts the global cooldown,
-- cleared by its answer, and would blink it (measured: about 0.1 s, 0.22 s for
-- a press and its release refused one after the other).
local COOLDOWN_GRACE = 0.35

local visuals = setmetatable({}, { __mode = "k" }) -- Blizzard button -> our frame
local scheduled = false
local cooldownTimer -- while a cooldown hides a replacement, or is about to

local function GetVisual(button)
    local visual = visuals[button]
    if visual then
        return visual
    end
    visual = CreateFrame("Frame", nil, button)
    visual:SetAllPoints(Buttons:GetIcon(button))
    visual:SetFrameLevel(Buttons:GetCooldownLevel(button) + 1)
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

local function Show(button, swap, onCooldown)
    local visual = GetVisual(button)
    visual.cooldownSince = onCooldown and (visual.cooldownSince or GetTime()) or nil
    visual.Icon:SetTexture(C_Spell.GetSpellTexture(swap.replacement))
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

-- Whether the replacement on the button stays shown on a cooldown.
local function IsInGrace(button)
    local visual = visuals[button]
    if not visual or not visual:IsShown() then
        return false
    end
    return not visual.cooldownSince or GetTime() - visual.cooldownSince < COOLDOWN_GRACE
end

local ScheduleUpdate

local function CheckCooldownSoon()
    if cooldownTimer or not Swaps:IsActive() then
        return
    end
    cooldownTimer = C_Timer.NewTimer(COOLDOWN_CHECK_INTERVAL, function()
        cooldownTimer = nil
        ScheduleUpdate()
    end)
end

local function Update()
    scheduled = false
    local anyOnCooldown = false
    for _, entry in ipairs(Buttons:Enumerate()) do
        local button = entry.button
        local swap = Buttons:GetShownSwap(button)
        local usable = swap ~= nil and Swaps:IsReplacementUsable(swap)
        local onCooldown = usable and Swaps:IsReplacementOnCooldown(swap)
        if usable and (not onCooldown or IsInGrace(button)) then
            Show(button, swap, onCooldown)
        else
            Hide(button)
        end
        anyOnCooldown = anyOnCooldown or onCooldown
    end
    if anyOnCooldown then
        CheckCooldownSoon()
    end
end

-- Blizzard's buttons update their `action` on the same events: look once
-- they did, once a frame.
function ScheduleUpdate()
    if not scheduled then
        scheduled = true
        C_Timer.After(0, Update)
    end
end

local listener = ns:CreateEventListener({
    SPELL_UPDATE_USABLE = ScheduleUpdate,
    SPELL_UPDATE_COOLDOWN = ScheduleUpdate,
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
    if cooldownTimer then
        cooldownTimer:Cancel()
        cooldownTimer = nil
    end
    for button in pairs(visuals) do
        Hide(button)
    end
end
