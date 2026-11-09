# AGENTS.md

This file is for Codex and other coding agents working on Forever Enhanced.

## Project Overview

Forever Enhanced is a standalone World of Warcraft Forever addon (successor to Vanilla Enhanced). It keeps the Blizzard UI recognizable while adding small, independent utility modules.

No modules exist yet; this is the base scaffolding.

## Runtime Layout

The addon folder must be named `ForeverEnhanced`. During development, `D:\Games\Blizzard\World of Warcraft\_forever_\Interface\AddOns\ForeverEnhanced` is a directory symlink to this repository.

Important files:

- `ForeverEnhanced.toc`: TOC and load order (`## Interface: 16001`).
- `core.lua`: global addon table, module registration, saved-variable helpers, chat output.
- `src/localization.lua`: addon UI strings, `ForeverEnhanced:T` and `ForeverEnhanced:RegisterStrings`.
- `src/init.lua`: `ADDON_LOADED` bootstrap, module initialization, `/fe` slash command. Must stay last in the TOC.
- `media/*`: runtime textures and sounds.

Keep the TOC load order in sync with dependencies. `core.lua` and `src/localization.lua` must load before modules; `src/init.lua` loads after all modules.

## Modules

Create a module with `ForeverEnhanced:CreateModule(key, displayName)` in `src/<module-key>/module.lua`. The bootstrap calls, in order:

- `module:Initialize()` once, after saved variables are available.
- `module:SetEnabled(enabled)` with the stored enabled state.

Optional hooks: `module:IsEnabled()`, `module:ResetSettings()`. Store settings via `ForeverEnhanced:GetModuleSettings(key, defaults)` (account-wide) or `ForeverEnhanced:GetCharacterModuleSettings(key, defaults)` (per character).

## Development Commands

Requires Bun and Git.

```powershell
bun install
bun test
bun run changelog
bun run release
```

`bun run changelog` regenerates `CHANGELOG.md` with the npm `git-cliff` package.

`bun run release` runs `bumpp`. It bumps `package.json`, updates the TOC version, regenerates `CHANGELOG.md`, creates a release commit, tags it, and pushes by default.

CurseForge automatic packaging uses `.pkgmeta` and does not run Bun scripts.

## Commit Guidelines

Use conventional commits with one of these types only: `feat`, `perf`, `fix`, `refactor`, or `chore`. The commit scope must be the module being worked on, or `core` if none apply. The commit subject should describe the feature or behavior being changed, not the technical implementation details.

## Packaging Rules

CurseForge expects a WoW addon zip with exactly one root folder and no version number in that folder name:

```text
ForeverEnhanced/
  ForeverEnhanced.toc
  core.lua
  src/
  media/
  README.md
  CHANGELOG.md
```

Do not package development-only files such as `.git`, `.agents`, `.release`, `node_modules`, or `tools`. `.pkgmeta` mirrors those rules; update it and the TOC when runtime assets are added.

## Coding Guidelines

- Target the WoW Forever client (`## Interface: 16001`) and its embedded Lua 5.1 runtime.
- Prefer existing helpers on `_G.ForeverEnhanced` for settings, modules, printing, and localization.
- Keep modules independent where practical. Shared behavior belongs in `core.lua` only when it is genuinely common.
- Localize player-facing strings (`enUS` and `frFR`). Use proper French spelling with accents.
- When changing runtime behavior, check the TOC load order and SavedVariables defaults.
- The GitHub README is meant for humans. Keep implementation notes here rather than in `README.md`.
