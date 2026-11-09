-- Every change to a window's anchors: saved positions, the player's drags,
-- pinning, and putting windows back where Blizzard placed them.
--
-- Blizzard's anchors are remembered whenever a frame is touched while it isn't
-- at a position we set: Blizzard's layout code just ran (or the frame was never
-- moved), so what it has is the default. Undoing re-sets those anchors.
--
-- The client would save a named frame moved with StartMoving in its own layout
-- cache and restore it at login, beyond our control: a dropped frame is marked
-- as not user-placed, and gets its own movable flag back.
--
-- Protected frames can't be moved in combat: the change waits for the end of
-- combat. Undoing still happens if the feature was turned off in between.

local _, ns = ...

local Windows = ns:GetFeature("interface", "windows")

local Placement = {}
Windows.Placement = Placement

-- Per frame: Blizzard's anchors, { { point, relativeTo, relativePoint, x, y }, ... }.
local defaults = setmetatable({}, { __mode = "k" })
-- Per frame: the position we anchored it to, while it is there.
local applied = setmetatable({}, { __mode = "k" })
-- Per frame: "apply" or "restore", waiting for the end of combat.
local pending = setmetatable({}, { __mode = "k" })
-- Per frame being dragged: whether it was movable before.
local moving = setmetatable({}, { __mode = "k" })

local listener

local function Defer(frame, action)
    pending[frame] = action
    listener:Start()
end

-- Whether the frame is anchored exactly where we put it.
local function IsAtApplied(frame)
    local position = applied[frame]
    if not position or frame:GetNumPoints() ~= 1 then
        return false
    end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    return point == position.point
        and relativeTo == UIParent
        and relativePoint == position.relativePoint
        and x == position.x
        and y == position.y
end

-- Remembers the frame's anchors as Blizzard's, unless they are ours.
local function Capture(frame)
    if IsAtApplied(frame) then
        return
    end
    local anchors = {}
    for index = 1, frame:GetNumPoints() do
        anchors[index] = { frame:GetPoint(index) }
    end
    defaults[frame] = anchors
    applied[frame] = nil
end

-- Anchors the frame to UIParent at the position. Capture first.
local function Anchor(frame, position)
    frame:ClearAllPoints()
    frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    applied[frame] = position
end

-- Puts the frame back on Blizzard's anchors, if we moved it.
local function Restore(frame)
    if not IsAtApplied(frame) then
        pending[frame] = nil
        applied[frame] = nil
        return
    end
    if not Placement:CanMove(frame) then
        Defer(frame, "restore")
        return
    end
    pending[frame] = nil
    applied[frame] = nil
    frame:ClearAllPoints()
    for _, anchor in ipairs(defaults[frame]) do
        frame:SetPoint(unpack(anchor, 1, 5))
    end
end

-- Whether the frame can be moved right now.
function Placement:CanMove(frame)
    return not (InCombatLockdown() and frame:IsProtected())
end

-- Moves the frame to its saved position, if it has one.
function Placement:Apply(frame)
    local position = Windows.Store:Get(frame:GetName())
    if not position then
        return
    end
    if not self:CanMove(frame) then
        Defer(frame, "apply")
        return
    end
    pending[frame] = nil
    Capture(frame)
    Anchor(frame, position)
end

-- Anchors the frame to the screen at its bottom right corner (nil when the
-- client can't place it yet), so that moving the frame it was anchored to
-- leaves it in place. Undone like a move.
function Placement:Pin(frame, right, bottom)
    if right and bottom and self:CanMove(frame) then
        Capture(frame)
        Anchor(frame, { point = "BOTTOMRIGHT", relativePoint = "BOTTOMLEFT", x = right, y = bottom })
    end
end

-- The player starts dragging the frame (check CanMove first).
function Placement:StartMoving(frame)
    if moving[frame] ~= nil then
        return
    end
    Capture(frame)
    moving[frame] = frame:IsMovable()
    frame:SetMovable(true)
    frame:StartMoving()
end

-- The player drops the frame: the client anchored it to UIParent, we save that.
function Placement:StopMoving(frame)
    local wasMovable = moving[frame]
    if wasMovable == nil then
        return
    end
    moving[frame] = nil
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    frame:SetMovable(wasMovable)

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local position = { point = point, relativePoint = relativePoint, x = x, y = y }
    Windows.Store:Save(frame:GetName(), position)
    Anchor(frame, position)
end

-- Forgets the frame's saved position and puts it back where Blizzard placed it.
function Placement:Reset(frame)
    Windows.Store:Forget(frame:GetName())
    Restore(frame)
end

function Placement:RestoreAll()
    for frame in pairs(applied) do
        Restore(frame)
    end
end

listener = ns:CreateEventListener({
    PLAYER_REGEN_ENABLED = function(self)
        self:Stop()
        for frame, action in pairs(pending) do
            if action == "restore" or not Windows:IsActive() then
                Restore(frame)
            else
                Placement:Apply(frame)
            end
        end
    end,
})
