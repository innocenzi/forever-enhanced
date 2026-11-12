-- Movable Windows: dragging title bars, saved positions surviving Blizzard's
-- re-layouts, the modifier, resetting, lifecycle and combat.
-- Blizzard puts panels at PANEL_ANCHOR and bags at BAG_ANCHOR; bags start open.

local PANEL_DEFAULT = "TOPLEFT UIParent TOPLEFT 16 -116"
local BAG_DEFAULT = "BOTTOMRIGHT UIParent BOTTOMRIGHT -4 100"
local DROPPED = "TOPLEFT UIParent BOTTOMLEFT 300 400"

local function Windows(world)
    return world.ns:GetFeature("interface", "windows")
end

local function Saved(world, name)
    local positions = Windows(world):GetAccountStore().positions
    return positions and positions[name]
end

-- A panel from a load-on-demand addon, registered after login.
local function LoadMacroFrame()
    local frame = CreateFrame("Frame", "MacroFrame", UIParent, "PortraitFrameTemplate")
    frame.shown = false
    RegisterUIPanel(frame, { area = "left" })
    return frame
end

test("dragging a panel's title bar moves it and saves where", function(world)
    ShowUIPanel(CharacterFrame)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "Blizzard's place")
    expect(world:HasTitleHandle(CharacterFrame), "title bar handle")

    world:DragTitle(CharacterFrame, 300, 400)
    equal(world:Anchor(CharacterFrame), DROPPED, "dropped")
    equal(Saved(world, "CharacterFrame").x, 300, "saved x")
    equal(Saved(world, "CharacterFrame").relativePoint, "BOTTOMLEFT", "saved relative point")
end)

test("a moved panel stays put when Blizzard lays the panels out again", function(world)
    ShowUIPanel(CharacterFrame)
    world:DragTitle(CharacterFrame, 300, 400)

    HideUIPanel(CharacterFrame)
    ShowUIPanel(CharacterFrame)
    equal(world:Anchor(CharacterFrame), DROPPED, "reopened")

    ShowUIPanel(LoadMacroFrame())
    equal(world:Anchor(CharacterFrame), DROPPED, "after another panel opened")
    UpdateUIPanelPositions()
    equal(world:Anchor(CharacterFrame), DROPPED, "after a re-layout")
end)

test("drops the frame's client-side placement and movable flag after a drag", function(world)
    ShowUIPanel(CharacterFrame)
    world:DragTitle(CharacterFrame, 300, 400)
    expect(not CharacterFrame:IsUserPlaced(), "not user-placed")
    expect(not CharacterFrame:IsMovable(), "movable flag restored")
end)

test("bags keep their saved position", function(world)
    UpdateContainerFrameAnchors()
    equal(world:Anchor(ContainerFrameCombinedBags), BAG_DEFAULT, "Blizzard's place")
    world:DragTitle(ContainerFrameCombinedBags, 300, 400)

    world:CloseBags()
    world:OpenBags()
    equal(world:Anchor(ContainerFrameCombinedBags), DROPPED, "reopened")
    UpdateContainerFrameAnchors()
    equal(world:Anchor(ContainerFrameCombinedBags), DROPPED, "after a re-layout")
end)

test("separate bags move one at a time", function(world)
    world:OpenSeparateBags()
    local bagPlace = world:Position(ContainerFrame2)

    world:DragTitle(ContainerFrame1, 300, 400)
    equal(world:Anchor(ContainerFrame1), DROPPED, "backpack moved")
    equal(world:Position(ContainerFrame2), bagPlace, "the bag stacked on it stays")

    UpdateContainerFrameAnchors()
    equal(world:Anchor(ContainerFrame1), DROPPED, "backpack after a re-layout")
    equal(world:Position(ContainerFrame2), bagPlace, "bag after a re-layout")

    world:DragTitle(ContainerFrame2, 600, 700)
    equal(world:Anchor(ContainerFrame1), DROPPED, "backpack stays")
    world:OpenSeparateBags()
    equal(world:Anchor(ContainerFrame2), "TOPLEFT UIParent BOTTOMLEFT 600 700", "bag after reopening")
end)

