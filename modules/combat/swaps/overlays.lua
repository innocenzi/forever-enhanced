-- Our secure buttons over Blizzard's action buttons that hold a swapped
-- spell. Each casts the replacement on key down and the original on key up
-- (`pressAndHoldAction` makes `type` act on down and `typerelease` on up, and
-- `downbutton` sends the down to the "swap" attributes). They take the
-- button's keys (its binding, through override click bindings), left clicks
-- and drags; tooltips and other clicks stay Blizzard's.
--
-- The main bar changes pages in combat (Stealth shows the bonus bar): a state
-- driver gives the page, and restricted code takes the keys only on pages
-- where the slot holds a swap, giving them back to Blizzard's button
-- otherwise. Everything else (which pages, spells and keys) is set out of
-- combat only.

local _, ns = ...

local Swaps = ns:GetFeature("combat", "swaps")
local Buttons = Swaps.Buttons

local Overlays = {}
Swaps.Overlays = Overlays

-- Runs in the restricted environment with the page (a string, or nil before
-- the driver's first state): claims the keys and shows the overlay for that
-- page's swap, or gives the keys back and hides it. Reads the attributes
-- WriteAttributes sets.
local APPLY = [[
    local page = ...
    self:ClearBindings()
    local original = page and self:GetAttribute("original-" .. page)
    if not original then
        self:Hide()
        return
    end
    self:SetAttribute("spell", original)
    self:SetAttribute("spell-swap", self:GetAttribute("replacement-" .. page))
    for i = 1, self:GetAttribute("keycount") or 0 do
        self:SetBindingClick(false, self:GetAttribute("key" .. i), self:GetName())
    end
    self:Show()
]]

local REAPPLY = [[self:RunAttribute("apply", self:GetAttribute("state-page"))]]

local overlays = setmetatable({}, { __mode = "k" }) -- Blizzard button -> overlay
-- overlay -> { signature, pages = { [page] = { swap, slot } }, attributes (names set) }
local configs = {}
local driven = {} -- overlay -> true while its state driver runs
local count = 0
local pending = false
local scheduled = false

-- The swap and slot of the overlay's current page, or nil.
local function GetCurrentPage(overlay)
    local config = configs[overlay]
    local page = overlay:GetAttribute("state-page")
    return config and page and config.pages[page]
end

-- The swap the overlay casts on its current page, or nil.
function Overlays:GetCurrentSwap(overlay)
    local current = GetCurrentPage(overlay)
    return current and current.swap
end

-- Our overlay takes these from Blizzard's button under it: it does what that
-- button would.
local function OnDragStart(overlay)
    local current = GetCurrentPage(overlay)
    if current then
        Buttons:MirrorDragStart(current.slot)
    end
end

local function OnReceiveDrag(overlay)
    local current = GetCurrentPage(overlay)
    if current then
        Buttons:MirrorReceiveDrag(current.slot)
    end
end

local function OnPostClick(overlay, _, down)
    local current = GetCurrentPage(overlay)
    Buttons:MirrorClick(overlay:GetParent(), current and current.slot, down)
end

-- The overlay shows when it takes the keys and hides when it gives them back,
-- maybe while one is held.
local function OnKeysHandedOver(overlay)
    Buttons:ReleasePress(overlay:GetParent())
end

local function CreateOverlay(button)
    count = count + 1
    -- Click bindings need a global name.
    local overlay = CreateFrame(
        "Button",
        "ForeverEnhancedSwapButton" .. count,
        button,
        "SecureActionButtonTemplate, SecureHandlerStateTemplate"
    )
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 10)
    overlay:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    overlay:SetPassThroughButtons("RightButton", "MiddleButton", "Button4", "Button5")
    overlay:SetMouseMotionEnabled(false)
    overlay:RegisterForDrag("LeftButton")
    overlay:SetScript("OnDragStart", OnDragStart)
    overlay:SetScript("OnReceiveDrag", OnReceiveDrag)
    overlay:HookScript("PostClick", OnPostClick)
    overlay:HookScript("OnShow", OnKeysHandedOver)
    overlay:HookScript("OnHide", OnKeysHandedOver)
    Swaps.Quiet:Attach(overlay)
    overlay:SetAttribute("pressAndHoldAction", true)
    overlay:SetAttribute("downbutton", "swap")
    overlay:SetAttribute("type-swap", "spell")
    overlay:SetAttribute("typerelease", "spell")
    overlay:SetAttribute("apply", APPLY)
    overlay:SetAttribute("_onstate-page", [[self:RunAttribute("apply", newstate)]])
    overlay:Hide()
    overlays[button] = overlay
    return overlay
