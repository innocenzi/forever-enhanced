-- The "share" part. Alt Click on the map pin, on Blizzard's map (mapbutton.lua)
-- or the seamless view (map.seamless, through Pin:Share), sends it to the
-- group in an addon message, nothing in chat; group members who run the addon
-- are offered to follow it (a dialog, like a group invite), or follow it at
-- once ("autoAccept"). The pin's tooltip says so while the player is in a group.
-- Following a pin places it and tracks it. In combat, the game refuses a pin
-- change from our code while Blizzard's map is open: an accepted pin waits
-- for the end of combat.
--
-- Messages start with the protocol version:
--   "1P:<mapID>:<x>:<y>"  a map pin, x and y in ten-thousandths, as in its link

local _, ns = ...

local L = ns.L
local Pin = ns:GetFeature("map", "pin")

local Sharing = {}
Pin.Sharing = Sharing

local PREFIX = "FEPin"
local VERSION = "1"
local DIALOG = "FOREVER_ENHANCED_SHARED_PIN"
-- Like a group invite.
local DIALOG_SECONDS = 60
local SCALE = 10000

local RECEIVE_CHANNELS = {
    PARTY = true,
    RAID = true,
    INSTANCE_CHAT = true,
}

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- An accepted pin waiting for the end of combat: { mapID, x, y }.
local waiting

local function Follow(mapID, x, y)
    if InCombatLockdown() then
        waiting = { mapID = mapID, x = x, y = y }
        return
    end
    waiting = nil
    Pin:Place(mapID, x, y, true)
end

StaticPopupDialogs[DIALOG] = {
    button1 = ACCEPT,
    button2 = DECLINE,
    OnAccept = function(_, data)
        Follow(data.mapID, data.x, data.y)
    end,
    hideOnEscape = 1,
    timeout = DIALOG_SECONDS,
    whileDead = 1,
}

local function Offer(sender, mapID, x, y)
    if Pin:GetSetting("autoAccept") then
        Follow(mapID, x, y)
        return
    end
    local info = C_Map.GetMapInfo(mapID)
    StaticPopupDialogs[DIALOG].text = L["map.pin.sharedPrompt"]
    StaticPopup_Show(DIALOG, Ambiguate(sender, "none"), info and info.name or "", { mapID = mapID, x = x, y = y })
end

-- mapID, x, y (normalized) of a map pin message, or nil.
local function ParseMessage(text)
    local mapID, x, y = text:match("^" .. VERSION .. "P:(%d+):(%d+):(%d+)$")
    if not mapID then
        return nil
    end
    x, y = tonumber(x) / SCALE, tonumber(y) / SCALE
    if x > 1 or y > 1 then
        return nil
    end
    return tonumber(mapID), x, y
end

local listener = ns:CreateEventListener({
    CHAT_MSG_ADDON = function(_, prefix, text, chatType, sender)
        if ns:IsAnySecret(prefix, text, chatType, sender) then
            return
        end
        if prefix ~= PREFIX or not RECEIVE_CHANNELS[chatType] then
            return
        end
        if ns:IsFromPlayer(sender) then
            return
        end
        local mapID, x, y = ParseMessage(text)
        if mapID and C_Map.CanSetUserWaypointOnMap(mapID) then
            Offer(sender, mapID, x, y)
        end
    end,
    PLAYER_REGEN_ENABLED = function()
        if waiting then
            Follow(waiting.mapID, waiting.x, waiting.y)
        end
    end,
})

-- The addon message channel of the player's group, or nil outside one.
local function GetGroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

-- Whether Alt Click on the map pin shares it: the player has one, and a group.
function Pin:CanShare()
    return self:IsPartActive("share") and C_Map.HasUserWaypoint() and GetGroupChannel() ~= nil
end

-- Alt Click on the map pin: sent to the group's addons.
function Pin:Share()
    if not self:CanShare() then
        return
    end
    local point = C_Map.GetUserWaypoint()
    local x = math.floor(point.position.x * SCALE + 0.5)
    local y = math.floor(point.position.y * SCALE + 0.5)
    local message = ("%sP:%d:%d:%d"):format(VERSION, point.uiMapID, x, y)
    local result = C_ChatInfo.SendAddonMessage(PREFIX, message, GetGroupChannel())
    if result ~= Enum.SendAddonMessageResult.Success then
        ns:Error(L["map.pin.shareFailed"])
        return
    end
    PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE)
    ns:Print(L["map.pin.shared"])
end

-- The map pin's tooltip: how to share it, while Alt Click would.
function Pin:AddShareHint(tooltip)
    if self:CanShare() then
        GameTooltip_AddColoredLine(tooltip, L["map.pin.shareHint"], GREEN_FONT_COLOR)
    end
end

function Sharing:Enable()
    Pin.MapButton:Enable()
    listener:Start()
end

function Sharing:Disable()
    Pin.MapButton:Disable()
    listener:Stop()
    waiting = nil
    StaticPopup_Hide(DIALOG)
end
