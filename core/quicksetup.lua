-- Quick setup (ns.QuickSetup): the rows on the root settings page that set a
-- few options at once, in plain words. Each row owns some feature toggles and
-- settings ("<module>.<feature>.enabled" or "<module>.<feature>.<key>"), and
-- each of its answers lists values for them. The row shows the answer matching
-- what's set, or "custom" when none does; picking an answer sets its values
-- through the registered settings, so controls and callbacks follow.
--
-- Matching reads what is in effect: a setting whose feature is off, or whose
-- `requires` isn't met, counts as off. So an answer that turns something off
-- matches while its feature is off, and an answer that turns something on
-- only while it works. An answer lists only the keys it decides; the others
-- are neither compared nor set. Applying a true value also turns on what it
-- needs to work: its `requires` chain, then its feature.
--
-- Rules, checked at load: a path belongs to one row; values pass the schema;
-- a row's features share a settings page (named by its Custom tooltip). Tests
-- check that each row's `default` answer is what a fresh install shows, and
-- that applying any answer makes the row show it.
--
-- Strings: core.quickSetup.<row>, core.quickSetup.<row>.<answer> and
-- core.quickSetup.<row>.<answer>.tooltip.

local _, ns = ...

local L = ns.L

local QuickSetup = {}
ns.QuickSetup = QuickSetup

QuickSetup.CUSTOM = "custom"

-- In display order. Within a row, answers go from the game's own behavior to
-- the most the addon does.
QuickSetup.ROWS = {
    {
        id = "merchant",
        answers = {
            {
                id = "none",
                default = true,
                values = {
                    { "inventory.merchant.autoSellJunk", false },
                    { "inventory.merchant.autoRepair", false },
                },
            },
            {
                id = "sell",
                values = {
                    { "inventory.merchant.autoSellJunk", true },
                    { "inventory.merchant.autoRepair", false },
                },
            },
            {
                id = "both",
                values = {
                    { "inventory.merchant.autoSellJunk", true },
                    { "inventory.merchant.autoRepair", true },
                },
            },
        },
    },
    {
        id = "bars",
        answers = {
            {
                id = "none",
                values = { { "combat.ranks.enabled", false }, { "inventory.food.enabled", false } },
            },
            {
                id = "ranks",
                default = true,
                values = { { "combat.ranks.enabled", true }, { "inventory.food.enabled", false } },
            },
            {
                id = "food",
                values = {
                    { "combat.ranks.enabled", true },
                    { "inventory.food.pick", "level" },
                    { "inventory.food.enabled", true },
                },
            },
        },
    },
    {
        id = "tracker",
        answers = {
            { id = "none", default = true, values = { { "quests.tracking.enabled", false } } },
            {
                id = "nearby",
                -- Without keepManual, quests tracked by hand get untracked once far away.
                values = { { "quests.tracking.keepManual", true }, { "quests.tracking.enabled", true } },
            },
        },
    },
    {
        id = "map",
        answers = {
            { id = "zones", default = true, values = { { "map.seamless.enabled", false } } },
            { id = "seamless", values = { { "map.seamless.enabled", true } } },
        },
    },
    {
        id = "errors",
        answers = {
            { id = "show", default = true, values = { { "combat.errors.enabled", false } } },
            {
                id = "combat",
                values = {
                    { "combat.errors.spells", false },
                    { "combat.errors.combat", true },
                    { "combat.errors.enabled", true },
                },
            },
            {
                id = "always",
                values = {
                    { "combat.errors.spells", false },
                    { "combat.errors.combat", false },
                    { "combat.errors.enabled", true },
                },
            },
        },
    },
    {
        id = "bags",
        answers = {
            { id = "none", default = true, values = { { "inventory.cheapest.enabled", false } } },
            {
                id = "cheapest",
                values = { { "inventory.cheapest.onlyWhenFull", true }, { "inventory.cheapest.enabled", true } },
            },
        },
    },
    {
        id = "questie",
        answers = {
            { id = "show", default = true, values = { { "quests.helpers.hideAnnouncements", false } } },
            { id = "hide", values = { { "quests.helpers.hideAnnouncements", true } } },
        },
    },
}

local function FindEntry(feature, key)
    for _, entry in ipairs(feature.settings) do
        if entry.key == key then
            return entry
        end
    end
end

-- The feature and key a path names, and the key's schema entry (nil for "enabled").
local function Resolve(path)
    local moduleId, featureId, key = path:match("^([^.]+)%.([^.]+)%.([^.]+)$")
    local feature = moduleId and ns:GetFeature(moduleId, featureId)
    assert(feature, "unknown feature in quick setup: " .. path)
    if key == "enabled" then
        return feature, key
    end
    local entry = FindEntry(feature, key)
    assert(entry, "unknown setting in quick setup: " .. path)
    return feature, key, entry
end

-- Whether the path's value is in effect as `value` (see the header).
local function Matches(path, value)
    local feature, key, entry = Resolve(path)
    if not entry then
        return feature.db.enabled == value
    end
    local works = ns.SettingsPanel:IsSettingInEffect(feature, entry)
    if value == false then
        return not works or feature.db[key] == false
    end
    return works and feature.db[key] == value
