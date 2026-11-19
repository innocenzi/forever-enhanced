-- Hosting (the "host" part, off unless the player turns it on): invites the
-- players who ask for another layer (protocol.lua) from the player's zone,
-- when the player stands on another layer than theirs. Every ask from the
-- zone gets a "heard" reply with the player's layer and whether the player
-- can invite now; an ask from the player's own layer gets "same" instead of
-- an invite that would change nothing.
--
-- The player only invites while free: out of combat, instances, flights and
-- the group finder, not asking for a layer themselves, and alone or leading a
-- group of their guests only. At most INVITE_CAP invites in INVITE_WINDOW
-- (players were silenced for "spamming group invites", LayerSwap's comments
-- say), and a player once a minute. Guests leave by themselves once moved:
-- nothing kicks them (the game restricts it), and the loot stays as it is.
--
-- The game sometimes moves the group's leader to its guest's layer instead: a
-- guest whose join or leave was followed by a transfer within MOVE_WATCH (one
-- the game didn't announce as a world refresh) isn't invited again for a while.

local _, ns = ...

local Layers = ns:GetFeature("map", "layers")
local Protocol = Layers.Protocol
local Comm = Layers.Comm
local Reader = Layers.Reader

local Host = {}
Layers.Host = Host

local INVITE_CAP = 6
local INVITE_WINDOW = 600
local PLAYER_COOLDOWN = 60
local PENDING_SECONDS = 60
local MOVED_SECONDS = 1800
local MOVE_WATCH = 20
local HEARD_COOLDOWN = 10
-- How long an asker's left layer counts for its ask sent again without it.
local LEAVES_SECONDS = 30
-- How long after the game announced a world refresh its transfer may come.
local ANNOUNCED_SECONDS = 60
local PARTY_MAX = 5

-- GetTime() of the invites sent lately.
local invites = {}
-- By key ("First Surname"): the last invite, invites not joined yet, guests in
-- the group (since when), guests that moved the player, the last "heard"
-- reply, and the layer each asker last said it leaves.
local lastInvite, pending, guests, movedBy, heardAt, leaves = {}, {}, {}, {}, {}, {}
-- { key, at }: the last guest who left.
local lastLeft
-- GetTime() the game announced a world refresh: its transfer is nobody's doing.
local announcedAt

-- The group's members by key, {} when alone, nil in a raid or when a name can't be read.
local function GroupMembers()
    local members = {}
    if not IsInGroup() then
        return members
    end
    if IsInRaid() then
        return nil
    end
    for index = 1, PARTY_MAX - 1 do
        local unit = "party" .. index
        if UnitExists(unit) then
            local key = Protocol:UnitKey(unit)
            if not key then
                return nil
            end
            table.insert(members, key)
        end
    end
    return members
end

local function PendingCount(now)
    local count = 0
    for key, at in pairs(pending) do
        if now - at > PENDING_SECONDS then
            pending[key] = nil
        else
            count = count + 1
        end
    end
    return count
end

local function RecentInvites(now)
    for index = #invites, 1, -1 do
        if now - invites[index] >= INVITE_WINDOW then
            table.remove(invites, index)
        end
    end
    return #invites
end

-- Whether the player is free to invite, and to invite `key` when given.
function Host:CanInvite(key)
    if InCombatLockdown() or IsInInstance() or UnitOnTaxi("player") then
        return false
    end
    if C_LFGList.HasActiveEntryInfo() or Layers.Swap:IsAsking() then
        return false
    end
    local now = GetTime()
    local members = GroupMembers()
    if not members then
        return false
    end
    if #members > 0 then
        if not UnitIsGroupLeader("player") then
            return false
        end
        for _, member in ipairs(members) do
            if not guests[member] and not pending[member] then
                return false
            end
        end
    end
    if 1 + #members + PendingCount(now) >= PARTY_MAX or RecentInvites(now) >= INVITE_CAP then
        return false
    end
    if key then
        if pending[key] or (lastInvite[key] and now - lastInvite[key] < PLAYER_COOLDOWN) then
            return false
        end
        if movedBy[key] and now - movedBy[key] < MOVED_SECONDS then
            return false
        end
    end
    return true
end

-- Forgets the askers and guests too old to matter.
local function Prune(now)
    for key, at in pairs(heardAt) do
        if now - at >= HEARD_COOLDOWN then
            heardAt[key] = nil
        end
    end
    for key, entry in pairs(leaves) do
        if now - entry.at > LEAVES_SECONDS then
            leaves[key] = nil
        end
    end
    for key, at in pairs(lastInvite) do
        if now - at >= PLAYER_COOLDOWN then
            lastInvite[key] = nil
        end
    end
    for key, at in pairs(movedBy) do
        if now - at >= MOVED_SECONDS then
            movedBy[key] = nil
        end
    end
end

-- An ask whispered by `sender` ("First Surname-Realm").
function Host:OnAsk(text, sender)
    if not Layers:IsPartActive("host") or IsInInstance() then
        return
    end
    local ask = Protocol:ParseAsk(text)
    local zone = Protocol:ZoneMap()
    if not ask or not zone or ask.zone ~= tostring(zone) then
        return
    end
    local key = Protocol:SenderKey(sender)
    local now = GetTime()
    Prune(now)
    local current = Reader:GetCurrent()
    if not current then
        Reader:Scan()
        current = Reader:GetCurrent()
    end
    local free = self:CanInvite(key)
    if not heardAt[key] then
        heardAt[key] = now
        Comm:Send(sender, Protocol:EncodeHeard(key, current, zone, free))
    end

    -- An ask sent again without the layer it leaves (the asker's answer to a
    -- host that didn't know its own) still leaves that layer.
    local leaving = ask.avoids[1]
    if leaving then
        leaves[key] = { layer = leaving, at = now }
    elseif not ask.want and leaves[key] and now - leaves[key].at <= LEAVES_SECONDS then
        leaving = leaves[key].layer
    end

    if not current or not free then
        return
    end
    if leaving and Protocol:SameLayer(leaving, current) then
        Comm:Send(sender, Protocol.SAME)
        return
    end
    if ask.want and not Protocol:SameLayer(ask.want, current) then
        return
    end
    for index = 2, #ask.avoids do
        if Protocol:SameLayer(ask.avoids[index], current) then
            return
        end
    end
    table.insert(invites, now)
    lastInvite[key] = now
    pending[key] = now
    -- By name without the realm, like LayerSwap's hosts.
    C_PartyInfo.InviteUnit(key)
end

function Host:OnTransferAnnounced()
    announcedAt = GetTime()
end

function Host:OnTransfer()
    local now = GetTime()
    local announced = announcedAt and now - announcedAt <= ANNOUNCED_SECONDS
    announcedAt = nil
    if not Layers:IsPartActive("host") or announced then
        return
    end
    local guest, at
    for key, joinedAt in pairs(guests) do
        if now - joinedAt <= MOVE_WATCH and (not at or joinedAt > at) then
            guest, at = key, joinedAt
        end
    end
    if lastLeft and now - lastLeft.at <= MOVE_WATCH and (not at or lastLeft.at > at) then
        guest = lastLeft.key
    end
    if guest then
        movedBy[guest] = now
    end
end

local listener = ns:CreateEventListener({
    GROUP_ROSTER_UPDATE = function()
        local members = GroupMembers()
        if not members then
            return
        end
        local now = GetTime()
        local present = {}
        for _, key in ipairs(members) do
            present[key] = true
            if pending[key] then
                pending[key] = nil
                guests[key] = now
            end
        end
        for key in pairs(guests) do
            if not present[key] then
                guests[key] = nil
                lastLeft = { key = key, at = now }
            end
        end
    end,
})

function Host:Enable()
    listener:Start()
end

function Host:Disable()
    listener:Stop()
    invites, lastInvite, pending, guests, movedBy, heardAt, leaves = {}, {}, {}, {}, {}, {}, {}
    lastLeft = nil
    announcedAt = nil
end
