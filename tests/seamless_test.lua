-- Seamless World Map: the zones' art stitched on the world map, zooming and
-- panning across maps, the map underneath following the view, clicks and map
-- pins, the player's arrow, map pins' mouse input in combat, and Blizzard's map
-- back once turned off.
-- The fake world (tests/wow.lua): Azeroth (947), Eastern Kingdoms (10) with
-- Westfall (5) west of Elwynn Forest (1) and Stormwind City (6) in it, Kalimdor
-- (11) with Durotar (2). Each zone's view fits it at zoom 10, Eastern Kingdoms'
-- at 2.5. A map's art tiles are files uiMapID * 100 + 1 to + 12.

local ARROW = "Interface\\Minimap\\MinimapArrow"

local function Set(world, key, value)
    world:Setting("map.seamless." .. key):SetValue(value)
end

local function Near(actual, expected, label)
    expect(math.abs(actual - expected) < 1e-3, ("%s: %s, expected %s"):format(label, actual, expected))
end

-- Gives each zone an explored-area piece in the game's tables (file uiMapID * 100 + 50),
-- explored, then turns the feature on.
local function Setup(world)
    local Seamless = ForeverEnhanced:GetFeature("map", "seamless")
    for _, mapID in ipairs({ 1, 2, 5 }) do
        local file = mapID * 100 + 50
        Seamless.Pieces[C_Map.GetMapArtID(mapID)] = { { 256, 256, 300, 200, file } }
        world.exploredMapTextures[mapID] = {
            { fileDataIDs = { file }, offsetX = 300, offsetY = 200, textureWidth = 256, textureHeight = 256 },
        }
    end
    Set(world, "enabled", true)
end

