-- The player's own ask for another layer, from Swap layer in the player
-- frame's menu or its key binding. A player changes layer by joining the group
-- of a player on another layer of the same zone, a host; LayerSwap's users
-- (and ours who host) invite whoever asks them.
--
-- 1. The click searches the zone's players (/who: only from a click or a key,
--    the game ignores an addon's search otherwise), one class at a time once
--    a search of the whole zone fills the list. Nameplates show for a moment
--    when the layer isn't known yet (reader.lua). Blizzard's who lists open
--    their window on any search's answer: those the player doesn't look at
--    don't hear ours.
-- 2. The ask is whispered to each player found (protocol.lua), the hosts that
--    answered the player before first, those asked lately in vain left out.
--    It waits up to LAYER_WAIT after the click for the layer, so hosts on the
--    player's own layer stay out.
-- 3. A host that can invite but hasn't read its layer is asked once more
--    without it (LayerSwap's hosts then read theirs and invite or say "same").
-- 4. The first invite from a player asked ends the burst, and is accepted
--    (the "accept" setting). Blizzard's invite dialog declines when hidden
--    before the group is joined, so it's hidden once in the group.
-- 5. In the host's group, the game moves the player (SHARD_TRANSFER) within a
--    few seconds: the group is left LEAVE_AFTER after joining, and the layer
--    read next is the outcome. Without a transfer in TRANSFER_WAIT, the host
--    stood on the player's layer: the group is left, and that host isn't
--    asked again for a while. Without an invite LAST_WAIT after the last ask,
--    the ask ends.
--
-- Progress shows as notices (asking, joining); every outcome goes to chat,
-- the new layer or why there's none (with how many players were asked and
-- answered). The game's "No player named ... is currently playing" for a
-- player asked who just logged off is hidden.

local _, ns = ...

local L = ns.L

local Layers = ns:GetFeature("map", "layers")
local Protocol = Layers.Protocol
local Comm = Layers.Comm
local Reader = Layers.Reader

local Swap = {}
Layers.Swap = Swap

local COOLDOWN = 10
local WHO_WAIT = 5
local LAYER_WAIT = 3
local ASK_SECONDS = 120
local WHO_LIST_CAP = 50
local MAX_NAMES = 49
-- The classes of Forever, searched one at a time once the zone fills a list.
local CLASS_IDS = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }
local ASKED_SECONDS = 15 * 60
local BOOK_SECONDS = 7 * 86400
local BOOK_MAX = 300
local REASK_DELAY = 1
-- How long an accepted invite may take to join the group.
local JOIN_WAIT = 10
local LEAVE_AFTER = 4
local TRANSFER_WAIT = 15
local RESULT_WAIT = 30
local AVOID_SECONDS = 600
local NOT_FOUND_SECONDS = 15
-- How long after the last ask an invite may still come (a host asked again
-- once it knows its layer included).
local LAST_WAIT = 15
-- How long a search's answer may still come: it goes to the who list event,
-- not to chat, until then.
local WHO_LATE = 30

-- The running ask: { at, zone, zoneName, from (the layer left), timers,
-- waitingWho, names (to ask), burstPending, sent (asks delivered), whispered,
-- replies, reasked (by key), inviter, accepted, joinedAt, transferAt, leaving,
-- result }.
local ask
local lastAskAt = -math.huge
-- 0: the whole zone; then the index in CLASS_IDS, once the zone fills a list.
local classRound = 0
local zoneFull = false
-- [whisper name] = GetTime() of the last ask.
local asked = {}
-- [key] = { layer, untilAt }: hosts that didn't move the player.
local avoided = {}
-- [key] = GetTime() of the last whisper, for the "not playing" line.
local sentTo = {}

local whoTimer
-- Blizzard's who lists that stopped hearing WHO_LIST_UPDATE for the search.
local muted = {}

-- The who lists that open their window on any search's answer: the group
-- finder's (LFGWhoListMixin:UpdateWhoList always), and the Friends frame's
-- while the social UI is off (WhoList_Update).
local function WhoLists()
    local lists = { FriendsFrame }
    if LFGWhoListFrame then
        table.insert(lists, LFGWhoListFrame)
    end
    return lists
end

-- Keeps the lists the player doesn't look at from opening on the answer.
local function MuteWhoLists()
    for _, list in ipairs(WhoLists()) do
        if not list:IsVisible() and list:IsEventRegistered("WHO_LIST_UPDATE") then
            list:UnregisterEvent("WHO_LIST_UPDATE")
            muted[list] = true
        end
    end