test("a bag stacked on a moved one keeps Blizzard's place when reopened", function(world)
    world:OpenSeparateBags()
    local bagPlace = world:Position(ContainerFrame2)
    world:DragTitle(ContainerFrame1, 300, 400)

    ContainerFrame1:Hide()
    ContainerFrame2:Hide()
    world:OpenSeparateBags()
    equal(world:Position(ContainerFrame2), bagPlace, "not carried by the backpack")
end)

test("resetting a bag puts it at Blizzard's place, even when the bag below it moved", function(world)
    world:OpenSeparateBags()
    local bagPlace = world:Position(ContainerFrame2)
    world:DragTitle(ContainerFrame1, 300, 400)
    world:DragTitle(ContainerFrame2, 600, 700)

    world:ShiftRightClickTitle(ContainerFrame2)
    equal(world:Position(ContainerFrame2), bagPlace, "bag back at once")
    equal(world:Anchor(ContainerFrame1), DROPPED, "backpack stays")
end)

test("disabling stacks separate bags again", function(world)
    world:OpenSeparateBags()
    world:DragTitle(ContainerFrame1, 300, 400)
    world:Setting("interface.windows.enabled"):SetValue(false)
    equal(world:Anchor(ContainerFrame1), BAG_DEFAULT, "backpack back")
    equal(world:Anchor(ContainerFrame2), "BOTTOMRIGHT ContainerFrame1 TOPRIGHT 0 5", "bag stacked on it")

    world:Setting("interface.windows.enabled"):SetValue(true)
    equal(world:Anchor(ContainerFrame1), DROPPED, "backpack moved again")
    equal(world:Position(ContainerFrame2), "1716,255", "bag at Blizzard's place")
end)

test("panels of load-on-demand addons and our own are movable", function(world)
    local macro = LoadMacroFrame()
    ShowUIPanel(macro)
    world:DragTitle(macro, 300, 400)
    HideUIPanel(macro)
    ShowUIPanel(macro)
    equal(world:Anchor(macro), DROPPED, "macro frame")

    world:OpenBags()
    world:ClickSideTab(world:BankSideTab())
    local savedBank = world:SavedBank()
    expect(world:HasTitleHandle(savedBank), "saved bank handle")
    world:DragTitle(savedBank, 300, 400)
    equal(Saved(world, "ForeverEnhancedSavedBankFrame").y, 400, "saved bank position")
end)

-- ToggleWorldMap.
local function OpenMap()
    WorldMapFrame:SetMapID(C_Map.GetBestMapForUnit("player"))
    ShowUIPanel(WorldMapFrame)
end

test("the world map moves while windowed and stays where Blizzard puts it maximized", function(world)
    local MAXIMIZED = "TOP UIParent TOP 0 0"
    OpenMap()
    expect(world:HasTitleHandle(WorldMapFrame), "title bar handle")
    world:DragTitle(WorldMapFrame, 300, 400)
    equal(world:Anchor(WorldMapFrame), DROPPED, "windowed")

    WorldMapFrame:Maximize()
    equal(world:Anchor(WorldMapFrame), MAXIMIZED, "maximized")
    world:DragTitle(WorldMapFrame, 600, 700)
    equal(world:Anchor(WorldMapFrame), MAXIMIZED, "not dragged while maximized")
    equal(Saved(world, "WorldMapFrame").x, 300, "position kept")
    UpdateUIPanelPositions()
    equal(world:Anchor(WorldMapFrame), MAXIMIZED, "maximized after a re-layout")
    HideUIPanel(WorldMapFrame)
    OpenMap()
    equal(world:Anchor(WorldMapFrame), MAXIMIZED, "reopened maximized")

    WorldMapFrame:Minimize()
    equal(world:Anchor(WorldMapFrame), DROPPED, "windowed again")
    HideUIPanel(WorldMapFrame)
    OpenMap()
    equal(world:Anchor(WorldMapFrame), DROPPED, "reopened windowed")

    world:Setting("interface.windows.enabled"):SetValue(false)
    equal(world:Anchor(WorldMapFrame), PANEL_DEFAULT, "back when disabled")
end)

test("full-screen panels and the loot window get no handle", function(world)
    ShowUIPanel(CinematicFrame)
    ShowUIPanel(LootFrame)
    equal(world:TitleHandle(CinematicFrame), nil, "cinematic")
    equal(world:TitleHandle(LootFrame), nil, "loot")
end)

