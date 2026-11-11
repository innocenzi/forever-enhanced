-- Blizzard's action buttons, the slots they show and the swaps those hold.
-- We only read their fields (`action`, `bindingAction`), never write them.

local _, ns = ...

local Swaps = ns:GetFeature("interface", "swaps")

local Buttons = {}
Swaps.Buttons = Buttons

local NUM_BUTTONS = 12

-- The main bar shows page 1 to 6, or the bonus bar of a stance (Stealth, Cat
-- Form...) on page 1, as ActionBarController does; vehicles, possession and
-- override bars replace it ("none": no swap).
local MAIN_PAGES = "[vehicleui][possessbar][overridebar][shapeshift] none; "
    .. "[actionbar:1,bonusbar:1] 7; [actionbar:1,bonusbar:2] 8; [actionbar:1,bonusbar:3] 9; "
    .. "[actionbar:1,bonusbar:4] 10; [actionbar:2] 2; [actionbar:3] 3; [actionbar:4] 4; "
    .. "[actionbar:5] 5; [actionbar:6] 6; 1"
local MAIN_PAGE_IDS = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }

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
    for _, page in ipairs(MAIN_PAGE_IDS) do
        slots[tostring(page)] = (page - 1) * NUM_BUTTONS + entry.index
    end
    return slots
end

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

-- What Blizzard's key handlers (ActionButtonDown / ActionButtonUp) do for a
-- button whose key or click went to our overlay instead: show it pressed
-- while held, and clear the highlight of a spell newly put on a bar (`slot`)
-- once used. The release can follow a press Blizzard's button took: Ambush
-- from Stealth leaves the Stealth bar while the key is held, and the key
-- comes back to us before it's released.
function Buttons:MirrorClick(button, slot, down)
    if not down then
        if button:GetButtonState() == "PUSHED" then
            button:SetButtonState("NORMAL")
        end
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
