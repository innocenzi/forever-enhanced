-- Values to text, for the log. In combat, some APIs return secret values:
-- addon code can pass them along but not read them (tostring, concatenation,
-- comparisons throw). They print as <secret type>, like Blizzard's /dump does.

local _, ns = ...

local MAX_DEPTH = 3 -- nested tables deeper than this print as {...}
local MAX_KEYS = 40 -- per table

local Serialize

local function KeyOrder(a, b)
    local typeA, typeB = type(a), type(b)
    if typeA ~= typeB then
        return typeA < typeB
    end
    if typeA == "number" or typeA == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

-- Secret keys can't be compared: such a table keeps its pairs() order.
local function SortKeys(keys)
    for _, key in ipairs(keys) do
        if not canaccessvalue(key) then
            return
        end
    end
    table.sort(keys, KeyOrder)
end

local function SerializeTable(value, depth, seen)
    if not canaccesstable(value) then
        return "<secret table>"
    end
    -- Widgets are tables around a userdata at [0]: print their name, not their fields.
    if type(value[0]) == "userdata" and value.GetObjectType then
        return ("<%s %s>"):format(value:GetObjectType(), value:GetDebugName() or "?")
    end
    if seen[value] then
        return "<cycle>"
    end
    if depth >= MAX_DEPTH then
        return "{...}"
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    SortKeys(keys)
    local parts = {}
    for index, key in ipairs(keys) do
        if index > MAX_KEYS then
            table.insert(parts, ("...+%d"):format(#keys - MAX_KEYS))
            break
        end
        local valueText = Serialize(value[key], depth + 1, seen)
        -- The array part (sorted first) prints without its indices.
        if type(key) == "number" and canaccessvalue(key) and key == index then
            table.insert(parts, valueText)
        else
            local keyText = type(key) == "string" and canaccessvalue(key) and key:match("^[%a_][%w_]*$") and key
                or "[" .. Serialize(key, depth + 1, seen) .. "]"
            table.insert(parts, keyText .. "=" .. valueText)
        end
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

function Serialize(value, depth, seen)
    local valueType = type(value)
    if not canaccessvalue(value) then
        return ("<secret %s>"):format(valueType)
    elseif valueType == "string" then
        return depth == 0 and value or ("%q"):format(value)
    elseif valueType == "table" then
        return SerializeTable(value, depth, seen)
    elseif valueType == "function" then
        return "<function>"
    end
    return tostring(value)
end

-- `...` as space-separated text: top-level strings raw, tables dumped.
-- Throws only on a value whose methods throw (a widget's GetDebugName).
function ns:Join(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = Serialize((select(index, ...)), 0, {})
    end
    return table.concat(parts, " ")
end

-- A widget or table's name for the log.
function ns:Name(owner)
    if type(owner) == "table" then
        local GetName = owner.GetDebugName or owner.GetName
        if type(GetName) == "function" then
            return GetName(owner) or "?"
        end
    end
    return tostring(owner)
end
