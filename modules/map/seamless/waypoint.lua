-- Sharing the map pin. Shift Click on Blizzard's map pin puts its link in chat and
-- copies its /mappin command to the clipboard (CopyToClipboard, protected). Once the
-- stitched map has changed the map underneath, Blizzard's map pin code runs tainted: it
-- reads the map's mapID, written from our code (feature.lua), and the pool its pins come
-- from was made then, tainted for the session. The copy was an "action blocked" error.
-- So Shift Click on the map pin is ours: its link goes in chat as Blizzard's does,
-- without the copy. Global pin mouse handlers run before the pin's own click, and
-- Blizzard's placing and removing pins (priority 90) before ours.
--
-- Installed on the feature's first enable, for the rest of the session: the map stays
-- tainted until a /reload once the feature has touched it, turned off or not (feature.lua).

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")

local Waypoint = {}
Seamless.Waypoint = Waypoint

local PRIORITY = 10

local installed = false

local function OnPinMouseAction(map, mouseAction)
    if mouseAction ~= MapCanvasMixin.MouseAction.Click or not IsModifiedClick("CHATLINK") then
        return false
    end
    for pin in map:EnumeratePinsByTemplate("WaypointLocationPinTemplate") do
        if pin:IsMouseOver() then
            ChatFrameUtil.InsertLink(C_Map.GetUserWaypointHyperlink())
            PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE)
            return true
        end
    end
    return false
end

function Waypoint:Enable()
    if not installed then
        installed = true
        WorldMapFrame:AddGlobalPinMouseActionHandler(OnPinMouseAction, PRIORITY)
    end
end

-- Nothing: once installed, Shift Click on the map pin stays ours for the rest of the session.
function Waypoint:Disable() end
