-- Spell Swaps: while a spell can be cast, the buttons of the spell it
-- replaces show it and cast it (e.g. Ambush on Backstab after Ghostly
-- Strike). Each character picks its own pairs in an editor opened from the
-- settings panel. Secure code, the only code allowed to change what a button
-- casts in combat, can't read auras, and a macro stops at its first failed
-- cast. So our secure button lies over Blizzard's and casts twice per press,
-- each its own hardware event: the replacement on key down (the game refuses
-- it when it can't be cast), the original on key up (refused on the global
-- cooldown when the replacement went off). So the original goes out later
-- than from Blizzard's buttons, which cast on key down, by as long as the key
-- is held (about 0.1 s, measured); the key down can't try it too, since a
-- refused cast uses up its key event.
--
-- Files of this slice:
--   feature.lua   registration, the character's swaps and lifecycle (this file)
--   locales.lua   strings
--   buttons.lua   Blizzard's action buttons: pages, slots, and standing in for them
--   overlays.lua  our secure buttons over them, their keys and their pages
--   display.lua   the replacement's icon and glow while it can be cast
--   quiet.lua     mutes the error of the cast that is meant to fail
--   editor.lua    the window where the player edits their swaps

local _, ns = ...

-- What a character starts with until they edit their swaps, by class.
local DEFAULTS = {
    ROGUE = {
        { original = 53, replacement = 8676 }, -- Backstab: Ambush (after Ghostly Strike)
        { original = 1752, replacement = 703 }, -- Sinister Strike: Garrote
    },
}

local Swaps = ns:RegisterFeature("combat", "swaps", {
    order = 3,
    -- It takes over the keys of the buttons it swaps: the player opts in.
    enabledByDefault = false,
    action = "edit",
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true },
    },
})

Swaps.MAX_SWAPS = 10

local function CopyList(list)
    local copy = {}
    for _, swap in ipairs(list) do
        table.insert(copy, { original = swap.original, replacement = swap.replacement })
    end
    return copy
end

-- The character's swaps, a copy: { { original = spellID, replacement = spellID } }.
-- Until the player edits them, their class's defaults (never saved, so later
-- defaults reach them).
function Swaps:GetList()
    local _, class = UnitClass("player")
    return CopyList(self:GetCharacterStore().swaps or DEFAULTS[class] or {})
end

-- The swaps on while active, by original spell name (see Resolve).
local active = {}

-- { [originalName] = { originalName, replacementName, replacement (spell ID) } }.
-- Spells match by name, so every rank counts.
local function Resolve(list)
    local swaps = {}
    for _, swap in ipairs(list) do
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
    return swaps
end

-- Saves the character's swaps and puts them on the bars.
function Swaps:SetList(list)
    self:GetCharacterStore().swaps = CopyList(list)
    if self:IsActive() then
        active = Resolve(list)
        self.Overlays:Refresh()
        self.Display:Refresh()
    end
end

-- Why `spellID` can't go on `side` ("original" or "replacement") of swap
-- `index` in `list`: a locale key, or nil when it can.
function Swaps:CheckSpell(list, index, side, spellID)
    local name = C_Spell.GetSpellName(spellID)
    if not name then
        return "combat.swaps.editor.notSpell"
    end
    local swap = list[index] or {}
    local other = side == "original" and swap.replacement or swap.original
    if other and C_Spell.GetSpellName(other) == name then
        return "combat.swaps.editor.sameSpell"
    end
    if side == "original" then
        for otherIndex, otherSwap in ipairs(list) do
            if otherIndex ~= index and C_Spell.GetSpellName(otherSwap.original) == name then
                return "combat.swaps.editor.alreadySwapped"
            end
        end
    end
end

-- The swaps that apply now (none while the feature is off).
function Swaps:GetSwaps()
    return active
end

-- A cooldown of its own, not the global cooldown. Both fields stay readable
-- when the client hides cooldowns from addons in combat.
local function OnCooldown(spellID)
    local cooldown = C_Spell.GetSpellCooldown(spellID)
    return cooldown ~= nil and cooldown.isActive and not cooldown.isOnGCD
end

-- Whether the swap's replacement can be cast now (the test the game's own
-- cast passes), and whether it only lacks power.
function Swaps:CanCastReplacement(swap)
    if OnCooldown(swap.replacement) then
        return false, false
    end
    return C_Spell.IsSpellUsable(swap.replacement)
end

function Swaps:OnAction(key)
    if key == "edit" then
        self.Editor:Toggle()
    end
end

function Swaps:OnEnable()
    active = Resolve(self:GetList())
    self.Overlays:Enable()
    self.Display:Enable()
end

function Swaps:OnDisable()
    active = {}
    self.Editor:Hide()
    self.Display:Disable()
    self.Overlays:Disable()
end
