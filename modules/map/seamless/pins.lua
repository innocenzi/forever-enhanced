-- Icons on the seamless view, which covers Blizzard's map and its pins: the quests
-- of the log (all of them with "quests" on, else the one followed), the map pin, the
-- corpse, the group's members and map.friends' friends, where they are on the world,
-- as Blizzard's map draws them. On the view, not its canvas, so they keep their size as
-- it zooms. They take no mouse input (a drag starting on one still pans): the view
-- finds the one under the cursor for its tooltip and its clicks.
-- While the view shows (Pins:Show, Pins:Hide), what they show is gathered on events (the
-- quests, the map pin, the corpse) and on the view's tick (the group and friends, who
-- move), and only placed again as the view moves.

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")
local Geometry, Quests = Seamless.Geometry, Seamless.Quests

local Pins = {}
Seamless.Pins = Pins

-- How near the cursor (view pixels) an icon is under it.
local HOVER_RADIUS = 12
-- How far past the view's edges (view pixels) icons are still placed: they slide out under its edge.
local EDGE_MARGIN = 24
-- Frame levels over the view's icon level, in Blizzard's order (its pin frame levels).
local LEVELS = { quest = 0, followed = 1, waypoint = 2, friend = 3, member = 3, corpse = 4 }
-- A group member's dot (Blizzard's raid blips, in their class's colour): in a raid, one's own
-- subgroup dotted, the rest smaller (GroupMembersDataProvider's sizes). Friends as map.friends'.
local MEMBER_ATLAS = "WhiteCircle-RaidBlips"
local SUBGROUP_ATLAS = "WhiteDotCircle-RaidBlips"
local PARTY_SIZE, RAID_SIZE, FRIEND_SIZE = 11, 11 * 0.75, 12
-- Blizzard's corpse pin (CorpsePinTemplate, at its map scale).
local CORPSE_TEXTURE = "Interface\\Minimap\\POIIcons"
local CORPSE_SIZE = 24 * 0.8
-- Blizzard's quest marker for where the game sends the player next (POIButtonUtil.Style.Waypoint).
local TRAVEL_ATLAS = "poi-traveldirections-arrow"

local PARTY_UNITS, RAID_UNITS = {}, {}
for index = 1, MAX_PARTY_MEMBERS do
    PARTY_UNITS[index] = "party" .. index
end
for index = 1, MAX_RAID_MEMBERS do
    RAID_UNITS[index] = "raid" .. index
end

-- What's on the world, each { kind, u, v, style (a key: an icon showing another restyles), and
-- by kind: quest: questID, followed, travel (where the game sends the player next); waypoint:
-- tracked; member: unit, look (LookOf's); friend: guid, color }: `marks` gathered on events,
-- `group` on the view's tick.
local marks = {}
local group, groupCount = {}, 0
-- The icons in view, { frame (Blizzard's quest marker's textures: Quests:BuildMarker),
-- entry, x, y (from the view's middle, view pixels, y down), style, level }.
local icons, used = {}, 0
-- unit -> its dot's look, until the roster changes
local looks = {}
-- the entry under the cursor a click goes to (group members and friends let clicks through to
-- what's under them, as Blizzard's), what the tooltip shows, and the frame owning it
local clicked, hoverKey, tooltipOwner
-- the quest the quest log's hovered entry lights up
local logQuest
-- whether the view shows, and the frame the icons go on, at their frame level (Pins:Show)
local open = false
local parent, baseLevel

-- map.friends (its friends' positions and names: its public API).
local function Friends()
    return ns:GetFeature("map", "friends")
end

-- Styles ---------------------------------------------------------------------------------

local function ClassColor(class)
    return class and not issecretvalue(class) and RAID_CLASS_COLORS[class]
end

local function StyleDot(frame, atlas, size, color)
    frame.Background:SetAtlas(atlas)
    frame.Background:SetSize(size, size)
    if color then
        frame.Background:SetVertexColor(color:GetRGB())
    else
        frame.Background:SetVertexColor(1, 1, 1)
    end
    frame.Icon:Hide()
end

local STYLES = {
    quest = function(frame, entry)
        Quests:StyleMarker(frame, entry.questID, entry.followed)
        -- (where the game sends the player next: Blizzard's travel arrow)
        if entry.travel then
            frame.Icon:SetAtlas(TRAVEL_ATLAS)
            frame.Icon:SetSize(13, 17)
        end
    end,
    waypoint = function(frame, entry)
        frame.Background:SetAtlas(entry.tracked and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked", true)
        frame.Background:SetVertexColor(1, 1, 1)
        frame.Icon:Hide()
        frame.Highlight:SetAtlas("Waypoint-MapPin-Highlight", true)
    end,
    corpse = function(frame)
        frame.Background:SetTexture(CORPSE_TEXTURE)
        frame.Background:SetTexCoord(0.56640625, 0.6328125, 0.001953125, 0.03515625)
        frame.Background:SetSize(CORPSE_SIZE, CORPSE_SIZE)
        frame.Background:SetVertexColor(1, 1, 1)
        frame.Icon:Hide()
    end,
    member = function(frame, entry)
        local look = entry.look
        StyleDot(frame, look.atlas, look.size, look.color)
    end,
    friend = function(frame, entry)
        StyleDot(frame, MEMBER_ATLAS, FRIEND_SIZE, entry.color)
    end,
}

-- Placing --------------------------------------------------------------------------------

-- Lights up the quest under the cursor and the one the quest log's hovered entry
-- points at, and the map pin under the cursor.
local function UpdateHighlights()
    for index = 1, used do
        local icon = icons[index]
        local entry = icon.entry
        local lit
        -- (by what it is: the entry under the cursor may be gathered again since)
        if entry.kind == "quest" then
            lit = clicked and clicked.kind == "quest" and clicked.questID == entry.questID or entry.questID == logQuest
        elseif entry.kind == "waypoint" then
            lit = clicked and clicked.kind == "waypoint"
        end
        icon.frame.Highlight:SetShown(lit or false)
    end
end

local function Put(entry, x, y)
    used = used + 1
    local icon = icons[used]
    if not icon then
        icon = { frame = CreateFrame("Frame", nil, parent) }
        icon.frame:SetSize(1, 1)
        Quests:BuildMarker(icon.frame)
        icons[used] = icon
    end
    icon.entry, icon.x, icon.y = entry, x, y
    if icon.style ~= entry.style then
        icon.style = entry.style
        STYLES[entry.kind](icon.frame, entry)
    end
    local level = baseLevel + LEVELS[entry.followed and "followed" or entry.kind]
    if icon.level ~= level then
        icon.level = level
        icon.frame:SetFrameLevel(level)
    end
    icon.frame:SetPoint("CENTER", parent, "CENTER", x, -y)
    icon.frame:Show()
end

local function PutAll(list, count)
    -- (view.lua, loaded after this file)
    local View = Seamless.View
    for index = 1, count do
        local entry = list[index]
        local x, y = View:ToView(entry.u, entry.v, EDGE_MARGIN)
        if x then
            Put(entry, x, y)
        end
    end
end

-- Puts every icon where its entry is in view now (as the view moves).
function Pins:Place()
    used = 0
    if open then
        PutAll(marks, #marks)
        PutAll(group, groupCount)
    end
    for index = used + 1, #icons do
        icons[index].frame:Hide()
        icons[index].entry = nil
    end
    UpdateHighlights()
end

-- Gathering ------------------------------------------------------------------------------

local function AddMark(kind, u, v, style)
    local entry = { kind = kind, u = u, v = v, style = style }
    table.insert(marks, entry)
    return entry
end

local function AddQuest(questID, followed, travel, u, v)
    local style = ("quest:%d:%s:%s:%s"):format(
        questID,
        tostring(followed),
        tostring(C_QuestLog.IsComplete(questID)),
        tostring(travel)
    )
    local entry = AddMark("quest", u, v, style)
    entry.questID, entry.followed, entry.travel = questID, followed, travel
end

-- The quests (as Blizzard's map: its filter, and only the quests it would show), the map pin
-- and the corpse.
function Pins:Refresh()
    wipe(marks)
    if open then
        if Quests:AreShown() then
            local followed = C_SuperTrack.GetSuperTrackedQuestID()
            local seen = {}
            -- (the game places the log's quests on each continent: C_QuestLog.GetQuestsOnMap)
            for _, continent in ipairs(Geometry:Continents()) do
                for _, info in ipairs(C_QuestLog.GetQuestsOnMap(continent) or {}) do
                    local questID = info.questID
                    if
                        not seen[questID]
                        and (Seamless.db.quests or questID == followed)
                        and Quests:ShouldShow(info)
                    then
                        seen[questID] = true
                        AddQuest(questID, questID == followed, false, Geometry:ToWorld(continent, info.x, info.y))
                    end
                end
            end
            -- (the quest followed, placed nowhere itself: where the game sends the player next, as Blizzard's)
            if followed and followed ~= 0 and not seen[followed] and Quests:IsQuestShown(followed) then
                for _, continent in ipairs(Geometry:Continents()) do
                    local x, y = C_QuestLog.GetNextWaypointForMap(followed, continent)
                    if x and y then
                        AddQuest(followed, true, true, Geometry:ToWorld(continent, x, y))
                        break
                    end
                end
            end
        end
        local waypoint = C_Map.GetUserWaypoint()
        if waypoint and Geometry:Rect(waypoint.uiMapID) then
            local tracked = C_SuperTrack.IsSuperTrackingUserWaypoint()
            local u, v = Geometry:ToWorld(waypoint.uiMapID, waypoint.position.x, waypoint.position.y)
            AddMark("waypoint", u, v, "waypoint:" .. tostring(tracked)).tracked = tracked
        end
        for _, continent in ipairs(Geometry:Continents()) do
            local corpse = C_DeathInfo.GetCorpseMapPosition(continent)
            if corpse then
                local u, v = Geometry:ToWorld(continent, corpse:GetXY())
                AddMark("corpse", u, v, "corpse")
                break
            end
        end
    end
    -- (its tooltip again: the quest's progress)
    hoverKey = nil
    self:Place()
end

-- A group member's dot, until the roster changes (once their class can be read).
local function LookOf(unit)
    local look = looks[unit]
    if look then
        return look
    end
    local inRaid = IsInRaid()
    local own = inRaid and UnitInSubgroup(unit)
    local _, class = UnitClass(unit)
    local color = ClassColor(class)
    look = {
        atlas = own and SUBGROUP_ATLAS or MEMBER_ATLAS,
        size = (own or not inRaid) and PARTY_SIZE or RAID_SIZE,
        color = color,
    }
    look.style = ("member:%s:%s:%s"):format(look.atlas, look.size, color and class or "")
    if color then
        looks[unit] = look
    end
    return look
end

local function NextGroupEntry()
    groupCount = groupCount + 1
    local entry = group[groupCount]
    if not entry then
        entry = {}
        group[groupCount] = entry
    end
    return entry
end

-- Where `unit` is on the world, if the game says.
local function UnitOnWorld(unit)
    local mapID = C_Map.GetBestMapForUnit(unit)
    local position = mapID and Geometry:Rect(mapID) and C_Map.GetPlayerMapPosition(mapID, unit)
    if position and not issecretvalue(position.x) and not issecretvalue(position.y) then
        return Geometry:ToWorld(mapID, position.x, position.y)
    end
end

local function AddMember(unit)
    local u, v = UnitOnWorld(unit)
    if u then
        local entry = NextGroupEntry()
        local look = LookOf(unit)
        entry.kind, entry.u, entry.v, entry.unit, entry.guid = "member", u, v, unit, nil
        entry.look, entry.style, entry.color = look, look.style, nil
    end
end

local function AddFriend(guid, mapID, x, y)
    if Geometry:Rect(mapID) then
        local u, v = Geometry:ToWorld(mapID, x, y)
        local _, class = Friends():DescribeFriend(guid)
        local color = ClassColor(class)
        local entry = NextGroupEntry()
        entry.kind, entry.u, entry.v, entry.unit, entry.guid = "friend", u, v, nil, guid
        entry.look, entry.style, entry.color = nil, "friend:" .. (color and class or ""), color
    end
end

-- The group's members (but the player: the arrow) and friends, where they are now, unless
-- the game keeps it secret; and the quest log's hovered quest.
function Pins:UpdateGroup()
    groupCount = 0
    if open then
        if IsInRaid() then
            for index = 1, GetNumGroupMembers() do
                local unit = RAID_UNITS[index]
                if not UnitIsUnit(unit, "player") then
                    AddMember(unit)
                end
            end
        else
            for index = 1, GetNumSubgroupMembers() do
                AddMember(PARTY_UNITS[index])
            end
        end
        Friends():ForEachFriendPosition(AddFriend)
        logQuest = Quests:GetLogHighlight()
    end
    self:Place()
end

-- Hovering -------------------------------------------------------------------------------

local function Distance(icon, x, y)
    return (icon.x - x) ^ 2 + (icon.y - y) ^ 2
end

-- The icon under the cursor at (x, y) from the view's middle (view pixels, y down), if
-- any: the one on top, then the nearest (with `clickable`, not a group member's or friend's).
local function IconAt(x, y, clickable)
    if not x then
        return
    end
    local best, bestLevel, bestDistance
    for index = 1, used do
        local icon = icons[index]
        local kind = icon.entry.kind
        local distance = Distance(icon, x, y)
        if distance <= HOVER_RADIUS * HOVER_RADIUS and not (clickable and (kind == "member" or kind == "friend")) then
            if not best or icon.level > bestLevel or icon.level == bestLevel and distance < bestDistance then
                best, bestLevel, bestDistance = icon, icon.level, distance
            end
        end
    end
    return best
end

-- A unit's "First Surname": Forever's UnitName gives the surname apart.
local function FullName(unit)
    local name, surname = UnitName(unit)
    if name and not issecretvalue(name) and surname and not issecretvalue(surname) and surname ~= "" then
        return name .. " " .. surname
    end
    return name
end

-- A group member's or friend's name and class, unless the game keeps the name secret.
local function NameOf(entry)
    local name, class
    if entry.kind == "member" then
        name, class = FullName(entry.unit), select(2, UnitClass(entry.unit))
    else
        name, class = Friends():DescribeFriend(entry.guid)
    end
    if name and not issecretvalue(name) then
        return name, class
    end
end

local function ByName(a, b)
    return a.name < b.name
end

-- Every member and friend under the cursor, one per line in their class's colour (as
-- Blizzard's map, by name), or nil.
local function GroupNames(x, y)
    local found = {}
    for index = 1, used do
        local icon = icons[index]
        local kind = icon.entry.kind
        if (kind == "member" or kind == "friend") and Distance(icon, x, y) <= HOVER_RADIUS * HOVER_RADIUS then
            local name, class = NameOf(icon.entry)
            if name then
                table.insert(found, { name = name, color = ClassColor(class) })
            end
        end
    end
    if #found == 0 then
        return nil
    end
    table.sort(found, ByName)
    local lines = {}
    for index, member in ipairs(found) do
        lines[index] = member.color and member.color:WrapTextInColorCode(member.name) or member.name
    end
    return table.concat(lines, "\n")
end

local function ShowText(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 5, 2)
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

-- The cursor at (x, y) on the view (nil: off it): the tooltip of the icon under it.
function Pins:Hover(x, y)
    local icon = IconAt(x, y)
    local entry = icon and icon.entry
    local key, names
    if entry then
        if entry.kind == "quest" then
            key = "quest:" .. entry.questID
        elseif entry.kind == "member" or entry.kind == "friend" then
            names = GroupNames(x, y)
            key = names and "group:" .. names
        else
            key = entry.kind
        end
    end
    local target = IconAt(x, y, true)
    target = target and target.entry
    local changed = clicked ~= target
    clicked = target
    if changed then
        UpdateHighlights()
    end
    if key == hoverKey and (not key or tooltipOwner and GameTooltip:IsOwned(tooltipOwner)) then
        return
    end
    hoverKey = key
    local shown = false
    if entry and entry.kind == "quest" then
        shown = Quests:ShowTooltip(icon.frame, entry.questID)
    elseif entry and entry.kind == "waypoint" then
        -- (Blizzard's map pin's)
        GameTooltip:SetOwner(icon.frame, "ANCHOR_CURSOR_RIGHT", 5, 2)
        GameTooltip_SetTitle(GameTooltip, MAP_PIN_SHARING)
        GameTooltip_AddNormalLine(GameTooltip, MAP_PIN_SHARING_TOOLTIP)
        GameTooltip_AddColoredLine(GameTooltip, MAP_PIN_REMOVE, GREEN_FONT_COLOR)
        GameTooltip:Show()
        shown = true
    elseif entry and entry.kind == "corpse" then
        ShowText(icon.frame, CORPSE_RED)
        shown = true
    elseif names then
        ShowText(icon.frame, names)
        shown = true
    end
    if shown then
        tooltipOwner = icon.frame
    elseif tooltipOwner then
        -- (only ours: the cursor may have gone on to a frame that just showed its own)
        if GameTooltip:IsOwned(tooltipOwner) then
            GameTooltip:Hide()
        end
        tooltipOwner = nil
    end
end

-- Whether the cursor is over the map pin's icon.
function Pins:IsWaypointUnderCursor()
    return clicked ~= nil and clicked.kind == "waypoint"
end

-- The quest whose marker is under the cursor, if any, and where it is on the world.
function Pins:QuestUnderCursor()
    if clicked and clicked.kind == "quest" then
        return clicked.questID, clicked.u, clicked.v
    end
end

local function Refresh()
    Pins:Refresh()
end

local listener = ns:CreateEventListener({
    QUEST_LOG_UPDATE = Refresh,
    QUEST_POI_UPDATE = Refresh,
    USER_WAYPOINT_UPDATED = Refresh,
    SUPER_TRACKING_CHANGED = Refresh,
    PLAYER_DEAD = Refresh,
    PLAYER_ALIVE = Refresh,
    PLAYER_UNGHOST = Refresh,
    CVAR_UPDATE = function(_, name)
        if name and name:lower() == "questpoi" then
            Pins:Refresh()
        end
    end,
    GROUP_ROSTER_UPDATE = function()
        wipe(looks)
        Pins:UpdateGroup()
    end,
})

-- The view shows: icons on `frame`, from frame level `level` up, gathered while it shows.
function Pins:Show(frame, level)
    parent, baseLevel = frame, level
    open = true
    -- (the roster may have changed while it was hidden)
    wipe(looks)
    listener:Start()
    self:Refresh()
    self:UpdateGroup()
end

function Pins:Hide()
    open = false
    listener:Stop()
    wipe(marks)
    groupCount = 0
    self:Place()
    self:Hover(nil)
end
