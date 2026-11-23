-- Item mover: moves items in rounds, waiting for the server between rounds.
--
-- Measured on Forever: the server busies and frees slots (ITEM_LOCK_CHANGED),
-- then delivers moves in one BAG_UPDATE_DELAYED. Slots are freed *before*
-- positions update, so only a bag update means positions are current.
--
-- local mover = ns:CreateMover({ Plan = function() return moves end, maxMovesPerKey = 3 })
--   Plan() reads the live containers and returns the moves still needed:
--   { { from = { bagID, slot }, to = { bagID, slot }, key = <item GUID>, count }, ... }
--   A move with `count` splits that many off the source stack, onto an empty
--   slot or a stack of the same item with room for all of them; without, it
--   moves the whole stack.
--   An empty list (or only moves out of attempts) ends the run.
--   Optional OnFinished(movedCount) runs when a run ends that way, with the
--   number of moves it sent; never when it's stopped, gives up or a drop fails.
--
-- Each round sends every move that shares no slot with another and touches no
-- busy slot, as two pickups (a split, then a pickup, for a move with `count`):
-- onto the same item, the client merges the stacks; otherwise it swaps them.
-- Other moves wait for a later round. A round's moves go out MOVES_PER_FRAME a
-- frame. The next round runs on the bag update that follows the last of them,
-- once the sent slots are free and both slots of every sent move show it (what
-- they hold changed): another bag update can come in between, the bank's own
-- on opening for one, and planning from the old positions would send the same
-- moves again (seen in game: a withdrawal of 16 off a stack of 20 took all 20).
-- Rounds re-plan from live positions, so a late server batch just costs one
-- more round.
-- A key moved maxMovesPerKey times is dropped (the server refuses the move).
--
-- No rounds run in combat: the run pauses until combat ends. Seen on Forever: in
-- combat the pickup goes through but the drop is blocked (ADDON_ACTION_BLOCKED),
-- leaving both slots locked. A drop that leaves the item on the cursor (the
-- client blocked or refused it) puts it back and ends the run, so a failed move
-- never leaves an item held and its slot greyed.

local _, ns = ...

local MOVE_TIMEOUT_SECONDS = 1 -- fallback when a round's moves never report back
local GIVE_UP_SECONDS = 20 -- abandon a run that never finishes
-- Measured on Forever: a swap costs the client ~6 ms (its two pickups), so a
-- round's swaps are spread over frames.
local MOVES_PER_FRAME = 4

local function SlotKey(location)
    return location.bagID .. ":" .. location.slot
end

local function IsSlotBusy(location)
    local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
    return info ~= nil and info.isLocked
end

-- What a slot holds, by stack (GUID) and count: a move changes it on both of
-- its slots, a swap of two stacks of the same item included.
local function GetContents(location)
    local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
    if not info then
        return ""
    end
    local guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(location.bagID, location.slot))
    return tostring(guid) .. "x" .. info.stackCount
end

local MoverMixin = {}

function MoverMixin:IsRunning()
    return self.running
end

-- Waiting for a server change started elsewhere (WaitForServer).
function MoverMixin:IsWaitingForServer()
    return self.running and self.waitingForServer
end

-- Runs `method` (default: the next round) after `seconds` (0: next frame),
-- replacing whatever was scheduled.
function MoverMixin:Schedule(seconds, method)
    if self.timer then
        self.timer:Cancel()
    end
    self.timer = C_Timer.NewTimer(seconds, function()
        self[method or "RunRound"](self)
    end)
end

-- Starts a run if needed. A round still being sent is dropped: the next one plans again.
function MoverMixin:Begin()
    self.queue = {}
    if self.running then
        return
    end
    self.running = true
    self.moveCounts = {}
    self.movedCount = 0
    self.pending = {}
    self:StartGiveUpTimer()
    self.listener:Start()
end

-- (Re)starts the countdown that abandons a run that never finishes.
function MoverMixin:StartGiveUpTimer()
    if self.giveUpTimer then
        self.giveUpTimer:Cancel()
    end
    self.giveUpTimer = C_Timer.NewTimer(GIVE_UP_SECONDS, function()
        self:Stop()
    end)
end

-- Starts a run (or keeps the current one going) with a round on the next frame.
function MoverMixin:Start()
    self:Begin()
    self.waitingForServer = false
    self:Schedule(0)
end

