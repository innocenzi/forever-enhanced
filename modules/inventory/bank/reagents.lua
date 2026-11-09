-- Marks recipe reagent slots (professions window, recipe inspection) when the
-- bags are short of a reagent and this character's saved bank makes up the
-- difference, so a bank trip would let the player craft. The "reagentMark"
-- setting picks the mark:
--   line:  a gold "4 in the bank" line under the reagent name
--   icon:  a banker icon over the icon's top-right corner
--   count: the bank count in gold, in the icon's bottom-left corner
--
-- Reagent slots come from Blizzard_ProfessionsTemplates (load-on-demand), from
-- frame pools created on the first recipe shown. ProfessionsReagentSlotMixin is
-- copied into each slot when it is created, so hooking its Update once the
-- templates load reaches every slot; slots another addon created earlier get no
-- mark. Update runs on every fill (also when items finish loading), reagent
-- change and bag update, and rewrites the name first. Slots are reused across
-- recipes, so each update sets the mark either way.

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

local Reagents = {}
Bank.Reagents = Reagents

local TEMPLATES_ADDON = "Blizzard_ProfessionsTemplates"
local BANKER_ICON = "Interface\\Minimap\\Tracking\\Banker"
local ICON_SIZE = 18

-- Per Blizzard reagent slot we have seen: our decoration ({ frame, icon, count,
-- nameBase, nameWithLine }), false until a mark was needed.
-- Weak keys: we never stamp fields onto Blizzard frames.
local decorations = setmetatable({}, { __mode = "k" })
local hookInstalled = false

-- Total of the slot's reagent items (quality tiers are several items), by countItem(itemID).
local function CountReagent(schematic, countItem)
    local total = 0
    for _, reagent in ipairs(schematic.reagents) do
        if reagent.itemID then -- currency reagents have none
            total = total + countItem(reagent.itemID)
        end
    end
    return total
end

-- How many the saved bank holds, when the bags are short of the reagent and
-- the bank makes up the difference; nil otherwise.
local function GetBankSupply(slot)
    local schematic = slot:GetReagentSlotSchematic()
    if not schematic or schematic.reagentType ~= Enum.CraftingReagentType.Basic then
        return nil
    end
    local need = schematic.quantityRequired
    local inBags = CountReagent(schematic, function(itemID)
        return C_Item.GetItemCount(itemID)
    end)
    if inBags >= need then
        return nil
    end
    local playerKey = Bank.Store:GetPlayerKey()
    local inBank = CountReagent(schematic, function(itemID)
        return Bank.Store:CountItem(playerKey, itemID)
    end)
    if inBags + inBank >= need then
        return inBank
    end
end

local function CreateDecoration(slot)
    local button = slot.Button
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints()
    frame:SetFrameLevel(button:GetFrameLevel() + 1)

    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(BANKER_ICON)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPRIGHT", 5, 5)

    local count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMLEFT", 3, 2)
    count:SetTextColor(NORMAL_FONT_COLOR:GetRGB())

    return { frame = frame, icon = icon, count = count }
end

-- Adds (line) or removes (nil) our line under the reagent name. Blizzard rewrites
-- the name on every update; only a name we still own is put back.
local function SetNameLine(slot, decoration, line)
    if decoration.nameBase then
        if slot.Name:GetText() == decoration.nameWithLine then
            slot.Name:SetText(decoration.nameBase)
        end
        decoration.nameBase, decoration.nameWithLine = nil, nil
    end
    if line then
        decoration.nameBase = slot.Name:GetText()
        decoration.nameWithLine = decoration.nameBase .. "\n" .. line
        slot.Name:SetText(decoration.nameWithLine)
    end
end

local function UpdateSlot(slot)
    local style = Bank:IsActive() and not slot:IsLoading() and Bank:GetSetting("reagentMark") or "none"
    local inBank = style ~= "none" and GetBankSupply(slot) or nil
    if not inBank then
        style = "none"
    end

    local decoration = decorations[slot]
    if not decoration and style ~= "none" then
        decoration = CreateDecoration(slot)
    end
    decorations[slot] = decoration or false
    if not decoration then
        return
    end

    decoration.frame:SetShown(style == "icon" or style == "count")
    decoration.icon:SetShown(style == "icon")
    decoration.count:SetShown(style == "count")
    decoration.count:SetText(inBank or "")
    SetNameLine(slot, decoration, style == "line" and Bank:FormatCount(inBank) or nil)
end

-- hooksecurefunc hooks can't be removed: install once, UpdateSlot checks IsActive().
local function InstallHook()
    if not hookInstalled then
        hookInstalled = true
        hooksecurefunc(ProfessionsReagentSlotMixin, "Update", UpdateSlot)
    end
end

local listener = ns:CreateEventListener({
    ADDON_LOADED = function(self, addonName)
        if addonName == TEMPLATES_ADDON then
            self:Stop()
            InstallHook()
        end
    end,
})

-- Re-marks every slot seen so far (after a setting or lifecycle change).
function Reagents:Refresh()
    for slot in pairs(decorations) do
        UpdateSlot(slot)
    end
end

function Reagents:Enable()
    if C_AddOns.IsAddOnLoaded(TEMPLATES_ADDON) then
        InstallHook()
    elseif not hookInstalled then
        listener:Start()
    end
    self:Refresh()
end

function Reagents:Disable()
    listener:Stop()
    self:Refresh()
end
