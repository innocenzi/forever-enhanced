-- Combo Points on Nameplates: every nameplate whose unit holds points shows
-- them, targeted or not; bars follow plates being shown, removed and
-- recycled, hide without points or for a class that doesn't build them, sit
-- under the health bar (below the cast bar while it shows), and are fully
-- undone when disabled.

-- A rogue targeting MOB, whose nameplate is shown.
local function Rogue(world)
    world.player.class = "ROGUE"
    local plate = world:ShowNamePlate("MOB")
    world:Target("MOB")
    return plate
end

-- Where the bar's top edge stands on the plate, in the plate's units (the
-- bar's anchor offsets are in its own scale): how far below the target
-- highlight, and how far its center is from the highlight's.
local function Placement(bar, plate)
    local point, relativeTo, relativePoint, x, y = bar:GetPoint(1)
    assert(point == "TOP" and relativePoint == "BOTTOM", "anchored by its top to the bottom of a region")
    local scale = bar:GetEffectiveScale() / bar:GetParent():GetEffectiveScale()
    local left, bottom, width = relativeTo:GetScreenRect()
    local highlight = plate.UnitFrame.HealthBarsContainer.healthBar.selectedBorder
    local highlightLeft, highlightBottom, highlightWidth = highlight:GetScreenRect()
    local drop = highlightBottom - (bottom + y * scale)
    local shift = (left + width / 2 + x * scale) - (highlightLeft + highlightWidth / 2)
    return drop, shift
end

local function Drop(bar, plate)
    return (Placement(bar, plate))
end

local function Shift(bar, plate)
    return select(2, Placement(bar, plate))
end

-- How far the cast bar area reaches below the target highlight.
local function CastBarDepth(world)
    return world.CAST_BAR_SPACING + world.CAST_BARS_HEIGHT - world.HIGHLIGHT_OVERFLOW
end

test("shows the points under the target's nameplate", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(2)

    local points, bar = world:ComboPoints(plate)
    expect(points, "shown")
    equal(points.slots, 5, "slots")
    equal(points.active, 2, "filled")
    expect(points.animated, "building a point animates")
    equal(Shift(bar, plate), 0, "centered on the target highlight")
    local drop = Drop(bar, plate)
    expect(drop > 0 and drop < CastBarDepth(world), "right under the target highlight")
end)

test("follows points as they are built and spent", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(1)
    world:SetComboPoints(5)
    equal(world:ComboPoints(plate).active, 5, "built")

    world:SetComboPoints(0)
    equal(world:ComboPoints(plate), nil, "hidden once spent")
end)

test("hidden without combo points", function(world)
    local plate = Rogue(world)
    equal(world:ComboPoints(plate), nil, "hidden at 0 points")
    equal(world:ComboPointBarCount(), 0, "no bar anywhere")
end)

test("keeps showing the points of a unit no longer targeted", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(3)

    world:Target(nil)
    local points = world:ComboPoints(plate)
    expect(points, "shown without a target")
    equal(points.active, 3, "filled")

    world:ShowNamePlate("OTHER")
    world:Target("OTHER")
    points = world:ComboPoints(plate)
    expect(points, "shown while targeting another unit")
    equal(points.active, 3, "filled")
end)

test("shows the points of every unit holding some", function(world)
    local mobPlate = Rogue(world)
    world:SetComboPoints(3)
    local otherPlate = world:ShowNamePlate("OTHER")
    world:Target("OTHER")
    world:SetComboPoints(2)

    equal(world:ComboPointBarCount(), 2, "two bars")
    equal(world:ComboPoints(mobPlate).active, 3, "points on the first unit")
    equal(world:ComboPoints(otherPlate).active, 2, "points on the second unit")

    world:Target("MOB")
    world:SetComboPoints(0)
    equal(world:ComboPoints(mobPlate), nil, "spent on the first unit")
    equal(world:ComboPoints(otherPlate).active, 2, "kept on the second unit")
end)

test("waits for the nameplate of a unit holding points", function(world)
    world.player.class = "ROGUE"
    world:Target("MOB")
    world:SetComboPoints(3)
    equal(world:ComboPointBarCount(), 0, "no plate, no bar")

    local plate = world:ShowNamePlate("MOB")
    local points = world:ComboPoints(plate)
    expect(points, "shown once the plate appears")
    equal(points.active, 3, "filled")
    expect(not points.animated, "a new plate shows the points without animating")
end)

test("refreshes when the combo target changes", function(world)
    local plate = Rogue(world)
    world.comboPoints.MOB = 2
    world:Fire("COMBO_TARGET_CHANGED")
    equal(world:ComboPoints(plate).active, 2, "filled")
end)

test("a removed plate gives its bar back", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(4)
    world:HideNamePlate("MOB")
    equal(world:ComboPointBarCount(), 0, "no bar left")

    -- The frame is recycled for another unit: the points don't come with it.
    local recycled = world:ShowNamePlate("OTHER")
    equal(recycled, plate, "recycled plate")
    equal(world:ComboPoints(recycled), nil, "not shown on another unit's plate")
end)

test("ignores other plates being removed", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(4)
    world:ShowNamePlate("OTHER")
    world:HideNamePlate("OTHER")
    equal(world:ComboPoints(plate).active, 4, "still shown")
end)

test("a reused bar fills like a new one", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(5)
    world:HideNamePlate("MOB")

    local otherPlate = world:ShowNamePlate("OTHER")
    world:Target("OTHER")
    world:SetComboPoints(1)
    local points = world:ComboPoints(otherPlate)
    equal(points.active, 1, "only the new unit's points")
    expect(points.animated, "the first point animates")
    expect(otherPlate == plate, "same plate frame, reused bar")
end)

test("moves below the cast bar while the unit casts", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(2)
    local _, bar = world:ComboPoints(plate)

    world:SetCasting("MOB", true)
    equal(Shift(bar, plate), 0, "still centered on the health bar")
    expect(Drop(bar, plate) > CastBarDepth(world), "below the cast bar area")

    world:SetCasting("MOB", false)
    expect(Drop(bar, plate) < CastBarDepth(world), "back under the health bar")
end)

test("placed below a cast already showing when the points appear", function(world)
    local plate = Rogue(world)
    world:SetCasting("MOB", true)
    world:SetComboPoints(1)
    local _, bar = world:ComboPoints(plate)
    expect(Drop(bar, plate) > CastBarDepth(world), "below the cast bar area")
end)

test("each bar follows its own plate's cast bar", function(world)
    local mobPlate = Rogue(world)
    world:SetComboPoints(2)
    local otherPlate = world:ShowNamePlate("OTHER")
    world:Target("OTHER")
    world:SetComboPoints(1)

    world:SetCasting("MOB", true)
    expect(
        Drop(select(2, world:ComboPoints(mobPlate)), mobPlate) > CastBarDepth(world),
        "casting unit's bar moves down"
    )
    expect(Drop(select(2, world:ComboPoints(otherPlate)), otherPlate) < CastBarDepth(world), "other bar stays")
end)

test("works for druids", function(world)
    world.player.class = "DRUID"
    local plate = world:ShowNamePlate("MOB")
    world:Target("MOB")
    world:SetComboPoints(2)
    equal(world:ComboPoints(plate).active, 2, "filled")
end)

test("never shown for classes without combo points", function(world)
    world:ShowNamePlate("MOB")
    world:Target("MOB")
    world:SetComboPoints(2)
    equal(world:ComboPointBarCount(), 0, "hidden for a mage")
end)

test("disabling hides every bar and leaves the plates", function(world)
    local mobPlate = Rogue(world)
    world:SetComboPoints(3)
    local otherPlate = world:ShowNamePlate("OTHER")
    world:Target("OTHER")
    world:SetComboPoints(2)

    world:Setting("interface.combopoints.enabled"):SetValue(false)
    equal(world:ComboPointBarCount(), 0, "no bar left")

    world:SetComboPoints(4)
    equal(world:ComboPointBarCount(), 0, "ignores points while disabled")

    world:Setting("interface.combopoints.enabled"):SetValue(true)
    equal(world:ComboPoints(mobPlate).active, 3, "first unit back")
    equal(world:ComboPoints(otherPlate).active, 4, "second unit back")
end)

local COMBAT_TICK_SECONDS = 1

-- MOB holds 3 points while the player targets OTHER.
local function PointsOnAnotherUnit(world)
    local plate = Rogue(world)
    world:SetComboPoints(3)
    world:ShowNamePlate("OTHER")
    world:Target("OTHER")
    return plate
end

-- Plates can't be measured in combat.
test("moves below the cast bar in combat", function(world)
    local plate = Rogue(world)
    world:SetComboPoints(2)
    world:EnterCombat()

    world:SetCasting("MOB", true)
    local _, bar = world:ComboPoints(plate)
    equal(Shift(bar, plate), 0, "centered on the health bar")
    expect(Drop(bar, plate) > CastBarDepth(world), "below the cast bar area")

    world:SetCasting("MOB", false)
    expect(Drop(bar, plate) < CastBarDepth(world), "back under the health bar")
end)

test("placed below a cast when the points appear in combat", function(world)
    local plate = Rogue(world)
    world:EnterCombat()
    world:SetCasting("MOB", true)
    world:SetComboPoints(1)
    local _, bar = world:ComboPoints(plate)
    expect(Drop(bar, plate) > CastBarDepth(world), "below the cast bar area")
end)

test("in combat, notices points running out on a unit that isn't targeted", function(world)
    local plate = PointsOnAnotherUnit(world)
    world:EnterCombat()

    world.comboPoints.MOB = 1
    world:Elapse(COMBAT_TICK_SECONDS)
    equal(world:ComboPoints(plate).active, 1, "updated on the next tick")

    world.comboPoints.MOB = nil
    world:Elapse(COMBAT_TICK_SECONDS)
    equal(world:ComboPoints(plate), nil, "hidden once they run out")
end)

test("checks again when leaving combat, then stops checking", function(world)
    local plate = PointsOnAnotherUnit(world)
    local others = world:TickerCount()
    world:EnterCombat()
    equal(world:TickerCount(), others + 1, "checking in combat")

    world.comboPoints.MOB = nil
    world:LeaveCombat()
    equal(world:ComboPoints(plate), nil, "checked when leaving combat")
    equal(world:TickerCount(), others, "no longer checking")
end)

test("doesn't check out of combat", function(world)
    PointsOnAnotherUnit(world)
    local withFeature = world:TickerCount()
    world:Setting("interface.combopoints.enabled"):SetValue(false)
    equal(world:TickerCount(), withFeature, "no ticker of ours out of combat")
end)

test("checks when enabled in combat, and stops when disabled", function(world)
    local plate = PointsOnAnotherUnit(world)
    world:Setting("interface.combopoints.enabled"):SetValue(false)
    local others = world:TickerCount()
    world.inCombat = true
    world:Setting("interface.combopoints.enabled"):SetValue(true)
    equal(world:TickerCount(), others + 1, "checking in combat")

    world.comboPoints.MOB = nil
    world:Elapse(COMBAT_TICK_SECONDS)
    equal(world:ComboPoints(plate), nil, "updated on the next tick")

    world:Setting("interface.combopoints.enabled"):SetValue(false)
    equal(world:TickerCount(), others, "stopped when disabled")
end)
