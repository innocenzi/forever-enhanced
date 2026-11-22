-- Seamless World Map: a view of our own over Blizzard's map, which it never writes
-- into. Opening it past Blizzard's widest view, the zones' art stitched on it, zooming
-- and panning across the world, clicks and map pins, handing Blizzard's map back on a
-- zone, combat, the icons and the player's arrow on it, the continents' quests on
-- Blizzard's map, and turning it off.
-- The fake world (tests/wow.lua): Azeroth (947), Eastern Kingdoms (10) with
-- Westfall (5) west of Elwynn Forest (1) and Stormwind City (6) in it, Kalimdor
-- (11) with Durotar (2), a dungeon (3). The view and Blizzard's map are as big as
-- the world's art (1000 x 700): zoom 1 shows it all. Each zone fits the view at zoom
-- 10, Eastern Kingdoms at 2.5. A map's art tiles are files uiMapID * 100 + 1 to + 12.

local ARROW = "UI-WorldMapArrow"

local function Seamless()
    return ForeverEnhanced:GetFeature("map", "seamless")
end

local function Set(world, key, value)
    world:Setting("map.seamless." .. key):SetValue(value)
end

local function Near(actual, expected, label)
    expect(math.abs(actual - expected) < 1e-3, ("%s: %s, expected %s"):format(label, actual, expected))
end

-- Gives each zone an explored-area piece in the game's tables (file uiMapID * 100 + 50),
-- explored, then turns the feature on.
local function Setup(world)
    for _, mapID in ipairs({ 1, 2, 5 }) do
        local file = mapID * 100 + 50
        Seamless().Pieces[C_Map.GetMapArtID(mapID)] = { { 256, 256, 300, 200, file } }
        world.exploredMapTextures[mapID] = {
            { fileDataIDs = { file }, offsetX = 300, offsetY = 200, textureWidth = 256, textureHeight = 256 },
        }
    end
    Set(world, "enabled", true)
end

-- The seamless view: its middle on the world and the share of the world's width it
-- shows; nil while it's hidden.
local function View()
    local view = Seamless().View
    local u, v, zoom = view:GetView()
    if not u then
        return nil
    end
    local frame = view:GetFrame()
    local width, height = Seamless().Geometry:Size()
    local fit = math.min(frame:GetWidth() / width, frame:GetHeight() / height)
    return u, v, frame:GetWidth() / (width * fit * zoom)
end

-- The screen point over world point (u, v) on the seamless view.
local function ViewPoint(u, v)
    local frame = Seamless().View:GetFrame()
    local cu, cv, shown = View()
    local left, bottom, width, height = frame:GetScreenRect()
    local px = width / (shown * 1000)
    return left + width / 2 + (u - cu) * 1000 * px, bottom + height / 2 - (v - cv) * 700 * px
end

local function PointAt(world, u, v)
    local x, y = ViewPoint(u, v)
    world.mouse = { x = x, y = y }
end

-- The world point under the mouse on the seamless view.
local function UnderMouse(world)
    local frame = Seamless().View:GetFrame()
    local cu, cv, shown = View()
    local left, bottom, width, height = frame:GetScreenRect()
    local px = width / (shown * 1000)
    return cu + (world.mouse.x - left - width / 2) / (1000 * px),
        cv - (world.mouse.y - bottom - height / 2) / (700 * px)
end

-- Drags the seamless view so that world point (u, v) comes to its middle.
local function Drag(world, u, v)
    local cu, cv = View()
    PointAt(world, cu, cv)
    world:MouseDown("LeftButton")
    local x, y = ViewPoint(cu, cv)
    local tx, ty = ViewPoint(u, v)
    world:MoveMouse(2 * x - tx, 2 * y - ty)
    world:MouseUp("LeftButton")
end

-- Opens the seamless view on `mapID`: Blizzard's map opened there (unless it shows, then
-- on it already), the wheel zooming out at the map's middle where Blizzard's map can't
-- (its widest view).
local function Open(world, mapID)
    if not WorldMapFrame:IsShown() then
        world:OpenMap(mapID)
    end
    equal(WorldMapFrame:GetMapID(), mapID, "Open: Blizzard's map on the map to open on")
    world:RunFrames(0.1)
    local left, right, top, bottom = Seamless().Geometry:Rect(mapID)
    world:PointMouseAt((left + right) / 2, (top + bottom) / 2)
    world:MapWheel(-1)
    world:RunFrames(1)
end

-- The art drawn on the seamless view: file -> how many textures.
local function Art(world)
    local view = Seamless().View:GetFrame()
    local files = {}
    for _, texture in ipairs(world.textures) do
        local frame = texture.owner
        while frame and frame ~= view do
            frame = frame.parent
        end
        if frame and texture.texture and world:IsRegionDrawn(texture) then
            files[texture.texture] = (files[texture.texture] or 0) + 1
        end
    end
    return files
end

-- How many textures of `file` drawn on the view are masked by a mask of `maskFile`.
local function ArtMasked(world, file, maskFile)
    local count = 0
    local view = Seamless().View:GetFrame()
    for _, texture in ipairs(world.textures) do
        local frame = texture.owner
        while frame and frame ~= view do
            frame = frame.parent
        end
        if frame and texture.texture == file and world:IsRegionDrawn(texture) then
            for _, mask in ipairs(texture.masks or {}) do
                if mask.texture == maskFile then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Whether a texture showing `atlas` is drawn.
local function AtlasDrawn(world, atlas)
    for _, texture in ipairs(world.textures) do
        if texture.atlas == atlas and world:IsRegionDrawn(texture) then
            return true
        end
    end
    return false
end

-- Nothing of ours ran in Blizzard's map or was written into it, and Blizzard's map changed
-- map only from a click or the wheel (C_Map.OpenWorldMap, refused otherwise in game).
local function Untouched(world)
    equal(table.concat(world:BlizzardMapWrites(), ", "), "", "Blizzard's map untouched")
    for index, call in ipairs(world.openWorldMapCalls) do
        expect(call.hardware, ("OpenWorldMap %d from a click or the wheel"):format(index))
    end
end

-- Every test ends with Blizzard's map untouched.
local register = test
local function test(name, func, options)
    register(name, function(world)
        func(world)
        Untouched(world)
    end, options)
end

-- Blizzard's map --------------------------------------------------------------------------

