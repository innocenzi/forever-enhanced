# AGENTS.md

Forever Enhanced: a World of Warcraft Forever addon of small, independent quality-of-life modules that keep the default UI recognizable.

## Runtime

- Client: WoW Forever, `## Interface: 16001`, Lua 5.1. It loads the retail (mainline) UI, but not every retail API exists: check APIs and frame internals on the `forever` branch of `Gethe/wow-ui-source`.
- The repo is junctioned into the game's `Interface\AddOns\ForeverEnhanced` (folder name must stay `ForeverEnhanced`); edits are live after `/reload`.
- `ForeverEnhanced.toc` defines load order: add every new runtime file there, after its dependencies.
- Every file starts with `local _, ns = ...` (the shared namespace); `core/addon.lua` also exposes it as `_G.ForeverEnhanced`.

## Architecture

- **Module**: a group of features, one settings subcategory (no toggle of its own). `ns:RegisterModule(id, { order })`. Order modules, and features within a module (`order`), from the most widely useful to the most niche; settings within a feature too.
- **Feature**: a vertical slice in `modules/<module>/<feature>/`. `ns:RegisterFeature(module, id, { order, enabledByDefault, settings })` (`enabledByDefault = false` for opt-in features, e.g. ones that speak in chat) in the slice's `feature.lua`, loaded first; the other slice files get it with `ns:GetFeature(module, id)` and attach their component tables to it.
- A feature is active only when the player has logged in and the feature is enabled. Core calls `OnEnable` / `OnDisable` on every transition and `OnSettingChanged(key, value)` while active. `OnDisable` must fully undo the feature (events, visible UI).
- Related features share one feature, each behind a toggle setting (e.g. `inventory.bank`: saved bank and transfers; `quests.helpers`: nearby tracking, sparkles, tooltip objectives). A part is a table with `Enable` / `Disable`; the feature calls `self:SyncPart(key, part)` for each from `OnEnable`, `OnDisable` and `OnSettingChanged`, and the part's hooks and handlers check `feature:IsPartActive(key)` instead of `IsActive()`.
- `hooksecurefunc` can't be removed: install it once on first enable, and check `feature:IsActive()` first thing in the body.
- Item tooltip lines: `ns:AddItemTooltipHandler(feature, function(tooltip, data) end)` at file load (`core/tooltips.lua` owns the single post-call and only calls handlers of active features).
- Features never reach into each other; cross-feature calls go through a small public API on the feature object (e.g. `Locking:IsLocked(itemLocation)`).
- Settings are data: each `settings` entry is `{ key, type = "toggle", default }`, `{ key, type = "dropdown", default, options = { ... } }` or `{ key, type = "slider", default, min, max, step }` (out-of-range saved values reset to the default) or `{ key, type = "text", default }` (an edit box; blank text resets to the default). An entry without `default` takes it from the locale key `<module>.<feature>.<key>.default`, for text in the player's language. The Settings API has no edit box: the text row is our template in `core/settings.xml`, built on Blizzard's `SettingsControlMixin` with `TextControlMixin` (`core/settings.lua`). Add `requires = { otherKey = value }` (one setting) to nest an entry under an earlier one and grey it out unless that setting has that value (and its own requirement holds, up the chain). `core/settings.lua` builds the Options > AddOns panel from them; features never call the Settings API. A feature can also declare `action = key`: a button beside its checkbox (Blizzard's checkbox with button row), reading `<module>.<feature>.<key>`, usable while the feature is on, that calls `feature:OnAction(key)`; for options a list of values can't express, like the swaps editor (`combat/swaps/editor.lua`, a window over the panel). On its module's page, a feature without settings is a single checkbox named after it, at the top (under a header it would read as an option of that header's feature); any other gets a section header, an "Enable" checkbox and its settings under it. A new widget type is a new entry in its `controls` table. Every row, headers included, uses our own copy of Blizzard's template (`core/settings.xml`), never Blizzard's builders (`Settings.CreateCheckbox`, ...): the list pools row frames by template, our rows leave theirs tainted, and a Blizzard row that reuses one gets its protected calls blocked (the Discord voice option on the Audio page). Rows are added with `Settings.RegisterInitializer`, never `layout:AddInitializer`, and nested with `SetParent` (`core/settings.lua`), never `SetParentInitializer`: the settings search reads `parentInitializer` outside the rows' secure calls, so a value we wrote there taints the search and every frame it builds (the Keybindings push-to-talk button, kept for the session).
- Presets: `ns.PRESETS` (`core/presets.lua`) lists the shipped presets, picked in the root settings page. A feature declares its values per preset in `RegisterFeature`: `presets = { minimal = { enabled = true, announce = false }, enhanced = { ... } }` (`enabled` or schema keys, validated at load). Applying one (`core/presets.lua`) sets those values through the registered settings, so controls and `OnSettingChanged` follow; values it leaves out are kept. Name and tooltip: `core.presets.<id>` / `.tooltip`.
- Saved variables: `feature.db` (account, derived from the schema; unknown keys are dropped; moving a feature to another module needs an entry in `MOVED_FEATURES`, `core/database.lua`, so its settings follow), `feature:GetCharacterStore()` (per character, feature-owned) and `feature:GetAccountStore()` (account-wide, feature-owned: data one character saves for the others to read).
- Events: `ns:CreateEventListener({ EVENT = function(listener, ...) end })`, then `:Start()` / `:Stop()` with the feature lifecycle.
- Containers: `ns.Containers` (`BAG_IDS`, `ALL_CONTAINER_IDS`, `GetBankContainerIDs()`, `ForEachSlot`).
- CVars: only through `ns:CreateCVarOverride(feature)` (`core/cvars.lua`), created at file load. `:Set(name, value)` keeps the player's value (in the feature's account store, under `cvars`); `:Restore()` in `OnDisable` puts it back unless the player changed it since. It writes only on change (every write runs `CVAR_UPDATE` handlers from our tainted code) and never in combat.
- Moving items: only through `ns:CreateMover({ Plan, maxMovesPerKey })` (`core/moves.lua`), never ad-hoc pickup sequences. `Plan()` returns the moves still needed from live positions; the mover sends non-conflicting moves in rounds and waits for the server between them.

