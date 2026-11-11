---
name: debugging
description: Debug Forever Enhanced in the real game client. Use when the player reports something wrong in game and its cause isn't clear from the code and the tests (client behavior, event order, taint, timing, state that only exists in game) and you need to see what actually happens in game. Installs a temporary in-memory logger with a /fedebug window the player copies the log from, and removes every trace of it once the bug is fixed.
---

# Debugging in game

The fake client (`tests/wow.lua`) only models what was measured. When a bug depends on what the real client does, instrument the addon, let the player reproduce it, and read the log they paste back.

## 1. Install the logger

1. Copy `.claude/skills/debugging/debug.lua` to `core/debug.lua` unchanged.
2. Add `core\debug.lua` to `ForeverEnhanced.toc` as the **first** line under `# Core`, so every file can log, even at load.

This is a temporary exception to the no-slash-command rule (`/fedebug`). It never gets committed.

It adds, on the namespace:

- `ns:DebugLog(tag, ...)`: one entry with any values (tables are dumped, widgets named). It never throws into the code it instruments.
- `ns:DebugEvents(tag, "EVENT_A", "EVENT_B", ...)`: logs each firing with its arguments (its own frame, independent of the feature lifecycle).
- `ns:DebugHook(tag, "GlobalFunction")` / `ns:DebugHook(tag, table, "method")`: logs each call after it ran, with its arguments (`hooksecurefunc`, permanent until `/reload`).
- `ns:DebugStack(tag)`: logs the caller's stack.

The log keeps the last 5000 entries, in memory only: a `/reload` starts a new one.

## 2. Instrument

Before adding logs, write down the hypotheses, then log what tells them apart, so that **one** reproduction is enough:

- Inputs and state at the entry of the suspect code, and the state it leaves.
- Which branch was taken and why (the values of the conditions, not just "here").
- Event order around the bug: `ns:DebugEvents` on everything that could be involved, Blizzard's too.
- Blizzard functions the feature reacts to or depends on: `ns:DebugHook`.
- Return values of the client APIs the code trusts.

In combat, many APIs return secret values that addon code can pass along but not read: tostring, concatenation, comparisons and arithmetic on them throw (e.g. cooldown times, `SecretWhenCooldownsRestricted` in `Blizzard_APIDocumentationGenerated` on the `forever` branch). A throw in the instrumented code breaks what you're observing (a click stops halfway, its hooks don't run), so pass API results to `ns:DebugLog` as they are and compute nothing from them for a log; when a value must be readable in combat, log the fields documented `NeverSecret` instead (`isActive`, `isOnGCD` of a cooldown). The fake client models no secrets, so the tests won't catch this.

Tags are `<module>.<feature>.<place>` (`inventory.bank.transfers.plan`). Log on change, never every frame (`OnUpdate`, frequent events): throttle or compare with the last value. Logging too much in one round trip beats asking the player for another.

The tests still run with the logger installed (it only registers the slash command at load): keep `bun run test` green while debugging.

## 3. Hand off to the player

Tell the player exactly:

1. `/reload`.
2. `/fedebug clear` (drops the noise from login, unless login is the bug).
3. The precise steps that reproduce the bug.
4. `/fedebug`: the window opens with the whole log selected; Ctrl+C, then paste it in the chat.

## Reading the log

```
ForeverEnhanced 0.2.0, build 61234, frFR, exported at 4521.870, 3 entries
[4518.204] inventory.bank.transfers.plan: 4 {bag=0, slot=3, items={6948, 2589}}
[4519.010!] combat.swaps.cast: <secret number> <Button ForeverEnhancedSwapButton1>
[4519.500-4520.750] combat.swaps.update: nil (x12)
```

- Header: addon version, client build, client locale, `GetTime()` at export (compare with the entries to tell old ones from the reproduction), entry count and how many older ones were dropped.
- `[time]` is `GetTime()` in seconds; `!` after it means in combat.
- `[first-last] … (xN)`: N identical consecutive entries collapsed into one.
- Values are space-separated, top-level strings raw. Tables: sorted keys, array part without indices, nested strings quoted; `{...}` is deeper than 3 levels, `...+N` is N keys past the first 40, `<cycle>` a table already being printed.
- `<Type Name>`: a widget. `<function>`: a function. `<secret type>` / `<secret table>`: a value addon code can't read in combat (see 2). `<not logged: error>`: the entry itself failed.
- Pipes are doubled (`||cff…`, `||Hitem:…`) so color codes and links stay text: read `||` as `|`.

If the log doesn't settle it, change the logs and hand off again (the player reloads). Once the cause is known, fix it and, when the fake client can express it, add a test that fails without the fix (extend `tests/wow.lua` with the behavior the log showed, faithful to it). Tell the player what to check in game to confirm the fix, still with the logger in, if useful.

## 4. Clean up

Required before committing, and before calling the bug done. Never commit with the logger installed.

1. Delete `core/debug.lua` and its line in `ForeverEnhanced.toc`.
2. Remove every `ns:Debug*` call, and anything added only to feed them (locals, counters, extra returns).
3. Check nothing remains; this must print nothing:

   ```bash
   grep -rnE "Debug(Log|Events|Hook|Stack)|fedebug|core.debug\.lua" core modules tests ForeverEnhanced.toc
   ```

4. `git diff`: only the fix (and its test) is left.
5. `bun run format`, `bun run lint`, `bun run test`.
