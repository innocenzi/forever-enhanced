-- The friends' pins on the world map: a data provider on WorldMapFrame draws
-- the last position each friend sent, converted to the shown map through
-- world coordinates (a friend in a zone shows on its continent too).
-- Positions expire (after POSITION_SECONDS for the addon's own), and group
-- members are left to Blizzard's own pins. openmap.lua adds the positions of
-- friends who use OpenMap through SetPosition and ClearPosition.
--
-- While the map is shown it asks friends for their position: at once, then
-- every WATCH_SECONDS. A friend who answered once (a peer) is asked each time.
-- Other online friends are asked once, then not again until they come back
-- online: without the addon, they never answer.

local _, ns = ...

local Friends = ns:GetFeature("map", "friends")
local Roster, Comm = Friends.Roster, Friends.Comm

local Map = {}
Friends.Map = Map

local PIN_TEMPLATE = "ForeverEnhancedFriendPinTemplate"
local TICK_SECONDS = 5
local WATCH_SECONDS = 15
local POSITION_SECONDS = 40

-- guid -> { mapID, x, y, expiresAt }
local positions = {}
-- guid -> true once asked this session / once they answered
local asked = {}
local peers = {}
local ticker
local watchedAt

local provider = CreateFromMixins(MapCanvasDataProviderMixin)

-- Normalized coordinates of a friend's position on the shown map, or nil off it.
local function ToShownMap(position, shownMapID)
    local continentID, worldPosition =
        C_Map.GetWorldPosFromMapPos(position.mapID, CreateVector2D(position.x, position.y))
    if not continentID then
        return nil
    end
    local _, mapPosition = C_Map.GetMapPosFromWorldPos(continentID, worldPosition, shownMapID)
    if not mapPosition then
        return nil
    end
    local x, y = mapPosition.x, mapPosition.y
    if x < 0 or x > 1 or y < 0 or y > 1 then
        return nil
    end
    return x, y
end

function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function provider:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local shownMapID = map:GetMapID()
    local now = GetTime()
    for guid, position in pairs(positions) do
        if now <= position.expiresAt and not C_PartyInfo.IsGUIDInGroup(guid) then
            local x, y = ToShownMap(position, shownMapID)
            if x then
                map:AcquirePin(PIN_TEMPLATE, guid, position.mapID, x, y)
            end
        end
    end
end

function provider:OnShow()
    Map:StartWatching()
end

function provider:OnHide()
    Map:StopWatching()
end

local function Refresh()
    if WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end

local function SendWatches()
    watchedAt = GetTime()
    for guid in Roster:Enumerate() do
        if peers[guid] or not asked[guid] then
            asked[guid] = true
            Comm:Send(guid, Comm.WATCH)
        end
    end
end

local function DropExpired()
    local now = GetTime()
    local dropped = false
    for guid, position in pairs(positions) do
        if now > position.expiresAt then
            positions[guid] = nil
            dropped = true
        end
    end
    return dropped
end

local function Tick()
    if DropExpired() then
        Refresh()
    end
    if GetTime() - watchedAt >= WATCH_SECONDS then
        SendWatches()
    end
end

function Map:StartWatching()
    if ticker then
        return
    end
    SendWatches()
    ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
end

function Map:StopWatching()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Shows the friend `guid` at (x, y) on mapID for `seconds`, unless updated.
function Map:SetPosition(guid, mapID, x, y, seconds)
    positions[guid] = { mapID = mapID, x = x, y = y, expiresAt = GetTime() + seconds }
    Refresh()
end

function Map:ClearPosition(guid)
    if positions[guid] then
        positions[guid] = nil
        Refresh()
    end
end

function Map:OnPosition(guid, mapID, x, y)
    peers[guid] = true
    self:SetPosition(guid, mapID, x, y, POSITION_SECONDS)
end

function Map:OnHidden(guid)
    peers[guid] = true
    self:ClearPosition(guid)
end

-- Forgets friends who went offline, so they're asked again when they're back.
function Map:OnRosterChanged()
    for guid in pairs(asked) do
        if not Roster:Get(guid) then
            asked[guid], peers[guid] = nil, nil
        end
    end
    local changed = false
    for guid in pairs(positions) do
        if not Roster:Get(guid) then
            positions[guid] = nil
            changed = true
        end
    end
    if changed then
        Refresh()
    end
end

function Map:Enable()
    WorldMapFrame:AddDataProvider(provider)
    if WorldMapFrame:IsShown() then
        provider:RefreshAllData()
        self:StartWatching()
    end
end

function Map:Disable()
    self:StopWatching()
    WorldMapFrame:RemoveDataProvider(provider)
    positions, asked, peers = {}, {}, {}
end

-- The pin: a dot in the friend's class color, named in its tooltip with the
-- zone they're in. pins.xml mixes it into the template.
local PinMixin = CreateFromMixins(MapCanvasPinMixin)
Map.PinMixin = PinMixin

function PinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_GROUP_MEMBER")
    self:SetScalingLimits(1, 1.0, 1.2)
end

function PinMixin:OnAcquired(guid, mapID, x, y)
    self.guid = guid
    self.mapID = mapID
    self:SetPosition(x, y)
    local _, classFile = GetPlayerInfoByGUID(guid)
    local color = classFile and RAID_CLASS_COLORS[classFile]
    if color then
        self.Dot:SetVertexColor(color:GetRGB())
    else
        self.Dot:SetVertexColor(1, 1, 1)
    end
end

function PinMixin:OnMouseEnter()
    local _, classFile, _, _, _, name = GetPlayerInfoByGUID(self.guid)
    local color = classFile and RAID_CLASS_COLORS[classFile]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(name and color and color:WrapTextInColorCode(name) or name or "")
    local mapInfo = C_Map.GetMapInfo(self.mapID)
    if mapInfo then
        GameTooltip:AddLine(mapInfo.name, 1, 1, 1)
    end
    GameTooltip:Show()
end

function PinMixin:OnMouseLeave()
    GameTooltip:Hide()
end
