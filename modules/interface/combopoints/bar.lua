-- On Forever, combo points are held per unit: points built on one mob stay on
-- it while the player builds more on another, targeted or not, and
-- GetComboPoints("player", unit) reads each mob's. So every nameplate whose
-- unit holds points gets its own bar, taken from a pool and given back when
-- the unit has none left or the plate goes away (plates are recycled).
-- A bar sits right under the health bar, centered on it (not on the level
-- badge beside it). The cast bar shows in the space below the health bar, so
-- while it's up the points move below the cast bar area. Its visibility is
-- polled from the bar's own frame while shown rather than hooked, since
-- Blizzard's plates are pooled and hooks can't be removed.
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

-- Under the health bar, or as far below it as the bottom of the cast bar
-- area. The health bar's border is drawn past its frame, and the target
-- highlight past the border: the points go under the highlight, which is
-- centered on the health bar. The offset is converted to our own scale.
function BarMixin:Place()
    local unitFrame = self.plate.UnitFrame
    local highlight = unitFrame.HealthBarsContainer.healthBar.selectedBorder
    local castBars = unitFrame.CastBarsContainer
    local below = castBars.castBar:IsShown()
    if below == self.belowCastBar then
        return
    end
    self.belowCastBar = below

    local offset = OFFSET_Y
    if below then
        local highlightBottom, castBarsBottom = highlight:GetBottom(), castBars:GetBottom()
        if highlightBottom and castBarsBottom then
            local scale = highlight:GetEffectiveScale() / self.frame:GetEffectiveScale()
            offset = offset - math.max(highlightBottom - castBarsBottom, 0) * scale
        else
            -- Not laid out yet: under the health bar, and try again next frame.
            self.belowCastBar = nil
        end
    end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOP", highlight, "BOTTOM", 0, offset)
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
    bar.frame:ClearAllPoints()
    bar.frame:SetParent(UIParent)
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
