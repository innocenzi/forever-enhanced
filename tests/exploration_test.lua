-- Exploration: the button over the world map, on zones, continents and the world, as the
-- player explores, on the seamless view's map, and turning it off.
-- The fake world (tests/wow.lua): Azeroth (947), Eastern Kingdoms (10) with Elwynn Forest
-- (1), Westfall (5) and Stormwind City (6, nothing to explore), Kalimdor (11) with
-- Durotar (2), a dungeon (3). Each map's art is uiMapID * 10.

local GOLDSHIRE, NORTHSHIRE, CRYSTAL_LAKE, MIRROR_LAKE, MOONBROOK, RAZOR_HILL = 101, 102, 103, 104, 201, 301
-- The achievement window's criteria colours: done, missing.
local DONE, MISSING = { 0, 1, 0 }, { 0.6, 0.6, 0.6 }

local function Exploration()
    return ForeverEnhanced:GetFeature("map", "exploration")
end

local function Button()
    return Exploration().Button:GetFrame()
end

local function Icon(world)
    for _, texture in ipairs(world.textures) do
        if texture.owner == Button() and texture.texture == "Interface\\Icons\\INV_Misc_Map_01" then
            return texture
        end
    end
end

local function Check(world)
    for _, texture in ipairs(world.textures) do
        if texture.owner == Button() and texture.atlas == "UI-LFG-ReadyMark" then
            return texture
        end
    end
end

local function Overlay(width, x, ...)
    return { width, 100, x, 0, ... }
end

local function Explored(width, x)
    return { fileDataIDs = { 1 }, offsetX = x, offsetY = 0, textureWidth = width, textureHeight = 100 }
end

-- Elwynn Forest: Goldshire explored, Northshire Valley in two overlays (the second
-- explored), Crystal Lake and Mirror Lake in one not explored. Westfall: Moonbrook,
-- explored. Durotar: Razor Hill, not explored.
local function Setup(world)
    world.areaNames = {
        [GOLDSHIRE] = "Goldshire",
        [NORTHSHIRE] = "Northshire Valley",
        [CRYSTAL_LAKE] = "Crystal Lake",
        [MIRROR_LAKE] = "Mirror Lake",
        [MOONBROOK] = "Moonbrook",
        [RAZOR_HILL] = "Razor Hill",
    }
    Exploration().Overlays[10] = {
        Overlay(100, 0, GOLDSHIRE),
        Overlay(110, 100, NORTHSHIRE),
        Overlay(120, 200, NORTHSHIRE),
        Overlay(130, 300, CRYSTAL_LAKE, MIRROR_LAKE),
    }
    Exploration().Overlays[50] = { Overlay(100, 0, MOONBROOK) }
    Exploration().Overlays[20] = { Overlay(100, 0, RAZOR_HILL) }
    world.exploredMapTextures[1] = { Explored(100, 0), Explored(120, 200) }
    world.exploredMapTextures[5] = { Explored(100, 0) }
end

local function Hover()
    Button():RunScript("OnEnter")
end

-- The value line: its label in gold, the count in white.
local function Count(world, kind, explored, total)
    return world.L["map.exploration.explored." .. kind]:format(
        HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(explored .. "/" .. total)
    )
end

local function SameColor(actual, expected)
    return actual[1] == expected[1] and actual[2] == expected[2] and actual[3] == expected[3]
end

-- Whether the tooltip lists `text` coloured as the achievement window's criteria, after the ready
-- check's marks: done in green after its check, missing in grey after its cross.
local function Listed(world, text, done)
    for index, line in ipairs(world.tooltipLines) do
        if line:find(text, 1, true) then
            local mark = done and "^|A:UI%-LFG%-ReadyMark:14:14|a " or "^|A:UI%-LFG%-DeclineMark:14:14|a "
            local marked = line:find(mark)
            return marked ~= nil and SameColor(world.tooltipColors[index], done and DONE or MISSING)
        end
    end
    return false
end

-- The tooltip's head: the map's name, white; the value line, gold; a blank line.
local function Head(world, name, kind, explored, total)
    equal(world.tooltip, name, "named after the map")
    expect(SameColor(world.tooltipColor, { HIGHLIGHT_FONT_COLOR:GetRGB() }), "its name in white")
    equal(world.tooltipLines[1], Count(world, kind, explored, total), "the count")
    expect(SameColor(world.tooltipColors[1], { NORMAL_FONT_COLOR:GetRGB() }), "its label in gold")
    equal(world.tooltipLines[2], " ", "a blank line before the list")
end

