-- The player's damage over time effects on each unit, from their own casts.
--
-- A cast of a followed spell lands on the target (as it was sent, for a spell
-- with a cast time). The client logs a miss on the unit (dodge, parry,
-- immune...) in the same frame as the cast, after it: a cast is applied on the
-- next frame, unless such a miss came in between.
-- The miss doesn't say whose it was (a party member's swing, the player's own
-- white swing), so a cast missed that way waits for its combo points instead,
-- when it spends some (finishing moves) or awards some: one that lands changes
-- them, one that misses doesn't. Other spells have nothing to wait for: they
-- count as missed. A finishing move's points are read as it is sent (they are
-- spent once it lands). Casting the spell again on the unit replaces its
-- effect, like the game does.
--
-- Effects are kept by unit: by its GUID, or by its nameplate while its GUID
-- is secret (Tracker:GetUnitKey).
--
-- Out of combat the player's auras are readable again: effects whose aura is
-- gone are forgotten (the unit died, reset or was cleansed), the others take
-- the aura's timing.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local Tracker = {}
DoTs.Tracker = Tracker

-- UNIT_COMBAT actions of a cast that didn't land.
local MISSES = {
    MISS = true,
    DODGE = true,
    PARRY = true,
    DEFLECT = true,
    EVADE = true,
    IMMUNE = true,
    RESIST = true,
    REFLECT = true,
}

-- How long a cast that may have missed waits for its combo points.
local CONFIRM_SECONDS = 1

local EMPTY = {}

-- Unit key (Tracker:GetUnitKey) -> spell key -> { key, start, duration, perTick, tick }.
local effects = {}
-- Unit key -> amplifier key -> { from, to, bonus, amplifies }.
local amplifiers = {}
-- The last cast sent: { castGUID, unitKey, points } (its target, and the combo
-- points on it then).
local lastSent
-- Casts that landed this frame: { unitKey, spellID, definition, amplifier, points, time, missed }.
local pending = {}
-- Casts that may have missed, waiting for their combo points: { cast, timer }.
local unconfirmed = {}

-- The key the player's effects on a unit are kept under: its GUID or, while
-- its identity is secret (restricted units, like in instances), the token of
-- its nameplate, valid until the plate is removed; nil without either.
function Tracker:GetUnitKey(unit)
    local guid = UnitGUID(unit)
    if not guid then
        return nil
    elseif not issecretvalue(guid) then
        return guid
    end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    return plate and plate:GetUnit()
end

local function TickCount(effect)
    return math.floor(effect.duration / effect.tick + 0.5)
end

-- How many of the effect's ticks have landed by `now`.
local function LandedTicks(effect, now)
    return math.floor((now - effect.start) / effect.tick)
end

-- How much the effect's tick landing at `time` deals on the unit.
local function TickDamage(unitKey, effect, time)
    local multiplier = 1
    for _, amplifier in pairs(amplifiers[unitKey] or EMPTY) do
        if amplifier.amplifies[effect.key] and time > amplifier.from and time <= amplifier.to then
            multiplier = multiplier + amplifier.bonus
        end
    end
    return effect.perTick * multiplier
end

local function Apply(cast)
    if cast.amplifier then
        local amplifier = cast.amplifier
        amplifiers[cast.unitKey] = amplifiers[cast.unitKey] or {}
        amplifiers[cast.unitKey][amplifier.key] = {
            from = cast.time,
            to = cast.time + amplifier.duration,
            bonus = amplifier.bonus,
            amplifies = amplifier.amplifies,
        }
        return
    end
    local definition = cast.definition
    local perTick, duration = DoTs.Spells:Read(definition, cast.spellID, cast.points)
    if not perTick or duration < definition.tick then
        return
    end
    effects[cast.unitKey] = effects[cast.unitKey] or {}
    effects[cast.unitKey][definition.key] = {
        key = definition.key,
        start = cast.time,
        duration = duration,
        perTick = perTick,
        tick = definition.tick,
    }
end

local function Unconfirm(cast)
    local entry = { cast = cast }
    -- Its points never changed: it missed.
    entry.timer = C_Timer.NewTimer(CONFIRM_SECONDS, function()
        for index, other in ipairs(unconfirmed) do
            if other == entry then
                table.remove(unconfirmed, index)
                return
            end
        end
    end)
    table.insert(unconfirmed, entry)
end

local function Commit()
    local casts = pending
    pending = {}
    for _, cast in ipairs(casts) do
        if not cast.missed then
            Apply(cast)
        elseif (cast.definition or cast.amplifier).comboPoints then
            Unconfirm(cast)
        end
    end
    DoTs.Overlays:Refresh()
end

-- The target's combo points changed: its casts that may have missed landed.
local function Confirm()
    local unitKey = Tracker:GetUnitKey("target")
    if not unitKey then
        return
    end
    local points = GetComboPoints("player", "target")
    local confirmed = false
    for index = #unconfirmed, 1, -1 do
        local entry = unconfirmed[index]
        if entry.cast.unitKey == unitKey and entry.cast.points ~= points then
            entry.timer:Cancel()
            table.remove(unconfirmed, index)
            Apply(entry.cast)
            confirmed = true
        end
    end
    if confirmed then
        DoTs.Overlays:Refresh()
    end
end

