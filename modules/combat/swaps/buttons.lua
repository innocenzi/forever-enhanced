-- Blizzard's action buttons: their bars and pages, the swaps their slots hold,
-- and what they do themselves for a key or click our overlay takes instead
-- (pressed look, new spell highlight, drags). The only file that knows their
-- fields and handlers; we never stamp fields onto them.

local _, ns = ...

local Swaps = ns:GetFeature("combat", "swaps")

local Buttons = {}
Swaps.Buttons = Buttons

local NUM_BUTTONS = 12

-- Bars and pages ---------------------------------------------------------------

-- The main bar shows page 1 to 6, or the bonus bar of a stance (Stealth, Cat
-- Form...) on page 1, as ActionBarController does; vehicles, possession and
-- override bars replace it ("none": no swap).
local MAIN_PAGES = "[vehicleui][possessbar][overridebar][shapeshift] none; "
    .. "[actionbar:1,bonusbar:1] 7; [actionbar:1,bonusbar:2] 8; [actionbar:1,bonusbar:3] 9; "
    .. "[actionbar:1,bonusbar:4] 10; [actionbar:2] 2; [actionbar:3] 3; [actionbar:4] 4; "
    .. "[actionbar:5] 5; [actionbar:6] 6; 1"
local NUM_MAIN_PAGES = 10

-- The other bars always show their own slot, hidden with the main bar's
-- replacements.
local FIXED_PAGES = "[vehicleui][possessbar][overridebar] none; fixed"

local BARS = {
    { prefix = "ActionButton", main = true },
    { prefix = "MultiBarBottomLeftButton" },
    { prefix = "MultiBarBottomRightButton" },
    { prefix = "MultiBarRightButton" },
    { prefix = "MultiBarLeftButton" },
    { prefix = "MultiBar5Button" },
    { prefix = "MultiBar6Button" },
    { prefix = "MultiBar7Button" },
}

-- Every action button: { button, main, index }.
function Buttons:Enumerate()
    local entries = {}
    for _, bar in ipairs(BARS) do
        for index = 1, NUM_BUTTONS do
            local button = _G[bar.prefix .. index]
            if button then
                table.insert(entries, { button = button, main = bar.main, index = index })
            end
        end
    end
    return entries
end

-- The macro conditions that give the entry's page.
function Buttons:GetPageDriver(entry)
    return entry.main and MAIN_PAGES or FIXED_PAGES
end

-- The slots the entry shows: { [page] = slot }, pages as the driver names them.
function Buttons:GetSlots(entry)
    if not entry.main then
        return { fixed = entry.button.action }
    end
    local slots = {}
    for page = 1, NUM_MAIN_PAGES do
        slots[tostring(page)] = (page - 1) * NUM_BUTTONS + entry.index
    end
    return slots
end

-- What they hold -------------------------------------------------------------------

-- The swap (from Swaps:GetSwaps()) of the spell in `slot`, or nil.
function Buttons:GetSwapAt(slot)
    if not slot then
        return nil
    end
    local actionType, id = GetActionInfo(slot)
    if actionType ~= "spell" then
        return nil
    end
    local name = C_Spell.GetSpellName(id)
    return name and Swaps:GetSwaps()[name]
end

-- The swap of the spell the button shows now, or nil.
function Buttons:GetShownSwap(button)
    return self:GetSwapAt(button.action)
end

-- The keys bound to the button, through its binding or a click binding.
function Buttons:GetKeys(button)
    local keys = {}
    for _, command in ipairs({ button.bindingAction or "", "CLICK " .. button:GetName() .. ":LeftButton" }) do
        for _, key in ipairs({ GetBindingKey(command) }) do
            table.insert(keys, key)
        end
    end
    return keys
end

-- The button's icon texture, to lay the replacement's over.
function Buttons:GetIcon(button)
    return button.icon
end

-- Standing in for them ---------------------------------------------------------------

-- What Blizzard's key handlers (ActionButtonDown / ActionButtonUp) do: show
-- the button pressed while held, and clear the highlight of a spell newly put
-- on a bar (`slot`) once used.
function Buttons:MirrorClick(button, slot, down)
    if not down then
        self:ReleasePress(button)
        return
    end
    if button:GetButtonState() == "NORMAL" then
        button:SetButtonState("PUSHED")
    end
    if slot and GetNewActionHighlightMark(slot) then
        ClearNewActionHighlight(slot)
        button:UpdateHighlightMark()
    end
end

-- Shows the button released. Also for a key changing hands while held (Ambush
-- breaks Stealth, and the main bar's key goes from Blizzard's button to our
-- overlay): the game drops that key's release, so whichever side took the
-- press would show it pressed for good.
function Buttons:ReleasePress(button)
    if button:GetButtonState() == "PUSHED" then
        button:SetButtonState("NORMAL")
    end
end

-- What Blizzard's button does when dragged, out of combat: picks up the spell
-- in `slot` when the bars are unlocked or with the pick up modifier.
function Buttons:MirrorDragStart(slot)
    if InCombatLockdown() then
        return
    end
    if Settings.GetValue("lockActionBars") and not IsModifiedClick("PICKUPACTION") then
        return
    end
    PickupAction(slot)
end

-- What Blizzard's button does when something is dropped on it, out of combat.
function Buttons:MirrorReceiveDrag(slot)
    if not InCombatLockdown() then
        PlaceAction(slot)
    end
end
