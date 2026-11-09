-- Saved positions, in the account store so every character shares them.
--
-- positions[frameName] = { point, relativePoint, x, y }, relative to UIParent.

local _, ns = ...

local Windows = ns:GetFeature("interface", "windows")

local Store = {}
Windows.Store = Store

local POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local function GetPositions()
    local store = Windows:GetAccountStore()
    if type(store.positions) ~= "table" then
        store.positions = {}
    end
    return store.positions
end

local function IsValid(position)
    return type(position) == "table"
        and POINTS[position.point]
        and POINTS[position.relativePoint]
        and type(position.x) == "number"
        and type(position.y) == "number"
end

-- The saved position of the frame, or nil. Malformed entries are dropped.
function Store:Get(name)
    local positions = GetPositions()
    local position = positions[name]
    if position ~= nil and not IsValid(position) then
        positions[name] = nil
        return nil
    end
    return position
end

function Store:Save(name, position)
    GetPositions()[name] = position
end

function Store:Forget(name)
    GetPositions()[name] = nil
end
