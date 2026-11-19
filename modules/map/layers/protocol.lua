-- LayerSwap's wire format on the live realms, written from its messages so
-- the player can ask LayerSwap's hosts, and host for its users. Everything
-- travels as addon whispers on the "LayerSwap" prefix (the live realms refuse
-- an addon's chat lines and channel messages):
--
--   asker -> each player found:  inv layer <LS <zone> not <layer> <x>,<y>>
--     zone: the zone-level map ID; layer: the one the asker leaves (left out
--     while unknown); x,y: the asker's place on the zone map, in percent with
--     one decimal (hosts that skip askers near them drop asks without it).
--     LayerSwap's own asks may name more layers ("not" again, the ones it saw
--     in the zone) or one it wants ("want <layer>").
--   host -> asker:  heard <asker>|<layer or ->|<zone or ->|<h or ->
--     what the host stands on, and "h" when it can invite now
--   host -> asker:  same  (the host stands on the asker's layer)
--
-- A layer is read from creature GUIDs, Creature-0-<server>-<map>-<zoneUID>-...:
-- it's sent as "<server>-<zoneUID>", and two of them are the same layer when
-- their <server> parts are (measured on live by LayerSwap's author, and how
-- LayerSwap compares them).
--
-- Names on Forever are "First Surname"; an addon message's sender carries the
-- realm too ("First Surname-Realm"), which keys leave out.

local _, ns = ...

local Layers = ns:GetFeature("map", "layers")

local Protocol = {}
Layers.Protocol = Protocol

Protocol.PREFIX = "LayerSwap"

local ASK = "^inv layer"

local function IsReadable(value)
    return value ~= nil and not issecretvalue(value)
end

-- "<server>-<zoneUID>" of a creature's GUID, or nil for anything else.
function Protocol:ParseCreatureGUID(guid)
    if not IsReadable(guid) then
        return nil
    end
    local kind, _, server, _, zoneUID = strsplit("-", guid)
    if (kind ~= "Creature" and kind ~= "Vehicle") or not server or not zoneUID then
        return nil
    end
    return server .. "-" .. zoneUID
end

-- The part of a layer that names it: its <server>.
function Protocol:LayerKey(layer)
    return layer:match("^(%d+)%-") or layer
end

function Protocol:SameLayer(a, b)
    return a ~= nil and b ~= nil and self:LayerKey(a) == self:LayerKey(b)
end

-- The name without the realm.
function Protocol:SenderKey(sender)
    return sender:match("^([^%-]+)") or sender
end

-- A unit's "First Surname" (another unit gives the surname apart), or nil.
function Protocol:UnitKey(unit)
    local first, surname = UnitName(unit)
    if not IsReadable(first) or first == "" then
        return nil
    end
    if IsReadable(surname) and surname ~= "" then
        return first .. " " .. surname
    end
    return first
end

-- The zone-level map the player stands in (a cave or a town counts as its
-- zone: layers are the zone's), or nil.
function Protocol:ZoneMap()
    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info do
        if info.mapType == Enum.UIMapType.Zone then
            return info.mapID
        end
        if info.mapType < Enum.UIMapType.Zone or not info.parentMapID or info.parentMapID == 0 then
            return nil
        end
        info = C_Map.GetMapInfo(info.parentMapID)
    end
    return nil
end

-- The player's place on `zone`'s map, 0 to 1, or nil.
function Protocol:MapPosition(zone)
    local position = C_Map.GetPlayerMapPosition(zone, "player")
    local x, y = position and position.x, position and position.y
    if not IsReadable(x) or not IsReadable(y) or x < 0 or x > 1 or y < 0 or y > 1 then
        return nil
    end
    return x, y
end

-- The ask, from `zone`, leaving `leaving` (nil while unknown), at x, y (0 to 1, or nil).
function Protocol:EncodeAsk(zone, leaving, x, y)
    local parts = { "<LS", tostring(zone) }
    if leaving then
        table.insert(parts, "not " .. leaving)
    end
    if x and y then
        table.insert(parts, ("%.1f,%.1f"):format(x * 100, y * 100))
    end
    return "inv layer " .. table.concat(parts, " ") .. ">"
end

function Protocol:IsAsk(text)
    return text:find(ASK) ~= nil
end

-- { zone (a string), want, avoids = { the layer left, then any seen }, x, y }
-- of an ask, or nil without a zone: a host only answers askers of its zone.
function Protocol:ParseAsk(text)
    if not self:IsAsk(text) then
        return nil
    end
    local body = text:match("<LS([^<>]*)>")
    local zone = body and (body:match("^%s*(%d+)%s") or body:match("^%s*(%d+)%s*$"))
    if not zone then
        return nil
    end
    local avoids = {}
    for layer in body:gmatch("not%s+(%d+%-%d+)") do
        table.insert(avoids, layer)
    end
    local x, y = body:match("(%d+%.?%d*),(%d+%.?%d*)%s*$")
    return {
        zone = zone,
        want = body:match("want%s+(%d+%-%d+)"),
        avoids = avoids,
        x = tonumber(x),
        y = tonumber(y),
    }
end

function Protocol:EncodeHeard(asker, layer, zone, canInvite)
    return ("heard %s|%s|%s|%s"):format(asker, layer or "-", zone and tostring(zone) or "-", canInvite and "h" or "-")
end

Protocol.SAME = "same"

-- { kind = "heard", asker, layer, zone, canInvite } or { kind = "same" }, or nil.
function Protocol:ParseReply(text)
    local asker, layer, zone, flag = text:match("^heard (.-)|([^|]*)|([^|]*)|([^|]*)$")
    if asker then
        return {
            kind = "heard",
            asker = asker,
            layer = layer ~= "-" and layer or nil,
            zone = zone ~= "-" and zone or nil,
            canInvite = flag == "h",
        }
    end
    if text:match("^same%s*%S*$") then
        return { kind = "same" }
    end
    return nil
end
