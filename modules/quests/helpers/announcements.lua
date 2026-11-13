-- Hide quest addon announcements (the "hideAnnouncements" part): hides other
-- players' Questie and Polestar announcements in group chat, and their chat
-- bubbles.
--
-- Both addons start every group announcement with a fixed prefix:
-- "{rt1} Questie: " and "{rt1} Polestar: " ("{rt1} Questie : " from French
-- clients, "{звезда} Questie: " from Russian ones, and the same for Polestar).
-- A receiver who runs the addon too may see it already rewritten to the
-- addon's logo by the addon's own filter (Questie drops its name, Polestar
-- keeps it). Matching only at the start keeps ordinary chat that mentions
-- them. The player's own messages stay.
--
-- Chat filters don't reach chat bubbles: the client draws those itself. After
-- an announcement, the bubble showing its text is faded out until the client
-- reuses it for another message or keeps it hidden (it hides a bubble for a
-- moment while reusing it, so a short hide keeps it faded). Bubbles in
-- dungeons and raids are forbidden to addons, so those stay.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local AnnouncementFilter = {}
Helpers.AnnouncementFilter = AnnouncementFilter

local EVENTS = {
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local PATTERNS = {
    "^{rt1} Questie ?: ",
    "^{звезда} Questie ?: ",
    "^|TInterface\\Addons\\Questie\\Icons\\questie%.png:0|t ",
    "^{rt1} Polestar ?: ",
    "^{звезда} Polestar ?: ",
    "^|TInterface\\AddOns\\Polestar\\Media\\UI\\logo:0|t Polestar ?: ",
}

-- How long after an announcement its bubble may still show up.
local BUBBLE_WAIT_SECONDS = 1
-- How long a faded bubble may stay hidden and still be the same message: the
-- client hides a bubble for a moment after reusing it for a new message.
local HIDDEN_GRACE_SECONDS = 2

-- The announcement's text after the prefix, or nil for any other message.
local function GetAnnouncement(message)
    for _, pattern in ipairs(PATTERNS) do
        local _, finish = message:find(pattern)
        if finish then
            return message:sub(finish + 1)
        end
    end
    return nil
end

local function IsFromOtherPlayer(author)
    return Ambiguate(author, "none") ~= UnitName("player")
end

-- Chat filter: returning true hides the message.
local function HideAnnouncement(_, _, message, author)
    return GetAnnouncement(message) ~= nil and IsFromOtherPlayer(author)
end

-- Bubbles ---------------------------------------------------------------------

-- Text without color, link and texture codes, as bubbles and chat differ in
-- those: bubbles show a link as its bare name, without its brackets.
local function StripCodes(text)
    return (
        text:gsub("|H.-|h%[(.-)%]|h", "%1")
            :gsub("|H.-|h", "")
            :gsub("|h", "")
            :gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|r", "")
            :gsub("|T.-|t", "")
    )
end

-- Announcements whose bubble hasn't been found yet: { text, expires }.
local pending = {}
-- Faded bubbles: bubble frame -> { text (shown when faded), hiddenSince (when
-- the client hid it, nil while shown) }.
local fadedBubbles = setmetatable({}, { __mode = "k" })

local watcher = CreateFrame("Frame")
watcher:Hide()

-- The bubble's own frame (ChatBubbleTemplate), holding its text in .String.
local function GetBubbleContent(bubble)
    local content = bubble:GetChildren()
    return content and content.String and content
end

local function RestoreBubble(bubble)
    local content = GetBubbleContent(bubble)
    if content then
        content:SetAlpha(1)
    end
    fadedBubbles[bubble] = nil
end

local function FindPending(text)
    local plain = StripCodes(text)
    for index, announcement in ipairs(pending) do
        if plain:find(announcement.text, 1, true) then
            return index
        end
    end
    return nil
end

local function UpdateBubbles()
    local now = GetTime()
    for bubble, faded in pairs(fadedBubbles) do
        local content = GetBubbleContent(bubble)
        if not content or content.String:GetText() ~= faded.text then
            RestoreBubble(bubble)
        elseif bubble:IsShown() then
            faded.hiddenSince = nil
        elseif not faded.hiddenSince then
            faded.hiddenSince = now
        elseif now - faded.hiddenSince > HIDDEN_GRACE_SECONDS then
            RestoreBubble(bubble)
        end
    end

    for index = #pending, 1, -1 do
        if pending[index].expires < now then
            table.remove(pending, index)
        end
    end
    if #pending > 0 then
        for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles()) do
            local content = GetBubbleContent(bubble)
            if content and not fadedBubbles[bubble] and bubble:IsShown() then
                local text = content.String:GetText()
                local index = text and FindPending(text)
                if index then
                    table.remove(pending, index)
                    content:SetAlpha(0)
                    fadedBubbles[bubble] = { text = text }
                end
            end
        end
    end

    if #pending == 0 and next(fadedBubbles) == nil then
        watcher:Hide()
    end
end

watcher:SetScript("OnUpdate", UpdateBubbles)

local function OnGroupChat(_, message, author)
    local announcement = GetAnnouncement(message)
    if announcement and IsFromOtherPlayer(author) then
        table.insert(pending, { text = StripCodes(announcement), expires = GetTime() + BUBBLE_WAIT_SECONDS })
        watcher:Show()
    end
end

local handlers = {}
for _, event in ipairs(EVENTS) do
    handlers[event] = OnGroupChat
end
local listener = ns:CreateEventListener(handlers)

function AnnouncementFilter:Enable()
    for _, event in ipairs(EVENTS) do
        ChatFrameUtil.AddMessageEventFilter(event, HideAnnouncement)
    end
    listener:Start()
end

function AnnouncementFilter:Disable()
    for _, event in ipairs(EVENTS) do
        ChatFrameUtil.RemoveMessageEventFilter(event, HideAnnouncement)
    end
    listener:Stop()
    watcher:Hide()
    pending = {}
    for bubble in pairs(fadedBubbles) do
        RestoreBubble(bubble)
    end
end
