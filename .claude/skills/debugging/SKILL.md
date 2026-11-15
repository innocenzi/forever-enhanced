---
name: debugging
description: Debug Forever Enhanced in the real game client. Use when the player reports something wrong in game and its cause isn't clear from the code and the tests (client behavior, event order, taint, timing, state that only exists in game) and you need to see what actually happens in game. Reads the debug addon's persistent log (/fedebug: taint, errors and blocked actions it already caught), adds temporary ForeverEnhancedDebug:Log calls when that isn't enough, and removes every trace of them once the bug is fixed.
---

# Debugging in game

The fake client (`tests/wow.lua`) only models what was measured. When a bug depends on what the real client does, read what the debug addon caught, instrument the addon if needed, let the player reproduce it, and read the log they paste back.

## 0. The debug addon

Forever Enhanced Debug (`debug/`, see "Debug addon" in `AGENTS.md`) runs in the maintainer's game all the time and keeps its log across reloads and sessions. It must be junctioned into the game once (the player does it, in a Command Prompt):

```
mklink /J "<game>\_forever_\Interface\AddOns\ForeverEnhancedDebug" "<repo>\dev"
```

On its own it logs **incidents**: taint of the Blizzard state in its watch list (`debug/watches.lua`), our errors (through BugGrabber) and our blocked actions. Each one comes with its stack when known, the context (zone, instance, combat, active features) and the events just before it, and it prints a chat line pointing to `/fedebug`.

**Start there.** For taint, errors and anything the player can't reproduce on demand, ask for the `/fedebug` log first: the incident may already be in it. When a taint bug involves Blizzard state that isn't watched yet, add it to `WATCHES` (it stays: the list grows with every bug), then let the player play until it shows up.

## 1. Instrument

When the incidents don't settle it, add temporary calls in the addon code. They need no install: the debug addon loads before ForeverEnhanced.

- `ForeverEnhancedDebug:Log(tag, ...)`: one entry with any values (tables are dumped, widgets named). It never throws into the code it instruments.
- `ForeverEnhancedDebug:Events(tag, "EVENT_A", "EVENT_B", ...)`: logs each firing with its arguments (its own frame, independent of the feature lifecycle).
- `ForeverEnhancedDebug:Hook(tag, "GlobalFunction")` / `ForeverEnhancedDebug:Hook(tag, table, "method")`: logs each call after it ran, with its arguments (`hooksecurefunc`, permanent until `/reload`).
- `ForeverEnhancedDebug:Stack(tag)`: logs the caller's stack.

The log keeps the last 5000 entries across reloads and sessions.

Before adding logs, write down the hypotheses, then log what tells them apart, so that **one** reproduction is enough:

- Inputs and state at the entry of the suspect code, and the state it leaves.
- Which branch was taken and why (the values of the conditions, not just "here").
- Event order around the bug: `ForeverEnhancedDebug:Events` on everything that could be involved, Blizzard's too.
- Blizzard functions the feature reacts to or depends on: `ForeverEnhancedDebug:Hook`.
- Return values of the client APIs the code trusts.

In combat, many APIs return secret values that addon code can pass along but not read: tostring, concatenation, comparisons and arithmetic on them throw (e.g. cooldown times, `SecretWhenCooldownsRestricted` in `Blizzard_APIDocumentationGenerated` on the `forever` branch). A throw in the instrumented code breaks what you're observing (a click stops halfway, its hooks don't run), so pass API results to `ForeverEnhancedDebug:Log` as they are and compute nothing from them for a log; when a value must be readable in combat, log the fields documented `NeverSecret` instead (`isActive`, `isOnGCD` of a cooldown). The fake client models no secrets, so the tests won't catch this.

Tags are `<module>.<feature>.<place>` (`inventory.bank.transfers.plan`). Log on change, never every frame (`OnUpdate`, frequent events): throttle or compare with the last value. Logging too much in one round trip beats asking the player for another.

The tests load the debug addon too: keep `bun run test` green while debugging.

## 2. Hand off to the player

Tell the player exactly:

1. `/reload`.
2. `/fedebug clear`: the log survives reloads, so this drops older sessions and the noise from login (skip it when login is the bug, or when waiting for an incident that may come any time).
3. The precise steps that reproduce the bug, or "play until the chat says Forever Enhanced Debug logged something" when it can't be reproduced on demand.
4. `/fedebug`: the window opens with the whole log selected (This session / All sessions toggles which); Ctrl+C, then paste it in the chat.

## Reading the log

```
ForeverEnhanced 1.1.0, build 61234, frFR, exported 2026-11-15 21:04:10 (4521.870), 4 entries
== session 12, 2026-11-15 20:58:02 ==
[4518.204] inventory.bank.transfers.plan: 4 {bag=0, slot=3, items={6948, 2589}}
[4519.010!] combat.swaps.cast: <secret number> <Button ForeverEnhancedSwapButton1>
[4519.500-4520.750] combat.swaps.update: nil (x12)
[4520.900] taint.objectiveTracker: ObjectiveTrackerFrame.dirty tainted by ForeverEnhanced (after MarkDirty)
stack:
...
context: zone=Stormwind City instance=none combat=false version=1.1.0
  active: inventory.locking quests.tracking ...
events before:
  [4519.120] QUEST_WATCH_LIST_CHANGED 26389 true
```

- Header: addon version, client build, client locale, date and `GetTime()` at export, entry count and how many older ones were dropped.
- `== session N, date ==`: a new load of the UI (login or `/reload`); `GetTime()` restarts with the client, so compare times within a session.
- `[time]` is `GetTime()` in seconds; `!` after it means in combat.
- `[first-last] … (xN)`: N identical consecutive entries collapsed into one.
- Values are space-separated, top-level strings raw. Tables: sorted keys, array part without indices, nested strings quoted; `{...}` is deeper than 3 levels, `...+N` is N keys past the first 40, `<cycle>` a table already being printed.
- `<Type Name>`: a widget. `<function>`: a function. `<secret type>` / `<secret table>`: a value addon code can't read in combat (see 1). `<not logged: error>`: the entry itself failed.
- Incidents (`taint.<watch>`, `error`, `blocked`): the summary, then the stack (when known), the context and the events recorded just before. `error.again` / `blocked.again`: the same one again this session.
- Pipes are doubled (`||cff…`, `||Hitem:…`) so color codes and links stay text: read `||` as `|`.

If the log doesn't settle it, change the logs and hand off again (the player reloads). Once the cause is known, fix it and, when the fake client can express it, add a test that fails without the fix (extend `tests/wow.lua` with the behavior the log showed, faithful to it). Tell the player what to check in game to confirm the fix, if useful.

## 3. Clean up

Required before committing, and before calling the bug done. Never commit temporary calls. Additions to the debug addon's watch list stay.

1. Remove every `ForeverEnhancedDebug:` call from the addon code, and anything added only to feed them (locals, counters, extra returns).
2. Check nothing remains; this must print nothing:

   ```bash
   grep -rn "ForeverEnhancedDebug" core modules
   ```

3. `git diff`: only the fix (and its test, and any new watch) is left.
4. `bun run format`, `bun run lint`, `bun run test`.
