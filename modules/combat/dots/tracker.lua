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
-- A mark (Death Mark) deals, when it ends, a share of what the player dealt
-- the unit while it lasted (spells.lua): the followed effects' ticks (it keeps
-- the effects that ran on the unit then, replaced ones included up to when they
-- were, and counts their ticks in its window), the strikes that landed on it
-- then, and white swings while the player auto attacks it (counted until the
-- mark ends unless they stop or the target changes before).
--
-- Effects are kept by unit: by its GUID, or by its nameplate while its GUID
-- is secret (Tracker:GetUnitKey).
--
-- Out of combat the player's auras are readable again: effects whose aura is
-- gone are forgotten (the unit died, reset or was cleansed), the others take
-- the aura's timing.
--
-- Whatever changes what the player has yet to deal to a unit is told to
-- sharing.lua, which sends it to the group.

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

-- How far (seconds) an aura's timing must be from ours for the group to hear of it.
local TIMING_SLACK = 0.25

local EMPTY = {}

-- Unit key (Tracker:GetUnitKey) -> spell key -> { key, start, duration, perTick, tick }.
local effects = {}
-- Unit key -> amplifier key -> { from, to, bonus, amplifies }.
local amplifiers = {}
-- Unit key -> mark key -> { from, to, share, cap, stores, sources, strikes,
-- swingRate, swingSeconds, swingingSince } (sources: the effects that ran on the
-- unit while it lasts, `ended` set on one replaced; strikes: the damage of the
-- strikes that landed, through its armor; swingRate: white swing damage per
-- second through its armor; swingSeconds: the time spent swinging at the unit,
-- swingingSince when it is going on).
local marks = {}
-- Whether the player auto attacks their target (PLAYER_ENTER_COMBAT).
local swinging = false
-- The last cast sent: { castGUID, unitKey, points, armorPassed } (its target,
-- the combo points on it then, and the share of physical damage its armor
-- lets through).
local lastSent
-- Casts that landed this frame: { unitKey, spellID, definition, amplifier, mark,
-- points, armorPassed, time, missed }.
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

-- Whether a unit key is a nameplate's token, which only means something to
-- this client, until the plate is removed.
function Tracker:IsPlateKey(unitKey)
    return unitKey:match("^nameplate%d+$") ~= nil
end

local function TickCount(effect)
    return math.floor(effect.duration / effect.tick + 0.5)
end

-- How many of the effect's ticks have landed by `now`.
local function LandedTicks(effect, now)
    return math.floor((now - effect.start) / effect.tick)
end

-- The first and last of the effect's ticks left at `now` (the first is past the
-- last when none is).
function Tracker:GetTicksLeft(effect, now)
    return LandedTicks(effect, now) + 1, TickCount(effect)
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

-- The damage the mark stores (its sources' ticks, the strikes, the white
-- swings until it ends), up to its cap.
local function StoredDamage(unitKey, mark)
    local stored = 0
    for _, effect in ipairs(mark.sources) do
        for index = 1, TickCount(effect) do
            local time = effect.start + index * effect.tick
            if time > mark.from and time <= mark.to and time <= (effect.ended or math.huge) then
                stored = stored + TickDamage(unitKey, effect, time) * mark.stores[effect.key]
            end
        end
    end
    local swingSeconds = mark.swingSeconds
    if mark.swingingSince then
        swingSeconds = swingSeconds + mark.to - mark.swingingSince
    end
    stored = stored + mark.strikes + mark.swingRate * swingSeconds
    return math.min(stored * mark.share, mark.cap)
end

-- Starts or stops counting each running mark's white swings: they go to the
-- target while the player auto attacks.
local function SyncSwings()
    local now = GetTime()
    local swungAt = swinging and Tracker:GetUnitKey("target")
    for unitKey, unitMarks in pairs(marks) do
        for _, mark in pairs(unitMarks) do
            local swung = unitKey == swungAt and now < mark.to
            if mark.swingingSince and not swung then
                mark.swingSeconds = mark.swingSeconds + math.min(now, mark.to) - mark.swingingSince
                mark.swingingSince = nil
                DoTs.Sharing:OnUnitChanged(unitKey)
            elseif swung and not mark.swingingSince then
                mark.swingingSince = now
                DoTs.Sharing:OnUnitChanged(unitKey)
            end
        end
    end
end

-- Whether a mark on the unit has yet to deal its damage.
local function HasRunningMark(unitKey, now)
    for _, mark in pairs(marks[unitKey] or EMPTY) do
        if now < mark.to then
            return true
        end
    end
    return false
end

