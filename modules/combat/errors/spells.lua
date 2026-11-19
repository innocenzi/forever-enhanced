-- Mutes the errors of a chosen spell's cast: action buttons (Blizzard's, and
-- other addons' bars) cast through UseAction, spell buttons through
-- CastSpellByID or CastSpellByName. Each hook runs right after the cast and
-- before the client reports its error, later in the same frame.

local _, ns = ...

local Errors = ns:GetFeature("combat", "errors")

local Spells = {}
Errors.Spells = Spells

local function OnCast(name)
    if Errors:IsChosen(name) then
        ns:MuteGameErrorsThisFrame()
    end
end

-- The spell an action slot casts: a spell, or a macro showing one.
local function GetActionSpellName(slot)
    local actionType, id, subType = GetActionInfo(slot)
    if actionType == "spell" or (actionType == "macro" and subType == "spell") then
        return C_Spell.GetSpellName(id)
    end
end

local installed = false

function Spells:Install()
    if installed then
        return
    end
    installed = true
    ns:HookSecureFunc("UseAction", function(slot)
        if Errors:IsHidingSpells() then
            OnCast(GetActionSpellName(slot))
        end
    end)
    ns:HookSecureFunc("CastSpellByID", function(spellID)
        if Errors:IsHidingSpells() then
            OnCast(C_Spell.GetSpellName(spellID))
        end
    end)
    ns:HookSecureFunc("CastSpellByName", function(name)
        if Errors:IsHidingSpells() and type(name) == "string" then
            -- "Frostbolt(Rank 1)" casts Frostbolt.
            OnCast((name:gsub("%s*%(.-%)$", "")))
        end
    end)
end
