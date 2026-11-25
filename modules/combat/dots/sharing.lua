-- The "share" part: group members who run the addon see the same damage to
-- come, everyone's effects added up.
--
-- Each player tells the group what their effects and marks have yet to deal to
-- a unit, whenever that changes: a whole snapshot, which replaces their last
-- one on that unit. The sender works out the damage (it depends on their ranks,
-- talents and power); the receiver only adds it up until it ends or the unit
-- dies. Clocks differ between clients: times are relative to the sending.
--
-- A unit's GUID is the same for everyone. Units told apart by their nameplate
-- (their GUID is secret: dungeons and raids, where the client's documentation
-- says addon messages are refused too) aren't shared.
--
-- Messages start with the protocol version:
--   "1Q:<player GUID>"  the sender joined the group, or just loaded: answer
--                       with your snapshots
--   "1U:<player GUID>:<unit GUID>:<effects>:<marks>"  a snapshot; `;` separates
--                       effects and marks, `,` the numbers of one:
--     effect: damage per tick, seconds between ticks, duration, seconds since
--             it started, then for each amplifier its bonus and seconds left
--     mark:   the damage it will deal, seconds left

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local Sharing = {}
DoTs.Sharing = Sharing

local PREFIX = "FEDots"
local VERSION = "1"
-- More ticks than any effect has: a snapshot past it is malformed.
local MAX_TICKS = 100

local RECEIVE_CHANNELS = {
    PARTY = true,
    RAID = true,
    INSTANCE_CHAT = true,
}

local EMPTY = {}

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- What group members have yet to deal: unit GUID -> player GUID ->
-- { effects = { { start, duration, perTick, tick, amplifiers = { { bonus, to } } } },
-- marks = { { damage, to } } }.
local shared = {}
-- The units whose snapshot waits to be sent, in order, and as a set.
local queue = {}
local queued = {}
-- Whether an ask waits to be sent (before the snapshots).
local asking = false
-- Whether the player was in a group as of the last roster update.
local grouped = false
local pumpScheduled = false

local function GetChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "PARTY"
    end
    return nil
end

local function ClearQueue()
    queue = {}
    queued = {}
    asking = false
end

local function FormatNumbers(numbers)
    local texts = {}
    for index, number in ipairs(numbers) do
        texts[index] = ("%.2f"):format(number)
    end
    return table.concat(texts, ",")
end

local function AskMessage()
    return ("%sQ:%s"):format(VERSION, UnitGUID("player"))
end

local function SnapshotMessage(unitGUID)
    local effects, marks = DoTs.Tracker:GetSnapshot(unitGUID)
    local effectTexts, markTexts = {}, {}
    for _, effect in ipairs(effects) do
        local numbers = { effect.perTick, effect.tick, effect.duration, effect.elapsed }
        for _, amplifier in ipairs(effect.amplifiers) do
            table.insert(numbers, amplifier.bonus)
            table.insert(numbers, amplifier.left)
        end
        table.insert(effectTexts, FormatNumbers(numbers))
    end
    for _, mark in ipairs(marks) do
        table.insert(markTexts, FormatNumbers({ mark.damage, mark.left }))
    end
    local effectsText, marksText = table.concat(effectTexts, ";"), table.concat(markTexts, ";")
    return ("%sU:%s:%s:%s:%s"):format(VERSION, UnitGUID("player"), unitGUID, effectsText, marksText)
end

-- What waits, for the pacer. A snapshot is taken as it goes out, so one that
-- waited holds the latest, timed from then.
local Outbox = {}

function Outbox:HasNext()
    return asking or #queue > 0
end

function Outbox:SendNext()
    local channel = GetChannel()
    if not channel then
        ClearQueue()
        return true
    end
    local message = asking and AskMessage() or SnapshotMessage(queue[1])
    if ns:IsMessageThrottled(C_ChatInfo.SendAddonMessage(PREFIX, message, channel)) then
        return false
    end
    if asking then
        asking = false
    else
        queued[table.remove(queue, 1)] = nil
    end
    return true
end

local pacer = ns:CreateMessagePacer(Outbox)

-- On the next frame: one cast can change a unit several times.
local function SchedulePump()
    if pumpScheduled then
        return
    end
    pumpScheduled = true
    C_Timer.After(0, function()
        pumpScheduled = false
        if DoTs:IsPartActive("share") then
            pacer:Pump()
        end
    end)
end

local function Ask()
    if GetChannel() then
        asking = true
        SchedulePump()
    end
end

-- What the player has yet to deal to the unit changed.
function Sharing:OnUnitChanged(unitKey)
    if not DoTs:IsPartActive("share") or not GetChannel() or DoTs.Tracker:IsPlateKey(unitKey) then
        return
    end
    if not queued[unitKey] then
        queued[unitKey] = true
        table.insert(queue, unitKey)
    end
    SchedulePump()
end

local function SendAll()
    DoTs.Tracker:ForEachUnit(function(unitKey)
        Sharing:OnUnitChanged(unitKey)
    end)
end

-- The numbers of a list, or nil when one isn't.
local function ParseNumbers(text)
    local numbers = {}
    for _, part in ipairs({ strsplit(",", text) }) do
        local number = part:match("^%d+%.%d+$") and tonumber(part)
        if not number then
            return nil
        end
        table.insert(numbers, number)
    end
    return numbers
end

