-- Herbs and ore nodes: the skill they require, by name. The world tooltip of a
-- node shows only its name and the profession, colored by difficulty; nodes
-- are server objects, missing from the client's DB2 tables. Names and required
-- skills come from Wowhead Classic (game data, enUS and frFR); quest objects
-- needing a profession are left out.

local _, ns = ...

local SkillUps = ns:GetFeature("professions", "skillups")

local HERBALISM, MINING = 182, 186

-- { skill line, required skill, enUS name, frFR name }
local NODES = {
    { HERBALISM, 1, "Peacebloom", "Pacifique" },
    { HERBALISM, 1, "Silverleaf", "Feuillargent" },
    { HERBALISM, 15, "Earthroot", "Terrestrine" },
    { HERBALISM, 50, "Mageroyal", "Mage royal" },
    { HERBALISM, 70, "Briarthorn", "Eglantine" },
    { HERBALISM, 85, "Stranglekelp", "Etouffante" },
    { HERBALISM, 100, "Bruiseweed", "Doulourante" },
    { HERBALISM, 115, "Wild Steelbloom", "Aciérite sauvage" },
    { HERBALISM, 120, "Grave Moss", "Tombeline" },
    { HERBALISM, 125, "Kingsblood", "Sang-royal" },
    { HERBALISM, 150, "Liferoot", "Vietérule" },
    { HERBALISM, 160, "Fadeleaf", "Pâlerette" },
    { HERBALISM, 170, "Goldthorn", "Dorépine" },
    { HERBALISM, 185, "Khadgar's Whisker", "Moustache de Khadgar" },
    { HERBALISM, 195, "Wintersbite", "Hivernale" },
    { HERBALISM, 205, "Firebloom", "Fleur de feu" },
    { HERBALISM, 210, "Purple Lotus", "Lotus pourpre" },
    { HERBALISM, 220, "Arthas' Tears", "Larmes d'Arthas" },
    { HERBALISM, 230, "Sungrass", "Soleillette" },
    { HERBALISM, 235, "Blindweed", "Aveuglette" },
    { HERBALISM, 245, "Ghost Mushroom", "Champignon fantôme" },
    { HERBALISM, 250, "Gromsblood", "Gromsang" },
    { HERBALISM, 260, "Golden Sansam", "Sansam doré" },
    { HERBALISM, 270, "Dreamfoil", "Feuillerêve" },
    { HERBALISM, 280, "Mountain Silversage", "Sauge-argent des montagnes" },
    { HERBALISM, 285, "Plaguebloom", "Fleur de peste" },
    { HERBALISM, 290, "Icecap", "Calot de glace" },
    { HERBALISM, 300, "Black Lotus", "Lotus noir" },
    { MINING, 1, "Copper Vein", "Filon de cuivre" },
    { MINING, 65, "Incendicite Mineral Vein", "Filon d'incendicite" },
    { MINING, 65, "Tin Vein", "Filon d'étain" },
    { MINING, 75, "Lesser Bloodstone Deposit", "Gisement de pierre de sang inférieure" },
    { MINING, 75, "Ooze Covered Silver Vein", "Filon d'argent couvert de limon" },
    { MINING, 75, "Silver Vein", "Filon d'argent" },
    { MINING, 125, "Iron Deposit", "Gisement de fer" },
    { MINING, 150, "Indurium Mineral Vein", "Filon d'indurium" },
    { MINING, 155, "Gold Vein", "Filon d'or" },
    { MINING, 155, "Ooze Covered Gold Vein", "Filon d'or couvert de limon" },
    { MINING, 175, "Mithril Deposit", "Gisement de mithril" },
    { MINING, 175, "Ooze Covered Mithril Deposit", "Gisement de mithril couvert de vase" },
    { MINING, 230, "Dark Iron Deposit", "Gisement de sombrefer" },
    { MINING, 230, "Ooze Covered Truesilver Deposit", "Gisement de vrai-argent couvert de vase" },
    { MINING, 230, "Truesilver Deposit", "Gisement de vrai-argent" },
    { MINING, 245, "Ooze Covered Thorium Vein", "Filon de thorium couvert de limon" },
    { MINING, 245, "Small Thorium Vein", "Petit filon de thorium" },
    { MINING, 275, "Hakkari Thorium Vein", "Filon de thorium Hakkari" },
    { MINING, 275, "Ooze Covered Rich Thorium Vein", "Riche filon de thorium couvert de limon" },
    { MINING, 275, "Rich Thorium Vein", "Riche filon de thorium" },
    { MINING, 305, "Large Obsidian Chunk", "Grand morceau d'obsidienne" },
    { MINING, 305, "Small Obsidian Chunk", "Petit morceau d'obsidienne" },
}

local NAME_COLUMNS = { enUS = 3, frFR = 4 }

local Nodes = {}
SkillUps.Nodes = Nodes

-- Node name in the client's language -> node; built on first use, empty for
-- other languages.
local byName

-- The node named `name` (game text): { skillLine, required }, or nil.
function Nodes:Get(name)
    if not byName then
        byName = {}
        local column = NAME_COLUMNS[GetLocale()]
        if column then
            for _, node in ipairs(NODES) do
                byName[node[column]] = { skillLine = node[1], required = node[2] }
            end
        end
    end
    return byName[name]
end
