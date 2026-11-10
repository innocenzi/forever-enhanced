-- On Forever, combo points are held per unit: points built on one mob stay on
-- it while the player builds more on another, targeted or not, and
-- GetComboPoints("player", unit) reads each mob's. So every nameplate whose
-- unit holds points gets its own bar, taken from a pool and given back when
-- the unit has none left or the plate goes away (plates are recycled).
-- A bar sits right under the health bar, centered on it (not on the level
-- badge beside it). The cast bar shows in the space below the health bar, so
-- while it's up the points move below the cast bar area. Its visibility is
-- polled from the bar's own frame while shown rather than hooked, since
-- Blizzard's plates are pooled and hooks can't be removed. Plate regions
-- can't be measured in combat, so both spots are built from anchors only.
-- The points are Blizzard's RogueComboPointTemplate, the one the combo arc
-- around the target frame portrait is built from.
-- Points can run out on a unit that isn't the target without an event we
-- could catch, so in combat every plate is checked again on a slow ticker.

local _, ns = ...

local ComboPoints = ns:GetFeature("interface", "combopoints")

local Bars = {}
ComboPoints.Bars = Bars

local MAX_POINTS = 5
local POINT_SIZE = 20
local POINT_SPACING = 4
local SCALE = 0.5
-- Gap under the health bar, in the bar's own (scaled) units.
local OFFSET_Y = -6
local COMBAT_TICK_SECONDS = 1

local combatTicker

-- Bars shown, by the Blizzard plate they're on, and bars free for reuse.
local barsByPlate = setmetatable({}, { __mode = "k" })
local freeBars = {}

local BarMixin = {}

