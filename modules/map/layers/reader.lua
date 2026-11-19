-- The player's layer, read from the creatures around: the game has no layer
-- API, but a creature's GUID names the layer it stands on (protocol.lua). Read
-- from nameplates as they show, the target and the mouseover; pets and other
-- player-controlled units carry where they were summoned, so they don't count.
--
-- A transfer (the game moving the player to another layer), a zone border or
-- a loading screen makes the layer unknown. Creatures still in view after a
-- transfer or a border may be those of the layer or zone left: they don't
-- count for SNAPSHOT_SECONDS, after which the units in view are read again.
-- While the layer is unknown, one new creature reads it; once known, it takes
-- two creatures of another layer within OTHERS_SECONDS to change it (one
-- wandering in from the next zone isn't enough). Instances have no layers:
-- nothing is read there.
--
-- Layers get letters per zone in the order the player meets them ("Layer A",
-- "Layer B"), kept for an hour in the character store so a reload keeps them.
--
-- When the player asks for a swap without a known layer, nameplates are shown
-- for a moment (the CVars of `override`) so a creature comes into view: put
-- back as soon as the layer is read, or after FLASH_SECONDS. Never in combat.

local _, ns = ...

local Layers = ns:GetFeature("map", "layers")
local Protocol = Layers.Protocol

local Reader = {}
Layers.Reader = Reader

local SNAPSHOT_SECONDS = 10
local FLASH_SECONDS = 3
local LABEL_SECONDS = 3600
local PLATE_CVARS = { "nameplateShowAll", "nameplateShowEnemies", "nameplateShowFriendlyNPCs" }
local MAX_PLATES = 40
local OTHERS_SECONDS = 60

local override = ns:CreateCVarOverride(Layers)

local current
-- The letter of `current` in its zone.
local letter
-- GUIDs in view at the last reset, ignored until snapshotTimer runs.
local ignored = {}
local snapshotTimer
-- Creatures of another layer than `current` since it was read, by GUID:
-- { key (their layer's), at }.
local others = {}
local flashTimer

local function ForEachUnitInView(callback)
    for index = 1, MAX_PLATES do
        callback("nameplate" .. index)
    end
    callback("target")
    callback("mouseover")
end

local function Labels()
    local store = Layers:GetCharacterStore()
    store.labels = store.labels or {}
    return store.labels
end

-- The letter of `layer` in `zone`, given one if new; letters of layers
-- unseen for an hour are forgotten.
local function LetterOf(layer, zone)
    local labels = Labels()
    local now = GetServerTime()
    local zoneLabels = labels[zone] or { count = 0, layers = {} }
    labels[zone] = zoneLabels
    for key, entry in pairs(zoneLabels.layers) do
        if now - entry.seen > LABEL_SECONDS then
            zoneLabels.layers[key] = nil
        end
    end
    if next(zoneLabels.layers) == nil then
        zoneLabels.count = 0
    end
    local key = Protocol:LayerKey(layer)
    local entry = zoneLabels.layers[key]
    if not entry then
        zoneLabels.count = zoneLabels.count + 1
        entry = { letter = zoneLabels.count <= 26 and string.char(64 + zoneLabels.count) or tostring(zoneLabels.count) }
        zoneLabels.layers[key] = entry
    end
    entry.seen = now
    return entry.letter
end

function Reader:Unflash()
    if flashTimer then
        flashTimer:Cancel()
        flashTimer = nil
    end
    override:Restore()
end

local function SetCurrent(layer)
    current = layer
    others = {}
    Reader:Unflash()
    local zone = Protocol:ZoneMap()
    letter = zone and LetterOf(layer, zone) or nil
    Layers.Swap:OnLayerRead(layer)
end

local function Observe(unit)
    if IsInInstance() then
        return
    end
    local guid = UnitGUID(unit)
    local layer = Protocol:ParseCreatureGUID(guid)
    if not layer or ignored[guid] or others[guid] or UnitPlayerControlled(unit) then
        return
    end
    if not current then
        SetCurrent(layer)
        return
    end
    if Protocol:SameLayer(layer, current) then
        return
    end
    local key, now = Protocol:LayerKey(layer), GetTime()
    others[guid] = { key = key, at = now }
    local count = 0
    for _, other in pairs(others) do
        if other.key == key and now - other.at <= OTHERS_SECONDS then
            count = count + 1
        end
    end
    if count >= 2 then
        SetCurrent(layer)
    end
end

-- Reads the units in view now.
function Reader:Scan()
    ForEachUnitInView(Observe)
end

-- Forgets the layer. `snapshot`: the units in view may be of the layer or
-- zone left behind (a transfer, a zone border), so they don't count for a while.
local function Reset(snapshot)
    current = nil
    letter = nil
    others = {}
    ignored = {}
    if snapshotTimer then
        snapshotTimer:Cancel()
        snapshotTimer = nil
    end
    if not snapshot then
        return
    end
    ForEachUnitInView(function(unit)
        local guid = UnitGUID(unit)
        if guid and not issecretvalue(guid) then
            ignored[guid] = true
        end
    end)
    snapshotTimer = C_Timer.NewTimer(SNAPSHOT_SECONDS, function()
        snapshotTimer = nil
        ignored = {}
        Reader:Scan()
    end)
end

local listener = ns:CreateEventListener({
    NAME_PLATE_UNIT_ADDED = function(_, unit)
        Observe(unit)
    end,
    PLAYER_TARGET_CHANGED = function()
        Observe("target")
    end,
    UPDATE_MOUSEOVER_UNIT = function()
        Observe("mouseover")
    end,
    SHARD_TRANSFER = function()
        Reset(true)
        Layers.Swap:OnTransfer()
        Layers.Host:OnTransfer()
    end,
    SHARD_TRANSFER_IMMINENT = function()
        Layers.Host:OnTransferAnnounced()
    end,
    ZONE_CHANGED_NEW_AREA = function()
        Reset(true)
    end,
    -- A loading screen: what shows next is the new place's.
    PLAYER_ENTERING_WORLD = function()
        Reset(false)
    end,
})

-- The layer the player stands on, or nil while unknown.
function Reader:GetCurrent()
    return current
end

-- The letter of the layer in its zone ("B"), or nil while unknown.
function Reader:GetLetter()
    return letter
end

-- "Layer B", or nil while unknown.
function Reader:GetLabel()
    return letter and ns.L["map.layers.layer"]:format(letter) or nil
end

-- Shows nameplates for a moment, unless the layer is known or in combat.
function Reader:Flash()
    if current or InCombatLockdown() then
        return
    end
    for _, name in ipairs(PLATE_CVARS) do
        override:Set(name, "1")
    end
    if flashTimer then
        flashTimer:Cancel()
    end
    flashTimer = C_Timer.NewTimer(FLASH_SECONDS, function()
        flashTimer = nil
        override:Restore()
    end)
end

function Reader:Enable()
    -- Nameplates a flash left shown when the game closed.
    override:Restore()
    listener:Start()
    Reset(false)
    self:Scan()
end

function Reader:Disable()
    listener:Stop()
    self:Unflash()
    Reset(false)
end
