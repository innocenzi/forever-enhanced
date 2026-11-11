-- Spell Rank Upgrades: learning a new rank of a spell puts it in place of
-- every older rank of that spell on the action bars (ranks share their name).
-- Trainers teach ranks in order, so the learned spell is the highest rank.
-- Action slots can't change in combat: spells learned then wait for it to end.
--
-- Files of this slice:
--   feature.lua  registration, lifecycle and the upgrade (this file)
--   locales.lua  strings

local _, ns = ...

local Ranks = ns:RegisterFeature("interface", "ranks", {
    order = 5,
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

-- Every action slot, the bars of every page included.
local NUM_ACTION_SLOTS = 180

-- Spells learned in combat, upgraded once it ends.
local pending = {}

local function Upgrade(spellID)
    local name = C_Spell.GetSpellName(spellID)
    if not name then
        return
    end
    for slot = 1, NUM_ACTION_SLOTS do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id ~= spellID and C_Spell.GetSpellName(id) == name then
            C_Spell.PickupSpell(spellID)
            PlaceAction(slot)
            -- The older rank came back on the cursor.
            ClearCursor()
        end
    end
end

local function UpgradePending()
    if InCombatLockdown() then
        return
    end
    for _, spellID in ipairs(pending) do
        Upgrade(spellID)
    end
    pending = {}
end

local listener = ns:CreateEventListener({
    LEARNED_SPELL_IN_SKILL_LINE = function(_, spellID)
        table.insert(pending, spellID)
        UpgradePending()
    end,
    PLAYER_REGEN_ENABLED = UpgradePending,
})

function Ranks:OnEnable()
    listener:Start()
end

function Ranks:OnDisable()
    listener:Stop()
    pending = {}
end
