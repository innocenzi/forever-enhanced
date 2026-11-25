-- The damage to come, drawn on the target frame's health bar and on each
-- nameplate's.
--
-- Unit health is secret: addon code can't compare or compute with it, only
-- hand it to a status bar. So an overlay is our own status bar laid exactly
-- over the health bar's fill (anchored to its texture, which spans the health
-- left), with the health bar's own value as its range and the damage to come
-- as its value.
--
-- The ticks' damage grows from the bar's left end: it covers as much health
-- as the ticks will take, the whole fill when they would kill, so the player
-- sees when the health left reaches it. That health shows animated, up to a
-- flare (tickbar.lua).
--
-- What marks will deal (Death Mark) grows from the health's end leftward: the
-- health its hit will remove, darkened. It is a second bar over the overlay
-- (markbar.lua), and draws above the ticks' part where they meet.
--
-- Like Blizzard's heal prediction, the overlay shares the health bar's frame
-- level and draws just above its fill, under the health text.
--
-- Nameplates can't be measured in combat: nothing in the overlay depends on
-- the bar's size.
--
-- The fill moves with each health change: while any effect runs, every
-- overlay follows its unit each frame.
--
-- Unit frames are pooled apart from plates: a plate's unit frame (and its
-- health bar, with our overlay) is released as its unit is removed, before we
-- hear of it, then shows another unit on another plate. So the health bars
-- shown are tracked by nameplate token, from the plates' events.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local Overlays = {}
DoTs.Overlays = Overlays

-- How the ticks' part is drawn: `inset`, how far the inside of the health bar's
-- art is from its edges; `height`, about how tall that inside is; `color`, the
-- art's, when the bar's own color doesn't tell it (the target frame's art is
-- green).
local TARGET_STYLE = {
    inset = 4,
    height = 12,
    color = { r = 0.55, g = 1, b = 0.25 },
}
local PLATE_STYLE = {
    inset = 1,
    height = 18,
}

-- Overlays, by the health bar they're on (kept with their pooled unit frame).
local overlaysByHealthBar = setmetatable({}, { __mode = "k" })
-- The fill texture each overlay is anchored to.
local anchoredTo = setmetatable({}, { __mode = "k" })
-- Nameplate token -> the health bar of its unit frame.
local plateHealthBars = {}

local driver

local function GetTargetHealthBar()
    local container = TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer
    return container.HealthBar, container.HealthBarMask
end

local function GetPlateHealthBar(plate)
    return plate.UnitFrame and plate.UnitFrame.HealthBarsContainer.healthBar
end

-- `mask`: the health bar's shape, if it has one.
local function GetOverlay(healthBar, mask, style)
    local overlay = overlaysByHealthBar[healthBar]
    if not overlay then
        overlay = CreateFrame("StatusBar", nil, healthBar)
        overlay:SetUsingParentLevel(true)
        DoTs.TickBar:SetUp(overlay, healthBar, mask, style)
        DoTs.MarkBar:Create(overlay, mask)
        overlay:Hide()
        overlaysByHealthBar[healthBar] = overlay
    end
    return overlay
end

-- Over the health bar's fill, and just above it in its draw layers: the
-- ticks' part, then what marks will deal.
local function AnchorToFill(overlay, fill)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", fill, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    local layer, subLevel = fill:GetDrawLayer()
    local markSubLevel = DoTs.TickBar:SetDrawLayer(overlay, layer, subLevel + 1)
    DoTs.MarkBar:SetDrawLayer(overlay, layer, markSubLevel)
end

local function HideOverlay(healthBar)
    local overlay = overlaysByHealthBar[healthBar]
    if overlay then
        overlay:Hide()
    end
end

-- The damage the player's effects and the group's shared ones have yet to deal
-- to the unit, their ticks' and what marks will deal: none on a dead unit
-- (forgetting its effects) or one that can't be told apart.
local function GetDamage(unit)
    local unitKey = DoTs.Tracker:GetUnitKey(unit)
    if not unitKey then
        return 0, 0
    end
    if UnitIsDead(unit) then
        DoTs.Tracker:Forget(unitKey)
        DoTs.Sharing:Forget(unitKey)
        return 0, 0
    end
    local ticks, stored = DoTs.Tracker:GetRemainingDamage(unitKey)
    local sharedTicks, sharedStored = DoTs.Sharing:GetRemainingDamage(unitKey)
    return ticks + sharedTicks, stored + sharedStored
end

-- Shows the damage to come on the unit over its health bar, or hides the
-- overlay when there's none: the ticks' from the left end, what marks will
-- deal from the health's end.
local function Update(healthBar, mask, unit, style)
    local ticks, stored = GetDamage(unit)
    if ticks <= 0 and stored <= 0 then
        HideOverlay(healthBar)
        return
    end
    local overlay = GetOverlay(healthBar, mask, style)
    -- The bar may have been given another texture since.
    local fill = healthBar:GetStatusBarTexture()
    if anchoredTo[overlay] ~= fill then
        anchoredTo[overlay] = fill
        AnchorToFill(overlay, fill)
    end
    -- The bar's value rather than UnitHealth: it is what its fill shows.
    local health = healthBar:GetValue()
    DoTs.TickBar:Update(overlay, health, ticks)
    DoTs.MarkBar:Update(overlay, health, stored)
    overlay:Show()
end

local function UpdateAll()
    local healthBar, mask = GetTargetHealthBar()
    Update(healthBar, mask, "target", TARGET_STYLE)
    for unit, plateHealthBar in pairs(plateHealthBars) do
        Update(plateHealthBar, nil, unit, PLATE_STYLE)
    end
end

-- Follows the effects each frame while any runs.
function Overlays:Refresh()
    if not DoTs:IsActive() then
        return
    end
    DoTs.Tracker:ForgetEnded()
    DoTs.Sharing:ForgetEnded()
    UpdateAll()
    driver:SetShown(DoTs.Tracker:IsTracking() or DoTs.Sharing:IsTracking())
end

local listener = ns:CreateEventListener({
    PLAYER_TARGET_CHANGED = function()
        Overlays:Refresh()
    end,
    NAME_PLATE_UNIT_ADDED = function(_, unit)
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        plateHealthBars[unit] = plate and GetPlateHealthBar(plate)
        Overlays:Refresh()
    end,
    -- The plate's unit frame is already released. The target frame may follow
    -- a unit told apart by its plate (Tracker:GetUnitKey).
    NAME_PLATE_UNIT_REMOVED = function(_, unit)
        local healthBar = plateHealthBars[unit]
        plateHealthBars[unit] = nil
        if healthBar then
            HideOverlay(healthBar)
        end
        Overlays:Refresh()
    end,
})

function Overlays:Enable()
    if not driver then
        driver = CreateFrame("Frame", nil, UIParent)
        driver:Hide()
        driver:SetScript("OnUpdate", function()
            Overlays:Refresh()
        end)
    end
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate:GetUnit()
        if unit then
            plateHealthBars[unit] = GetPlateHealthBar(plate)
        end
    end
    listener:Start()
    self:Refresh()
end

function Overlays:Disable()
    listener:Stop()
    if driver then
        driver:Hide()
    end
    plateHealthBars = {}
    for _, overlay in pairs(overlaysByHealthBar) do
        overlay:Hide()
    end
end