end

local function UnmuteWhoLists()
    for list in pairs(muted) do
        list:RegisterEvent("WHO_LIST_UPDATE")
    end
    muted = {}
end

-- The search's answer went to WHO_LIST_UPDATE (a small one would print in
-- chat otherwise), and the who lists didn't hear it: until it came, or can't
-- come anymore. The lists hear again the frame after, once it's been handled,
-- unless another search went out meanwhile.
local function ReleaseWho()
    if not whoTimer then
        return
    end
    whoTimer:Cancel()
    whoTimer = nil
    local shown = false
    for _, list in ipairs(WhoLists()) do
        shown = shown or list:IsVisible()
    end
    if not shown then
        C_FriendList.SetWhoToUi(false)
    end
    C_Timer.After(0, function()
        if not whoTimer then
            UnmuteWhoLists()
        end
    end)
end

local function SendWho(text, filters)
    ReleaseWho()
    UnmuteWhoLists()
    MuteWhoLists()
    C_FriendList.SetWhoToUi(true)
    whoTimer = C_Timer.NewTimer(WHO_LATE, ReleaseWho)
    C_FriendList.SendWho(text, Enum.SocialWhoOrigin.Social, filters)
end

local function Book()
    local store = Layers:GetAccountStore()
    store.book = store.book or {}
    return store.book
end

-- Keeps the players who answered an ask (whether they could invite), the
-- newest BOOK_MAX of the last BOOK_SECONDS.
local function PruneBook()
    local book = Book()
    local now = GetServerTime()
    local keys = {}
    for key, entry in pairs(book) do
        if now - entry.at > BOOK_SECONDS then
            book[key] = nil
        else
            table.insert(keys, key)
        end
    end
    if #keys > BOOK_MAX then
        table.sort(keys, function(a, b)
            return book[a].at > book[b].at
        end)
        for index = BOOK_MAX + 1, #keys do
            book[keys[index]] = nil
        end
    end
end

-- Forgets the asks and whispers too old to matter.
local function PruneAsked()
    local now = GetTime()
    for name, at in pairs(asked) do
        if now - at >= ASKED_SECONDS then
            asked[name] = nil
        end
    end
    for key, at in pairs(sentTo) do
        if now - at > NOT_FOUND_SECONDS then
            sentTo[key] = nil
        end
    end
    for key, entry in pairs(avoided) do
        if now > entry.untilAt then
            avoided[key] = nil
        end
    end
end

local function Later(a, seconds, callback)
    table.insert(
        a.timers,
        C_Timer.NewTimer(seconds, function()
            if ask == a then
                callback()
            end
        end)
    )
end

-- Ends the ask; `message`: its outcome, in chat.
local function Finish(message)
    local a = ask
    if not a then
        return
    end
    ask = nil
    for _, timer in ipairs(a.timers) do
        timer:Cancel()
    end
    Comm:Drop(a)
    if message then
        ns:Print(message)
    end
end

-- No invite came: how many players were asked, and how many answered.
local function NoHost(a)
    local answered = 0
    for _ in pairs(a.replies) do
        answered = answered + 1
    end
    Finish(L["map.layers.noHost"]:format(a.sent, answered))
end

local function IsAvoided(key)
    local entry = avoided[key]
    if not entry or GetTime() > entry.untilAt then
        return false
    end
    local current = Reader:GetCurrent()
    return current == nil or entry.layer == nil or Protocol:SameLayer(entry.layer, current)
end

-- The players to ask: the hosts of the book, then the zone's players, then
-- the others listed; without the player, hosts that didn't move the player,
-- and players asked lately who never answered.
local function Candidates(a, count)
    local me = Protocol:UnitKey("player")
    local book = Book()
    local hosts, here, others, listed = {}, {}, {}, {}
    for index = 1, count do
        local info = C_FriendList.GetWhoInfo(index)
        local name = info and info.fullName
        if name and not issecretvalue(name) and name ~= "" then
            local key = Protocol:SenderKey(name)
            local entry = book[key]
            if key ~= me and not listed[key] and not IsAvoided(key) and (entry or not asked[name]) then
                listed[key] = true
                if entry and entry.host then
                    table.insert(hosts, name)
                elseif info.area == a.zoneName then
                    table.insert(here, name)
                else
                    table.insert(others, name)
                end
            end
        end
    end
    local names = hosts
    for _, list in ipairs({ here, others }) do
        for _, name in ipairs(list) do
            table.insert(names, name)
        end
    end
    while #names > MAX_NAMES do
        table.remove(names)
    end
    return names
