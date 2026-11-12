-- Fills the player's message template and sends it to the group.
--
-- Variables: {quest} (quest link), {objective} (objective text without its
-- counter), {current} and {total} (the counter). Any other {...} is left as
-- typed, so raid target icons like {rt1} still work.

local _, ns = ...

local Announce = ns:GetFeature("quests", "announce")

local Message = {}
Announce.Message = Message

-- The server refuses longer chat messages.
local MAX_BYTES = 255
-- Spaces, including the no-break space French puts before a colon.
local SPACE = "[%s\194\160]"
-- French uses the singular for 0 too.
local SINGULAR_ZERO = GetLocale() == "frFR"

-- Chat refuses the "|4singular:plural;" grammar code the objective text may
-- hold: pick the form for the number just before it, like the client does.
local function ResolveGrammar(text)
    return (
        text:gsub("(%d*)(" .. SPACE .. "*)|4([^:;]*):([^;]*);", function(number, space, singular, plural)
            local count = tonumber(number)
            local useSingular = count == 1 or (count == 0 and SINGULAR_ZERO)
            return number .. space .. (useSingular and singular or plural)
        end)
    )
end

-- "8/8 Kobold Vermin slain" or "Kobold Vermin slain: 8/8" -> "Kobold Vermin slain".
local function StripCounter(text)
    text = text:gsub("^" .. SPACE .. "*%d+/%d+" .. SPACE .. "+", "")
    text = text:gsub(SPACE .. "*:" .. SPACE .. "*%d+/%d+" .. SPACE .. "*$", "")
    return text
end

-- Cuts to MAX_BYTES without splitting a UTF-8 character.
local function Truncate(text)
    if #text <= MAX_BYTES then
        return text
    end
    local length = MAX_BYTES
    while length > 0 do
        local byte = text:byte(length + 1)
        -- 0x80-0xBF: a continuation byte, so the cut would split a character.
        if byte < 0x80 or byte > 0xBF then
            break
        end
        length = length - 1
    end
    return text:sub(1, length)
end

function Message:Format(template, values)
    return (template:gsub("{(%w+)}", values))
end

-- The message for a finished objective of a quest.
function Message:Build(questID, objective)
    local title = C_QuestLog.GetTitleForQuestID(questID) or ""
    local values = {
        quest = GetQuestLink(questID) or title,
        objective = StripCounter(ResolveGrammar(objective.text or "")),
        current = tostring(objective.numFulfilled),
        total = tostring(objective.numRequired),
    }
    local template = Announce:GetSetting("template")
    local message = self:Format(template, values)
    if #message > MAX_BYTES then
        -- A quest link is long; its title alone may fit.
        values.quest = title
        message = self:Format(template, values)
    end
    return Truncate(message)
end

-- Where the message goes: the instance group when allowed, else the party.
local function GetChannel()
    if Announce:GetSetting("channel") == "instance" and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "PARTY"
    end
end

function Message:Announce(questID, objective)
    local channel = GetChannel()
    if channel then
        C_ChatInfo.SendChatMessage(self:Build(questID, objective), channel)
    end
end
