-- Zone level ranges: on Blizzard's area label, pointing at zones on a continent, leaving the
-- client's ranges and other labels alone, and turning it off.
-- The fake world (tests/wow.lua): Eastern Kingdoms (10) with Elwynn Forest (1, rect
-- 0.70-0.80 x 0.55-0.65 on Azeroth's map) and Westfall (5, 0.60-0.70 x 0.55-0.65).

local function Levels()
    return ForeverEnhanced:GetFeature("map", "levels")
end

-- Blizzard's area label.
local function BlizzardLabel()
    for provider in pairs(WorldMapFrame.dataProviders) do
        if provider.Label then
            return provider.Label
        end
    end
end

-- Our font string on the label.
local function Ours(world)
    for _, fontString in ipairs(world.fontStrings) do
        if fontString.owner.parent == BlizzardLabel() then
            return fontString
        end
    end
end

-- What the label shows: ours while it's up, else Blizzard's name.
local function Shown(world)
    local ours = Ours(world)
    if ours and ours:IsShown() then
        equal(BlizzardLabel().Name:GetAlpha(), 0, "Blizzard's name hidden under ours")
        return ours:GetText()
    end
    equal(BlizzardLabel().Name:GetAlpha(), 1, "Blizzard's name shown")
    return BlizzardLabel().Name:GetText()
end

local function Ranged(name, range, color)
    return name .. RGBTableToColorCode(color) .. " (" .. range .. ")" .. FONT_COLOR_CODE_CLOSE
end

local function PointAtWestfall(world)
    world:OpenMap(10)
    world:PointMouseAt(0.65, 0.6)
    world:NextFrame()
end

test("names the zone under the cursor with its level range, coloured against the player's level", function(world)
    Levels().RANGES[5] = { 10, 20 }
    world.player.level = 15
    PointAtWestfall(world)
    equal(Shown(world), Ranged("Westfall", "10-20", QuestDifficultyColors.difficult), "within the range")
    world:LevelUp(30)
    world:NextFrame()
    equal(Shown(world), Ranged("Westfall", "10-20", GetQuestDifficultyColor(18)), "past it")
    world:PointMouseAt(0.75, 0.6)
    world:NextFrame()
    equal(Shown(world), "Elwynn Forest", "a zone without a range: Blizzard's own")
    world:PointMouseAt(0.65, 0.2)
    world:NextFrame()
    equal(Shown(world), "", "off every zone: nothing")
end)

test("shows a single level alone", function(world)
    Levels().RANGES[5] = { 60, 60 }
    world.player.level = 60
    PointAtWestfall(world)
    equal(Shown(world), Ranged("Westfall", "60", QuestDifficultyColors.difficult))
end)

test("leaves the client's ranges and other labels to Blizzard", function(world)
    Levels().RANGES[5] = { 10, 20 }
    world.mapLevels[5] = { 12, 22 }
    PointAtWestfall(world)
    equal(Shown(world), "Westfall (12-22)", "the client's range, Blizzard's label")
    world.mapLevels[5] = nil
    world.mapPoiLabel = "Sentinel Hill"
    world:NextFrame()
    equal(Shown(world), "Sentinel Hill", "a map pin's label")
end)

test("shows Blizzard's label alone when turned off, and the range again when back on", function(world)
    Levels().RANGES[5] = { 10, 20 }
    world.player.level = 15
    PointAtWestfall(world)
    world:Setting("map.levels.enabled"):SetValue(false)
    equal(Shown(world), "Westfall", "off: Blizzard's name back at once")
    world:NextFrame()
    equal(Shown(world), "Westfall", "and stays")
    equal(Levels():GetRange(5), nil, "no range for other features")
    world:Setting("map.levels.enabled"):SetValue(true)
    world:NextFrame()
    equal(Shown(world), Ranged("Westfall", "10-20", QuestDifficultyColors.difficult), "on again")
end)

test("gives every zone a range within levels 1 to 60", function()
    for mapID, range in pairs(Levels().RANGES) do
        expect(range[1] >= 1 and range[1] <= range[2] and range[2] <= 60, "zone " .. mapID)
    end
end)
