-- What the palette lists for each command (ns:AddCommand, core/commands.lua),
-- matching typed text against it, and its order.
--
-- A command's title is the game's own name, in the client's language, for a
-- binding (its name in the Key Bindings) and a spell (the one its function
-- gave, a profession's, else the spell's), the one an `each` value gave,
-- its key's string otherwise (<module>.<feature>.commands.<id>). Its
-- aliases, found in every language: its English name, the enUS string of its
-- key (for a command the game names, written in enUS only: never shown), and
-- the space-separated words of <...>.commands.<id>.keywords, in English and
-- in the player's language (an `each` value's: its command's).
--
-- Text is compared folded: lower case, accents dropped ("reputation" finds
-- "Réputation"). From the best match to the worst: the title starts with the
-- text; each typed word starts a word of the title, in any order ("map
-- world"); the title holds the text; its letters come in order in the title,
-- from the start of one of its words ("chr" finds "Character", "map" doesn't
-- find "compteur d'images par seconde"). Aliases (the English name, keywords)
-- count too, just below the title, letters in order aside. Ties go to the
-- most recently run, then to the commands' order.

local _, ns = ...

local Palette = ns:GetFeature("interface", "palette")

local Search = {}
Palette.Search = Search

-- UTF-8 Latin-1 letters, U+00C0 to U+00FF (0xC3 then 0x80 to 0xBF), folded:
-- the letter at their second byte's offset from 0x80, or LATIN1_SPECIAL's.
local LATIN1 = "aaaaaa?ceeeeiiiidnooooo?ouuuuy??aaaaaa?ceeeeiiiidnooooo?ouuuuy?y"
local LATIN1_SPECIAL = { [6] = "ae", [23] = "x", [30] = "th", [31] = "ss", [38] = "ae", [55] = "/", [62] = "th" }
local FOLDED = {}
for offset = 0, #LATIN1 - 1 do
    FOLDED["\195" .. string.char(0x80 + offset)] = LATIN1_SPECIAL[offset] or LATIN1:sub(offset + 1, offset + 1)
end
FOLDED["\197\146"] = "oe" -- Œ
FOLDED["\197\147"] = "oe" -- œ
local APOSTROPHE = "\226\128\153" -- ’

local MATCH = { prefix = 4, words = 3, substring = 2, letters = 1 }
-- Aliases rank a match just below the same match on the title.
local ALIAS_PENALTY = 0.5

local function GetTitle(command)
    if command.binding then
        return GetBindingName(command.binding)
    elseif command.spellID then
        return command.title or C_Spell.GetSpellName(command.spellID) or ns.L[command.key]
    end
    return command.title or ns.L[command.key]
end

local function GetAliases(command)
    local candidates = {
        ns:GetLocaleString("enUS", command.strings),
        ns:GetLocaleString("enUS", command.strings .. ".keywords"),
        rawget(ns.L, command.strings .. ".keywords"),
    }
    local aliases, seen = {}, {}
    for index = 1, 3 do
        local alias = candidates[index]
        if alias and not seen[alias] then
            seen[alias] = true
            table.insert(aliases, alias)
        end
    end
    return aliases
end

-- The commands offered right now (ns:GetCommands), as entries: { key, title,
-- aliases, order, command }.
function Search:GetEntries()
    local entries = {}
    for _, command in ipairs(ns:GetCommands()) do
        table.insert(entries, {
            key = command.key,
            title = GetTitle(command),
            aliases = GetAliases(command),
            order = command.order,
            command = command,
        })
    end
    return entries
end

-- Lower case, accents dropped, spaces collapsed.
function Search:Fold(text)
    text = text:gsub(APOSTROPHE, "'")
    text = text:gsub("[\195\197][\128-\191]", FOLDED):lower()
    return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function Words(text)
    local words = {}
    for word in text:gmatch("[^%s%p]+") do
        table.insert(words, word)
    end
    return words
end

-- Whether each of `queryWords` starts one of `words`, each word used once.
local function WordsMatch(queryWords, words)
    local used = {}
    for _, queryWord in ipairs(queryWords) do
        local found = false
        for index, word in ipairs(words) do
            if not used[index] and word:sub(1, #queryWord) == queryWord then
                used[index] = true
                found = true
                break
            end
        end
        if not found then
            return false
        end
    end
    return true
end

-- Whether the letters of `query` come in order in `text` from `position` on.
local function LettersFrom(query, text, position)
    for char in query:gsub(" ", ""):gmatch(".") do
        position = text:find(char, position, true)
        if not position then
            return false
        end
        position = position + 1
    end
    return true
end

-- Whether the letters of `query` come in order in `text`, from a word's start.
local function LettersMatch(query, text)
    local first = query:gsub(" ", ""):sub(1, 1)
    for start, initial in text:gmatch("()([^%s%p])[^%s%p]*") do
        if initial == first and LettersFrom(query, text, start) then
            return true
        end
    end
    return false
end

-- How well folded `query` matches folded `text`: a MATCH value, or 0.
local function Score(query, text, withLetters)
    if text:sub(1, #query) == query then
        return MATCH.prefix
    end
    local queryWords = Words(query)
    if #queryWords > 0 and WordsMatch(queryWords, Words(text)) then
        return MATCH.words
    end
    if text:find(query, 1, true) then
        return MATCH.substring
    end
    if withLetters and LettersMatch(query, text) then
        return MATCH.letters
    end
    return 0
end

-- How well typed `text` matches the entry ({ title, aliases }): 0 for no match.
function Search:Score(entry, text)
    local query = self:Fold(text)
    if query == "" then
        return 0
    end
    local score = Score(query, self:Fold(entry.title), true)
    for _, alias in ipairs(entry.aliases or {}) do
        score = math.max(score, Score(query, self:Fold(alias), false) - ALIAS_PENALTY)
    end
    return score
end

-- The entries ({ key, title, aliases, order }) matching `text`, best first;
-- lastRun[key]: how recently each was run (higher: more recently). With no
-- text: all of them, the recently run first.
function Search:Rank(entries, text, lastRun)
    local empty = self:Fold(text) == ""
    local ranked, scores = {}, {}
    for _, entry in ipairs(entries) do
        local score = empty and 0 or self:Score(entry, text)
        if empty or score > 0 then
            scores[entry] = score
            table.insert(ranked, entry)
        end
    end
    table.sort(ranked, function(a, b)
        if scores[a] ~= scores[b] then
            return scores[a] > scores[b]
        end
        local aRun, bRun = lastRun[a.key] or 0, lastRun[b.key] or 0
        if aRun ~= bRun then
            return aRun > bRun
        end
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.key < b.key
    end)
    return ranked
end
