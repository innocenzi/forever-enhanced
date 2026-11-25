-- The "share" part. Blizzard's map pin goes to chat as a link (Shift Click on
-- it): when the player sends one to group chat, an addon message carries it
-- to the group, and group members who run the addon are offered to follow it
-- (a dialog, like a group invite), or follow it at once ("autoAccept").
-- Following a pin places it and tracks it. In combat, the game refuses a pin
-- change from our code while Blizzard's map is open: an accepted pin waits
-- for the end of combat.
--
-- Messages start with the protocol version:
--   "1P:<mapID>:<x>:<y>"  a map pin, x and y in ten-thousandths, as in its link

local _, ns = ...

local Pin = ns:GetFeature("map", "pin")

local Sharing = {}
Pin.Sharing = Sharing

local PREFIX = "FEPin"
local VERSION = "1"
local DIALOG = "FOREVER_ENHANCED_SHARED_PIN"
-- Like a group invite.
local DIALOG_SECONDS = 60
local SCALE = 10000

-- Chat type of the message the link went in -> addon message channel.
local SEND_CHANNELS = {
    PARTY = "PARTY",
    RAID = "RAID",
    RAID_WARNING = "RAID",
    INSTANCE_CHAT = "INSTANCE_CHAT",
}

local RECEIVE_CHANNELS = {
    PARTY = true,
    RAID = true,
    INSTANCE_CHAT = true,
}

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

-- An accepted pin waiting for the end of combat: { mapID, x, y }.
local waiting
-- The chat hook stays once installed (hooks can't be removed).
local hooked = false

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
    StaticPopupDialogs[DIALOG].text = ns.L["map.pin.sharedPrompt"]
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

-- After the player sent a chat message: a map pin linked in group chat goes
-- to the group's addons too.
local function OnChatSent(text, chatType)
    if not Pin:IsPartActive("share") or ns:IsAnySecret(text, chatType) then
        return
    end
    local channel = SEND_CHANNELS[chatType]
    if not channel or not IsInGroup() then
        return
    end
    local mapID, x, y = text:match("|Hworldmap:(%d+):(%d+):(%d+)")
    if mapID then
        C_ChatInfo.SendAddonMessage(PREFIX, ("%sP:%s:%s:%s"):format(VERSION, mapID, x, y), channel)
    end
end

function Sharing:Enable()
    if not hooked then
        hooked = true
        ns:HookSecureFunc(C_ChatInfo, "SendChatMessage", OnChatSent)
    end
    listener:Start()
end

function Sharing:Disable()
    listener:Stop()
    waiting = nil
    StaticPopup_Hide(DIALOG)
end