-- The health bar's border is drawn past its frame, and the target highlight
-- past the border: the points go under the highlight, which is centered on
-- the health bar. The cast bar area spans the whole plate, level badge
-- included, so the spot below it takes its height from the area and its
-- horizontal center from the highlight: `left` and `right` each reach from a
-- bottom corner of the highlight to the area's opposite bottom corner, and
-- `belowCastBars` spans from the bottom left of one to the bottom right of
-- the other.
local function AnchorBelowCastBars(bar)
    local unitFrame = bar.plate.UnitFrame
    local highlight = unitFrame.HealthBarsContainer.healthBar.selectedBorder
    local castBars = unitFrame.CastBarsContainer
    local left, right, belowCastBars = bar.left, bar.right, bar.belowCastBars
    for _, frame in ipairs({ left, right, belowCastBars }) do
        frame:SetParent(bar.plate)
        frame:ClearAllPoints()
    end
    left:SetPoint("TOPLEFT", highlight, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", castBars, "BOTTOMRIGHT")
    right:SetPoint("TOPRIGHT", highlight, "BOTTOMRIGHT")
    right:SetPoint("BOTTOMLEFT", castBars, "BOTTOMLEFT")
    belowCastBars:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT")
    belowCastBars:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT")
end

-- Under the health bar, or below the cast bar area while it shows.
function BarMixin:Place()
    local unitFrame = self.plate.UnitFrame
    local below = unitFrame.CastBarsContainer.castBar:IsShown()
    if below == self.belowCastBar then
        return
    end
    self.belowCastBar = below
    local relativeTo = below and self.belowCastBars or unitFrame.HealthBarsContainer.healthBar.selectedBorder
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOP", relativeTo, "BOTTOM", 0, OFFSET_Y)
end

-- `instant` skips the fill animation, for points shown as they already are
-- rather than just built or spent.
function BarMixin:SetPoints(count, maxPoints, instant)
    self.frame:SetWidth(maxPoints * POINT_SIZE + (maxPoints - 1) * POINT_SPACING)
    for index, point in ipairs(self.points) do
        point:SetShown(index <= maxPoints)
        local active = index <= count
        if instant then
            point:SetActiveNoAnimation(active)
        else
            point:SetActive(active)
        end
    end
end

local function NewBar()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetScale(SCALE)
    frame:SetHeight(POINT_SIZE)
    frame:Hide()
    local bar = Mixin({ frame = frame, points = {} }, BarMixin)
    bar.left = CreateFrame("Frame", nil, UIParent)
    bar.right = CreateFrame("Frame", nil, UIParent)
    bar.belowCastBars = CreateFrame("Frame", nil, UIParent)
    bar.belowCastBars:SetHeight(1)
    frame:SetScript("OnUpdate", function()
        bar:Place()
    end)
    for index = 1, MAX_POINTS do
        local point = CreateFrame("Frame", nil, frame, "RogueComboPointTemplate")
        point:SetPoint("LEFT", frame, "LEFT", (index - 1) * (POINT_SIZE + POINT_SPACING), 0)
        point:Setup()
        bar.points[index] = point
    end
    return bar
end

-- A bar on the plate, its points empty so the first ones fill like new ones.
local function Acquire(plate)
    local bar = table.remove(freeBars) or NewBar()
    bar.plate = plate
    bar.belowCastBar = nil
    bar.frame:SetParent(plate)
    for _, point in ipairs(bar.points) do
        point:SetActiveNoAnimation(false)
    end
    AnchorBelowCastBars(bar)
    bar:Place()
    bar.frame:Show()
    barsByPlate[plate] = bar
    return bar
end

local function Release(plate)
    local bar = barsByPlate[plate]
    if not bar then
        return
    end
    barsByPlate[plate] = nil
    bar.frame:Hide()
    for _, frame in ipairs({ bar.frame, bar.left, bar.right, bar.belowCastBars }) do
        frame:ClearAllPoints()
        frame:SetParent(UIParent)
    end
    bar.plate = nil
    table.insert(freeBars, bar)
end

local function ReleaseAll()
    for plate in pairs(barsByPlate) do
        Release(plate)
    end
end

local function GetMaxPoints()
    return math.min(UnitPowerMax("player", Enum.PowerType.ComboPoints), MAX_POINTS)
end

local function RefreshPlate(plate, maxPoints, instant)
    local unit = plate:GetUnit()
    local count = unit and GetComboPoints("player", unit) or 0
    if maxPoints == 0 or count == 0 then
        Release(plate)
        return
    end
    local bar = barsByPlate[plate] or Acquire(plate)
    bar:SetPoints(count, maxPoints, instant)
end

local function RefreshAll(instant)
    local maxPoints = GetMaxPoints()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        RefreshPlate(plate, maxPoints, instant)
    end
end

local function OnPlayerPower(_, unit)
    if unit == "player" then
        RefreshAll(false)
    end
end

local function StartCombatTicker()
    if not combatTicker then
        combatTicker = C_Timer.NewTicker(COMBAT_TICK_SECONDS, function()
            RefreshAll(false)
        end)
    end
end

local function StopCombatTicker()
    if combatTicker then
        combatTicker:Cancel()
        combatTicker = nil
    end
end

local listener = ns:CreateEventListener({
    NAME_PLATE_UNIT_ADDED = function(_, unit)
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then
            RefreshPlate(plate, GetMaxPoints(), true)
        end
    end,
    -- The plate is about to be recycled for another unit.
    NAME_PLATE_UNIT_REMOVED = function(_, unit)
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate then
            Release(plate)
        end
    end,
    -- Points moved to another unit keep their count: no power event fires.
    COMBO_TARGET_CHANGED = function()
        RefreshAll(true)
    end,
    UNIT_POWER_FREQUENT = OnPlayerPower,
    UNIT_MAXPOWER = OnPlayerPower,
    PLAYER_REGEN_DISABLED = StartCombatTicker,
    PLAYER_REGEN_ENABLED = function()
        StopCombatTicker()
        RefreshAll(false)
    end,
})

function Bars:Enable()
    listener:Start()
    if InCombatLockdown() then
        StartCombatTicker()
    end
    RefreshAll(true)
end

function Bars:Disable()
    listener:Stop()
    StopCombatTicker()
    ReleaseAll()
end
