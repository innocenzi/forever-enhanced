# AGENTS.md

Forever Enhanced: a World of Warcraft Forever addon of small, independent quality-of-life modules that keep the default UI recognizable.

## Runtime

- Target: WoW Forever client, `## Interface: 16001`, Lua 5.1 (WoW's embedded runtime). Check API availability for this client; do not assume retail or Classic APIs exist.
- Addon folder name must be `ForeverEnhanced`. The repo is junctioned into `D:\Games\Blizzard\World of Warcraft\_forever_\Interface\AddOns\ForeverEnhanced`, so edits are live after `/reload`.
- `ForeverEnhanced.toc` defines load order. Add every new runtime file there, after its dependencies.
- `core/addon.lua` creates the shared namespace (`_G.ForeverEnhanced`, also the second vararg `...` in every file).
- Player-facing strings must support `enUS` and `frFR` (correct French accents).
- Forever loads the retail UI (game type `camelot`, mainline family). Blizzard's source for this client is the `forever` branch of `Gethe/wow-ui-source`: check APIs and frame internals there.

## Architecture

- **Module**: a group of features, one settings subcategory. `ns:RegisterModule(id, { order })`.
- **Feature**: a vertical slice in `modules/<module>/<feature>/`. `ns:RegisterFeature(module, id, { order, settings })` in the slice's `feature.lua`, loaded first; the other slice files get it with `ns:GetFeature(module, id)` and attach their component tables to it.
- A feature is active only when the player has logged in, its module is enabled and the feature is enabled. Core calls `OnEnable` / `OnDisable` on every transition and `OnSettingChanged(key, value)` while active. Features must fully undo themselves in `OnDisable` (events, visible UI).
- `hooksecurefunc` and tooltip post-calls can't be removed: install them once on first enable, and check `feature:IsActive()` first thing in the body.
- Features never reach into each other; cross-feature calls go through a small public API on the feature object (e.g. `Locking:IsLocked(itemLocation)`).
- Settings are data: each `settings` entry is `{ key, type = "toggle", default }` or `{ key, type = "dropdown", default, options = { ... } }`. `core/settings.lua` generates the Options > AddOns panel with the Blizzard vertical layout API; features never call the Settings API. Add a widget type by adding an entry to its `controls` table.
- Saved variables: `feature.db` (account, derived from the schema; unknown keys are dropped) and `feature:GetCharacterStore()` (per character, feature-owned).
- Locale keys: `<module>.title`, `<module>.description`, `<module>.<feature>.title|description|<key>|<key>.tooltip|<key>.<option>`, plus any feature strings under `<module>.<feature>.`. Each slice registers its own strings with `ns:RegisterLocale`. The settings list truncates labels past about 30 characters (in every locale): keep labels short and put details in the `.tooltip`.
- Events: `ns.CreateEventListener({ EVENT = function(listener, ...) end })`, then `:Start()` / `:Stop()` with the feature lifecycle.

## Lua style

- File-local state; nothing global besides the namespace and saved variables.
- Never implement slash commands: they share one global namespace and conflict between addons. Settings live only in the Options > AddOns panel.
- Never stamp fields onto Blizzard frames: keep per-frame state in a weak-keyed local table.
- Never wrap, replace or call Blizzard's item-use paths (`ContainerFrameItemButton_*`, `C_Container.UseContainerItem`) from addon code: it taints. Intercept with our own frames laid over theirs, and undo actions after the fact (e.g. `ClearCursor()`).
- Don't guard APIs that exist on this client; only nil-check load-on-demand frames (e.g. `AuctionHouseFrame`).
- Format with StyLua (`bun run format`); `bun run lint` checks formatting and Lua 5.1 syntax.

## Tooling

Bun scripts: `bun run format` / `bun run lint` (StyLua, Lua 5.1 syntax), `bun run changelog` (git-cliff → `CHANGELOG.md`), `bun run release` (bumpp: bumps `package.json` and the TOC `## Version`, regenerates the changelog, commits, tags, pushes).

## Packaging

CurseForge packages via `.pkgmeta` (no Bun step). When adding runtime assets or dev-only files, update the `.pkgmeta` ignore list so the zip contains only `ForeverEnhanced/` runtime files.

## Commits

Conventional commits. Types: `feat`, `perf`, `fix`, `refactor`, `chore` only. Scope: the module name, or `core`. Subject describes the behavior change, not the implementation.

## Docs

`README.md` is for players. Keep implementation notes here.
