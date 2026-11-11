-- Online friends who could run the addon, keyed by player GUID: character
-- friends, reached by whisper, and Battle.net friends playing this game, reached
-- by Battle.net game data (which also crosses realms and factions). A friend
-- who is both is reached over Battle.net. The list is rebuilt on the first
-- lookup after the friend lists change.

local _, ns = ...

local Friends = ns:GetFeature("map", "friends")

local Roster = {}
Friends.Roster = Roster

-- guid -> { guid, name = whisper target or nil, fullName = "Name-Realm" or nil, gameAccountID = number or nil,
--          displayName = character name or nil, classFile = "WARRIOR" or nil }
local friends = {}
local dirty = true
-- localized class name (male and female forms) -> class file, built on first use
local classFiles

local function FullName(name)
    if name:find("-", 1, true) then
        return name
    end
    return name .. "-" .. GetNormalizedRealmName()
end

-- The class file for a localized class name, which is all the friend list gives.
local function ClassFile(className)
    if not className then
        return nil
    end
    if not classFiles then
        classFiles = {}
        for _, isFemale in ipairs({ false, true }) do
            for classFile, name in pairs(LocalizedClassList(isFemale)) do
                classFiles[name] = classFile
            end
        end
    end
    return classFiles[className]
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
            entry.displayName = info.name
            entry.classFile = ClassFile(info.className)
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
                local entry = Entry(list, account.playerGuid)
                entry.gameAccountID = account.gameAccountID
                entry.displayName = entry.displayName or account.characterName
                entry.classFile = entry.classFile or account.classFilename
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

-- The name and class file of the friend `guid`, either of which may be nil:
-- from the client's cache of players met this session, else from the friend
-- lists (a friend never met nearby isn't cached).
function Roster:Describe(guid)
    local _, classFile, _, _, _, name = GetPlayerInfoByGUID(guid)
    local entry = self:Get(guid)
    if entry then
        name = name or entry.displayName
        classFile = classFile or entry.classFile
    end
    return name, classFile
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