end

-- A string that changes whenever the overlay's pages, spells or keys do.
local function Signature(pages, keys)
    local parts = {}
    for page, current in pairs(pages) do
        table.insert(parts, page .. "=" .. current.swap.originalName .. ">" .. current.swap.replacementName)
    end
    table.sort(parts)
    table.insert(parts, "keys=" .. table.concat(keys, ","))
    return table.concat(parts, ";")
end

-- Sets the attributes APPLY reads for `pages` and `keys`, clearing those the
-- overlay's previous ones set. Returns the names set.
local function WriteAttributes(overlay, pages, keys)
    local previous = configs[overlay]
    for _, name in ipairs(previous and previous.attributes or {}) do
        overlay:SetAttribute(name, nil)
    end
    local names = {}
    local function Set(name, value)
        overlay:SetAttribute(name, value)
        table.insert(names, name)
    end
    for page, current in pairs(pages) do
        Set("original-" .. page, current.swap.originalName)
        Set("replacement-" .. page, current.swap.replacementName)
    end
    for i, key in ipairs(keys) do
        Set("key" .. i, key)
    end
    Set("keycount", #keys)
    return names
end

-- Sets up the overlay of one Blizzard button for the current swaps (out of combat).
local function Configure(entry)
    local button = entry.button
    local pages = {}
    for page, slot in pairs(Buttons:GetSlots(entry)) do
        local swap = Buttons:GetSwapAt(slot)
        if swap then
            pages[page] = { swap = swap, slot = slot }
        end
    end

    local overlay = overlays[button]
    if not overlay and not next(pages) then
        return
    end
    overlay = overlay or CreateOverlay(button)

    local keys = next(pages) and Buttons:GetKeys(button) or {}
    local signature = Signature(pages, keys)
    if configs[overlay] and configs[overlay].signature == signature then
        return
    end
    configs[overlay] = { signature = signature, pages = pages, attributes = WriteAttributes(overlay, pages, keys) }

    if not driven[overlay] then
        driven[overlay] = true
        RegisterStateDriver(overlay, "page", Buttons:GetPageDriver(entry))
    end
    overlay:Execute(REAPPLY)
end

-- Gives every key back and hides every overlay (out of combat).
local function ReleaseAll()
    for _, overlay in pairs(overlays) do
        if driven[overlay] then
            driven[overlay] = nil
            UnregisterStateDriver(overlay, "page")
        end
        WriteAttributes(overlay, {}, {})
        configs[overlay] = nil
        ClearOverrideBindings(overlay)
        overlay:Hide()
    end
end

local function Rebuild()
    scheduled = false
    if not Swaps:IsActive() then
        return
    end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    for _, entry in ipairs(Buttons:Enumerate()) do
        Configure(entry)
    end
end

-- Many slots change at once (login, a new spec of bars): one rebuild a frame.
local function ScheduleRebuild()
    if not scheduled then
        scheduled = true
        C_Timer.After(0, Rebuild)
    end
end

local listener = ns:CreateEventListener({
    ACTIONBAR_SLOT_CHANGED = ScheduleRebuild,
    -- Also fired by our own click bindings: unchanged overlays are skipped.
    UPDATE_BINDINGS = ScheduleRebuild,
    SPELLS_CHANGED = ScheduleRebuild,
    PLAYER_REGEN_ENABLED = function()
        if pending then
            Rebuild()
        end
    end,
})

-- Turned off in combat: the keys go back once it ends.
local releaseListener = ns:CreateEventListener({
    PLAYER_REGEN_ENABLED = function(self)
        self:Stop()
        if not Swaps:IsActive() then
            ReleaseAll()
        end
    end,
})

function Overlays:Enable()
    listener:Start()
    Rebuild()
end

function Overlays:Refresh()
    Rebuild()
end

function Overlays:Disable()
    listener:Stop()
    pending = false
    if InCombatLockdown() then
        releaseListener:Start()
    else
        ReleaseAll()
    end
end
