-- Ability Swaps: while a spell can be cast, its button shows it and casts it
-- on the button of the spell it replaces (e.g. Ambush on Backstab after
-- Ghostly Strike). Secure code, the only code allowed to change what a button
-- casts in combat, can't read auras, and a macro stops at its first failed
-- cast. So our secure button lies over Blizzard's and casts twice per press,
-- each its own hardware event: the replacement on key down (the game refuses
-- it when it can't be cast), the original on key up (refused on the global
-- cooldown when the replacement went off).
--
-- Files of this slice:
--   feature.lua   registration, the swaps, schema and lifecycle (this file)
--   locales.lua   strings
--   buttons.lua   Blizzard's action buttons, their slots and the swaps they hold
--   overlays.lua  our secure buttons over them, their keys and their pages
--   display.lua   the replacement's icon and glow while it can be cast
--   quiet.lua     mutes the error of the cast that is meant to fail

local _, ns = ...

-- Each swap: the spell `replacement` shows on and casts from buttons holding
-- `original` (any rank: spells are matched by name), for players of `class`.
local SWAPS = {
    { key = "ambush", class = "ROGUE", original = 53, replacement = 8676 },
    { key = "garrote", class = "ROGUE", original = 1752, replacement = 703 },
}

local settings = {}
for _, swap in ipairs(SWAPS) do
    table.insert(settings, { key = swap.key, type = "toggle", default = true })
end

local Swaps = ns:RegisterFeature("interface", "swaps", {
    order = 4,
    -- It takes over the keys of the buttons it swaps: the player opts in.
    enabledByDefault = false,
    settings = settings,
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true },
    },
})

-- The swaps on while active, by original spell name (see Resolve).
local active = {}

-- { [originalName] = { originalName, replacementName, replacement (spell ID) } }
-- for the player's class and the toggles that are on.
local function Resolve(feature)
    local swaps = {}
    local _, class = UnitClass("player")
    for _, swap in ipairs(SWAPS) do
        if swap.class == class and feature:GetSetting(swap.key) then
            local originalName = C_Spell.GetSpellName(swap.original)
            local replacementName = C_Spell.GetSpellName(swap.replacement)
            if originalName and replacementName then
                swaps[originalName] = {
                    originalName = originalName,
                    replacementName = replacementName,
                    replacement = swap.replacement,
                }
            end
        end
    end
    return swaps
end

-- The swaps that apply now (none while the feature is off).
function Swaps:GetSwaps()
    return active
end

-- Whether the swap's replacement can be cast now (the test the game's own
-- cast passes), and whether it only lacks power.
function Swaps:CanCastReplacement(swap)
    return C_Spell.IsSpellUsable(swap.replacement)
end

function Swaps:OnEnable()
    active = Resolve(self)
    self.Overlays:Enable()
    self.Display:Enable()
end

function Swaps:OnDisable()
    active = {}
    self.Display:Disable()
    self.Overlays:Disable()
end

function Swaps:OnSettingChanged()
    active = Resolve(self)
    self.Overlays:Refresh()
    self.Display:Refresh()
end
