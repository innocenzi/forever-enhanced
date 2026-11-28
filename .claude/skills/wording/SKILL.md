---
name: wording
description: Review and fix Forever Enhanced's player-facing text (enUS and frFR) so every string is understandable where the player sees it and reads like Blizzard's own WoW text. Use after adding or changing player-facing strings (locales.lua: settings, tooltips, menus, chat messages, errors, dialogs, buttons), or when asked to check the wording of a feature, a module or the whole addon.
---

# Wording

A string can follow every rule in `AGENTS.md` > Localization and still mean nothing to the player who reads it. Judge each string where it's shown, as a player who never saw the code, then apply those rules. Fix what's wrong in both languages.

## 1. Scope

- By default: the strings the work at hand adds or changes. `git diff HEAD -- '*locales.lua'`, plus the `locales.lua` of new, untracked slices (`git status`).
- Otherwise what the user named: a feature (`modules/<module>/<feature>/locales.lua`), a module, or every `locales.lua` (`core/locales.lua` included).
- Always read a string with its siblings: a setting's label, `.tooltip` and options together, a feature's title and description together, a message with the action that prints it.

## 2. Rebuild the context

For each key, find where it's shown and what the player sees around it. Grep the key, and its prefix when code builds it (`core/settings.lua` appends `.title`, `.description`, `.tooltip`, `.format`, `.<option>`).

- **Settings panel** (`core/settings.lua`): the feature's page (its `page`, titled `core.pages.<page>`), shared with features of other modules. Features without settings are one checkbox each at the top, labeled with the title, the description as tooltip. Others get a section header (title; description as its tooltip), an "Enable" checkbox (same tooltip) and the settings below, nested under their `requires` parent. A setting with `needs` gets a last tooltip paragraph, "Requires <setting> in <feature>." (`core.needsSetting`, `core.needs`): its tooltip must not say it too. A tooltip opens beside its label, with the label as its heading: it must not repeat it.
- **Item tooltips**: lines under the sell price (`price = true`) or at the end, among Blizzard's own lines (`In bank: 7` next to `Sell Price:`).
- **Item menu** (Alt Right Click on a bag or bank item): entries among other features' entries.
- **Chat**: `ns:Print` reads as a system message, with no addon name. The player must tell what happened without knowing an addon did it.
- **Center screen**: `ns:Error` (red, for a blocked action) and `ns:Warning` (yellow): a few words, read mid-action.
- **Our windows, buttons, dialogs, empty states**: read the text with the window it sits in (title, other buttons).
- **Format strings**: fill them with realistic values (1 and several for plurals, a long item or character name, 0 where it can happen) and read the result.

## 3. Read it as the player

For each string, in its context:

- **Understandable**: could a player who never saw the code tell what it does or means? No implementation words: scan, cache, store, snapshot, handler, hook, part, feature, module, slot ID, sync, state, data, refresh.
- **What the player gets**, not how it works, nor the edge cases they won't notice.
- **Earns its place**: the tooltip adds something the label and description don't; the description says what the feature brings, not each setting.
- **One word per thing**: the same concept carries the same name in every string of the addon, and the game's name when the game has one.
- **Blizzard's words**: when the game already says it, say it the same way (step 4).
- **Then the rules** in `AGENTS.md` > Localization: sentence case, ~30 characters per label, tooltip verbs, click names, confirmations, value lines, plurals, French typography.

## 4. Look up the game's own text

The Forever client's GlobalStrings, in both languages (cached in the gitignored `tools/.cache`):

```bash
build=$(curl -s https://wago.tools/api/builds | bun -e 'console.log(JSON.parse(await Bun.stdin.text()).wowf[0].version)')
mkdir -p "tools/.cache/$build"
for locale in enUS frFR; do f="tools/.cache/$build/GlobalStrings-$locale.csv"; [ -s "$f" ] || curl -sSf -o "$f" "https://wago.tools/db2/GlobalStrings/csv?build=$build&locale=$locale"; done
```

Rows are `ID,BaseTag,TagText,Flags`. Search the English text for the concept (`grep -i "junk" .../GlobalStrings-enUS.csv`), then the French by its `BaseTag` (`grep ",SELL_ALL_JUNK_ITEMS," .../GlobalStrings-frFR.csv`). Several hits for one concept: pick the one used in the same kind of place (a button, a tooltip line, a label), checking where Blizzard uses it on the `forever` branch of `Gethe/wow-ui-source` when it matters. Reuse the term, and the phrasing patterns too: how the game words a value line, a confirmation, an error.

## 5. French is written, not translated

Read every frFR string on its own, as a French player would, without the English beside it: idiomatic, the game's French terms (from step 4, e.g. « Barres d’actions », « Vendre toute la camelote », « Ranger les sacs »), no English calques or word order, every word agreeing with a count inside the plural token. Both locales must hold the same keys: report any key one of them lacks.

## 6. Fresh eyes

The agent that wrote the code can't tell whether its text is clear: it knows what the text means. For a new feature, or one whose text changed a lot, spawn a subagent with only what the player sees:

- The strings laid out as shown in game (step 2): for a settings page, the page title, each section header with its tooltip, each control with its label, tooltip and options, nesting by indent; for a message, when it shows.
- Both languages, one after the other.
- Nothing else: no code, no file paths, no explanation of the feature. Tell it not to open any file.

Ask what each control, line or message does, what the player would expect to happen, and which words they'd stumble on. Wherever its answer differs from what the feature actually does, the text is unclear: rewrite it, and run the check again on the rewrite when the change was large.

## 7. Fix and report

Edit the `locales.lua` files directly, enUS and frFR together. Rename no keys unless their meaning changed (tests read text through `world.L[key]`). Then report:

- Each change as `key: before → after` and a short reason (per language when both changed).
- What's left for the user: a concept with no game term, a label that can't fit, a choice between two good wordings.

Run `bun run format`, `bun run lint` and `bun run test`.

## Examples

Past fixes in this repo, for tone:

| Before | After | Why |
| --- | --- | --- |
| `Bank count in tooltips` / `Shows how many of an item you have in your bank.` | `Show bank count` / `Shows in item tooltips how many you have in your bank.` | The label says what turning it on does; the tooltip says where. |
| `%d in the bank` | `In bank: %d` / `En banque : %d` | A value line, worded like the game's `Label: %d`. |
| `Locked items go back to their slot right after you sort your bags or bank. Each one can leave one other item slightly out of order.` | `Puts locked items back in their slot after you clean up your bags or bank.` | The game's "clean up"; the edge case the player won't notice is gone. |
| `barres d’action` | `barres d’actions` | The game's own French (`ACTIONBARS_LABEL`). |
