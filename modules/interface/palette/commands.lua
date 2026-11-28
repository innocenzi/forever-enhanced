-- Blizzard's commands: the key bindings of Forever's Bindings_Camelot.xml (and
-- the group finder's, Blizzard_GroupFinder_VanillaStyle) that open a window
-- or toggle part of the interface, and the player's professions, each opening
-- its crafting window, most useful first. Titles are the game's (bindings'
-- names in the Key Bindings, professions' names on the profession window's
-- tabs); English names and keywords are in locales.lua.

local _, ns = ...

local Palette = ns:GetFeature("interface", "palette")

-- Rogues' Poisons, which GetProfessions() leaves out: its spell opens its window.
local POISONS_SPELL = 2842

local function HasPet()
    return C_SpellBook.HasPetSpells() ~= nil
end

-- The spell opening the window of the player's profession of `skillLine`,
-- and the profession's name, like the profession window's tabs
-- (ProfessionsMixin:RefreshRightTab): its first spellbook item (in Forever, a
-- camp spell named otherwise, cast by ID: Fishing's isn't the cast that
-- fishes). Nothing when not learned, or without a window.
local function ProfessionSpell(skillLine)
    return function()
        for _, index in pairs({ GetProfessions() }) do
            local name, _, _, _, _, spellOffset, line = GetProfessionInfo(index)
            if line == skillLine then
                local item = C_SpellBook.GetSpellBookItemInfo(spellOffset + 1, Enum.SpellBookSpellBank.Player)
                local spellID = item and item.spellID
                if spellID and C_TradeSkillUI.CanTradeSkillShowCraftingUI(spellID) then
                    return spellID, name
                end
            end
        end
    end
end

local function PoisonsSpell()
    return IsPlayerSpell(POISONS_SPELL) and POISONS_SPELL or nil
end

local COMMANDS = {
    -- Windows.
    { id = "character", binding = "TOGGLECHARACTER0" },
    { id = "spellbook", binding = "TOGGLESPELLBOOK" },
    { id = "talents", binding = "TOGGLETALENTS" },
    { id = "quests", binding = "TOGGLEQUESTLOG" },
    { id = "map", binding = "TOGGLEWORLDMAP" },
    { id = "bags", binding = "OPENALLBAGS" },
    { id = "professions", binding = "TOGGLEPROFESSIONBOOK" },
    -- The player's professions, by skill line.
    { id = "cooking", spell = ProfessionSpell(185) },
    { id = "firstAid", spell = ProfessionSpell(129) },
    { id = "alchemy", spell = ProfessionSpell(171) },
    { id = "blacksmithing", spell = ProfessionSpell(164) },
    { id = "enchanting", spell = ProfessionSpell(333) },
    { id = "engineering", spell = ProfessionSpell(202) },
    { id = "leatherworking", spell = ProfessionSpell(165) },
    { id = "tailoring", spell = ProfessionSpell(197) },
    { id = "mining", spell = ProfessionSpell(186) },
    { id = "herbalism", spell = ProfessionSpell(182) },
    { id = "skinning", spell = ProfessionSpell(393) },
    { id = "fishing", spell = ProfessionSpell(356) },
    { id = "poisons", spell = PoisonsSpell },
    { id = "reputation", binding = "TOGGLECHARACTER2" },
    { id = "currency", binding = "TOGGLECURRENCY" },
    { id = "social", binding = "TOGGLESOCIAL" },
    { id = "friends", binding = "TOGGLEFRIENDSTAB" },
    { id = "who", binding = "TOGGLEWHOTAB" },
    { id = "guild", binding = "TOGGLEGUILDTAB", IsAvailable = IsInGuild },
    { id = "raid", binding = "TOGGLERAIDTAB" },
    { id = "groupfinder", binding = "TOGGLEGROUPFINDER" },
    { id = "collections", binding = "TOGGLECOLLECTIONS" },
    { id = "mounts", binding = "TOGGLECOLLECTIONSMOUNTJOURNAL" },
    { id = "pets", binding = "TOGGLECOLLECTIONSPETJOURNAL" },
    { id = "toys", binding = "TOGGLECOLLECTIONSTOYBOX" },
    { id = "appearances", binding = "TOGGLECOLLECTIONSWARDROBE" },
    { id = "petbook", binding = "TOGGLEPETBOOK", IsAvailable = HasPet },
    { id = "pvp", binding = "TOGGLECHARACTER4" },
    { id = "legacy", binding = "TOGGLELEGACYSYSTEM" },
    { id = "cooldowns", binding = "TOGGLECOOLDOWNVIEWERSETTINGS" },
    { id = "menu", binding = "TOGGLEGAMEMENU" },
    -- The interface.
    { id = "ui", binding = "TOGGLEUI" },
    { id = "minimap", binding = "TOGGLEMINIMAP" },
    { id = "zonemap", binding = "TOGGLEBATTLEFIELDMINIMAP" },
    { id = "scores", binding = "TOGGLEWORLDSTATESCORES" },
    { id = "actionbars", binding = "TOGGLEACTIONBARLOCK" },
    { id = "highlight", binding = "TOGGLESELFHIGHLIGHT" },
    { id = "fps", binding = "TOGGLEFPS" },
    { id = "sound", binding = "TOGGLESOUND" },
    { id = "music", binding = "TOGGLEMUSIC" },
    { id = "graphics", binding = "TOGGLEGRAPHICSSETTINGS" },
    { id = "windowed", binding = "TOGGLEWINDOWED" },
    { id = "screenshot", binding = "SCREENSHOT" },
}

for index, command in ipairs(COMMANDS) do
    command.order = index * 10
    ns:AddCommand(Palette, command)
end
