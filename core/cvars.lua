-- Console variables a feature changes while it is active.
--
-- CVars are the player's own settings, saved by the game (and synced to the
-- account), not by the addon. An override keeps the player's value of every
-- CVar it sets, and the value it set, in the feature's account store (CVars
-- are account-wide), so Restore() can put it back, even sessions later. A CVar
-- the player changed in the meantime keeps the player's value. What a feature
-- that isn't active at login left set (turned off in combat, then reloaded) is
-- put back then.
--
-- Writes happen only when the value changes: every write fires CVAR_UPDATE,
-- whose handlers (Blizzard's included) run at once, from our tainted code.
-- None happen in combat; they wait for its end.

local _, ns = ...

local CVarOverrideMixin = {}

-- Placeholder in `pending`: put the player's value back.
local RESTORE = {}

local overrides = {}

local function Write(name, value)
    if C_CVar.GetCVar(name) ~= value then
        C_CVar.SetCVar(name, value)
    end
end

-- The player's values and ours, by CVar name (saved variables exist once the
-- addon is loaded). Values saved before ours were kept have none of ours.
function CVarOverrideMixin:GetSavedValues()
    local store = self.feature:GetAccountStore()
    store.cvars = store.cvars or {}
    store.ourCVars = store.ourCVars or {}
    return store.cvars, store.ourCVars
end

-- Sets `name` to `value` (a string) until Restore.
function CVarOverrideMixin:Set(name, value)
    local saved, ours = self:GetSavedValues()
    if saved[name] == nil then
        saved[name] = C_CVar.GetCVar(name)
    end
    ours[name] = value
    self.pending[name] = value
    self:Flush()
end

-- Puts back the player's values, except where the player changed one since we set it.
function CVarOverrideMixin:Restore()
    for name in pairs((self:GetSavedValues())) do
        self.pending[name] = RESTORE
    end
    self:Flush()
end

-- The player's value of a CVar we set, or nil.
function CVarOverrideMixin:GetSaved(name)
    return (self:GetSavedValues())[name]
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
    local saved, ours = self:GetSavedValues()
    for name, value in pairs(pending) do
        if value == RESTORE then
            if ours[name] == nil or C_CVar.GetCVar(name) == ours[name] then
                Write(name, saved[name])
            end
            saved[name] = nil
            ours[name] = nil
        else
            Write(name, value)
        end
    end
end

function ns:CreateCVarOverride(feature)
    local override = Mixin({ feature = feature, pending = {} }, CVarOverrideMixin)
    override.combatListener = ns:CreateEventListener({
        PLAYER_REGEN_ENABLED = function()
            override:Flush()
        end,
    })
    table.insert(overrides, override)
    return override
end

-- At login, once features are active: puts back what inactive features left set.
function ns:RestoreLeftoverCVars()
    for _, override in ipairs(overrides) do
        if not override.feature:IsActive() and next((override:GetSavedValues())) then
            override:Restore()
        end
    end
end