local function ApplyMark(cast)
    local definition = cast.mark
    local share, cap = DoTs.Spells:ReadMark(cast.spellID, cast.points)
    if not share then
        return
    end
    local sources = {}
    for key, effect in pairs(effects[cast.unitKey] or EMPTY) do
        if definition.stores[key] then
            table.insert(sources, effect)
        end
    end
    marks[cast.unitKey] = marks[cast.unitKey] or {}
    marks[cast.unitKey][definition.key] = {
        from = cast.time,
        to = cast.time + definition.duration,
        share = share,
        cap = cap,
        stores = definition.stores,
        sources = sources,
        strikes = 0,
        swingRate = DoTs.Spells:GetSwingDamagePerSecond() * cast.armorPassed,
        swingSeconds = 0,
    }
    SyncSwings()
    DoTs.Sharing:OnUnitChanged(cast.unitKey)
end

local function ApplyAmplifier(cast)
    local amplifier = cast.amplifier
    amplifiers[cast.unitKey] = amplifiers[cast.unitKey] or {}
    amplifiers[cast.unitKey][amplifier.key] = {
        from = cast.time,
        to = cast.time + amplifier.duration,
        bonus = amplifier.bonus,
        amplifies = amplifier.amplifies,
    }
    if effects[cast.unitKey] then
        DoTs.Sharing:OnUnitChanged(cast.unitKey)
    end
end

-- Adds the strike's damage, through the unit's armor, to the marks running on
-- the unit.
local function ApplyStrike(cast)
    local damage
    for _, mark in pairs(marks[cast.unitKey] or EMPTY) do
        if cast.time >= mark.from and cast.time < mark.to then
            damage = damage or (DoTs.Spells:ReadStrike(cast.strike, cast.spellID, cast.points) or 0) * cast.armorPassed
            mark.strikes = mark.strikes + damage
            DoTs.Sharing:OnUnitChanged(cast.unitKey)
        end
    end
end

local function ApplyEffect(cast)
    local definition = cast.definition
    local perTick, duration = DoTs.Spells:Read(definition, cast.spellID, cast.points)
    if not perTick or duration < definition.tick then
        return
    end
    effects[cast.unitKey] = effects[cast.unitKey] or {}
    local replaced = effects[cast.unitKey][definition.key]
    if replaced then
        replaced.ended = cast.time
    end
    local effect = {
        key = definition.key,
        start = cast.time,
        duration = duration,
        perTick = perTick,
        tick = definition.tick,
    }
    effects[cast.unitKey][definition.key] = effect
    for _, mark in pairs(marks[cast.unitKey] or EMPTY) do
        if mark.stores[definition.key] and cast.time < mark.to then
            table.insert(mark.sources, effect)
        end
    end
    DoTs.Sharing:OnUnitChanged(cast.unitKey)
end

-- A cast that landed: a spell can be several of these (Hemorrhage amplifies
-- and strikes).
local function Apply(cast)
    if cast.mark then
        ApplyMark(cast)
    end
    if cast.amplifier then
        ApplyAmplifier(cast)
    end
    if cast.strike then
        ApplyStrike(cast)
    end
    if cast.definition then
        ApplyEffect(cast)
    end
end

-- The definition (or amplifier, mark or strike) of a cast.
local function Definition(cast)
    return cast.definition or cast.amplifier or cast.mark or cast.strike
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
        elseif Definition(cast).comboPoints then
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
    local mark = DoTs.Spells:GetMark(spellID)
    local strike = DoTs.Spells:GetStrike(spellID)
    if not (definition or amplifier or mark or strike) then
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
        mark = mark,
        strike = strike,
        points = points or GetComboPoints("player", "target"),
        armorPassed = sent and sent.armorPassed or DoTs.Armor:GetPassedShare("target"),
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

local function GetAura(unit, key)
    return C_UnitAuras.GetAuraDataBySpellName(unit, DoTs.Spells:GetName(key), "HARMFUL|PLAYER")
end

-- Out of combat: drops the effects and marks on the unit whose aura is gone,
-- and gives the other effects the aura's timing.
local function Reconcile(unit)
    if InCombatLockdown() or C_Secrets.ShouldAurasBeSecret() then
        return
    end
    local unitKey = Tracker:GetUnitKey(unit)
    if not unitKey or not (effects[unitKey] or marks[unitKey]) then
        return
    end
    local changed = false
    for key, effect in pairs(effects[unitKey] or EMPTY) do
        local aura = GetAura(unit, key)
        if aura then
            local start = aura.expirationTime - aura.duration
            changed = changed
                or math.abs(aura.duration - effect.duration) > TIMING_SLACK
                or math.abs(start - effect.start) > TIMING_SLACK
            effect.duration = aura.duration
            effect.start = start
        else
            effect.ended = GetTime()
            effects[unitKey][key] = nil
            changed = true
        end
    end
    for key in pairs(marks[unitKey] or EMPTY) do
        if not GetAura(unit, key) then
            marks[unitKey][key] = nil
            changed = true
        end
    end
    if changed then
        DoTs.Sharing:OnUnitChanged(unitKey)
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
        if
            unit == "player"
            and (
                DoTs.Spells:Get(spellID)
                or DoTs.Spells:GetAmplifier(spellID)
                or DoTs.Spells:GetMark(spellID)
                or DoTs.Spells:GetStrike(spellID)
            )
        then
            lastSent = {
                castGUID = castGUID,
                unitKey = Tracker:GetUnitKey("target"),
                points = GetComboPoints("player", "target"),
                armorPassed = DoTs.Armor:GetPassedShare("target"),
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
    -- Auto attack starts and stops; it swings at the target.
    PLAYER_ENTER_COMBAT = function()
        swinging = true
        SyncSwings()
        DoTs.Overlays:Refresh()
    end,
    PLAYER_LEAVE_COMBAT = function()
        swinging = false
        SyncSwings()
        DoTs.Overlays:Refresh()
    end,
    PLAYER_TARGET_CHANGED = function()
        SyncSwings()
        DoTs.Overlays:Refresh()
    end,
    -- Effects kept under the plate's token: its next unit is another.
    NAME_PLATE_UNIT_REMOVED = function(_, unit)
        Tracker:Forget(unit)
    end,
})