local function OnCast(castGUID, spellID)
    local definition = DoTs.Spells:Get(spellID)
    local amplifier = DoTs.Spells:GetAmplifier(spellID)
    if not (definition or amplifier) then
        return
    end
    -- A spell with a cast time lands on the unit targeted as it was sent.
    local sent = lastSent and lastSent.castGUID == castGUID and lastSent
    local unitKey
    if sent then
        unitKey = sent.unitKey
    else
        unitKey = Tracker:GetUnitKey("target")
    end
    if not unitKey then
        return
    end
    local points = sent and sent.points
    if #pending == 0 then
        C_Timer.After(0, Commit)
    end
    table.insert(pending, {
        unitKey = unitKey,
        spellID = spellID,
        definition = definition,
        amplifier = amplifier,
        points = points or GetComboPoints("player", "target"),
        time = GetTime(),
    })
end

-- A miss on the unit, from anyone: its casts this frame may not have landed.
local function OnMiss(unit)
    local unitKey = Tracker:GetUnitKey(unit)
    if not unitKey then
        return
    end
    for _, cast in ipairs(pending) do
        if cast.unitKey == unitKey then
            cast.missed = true
        end
    end
end

-- Out of combat: drops the effects on the unit whose aura is gone, and gives
-- the others the aura's timing.
local function Reconcile(unit)
    if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() then
        return
    end
    local unitKey = Tracker:GetUnitKey(unit)
    local unitEffects = unitKey and effects[unitKey]
    if not unitEffects then
        return
    end
    for key, effect in pairs(unitEffects) do
        local aura = C_UnitAuras.GetAuraDataBySpellName(unit, DoTs.Spells:GetName(key), "HARMFUL|PLAYER")
        if aura then
            effect.duration = aura.duration
            effect.start = aura.expirationTime - aura.duration
        else
            unitEffects[key] = nil
        end
    end
    DoTs.Overlays:Refresh()
end

local function ReconcileAll()
    Reconcile("target")
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = plate:GetUnit()
        if unit then
            Reconcile(unit)
        end
    end
end

local listener = ns:CreateEventListener({
    UNIT_SPELLCAST_SENT = function(_, unit, _, castGUID, spellID)
        if unit == "player" and (DoTs.Spells:Get(spellID) or DoTs.Spells:GetAmplifier(spellID)) then
            lastSent = {
                castGUID = castGUID,
                unitKey = Tracker:GetUnitKey("target"),
                points = GetComboPoints("player", "target"),
            }
        end
    end,
    UNIT_SPELLCAST_SUCCEEDED = function(_, unit, castGUID, spellID)
        if unit == "player" then
            OnCast(castGUID, spellID)
        end
    end,
    UNIT_COMBAT = function(_, unit, action)
        if MISSES[action] and #pending > 0 and (unit == "target" or unit:match("^nameplate")) then
            OnMiss(unit)
        end
    end,
    UNIT_POWER_FREQUENT = function(_, unit, powerType)
        if unit == "player" and powerType == "COMBO_POINTS" and #unconfirmed > 0 then
            Confirm()
        end
    end,
    UNIT_AURA = function(_, unit)
        if unit == "target" or unit:match("^nameplate") then
            Reconcile(unit)
        end
    end,
    PLAYER_REGEN_ENABLED = ReconcileAll,
    -- Effects kept under the plate's token: its next unit is another.
    NAME_PLATE_UNIT_REMOVED = function(_, unit)
        Tracker:Forget(unit)
    end,
})

-- The damage the player's effects on the unit have yet to deal.
function Tracker:GetRemainingDamage(unitKey)
    local now = GetTime()
    local remaining = 0
    for _, effect in pairs(effects[unitKey] or EMPTY) do
        for index = LandedTicks(effect, now) + 1, TickCount(effect) do
            remaining = remaining + TickDamage(unitKey, effect, effect.start + index * effect.tick)
        end
    end
    return remaining
end

-- Forgets the player's effects on the unit (it died).
function Tracker:Forget(unitKey)
    effects[unitKey] = nil
    amplifiers[unitKey] = nil
end

-- Forgets the effects whose last tick landed and the amplifiers that ended,
-- on every unit (most are never shown again).
function Tracker:ForgetEnded()
    local now = GetTime()
    for unitKey, unitEffects in pairs(effects) do
        for key, effect in pairs(unitEffects) do
            if LandedTicks(effect, now) >= TickCount(effect) then
                unitEffects[key] = nil
            end
        end
        if next(unitEffects) == nil then
            effects[unitKey] = nil
        end
    end
    for unitKey, unitAmplifiers in pairs(amplifiers) do
        for key, amplifier in pairs(unitAmplifiers) do
            if now > amplifier.to then
                unitAmplifiers[key] = nil
            end
        end
        if next(unitAmplifiers) == nil then
            amplifiers[unitKey] = nil
        end
    end
end

-- Whether any unit has effects running.
function Tracker:IsTracking()
    return next(effects) ~= nil
end

function Tracker:Enable()
    listener:Start()
end

function Tracker:Disable()
    listener:Stop()
    for _, entry in ipairs(unconfirmed) do
        entry.timer:Cancel()
    end
    effects = {}
    amplifiers = {}
    lastSent = nil
    pending = {}
    unconfirmed = {}
end
