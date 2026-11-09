-- Hides other players' Questie announcements in group chat.
--
-- Questie starts every group announcement with a fixed prefix: "{rt1} Questie: "
-- ("{rt1} Questie : " from French clients, "{звезда} Questie: " from Russian
-- ones). A receiver who runs Questie too may see it already rewritten to
-- Questie's logo by Questie's own filter. Matching only at the start keeps
-- ordinary chat that mentions Questie. The player's own messages stay.

local _, ns = ...

local Announce = ns:GetFeature("quests", "announce")

local QuestieFilter = {}
Announce.QuestieFilter = QuestieFilter

local enabled = false

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

local function IsQuestieAnnouncement(message)
    for _, pattern in ipairs(PATTERNS) do
        if message:find(pattern) then
            return true
        end
    end
    return false
end

-- Chat filter: returning true hides the message.
local function HideQuestieAnnouncement(_, _, message, author)
    return IsQuestieAnnouncement(message) and Ambiguate(author, "none") ~= UnitName("player")
end

-- Adds or removes the chat filter, once.
function QuestieFilter:SetEnabled(enable)
    if enable == enabled then
        return
    end
    enabled = enable
    for _, event in ipairs(EVENTS) do
        if enable then
            ChatFrameUtil.AddMessageEventFilter(event, HideQuestieAnnouncement)
        else
            ChatFrameUtil.RemoveMessageEventFilter(event, HideQuestieAnnouncement)
        end
    end
end