-- Starts a run (or keeps the current one going) that waits for a change the
-- server is making (e.g. a sort): the next round runs on the next bag update,
-- or after `seconds` if none comes.
function MoverMixin:WaitForServer(seconds)
    self:Begin()
    self.waitingForServer = true
    self:Schedule(seconds)
end

function MoverMixin:Stop()
    if not self.running then
        return
    end
    self.running = false
    self.queue = {}
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
    self.giveUpTimer:Cancel()
    self.giveUpTimer = nil
    self.pausedForCombat = false
    self.listener:Stop()
end

local function Pickup(location)
    C_Container.PickupContainerItem(location.bagID, location.slot)
end

-- Whether moves can be sent now: in combat the run pauses until it ends
-- (OnCombatEnded), without counting toward giving up; while the cursor holds
-- an item, the next round waits.
function MoverMixin:CanSend()
    if InCombatLockdown() then
        self.pausedForCombat = true
        self.giveUpTimer:Cancel()
        return false
    end
    if CursorHasItem() then
        self:Schedule(MOVE_TIMEOUT_SECONDS)
        return false
    end
    return true
end

function MoverMixin:RunRound()
    self.timer = nil
    self.waitingForServer = false
    if not self:CanSend() then
        return
    end

    local used, queue = {}, {}
    local remaining = false
    for _, move in ipairs(self.definition.Plan()) do
        local count = self.moveCounts[move.key] or 0
        if count < self.definition.maxMovesPerKey then
            remaining = true
            local fromKey, toKey = SlotKey(move.from), SlotKey(move.to)
            if not used[fromKey] and not used[toKey] and not IsSlotBusy(move.from) and not IsSlotBusy(move.to) then
                used[fromKey], used[toKey] = true, true
                table.insert(queue, move)
            end
        end
    end

    if not remaining then
        self:Stop()
        if self.definition.OnFinished then
            self.definition.OnFinished(self.movedCount)
        end
        return
    end
    self.queue, self.pending = queue, {}
    self:SendQueued()
end

-- Sends the round's queued moves, MOVES_PER_FRAME a frame, then waits for the server.
function MoverMixin:SendQueued()
    self.timer = nil
    if not self:CanSend() then
        self.queue = {} -- the next round plans again
        return
    end
    for _ = 1, math.min(MOVES_PER_FRAME, #self.queue) do
        local move = table.remove(self.queue, 1)
        -- Other changes may have reached these slots since the round was planned.
        if not IsSlotBusy(move.from) and not IsSlotBusy(move.to) then
            self.moveCounts[move.key] = (self.moveCounts[move.key] or 0) + 1
            self.movedCount = self.movedCount + 1
            local before = { from = GetContents(move.from), to = GetContents(move.to) }
            if move.count then
                C_Container.SplitContainerItem(move.from.bagID, move.from.slot, move.count)
            else
                Pickup(move.from)
            end
            Pickup(move.to)
            -- A completed drop empties the cursor at once; anything left was refused.
            if CursorHasItem() then
                ClearCursor()
                self:Stop()
                return
            end
            table.insert(self.pending, { location = move.from, before = before.from })
            table.insert(self.pending, { location = move.to, before = before.to })
        end
    end
    if self.queue[1] then
        self:Schedule(0, "SendQueued")
    else
        self:Schedule(MOVE_TIMEOUT_SECONDS)
    end
end

-- Whether the slots of the moves sent are free and show them.
function MoverMixin:HavePendingMovesLanded()
    for _, slot in ipairs(self.pending) do
        if IsSlotBusy(slot.location) or GetContents(slot.location) == slot.before then
            return false
        end
    end
    return not CursorHasItem()
end

function MoverMixin:OnCombatEnded()
    if self.pausedForCombat then
        self.pausedForCombat = false
        self:StartGiveUpTimer()
        self:Schedule(0)
    end
end

function MoverMixin:OnBagsUpdated()
    -- While a round is being sent, its last moves start the next one.
    if self.pausedForCombat or self.queue[1] then
        return
    end
    if self.waitingForServer or self:HavePendingMovesLanded() then
        self:Schedule(0)
    end
end

-- definition: { Plan = function() return moves end, maxMovesPerKey, OnFinished }
function ns:CreateMover(definition)
    local mover = Mixin({ definition = definition, running = false }, MoverMixin)
    mover.listener = ns:CreateEventListener({
        BAG_UPDATE_DELAYED = function()
            mover:OnBagsUpdated()
        end,
        PLAYER_REGEN_ENABLED = function()
            mover:OnCombatEnded()
        end,
    })
    return mover
end
