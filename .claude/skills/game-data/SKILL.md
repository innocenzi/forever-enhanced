---
name: game-data
description: Regenerate and check Forever Enhanced's generated game data. Use when a content patch or new Forever build landed and generated data must be refreshed (`bun run professions`, `instances`, `seamless`, `dots`); when following a new damage over time spell in `combat.dots` (`FOLLOWED` in `tools/dots.ts`); when measuring or re-measuring values in `modules/combat/dots/measured.lua`; when changing a generator in `tools/`; when changing the seamless map's zone shares or masks, or bumping its OpenMap commit; or when regenerating the addon icon.
---

# Generated game data

Never edit generated files by hand: change the generator and rerun it.

| Command | Generator | Output |
| --- | --- | --- |
| `bun run professions` | `tools/professions.ts` | `modules/professions/reagents/data.lua`, `modules/professions/skillups/data.lua` |
| `bun run instances` | `tools/instances.ts` | `modules/quests/helpers/data.lua` |
| `bun run seamless` | `tools/seamless.ts` | `modules/map/seamless/data.lua`, `modules/map/seamless/media/` |
| `bun run dots` | `tools/dots.ts` | `modules/combat/dots/data.lua` |
| `bun run icon` | `tools/icon.ts` | `media/icon.tga`, `tools/icon/logo.png` |

- Each generator's header comment is the reference for what it reads and writes.
- Data generators reach wago.tools through `tools/wago.ts` (latest `wowf` build), cached in `tools/.cache/` (gitignored). `--build 1.60.1.70888` pins a build; `--refresh` downloads again.
- Each generated `data.lua` names its build on line 1.
- After changing a generator: `bun run typecheck`, rerun it, review its output (step 3 below).

## Refresh after a content patch

1. Run `bun run professions`, `bun run instances`, `bun run seamless`, `bun run dots`.
2. `git diff --stat`: every generated header names the new build.
3. Review each `data.lua` diff:
   - Expected: changed values, a few entries added or removed (recipes, ranks, talents).
   - Suspect: tables emptied, most entries gone, keys renamed throughout: a DB2 table's columns changed. Fix the generator; don't commit.
   - `seamless`: media PNGs are binary: preview the zones whose `data.lua` entries changed (Seamless map below).
4. `bun run test`. A dots failure naming a key (`<key>: attack power measured`, `<key>: a followed spell`) means a followed spell was renamed: rename its key in `measured.lua`.
5. Commit the generated output.
6. `dots`: every `spells` entry in `measured.lua` not marked `Unmeasured:` names the build it was measured on. Measuring needs the player in game (Measuring below): ask them, or tell them which entries are still on an older build. When re-measured, if the ticks still match, update the build in the comment; otherwise refit, then update the value and its test.

## Following a new damage over time spell

1. Check it qualifies: cast on the target, ticking evenly. Refused: projectiles (they land, and miss, after the cast: the generator throws), ramping damage (Bane of Agony), health drains (Siphon Life, Devouring Plague).
2. Add the spell ID of one rank to `FOLLOWED` in `tools/dots.ts`, its name in a comment.
3. `bun run dots`. Check its `data.lua` entry: tick, school, spell power, ranks (none for a finishing move), talents, amplifiers.
4. A finishing move (`comboPoints = "spend"`) reads its base damage from its description at runtime, one line per combo point: check the description matches `PATTERNS` in `modules/combat/dots/spells.lua` in every locale. No other spell can use its description: the client includes the player's talents in the totals (Garrote's 338 is its data's 282 with Opportunity's 20%).
5. `bun run test` fails until `DoTs.Measured.spells` in `measured.lua` has `<key> = { attackPower, talentsRaiseBonus }` (`attackPower`: a number, or one per combo point for a finishing move). Measure it (next section). Above the entry, write how it was measured like the existing ones: build, attack power, talent ranks, ticks seen, the arithmetic; or "Unmeasured:" and why the value was chosen.
6. Add the measured ticks to `tests/dots_test.lua` ("matches the ticks measured in game").

## Measuring a damage over time spell

The server adds in its own code what the data lacks: the attack power share per tick, and whether the talents raising the effect also raise what attack and spell power add (`talentsRaiseBonus`). A talent bonus measured to differ from the data goes in `DoTs.Measured.talents` (talent spell ID → spell key → bonus per rank).

In combat, addon code can't read ticks (combat log restricted, `UNIT_COMBAT` amounts secret) nor attack and spell power (secret). The player reads the ticks; the addon logs the stats out of combat:

1. Install the logger with the `debugging` skill. Log right before the pull, out of combat: `UnitAttackPower("player")`, `GetSpellBonusDamage(school)` for the spell's school, and `DoTs.Stats:GetTalentRank(talentSpellID)` for each talent in the spell's `data.lua` entry. The log header gives the build.
2. Ask the player to cast the spell on a mob and paste several of its ticks from the game's combat log chat tab, with the combo points spent for a finishing move.
3. Fit the ticks from the base per tick (`data.lua`, or the description line), the talents' multiplier and the attack power share. When the player has a talent raising the damage, `(base + share * AP) * talents` versus `base * talents + share * AP` decides `talentsRaiseBonus`. An unknown share needs two attack power values or combo point counts.
4. Record it (step 5 of Following, above), then clean up the logger as the `debugging` skill says.

## Seamless map

- Also rerun `bun run seamless` after bumping `OPENMAP_COMMIT` in `tools/seamless/world.ts`.
- Check changes to the shares (`tools/seamless/ownership.ts`) or masks out of the game: `bun tools/seamless/preview.ts <left> <top> <right> <bottom> [px per world unit] [out.png]` (a normalized box on Azeroth's map, e.g. `0.70 0.60 0.84 0.74` around Duskwood; default output `tools/.cache/seamless/preview.png`). Read the image: no holes or doubled art at zone borders.

## Instances

The client links quests to instances only through quest log headers: `headerSortKey` is the header's area ID with bit 30 set (`modules/quests/helpers/ranking.lua`). So `tools/instances.ts` maps each dungeon and raid map to the area IDs its quests' headers can carry.

## Icon

Edit `tools/icon/icon.svg` (TOC `## IconTexture`) or `tools/icon/logo.svg`, run `bun run icon`, commit the SVGs with `media/icon.tga` and `tools/icon/logo.png`.