end

local function AnswerMatches(answer)
    for _, pair in ipairs(answer.values) do
        if not Matches(pair[1], pair[2]) then
            return false
        end
    end
    return true
end

function QuickSetup:GetRow(rowId)
    for _, row in ipairs(self.ROWS) do
        if row.id == rowId then
            return row
        end
    end
    error("unknown quick setup row: " .. tostring(rowId))
end

local function GetAnswer(row, answerId)
    for _, answer in ipairs(row.answers) do
        if answer.id == answerId then
            return answer
        end
    end
    error("unknown answer " .. tostring(answerId) .. " in quick setup row " .. row.id)
end

function QuickSetup:GetDefaultAnswer(row)
    for _, answer in ipairs(row.answers) do
        if answer.default then
            return answer.id
        end
    end
end

-- The ids of the answers in effect (one at most, which tests check).
function QuickSetup:GetMatchingAnswers(row)
    local ids = {}
    for _, answer in ipairs(row.answers) do
        if AnswerMatches(answer) then
            table.insert(ids, answer.id)
        end
    end
    return ids
end

-- The id of the answer in effect, or CUSTOM.
function QuickSetup:GetCurrentAnswer(row)
    return self:GetMatchingAnswers(row)[1] or self.CUSTOM
end

-- Sets what a true value needs to work: the entries up its `requires` chain.
local function SetRequirements(feature, entry)
    if not entry.requires then
        return
    end
    local key, value = next(entry.requires)
    SetRequirements(feature, FindEntry(feature, key))
    ns.SettingsPanel:SetValue(feature:GetLocaleKey(key), value)
end

-- Settings first, then the toggles: a feature turned on reads its final values
-- in OnEnable instead of going through OnSettingChanged for each.
function QuickSetup:Apply(row, answerId)
    local answer = GetAnswer(row, answerId)
    local toEnable, toggles = {}, {}
    for _, pair in ipairs(answer.values) do
        local path, value = pair[1], pair[2]
        local feature, _, entry = Resolve(path)
        if entry then
            if value ~= false then
                SetRequirements(feature, entry)
                toEnable[feature] = true
            end
            ns.SettingsPanel:SetValue(path, value)
        else
            table.insert(toggles, pair)
        end
    end
    for _, pair in ipairs(toggles) do
        local feature = Resolve(pair[1])
        toEnable[feature] = nil
        ns.SettingsPanel:SetValue(pair[1], pair[2])
    end
    for feature in pairs(toEnable) do
        ns.SettingsPanel:SetValue(feature:GetLocaleKey("enabled"), true)
    end
end

-- The settings page of the row's features.
function QuickSetup:GetPage(row)
    local feature = Resolve(row.answers[1].values[1][1])
    return feature.page
end

-- The names of what the answer turns on, for its tooltip: a feature's title
-- for its toggle, a setting's label otherwise.
function QuickSetup:GetTurnedOn(row, answerId)
    local names = {}
    for _, pair in ipairs(GetAnswer(row, answerId).values) do
        if pair[2] == true then
            local feature, key = Resolve(pair[1])
            table.insert(names, L[feature:GetLocaleKey(key == "enabled" and "title" or key)])
        end
    end
    return names
end

-- The row's on/off options and whether each is in effect, for the Custom
-- tooltip: { name, on } in the order the answers first list them.
function QuickSetup:GetOptionStates(row)
    local states, seen = {}, {}
    for _, answer in ipairs(row.answers) do
        for _, pair in ipairs(answer.values) do
            local path = pair[1]
            local feature, key, entry = Resolve(path)
            if not seen[path] and (not entry or entry.type == "toggle") then
                seen[path] = true
                local name = L[feature:GetLocaleKey(entry and key or "title")]
                table.insert(states, { name = name, on = Matches(path, true) })
            end
        end
    end
    return states
end

-- A typo or a shared path fails at load instead of misreading a row.
function QuickSetup:Validate()
    local owners = {}
    for _, row in ipairs(self.ROWS) do
        local page = self:GetPage(row)
        local defaults = 0
        for _, answer in ipairs(row.answers) do
            local name = row.id .. "." .. answer.id
            defaults = defaults + (answer.default and 1 or 0)
            for _, pair in ipairs(answer.values) do
                local path, value = pair[1], pair[2]
                local feature, _, entry = Resolve(path)
                assert(owners[path] == nil or owners[path] == row, "path in two quick setup rows: " .. path)
                owners[path] = row
                assert(feature.page == page, "quick setup row on two pages: " .. row.id)
                if entry then
                    assert(not entry.needs, "quick setup can't set what another feature needs: " .. path)
                    assert(ns.Database:IsValidValue(entry, value), "invalid value for " .. path .. " in " .. name)
                else
                    assert(type(value) == "boolean", "invalid value for " .. path .. " in " .. name)
                end
            end
        end
        assert(defaults == 1, "quick setup row needs one default answer: " .. row.id)
    end
end