test("shows how much of the zone in view is explored, and its areas", function(world)
    Setup(world)
    world:OpenMap(1)
    world:RunFrames(0.2)
    expect(Button():IsShown(), "the button")
    expect(Icon(world).desaturated, "greyed: not all explored")
    expect(not Check(world):IsShown(), "no check")
    Hover()
    expect(world.tooltipShown, "its tooltip")
    Head(world, "Elwynn Forest", "areas", 2, 3)
    expect(Listed(world, "Goldshire", true), "Goldshire explored")
    expect(Listed(world, "Northshire Valley", true), "Northshire Valley once, explored")
    expect(Listed(world, "Crystal Lake, Mirror Lake", false), "one overlay's areas, missing")
    equal(#world.tooltipLines, 5, "one line per area")
    expect(world.tooltipLines[3]:find("Crystal Lake", 1, true), "sorted by name")
    Button():RunScript("OnLeave")
    expect(not world.tooltipShown, "hidden on leaving")
end)

test("checks the icon once the player explored the whole zone", function(world)
    Setup(world)
    world:OpenMap(1)
    world:RunFrames(0.2)
    Hover()
    table.insert(world.exploredMapTextures[1], Explored(130, 300))
    world:Fire("MAP_EXPLORATION_UPDATED")
    expect(not Icon(world).desaturated, "in colour")
    expect(Check(world):IsShown(), "checked")
    equal(world.tooltipLines[1], Count(world, "areas", 3, 3), "the open tooltip follows")
    expect(Listed(world, "Crystal Lake, Mirror Lake", true), "the area just explored")
end)

test("hides on maps with nothing to explore", function(world)
    Setup(world)
    world:OpenMap(6)
    world:RunFrames(0.2)
    expect(not Button():IsShown(), "not on a city")
    world:ShowMap(3)
    world:RunFrames(0.2)
    expect(not Button():IsShown(), "not on a dungeon")
    world:ShowMap(1)
    world:RunFrames(0.2)
    expect(Button():IsShown(), "back on a zone")
end)

test("counts a continent's zones, and the world's continents", function(world)
    Setup(world)
    world:OpenMap(10)
    world:RunFrames(0.2)
    Hover()
    Head(world, "Eastern Kingdoms", "zones", 1, 2)
    expect(Listed(world, "Elwynn Forest: 2/3", false), "Elwynn Forest's areas, not all explored")
    expect(Listed(world, "Westfall: 1/1", true), "Westfall's, all explored")
    equal(#world.tooltipLines, 4, "no line for Stormwind City")
    world:ShowMap(947)
    world:RunFrames(0.2)
    Head(world, "Azeroth", "continents", 0, 2)
    expect(Listed(world, "Eastern Kingdoms: 1/2", false), "Eastern Kingdoms' zones")
    expect(Listed(world, "Kalimdor: 0/1", false), "Kalimdor's")
end)

test("follows the map the seamless view shows", function(world)
    Setup(world)
    local Seamless = ForeverEnhanced:GetFeature("map", "seamless")
    for _, mapID in ipairs({ 1, 2, 5 }) do
        Seamless.Pieces[C_Map.GetMapArtID(mapID)] = { { 256, 256, 300, 200, mapID * 100 + 50 } }
    end
    world:Setting("map.seamless.enabled"):SetValue(true)
    world:OpenMap(1)
    world:RunFrames(0.2)
    Hover()
    equal(world.tooltip, "Elwynn Forest", "Blizzard's map")
    -- (one notch out of Elwynn Forest whole: Eastern Kingdoms fits in the view)
    world:PointMouseAt(0.75, 0.6)
    world:MapWheel(-1)
    world:RunFrames(1)
    expect(Seamless.View:GetView(), "the seamless view")
    equal(WorldMapFrame:GetMapID(), 1, "Blizzard's map still on Elwynn Forest")
    equal(world.tooltip, "Eastern Kingdoms", "the view's map")
    expect(Button():IsShown(), "the button over the view")
    equal(Button():GetFrameStrata(), "HIGH", "in the strata of Blizzard's map buttons")
end)

test("hides once turned off", function(world)
    Setup(world)
    world:OpenMap(1)
    world:RunFrames(0.2)
    Hover()
    world:Setting("map.exploration.enabled"):SetValue(false)
    expect(not Button():IsShown(), "hidden")
    expect(not world.tooltipShown, "its tooltip too")
    world:ShowMap(5)
    world:RunFrames(0.2)
    expect(not Button():IsShown(), "still hidden on another map")
    world:Setting("map.exploration.enabled"):SetValue(true)
    world:RunFrames(0.2)
    expect(Button():IsShown(), "back once turned on")
end)
