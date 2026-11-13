-- The damage to come, drawn on the target frame's health bar and on each
-- nameplate's.
--
-- Unit health is secret: addon code can't compare or compute with it, only
-- hand it to a status bar. So an overlay is our own status bar laid exactly
-- over the health bar's fill (anchored to its texture, which spans the health
-- left), with the health bar's own value as its range and the damage to come
-- as its value: from the bar's left end, it covers as much health as the
-- damage will take, the whole fill when the damage would kill: that health
-- shows darkened (its own color and gloss underneath), and a marker shows
-- where it ends: on nameplates the experience bar's rested pip, at its size
-- (their bars are about as tall), centered on the end; on the target frame,
-- whose bar is taller and holds the health text, a thin line. Like Blizzard's
-- heal prediction, the overlay shares the health bar's frame level and draws
-- just above its fill, under the health text.
--
-- Nameplates can't be measured in combat: nothing in the overlay depends on
-- the bar's size (the pip has a fixed size).
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

local SHADE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local SHADE_COLOR = { r = 0, g = 0, b = 0, a = 0.5 }
-- The experience bar's rested pip (ExpBar.xml's ExhaustionTick).
local PIP_ATLAS = "UI-HUD-ExperienceBar-Frame-Pip"
local PIP_WIDTH, PIP_HEIGHT = 10, 14
local LINE_COLOR = { r = 1, g = 1, b = 1, a = 0.6 }
local LINE_WIDTH = 1
-- Draw sublevels range from -8 to 7.
local MAX_SUBLEVEL = 7

-- Overlays, by the health bar they're on (kept with their pooled unit frame).
local overlaysByHealthBar = setmetatable({}, { __mode = "k" })
-- The fill texture each overlay is anchored to.
local anchoredTo = setmetatable({}, { __mode = "k" })
-- The end marker of each overlay.
local markers = setmetatable({}, { __mode = "k" })
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

-- The experience bar's pip, centered on the fill's end, past the bar's edges
-- like on that bar.
local function CreatePip(parent, fill)
    local pip = parent:CreateTexture()
    pip:SetAtlas(PIP_ATLAS)
    pip:SetSize(PIP_WIDTH, PIP_HEIGHT)
    pip:SetPoint("CENTER", fill, "RIGHT")
    return pip
end

-- A thin line along the fill's end, within the bar's shape.
local function CreateLine(parent, fill, mask)
    local line = parent:CreateTexture()
    line:SetColorTexture(LINE_COLOR.r, LINE_COLOR.g, LINE_COLOR.b, LINE_COLOR.a)
    line:SetWidth(LINE_WIDTH)
    line:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    line:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    if mask then
        line:AddMaskTexture(mask)
    end
    return line
end

local function CreateMarker(parent, fill, mask, marker)
    if marker == "pip" then
        return CreatePip(parent, fill)
    end
    return CreateLine(parent, fill, mask)
end

-- `mask`: the health bar's shape, if it has one. `marker`: "pip" or "line".
local function GetOverlay(healthBar, mask, marker)
    local overlay = overlaysByHealthBar[healthBar]
    if not overlay then
        overlay = CreateFrame("StatusBar", nil, healthBar)
        overlay:SetUsingParentLevel(true)
        overlay:SetStatusBarTexture(SHADE_TEXTURE)
        overlay:SetStatusBarColor(SHADE_COLOR.r, SHADE_COLOR.g, SHADE_COLOR.b, SHADE_COLOR.a)
        local fill = overlay:GetStatusBarTexture()
        if mask then
            fill:AddMaskTexture(mask)
        end
        markers[overlay] = CreateMarker(overlay, fill, mask, marker)
        overlay:Hide()
        overlaysByHealthBar[healthBar] = overlay
    end
    return overlay
end

-- Over the health bar's fill, and just above it in its draw layers.
local function AnchorToFill(overlay, fill)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", fill, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    local layer, subLevel = fill:GetDrawLayer()
    overlay:GetStatusBarTexture():SetDrawLayer(layer, math.min(subLevel + 1, MAX_SUBLEVEL))
    markers[overlay]:SetDrawLayer(layer, math.min(subLevel + 2, MAX_SUBLEVEL))
end

local function HideOverlay(healthBar)
    local overlay = overlaysByHealthBar[healthBar]
    if overlay then
        overlay:Hide()
    end
end

-- The damage the player's effects have yet to deal to the unit: none on a
-- dead unit (forgetting its effects) or one that can't be told apart.
local function GetDamage(unit)
    local unitKey = DoTs.Tracker:GetUnitKey(unit)
    if not unitKey then
        return 0
    end
    if UnitIsDead(unit) then
        DoTs.Tracker:Forget(unitKey)
        return 0
    end
    return DoTs.Tracker:GetRemainingDamage(unitKey)
end

-- Shows the damage to come on the unit over its health bar, or hides the
-- overlay when there's none.
local function Update(healthBar, mask, unit, marker)
    local damage = GetDamage(unit)
    if damage <= 0 then
        HideOverlay(healthBar)
        return
    end
    local overlay = GetOverlay(healthBar, mask, marker)
    -- The bar may have been given another texture since.
    local fill = healthBar:GetStatusBarTexture()
    if anchoredTo[overlay] ~= fill then
        anchoredTo[overlay] = fill
        AnchorToFill(overlay, fill)
    end
    -- The bar's value rather than UnitHealth: it is what its fill shows.
    overlay:SetMinMaxValues(0, healthBar:GetValue())
    overlay:SetValue(damage)
    overlay:Show()
end

local function UpdateAll()
    local healthBar, mask = GetTargetHealthBar()
    Update(healthBar, mask, "target", "line")
    for unit, plateHealthBar in pairs(plateHealthBars) do
        Update(plateHealthBar, nil, unit, "pip")
    end
end

-- Follows the effects each frame while any runs.
function Overlays:Refresh()
    if not DoTs:IsActive() then
        return
    end
    DoTs.Tracker:ForgetEnded()
    UpdateAll()
    driver:SetShown(DoTs.Tracker:IsTracking())
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