end

local function AskText(a)
    local x, y = Protocol:MapPosition(a.zone)
    return Protocol:EncodeAsk(a.zone, Reader:GetCurrent(), x, y)
end

local function StartBurst(a)
    a.burstPending = false
    ns:Warning(L["map.layers.askingCount"]:format(#a.names))
    local done = 0
    local function OnSent(target, delivered)
        if delivered then
            asked[target] = GetTime()
            local key = Protocol:SenderKey(target)
            a.whispered[key] = true
            sentTo[key] = GetTime()
            a.sent = a.sent + 1
        end
        done = done + 1
        if done == #a.names then
            Later(a, LAST_WAIT, function()
                if not a.inviter then
                    NoHost(a)
                end
            end)
        end
    end
    for _, name in ipairs(a.names) do
        Comm:Send(name, function()
            return AskText(a)
        end, a, OnSent)
    end
end

local function Leave(a)
    a.leaving = true
    if IsInGroup() then
        C_PartyInfo.LeaveParty()
    end
    if a.result then
        Finish()
    end
end

local function NotMoved(a)
    avoided[a.inviter] = { layer = Reader:GetCurrent() or a.from, untilAt = GetTime() + AVOID_SECONDS }
    Leave(a)
    Finish(L["map.layers.sameLayer"]:format(a.inviter))
end

local function Request()
    if IsInInstance() then
        ns:Error(L["map.layers.instance"])
        return
    end
    if IsInGroup() then
        ns:Error(L["map.layers.inGroup"])
        return
    end
    if UnitOnTaxi("player") then
        ns:Error(L["map.layers.flying"])
        return
    end
    local zone = Protocol:ZoneMap()
    if not zone then
        ns:Error(L["map.layers.instance"])
        return
    end
    if GetTime() - lastAskAt < COOLDOWN then
        ns:Error(L["map.layers.cooldown"])
        return
    end
    lastAskAt = GetTime()
    PruneAsked()

    local a = {
        at = GetTime(),
        zone = zone,
        zoneName = C_Map.GetMapInfo(zone).name,
        from = Reader:GetCurrent(),
        timers = {},
        whispered = {},
        replies = {},
        reasked = {},
        sent = 0,
        waitingWho = true,
    }
    ask = a
    -- The whole zone once the classes are done or while it fits in a list.
    if classRound > 0 or zoneFull then
        classRound = (classRound + 1) % (#CLASS_IDS + 1)
    end
    SendWho(WHO_TAG_ZONE .. '"' .. a.zoneName .. '"', {
        uiMapIDs = { zone },
        classIDs = classRound > 0 and { CLASS_IDS[classRound] } or {},
        raceIDs = {},
    })
    Reader:Flash()
    Later(a, WHO_WAIT, function()
        if a.waitingWho then
            Finish(L["map.layers.noAnswer"])
        end
    end)
    Later(a, ASK_SECONDS, function()
        if a.joinedAt then
            return
        elseif a.inviter then
            -- Invited, but the invite wasn't accepted.
            Finish(L["map.layers.canceled"])
        else
            NoHost(a)
        end
    end)
    ns:Warning(L["map.layers.asking"])
end

-- Whether an ask waits for an invite.
function Swap:IsAsking()
    return ask ~= nil and not ask.joinedAt
end

-- Swap layer, or Cancel layer swap while an ask waits. From a click or a key only.
function Swap:Toggle()
    if not Layers:IsActive() or Layers:StandsDown() then
        return
    end
    if ask then
        if not ask.joinedAt then
            Finish()
        end
        return
    end
    Request()
end

-- A whisper that isn't an ask: a host's reply.
function Swap:OnReply(text, sender)
    local reply = Protocol:ParseReply(text)
    if not reply or (reply.kind == "heard" and reply.asker ~= Protocol:UnitKey("player")) then
        return
    end
    local key = Protocol:SenderKey(sender)
    Book()[key] = { at = GetServerTime(), host = reply.kind == "same" or reply.canInvite }
    local a = ask
    if not a then
        return
    end
    a.replies[key] = true
    if a.inviter or reply.kind ~= "heard" then
        return
    end
    if reply.canInvite and not reply.layer and reply.zone == tostring(a.zone) and not a.reasked[key] then
        a.reasked[key] = true
        Later(a, REASK_DELAY, function()
            if not a.inviter then
                local x, y = Protocol:MapPosition(a.zone)
                Comm:Send(sender, Protocol:EncodeAsk(a.zone, nil, x, y), a)
            end
        end)
    end
end

function Swap:OnLayerRead(layer)
    local a = ask
    if not a then
        return
    end
    if not a.joinedAt then
        -- Read after the click, or corrected: the layer the player leaves.
        a.from = layer
        if a.burstPending then
            StartBurst(a)
        end
        return
    end
    if a.transferAt and not a.result then
        a.result = true
        local letter = Reader:GetLetter()
        if a.from and Protocol:SameLayer(layer, a.from) then
            ns:Print(L["map.layers.notMoved"])
        elseif letter then
            ns:Print(L["map.layers.moved"]:format(letter))
        else
            ns:Print(L["map.layers.changed"])
        end
        if a.leaving then
            Finish()
        end
    end
end

function Swap:OnTransfer()
    local a = ask
    if not a or not a.joinedAt or a.transferAt then
        return
    end
    a.transferAt = GetTime()
    Later(a, math.max(0, a.joinedAt + LEAVE_AFTER - GetTime()), function()
        Leave(a)
    end)
    Later(a, RESULT_WAIT, function()
        Finish(not a.result and L["map.layers.changed"] or nil)
    end)
end

local listener = ns:CreateEventListener({
    WHO_LIST_UPDATE = function()
        ReleaseWho()
        local a = ask
        if not a or not a.waitingWho then
            return
        end
        a.waitingWho = false
        local count = C_FriendList.GetNumWhoResults()
        if classRound == 0 then
            zoneFull = count >= WHO_LIST_CAP
        end
        a.names = Candidates(a, count)
        if #a.names == 0 then
            Finish(L["map.layers.nobody"])
            return
        end
        local wait = Reader:GetCurrent() and 0 or a.at + LAYER_WAIT - GetTime()
        if wait > 0 then
            a.burstPending = true
            Later(a, wait, function()
                if a.burstPending then
                    StartBurst(a)
                end
            end)
        else
            StartBurst(a)
        end
    end,
    PARTY_INVITE_REQUEST = function(_, name)
        local a = ask
        if not a or a.joinedAt or issecretvalue(name) then
            return
        end
        local key = Protocol:SenderKey(name)
        if not a.whispered[key] then
            return
        end
        a.inviter = key
        if Layers:GetSetting("accept") then
            Comm:Drop(a)
            a.accepted = true
            AcceptGroup()
            ns:Warning(L["map.layers.invited"]:format(key))
            Later(a, JOIN_WAIT, function()
                if not a.joinedAt then
                    Finish(L["map.layers.canceled"])
                end
            end)
        end
    end,
    GROUP_JOINED = function()
        local a = ask
        if not a or a.joinedAt then
            return
        end
        if not a.inviter then
            Finish(L["map.layers.canceled"])
            return
        end
        a.joinedAt = GetTime()
        Comm:Drop(a)
        if a.accepted then
            StaticPopup_Hide("PARTY_INVITE")
        end
        Later(a, TRANSFER_WAIT, function()
            if not a.transferAt then
                NotMoved(a)
            end
        end)
    end,
    GROUP_LEFT = function()
        local a = ask
        if a and a.joinedAt and not a.leaving then
            -- Left by the player or the host: the outcome still shows after a transfer.
            if a.transferAt then
                a.leaving = true
            else
                Finish(L["map.layers.leftGroup"])
            end
        end
    end,
    ZONE_CHANGED_NEW_AREA = function()
        zoneFull, classRound = false, 0
        if ask and not ask.joinedAt then
            Finish(L["map.layers.canceled"])
        end
    end,
})

local notFoundPattern

-- Hides "No player named '<name>' is currently playing." for a player asked moments ago.
local function HideNotFound(_, _, message)
    if issecretvalue(message) then
        return false
    end
    notFoundPattern = notFoundPattern
        or "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)") .. "$"
    local name = message:match(notFoundPattern)
    local at = name and sentTo[Protocol:SenderKey(name)]
    return at ~= nil and GetTime() - at <= NOT_FOUND_SECONDS
end

function Swap:Enable()
    PruneBook()
    listener:Start()
    ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", HideNotFound)
end

function Swap:Disable()
    listener:Stop()
    ChatFrameUtil.RemoveMessageEventFilter("CHAT_MSG_SYSTEM", HideNotFound)
    ReleaseWho()
    UnmuteWhoLists()
    Finish()
end