test("leaves Blizzard's map alone until turned on", function(world)
    world:OpenMap(1)
    world:RunFrames(1)
    equal(#WorldMapFrame.ScrollContainer.zoomLevels, 1, "zoom levels")
    expect(next(world:MapArt()) == nil, "no stitched art")
    world:DragMap(0.65, 0.6)
    Near((world:MapView()), 0.75, "the view stays on Elwynn Forest")
end)

test("stitches the zones around the one shown, in place of Blizzard's art", function(world)
    Setup(world)
    world:OpenMap(1)
    world:RunFrames(1)
    local art = world:MapArt()
    expect(art[101] and art[112], "Elwynn Forest's art")
    expect(art[150], "its explored areas")
    expect(art[503] and art[504], "Westfall's art beside it")
    expect(not art[501] and not art[502], "not Westfall's far side, off the view")
    expect(art[ForeverEnhanced:GetFeature("map", "seamless").MEDIA .. "sea.png"], "blank sea paper under them")
    expect(not world:IsBlizzardMapArtShown(), "Blizzard's own art")
    local u, v, shown = world:MapView()
    Near(u, 0.75, "the view's middle")
    Near(v, 0.6, "the view's middle")
    Near(shown, 0.1, "the view shows Elwynn Forest whole")
end)

test("draws each zone once, tinted toward the shared palette", function(world)
    local Seamless = ForeverEnhanced:GetFeature("map", "seamless")
    Seamless.Tints[1] = { 0.8, 0.9, 1 }
    Setup(world)
    world:OpenMap(1)
    world:RunFrames(1)
    local art = world:MapArt()
    equal(art[101], 1, "Elwynn Forest's first tile")
    equal(art[150], 1, "its explored area")
    equal(table.concat(world:MapArtTint(101), " "), "0.8 0.9 1", "Elwynn Forest's tint")
    equal(table.concat(world:MapArtTint(503), " "), "1 1 1", "Westfall's colours, without a tint of its own")
end)

test("gives way to blank paper past the zones once they're in", function(world)
    local Seamless = ForeverEnhanced:GetFeature("map", "seamless")
    Seamless.Lands[10] = true
    local SEA = Seamless.MEDIA .. "sea.png"
    local LAND = Seamless.MEDIA .. "land.png"
    Setup(world)
    world:OpenMap(10)
    world:RunFrames(1)
    local art = world:MapArt()
    expect(art[1001] and art[94701], "the continent's and the world's art on the continent's map")
    expect(not art[LAND], "no land paper there")
    world:ShowMap(1)
    world:RunFrames(1)
    art = world:MapArt()
    expect(not art[1001] and not art[94701], "no stretched continent or world art on a zone's map")
    equal(art[SEA], 2, "the sea paper, at two scales")
    equal(art[LAND], 2, "Eastern Kingdoms' land paper, at two scales (Kalimdor has no land)")
end)

test("loads every tile near the view, however many come in at once", function(world)
    local Seamless = ForeverEnhanced:GetFeature("map", "seamless")
    local pieces = {}
    for i = 1, 150 do
        table.insert(pieces, { 16, 16, i * 4, 0, 1000 + i })
    end
    Setup(world)
    Seamless.Pieces[C_Map.GetMapArtID(1)] = pieces
    world.exploredMapTextures[1] = nil
    Set(world, "unexplored", true)
    world:OpenMap(1)
    world:RunFrames(2)
    local art = world:MapArt()
    for i = 1, 150 do
        expect(art[1000 + i], "piece " .. i)
    end
    for i = 1, 12 do
        expect(art[100 + i], "tile " .. i)
    end
end)

test("shows only the world from afar, and the zones as the view closes in", function(world)
    Setup(world)
    world:OpenMap(947)
    world:RunFrames(1)
    local art = world:MapArt()
    expect(art[94701], "the world's art")
    expect(not art[1001], "the continents' art")
    expect(not art[101], "the zones' art")
    world:ShowMap(10)
    world:RunFrames(1)
    art = world:MapArt()
    expect(art[1001], "a continent's art once it fills the view")
    expect(art[101], "its zones' art coming in")
end)

test("zooms toward the point under the mouse with the wheel", function(world)
    Setup(world)
    world:OpenMap(10)
    local _, _, before = world:MapView()
    world:PointMouseAt(0.65, 0.6)
    world:MapWheel(1)
    world:RunFrames(1)
    local _, _, after = world:MapView()
    Near(after, before / 1.25, "one notch in")
    local u, v = world:MapPointUnderMouse()
    Near(u, 0.65, "the point under the mouse")
    Near(v, 0.6, "the point under the mouse")
    equal(WorldMapFrame:GetMapID(), 10, "still the continent underneath")
end)

test("pans past the map underneath, which follows the view once it rests", function(world)
    Setup(world)
    world:OpenMap(1)
    world:DragMap(0.65, 0.6)
    Near((world:MapView()), 0.65, "the view in Westfall")
    equal(WorldMapFrame:GetMapID(), 1, "Elwynn Forest underneath while it moves")
    world:RunFrames(1)
    equal(WorldMapFrame:GetMapID(), 5, "Westfall underneath")
    local u, v, shown = world:MapView()
    Near(u, 0.65, "the view kept")
    Near(v, 0.6, "the view kept")
    Near(shown, 0.1, "the zoom kept")
end)

test("the map underneath follows the view soon after it rests", function(world)
    Setup(world)
    world:OpenMap(1)
    world:DragMap(0.65, 0.6)
    world:RunFrames(0.05)
    equal(WorldMapFrame:GetMapID(), 1, "not at once")
    world:RunFrames(0.15)
    equal(WorldMapFrame:GetMapID(), 5, "within a fifth of a second")
end)

test("the map underneath follows the wheel's zoom as it ends", function(world)
    Setup(world)
    world:OpenMap(1)
    world:PointMouseAt(0.75, 0.6)
    for _ = 1, 3 do
        world:MapWheel(-1)
    end
    world:RunFrames(0.4)
    equal(WorldMapFrame:GetMapID(), 10, "Eastern Kingdoms underneath")
    world:RunFrames(1)
    Near((world:MapView()), 0.75, "the zoom ends where it was going")
    local _, _, shown = world:MapView()
    Near(shown, 0.1 * 1.25 ^ 3, "the zoom ends where it was going")
end)

test("the map underneath follows a flung view without waiting out Blizzard's last pixel", function(world)
    Setup(world)
    world:OpenMap(1)
    world:FlingMap(0.65, 0.6, 0.01)
    world:RunFrames(0.8)
    equal(WorldMapFrame:GetMapID(), 5, "Westfall underneath")
    Near((world:MapView()), 0.66, "where the fling ends")
end)

test("zooming out of a zone makes its continent the map underneath", function(world)
    Setup(world)
    world:OpenMap(1)
    world:PointMouseAt(0.75, 0.6)
    for _ = 1, 3 do
        world:MapWheel(-1)
    end
    world:RunFrames(2)
    equal(WorldMapFrame:GetMapID(), 10, "Eastern Kingdoms underneath")
    Near((world:MapView()), 0.75, "the view kept")
end)

test("a click zooms into the zone under the mouse, a right click out to its continent", function(world)
    Setup(world)
    world:OpenMap(10)
    world:PointMouseAt(0.65, 0.6)
    world:MapClick()
    world:RunFrames(2)
    local u, v, shown = world:MapView()
    Near(u, 0.65, "Westfall in the middle")
    Near(v, 0.6, "Westfall in the middle")
    Near(shown, 0.1, "Westfall whole")
    equal(WorldMapFrame:GetMapID(), 5, "Westfall underneath")
    world:MapClick("RightButton")
    world:RunFrames(2)
    u, v, shown = world:MapView()
    Near(u, 0.75, "Eastern Kingdoms in the middle")
    Near(shown, 0.4, "Eastern Kingdoms whole")
    equal(WorldMapFrame:GetMapID(), 10, "Eastern Kingdoms underneath")
end)

test("leaves other modified clicks to the map's other handlers", function(world)
    Setup(world)
    world:OpenMap(10)
    local clicks = 0
    WorldMapFrame:AddCanvasClickHandler(function()
        clicks = clicks + 1
        return true
    end, 0)
    world:PointMouseAt(0.65, 0.6)
    world.shift = true
    world:MapClick()
    equal(clicks, 1, "Shift Click passed on")
    world.shift = false
    world:MapClick()
    equal(clicks, 1, "a plain click is the stitched map's")
end)

test("leaves map pins over the map underneath to Blizzard's", function(world)
    Setup(world)
    world:OpenMap(1)
    world:PointMouseAt(0.72, 0.62)
    world.ctrl = true
    world:MapClick()
    world.ctrl = false
    equal(world.waypoint.uiMapID, 1, "Ctrl Click: on Elwynn Forest")
    Near(world.waypoint.position.x, 0.2, "where it was clicked")
    world.waypoint = nil
    WorldMapFrame.WorldMapTrackingPinButton.isActive = true
    world:MapClick()
    WorldMapFrame.WorldMapTrackingPinButton.isActive = false
    equal(world.waypoint.uiMapID, 1, "a click with the pin button on: on Elwynn Forest")
    Near((world:MapView()), 0.75, "and no zoom")
end)

test("places map pins past the map underneath on the map they're over", function(world)
    Setup(world)
    world:OpenMap(1)
    world:PointMouseAt(0.75, 0.6)
    world:MapWheel(-1)
    world:RunFrames(1)
    equal(WorldMapFrame:GetMapID(), 1, "still Elwynn Forest underneath")
    world:PointMouseAt(0.68, 0.6)
    world.ctrl = true
    world:MapClick()
    world.ctrl = false
    equal(world.waypoint.uiMapID, 5, "on Westfall, not on Elwynn Forest's edge")
    Near(world.waypoint.position.x, 0.8, "where it was clicked on Westfall")
    Near(world.waypoint.position.y, 0.5, "where it was clicked on Westfall")
end)

test("keeps a quest's details open as the map moves", function(world)
    Setup(world)
    world:OpenMap(1)
    world:OpenQuestDetails(1)
    world:DragMap(0.65, 0.6)
    world:RunFrames(2)
    equal(WorldMapFrame:GetMapID(), 1, "Elwynn Forest underneath")
    equal(QuestMapFrame.DetailsFrame.questMapID, 1, "the quest's details still open")
    QuestMapFrame.DetailsFrame.questMapID = nil
    world:RunFrames(1)
    equal(WorldMapFrame:GetMapID(), 5, "the map underneath follows once they're closed")
end)

test("never changes the map underneath in combat", function(world)
    Setup(world)
    world:OpenMap(1)
    world:EnterCombat()
    world:DragMap(0.65, 0.6)
    world:RunFrames(2)
    equal(WorldMapFrame:GetMapID(), 1, "in combat")
    world:LeaveCombat()
    world:RunFrames(1)
    equal(WorldMapFrame:GetMapID(), 5, "after combat")
end)

test("leaves dungeon maps as Blizzard made them", function(world)
    Setup(world)
    world:OpenMap(3)
    world:RunFrames(1)
    equal(#WorldMapFrame.ScrollContainer.zoomLevels, 1, "Blizzard's zoom levels")
    expect(world:IsBlizzardMapArtShown(), "Blizzard's own art")
    expect(next(world:MapArt()) == nil, "no stitched art")
    world:ShowMap(1)
    world:RunFrames(1)
    expect(world:MapArt()[101], "stitched again on a zone")
end)

test("hides unexplored areas unless turned on, and shows areas as they're explored", function(world)
    Setup(world)
    world.exploredMapTextures[1] = {
        { fileDataIDs = { 160 }, offsetX = 600, offsetY = 400, textureWidth = 128, textureHeight = 128 },
    }
    world:OpenMap(1)
    world:RunFrames(1)
    local art = world:MapArt()
    expect(not art[150], "unexplored area hidden")
    expect(art[160], "explored area")
    Set(world, "unexplored", true)
    world:RunFrames(1)
    expect(world:MapArt()[150], "unexplored area shown once turned on")
    Set(world, "unexplored", false)
    expect(not world:MapArt()[150], "hidden again")
    table.insert(
        world.exploredMapTextures[1],
        { fileDataIDs = { 150 }, offsetX = 300, offsetY = 200, textureWidth = 256, textureHeight = 256 }
    )
    world:Fire("MAP_EXPLORATION_UPDATED")
    expect(world:MapArt()[150], "the area just explored")
end)

test("shows areas explored while it was off once back on", function(world)
    Setup(world)
    world.exploredMapTextures[1] = {}
    world:OpenMap(1)
    world:RunFrames(1)
    expect(not world:MapArt()[150], "unexplored area hidden")
    Set(world, "enabled", false)
    world.exploredMapTextures[1] = {
        { fileDataIDs = { 150 }, offsetX = 300, offsetY = 200, textureWidth = 256, textureHeight = 256 },
    }
    world:Fire("MAP_EXPLORATION_UPDATED")
    Set(world, "enabled", true)
    world:RunFrames(1)
    expect(world:MapArt()[150], "the area explored meanwhile")
end)

test("shows the player's arrow where the map underneath can't", function(world)
    Setup(world)
    world.position = { x = 500, y = 500, continentID = 0 }
    world.facing = 1
    world:OpenMap(10)
    world:RunFrames(1)
    expect(world:IsDrawn(ARROW), "on Eastern Kingdoms, the player in Elwynn Forest")
    world:ShowMap(1)
    world:RunFrames(1)
    expect(not world:IsDrawn(ARROW), "on Elwynn Forest, Blizzard's own")
    world:ShowMap(10)
    world.secretValues[world.facing] = true
    world:RunFrames(1)
    expect(not world:IsDrawn(ARROW), "while the game keeps it secret")
end)

test("keeps the player's arrow on the player as the map pans", function(world)
    Setup(world)
    world.position = { x = 500, y = 500, continentID = 0 }
    world.facing = 1
    world:OpenMap(10)
    world:RunFrames(1)
    local before = world:DrawnAt(ARROW)
    world:DragMap(0.70, 0.5)
    world:NextFrame()
    local after = world:DrawnAt(ARROW)
    Near(after - before, 0.05 / 0.4 * 1000, "moved with the map on the next frame")
end)

-- questID -> position of the map's quest pins of `template` (ours, or Blizzard's QuestPinTemplate).
local function QuestPins(template)
    local pins = {}
    for _, pin in ipairs(WorldMapFrame.pins) do
        if pin.template == template then
            pins[pin.questID] = pin.position
        end
    end
    return pins
end

local OUR_QUESTS = "ForeverEnhancedQuestPinTemplate"
local BLIZZARD_QUESTS = "QuestPinTemplate"

local function SetupQuests(world)
    world.questLog = {
        { questID = 1, title = "Items of Some Consequence", onMap = { x = 0.3, y = 0.4 } },
        { questID = 2, title = "Crime and Punishment", onMap = { x = 0.6, y = 0.7 } },
    }
    world.superTracked = 2
    Setup(world)
end

test("shows every quest on a continent, the super-tracked one left to Blizzard's", function(world)
    SetupQuests(world)
    world:OpenMap(10)
    local ours = QuestPins(OUR_QUESTS)
    Near(ours[1].x, 0.3, "where the game places it")
    Near(ours[1].y, 0.4, "where the game places it")
    expect(not ours[2], "not the super-tracked quest")
    local blizzard = QuestPins(BLIZZARD_QUESTS)
    expect(blizzard[2] and not blizzard[1], "Blizzard's shows only the super-tracked quest")
    C_SuperTrack.SetSuperTrackedQuestID(1)
    ours = QuestPins(OUR_QUESTS)
    expect(ours[2] and not ours[1], "following super tracking")
end)

test("leaves zones' quests to Blizzard's", function(world)
    SetupQuests(world)
    world:OpenMap(1)
    expect(next(QuestPins(OUR_QUESTS)) == nil, "none of ours")
    local blizzard = QuestPins(BLIZZARD_QUESTS)
    expect(blizzard[1] and blizzard[2], "Blizzard's shows them all")
    world:ShowMap(10)
    expect(QuestPins(OUR_QUESTS)[1], "ours once the continent is underneath")
end)

test("shows only the quest whose details are open", function(world)
    SetupQuests(world)
    world.superTracked = 0
    world:OpenMap(10)
    QuestMapFrame.DetailsFrame.questID = 1
    C_SuperTrack.SetSuperTrackedQuestID(0)
    local ours = QuestPins(OUR_QUESTS)
    expect(not ours[1] and not ours[2], "neither: Blizzard's shows the focused one")
end)

test("shows continents' quests only while turned on", function(world)
    SetupQuests(world)
    world:OpenMap(10)
    Set(world, "quests", false)
    expect(next(QuestPins(OUR_QUESTS)) == nil, "turned off")
    Set(world, "quests", true)
    expect(QuestPins(OUR_QUESTS)[1], "turned back on")
end)

test("turning it off removes continents' quests for good", function(world)
    SetupQuests(world)
    world:OpenMap(10)
    Set(world, "enabled", false)
    expect(next(QuestPins(OUR_QUESTS)) == nil, "removed")
    C_SuperTrack.SetSuperTrackedQuestID(1)
    expect(next(QuestPins(OUR_QUESTS)) == nil, "not back as super tracking changes")
    Set(world, "enabled", true)
    expect(QuestPins(OUR_QUESTS)[2], "back once turned on")
end)

local function SetInCombat(world)
    for _, input in ipairs(world.mouseInputs) do
        if input.inCombat then
            return true
        end
    end
    return false
end

test("defers map pins' mouse input to the end of combat", function(world)
    Setup(world)
    world:OpenMap(1)
    world.mouseInputs = {}
    world:EnterCombat()
    WorldMapFrame:AcquirePin("MapExplorationPinTemplate")
    WorldMapFrame:AcquirePin("SuperTrackablePinTemplate")
    expect(not SetInCombat(world), "nothing set in combat")
    world:LeaveCombat()
    equal(#world.mouseInputs, 3, "set after combat: passthrough twice, propagation once")
end)

test("drops a pin's waiting mouse input once the pin is let go", function(world)
    Setup(world)
    world:OpenMap(1)
    world.mouseInputs = {}
    world:EnterCombat()
    WorldMapFrame:AcquirePin("SuperTrackablePinTemplate")
    WorldMapFrame:RemoveAllPinsByTemplate("SuperTrackablePinTemplate")
    world:LeaveCombat()
    equal(#world.mouseInputs, 0, "nothing set for a pin no longer on the map")
end)

test("keeps deferring map pins' mouse input once turned off, the map still tainted", function(world)
    Setup(world)
    world:OpenMap(1)
    Set(world, "enabled", false)
    world.mouseInputs = {}
    world:EnterCombat()
    WorldMapFrame:AcquirePin("MapExplorationPinTemplate")
    expect(not SetInCombat(world), "nothing set in combat")
    world:LeaveCombat()
    equal(#world.mouseInputs, 1, "set after combat")
end)

test("turning it off gives Blizzard's map back", function(world)
    Setup(world)
    world:OpenMap(1)
    world:RunFrames(1)
    world:PointMouseAt(0.7, 0.6)
    world:MapWheel(1)
    world:RunFrames(1)
    Set(world, "enabled", false)
    world:RunFrames(1)
    local scroll = WorldMapFrame.ScrollContainer
    equal(#scroll.zoomLevels, 1, "Blizzard's zoom levels")
    equal(scroll.mouseWheelZoomMode, MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL, "Blizzard's wheel")
    expect(world:IsBlizzardMapArtShown(), "Blizzard's own art")
    expect(next(world:MapArt()) == nil, "no stitched art")
    local u, _, shown = world:MapView()
    Near(u, 0.75, "Elwynn Forest whole")
    Near(shown, 0.1, "Elwynn Forest whole")
    world:DragMap(0.65, 0.6)
    Near((world:MapView()), 0.75, "the pan stays on the map")
    Set(world, "enabled", true)
    world:RunFrames(1)
    expect(world:MapArt()[101], "stitched again once turned back on")
end)

test("ships every mask and paper its data lists", function()
    local Seamless = ForeverEnhanced:GetFeature("map", "seamless")
    local function Exists(path)
        local file = io.open(path, "rb")
        if file then
            file:close()
        end
        return file ~= nil
    end
    local count = 0
    for mapID in pairs(Seamless.Zones) do
        count = count + 1
        expect(Exists(("modules/map/seamless/media/zone/%d.png"):format(mapID)), "zone " .. mapID)
        expect(Seamless.Tints[mapID], "tint " .. mapID)
    end
    expect(count > 40, "zones listed")
    for mapID in pairs(Seamless.Lands) do
        expect(Exists(("modules/map/seamless/media/land/%d.png"):format(mapID)), "land " .. mapID)
    end
    for _, name in ipairs({ "feather-thin", "feather-wide", "feather-round", "land", "sea" }) do
        expect(Exists("modules/map/seamless/media/" .. name .. ".png"), name)
    end
    expect(Seamless.Papers.land > 0 and Seamless.Papers.sea > 0, "the papers' sizes")
end)
