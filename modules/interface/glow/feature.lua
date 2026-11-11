-- Glow on Nearest Object: makes the herb, ore vein, quest object (or any other
-- object) the Interact Key would act on glow, out of combat. Addons can't see
-- world objects, but the game's soft target picks one around the player and
-- can give it a nameplate, which the glow hangs on. One object at a time.
-- Side effect, from the game: with soft targeting on, helpful spells cast with
-- no target land on a nearby NPC or player instead of on you.
--
-- Files of this slice:
--   feature.lua  registration, object categories, schema and lifecycle (this file)
--   locales.lua  strings
--   cvars.lua    the soft targeting CVars, and the nameplate and icon on the soft target
--   effect.lua   the glow, drawn on the soft target's nameplate
--   target.lua   follows the soft target: what it is, its reach, its nameplate

local _, ns = ...

-- Kinds of objects, each with its own setting and color. An object's kind
-- comes from the cursor it shows on mouseover: Interface\Cursor\<name> (or
-- "Unable<name>" when it can't be used now), or an atlas or path holding
-- `keyword`. Objects of an active quest count as quest objects whatever their
-- cursor; anything unknown is "other".
local CATEGORIES = {
    { key = "herbs", cursors = { "GatherHerbs" }, keyword = "herb", color = { 0.45, 1, 0.4 } },
    { key = "ore", cursors = { "Mine" }, keyword = "mine", color = { 1, 0.6, 0.25 } },
    {
        key = "quest",
        cursors = { "Quest", "QuestRepeatable", "QuestTurnIn" },
        keyword = "quest",
        color = { 1, 0.85, 0.3 },
    },
    {
        key = "other",
        cursors = { "Interact", "LootAll", "PickLock", "Pickup" },
        color = { 0.75, 0.9, 1 },
        off = true,
    },
}

local settings = {}
for _, category in ipairs(CATEGORIES) do
    table.insert(settings, { key = category.key, type = "toggle", default = not category.off })
end
-- The game's interaction icon (e.g. the herb or pickaxe) above glowing objects.
table.insert(settings, { key = "icon", type = "toggle", default = true })
-- The game drops soft targets past about 15 yards, whatever the CVar says.
table.insert(settings, { key = "range", type = "slider", default = 15, min = 5, max = 15, step = 1 })

local ObjectGlow = ns:RegisterFeature("interface", "glow", {
    order = 2,
    -- It changes the game's targeting (see above): the player opts in.
    enabledByDefault = false,
    settings = settings,
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true },
    },
})

ObjectGlow.CATEGORIES = CATEGORIES

function ObjectGlow:OnEnable()
    self.CVars:Apply()
    self.Target:Enable()
end

function ObjectGlow:OnDisable()
    self.Target:Disable()
    self.CVars:Restore()
end

function ObjectGlow:OnSettingChanged(key)
    if key == "range" then
        self.CVars:Apply()
    else
        self.Target:Refresh()
    end
end
