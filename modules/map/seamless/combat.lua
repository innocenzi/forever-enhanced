-- Map pins' mouse input in combat. As each pin is put on the map, Blizzard sets
-- which mouse buttons pass through it (MapCanvasPinMixin:CheckMouseButtonPassthrough:
-- right clicks go on to the map) and whether its clicks go on to the map
-- (SuperTrackablePinMixin:UpdateMousePropagation). The game blocks both setters
-- (SetPassThroughButtons, SetPropagateMouseClicks) in combat when the map's code
-- runs tainted, which it does once the stitched map has touched it (feature.lua):
-- every map refresh in combat (opening it, the quest log updating) was an "action
-- blocked" error. So in combat each pin's last request waits, and is applied when
-- combat ends (a right click on a pin placed in combat doesn't reach the map until then).
--
-- CreateFromMixins copies methods: every mixin made from Blizzard's (other addons'
-- too) and every pin already made from one is pointed at ours; pins made later
-- inherit it. Mixins of addons loaded later are pointed after they load (one sweep a
-- frame), and a new pool of pins as the canvas first redraws with it.
--
-- Installed on the feature's first enable, for the rest of the session: the map stays
-- tainted until a /reload once the feature has touched it, turned off or not
-- (feature.lua), so the requests keep waiting out combat, and its hooks don't check
-- whether the feature is on.
--
-- From OpenMap's Map/Combat.lua (openmap-license.txt).

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")

local Combat = {}
Seamless.Combat = Combat

local installed = false
local passthrough, propagation -- Blizzard's
-- pin -> { passthrough = { n, ... }, propagation = { n, ... } }: requests waiting for the end of combat
local waiting = setmetatable({}, { __mode = "k" })
-- pin pools already pointed
local seenPools = setmetatable({}, { __mode = "k" })
local sweepSoon = false

local function Wait(pin, key, ...)
    waiting[pin] = waiting[pin] or {}
    waiting[pin][key] = { n = select("#", ...), ... }
end

local function Done(pin, key)
    local requests = waiting[pin]
    if requests then
        requests[key] = nil
        if not requests.passthrough and not requests.propagation then
            waiting[pin] = nil
        end
    end
end

-- (in combat, nothing is returned: Blizzard's map ignores what these return as it puts a pin up)
local function DeferredPassthrough(pin, ...)
    if InCombatLockdown() then
        return Wait(pin, "passthrough", ...)
    end
    Done(pin, "passthrough")
    return passthrough(pin, ...)
end

local function DeferredPropagation(pin, ...)
    if InCombatLockdown() then
        return Wait(pin, "propagation", ...)
    end
    Done(pin, "propagation")
    return propagation(pin, ...)
end

local function Point(object)
    if type(object) ~= "table" then
        return
    end
    -- (a forbidden table errors on any read: left alone)
    local ok, method = pcall(rawget, object, "CheckMouseButtonPassthrough")
    if ok and method == passthrough then
        object.CheckMouseButtonPassthrough = DeferredPassthrough
    end
    ok, method = pcall(rawget, object, "UpdateMousePropagation")
    if ok and method == propagation then
        object.UpdateMousePropagation = DeferredPropagation
    end
end

-- (a pool lists only its pins in use: one released before it was pointed is pointed
-- the next time it's in use as the map shows)
local function PointPool(pool)
    for pin in pool:EnumerateActive() do
        Point(pin)
    end
end

local function PointPins()
    for _, pool in pairs(WorldMapFrame.pinPools) do
        PointPool(pool)
    end
end

-- Pools not met before: the first pins of a new pool, as the canvas redraws with it.
local function ScanPools()
    for _, pool in pairs(WorldMapFrame.pinPools) do
        if not seenPools[pool] then
            seenPools[pool] = true
            PointPool(pool)
        end
    end
end

local function Sweep()
    sweepSoon = false
    for _, value in pairs(_G) do
        Point(value)
    end
    PointPins()
end

local function Flush()
    for pin, requests in pairs(waiting) do
        waiting[pin] = nil
        -- (a pin let go meanwhile has no map: its old setup isn't wanted)
        if pin:GetMap() then
            if requests.passthrough then
                passthrough(pin, unpack(requests.passthrough, 1, requests.passthrough.n))
            end
            if requests.propagation then
                propagation(pin, unpack(requests.propagation, 1, requests.propagation.n))
            end
        end
    end
end

local listener = ns:CreateEventListener({
    ADDON_LOADED = function()
        -- (addons loading one after another: one sweep, on the next frame)
        if not sweepSoon then
            sweepSoon = true
            C_Timer.After(0, Sweep)
        end
    end,
    PLAYER_REGEN_ENABLED = Flush,
})

local function Install()
    installed = true
    passthrough = MapCanvasPinMixin.CheckMouseButtonPassthrough
    propagation = SuperTrackablePinMixin.UpdateMousePropagation
    Sweep()
    ScanPools()
    WorldMapFrame:HookScript("OnShow", PointPins)
    hooksecurefunc(WorldMapFrame.ScrollContainer, "MarkCanvasDirty", ScanPools)
    listener:Start()
end

function Combat:Enable()
    if not installed then
        Install()
    end
end

-- Nothing: once installed, the requests wait out combat for the rest of the session.
function Combat:Disable() end