## Localization

- Every player-facing string exists in `enUS` and `frFR` (correct French accents). Each slice registers its own strings with `ns:RegisterLocale`.
- The player picks the addon's language in Options (`ForeverEnhancedDB.language`: `"auto"` for the client's, or one of `ns.LANGUAGES`); a change applies after a reload. `ns.L` is filled only at `ADDON_LOADED` (before that every key renders as itself): never read `L` at file load, look strings up when they're shown or frames are built. A text setting still at a locale's default switches to the new language's. Game text (quest objectives, item names) stays in the client's language: parse it by `GetLocale()`.
- Adding a language: append it to `ns.LANGUAGES` and its native name in `core/locale.lua`, and to `LOCALES` in `tests/run.lua`.
- Keys: `<module>.title`, `<module>.<feature>.title|description|<key>|<key>.tooltip|<key>.<option>|<key>.format|<key>.default` (`.format`: a slider's value label, e.g. `"%d yd"`, the plain number otherwise; `.default`: the default of an entry without one), plus any feature strings under `<module>.<feature>.`.
- The settings list truncates labels past about 30 characters: keep labels short (the title of a feature without settings is a label too) and put details in the `.tooltip`.
- Write like Blizzard's own GlobalStrings (reuse their wording when a game string exists: "Sell All Junk Items", "Clean Up Bags", "Dépôt", "Ranger les sacs").
- Keep it short: one sentence per tooltip when possible. Say what the player gets, never how it works or edge cases they won't notice; don't repeat the label, or in a tooltip what the description already says.
  - enUS: sentence case everywhere, including titles, setting labels, dropdown options and menu entries ("Lock indicator", "Fill existing stacks"); only proper nouns and Blizzard button names keep their capitals ("Questie", "Sell All Junk Items"); tooltips are sentences starting with a third-person verb ("Shows…", "Controls…"); "When disabled, …" for the off state, only when it isn't obvious; confirmations open with "Are you sure you want to…?"; clicks are written "Alt Left Click", "Right Click"; tooltip value lines are `Label: %d`.
  - frFR: sentence case, infinitive labels ("Ouvrir avec les sacs"); tooltips start with a third-person verb ("Affiche…", "Contrôle…"); "Si cette option est désactivée, …"; confirmations "Voulez-vous vraiment… ?"; clicks "Alt-clic gauche", "clic droit"; typographic apostrophe `’`, and a no-break space (U+00A0) before `: ? ! ;` and inside `« »`.
- Plurals: WoW's `|4singular:plural;` markup right after the number (`"%d |4item:items;"`); the client picks the form per language. It reads the number immediately before the token (no color code in between), so put every word that agrees with the count inside the token, after the number (`"%d |4objet sera conservé:objets seront conservés;"`).

## Lua style

- File-local state; nothing global besides the namespace, saved variables and XML template names (prefixed `ForeverEnhanced`; their scripts reach Lua through `ForeverEnhanced`). Secure buttons that take keys through click bindings need a name too (`ForeverEnhancedSwapButton<n>`, `combat/swaps/overlays.lua`). One more exception: a window that must behave like a Blizzard panel (`RegisterUIPanel`, `UISpecialFrames` for Escape) needs a frame name, prefixed `ForeverEnhanced` (e.g. `ForeverEnhancedSavedBankFrame`). The panel manager does nothing in combat, so show and hide it directly when `ShowUIPanel` / `HideUIPanel` didn't. A dialog Blizzard's generic ones can't express gets its own `StaticPopupDialogs` entry, keyed `FOREVER_ENHANCED_<NAME>` (e.g. the item note in `locking/notes.lua`); prefer `StaticPopup_ShowCustomGenericConfirmation` / `StaticPopup_ShowCustomGenericInputBox` otherwise.
- Functions on the namespace and on feature or component tables are always called with a colon (`ns:Print`, `Locking:IsLocked`), whether or not they use `self`. Dot calls are for plain data records (e.g. the `sources` entries in `buttons.lua`) and Blizzard APIs.
- Never implement slash commands (one global namespace shared by all addons); settings live only in the Options > AddOns panel. The one exception is TomTom's `/way`, `/wayb` and `/cway` (`map/way/commands.lua`), which players paste from guides: registered on enable only when no other addon owns the command, under `SLASH_FOREVERENHANCED_*` / `SlashCmdList.FOREVERENHANCED_*`, and removed on disable from `SlashCmdList`, its proxy table, the `SLASH_*` globals and `hash_SlashCmdList`.
- Never stamp fields onto Blizzard frames: keep per-frame state in a weak-keyed local table.
- Never wrap, replace or replay Blizzard's item-use paths (`ContainerFrameItemButton_*`, their click handlers): it taints item use. Intercept with our own frames laid over theirs, and undo actions after the fact (e.g. `ClearCursor()`). `C_Container.UseContainerItem` is allowed only for an explicit, user-confirmed action with no protected effect, like selling at an open merchant (`locking/junk.lua`, and `merchant/junk.lua` once the player turned on auto selling), never to stand in for a player's click.
- What a button casts in combat can only change through secure code (restricted snippets, state drivers on macro conditions), which can't read auras or spell usability, and a macro stops at its first refused cast. `combat.swaps` works around both by casting on key down and on key up (`pressAndHoldAction`, `downbutton`, `typerelease`): two hardware events, the game refusing whichever can't be cast. So its condition is fixed ("while the replacement can be cast"); the pairs are each character's, in its character store.
- Don't guard APIs that exist on this client; only nil-check load-on-demand frames (e.g. `AuctionHouseFrame`).

## Tooling

- `bun run format` / `bun run lint`: StyLua (Lua 5.1 syntax). Run both before committing.
- `bun run test`: see Tests. `bun run typecheck`: the TypeScript in `tools/`.
- `bun run icon`: renders `tools/icon/icon.svg` → `media/icon.tga` (TOC `## IconTexture`) and `tools/icon/logo.svg` → `tools/icon/logo.png`. Edit the SVGs, rerun, commit the outputs.
- `bun run release` (bumps versions, regenerates `CHANGELOG.md` with git-cliff, commits, tags, pushes) is the maintainer's: don't run it unasked.

## Tests

`bun run test` runs `tests/run.lua` with a Lua 5.2+ CLI (for per-test environments; addon code stays 5.1). Every test boots a fresh fake client (`tests/wow.lua`), loads the addon in TOC order, logs in, and runs once per locale.

- Add tests to the matching `tests/<area>_test.lua` (or a new file listed in `TEST_FILES` in `run.lua`) with `test(name, function(world) ... end)`, `expect` and `equal`. Test files see the fake client's globals directly (`C_Container`, `MerchantFrame`, ...).
- Drive and inspect the client through `world` (`world:AltClick(slot)`, `world:Fire(event)`, `world:Elapse(seconds)`, `world:Bag()`, `world:Indicator(slot)`, ...). Extend `tests/wow.lua` when a feature uses an API it lacks.
- Compare player-facing text through `world.L[...]`, never literal strings.
- The fake client models behaviors measured in game (e.g. a sort lands in one `BAG_UPDATE_DELAYED`, slots unlock before positions update). Keep it faithful to the real client, and tell the user what to check in game when a change depends on client behavior.

## Packaging

The BigWigs packager builds the zip from `.pkgmeta`. When adding dev-only files or folders, add them to its ignore list so the zip contains only runtime files.

`.github/workflows/ci.yml` runs lint, tests and typecheck on every push and pull request. On a `v*` tag (pushed by `bun run release`) it also packages the addon and uploads it to CurseForge (project `1795191`, `CF_API_KEY` repository secret) and to GitHub Releases, with that release's git-cliff notes as the changelog.

## Commits

Conventional commits. Types: `feat`, `perf`, `fix`, `refactor`, `chore` only. Scope: the module name, or `core`. Subject describes the behavior change, not the implementation.

## Docs

`README.md` is for players: update it when player-visible behavior changes. Implementation notes go here.
