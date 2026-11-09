# AGENTS.md

Forever Enhanced: a World of Warcraft Forever addon of small, independent quality-of-life modules that keep the default UI recognizable.

## Runtime

- Target: WoW Forever client, `## Interface: 16001`, Lua 5.1 (WoW's embedded runtime). Check API availability for this client; do not assume retail or Classic APIs exist.
- Addon folder name must be `ForeverEnhanced`. The repo is junctioned into `D:\Games\Blizzard\World of Warcraft\_forever_\Interface\AddOns\ForeverEnhanced`, so edits are live after `/reload`.
- `ForeverEnhanced.toc` defines load order. Add every new runtime file there, after its dependencies.
- `core.lua` creates the shared namespace (`_G.ForeverEnhanced`, also the second vararg `...` in every file).
- Player-facing strings must support `enUS` and `frFR` (correct French accents).

## Tooling

Bun scripts: `bun run changelog` (git-cliff → `CHANGELOG.md`), `bun run release` (bumpp: bumps `package.json` and the TOC `## Version`, regenerates the changelog, commits, tags, pushes).

## Packaging

CurseForge packages via `.pkgmeta` (no Bun step). When adding runtime assets or dev-only files, update the `.pkgmeta` ignore list so the zip contains only `ForeverEnhanced/` runtime files.

## Commits

Conventional commits. Types: `feat`, `perf`, `fix`, `refactor`, `chore` only. Scope: the module name, or `core`. Subject describes the behavior change, not the implementation.

## Docs

`README.md` is for players. Keep implementation notes here.
