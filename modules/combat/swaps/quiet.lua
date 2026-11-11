-- Each press of a swap button casts twice, and one of the two is meant to
-- fail: the replacement on key down when it can't be cast, or else the
-- original on key up, still on the global cooldown. This hides the error (red
-- text and voice) of that one click, and only that one: the other cast's
-- errors (out of range, not enough energy) still show. The client reports a
-- refused cast at once, inside the click.

local _, ns = ...

local Swaps = ns:GetFeature("combat", "swaps")

local Quiet = {}
Swaps.Quiet = Quiet

local EVENT = "UI_ERROR_MESSAGE"

-- Overlay -> whether the replacement could be cast when its key went down.
local usableAtPress = setmetatable({}, { __mode = "k" })
local muted = false

local function Mute()
    if UIErrorsFrame:IsEventRegistered(EVENT) then
        UIErrorsFrame:UnregisterEvent(EVENT)
        muted = true
    end
end

local function Unmute()
    if muted then
        muted = false
        UIErrorsFrame:RegisterEvent(EVENT)
    end
end

local function PreClick(overlay, _, down)
    local swap = Swaps.Overlays:GetCurrentSwap(overlay)
    if not swap then
        return
    end
    if down then
        usableAtPress[overlay] = Swaps:CanCastReplacement(swap)
        if not usableAtPress[overlay] then
            Mute()
        end
    elseif usableAtPress[overlay] then
        Mute()
    end
end

function Quiet:Attach(overlay)
    overlay:HookScript("PreClick", PreClick)
    overlay:HookScript("PostClick", Unmute)
end
