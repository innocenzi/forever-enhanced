-- Commands: what the command palette (interface.palette) offers, registered
-- by any feature at file load and offered only while that feature (or part)
-- is active.
--
-- A command does one of four things, run from the palette's Enter key press:
--   binding = command  runs a key binding ("TOGGLECHARACTER0", or one of our
--                      Bindings.xml): Enter passes through to it, so the game
--                      runs it from the key press, untainted. The way to open
--                      Blizzard's windows.
--   click = name       clicks a named button the same way (a secure button of
--                      ours, a micro button).
--   spell = spellID    casts the spell the same way, through the palette's
--                      secure button (a profession's, to open its window). A
--                      function returns the spell to cast now (nil hides the
--                      command) and, when the spell's name isn't the right
--                      one, the game's own name for the command, in the
--                      client's language (a profession's, its spell being
--                      another's).
--   run = function     our own code, for our own windows only: Blizzard's
--                      would run tainted.
-- With `each = function`, a run command is offered once per value that
-- function returns now, a list of { id, title, ... }: run(value) is its code,
-- title (in the player's language) its title, and <key>.<id> its own key
-- (id: unique among them, the same from one session to the next), e.g. one
-- per addon settings page.
-- Its strings, under its key <module>.<feature>.commands.<id>, are the
-- palette's (titles and search words: interface/palette/search.lua).

local _, ns = ...

local commands = {}
local keys = {}

local ACTIONS = { "binding", "click", "spell", "run" }

-- command: { id, binding | click | spell | run, each, order, part,
-- IsAvailable }. id is unique within the feature; order (spaced by tens)
-- sorts the palette's empty list and breaks ties; part: the toggle key of the
-- part the command belongs to; IsAvailable(): true while it's offered
-- (unset: always), e.g. only in a guild.
function ns:AddCommand(feature, command)
    local actions = 0
    for _, action in ipairs(ACTIONS) do
        actions = actions + (command[action] and 1 or 0)
    end
    assert(actions == 1, "a command needs exactly one of binding, click, spell and run: " .. tostring(command.id))
    assert(not command.each or command.run, "a command with each needs run: " .. tostring(command.id))
    local key = feature:GetLocaleKey("commands." .. assert(command.id, "a command needs an id"))
    assert(not keys[key], "command already registered: " .. key)
    keys[key] = true
    table.insert(commands, {
        feature = feature,
        key = key,
        binding = command.binding,
        click = command.click,
        spell = command.spell,
        run = command.run,
        each = command.each,
        order = command.order or math.huge,
        part = command.part,
        IsAvailable = command.IsAvailable,
    })
end

-- The spell a command casts now and its name from the game, if it has one.
-- An error is reported, and hides the command.
local function ResolveSpell(command)
    if type(command.spell) == "function" then
        return securecallfunction(command.spell)
    end
    return command.spell
end

-- Adds one record per value of a command with each, sharing its strings.
local function OfferEach(command, offered)
    -- An error is reported, and offers none.
    for _, value in ipairs(securecallfunction(command.each) or {}) do
        table.insert(offered, {
            key = command.key .. "." .. value.id,
            strings = command.key,
            title = value.title,
            run = function()
                command.run(value)
            end,
            order = command.order,
        })
    end
end

-- Adds the command to `offered` as offered now, if it is.
local function Offer(command, offered)
    if not command.feature:IsHandlerActive(command.part) then
        return
    end
    -- An error is reported, and hides the command.
    if command.IsAvailable and securecallfunction(command.IsAvailable) ~= true then
        return
    end
    if command.each then
        OfferEach(command, offered)
        return
    end
    local spellID, title = ResolveSpell(command)
    if command.spell and not spellID then
        return
    end
    table.insert(offered, {
        key = command.key,
        strings = command.key,
        binding = command.binding,
        click = command.click,
        spellID = spellID,
        title = title,
        run = command.run,
        order = command.order,
    })
end

-- The commands offered right now, each a record: { key, strings, binding |
-- click | spellID | run, title, order } (key: <module>.<feature>.commands.<id>,
-- plus .<id> of each value for a command with each; strings: the key of its
-- strings, the command's; title: the game's name for a spell command, if its
-- function gave one, or each value's).
function ns:GetCommands()
    local offered = {}
    for _, command in ipairs(commands) do
        Offer(command, offered)
    end
    return offered
end