local function ParseEffect(text, now)
    local numbers = ParseNumbers(text)
    if not numbers or #numbers < 4 or #numbers % 2 ~= 0 then
        return nil
    end
    local perTick, tick, duration, elapsed = unpack(numbers, 1, 4)
    if tick == 0 or duration / tick > MAX_TICKS then
        return nil
    end
    local amplifiers = {}
    for index = 5, #numbers, 2 do
        table.insert(amplifiers, { bonus = numbers[index], to = now + numbers[index + 1] })
    end
    return { start = now - elapsed, duration = duration, perTick = perTick, tick = tick, amplifiers = amplifiers }
end

local function ParseMark(text, now)
    local numbers = ParseNumbers(text)
    if not numbers or #numbers ~= 2 then
        return nil
    end
    return { damage = numbers[1], to = now + numbers[2] }
end

-- The entries of a list, or nil when one is malformed.
local function ParseList(text, parse, now)
    local entries = {}
    if text == "" then
        return entries
    end
    for _, part in ipairs({ strsplit(";", text) }) do
        local entry = parse(part, now)
        if not entry then
            return nil
        end
        table.insert(entries, entry)
    end
    return entries
end

-- Whether a message's sender is another member of the group (the client gives
-- the player's own messages back too).
local function IsMember(playerGUID)
    return playerGUID ~= UnitGUID("player") and C_PartyInfo.IsGUIDInGroup(playerGUID)
end

local function OnSnapshot(playerGUID, rest)
    local unitGUID, effectsText, marksText = rest:match("^:([^:]+):([^:]*):([^:]*)$")
    if not unitGUID then
        return
    end
    local now = GetTime()
    local effects = ParseList(effectsText, ParseEffect, now)
    local marks = ParseList(marksText, ParseMark, now)
    if not effects or not marks then
        return
    end
    shared[unitGUID] = shared[unitGUID] or {}
    shared[unitGUID][playerGUID] = { effects = effects, marks = marks }
    DoTs.Overlays:Refresh()
end

local function HasLeft(_, playerGUID)
    return not C_PartyInfo.IsGUIDInGroup(playerGUID)
end

-- Forgets the snapshots `condition(snapshot, playerGUID)` is true of.
local function ForgetWhere(condition)
    for unitGUID, snapshots in pairs(shared) do
        for playerGUID, snapshot in pairs(snapshots) do
            if condition(snapshot, playerGUID) then
                snapshots[playerGUID] = nil
            end
        end
        if next(snapshots) == nil then
            shared[unitGUID] = nil
        end
    end
end

local listener = ns:CreateEventListener({
    CHAT_MSG_ADDON = function(_, prefix, text, chatType)
        if ns:IsAnySecret(prefix, text, chatType) or prefix ~= PREFIX or not RECEIVE_CHANNELS[chatType] then
            return
        end
        local kind, playerGUID, rest = text:match("^" .. VERSION .. "(%u):([^:]+)(.*)$")
        if not kind or not IsMember(playerGUID) then
            return
        end
        if kind == "Q" then
            SendAll()
        elseif kind == "U" then
            OnSnapshot(playerGUID, rest)
        end
    end,
    -- What the group sent during a loading screen may be lost.
    PLAYER_ENTERING_WORLD = Ask,
    GROUP_ROSTER_UPDATE = function()
        local wasGrouped = grouped
        grouped = GetChannel() ~= nil
        if grouped and not wasGrouped then
            Ask()
            SendAll()
        end
        ForgetWhere(HasLeft)
        DoTs.Overlays:Refresh()
    end,
})

local function SharedTickDamage(effect, time)
    local multiplier = 1
    for _, amplifier in ipairs(effect.amplifiers) do
        if time <= amplifier.to then
            multiplier = multiplier + amplifier.bonus
        end
    end
    return effect.perTick * multiplier
end

-- The damage group members' effects and marks have yet to deal to the unit:
-- the effects' ticks, what the marks will deal, and the seconds until the next
-- mark with damage to deal does (math.huge without one).
function Sharing:GetRemainingDamage(unitKey)
    local ticks, stored, left = 0, 0, math.huge
    local now = GetTime()
    for _, snapshot in pairs(shared[unitKey] or EMPTY) do
        for _, effect in ipairs(snapshot.effects) do
            local first, last = DoTs.Tracker:GetTicksLeft(effect, now)
            for index = first, last do
                ticks = ticks + SharedTickDamage(effect, effect.start + index * effect.tick)
            end
        end
        for _, mark in ipairs(snapshot.marks) do
            if now < mark.to and mark.damage > 0 then
                stored = stored + mark.damage
                left = math.min(left, mark.to - now)
            end
        end
    end
    return ticks, stored, left
end

-- Forgets the group's effects on the unit (it died).
function Sharing:Forget(unitKey)
    shared[unitKey] = nil
end

local function HasEnded(snapshot)
    local now = GetTime()
    for _, effect in ipairs(snapshot.effects) do
        local first, last = DoTs.Tracker:GetTicksLeft(effect, now)
        if first <= last then
            return false
        end
    end
    for _, mark in ipairs(snapshot.marks) do
        if now < mark.to then
            return false
        end
    end
    return true
end

-- Forgets the snapshots with nothing left to deal, on every unit (most are
-- never shown again).
function Sharing:ForgetEnded()
    ForgetWhere(HasEnded)
end

-- Whether group members have anything left to deal to any unit.
function Sharing:IsTracking()
    return next(shared) ~= nil
end

function Sharing:Enable()
    listener:Start()
    grouped = GetChannel() ~= nil
    Ask()
    SendAll()
end

function Sharing:Disable()
    listener:Stop()
    pacer:Cancel()
    ClearQueue()
    shared = {}
    DoTs.Overlays:Refresh()
end
