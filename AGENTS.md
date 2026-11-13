# AGENTS.md

Forever Enhanced: a World of Warcraft Forever addon of small, independent quality-of-life modules that keep the default UI recognizable.

## Runtime

- Client: WoW Forever, `## Interface: 16001`, Lua 5.1. It loads the retail (mainline) UI, but not every retail API exists: check APIs and frame internals on the `forever` branch of `Gethe/wow-ui-source`.
- The repo is junctioned into the game's `Interface\AddOns\ForeverEnhanced` (the folder name must stay `ForeverEnhanced`); edits are live after `/reload`.
- `ForeverEnhanced.toc` defines load order: add every new runtime file there, after its dependencies.
- Every file starts with `local _, ns = ...` (the shared namespace, also `_G.ForeverEnhanced`).
- Secret values (measured in game):
  - Secret: unit health always; attack power and cooldowns in combat (spell power presumably, unmeasured); `UnitGUID` for restricted units (instances), so `combat.dots` tells units apart by nameplate token there.
  - Unreadable in combat: unit auras (`GetAuraDataByIndex` errors, `GetAuraDataBySpellName` returns nothing); the combat log is restricted.
  - Readable in combat: the player's casts (`UNIT_SPELLCAST_*`), combo points, unit GUIDs (nameplates included), spell descriptions, `UNIT_COMBAT`'s action (not its amount).
  - Status bars accept secret values (`SetMinMaxValues`, `SetValue`): `combat.dots` draws over health that way. Comparing a secret value with a plain one through status bars and clipping frames (Does It Die?'s skull trick) never showed in game, with an empty or a full 10000 px bar: don't build on it without measuring first.

## Architecture

- **Module**: a group of features with one settings subcategory and no toggle of its own: `ns:RegisterModule(id, { order })`. Order modules, features within a module, and settings within a feature from most widely useful to most niche.
- **Feature**: a vertical slice in `modules/<module>/<feature>/`, registered in its `feature.lua` (loaded first) with `ns:RegisterFeature(module, id, { order, enabledByDefault, settings, presets })` (`enabledByDefault = false` for opt-in features, e.g. ones that speak in chat). Other slice files get it with `ns:GetFeature(module, id)` and attach their component tables to it.
- Lifecycle: a feature is active once the player has logged in and while it is enabled. Core calls `OnEnable` / `OnDisable` on every transition and `OnSettingChanged(key, value)` while active. `OnDisable` must fully undo the feature (events, visible UI).
- Parts: related behaviors share one feature, each behind a toggle setting (e.g. `inventory.marks`: junk, auction house and bank marks, item notes, Wowhead link). A part is a table with `Enable` / `Disable`; the feature calls `self:SyncPart(key, part)` for each from `OnEnable`, `OnDisable` and `OnSettingChanged`. The part's hooks and handlers check `feature:IsPartActive(key)` instead of `IsActive()`; a core handler (item buttons, junk) belonging to a part declares `part = key` so core calls it only while the part runs.
- `hooksecurefunc` can't be removed: install it once on first enable, and check `feature:IsActive()` (or `IsPartActive`) first thing in the body.
- Features never reach into each other; cross-feature calls go through a small public API on the feature object (e.g. `Locking:IsLocked(itemLocation)`).

### Core services

Handlers are registered at file load; core only calls those of active features (and parts).

- Item tooltips: `ns:AddItemTooltipHandler(feature, function(tooltip, data) end)` (`core/tooltips.lua`).
- Bag and bank item buttons: `ns:AddItemButtonHandler(feature, { Update, IsGuarded, OnGuardedClick, OnGuardedDrag, OnAltClick, AddMenuEntries, menuOrder })` (`core/itembuttons.lua` owns the buttons, hooks and click shield; its header documents each field and the taken `menuOrder` values). Features draw their marks in `Update` and hide them in `OnDisable`; call `ns:RefreshItemButtons()` from `OnEnable` / `OnDisable` and whenever what they draw or guard changes. Alt Right Click opens the item menu from every active handler's `AddMenuEntries`, ordered by `menuOrder` (required with it, unique, spaced by tens).
- Junk: `ns:AddJunkHandler(feature, { IsJunk, IsKept, CanSellAroundKept })`, `ns:CollectJunk()`, `ns:IsSoldAsJunk(bagID, slot)` (`core/junk.lua`, which also takes over Sell All Junk Items when features add or keep junk); call `ns:RefreshJunk()` when what a handler adds or keeps changes.
- Events: `ns:CreateEventListener({ EVENT = function(listener, ...) end })`, then `:Start()` / `:Stop()` with the feature lifecycle.
- Containers: `ns.Containers` (`BAG_IDS`, `ALL_CONTAINER_IDS`, `GetBankContainerIDs()`, `ForEachSlot`).
- CVars: only through `ns:CreateCVarOverride(feature)` (`core/cvars.lua`), created at file load. `:Set(name, value)` saves the player's value; `:Restore()` in `OnDisable` puts it back unless the player changed it since. It writes only on change (each write runs `CVAR_UPDATE` handlers from our tainted code) and never in combat.
- Moving items: only through `ns:CreateMover({ Plan, maxMovesPerKey })` (`core/moves.lua`), never ad-hoc pickup sequences. `Plan()` returns the moves still needed from live positions; the mover sends non-conflicting moves in rounds and waits for the server between them.
- Messages: only for what the player caused (an action, or an automation they turned on, usually behind an `announce` toggle). `ns:Print` (`core/messages.lua`) prints like a game system message (no addon prefix); `ns:Error` shows Blizzard's red error text for a blocked action. Features never write to chat frames themselves.
- Saved variables: `feature.db` (account-wide settings, derived from the schema; unknown keys are dropped; moving a feature to another module needs a `MOVED_FEATURES` entry in `core/database.lua`), `feature:GetCharacterStore()` (per character) and `feature:GetAccountStore()` (account-wide data one character saves for others to read).

### Settings

`core/settings.lua` builds the Options > AddOns panel from each feature's `settings`; features never call the Settings API, and the panel is the only place for settings.

- Entry types: `{ key, type = "toggle", default }`, `{ key, type = "dropdown", default, options = { ... } }`, `{ key, type = "slider", default, min, max, step }` (out-of-range saved values reset to the default), `{ key, type = "text", default }` (an edit box; blank resets to the default). Without `default`, it comes from the locale key `<module>.<feature>.<key>.default` (for text in the player's language). A new widget type is a new entry in the `controls` table.
- `requires = { otherKey = value }` (one setting) nests an entry under an earlier one and greys it out unless that setting has that value (recursively up the chain).
- `action = key` on a feature: a button beside its checkbox, labeled `<module>.<feature>.<key>`, usable while the feature is on, calling `feature:OnAction(key)`; for options a list of values can't express (e.g. the swaps editor, `combat/swaps/editor.lua`).
- Layout: a feature without settings is a single checkbox named after it, at the top of its module's page; any other gets a section header, an "Enable" checkbox and its settings.
- Taint: every row, headers included, uses our own templates in `core/settings.xml`, never Blizzard's builders (`Settings.CreateCheckbox`, ...), `layout:AddInitializer` or `SetParentInitializer`: see `core/settings.lua`.
- Presets: `ns.PRESETS` (`core/presets.lua`) lists the shipped presets, picked on the root settings page. A feature declares its values per preset: `presets = { minimal = { enabled = true, announce = false }, enhanced = { ... } }` (`enabled` or schema keys, validated at load). Applying one sets values through the registered settings (controls and `OnSettingChanged` follow) and keeps values it leaves out. Presets must be symmetric: any value one preset sets, every other sets too (only the settings of a feature a preset turns off may be omitted). Strings: `core.presets.<id>` / `.tooltip`.

## Localization

- Every player-facing string exists in `enUS` and `frFR`. Each slice registers its own strings with `ns:RegisterLocale`.
- `ns.L` is filled only at `ADDON_LOADED` (before that every key renders as itself): never read `L` at file load; look strings up when shown or when frames are built. The player picks the addon's language in Options (`ForeverEnhancedDB.language`, `"auto"` or one of `ns.LANGUAGES`), applied after a reload; text settings still at a locale default follow the new language.
- Game text (quest objectives, item names) stays in the client's language: parse it by `GetLocale()`.
- Keys: `<module>.title`, `<module>.<feature>.title|description|<key>|<key>.tooltip|<key>.<option>|<key>.format|<key>.default` (`.format`: a slider's value label, e.g. `"%d yd"`), plus any feature strings under `<module>.<feature>.`.
- Labels truncate past about 30 characters (feature titles without settings included): keep them short, details go in `.tooltip`.
- Write like Blizzard's GlobalStrings and reuse their wording when a game string exists ("Sell All Junk Items", "Clean Up Bags", "Dépôt", "Ranger les sacs").
- One sentence per tooltip when possible. Say what the player gets, never how it works or edge cases they won't notice; don't repeat the label, or what the description already says.
- enUS: sentence case everywhere (titles, labels, dropdown options, menu entries); only proper nouns and Blizzard button names keep capitals ("Questie", "Sell All Junk Items"). Tooltips start with a third-person verb ("Shows…"); "When disabled, …" only when not obvious; confirmations "Are you sure you want to…?"; clicks "Alt Left Click", "Right Click"; value lines `Label: %d`.
- frFR: correct accents, sentence case, infinitive labels ("Ouvrir avec les sacs"); tooltips start with a third-person verb ("Affiche…"); "Si cette option est désactivée, …"; confirmations "Voulez-vous vraiment… ?"; clicks "Alt-clic gauche", "clic droit"; typographic apostrophe `’`; a no-break space (U+00A0) before `: ? ! ;` and inside `« »`.
- Plurals: `|4singular:plural;` immediately after the number, with no color code between (`"%d |4item:items;"`). Put every word agreeing with the count inside the token (`"%d |4objet sera conservé:objets seront conservés;"`).

## Lua style

- File-local state. Globals only for: the namespace, saved variables, and names prefixed `ForeverEnhanced` where the game requires one: XML templates (their scripts reach Lua through `ForeverEnhanced`), secure buttons bound to keys by click bindings (`ForeverEnhancedSwapButton<n>`), and windows behaving like Blizzard panels (`RegisterUIPanel`, `UISpecialFrames`; e.g. `ForeverEnhancedSavedBankFrame`). The panel manager does nothing in combat: show or hide such a window directly when `ShowUIPanel` / `HideUIPanel` didn't.
- Dialogs: prefer `StaticPopup_ShowCustomGenericConfirmation` / `StaticPopup_ShowCustomGenericInputBox`; otherwise a `StaticPopupDialogs.FOREVER_ENHANCED_<NAME>` entry (e.g. `inventory/marks/notes.lua`).
- Call functions on the namespace and on feature or component tables with a colon (`ns:Print`, `Locking:IsLocked`), whether or not they use `self`. Dot calls are for plain data records and Blizzard APIs.
- No slash commands. The one exception is TomTom's `/way`, `/wayb`, `/cway` (`map/pin/commands.lua`): registered on enable only when no other addon owns them, under `SLASH_FOREVERENHANCED_*` / `SlashCmdList.FOREVERENHANCED_*`, and removed on disable from `SlashCmdList`, its proxy table, the `SLASH_*` globals and `hash_SlashCmdList`. The debugging skill's `/fedebug` is never committed.
- Never stamp fields onto Blizzard frames: keep per-frame state in a weak-keyed local table. The sole exception is `map.seamless` (its `feature.lua` lists what and why); don't extend it.
- Never wrap, replace or replay Blizzard's item-use paths (`ContainerFrameItemButton_*`, their click handlers): it taints item use. Lay our own frames over theirs and undo actions after the fact (e.g. `ClearCursor()`). `C_Container.UseContainerItem` only for an explicit, player-confirmed action with no protected effect (selling at an open merchant: `core/junk.lua`, `inventory/merchant/junk.lua`), never to stand in for a click.
- What a button casts in combat can only change through secure code (restricted snippets, macro-condition state drivers), which can't read auras or spell usability, and a macro stops at its first refused cast. `combat.swaps` casts on both key down and key up (two hardware events; the game refuses whichever can't be cast), so its condition is fixed: "while the replacement can be cast".
- Don't guard APIs that exist on this client; only nil-check load-on-demand frames (e.g. `AuctionHouseFrame`).

## Tooling

- `bun run format` and `bun run lint` (StyLua): run both before committing. `bun run typecheck`: the TypeScript in `tools/`. `bun run test`: see Tests.
- In-game debugging: the `debugging` skill.
- Generated files are never edited by hand: `data.lua` in `modules/professions/reagents`, `modules/professions/skillups`, `modules/quests/helpers`, `modules/map/seamless` (and its `media/`) and `modules/combat/dots`, plus `media/icon.tga` and `tools/icon/logo.png`. Regenerate them (and measure `modules/combat/dots/measured.lua`) with the `game-data` skill.
- `bun run release` is the maintainer's: never run it unasked.

## Tests

`bun run test` runs `tests/run.lua` (Lua 5.2+ CLI; addon code stays 5.1). Each test boots a fresh fake client (`tests/wow.lua`), loads the addon in TOC order, logs in, and runs once per locale.

- Add tests to the matching `tests/<area>_test.lua` (a new file goes in `TEST_FILES` in `run.lua`) with `test(name, function(world) ... end)`, `expect` and `equal`. Test files see the fake client's globals (`C_Container`, `MerchantFrame`, ...).
- Drive and inspect the client through `world` (`world:AltClick(slot)`, `world:Fire(event)`, `world:Elapse(seconds)`, `world:Bag()`, ...). Extend `tests/wow.lua` when a feature uses an API it lacks.
- Compare player-facing text through `world.L[...]`, never literal strings.
- The fake client models behaviors measured in game (e.g. a sort lands in one `BAG_UPDATE_DELAYED`, slots unlock before positions update). Keep it faithful, and tell the user what to check in game when a change depends on client behavior.

## Packaging

The BigWigs packager builds the zip from `.pkgmeta`: add new dev-only files or folders to its ignore list. CI (`.github/workflows/ci.yml`) runs lint, tests and typecheck, and on `v*` tags uploads to CurseForge and GitHub Releases.

## Commits and docs

- Conventional commits. Types: `feat`, `perf`, `fix`, `refactor`, `chore` only. Scope: the module name, or `core`. The subject describes the behavior change, not the implementation.
- Never edit `README.md` (the maintainer writes it). Implementation notes go here.