-- The damage the player's effects and marks on the unit have yet to deal: the
-- effects' ticks, what the marks will deal, and the seconds until the next mark
-- with damage to deal does (math.huge without one).
function Tracker:GetRemainingDamage(unitKey)
    local now = GetTime()
    local ticks = 0
    for _, effect in pairs(effects[unitKey] or EMPTY) do
        local first, last = self:GetTicksLeft(effect, now)
        for index = first, last do
            ticks = ticks + TickDamage(unitKey, effect, effect.start + index * effect.tick)
        end
    end
    local stored, left = 0, math.huge
    for _, mark in pairs(marks[unitKey] or EMPTY) do
        local damage = now < mark.to and StoredDamage(unitKey, mark) or 0
        if damage > 0 then
            stored = stored + damage
            left = math.min(left, mark.to - now)
        end
    end
    return ticks, stored, left
end

-- What the player's effects and marks have yet to deal to the unit, for the
-- group: the effects running, { perTick, tick, duration, elapsed, amplifiers =
-- { { bonus, left } } }, and the marks, { damage, left } (elapsed and left:
-- seconds from now).
function Tracker:GetSnapshot(unitKey)
    local now = GetTime()
    local runningEffects, runningMarks = {}, {}
    for key, effect in pairs(effects[unitKey] or EMPTY) do
        local first, last = self:GetTicksLeft(effect, now)
        if first <= last then
            local raisedBy = {}
            for _, amplifier in pairs(amplifiers[unitKey] or EMPTY) do
                if amplifier.amplifies[key] and now < amplifier.to then
                    table.insert(raisedBy, { bonus = amplifier.bonus, left = amplifier.to - now })
                end
            end
            table.insert(runningEffects, {
                perTick = effect.perTick,
                tick = effect.tick,
                duration = effect.duration,
                elapsed = math.max(0, now - effect.start),
                amplifiers = raisedBy,
            })
        end
    end
    for _, mark in pairs(marks[unitKey] or EMPTY) do
        if now < mark.to then
            table.insert(runningMarks, { damage = StoredDamage(unitKey, mark), left = mark.to - now })
        end
    end
    return runningEffects, runningMarks
end

-- Calls func(unitKey) for each unit the player has effects or marks on.
function Tracker:ForEachUnit(func)
    for unitKey in pairs(effects) do
        func(unitKey)
    end
    for unitKey in pairs(marks) do
        if not effects[unitKey] then
            func(unitKey)
        end
    end
end

-- Forgets the player's effects on the unit (it died).
function Tracker:Forget(unitKey)
    effects[unitKey] = nil
    amplifiers[unitKey] = nil
    marks[unitKey] = nil
end

-- Forgets the effects whose last tick landed, the marks that dealt their
-- damage and the amplifiers that ended (kept while a mark counts the ticks
-- they raised), on every unit (most are never shown again).
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
    for unitKey, unitMarks in pairs(marks) do
        for key, mark in pairs(unitMarks) do
            if now >= mark.to then
                unitMarks[key] = nil
            end
        end
        if next(unitMarks) == nil then
            marks[unitKey] = nil
        end
    end
    for unitKey, unitAmplifiers in pairs(amplifiers) do
        local marked = HasRunningMark(unitKey, now)
        for key, amplifier in pairs(unitAmplifiers) do
            if now > amplifier.to and not marked then
                unitAmplifiers[key] = nil
            end
        end
        if next(unitAmplifiers) == nil then
            amplifiers[unitKey] = nil
        end
    end
end

-- Whether any unit has effects or marks running.
function Tracker:IsTracking()
    return next(effects) ~= nil or next(marks) ~= nil
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
    marks = {}
    swinging = false
    lastSent = nil
    pending = {}
    unconfirmed = {}
end
