-- Fishing: a key the player binds (its setting, or Key Bindings under the
-- addon's header) casts Fishing, and pressing it again while the line is out reels in.
-- With "swap", its first press equips the best fishing pole in the bags
-- instead, and the weapons it took off go back on when combat starts or
-- `delay` seconds after the last cast.
--
-- Casting needs secure code: the key clicks our secure button (a click
-- binding in Bindings.xml), which casts Fishing. Reeling in is the game's own
-- interaction: while Fishing channels, an override binding turns the key into
-- Interact With Target when the soft interact target is our bobber, and into
-- Interact With Mouseover otherwise (the bobber landed out of the soft
-- target's reach, about 15 yards: the player points at it). Bindings and
-- attributes can't change in combat: combat ends the fishing (weapons back
-- on, the key casting again).
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   gear.lua     the fishing pole and the weapons it replaces ("swap")
--   button.lua   the secure button the key clicks, and the key's name
--   session.lua  while fishing: the key reeling in, soft targeting, the end of it

local _, ns = ...

-- The key binding the player sets (here, or in Key Bindings), clicking our button (Bindings.xml).
local BUTTON_NAME = "ForeverEnhancedFishingButton"
local BINDING = "CLICK " .. BUTTON_NAME .. ":LeftButton"

local Fishing = ns:RegisterFeature("professions", "fishing", {
    order = 4,
    settings = {
        { key = "key", type = "binding", binding = BINDING },
        { key = "swap", type = "toggle", default = true },
        { key = "delay", type = "slider", default = 30, min = 15, max = 300, step = 15, requires = { swap = true } },
    },
    presets = {
        minimal = { enabled = true, swap = true, delay = 30 },
        enhanced = { enabled = true, swap = true, delay = 30 },
    },
})

-- Fishing's first rank: every rank shares its name, and a name casts the highest known.
local FISHING = 7620

Fishing.BUTTON_NAME = BUTTON_NAME
Fishing.BINDING = BINDING

-- Fishing's name, in the client's language.
function Fishing:GetSpellName()
    return C_Spell.GetSpellName(FISHING)
end

-- Whether `spellID` (from a cast event) is a rank of Fishing.
function Fishing:IsFishingSpell(spellID)
    return not ns:IsAnySecret(spellID) and C_Spell.GetSpellName(spellID) == self:GetSpellName()
end

-- The keys bound to the fishing key.
function Fishing:GetKeys()
    return { GetBindingKey(self.BINDING) }
end

function Fishing:OnEnable()
    self.Button:Enable()
    self:SyncPart("swap", self.Gear)
    self.Session:Enable()
end

function Fishing:OnDisable()
    self.Session:Disable()
    self:SyncPart("swap", self.Gear)
    self.Button:Disable()
end

function Fishing:OnSettingChanged()
    self:SyncPart("swap", self.Gear)
end
