-- While fishing. Fishing channeling with the key bound starts it: soft
-- targeting picks objects for the keyboard too, as far as it reaches, so the
-- bobber can be the soft interact target, and while the channel lasts the key
-- reels in (see feature.lua). It ends `delay` seconds after the last cast, or
-- after the pole went on without one, and as combat starts: the weapons go
-- back on and the CVars back to the player's. Combat ends it just before the
-- lockdown starts (PLAYER_REGEN_DISABLED), the last moment to give the key back.

local _, ns = ...

local Fishing = ns:GetFeature("professions", "fishing")

local Session = {}
Fishing.Session = Session

-- The game object every rank of Fishing summons (SpellEffect).
local BOBBER = 35591

local CVARS = {
    -- Soft interact targeting with mouse and keyboard too (Enum.SoftTargetEnableFlags.Any).
    SoftTargetInteract = "3",
    -- As far as it goes: the game drops soft targets past about 15 yards.
    SoftTargetInteractRange = "15",
}

local cvars = ns:CreateCVarOverride(Fishing)
-- Owns the override bindings of the key while Fishing channels.
local owner = CreateFrame("Frame")

local fishing = false
local channeling = false
-- The keys bound to the fishing key as the channel started (overrides taking them).
local keys = {}
local timer

-- Whether `guid` is a fishing bobber (secret in instances: then it isn't known).
local function IsBobber(guid)
    if not guid or ns:IsAnySecret(guid) then
        return false
    end
    local kind, _, _, _, _, entry = strsplit("-", guid)
    return kind == "GameObject" and tonumber(entry) == BOBBER
end

-- The key reels in while Fishing channels, and is the player's again otherwise.
local function Bind()
    if InCombatLockdown() then
        return
    end
    ClearOverrideBindings(owner)
    if not channeling then
        return
    end
    local action = IsBobber(UnitGUID("softinteract")) and "INTERACTTARGET" or "INTERACTMOUSEOVER"
    for _, key in ipairs(keys) do
        SetOverrideBinding(owner, true, key, action)
    end
end

local function StopTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

local function End()
    StopTimer()
    fishing = false
    channeling = false
    Bind()
    cvars:Restore()
    if Fishing:IsPartActive("swap") then
        Fishing.Gear:Restore()
    end
end

-- Starts the countdown to the end of the fishing again.
function Session:Touch()
    StopTimer()
    fishing = true
    timer = C_Timer.NewTimer(Fishing.db.delay, End)
end

local function IsPlayerFishing(unit, spellID)
    return unit == "player" and Fishing:IsFishingSpell(spellID)
end

local listener = ns:CreateEventListener({
    UNIT_SPELLCAST_CHANNEL_START = function(_, unit, _, spellID)
        if not IsPlayerFishing(unit, spellID) or InCombatLockdown() then
            return
        end
        StopTimer()
        fishing = true
        channeling = true
        keys = Fishing:GetKeys()
        if #keys > 0 then
            for name, value in pairs(CVARS) do
                cvars:Set(name, value)
            end
        end
        Bind()
    end,
    UNIT_SPELLCAST_CHANNEL_STOP = function(_, unit, _, spellID)
        if not IsPlayerFishing(unit, spellID) or not channeling then
            return
        end
        channeling = false
        Bind()
        Session:Touch()
    end,
    -- The bobber came within reach of the soft target, or left it.
    PLAYER_SOFT_INTERACT_CHANGED = function()
        if channeling then
            Bind()
        end
    end,
    PLAYER_REGEN_DISABLED = function()
        if fishing then
            End()
        end
    end,
})

function Session:Enable()
    listener:Start()
    -- The pole stayed in hand since the last session (a reload).
    if Fishing.Gear:HasSavedWeapons() then
        self:Touch()
    end
end

function Session:Disable()
    listener:Stop()
    End()
end
