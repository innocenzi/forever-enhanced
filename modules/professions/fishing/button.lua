-- The secure button the fishing key clicks (its click binding is in
-- Bindings.xml), casting Fishing on key down. Out of combat, its pre-click
-- picks what the press does: equip the pole (no cast, as the pole lands after
-- the press) or cast. Its post-click sets it back to casting, which it does in
-- combat, when its attributes can't change. Created on the first enable out
-- of combat, never shown: a click binding needs no visible button.

local _, ns = ...

local Fishing = ns:GetFeature("professions", "fishing")

local Button = {}
Fishing.Button = Button

local button

local function PreClick(self)
    if InCombatLockdown() or not Fishing:IsActive() or not Fishing.Gear:ShouldEquipPole() then
        return
    end
    self:SetAttribute("type", nil)
    Fishing.Gear:EquipPole()
    Fishing.Session:Touch()
end

local function PostClick(self)
    if not InCombatLockdown() and Fishing:IsActive() then
        self:SetAttribute("type", "spell")
    end
end

local combatListener

-- Casting while the feature is active, nothing otherwise.
local function Sync()
    if InCombatLockdown() then
        combatListener:Start()
        return
    end
    combatListener:Stop()
    if not button then
        if not Fishing:IsActive() then
            return
        end
        button = CreateFrame("Button", Fishing.BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
        button:RegisterForClicks("LeftButtonDown")
        button:SetAttribute("useOnKeyDown", true)
        button:SetScript("PreClick", PreClick)
        button:SetScript("PostClick", PostClick)
    end
    button:SetAttribute("spell", Fishing:GetSpellName())
    button:SetAttribute("type", Fishing:IsActive() and "spell" or nil)
end

combatListener = ns:CreateEventListener({
    PLAYER_REGEN_ENABLED = Sync,
})

function Button:Enable()
    Sync()
end

function Button:Disable()
    Sync()
end

-- The key binding's name, in the player's language once it's known.
ns:CreateEventListener({
    PLAYER_LOGIN = function(listener)
        listener:Unregister("PLAYER_LOGIN")
        _G["BINDING_NAME_" .. Fishing.BINDING] = ns.L["professions.fishing.binding"]
    end,
}):Start()
