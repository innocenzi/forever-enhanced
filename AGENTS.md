# AGENTS.md

Forever Enhanced: a World of Warcraft Forever addon of small, independent quality-of-life modules that keep the default UI recognizable.

## Runtime

- Client: WoW Forever, `## Interface: 16001`, Lua 5.1. It loads the retail (mainline) UI, but not every retail API exists: check APIs and frame internals on the `forever` branch of `Gethe/wow-ui-source`.
- The repo is junctioned into the game's `Interface\AddOns\ForeverEnhanced` (folder name must stay `ForeverEnhanced`); edits are live after `/reload`.
- `ForeverEnhanced.toc` defines load order: add every new runtime file there, after its dependencies.
- Every file starts with `local _, ns = ...` (the shared namespace); `core/addon.lua` also exposes it as `_G.ForeverEnhanced`.

## Architecture

- **Module**: a group of features, one settings subcategory. `ns:RegisterModule(id, { order })`.
- **Feature**: a vertical slice in `modules/<module>/<feature>/`. `ns:RegisterFeature(module, id, { order, settings })` in the slice's `feature.lua`, loaded first; the other slice files get it with `ns:GetFeature(module, id)` and attach their component tables to it.
- A feature is active only when the player has logged in, its module is enabled and the feature is enabled. Core calls `OnEnable` / `OnDisable` on every transition and `OnSettingChanged(key, value)` while active. `OnDisable` must fully undo the feature (events, visible UI).
- `hooksecurefunc` and tooltip post-calls can't be removed: install them once on first enable, and check `feature:IsActive()` first thing in the body.
- Features never reach into each other; cross-feature calls go through a small public API on the feature object (e.g. `Locking:IsLocked(itemLocation)`).
- Settings are data: each `settings` entry is `{ key, type = "toggle", default }`, `{ key, type = "dropdown", default, options = { ... } }` or `{ key, type = "slider", default, min, max, step }` (out-of-range saved values reset to the default). Add `requires = { otherKey = value }` (one setting) to nest an entry under an earlier one and grey it out unless that setting has that value. `core/settings.lua` builds the Options > AddOns panel from them; features never call the Settings API. A new widget type is a new entry in its `controls` table.
- Saved variables: `feature.db` (account, derived from the schema; unknown keys are dropped), `feature:GetCharacterStore()` (per character, feature-owned) and `feature:GetAccountStore()` (account-wide, feature-owned: data one character saves for the others to read).
- Events: `ns:CreateEventListener({ EVENT = function(listener, ...) end })`, then `:Start()` / `:Stop()` with the feature lifecycle.
- Containers: `ns.Containers` (`BAG_IDS`, `ALL_CONTAINER_IDS`, `GetBankContainerIDs()`, `ForEachSlot`).
- Moving items: only through `ns:CreateMover({ Plan, maxMovesPerKey })` (`core/moves.lua`), never ad-hoc pickup sequences. `Plan()` returns the moves still needed from live positions; the mover sends non-conflicting moves in rounds and waits for the server between them.

## Localization

- Every player-facing string exists in `enUS` and `frFR` (correct French accents). Each slice registers its own strings with `ns:RegisterLocale`.
- Keys: `<module>.title`, `<module>.description`, `<module>.<feature>.title|description|<key>|<key>.tooltip|<key>.<option>|<key>.format` (a slider's value label, e.g. `"%d yd"`; the plain number otherwise), plus any feature strings under `<module>.<feature>.`.
- The settings list truncates labels past about 30 characters: keep labels short and put details in the `.tooltip`.
- Plurals: WoW's `|4singular:plural;` markup right after the number (`"%d |4item:items;"`); the client picks the form per language. It reads the number immediately before the token (no color code in between), so put every word that agrees with the count inside the token, after the number (`"%d |4objet sera conservé:objets seront conservés;"`).

## Lua style

- File-local state; nothing global besides the namespace and saved variables. One exception: a window that must behave like a Blizzard panel (`RegisterUIPanel`, `UISpecialFrames` for Escape) needs a frame name, prefixed `ForeverEnhanced` (e.g. `ForeverEnhancedSavedBankFrame`). The panel manager does nothing in combat, so show and hide it directly when `ShowUIPanel` / `HideUIPanel` didn't.
- Functions on the namespace and on feature or component tables are always called with a colon (`ns:Print`, `Locking:IsLocked`), whether or not they use `self`. Dot calls are for plain data records (e.g. the `sources` entries in `buttons.lua`) and Blizzard APIs.
- Never implement slash commands (one global namespace shared by all addons); settings live only in the Options > AddOns panel.
- Never stamp fields onto Blizzard frames: keep per-frame state in a weak-keyed local table.
- Never wrap, replace or replay Blizzard's item-use paths (`ContainerFrameItemButton_*`, their click handlers): it taints item use. Intercept with our own frames laid over theirs, and undo actions after the fact (e.g. `ClearCursor()`). `C_Container.UseContainerItem` is allowed only for an explicit, user-confirmed action with no protected effect, like selling at an open merchant (`junk.lua`), never to stand in for a player's click.
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

CurseForge packages from `.pkgmeta`. When adding dev-only files or folders, add them to its ignore list so the zip contains only runtime files.

## Commits

Conventional commits. Types: `feat`, `perf`, `fix`, `refactor`, `chore` only. Scope: the module name, or `core`. Subject describes the behavior change, not the implementation.

## Docs

`README.md` is for players: update it when player-visible behavior changes. Implementation notes go here.