test("with a modifier set, only a drag holding it moves the window", function(world)
    world:Setting("interface.windows.modifier"):SetValue("shift")
    ShowUIPanel(CharacterFrame)

    world:DragTitle(CharacterFrame, 300, 400)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "plain drag")
    equal(Saved(world, "CharacterFrame"), nil, "nothing saved")

    world:SetModifier("shift", true)
    world:DragTitle(CharacterFrame, 300, 400)
    world:SetModifier("shift", false)
    equal(world:Anchor(CharacterFrame), DROPPED, "shift drag")
end)

test("Shift Right Click on the title bar puts the window back", function(world)
    ShowUIPanel(CharacterFrame)
    world:DragTitle(CharacterFrame, 300, 400)

    world:ShiftRightClickTitle(CharacterFrame)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "Blizzard's place")
    equal(Saved(world, "CharacterFrame"), nil, "forgotten")

    HideUIPanel(CharacterFrame)
    ShowUIPanel(CharacterFrame)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "stays there")
end)

test("Shift Right Click resets a position saved in an earlier session", function(world)
    -- Read back from saved variables: not a number the client stores exactly.
    Windows(world):GetAccountStore().positions = {
        CharacterFrame = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 512.37, y = 400.1 },
        ContainerFrameCombinedBags = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = 812.37, y = 600.1 },
    }
    ShowUIPanel(CharacterFrame)
    UpdateContainerFrameAnchors()

    world:ShiftRightClickTitle(CharacterFrame)
    world:ShiftRightClickTitle(ContainerFrameCombinedBags)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "panel back at once")
    equal(world:Anchor(ContainerFrameCombinedBags), BAG_DEFAULT, "bags back at once")
end)

test("disabling puts windows back and hides the handles; enabling moves them again", function(world)
    ShowUIPanel(CharacterFrame)
    UpdateContainerFrameAnchors()
    world:DragTitle(CharacterFrame, 300, 400)
    world:DragTitle(ContainerFrameCombinedBags, 300, 400)

    world:Setting("interface.windows.enabled"):SetValue(false)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "panel back")
    equal(world:Anchor(ContainerFrameCombinedBags), BAG_DEFAULT, "bags back")
    expect(not world:HasTitleHandle(CharacterFrame), "handle hidden")
    expect(Saved(world, "CharacterFrame"), "position kept")

    HideUIPanel(CharacterFrame)
    ShowUIPanel(CharacterFrame)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "not re-applied while off")

    world:Setting("interface.windows.enabled"):SetValue(true)
    equal(world:Anchor(CharacterFrame), DROPPED, "panel moved again")
    equal(world:Anchor(ContainerFrameCombinedBags), DROPPED, "bags moved again")
    expect(world:HasTitleHandle(CharacterFrame), "handle shown")
end)

test("protected windows don't move in combat; their position waits for its end", function(world)
    ShowUIPanel(CharacterFrame)
    CharacterFrame.protected = true
    world.inCombat = true

    world:DragTitle(CharacterFrame, 300, 400)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "not moved")
    equal(world.errors[#world.errors], ERR_NOT_IN_COMBAT, "error shown")

    world.inCombat = false
    world:DragTitle(CharacterFrame, 300, 400)
    world.inCombat = true
    UpdateUIPanelPositions() -- the secure manager re-lays out in combat
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "left where Blizzard put it")

    world.inCombat = false
    world:Fire("PLAYER_REGEN_ENABLED")
    equal(world:Anchor(CharacterFrame), DROPPED, "moved after combat")
end)

test("disabling in combat puts protected windows back after combat", function(world)
    ShowUIPanel(CharacterFrame)
    CharacterFrame.protected = true
    world:DragTitle(CharacterFrame, 300, 400)

    world.inCombat = true
    world:Setting("interface.windows.enabled"):SetValue(false)
    equal(world:Anchor(CharacterFrame), DROPPED, "untouched in combat")

    world.inCombat = false
    world:Fire("PLAYER_REGEN_ENABLED")
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "back after combat")
end)

test("drops malformed saved positions", function(world)
    Windows(world):GetAccountStore().positions = { CharacterFrame = { point = "NOWHERE", x = 1 } }
    ShowUIPanel(CharacterFrame)
    equal(world:Anchor(CharacterFrame), PANEL_DEFAULT, "Blizzard's place")
    equal(Saved(world, "CharacterFrame"), nil, "dropped")
end)