test("leaves Blizzard's map alone until turned on", function(world)
    world:OpenMap(1)
    world:RunFrames(1)
    equal(#WorldMapFrame.ScrollContainer.zoomLevels, 1, "zoom levels")
    world:PointMouseAt(0.75, 0.6)
    world:MapWheel(-1)
    world:RunFrames(1)
    expect(not View(), "no seamless view")
    world:DragMap(0.65, 0.6)
    Near((world:MapView()), 0.75, "the view stays on Elwynn Forest")
end)

test("leaves Blizzard's map as Blizzard made it while turned on", function(world)
    Setup(world)
    world:OpenMap(1)
    world:RunFrames(1)
    expect(not View(), "no seamless view on opening the map")
    expect(world:IsBlizzardMapArtShown(), "Blizzard's own art")
    equal(WorldMapFrame.ScrollContainer.mouseWheelZoomMode, MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL, "its wheel")
    world:DragMap(0.65, 0.6)
    Near((world:MapView()), 0.75, "its pan, within the map")
end)

test("opens past Blizzard's widest view, where Blizzard's view was", function(world)
    Setup(world)
    world.mapMaxScale[1] = 2
    world:OpenMap(1)
    world:RunFrames(0.1)
    world:PointMouseAt(0.75, 0.6)
    world:MapWheel(1)
    world:RunFrames(0.1)
    world:MapWheel(-1)
    world:RunFrames(0.1)
    expect(not View(), "Blizzard's own zoom back out to its widest view")
    world:MapWheel(-1)
    world:RunFrames(1)
    local u, v, shown = View()
    expect(u, "the seamless view, zooming out past it")
    Near(u, 0.75, "Elwynn Forest in the middle")
    Near(v, 0.6, "Elwynn Forest in the middle")
    Near(shown, 0.1 * 1.25, "one notch out from Elwynn Forest whole")
    equal(WorldMapFrame:GetMapID(), 1, "Blizzard's map still on Elwynn Forest")
    expect(world:IsBlizzardMapArtShown(), "Blizzard's own art underneath")
end)

test("never opens on dungeon maps", function(world)
    Setup(world)
    world:OpenMap(3)
    world:RunFrames(0.1)
    -- (the dungeon's map isn't on Azeroth's: the mouse in the map's middle)
    local left, bottom, width, height = WorldMapFrame.ScrollContainer:GetScreenRect()
    world.mouse = { x = left + width / 2, y = bottom + height / 2 }
    world:MapWheel(-1)
    world:RunFrames(1)
    expect(not View(), "no seamless view")
    expect(world:IsBlizzardMapArtShown(), "Blizzard's own art")
end)

-- The art -----------------------------------------------------------------------------------

test("stitches the zones around the one shown", function(world)
    Setup(world)
    Open(world, 1)
    local art = Art(world)
    expect(art[101] and art[112], "Elwynn Forest's art")
    expect(art[150], "its explored areas")
    expect(art[503] and art[504], "Westfall's art beside it")
    expect(not art[501], "not Westfall's far side, off the view")
    expect(art[Seamless().MEDIA .. "sea.png"], "blank sea paper under them")
end)

test("draws each zone once, tinted toward the shared palette", function(world)
    Seamless().Tints[1] = { 0.8, 0.9, 1 }
    Setup(world)
    Open(world, 1)
    local art = Art(world)
    equal(art[101], 1, "Elwynn Forest's first tile")
    equal(art[150], 1, "its explored area")
    equal(table.concat(world:MapArtTint(101), " "), "0.8 0.9 1", "Elwynn Forest's tint")
    equal(table.concat(world:MapArtTint(503), " "), "1 1 1", "Westfall's colours, without a tint of its own")
end)

test("shows only the world from afar, and the zones as the view closes in", function(world)
    Setup(world)
    Open(world, 947)
    local art = Art(world)
    expect(art[94701], "the world's art")
    expect(not art[1001], "the continents' art")
    expect(not art[101], "the zones' art")
    PointAt(world, 0.75, 0.5)
    world:MapClick()
    world:RunFrames(1)
    art = Art(world)
    expect(art[1001], "a continent's art once it fills the view")
    expect(art[101], "its zones' art coming in")
end)

test("gives way to blank paper past the zones once they're in", function(world)
    Seamless().Lands[10] = true
    local SEA = Seamless().MEDIA .. "sea.png"
    local LAND = Seamless().MEDIA .. "land.png"
    Setup(world)
    Open(world, 947)
    PointAt(world, 0.75, 0.5)
    world:MapClick()
    world:RunFrames(1)
    local art = Art(world)
    expect(art[1001] and art[94701], "the continent's and the world's art on the continent")
    expect(not art[LAND], "no land paper there")
    -- (zoomed in where Eastern Kingdoms has no zone)
    PointAt(world, 0.9, 0.4)
    for _ = 1, 6 do
        world:MapWheel(1)
    end
    world:RunFrames(1)
    art = Art(world)
    expect(not art[1001] and not art[94701], "no stretched continent or world art zoomed in")
    equal(art[SEA], 2, "the sea paper, at two scales")
    equal(art[LAND], 2, "Eastern Kingdoms' land paper, at two scales (Kalimdor has no land)")
end)

test("loads every tile near the view, however many come in at once", function(world)
    local pieces = {}
    for i = 1, 150 do
        table.insert(pieces, { 16, 16, i * 4, 0, 1000 + i })
    end
    Setup(world)
    Seamless().Pieces[C_Map.GetMapArtID(1)] = pieces
    world.exploredMapTextures[1] = nil
    Set(world, "unexplored", true)
    Open(world, 1)
    world:RunFrames(1)
    local art = Art(world)
    for i = 1, 150 do
        expect(art[1000 + i], "piece " .. i)
    end
    for i = 1, 12 do
        expect(art[100 + i], "tile " .. i)
    end
end)

test("hides unexplored areas unless turned on, and shows areas as they're explored", function(world)
    Setup(world)
    world.exploredMapTextures[1] = {
        { fileDataIDs = { 160 }, offsetX = 600, offsetY = 400, textureWidth = 128, textureHeight = 128 },
    }
    Open(world, 1)
    local art = Art(world)
    expect(not art[150], "unexplored area hidden")
    expect(art[160], "explored area")
    Set(world, "unexplored", true)
    world:RunFrames(1)
    expect(Art(world)[150], "unexplored area shown once turned on")
    Set(world, "unexplored", false)
    expect(not Art(world)[150], "hidden again")
    table.insert(
        world.exploredMapTextures[1],
        { fileDataIDs = { 150 }, offsetX = 300, offsetY = 200, textureWidth = 256, textureHeight = 256 }
    )
    world:Fire("MAP_EXPLORATION_UPDATED")
    expect(Art(world)[150], "the area just explored")
end)

test("lays the land paper over a zone's blank parchment", function(world)
    local LAND, BLANK = Seamless().MEDIA .. "land.png", Seamless().MEDIA .. "blank\\1.png"
    Seamless().Zones[1] = true
    Setup(world)
    Open(world, 1)
    equal(ArtMasked(world, LAND, BLANK), 2, "both copies of the paper, through the zone's blank parchment")
    expect(Art(world)[150], "its explored area")
    Set(world, "enabled", false)
    equal(ArtMasked(world, LAND, BLANK), 0, "gone with the feature")
end)

test("shows areas explored while it was off once back on", function(world)
    Setup(world)
    world.exploredMapTextures[1] = {}
    Open(world, 1)
    expect(not Art(world)[150], "unexplored area hidden")
    Set(world, "enabled", false)
    world.exploredMapTextures[1] = {
        { fileDataIDs = { 150 }, offsetX = 300, offsetY = 200, textureWidth = 256, textureHeight = 256 },
    }
    world:Fire("MAP_EXPLORATION_UPDATED")
    Set(world, "enabled", true)
    Open(world, 1)
    expect(Art(world)[150], "the area explored meanwhile")
end)

-- The view opened from Westfall, panned to Elwynn Forest's middle, the mouse there, in combat:
-- the wheel zooms in on Elwynn Forest past where it fits without handing Blizzard's map back
-- (refused in combat, onto a map it doesn't show). Elwynn Forest fits the view at zoom 10, the
-- view at zoom 8: one notch in to 10, two to 12.5, three to 15.6.
local function OnElwynnInCombat(world)
    Open(world, 5)
    Drag(world, 0.75, 0.6)
    world:RunFrames(1)
    world:EnterCombat()
    PointAt(world, 0.75, 0.6)
end

-- Turns the wheel `count` notches (out if negative), then lets the view settle.
local function Notches(world, count)
    for _ = 1, math.abs(count) do
        world:MapWheel(count > 0 and 1 or -1)
    end
    world:RunFrames(1)
end

-- (Elwynn Forest's tile 106 is in its middle: drawn once stitched, twice once whole too)
test("draws the zone in the middle whole three notches in, stitched again back where it fits", function(world)
    Setup(world)
    OnElwynnInCombat(world)
    equal(Art(world)[106], 1, "only stitched")
    Notches(world, 2)
    equal(Art(world)[106], 1, "two notches in: still only stitched")
    Notches(world, 1)
    equal(Art(world)[106], 2, "three notches in: whole too")
    Notches(world, -1)
    equal(Art(world)[106], 2, "back a notch: still whole")
    Notches(world, -1)
    equal(Art(world)[106], 1, "back where it fits: only stitched")
end)

test("keeps the zone whole while most of the land in view is its own", function(world)
    -- (Westfall's land reaches a little way into Elwynn Forest's map, around (0.71, 0.6))
    local AtPosition = C_Map.GetMapInfoAtPosition
    C_Map.GetMapInfoAtPosition = function(uiMapID, x, y)
        local u, v = 0.55 + x * 0.4, 0.3 + y * 0.4
        if uiMapID == 10 and u >= 0.70 and u < 0.718 and v >= 0.595 and v < 0.605 then
            return C_Map.GetMapInfo(5)
        end
        return AtPosition(uiMapID, x, y)
    end
    Setup(world)
    OnElwynnInCombat(world)
    Notches(world, 3)
    Drag(world, 0.715, 0.6)
    world:RunFrames(1)
    equal(Art(world)[106], 2, "Elwynn Forest still whole, its land in the middle Westfall's")
    expect((Art(world)[506] or 0) <= 1, "Westfall not whole")
end)

test("draws whole the zone whose land is in the middle, not a neighbour's map reaching over it", function(world)
    -- (Westfall's map, bigger, reaches over Elwynn Forest's west edge)
    world:SetMapRect(5, { 0.58, 0.72, 0.53, 0.67 })
    Setup(world)
    Open(world, 5)
    Drag(world, 0.705, 0.6)
    world:RunFrames(1)
    world:EnterCombat()
    PointAt(world, 0.705, 0.6)
    Notches(world, 5)
    equal(Art(world)[106], 2, "Elwynn Forest whole")
    expect((Art(world)[506] or 0) <= 1, "Westfall not whole")
end)

test("draws a zone whole on its own parchment", function(world)
    Seamless().Zones[1] = true
    local LAND = Seamless().MEDIA .. "land.png"
    Setup(world)
    OnElwynnInCombat(world)
    local stitched = Art(world)[LAND]
    expect(stitched, "the land paper over the stitched zone")
    Notches(world, 3)
    equal(Art(world)[106], 2, "Elwynn Forest whole")
    equal(Art(world)[LAND], stitched, "no more land paper")
end)

-- Zooming and panning -------------------------------------------------------------------------

test("zooms toward the point under the mouse with the wheel", function(world)
    Setup(world)
    Open(world, 10)
    local _, _, before = View()
    PointAt(world, 0.65, 0.6)
    world:MapWheel(-1)
    world:RunFrames(1)
    local _, _, after = View()
    Near(after, before * 1.25, "one notch out")
    local u, v = UnderMouse(world)
    Near(u, 0.65, "the point under the mouse")
    Near(v, 0.6, "the point under the mouse")
    equal(WorldMapFrame:GetMapID(), 10, "Blizzard's map still on Eastern Kingdoms")
end)

test("pans across the world, past Blizzard's map", function(world)
    Setup(world)
    Open(world, 1)
    Drag(world, 0.62, 0.6)
    world:RunFrames(1)
    local u, v, shown = View()
    Near(u, 0.62, "the view in Westfall")
    Near(v, 0.6, "the view in Westfall")
    Near(shown, 0.125, "the zoom kept")
    equal(WorldMapFrame:GetMapID(), 1, "Blizzard's map still on Elwynn Forest")
end)

test("a click on a continent zooms in, a right click back out to the world's map", function(world)
    Setup(world)
    Open(world, 947)
    PointAt(world, 0.75, 0.5)
    world:MapClick()
    world:RunFrames(1)
    local u, _, shown = View()
    Near(u, 0.75, "Eastern Kingdoms in the middle")
    Near(shown, 0.4, "Eastern Kingdoms whole")
    equal(WorldMapFrame:GetMapID(), 947, "Blizzard's map still on Azeroth")
    world:MapClick("RightButton")
    world:RunFrames(1)
    expect(not View(), "handed back to Azeroth, Blizzard's map")
    equal(#world.openWorldMapCalls, 0, "without opening a map")
end)

test("a drag isn't a click", function(world)
    Setup(world)
    Open(world, 947)
    PointAt(world, 0.75, 0.5)
    world:MouseDown("LeftButton")
    local x, y = world.mouse.x, world.mouse.y
    world:MoveMouse(x + 30, y)
    world:MoveMouse(x, y)
    world:MouseUp("LeftButton")
    world:RunFrames(1)
    local _, _, shown = View()
    Near(shown, 1, "no zoom")
end)

-- Handing back -------------------------------------------------------------------------------

test("hands Blizzard's map back once the wheel comes to a zone", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.69, 0.6)
    world:MapWheel(1)
    equal(#world.openWorldMapCalls, 1, "Blizzard's map opened")
    equal(world.openWorldMapCalls[1].mapID, 5, "on Westfall, under the mouse")
    expect(world.openWorldMapCalls[1].hardware, "from the wheel")
    world:RunFrames(2)
    expect(not View(), "the seamless view gone")
    expect(next(Art(world)) == nil, "no stitched art left")
    equal(WorldMapFrame:GetMapID(), 5, "Blizzard's map on Westfall")
    local u, _, shown = world:MapView()
    Near(u, 0.65, "Westfall whole")
    Near(shown, 0.1, "Westfall whole")
end)

test("hands back to the map it opened on, zooming back in", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.75, 0.6)
    world:MapWheel(1)
    world:RunFrames(2)
    expect(not View(), "the seamless view gone")
    equal(#world.openWorldMapCalls, 0, "Blizzard's map already there")
    equal(WorldMapFrame:GetMapID(), 1, "Blizzard's map on Elwynn Forest")
end)

test("a click zooms into the zone under the mouse, handed back there", function(world)
    Setup(world)
    Open(world, 947)
    PointAt(world, 0.65, 0.6)
    world:MapClick()
    world:RunFrames(1)
    expect(View(), "Eastern Kingdoms first, in the seamless view")
    equal(#world.openWorldMapCalls, 0, "Blizzard's map left on Azeroth")
    PointAt(world, 0.65, 0.6)
    world:MapClick()
    equal(world.openWorldMapCalls[1].mapID, 5, "Blizzard's map opened on Westfall")
    world:RunFrames(2)
    expect(not View(), "the seamless view gone")
    equal(WorldMapFrame:GetMapID(), 5, "Blizzard's map on Westfall")
end)

test("draws the zone it hands back to whole as it glides there", function(world)
    Setup(world)
    Open(world, 1)
    equal(Art(world)[101], 1, "Elwynn Forest only stitched")
    PointAt(world, 0.75, 0.6)
    world:MapWheel(1)
    world:RunFrames(0.3)
    equal(Art(world)[101], 2, "Elwynn Forest stitched, and whole")
end)

test("hands back to the map Blizzard changes to, and closes on one it can't draw", function(world)
    Setup(world)
    Open(world, 1)
    world:OpenQuestDetails(5)
    world:RunFrames(2)
    expect(not View(), "handed back for a quest's details")
    equal(WorldMapFrame:GetMapID(), 5, "Blizzard's map on the quest's")
    Open(world, 5)
    expect(View(), "open again")
    world:ShowMap(3)
    expect(not View(), "closed at once on a dungeon")
end)

test("opens again with the wheel as it fades out after handing back", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.75, 0.6)
    world:MapWheel(1)
    world:RunFrames(0.45)
    world:PointMouseAt(0.75, 0.6)
    world:MapWheel(-1)
    world:RunFrames(1)
    local _, _, shown = View()
    expect(shown, "open again")
    Near(shown, 0.125, "one notch out from Elwynn Forest whole")
end)

test("stays open when the wheel zooms back out during the glide handing back", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.69, 0.6)
    world:MapWheel(1)
    equal(WorldMapFrame:GetMapID(), 5, "Blizzard's map opened on Westfall")
    world:RunFrames(0.2)
    world:MapWheel(-1)
    world:RunFrames(1)
    expect(View(), "the view still open")
    equal(Seamless().View:GetFrame():GetAlpha(), 1, "not fading")
    expect((Art(world)[506] or 0) <= 1, "Westfall no longer drawn whole")
    -- (zooming in on Westfall again: handed back onto Blizzard's map, already there)
    PointAt(world, 0.65, 0.6)
    Notches(world, 2)
    world:RunFrames(1)
    expect(not View(), "handed back")
    equal(#world.openWorldMapCalls, 1, "without opening Blizzard's map again")
end)

test("still closes when Blizzard changes its map as the view fades out", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.75, 0.6)
    world:MapWheel(1)
    world:RunFrames(0.45)
    world:OpenQuestDetails(5)
    world:RunFrames(0.15)
    expect(not View(), "closed once faded, still gliding to the quest's map")
    equal(WorldMapFrame:GetMapID(), 5, "Blizzard's map on the quest's")
end)

test("leaves Blizzard's wheel alone while the fading view glides to a map Blizzard changed to", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.75, 0.6)
    world:MapWheel(1)
    world:RunFrames(0.45)
    world:ShowMap(5)
    world:NextFrame()
    world:PointMouseAt(0.65, 0.6)
    world:MapWheel(-1)
    world:RunFrames(1)
    expect(not View(), "not opened again: it fades out")
end)

test("raises Blizzard's quest log toggle over the view while it shows", function(world)
    Setup(world)
    Open(world, 1)
    equal(WorldMapFrame.SidePanelToggle:GetFrameStrata(), "HIGH", "over the view")
    world:CloseMap()
    equal(WorldMapFrame.SidePanelToggle:GetFrameStrata(), "MEDIUM", "back in the map's own")
end)

test("closes with the map", function(world)
    Setup(world)
    Open(world, 1)
    world:CloseMap()
    expect(not View(), "closed")
    world:OpenMap(1)
    world:RunFrames(1)
    expect(not View(), "Blizzard's map on opening it again")
end)

test("stays in the seamless view in combat, where Blizzard's map can't be opened", function(world)
    Setup(world)
    Open(world, 1)
    world:EnterCombat()
    PointAt(world, 0.69, 0.6)
    world:MapWheel(1)
    world:RunFrames(1)
    equal(#world.openWorldMapCalls, 0, "Blizzard's map not opened")
    equal(#world.forbidden, 0, "nothing blocked")
    local _, _, shown = View()
    Near(shown, 0.1, "zoomed in on Westfall, in the seamless view")
    world:MapWheel(1)
    world:RunFrames(1)
    _, _, shown = View()
    Near(shown, 0.08, "and on, past where it fits")
    world:MapClick()
    world:RunFrames(1)
    expect(View(), "a click stays too")
    equal(world.errors[#world.errors], ERR_NOT_IN_COMBAT, "saying why")
    PointAt(world, 0.75, 0.6)
    for _ = 1, 2 do
        world:MapWheel(-1)
    end
    world:RunFrames(1)
    world:MapWheel(1)
    world:RunFrames(2)
    expect(not View(), "handed back onto Blizzard's own map, Elwynn Forest, in combat too")
end)

-- Map pins, icons and the arrow ---------------------------------------------------------------

test("leaves map pins on Blizzard's map to Blizzard's", function(world)
    Setup(world)
    world:OpenMap(1)
    world:PointMouseAt(0.72, 0.62)
    world.ctrl = true
    world:MapClick()
    world.ctrl = false
    equal(world.waypoint.uiMapID, 1, "Ctrl Click: on Elwynn Forest")
    Near(world.waypoint.position.x, 0.2, "where it was clicked")
end)

test("places map pins on the map under the mouse", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.69, 0.6)
    world.ctrl = true
    world:MapClick()
    world.ctrl = false
    equal(world.waypoint.uiMapID, 5, "on Westfall")
    Near(world.waypoint.position.x, 0.9, "where it was clicked on Westfall")
    Near(world.waypoint.position.y, 0.5, "where it was clicked on Westfall")
    world.waypoint = nil
    WorldMapFrame.WorldMapTrackingPinButton.isActive = true
    world:MapClick()
    WorldMapFrame.WorldMapTrackingPinButton.isActive = false
    equal(world.waypoint.uiMapID, 5, "a click with the pin button on")
    local _, _, shown = View()
    Near(shown, 0.125, "and no zoom")
end)

local function WaypointPin()
    return WorldMapFrame:EnumeratePinsByTemplate("WaypointLocationPinTemplate")()
end

test("leaves Shift Click on Blizzard's map pin to Blizzard's", function(world)
    world:OpenMap(1)
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(1, 0.2, 0.4))
    world.modifiedClick = "CHATLINK"
    world:ClickPin(WaypointPin())
    equal(#world.chatLinks, 1, "its link in chat")
    equal(world.clipboard, "/mappin 1 20.0 40.0", "its command copied")
end)

test("leaves Blizzard's map pin copying its command once the view handed back", function(world)
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.75, 0.6)
    world:MapWheel(1)
    world:RunFrames(2)
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(1, 0.2, 0.4))
    world.modifiedClick = "CHATLINK"
    world:ClickPin(WaypointPin())
    equal(world.clipboard, "/mappin 1 20.0 40.0", "its command copied")
    equal(#world.forbidden, 0, "nothing blocked")
end)

test("shows the map pin on the view, shared in chat with Shift Click", function(world)
    Setup(world)
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(5, 0.9, 0.5))
    Open(world, 1)
    expect(AtlasDrawn(world, "Waypoint-MapPin-Untracked"), "the map pin")
    PointAt(world, 0.69, 0.6)
    world:NextFrame()
    world.modifiedClick = "CHATLINK"
    world:MapClick()
    world.modifiedClick = nil
    equal(#world.chatLinks, 1, "its link in chat")
    equal(world.chatLinks[1], C_Map.GetUserWaypointHyperlink(), "the map pin's link")
    equal(#world.forbidden, 0, "nothing blocked")
end)

test("shows the log's quests on the view, with Blizzard's markers, while turned on", function(world)
    world.questLog = {
        { questID = 1, title = "Items of Some Consequence", onMap = { x = 0.4, y = 0.75 } },
        { questID = 2, title = "Crime and Punishment", onMap = { x = 0.42, y = 0.75 } },
        {
            questID = 3,
            title = "The Defias Brotherhood",
            onMap = { x = 0.44, y = 0.75 },
            classification = Enum.QuestClassification.Campaign,
            isComplete = true,
        },
    }
    world.superTracked = 2
    Setup(world)
    Open(world, 1)
    expect(AtlasDrawn(world, "UI-QuestPoi-QuestNumber"), "a quest's marker")
    expect(AtlasDrawn(world, "Quest-In-Progress-Icon-yellow"), "in progress")
    expect(AtlasDrawn(world, "UI-QuestPoi-QuestNumber-SuperTracked"), "the quest followed")
    expect(AtlasDrawn(world, "Quest-In-Progress-Icon-Brown"), "in progress, followed")
    expect(AtlasDrawn(world, "UI-QuestPoiCampaign-QuestNumber"), "a campaign quest's marker")
    expect(AtlasDrawn(world, "UI-QuestPoiCampaign-QuestBangTurnIn"), "ready to turn in")
    Set(world, "quests", false)
    expect(not AtlasDrawn(world, "UI-QuestPoi-QuestNumber"), "turned off")
end)

-- A quest of the log in Westfall, placed on Eastern Kingdoms' map.
local function WestfallQuest(world)
    local x, y = Seamless().Geometry:FromWorld(10, 0.65, 0.6)
    world.questLog = { { questID = 1, title = "Items of Some Consequence", onMap = { x = x, y = y, mapID = 10 } } }
end

test("a click on a quest's marker follows it, handed back on its zone", function(world)
    WestfallQuest(world)
    Setup(world)
    Open(world, 10)
    PointAt(world, 0.65, 0.6)
    world:NextFrame()
    world:MapClick()
    equal(C_SuperTrack.GetSuperTrackedQuestID(), 1, "followed")
    equal(world.openWorldMapCalls[1].mapID, 5, "Blizzard's map opened on Westfall")
    world:RunFrames(2)
    expect(not View(), "handed back")
end)

test("a click on a quest's marker in combat goes to its zone, saying it can't be followed", function(world)
    WestfallQuest(world)
    Setup(world)
    Open(world, 10)
    world:EnterCombat()
    PointAt(world, 0.65, 0.6)
    world:NextFrame()
    world:MapClick()
    expect(
        C_SuperTrack.GetSuperTrackedQuestID() ~= 1,
        "not followed: Blizzard's open map would put its pins up from ours"
    )
    equal(#world.openWorldMapCalls, 0, "Blizzard's map not opened")
    equal(table.concat(world.errors, ", "), ERR_NOT_IN_COMBAT, "saying why, once")
    world:RunFrames(1)
    local u, v, shown = View()
    Near(u, 0.65, "Westfall in the middle")
    Near(v, 0.6, "Westfall in the middle")
    Near(shown, 0.1, "Westfall whole")
end)

-- Whether the texture is on the seamless view.
local function OnView(texture)
    local view = Seamless().View:GetFrame()
    local frame = texture.owner
    while frame and frame ~= view do
        frame = frame.parent
    end
    return frame ~= nil
end

-- The first texture drawn on the view showing `atlas`, and where its frame is from the view's middle.
local function DrawnAtlas(world, atlas)
    for _, texture in ipairs(world.textures) do
        if texture.atlas == atlas and world:IsRegionDrawn(texture) and OnView(texture) then
            local anchor = texture.owner.anchors[1]
            return texture, anchor[4], anchor[5]
        end
    end
end

test("shows the group's members on the view, in their class's colour, named on hover", function(world)
    Setup(world)
    world:JoinGroup("Ahnna")
    local member = world.partyMembers[1]
    world.npcClasses[member.guid] = "MAGE"
    -- (in the middle of Elwynn Forest)
    member.position = { x = 500, y = 500, continentID = 0 }
    Open(world, 1)
    local dot, before = DrawnAtlas(world, "WhiteCircle-RaidBlips")
    expect(dot, "the member's dot")
    equal(table.concat(dot.tint, " "), table.concat({ RAID_CLASS_COLORS.MAGE:GetRGB() }, " "), "a mage's colour")
    PointAt(world, 0.75, 0.6)
    world:NextFrame()
    equal(world.tooltip, RAID_CLASS_COLORS.MAGE:WrapTextInColorCode("Ahnna"), "their name")
    member.position = { x = 600, y = 500, continentID = 0 }
    world:RunFrames(0.1)
    local _, after = DrawnAtlas(world, "WhiteCircle-RaidBlips")
    local _, _, shown = View()
    Near(after - before, 0.01 / shown * 1000, "following them as they move")
    world:LeaveGroup()
    expect(not DrawnAtlas(world, "WhiteCircle-RaidBlips"), "gone once they've left")
end)

test("shows the player's arrow on the view", function(world)
    Setup(world)
    world.position = { x = 500, y = 500, continentID = 0 }
    world.facing = 1
    world:OpenMap(10)
    world:RunFrames(1)
    expect(not AtlasDrawn(world, ARROW), "Blizzard's own on Blizzard's map")
    Open(world, 10)
    expect(AtlasDrawn(world, ARROW), "ours on the seamless view")
    world.secretValues[world.facing] = true
    world:RunFrames(1)
    expect(not AtlasDrawn(world, ARROW), "while the game keeps it secret")
end)

test("keeps the player's arrow on the player as the view pans", function(world)
    Setup(world)
    world.position = { x = 500, y = 500, continentID = 0 }
    world.facing = 1
    Open(world, 10)
    local _, before = DrawnAtlas(world, ARROW)
    Drag(world, 0.70, 0.5)
    world:NextFrame()
    local _, after = DrawnAtlas(world, ARROW)
    local _, _, shown = View()
    Near(after - before, 0.05 / shown * 1000, "moved with the view on the next frame")
end)

-- How many textures showing `atlas` are drawn.
local function CountAtlas(world, atlas)
    local count = 0
    for _, texture in ipairs(world.textures) do
        if texture.atlas == atlas and world:IsRegionDrawn(texture) and OnView(texture) then
            count = count + 1
        end
    end
    return count
end

-- The quest marker's frame drawn for the first texture showing `atlas`.
local function Marker(world, atlas)
    local texture = DrawnAtlas(world, atlas)
    return texture and texture.owner
end

-- The zone label's text on the view.
local function Label(world)
    local view = Seamless().View:GetFrame()
    for _, fontString in ipairs(world.fontStrings) do
        local frame = fontString.owner
        while frame and frame ~= view do
            frame = frame.parent
        end
        if frame then
            return fontString:GetText()
        end
    end
end

test("keeps a hovered quest's marker lit as the view zooms and the log changes", function(world)
    WestfallQuest(world)
    Setup(world)
    Open(world, 10)
    PointAt(world, 0.65, 0.6)
    world:NextFrame()
    local marker = Marker(world, "UI-QuestPoi-QuestNumber")
    expect(marker.Highlight:IsShown(), "lit on hover")
    world:MapWheel(-1)
    world:RunFrames(1)
    expect(Marker(world, "UI-QuestPoi-QuestNumber").Highlight:IsShown(), "still lit, zoomed out about it")
    world:Fire("QUEST_LOG_UPDATE")
    world:NextFrame()
    expect(Marker(world, "UI-QuestPoi-QuestNumber").Highlight:IsShown(), "still lit as the log changes")
end)

test(
    "shows Blizzard's quest tooltip on a marker: the objectives left, or where to go for the quest followed",
    function(world)
        WestfallQuest(world)
        world.questLog[1].objectives = { world:Objective("Gnoll Paw", 8, 3), world:Objective("Bandana", 2, 2) }
        world.questLog[1].waypointText = "Go to Sentinel Hill"
        Setup(world)
        Open(world, 10)
        PointAt(world, 0.65, 0.6)
        world:NextFrame()
        equal(world.tooltip, "Items of Some Consequence", "its title")
        equal(
            table.concat(world.tooltipLines, ", "),
            QUEST_DASH .. world.questLog[1].objectives[1].text,
            "the objective left"
        )
        C_SuperTrack.SetSuperTrackedQuestID(1)
        world:NextFrame()
        equal(table.concat(world.tooltipLines, ", "), QUEST_DASH .. "Go to Sentinel Hill", "followed: where to go")
        PointAt(world, 0.75, 0.6)
        world:NextFrame()
        expect(not world.tooltipShown, "hidden off it")
        PointAt(world, 0.65, 0.6)
        world:NextFrame()
        local other = CreateFrame("Frame")
        GameTooltip:SetOwner(other, "ANCHOR_RIGHT")
        GameTooltip:Show()
        PointAt(world, 0.75, 0.6)
        world:NextFrame()
        expect(world.tooltipShown and GameTooltip:IsOwned(other), "another frame's tooltip left up")
    end
)

test(
    "treats the map pin on the view as Blizzard's: its tooltip, tracked with a click, removed with Ctrl Click",
    function(world)
        Setup(world)
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(5, 0.9, 0.5))
        Open(world, 1)
        PointAt(world, 0.69, 0.6)
        world:NextFrame()
        equal(world.tooltip, MAP_PIN_SHARING, "its tooltip")
        equal(table.concat(world.tooltipLines, ", "), MAP_PIN_SHARING_TOOLTIP .. ", " .. MAP_PIN_REMOVE, "its lines")
        expect(Marker(world, "Waypoint-MapPin-Untracked").Highlight:IsShown(), "lit on hover")
        world:MapClick()
        expect(C_SuperTrack.IsSuperTrackingUserWaypoint(), "tracked")
        expect(tContains(world.sounds, SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON), "with Blizzard's sound")
        local _, _, shown = View()
        Near(shown, 0.125, "no zoom")
        expect(AtlasDrawn(world, "Waypoint-MapPin-Tracked"), "drawn tracked")
        world.ctrl = true
        world:NextFrame()
        equal(world.mapCursor, "MAP_PIN_CURSOR", "the map pin's cursor with Ctrl")
        world:MapClick()
        world.ctrl = false
        world:NextFrame()
        expect(not world.waypoint, "removed")
        expect(not world.superTrackingWaypoint, "untracked")
        equal(world.mapCursor, nil, "the cursor back once Ctrl is up")
        equal(table.concat(world.trackerEvents, " "), "", "kept from the objective tracker")
        equal(#world.forbidden, 0, "nothing blocked")
    end
)

test(
    "a click on a quest's marker watches it, with Blizzard's sound; Shift Click links it, or unwatches it",
    function(world)
        WestfallQuest(world)
        Setup(world)
        Open(world, 10)
        PointAt(world, 0.65, 0.6)
        world:NextFrame()
        world.modifiedClick = "CHATLINK"
        world.shift = true
        world.chatBoxOpen = true
        world:MapClick()
        world.modifiedClick, world.shift, world.chatBoxOpen = nil, nil, nil
        equal(world.chatLinks[1], "quest:1", "linked in chat")
        expect(C_SuperTrack.GetSuperTrackedQuestID() ~= 1, "not followed")
        equal(#world.openWorldMapCalls, 0, "no zone opened")
        world.sounds = {}
        world:MapClick()
        equal(table.concat(world.sounds, " "), SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Blizzard's sound")
        expect(QuestUtils_IsQuestWatched(1), "watched")
        equal(C_SuperTrack.GetSuperTrackedQuestID(), 1, "followed")
        equal(table.concat(world.trackerEvents, " "), "", "kept from the objective tracker")
        equal(table.concat(world.questLogEvents, " "), "", "and from the quest log")
        world:RunFrames(2)
        Open(world, 5)
        PointAt(world, 0.65, 0.6)
        world:NextFrame()
        world.modifiedClick = "CHATLINK"
        world.shift = true
        world:MapClick()
        world.modifiedClick, world.shift = nil, nil
        expect(not QuestUtils_IsQuestWatched(1), "Shift Click, the chat box closed: unwatched, as Blizzard's")
        equal(table.concat(world.trackerEvents, " "), "", "kept from the objective tracker")
    end
)

test("follows the map's quest filter, and always shows the quest followed", function(world)
    world.questLog = {
        { questID = 1, title = "Items of Some Consequence", onMap = { x = 0.4, y = 0.75 } },
        { questID = 2, title = "Crime and Punishment", onMap = { x = 0.42, y = 0.75 } },
        { questID = 3, title = "A bonus objective", onMap = { x = 0.44, y = 0.75 }, isBonus = true },
        { questID = 4, title = "A map indicator", onMap = { x = 0.46, y = 0.75 }, isMapIndicatorQuest = true },
        { questID = 5, title = "Not loaded", onMap = { x = 0.48, y = 0.75 }, noData = true },
    }
    world.superTracked = 2
    Setup(world)
    Open(world, 1)
    equal(CountAtlas(world, "UI-QuestPoi-QuestNumber"), 1, "only the quests Blizzard's would show")
    Set(world, "quests", false)
    equal(CountAtlas(world, "UI-QuestPoi-QuestNumber"), 0, "the others off")
    expect(AtlasDrawn(world, "UI-QuestPoi-QuestNumber-SuperTracked"), "the quest followed still")
    C_CVar.SetCVar("questPOI", "0")
    expect(not AtlasDrawn(world, "UI-QuestPoi-QuestNumber-SuperTracked"), "none with the map's filter off")
end)

test("shows the quest followed where the game sends the player next, when it isn't placed itself", function(world)
    local x, y = Seamless().Geometry:FromWorld(10, 0.65, 0.6)
    world.questLog = { { questID = 1, title = "Items of Some Consequence", waypoint = { x = x, y = y, mapID = 10 } } }
    world.superTracked = 1
    Setup(world)
    Open(world, 10)
    local _, mx, my = DrawnAtlas(world, "UI-QuestPoi-QuestNumber-SuperTracked")
    local _, _, shown = View()
    local cu, cv = View()
    Near(mx, (0.65 - cu) / shown * 1000, "where it's sent next")
    Near(my, -(0.6 - cv) / shown * 700, "where it's sent next")
end)

test("draws the quest followed over the others, and icons slide out under the view's edge", function(world)
    WestfallQuest(world)
    table.insert(world.questLog, { questID = 2, title = "Crime and Punishment", onMap = world.questLog[1].onMap })
    world.superTracked = 2
    Setup(world)
    Open(world, 10)
    PointAt(world, 0.65, 0.6)
    world:NextFrame()
    equal(world.tooltip, "Crime and Punishment", "the quest followed, on top")
    local followed = Marker(world, "UI-QuestPoi-QuestNumber-SuperTracked")
    local other = Marker(world, "UI-QuestPoi-QuestNumber")
    expect(followed:GetFrameLevel() > other:GetFrameLevel(), "drawn over the other")
    local cu, cv, shown = View()
    local function At(pixels)
        local px, py = Seamless().Geometry:FromWorld(10, cu + shown / 2 + pixels * shown / 1000, cv)
        world.questLog =
            { { questID = 1, title = "Items of Some Consequence", onMap = { x = px, y = py, mapID = 10 } } }
        world:Fire("QUEST_LOG_UPDATE")
    end
    At(10)
    expect(DrawnAtlas(world, "UI-QuestPoi-QuestNumber"), "just past the edge: half out under it")
    At(40)
    expect(not DrawnAtlas(world, "UI-QuestPoi-QuestNumber"), "past its width: not drawn")
end)

test("a click during a glide aims from where it's going: a double click goes two levels down", function(world)
    Setup(world)
    Open(world, 1)
    for _ = 1, 2 do
        world:MapClick("RightButton")
        world:RunFrames(1)
    end
    local _, _, shown = View()
    Near(shown, 1, "the whole world")
    PointAt(world, 0.65, 0.6)
    world:MapClick()
    world:NextFrame()
    world:MapClick()
    equal(world.openWorldMapCalls[1] and world.openWorldMapCalls[1].mapID, 5, "on to Westfall, handed back")
end)

test("names the map under the cursor with its level range, or the area of a zone zoomed in on", function(world)
    world.mapLevels[5] = { 10, 20 }
    world.areaNames[5] = "Sentinel Hill"
    Setup(world)
    Open(world, 1)
    PointAt(world, 0.69, 0.6)
    world:RunFrames(0.1)
    equal(
        Label(world),
        "Westfall" .. RGBTableToColorCode(QuestDifficultyColors.difficult) .. " (10-20)" .. FONT_COLOR_CODE_CLOSE,
        "the zone a click goes to"
    )
    world:EnterCombat()
    for _ = 1, 6 do
        world:MapWheel(1)
    end
    world:RunFrames(1)
    equal(Label(world), "Sentinel Hill", "zoomed in on it: the area")
    PointAt(world, 0.65, 2)
    world:RunFrames(0.1)
    equal(Label(world), "", "nothing off the view")
end)

test("shows the corpse on the view", function(world)
    local Geometry = Seamless().Geometry
    local continent = Geometry:Continents()[1]
    local x, y = Geometry:FromWorld(continent, 0.65, 0.6)
    world.corpse[continent] = { x = x, y = y }
    Setup(world)
    Open(world, 10)
    expect(world:IsDrawn("Interface\\Minimap\\POIIcons"), "Blizzard's corpse")
    PointAt(world, 0.65, 0.6)
    world:NextFrame()
    equal(world.tooltip, CORPSE_RED, "named on hover")
    world.corpse = {}
    world:Fire("PLAYER_ALIVE")
    expect(not world:IsDrawn("Interface\\Minimap\\POIIcons"), "gone once alive")
end)

test("names every group member under the cursor, at Blizzard's size", function(world)
    Setup(world)
    world:JoinGroup("Ahnna Stormhold")
    world:GuestJoins("Brom")
    for _, member in ipairs(world.partyMembers) do
        member.position = { x = 500, y = 500, continentID = 0 }
    end
    world.npcClasses[world.partyMembers[1].guid] = "MAGE"
    world.npcClasses[world.partyMembers[2].guid] = "WARRIOR"
    Open(world, 1)
    local dot = DrawnAtlas(world, "WhiteCircle-RaidBlips")
    equal(dot.width, 11, "a party member's size")
    PointAt(world, 0.75, 0.6)
    world:NextFrame()
    equal(
        world.tooltip,
        RAID_CLASS_COLORS.MAGE:WrapTextInColorCode("Ahnna Stormhold")
            .. "\n"
            .. RAID_CLASS_COLORS.WARRIOR:WrapTextInColorCode("Brom"),
        "both, one per line, by their full names"
    )
end)

test("draws group members' new looks after the roster changed while the view was closed", function(world)
    Setup(world)
    world:JoinGroup("Ahnna")
    local member = world.partyMembers[1]
    world.npcClasses[member.guid] = "MAGE"
    member.position = { x = 500, y = 500, continentID = 0 }
    Open(world, 1)
    world:CloseMap()
    world:LeaveGroup()
    world:JoinGroup("Brom")
    world.npcClasses[world.partyMembers[1].guid] = "WARRIOR"
    world.partyMembers[1].position = { x = 500, y = 500, continentID = 0 }
    Open(world, 1)
    local dot = DrawnAtlas(world, "WhiteCircle-RaidBlips")
    equal(table.concat(dot.tint, " "), table.concat({ RAID_CLASS_COLORS.WARRIOR:GetRGB() }, " "), "a warrior's colour")
end)

test("lights up the marker of the quest hovered in the quest log", function(world)
    WestfallQuest(world)
    Setup(world)
    Open(world, 10)
    expect(not Marker(world, "UI-QuestPoi-QuestNumber").Highlight:IsShown(), "dark")
    world.logHighlight = 1
    world:RunFrames(0.1)
    expect(Marker(world, "UI-QuestPoi-QuestNumber").Highlight:IsShown(), "lit")
    world.logHighlight = nil
    world:RunFrames(0.1)
    expect(not Marker(world, "UI-QuestPoi-QuestNumber").Highlight:IsShown(), "dark again")
end)

test("shows map.friends' friends on the view, named on hover", function(world)
    world.friends = { { guid = "Player-1-0000000A", name = "Alice" } }
    world.players = { ["Player-1-0000000A"] = { name = "Alice", realm = "Forever", class = "WARRIOR" } }
    world:Setting("map.friends.enabled"):SetValue(true)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.2500:0.5000", "Alice-Forever")
    Open(world, 1)
    local dot = DrawnAtlas(world, "WhiteCircle-RaidBlips")
    expect(dot, "the friend's dot")
    equal(table.concat(dot.tint, " "), table.concat({ RAID_CLASS_COLORS.WARRIOR:GetRGB() }, " "), "a warrior's colour")
    PointAt(world, Seamless().Geometry:ToWorld(1, 0.25, 0.5))
    world:NextFrame()
    equal(world.tooltip, RAID_CLASS_COLORS.WARRIOR:WrapTextInColorCode("Alice"), "their name")
end)

test("gathers the quests on events, not as the view pans", function(world)
    WestfallQuest(world)
    Setup(world)
    Open(world, 10)
    local calls = 0
    local original = C_QuestLog.GetQuestsOnMap
    C_QuestLog.GetQuestsOnMap = function(...)
        calls = calls + 1
        return original(...)
    end
    Drag(world, 0.6, 0.5)
    world:RunFrames(0.5)
    equal(calls, 0, "not while panning")
    expect(AtlasDrawn(world, "UI-QuestPoi-QuestNumber"), "the marker moved along")
    world:Fire("QUEST_LOG_UPDATE")
    expect(calls > 0, "again as the log changes")
end)

test("lets clicks through a group member's dot to the quest under it, and draws the corpse over both", function(world)
    WestfallQuest(world)
    local Geometry = Seamless().Geometry
    local continent = Geometry:Continents()[1]
    Setup(world)
    world:JoinGroup("Ahnna")
    -- (on the quest's marker, in Westfall: x 650 of the world's 1000)
    world.partyMembers[1].position = { x = -500, y = 500, continentID = 0 }
    Open(world, 10)
    local dot, dx, dy = DrawnAtlas(world, "WhiteCircle-RaidBlips")
    local _, mx, my = DrawnAtlas(world, "UI-QuestPoi-QuestNumber")
    expect(dot and math.abs(dx - mx) < 12 and math.abs(dy - my) < 12, "the dot on the marker")
    PointAt(world, 0.65, 0.6)
    world:NextFrame()
    equal(world.tooltip, RAID_CLASS_COLORS.WARRIOR:WrapTextInColorCode("Ahnna"), "the member named, on top")
    world:MapClick()
    equal(C_SuperTrack.GetSuperTrackedQuestID(), 1, "the click follows the quest under the dot")
    world:RunFrames(2)
    local x, y = Geometry:FromWorld(continent, 0.65, 0.6)
    world.corpse[continent] = { x = x, y = y }
    -- (Blizzard's map handed back on Westfall)
    Open(world, 5)
    PointAt(world, 0.65, 0.6)
    world:NextFrame()
    equal(world.tooltip, CORPSE_RED, "the corpse on top of the member")
end)

test(
    "refuses map pin changes in combat, saying why, where Blizzard's map would put its pin up from ours",
    function(world)
        Setup(world)
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(5, 0.9, 0.5))
        Open(world, 1)
        world:EnterCombat()
        PointAt(world, 0.69, 0.6)
        world:NextFrame()
        world:MapClick()
        expect(not C_SuperTrack.IsSuperTrackingUserWaypoint(), "not tracked")
        world.ctrl = true
        world:MapClick()
        PointAt(world, 0.75, 0.6)
        world:MapClick()
        world.ctrl = false
        equal(world.waypoint.uiMapID, 5, "neither removed nor moved")
        equal(
            table.concat(world.errors, ", "),
            ("%s, %s, %s"):format(ERR_NOT_IN_COMBAT, ERR_NOT_IN_COMBAT, ERR_NOT_IN_COMBAT),
            "saying why"
        )
        for _, input in ipairs(world.mouseInputs) do
            expect(not input.inCombat, "no pin set up in combat")
        end
    end
)

-- Zooms the view out to the whole world, then clicks Eastern Kingdoms (at Westfall) to glide there.
local function GlideToEasternKingdoms(world)
    Open(world, 1)
    for _ = 1, 2 do
        world:MapClick("RightButton")
        world:RunFrames(1)
    end
    PointAt(world, 0.65, 0.6)
    world:MapClick()
    world:NextFrame()
end

test("a press during a glide lets it finish", function(world)
    Setup(world)
    GlideToEasternKingdoms(world)
    world:MouseDown("LeftButton")
    world:RunFrames(1)
    local _, _, shown = View()
    Near(shown, 0.4, "the glide went on to Eastern Kingdoms")
end)

test("a drag started during a glide stops it", function(world)
    Setup(world)
    GlideToEasternKingdoms(world)
    local x, y = world.mouse.x, world.mouse.y
    world:MouseDown("LeftButton")
    world:MoveMouse(x + 40, y)
    world:RunFrames(1)
    local _, _, shown = View()
    expect(shown > 0.5, "the drag stopped the glide")
    world:MoveMouse(x + 80, y)
    world:RunFrames(1)
    local _, _, after = View()
    Near(after, shown, "and it stays stopped")
    world:MouseUp("LeftButton")
end)

test("puts the cursor back when the view closes in pin mode", function(world)
    Setup(world)
    Open(world, 1)
    world.ctrl = true
    world:NextFrame()
    equal(world.mapCursor, "MAP_PIN_CURSOR", "the map pin's cursor")
    world:CloseMap()
    equal(world.mapCursor, nil, "put back")
    world.ctrl = false
end)

test("draws a friend who joins the group once, as a member", function(world)
    world.friends = { { guid = "Player-1-Ahnna", name = "Ahnna" } }
    world.players = { ["Player-1-Ahnna"] = { name = "Ahnna", realm = "Forever", class = "WARRIOR" } }
    world:Setting("map.friends.enabled"):SetValue(true)
    Setup(world)
    world:OpenMap(1)
    world:ReceiveWhisperAddon("1P:1:0.5000:0.5000", "Ahnna-Forever")
    world:JoinGroup("Ahnna")
    world.groupGUIDs["Player-1-Ahnna"] = true
    world.partyMembers[1].position = { x = 500, y = 500, continentID = 0 }
    Open(world, 1)
    equal(CountAtlas(world, "WhiteCircle-RaidBlips"), 1, "one dot")
end)

-- Continents' quests on Blizzard's map -----------------------------------------------------------

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

local function QuestPin(template, questID)
    for _, pin in ipairs(WorldMapFrame.pins) do
        if pin.template == template and pin.questID == questID then
            return pin
        end
    end
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
    expect(QuestPins(OUR_QUESTS)[1], "ours on the continent")
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

test("updates continents' quests as the log changes, but not in combat", function(world)
    SetupQuests(world)
    world:OpenMap(10)
    table.insert(world.questLog, { questID = 3, title = "Lost Necklace", onMap = { x = 0.5, y = 0.5 } })
    world:Fire("QUEST_LOG_UPDATE")
    expect(QuestPins(OUR_QUESTS)[3], "the quest just accepted")
    world:EnterCombat()
    table.insert(world.questLog, { questID = 4, title = "Princess Must Die!", onMap = { x = 0.2, y = 0.2 } })
    world:Fire("QUEST_LOG_UPDATE")
    expect(not QuestPins(OUR_QUESTS)[4], "not in combat")
    world:LeaveCombat()
    expect(QuestPins(OUR_QUESTS)[4], "once combat ends")
end)

test("names a continent's quest on hover, a click following it onto its zone", function(world)
    SetupQuests(world)
    -- (quest 1 in Westfall)
    local x, y = Seamless().Geometry:FromWorld(10, 0.65, 0.6)
    world.questLog[1].onMap = { x = x, y = y }
    world:OpenMap(10)
    local pin = QuestPin(OUR_QUESTS, 1)
    equal(pin.Background:GetAtlas(), "UI-QuestPoi-QuestNumber", "Blizzard's quest marker")
    equal(pin.Icon:GetAtlas(), "Quest-In-Progress-Icon-yellow", "in progress")
    pin:OnMouseEnter()
    equal(world.tooltip, "Items of Some Consequence", "its title")
    world:ClickOwnPin(pin)
    equal(C_SuperTrack.GetSuperTrackedQuestID(), 1, "followed")
    equal(WorldMapFrame:GetMapID(), 5, "Blizzard's map on its zone, Westfall")
end)

test("a click on a continent's quest in combat says it can't be followed", function(world)
    SetupQuests(world)
    -- (quest 1 in Westfall)
    local x, y = Seamless().Geometry:FromWorld(10, 0.65, 0.6)
    world.questLog[1].onMap = { x = x, y = y }
    world:OpenMap(10)
    world:EnterCombat()
    world:ClickOwnPin(QuestPin(OUR_QUESTS, 1))
    equal(C_SuperTrack.GetSuperTrackedQuestID(), 2, "not followed")
    equal(WorldMapFrame:GetMapID(), 10, "still on Eastern Kingdoms")
    equal(table.concat(world.errors, ", "), ERR_NOT_IN_COMBAT, "saying why, once")
    WorldMapFrame.WorldMapTrackingPinButton.isActive = true
    world:ClickOwnPin(QuestPin(OUR_QUESTS, 1))
    WorldMapFrame.WorldMapTrackingPinButton.isActive = false
    expect(not world.waypoint, "no map pin placed in pin mode")
    equal(world.errors[2], ERR_NOT_IN_COMBAT, "saying why")
    equal(#world.forbidden, 0, "nothing blocked")
end)

test("drops a continent's quests on a map change in combat", function(world)
    SetupQuests(world)
    world:OpenMap(10)
    world:EnterCombat()
    world:ShowMap(1)
    expect(next(QuestPins(OUR_QUESTS)) == nil, "none on the zone")
    world:ShowMap(10)
    expect(next(QuestPins(OUR_QUESTS)) == nil, "none back on the continent until combat ends")
    world:LeaveCombat()
    expect(QuestPins(OUR_QUESTS)[1], "back once it ends")
end)

test("continents' quests: Blizzard's tooltip and filter, Shift Click linking, lit from the quest log", function(world)
    SetupQuests(world)
    world.questLog[1].objectives = { world:Objective("Gnoll Paw", 8, 3) }
    world:OpenMap(10)
    local pin = QuestPin(OUR_QUESTS, 1)
    pin:OnMouseEnter()
    equal(world.tooltipLines[1], QUEST_DASH .. world.questLog[1].objectives[1].text, "the objective left")
    pin:OnMouseLeave()
    expect(not world.tooltipShown, "hidden on leaving")
    world.modifiedClick = "CHATLINK"
    world.shift = true
    world.chatBoxOpen = true
    world:ClickOwnPin(pin)
    world.modifiedClick, world.shift, world.chatBoxOpen = nil, nil, nil
    equal(world.chatLinks[1], "quest:1", "linked in chat")
    equal(WorldMapFrame:GetMapID(), 10, "not followed onto its zone")
    world.logHighlight = 1
    world:RunFrames(0.2)
    expect(QuestPin(OUR_QUESTS, 1).Highlight:IsShown(), "lit from the quest log")
    C_CVar.SetCVar("questPOI", "0")
    expect(next(QuestPins(OUR_QUESTS)) == nil, "none with the map's filter off")
    C_CVar.SetCVar("questPOI", "1")
    expect(QuestPins(OUR_QUESTS)[1], "back with it on")
end)

test("a continent's quest pin: no click when let go off it, a map pin in pin mode", function(world)
    SetupQuests(world)
    world:OpenMap(10)
    world:ClickOwnPin(QuestPin(OUR_QUESTS, 1), "LeftButton", false)
    equal(C_SuperTrack.GetSuperTrackedQuestID(), 2, "let go off it: not followed")
    WorldMapFrame.WorldMapTrackingPinButton.isActive = true
    world:ClickOwnPin(QuestPin(OUR_QUESTS, 1))
    WorldMapFrame.WorldMapTrackingPinButton.isActive = false
    equal(C_SuperTrack.GetSuperTrackedQuestID(), 2, "pin mode: not followed")
    equal(world.waypoint and world.waypoint.uiMapID, 10, "a map pin on the continent")
    Near(world.waypoint.position.x, 0.3, "at the quest's pin")
    equal(table.concat(world.trackerEvents, " "), "", "kept from the objective tracker")
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

-- Turning it off -------------------------------------------------------------------------------

test("turning it off closes the view, Blizzard's map as it was", function(world)
    Setup(world)
    Open(world, 1)
    Set(world, "enabled", false)
    world:RunFrames(1)
    expect(not View(), "the seamless view gone")
    expect(next(Art(world)) == nil, "no stitched art")
    equal(WorldMapFrame:GetMapID(), 1, "Blizzard's map on Elwynn Forest")
    local u, _, shown = world:MapView()
    Near(u, 0.75, "Elwynn Forest whole")
    Near(shown, 0.1, "Elwynn Forest whole")
    world:MapWheel(-1)
    world:RunFrames(1)
    expect(not View(), "not opened again while off")
    Set(world, "enabled", true)
    world:RunFrames(1)
    expect(not View(), "not opened by turning it back on")
    Open(world, 1)
    expect(Art(world)[101], "stitched again past Blizzard's widest view")
end)

test("ships every mask and paper its data lists", function()
    local function Exists(path)
        local file = io.open(path, "rb")
        if file then
            file:close()
        end
        return file ~= nil
    end
    local count = 0
    for mapID in pairs(Seamless().Zones) do
        count = count + 1
        expect(Exists(("modules/map/seamless/media/zone/%d.png"):format(mapID)), "zone " .. mapID)
        expect(Exists(("modules/map/seamless/media/blank/%d.png"):format(mapID)), "blank " .. mapID)
        expect(Seamless().Tints[mapID], "tint " .. mapID)
    end
    expect(count > 40, "zones listed")
    for mapID in pairs(Seamless().Lands) do
        expect(Exists(("modules/map/seamless/media/land/%d.png"):format(mapID)), "land " .. mapID)
    end
    for _, name in ipairs({ "feather-thin", "feather-wide", "feather-round", "land", "sea" }) do
        expect(Exists("modules/map/seamless/media/" .. name .. ".png"), name)
    end
    expect(Seamless().Papers.land > 0 and Seamless().Papers.sea > 0, "the papers' sizes")
end)
