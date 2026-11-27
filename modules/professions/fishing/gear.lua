-- The fishing pole and the weapons it replaces ("swap"). Fishing poles are
-- two-handed: the pole goes in the main hand and the off hand comes off too.
-- The weapons taken off are saved per character by item GUID until they go
-- back on, across reloads and sessions. They go back main hand first, and the
-- off hand once the main hand's change lands: equipped while the two-handed
-- pole is still in hand, the off hand would take the pole off on its own.
-- Equipping weapons isn't protected: they go back on as combat starts.
-- A weapon the player put away meanwhile (sold, banked) is skipped, and
-- weapons the player equips themselves are theirs: nothing goes back then.

local _, ns = ...

local Fishing = ns:GetFeature("professions", "fishing")

local Gear = {}
Fishing.Gear = Gear

local MAIN_HAND, OFF_HAND = INVSLOT_MAINHAND, INVSLOT_OFFHAND

-- The off hand waits for the main hand to go back on.
local pendingOffHand = nil
local offHandListener -- (defined below)

local function GetStore()
    return Fishing:GetCharacterStore()
end

local function IsPole(itemID)
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == Enum.ItemClass.Weapon and subclassID == Enum.ItemWeaponSubclass.Fishingpole
end

-- Whether the main hand holds a fishing pole.
function Gear:IsPoleEquipped()
    local itemID = GetInventoryItemID("player", MAIN_HAND)
    return itemID ~= nil and IsPole(itemID)
end

local function GetEquippedGUID(slot)
    return ns.Containers:GetItemGUID(ItemLocation:CreateFromEquipmentSlot(slot))
end

-- The bag location of the best pole the character can use, or nil: the
-- highest item level, as the fishing bonus grows with it.
local function FindBestPole()
    local best, bestLevel
    ns.Containers:ForEachSlot(ns.Containers.BAG_IDS, function(bagID, slot)
        local location = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        if not C_Item.DoesItemExist(location) then
            return
        end
        local itemID = C_Item.GetItemID(location)
        if IsPole(itemID) and C_PlayerInfo.CanUseItem(itemID) then
            local level = C_Item.GetCurrentItemLevel(location) or 0
            if not best or level > bestLevel then
                best, bestLevel = location, level
            end
        end
    end)
    return best
end

-- Presses wait for the pole to land, for a second at most.
local POLE_WAIT_SECONDS = 1
local poleDueUntil = 0

local function IsPoleDue()
    return GetTime() < poleDueUntil
end

-- Whether the next press equips a pole instead of casting (or waits for it).
function Gear:ShouldEquipPole()
    if not Fishing:IsPartActive("swap") then
        return false
    end
    return IsPoleDue() or (not self:IsPoleEquipped() and FindBestPole() ~= nil)
end

-- Equips the best pole, saving the weapons it takes off.
function Gear:EquipPole()
    if IsPoleDue() then
        return
    end
    local location = FindBestPole()
    if not location then
        return
    end
    -- The main hand isn't a pole: whatever was saved before already went back
    -- on or was given up by the player.
    GetStore().weapons = { main = GetEquippedGUID(MAIN_HAND), off = GetEquippedGUID(OFF_HAND) }
    pendingOffHand = nil
    offHandListener:Stop()
    poleDueUntil = GetTime() + POLE_WAIT_SECONDS
    C_Item.EquipItemByName(C_Item.GetItemLink(location), MAIN_HAND)
end

-- Equips the weapon with this GUID in `slot` if it's in the bags.
local function Equip(guid, slot)
    local location = guid and C_Item.GetItemLocation(guid)
    if not location or not location:IsBagAndSlot() then
        return false
    end
    C_Item.EquipItemByName(C_Item.GetItemLink(location), slot)
    return true
end

-- Whether weapons wait to go back on.
function Gear:HasSavedWeapons()
    return GetStore().weapons ~= nil
end

-- The off hand, once the main hand went back on (it runs past the part's end).
offHandListener = ns:CreateEventListener({
    PLAYER_EQUIPMENT_CHANGED = function(listener, slot)
        if slot ~= MAIN_HAND then
            return
        end
        listener:Stop()
        local guid = pendingOffHand
        pendingOffHand = nil
        Equip(guid, OFF_HAND)
    end,
})

-- Puts the saved weapons back on, while the pole is still in hand. Nothing
-- once they are going back (the off hand may still wait for the main hand).
function Gear:Restore()
    local weapons = GetStore().weapons
    if not weapons then
        return
    end
    GetStore().weapons = nil
    if not self:IsPoleEquipped() then
        return
    end
    if Equip(weapons.main, MAIN_HAND) then
        if weapons.off then
            pendingOffHand = weapons.off
            offHandListener:Start()
        end
    else
        Equip(weapons.off, OFF_HAND)
    end
end

-- The pole landing, or the player taking it off themselves: the weapons stay as they are then.
local listener = ns:CreateEventListener({
    PLAYER_EQUIPMENT_CHANGED = function(_, slot)
        if slot ~= MAIN_HAND then
            return
        end
        poleDueUntil = 0
        if not pendingOffHand and Gear:HasSavedWeapons() and not Gear:IsPoleEquipped() then
            GetStore().weapons = nil
        end
    end,
})

function Gear:Enable()
    listener:Start()
    -- Taken off since the weapons were saved (the part was off, or another addon).
    if self:HasSavedWeapons() and not self:IsPoleEquipped() then
        GetStore().weapons = nil
    end
end

function Gear:Disable()
    listener:Stop()
    self:Restore()
end
