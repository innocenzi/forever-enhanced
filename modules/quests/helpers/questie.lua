-- Hide Questie announcements (the "hideQuestie" part): hides other players'
-- Questie announcements in group chat, and their chat bubbles.
--
-- Questie starts every group announcement with a fixed prefix: "{rt1} Questie: "
-- ("{rt1} Questie : " from French clients, "{звезда} Questie: " from Russian
-- ones). A receiver who runs Questie too may see it already rewritten to
-- Questie's logo by Questie's own filter. Matching only at the start keeps
-- ordinary chat that mentions Questie. The player's own messages stay.
--
-- Chat filters don't reach chat bubbles: the client draws those itself. After
-- an announcement, the bubble showing its text is faded out until the client
-- hides it or reuses it for another message. Bubbles in dungeons and raids are
-- forbidden to addons, so those stay.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local QuestieFilter = {}
Helpers.QuestieFilter = QuestieFilter

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
}

-- How long after an announcement its bubble may still show up.
local BUBBLE_WAIT_SECONDS = 1

-- The announcement's text after the prefix, or nil for any other message.
local function GetQuestieAnnouncement(message)
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
local function HideQuestieAnnouncement(_, _, message, author)
    return GetQuestieAnnouncement(message) ~= nil and IsFromOtherPlayer(author)
end

-- Bubbles ---------------------------------------------------------------------

-- Text without color, link and texture codes, as bubbles and chat may differ in those.
local function StripCodes(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", ""))
end

-- Announcements whose bubble hasn't been found yet: { text, expires }.
local pending = {}
-- Faded bubbles: bubble frame -> the text it showed when faded.
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
    for bubble, text in pairs(fadedBubbles) do
        local content = GetBubbleContent(bubble)
        if not bubble:IsShown() or not content or content.String:GetText() ~= text then
            RestoreBubble(bubble)
        end
    end

    local now = GetTime()
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
                    fadedBubbles[bubble] = text
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
    local announcement = GetQuestieAnnouncement(message)
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

function QuestieFilter:Enable()
    for _, event in ipairs(EVENTS) do
        ChatFrameUtil.AddMessageEventFilter(event, HideQuestieAnnouncement)
    end
    listener:Start()
end

function QuestieFilter:Disable()
    for _, event in ipairs(EVENTS) do
        ChatFrameUtil.RemoveMessageEventFilter(event, HideQuestieAnnouncement)
    end
    listener:Stop()
    watcher:Hide()
    pending = {}
    for bubble in pairs(fadedBubbles) do
        RestoreBubble(bubble)
    end
end
