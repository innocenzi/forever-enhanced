-- Online friends who could run the addon, keyed by player GUID: character
-- friends, reached by whisper, and Battle.net friends playing this game, reached
-- by Battle.net game data (which also crosses realms and factions). A friend
-- who is both is reached over Battle.net. The list is rebuilt on the first
-- lookup after the friend lists change.

local _, ns = ...

local Friends = ns:GetFeature("map", "friends")

local Roster = {}
Friends.Roster = Roster

-- guid -> { guid, name = whisper target or nil, fullName = "Name-Realm" or nil, gameAccountID = number or nil }
local friends = {}
local dirty = true

local function FullName(name)
    if name:find("-", 1, true) then
        return name
    end
    return name .. "-" .. GetNormalizedRealmName()
end

local function Entry(list, guid)
    list[guid] = list[guid] or { guid = guid }
    return list[guid]
end

local function AddCharacterFriends(list)
    for index = 1, C_FriendList.GetNumFriends() do
        local info = C_FriendList.GetFriendInfoByIndex(index)
        if info and info.connected and info.guid then
            local entry = Entry(list, info.guid)
            entry.name = info.name
            entry.fullName = FullName(info.name)
        end
    end
end

local function AddBattleNetFriends(list)
    local playerGUID = UnitGUID("player")
    for friendIndex = 1, BNGetNumFriends() do
        for accountIndex = 1, C_BattleNet.GetFriendNumGameAccounts(friendIndex) do
            local account = C_BattleNet.GetFriendGameAccountInfo(friendIndex, accountIndex)
            if
                account
                and account.isOnline
                and account.clientProgram == BNET_CLIENT_WOW
                and account.wowProjectID == WOW_PROJECT_ID
                and account.playerGuid
                and account.playerGuid ~= playerGUID
            then
                Entry(list, account.playerGuid).gameAccountID = account.gameAccountID
            end
        end
    end
end

local function Rebuild()
    if not dirty then
        return
    end
    dirty = false
    friends = {}
    AddCharacterFriends(friends)
    AddBattleNetFriends(friends)
end

local function Changed()
    dirty = true
    Friends.Map:OnRosterChanged()
    Friends.OpenMap:OnRosterChanged()
end

local listener = ns:CreateEventListener({
    FRIENDLIST_UPDATE = Changed,
    BN_FRIEND_INFO_CHANGED = Changed,
    BN_CONNECTED = Changed,
    BN_DISCONNECTED = Changed,
})

-- The online friend with this GUID, or nil.
function Roster:Get(guid)
    Rebuild()
    return friends[guid]
end

-- Iterates guid, entry over online friends.
function Roster:Enumerate()
    Rebuild()
    return pairs(friends)
end

-- The GUID of the character friend whispering as `sender` ("Name-Realm"), or nil.
function Roster:FindBySender(sender)
    Rebuild()
    for guid, entry in pairs(friends) do
        if entry.fullName == sender then
            return guid
        end
    end
end

-- The GUID of the Battle.net friend playing on `gameAccountID`, or nil.
function Roster:FindByGameAccount(gameAccountID)
    Rebuild()
    for guid, entry in pairs(friends) do
        if entry.gameAccountID == gameAccountID then
            return guid
        end
    end
end

function Roster:Enable()
    dirty = true
    listener:Start()
end

function Roster:Disable()
    listener:Stop()
    friends = {}
    dirty = true
end
