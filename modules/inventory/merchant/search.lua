-- The "search" part: a search box on the merchant's items (not the buyback
-- tab). Our own overlays dim the items that don't match, a glow over the page
-- arrows points to matches on other pages, and typing shows the first page
-- holding a match.
--
-- Showing another page means writing MerchantFrame.page from our code, which
-- taints the rest of that visit's purchase path (Blizzard's refresh of the
-- item buttons, their confirmation popups). Nothing there is protected; it's
-- only done when the page shown holds no match, and Blizzard writes the page
-- afresh when the next merchant opens. Blizzard's frames are otherwise only read.

local _, ns = ...

local Merchant = ns:GetFeature("inventory", "merchant")

local Search = {}
Merchant.Search = Search

local DIM_ALPHA = 0.65
-- Above the slot's item button.
local OVERLAY_LEVEL_OFFSET = 10

-- The lowercased search text.
local needle = ""
local hooked = false

-- Our dimming overlays, by merchant slot (1 to MERCHANT_ITEMS_PER_PAGE).
local overlays = {}
-- Our glows, by page button.
local glows = {}

local function Matches(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    return ns:MatchesItemSearch(needle, info and info.name, GetMerchantItemID(index))
end

-- The merchant index of the first item on the page shown.
local function FirstIndexOnPage()
    return (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + 1
end

local function GetOverlay(slot)
    local overlay = overlays[slot]
    if not overlay then
        local item = _G["MerchantItem" .. slot]
        overlay = CreateFrame("Frame", nil, item)
        overlay:SetAllPoints()
        overlay:SetFrameLevel(item:GetFrameLevel() + OVERLAY_LEVEL_OFFSET)
        local texture = overlay:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetColorTexture(0, 0, 0, DIM_ALPHA)
        overlays[slot] = overlay
    end
    return overlay
end

local function SetGlow(button, shown)
    local glow = glows[button]
    if not glow and shown then
        glow = CreateFrame("Frame", nil, button)
        glow:SetAllPoints()
        local texture = glow:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        texture:SetBlendMode("ADD")
        glows[button] = glow
    end
    if glow then
        glow:SetShown(shown and button:IsShown() and button:IsEnabled())
    end
end

-- Whether a search filters the merchant's items right now.
local function IsSearching()
    return Merchant:IsPartActive("search")
        and needle ~= ""
        and MerchantFrame:IsShown()
        and MerchantFrame.selectedTab == 1
end

local function Clear()
    for _, overlay in pairs(overlays) do
        overlay:Hide()
    end
    for _, glow in pairs(glows) do
        glow:Hide()
    end
end

local function Refresh()
    if not IsSearching() then
        Clear()
        return
    end

    local numItems = GetMerchantNumItems()
    local first = FirstIndexOnPage()
    local last = first + MERCHANT_ITEMS_PER_PAGE - 1
    local before, after = false, false
    for index = 1, numItems do
        if index < first then
            before = before or Matches(index)
        elseif index > last then
            after = after or Matches(index)
        end
    end
    for slot = 1, MERCHANT_ITEMS_PER_PAGE do
        local index = first + slot - 1
        GetOverlay(slot):SetShown(index <= numItems and not Matches(index))
    end
    SetGlow(MerchantPrevPageButton, before)
    SetGlow(MerchantNextPageButton, after)
end

-- The page holding the first match, when the page shown holds none; nil otherwise.
local function PageToShow()
    local first = FirstIndexOnPage()
    local firstMatch
    for index = 1, GetMerchantNumItems() do
        if Matches(index) then
            if index >= first and index < first + MERCHANT_ITEMS_PER_PAGE then
                return nil
            end
            firstMatch = firstMatch or index
        end
    end
    return firstMatch and math.ceil(firstMatch / MERCHANT_ITEMS_PER_PAGE)
end

-- The search box's text changed.
function Search:SetText(text)
    text = text:lower()
    if text == needle then
        return
    end
    needle = text
    local page = IsSearching() and PageToShow()
    if page then
        MerchantFrame.page = page
        MerchantFrame_CloseStackSplitFrame()
        -- Our hook on it refreshes the view.
        MerchantFrame_Update()
        return
    end
    Refresh()
end

local listener = ns:CreateEventListener({
    -- Names of items not cached yet arrive late.
    GET_ITEM_INFO_RECEIVED = function()
        if IsSearching() then
            Refresh()
        end
    end,
    -- Each visit starts with an empty search.
    MERCHANT_CLOSED = function()
        Search.Box:Clear()
    end,
})

-- Blizzard redrew the merchant: page turns, tab clicks, stock and bag changes.
local function OnMerchantUpdate()
    if Merchant:IsPartActive("search") then
        Search.Box:Update()
        Refresh()
    end
end

function Search:Enable()
    self.Box:Create()
    if not hooked then
        hooked = true
        ns:HookSecureFunc("MerchantFrame_Update", OnMerchantUpdate)
    end
    listener:Start()
    self.Box:Update()
    Refresh()
end

function Search:Disable()
    listener:Stop()
    self.Box:Clear()
    self.Box:Update()
    Refresh()
end
