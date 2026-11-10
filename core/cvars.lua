-- Console variables a feature changes while it is active.
--
-- CVars are the player's own settings, saved by the game (and synced to the
-- account), not by the addon. An override keeps the player's value of every
-- CVar it sets in the feature's account store (CVars are account-wide), so
-- Restore() can put it back, even sessions later. A CVar the player changed
-- in the meantime keeps the player's value.
--
-- Writes happen only when the value changes: every write fires CVAR_UPDATE,
-- whose handlers (Blizzard's included) run at once, from our tainted code.
-- None happen in combat; they wait for its end.

local _, ns = ...

local CVarOverrideMixin = {}

-- Placeholder in `pending`: put the player's value back.
local RESTORE = {}

local function Write(name, value)
    if C_CVar.GetCVar(name) ~= value then
        C_CVar.SetCVar(name, value)
    end
end

-- The player's values, by CVar name (saved variables exist once the addon is loaded).
function CVarOverrideMixin:GetSavedValues()
    local store = self.feature:GetAccountStore()
    store.cvars = store.cvars or {}
    return store.cvars
end

-- Sets `name` to `value` (a string) until Restore.
function CVarOverrideMixin:Set(name, value)
    local saved = self:GetSavedValues()
    if saved[name] == nil then
        saved[name] = C_CVar.GetCVar(name)
    end
    self.ours[name] = value
    self.pending[name] = value
    self:Flush()
end

-- Puts back the player's values, except where the player changed one since we set it.
function CVarOverrideMixin:Restore()
    for name in pairs(self:GetSavedValues()) do
        self.pending[name] = RESTORE
    end
    self:Flush()
end

-- The player's value of a CVar we set, or nil.
function CVarOverrideMixin:GetSaved(name)
    return self:GetSavedValues()[name]
end

function CVarOverrideMixin:Flush()
    if InCombatLockdown() then
        self.combatListener:Start()
        return
    end
    self.combatListener:Stop()

    -- Writes run CVAR_UPDATE handlers, which may set more: take the list first.
    local pending = self.pending
    self.pending = {}
    local saved = self:GetSavedValues()
    for name, value in pairs(pending) do
        if value == RESTORE then
            if C_CVar.GetCVar(name) == self.ours[name] then
                Write(name, saved[name])
            end
            saved[name] = nil
            self.ours[name] = nil
        else
            Write(name, value)
        end
    end
end

function ns:CreateCVarOverride(feature)
    local override = Mixin({ feature = feature, ours = {}, pending = {} }, CVarOverrideMixin)
    override.combatListener = ns:CreateEventListener({
        PLAYER_REGEN_ENABLED = function()
            override:Flush()
        end,
    })
    return override
end
