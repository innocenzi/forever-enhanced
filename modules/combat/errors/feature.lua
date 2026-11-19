-- Hide Error Messages: mutes the game's red error messages (not enough mana,
-- out of range, ...) and their voice lines, through ns:MuteGameErrors: all of
-- them, or only those of the spells the character picked, always or only in
-- combat. Our own errors (ns:Error) still show.
--
-- An error doesn't say which spell it's about, so for chosen spells the cast
-- itself mutes them: the client reports a refused cast's error after the call
-- that cast it, later in the same frame (measured by combat.swaps), so a
-- post-hook on the cast mutes errors until the next frame. Errors the server
-- sends back later (line of sight) still show.
--
-- Files of this slice:
--   feature.lua  registration, schema, the character's spells and lifecycle (this file)
--   locales.lua  strings
--   spells.lua   the cast hooks muting the errors of a chosen spell's cast
--   editor.lua   the window where the player picks the spells

local _, ns = ...

local Errors = ns:RegisterFeature("combat", "errors", {
    order = 2,
    -- Errors tell the player why an action failed: the player opts in.
    enabledByDefault = false,
    settings = {
        -- Off: every error. The button beside it opens the editor.
        { key = "spells", type = "toggle", default = false, action = "choose" },
        { key = "combat", type = "toggle", default = false },
    },
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true, spells = false, combat = true },
    },
})

Errors.MAX_SPELLS = 24

local inCombat = false

-- Whether errors are hidden now, by the combat setting.
local function IsHidingNow()
    return not Errors.db.combat or inCombat
end

local function CopyList(list)
    local copy = {}
    for index, value in ipairs(list) do
        copy[index] = value
    end
    return copy
end

-- The character's chosen spells, a copy: { spellID, ... }.
function Errors:GetSpells()
    return CopyList(self:GetCharacterStore().spells or {})
end

-- The chosen spells by name, so every rank counts: { [name] = true }.
local chosenNames = {}

local function ResolveNames(spells)
    local names = {}
    for _, spellID in ipairs(spells) do
        local name = C_Spell.GetSpellName(spellID)
        if name then
            names[name] = true
        end
    end
    return names
end

function Errors:SetSpells(spells)
    self:GetCharacterStore().spells = CopyList(spells)
    chosenNames = ResolveNames(spells)
end

-- Whether the spell (by name) is one of the character's chosen spells.
function Errors:IsChosen(name)
    return name ~= nil and chosenNames[name] == true
end

-- Whether the errors of a chosen spell's cast are muted now.
function Errors:IsHidingSpells()
    return self:IsActive() and self.db.spells and IsHidingNow()
end

local function Sync()
    if not Errors.db.spells and IsHidingNow() then
        ns:MuteGameErrors(Errors)
    else
        ns:UnmuteGameErrors(Errors)
    end
end

local listener = ns:CreateEventListener({
    PLAYER_REGEN_DISABLED = function()
        inCombat = true
        Sync()
    end,
    PLAYER_REGEN_ENABLED = function()
        inCombat = false
        Sync()
    end,
})

function Errors:OnAction(key)
    if key == "choose" then
        self.Editor:Toggle()
    end
end

function Errors:OnEnable()
    inCombat = InCombatLockdown()
    chosenNames = ResolveNames(self:GetSpells())
    self.Spells:Install()
    listener:Start()
    Sync()
end

function Errors:OnDisable()
    listener:Stop()
    self.Editor:Hide()
    ns:UnmuteGameErrors(self)
end

function Errors:OnSettingChanged()
    Sync()
    if not self.db.spells then
        self.Editor:Hide()
    end
end
