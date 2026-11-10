-- Item mover: moves items in rounds, waiting for the server between rounds.
--
-- Measured on Forever: the server busies and frees slots (ITEM_LOCK_CHANGED),
-- then delivers moves in one BAG_UPDATE_DELAYED. Slots are freed *before*
-- positions update, so only a bag update means positions are current.
--
-- local mover = ns:CreateMover({ Plan = function() return moves end, maxMovesPerKey = 3 })
--   Plan() reads the live containers and returns the moves still needed:
--   { { from = { bagID, slot }, to = { bagID, slot }, key = <item GUID> }, ... }
--   An empty list (or only moves out of attempts) ends the run.
--
-- Each round sends every move that shares no slot with another and touches no
-- busy slot, as two pickups: onto the same item, the client merges the stacks;
-- otherwise it swaps them. Other moves wait for a later round. The next round
-- runs on the bag update that follows, once the sent slots are free. Rounds
-- re-plan from live positions, so a late server batch just costs one more round.
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

local function SlotKey(location)
    return location.bagID .. ":" .. location.slot
end

local function IsSlotBusy(location)
    local info = C_Container.GetContainerItemInfo(location.bagID, location.slot)
    return info ~= nil and info.isLocked
end

local MoverMixin = {}

function MoverMixin:IsRunning()
    return self.running
end

-- Waiting for a server change started elsewhere (WaitForServer).
function MoverMixin:IsWaitingForServer()
    return self.running and self.waitingForServer
end

-- Runs the next round after `seconds` (0: next frame), replacing any scheduled one.
function MoverMixin:Schedule(seconds)
    if self.timer then
        self.timer:Cancel()
    end
    self.timer = C_Timer.NewTimer(seconds, function()
        self:RunRound()
    end)
end

function MoverMixin:Begin()
    if self.running then
        return
    end
    self.running = true
    self.moveCounts = {}
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

function MoverMixin:RunRound()
    self.timer = nil
    self.waitingForServer = false

    -- Paused until combat ends (OnCombatEnded), without counting toward giving up.
    if InCombatLockdown() then
        self.pausedForCombat = true
        self.giveUpTimer:Cancel()
        return
    end

    if CursorHasItem() then
        self:Schedule(MOVE_TIMEOUT_SECONDS)
        return
    end

    local used, pending = {}, {}
    local remaining = false
    for _, move in ipairs(self.definition.Plan()) do
        local count = self.moveCounts[move.key] or 0
        if count < self.definition.maxMovesPerKey then
            remaining = true
            local fromKey, toKey = SlotKey(move.from), SlotKey(move.to)
            if not used[fromKey] and not used[toKey] and not IsSlotBusy(move.from) and not IsSlotBusy(move.to) then
                used[fromKey], used[toKey] = true, true
                self.moveCounts[move.key] = count + 1
                Pickup(move.from)
                Pickup(move.to)
                -- A completed drop empties the cursor at once; anything left was refused.
                if CursorHasItem() then
                    ClearCursor()
                    self:Stop()
                    return
                end
                table.insert(pending, move.from)
                table.insert(pending, move.to)
            end
        end
    end

    if not remaining then
        self:Stop()
        return
    end
    self.pending = pending
    self:Schedule(MOVE_TIMEOUT_SECONDS)
end

function MoverMixin:ArePendingSlotsFree()
    for _, location in ipairs(self.pending) do
        if IsSlotBusy(location) then
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
    if self.pausedForCombat then
        return
    end
    if self.waitingForServer or self:ArePendingSlotsFree() then
        self:Schedule(0)
    end
end

-- definition: { Plan = function() return moves end, maxMovesPerKey }
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
