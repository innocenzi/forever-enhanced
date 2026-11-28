---
name: debugging
description: Debug Forever Enhanced in the real game client. Use when the player reports something wrong in game and its cause isn't clear from the code and the tests (client behavior, event order, taint, timing, state that only exists in game) and you need to see what actually happens in game. Reads the debug addon's persistent log straight from the game's saved variables (bun run debug-log: taint, errors and blocked actions it already caught), adds temporary probes and ForeverEnhancedDebug:Log calls when that isn't enough, and removes every trace of them once the bug is fixed.
---

# Debugging in game

The fake client (`tests/wow.lua`) only models what was measured. When a bug depends on what the real client does, read what the debug addon caught, instrument the addon or probe the game if needed, let the player reproduce it, and read the log from disk once they `/reload`.

## The round trip

An addon can't open files or sockets: the game reads addon files only when the UI loads, and writes saved variables only at `/reload`, logout or exit. That makes `/reload` the channel both ways:

- **Game to you**: at logout (a `/reload` too) the debug addon exports its log as text into its saved variables, which the game then writes to `WTF\Account\<account>\SavedVariables\ForeverEnhancedDebug.lua`. `bun run debug-log` prints it: the session that just ended, or every session with `--all`. Its first line says when the file was saved: if that's before the player's reproduction, they haven't reloaded since.
- **You to the game**: what you write in the addon code (temporary logs) and in `debug/probe.lua` (probes) runs after the next `/reload`.
- **Waiting**: `bun run debug-log --wait` (run it in the background) blocks until the file is saved again, then prints it, so you see the log as soon as the player reloads.

`bun run debug-log` finds the game through `WOW_FOREVER_DIR` (the `_forever_` folder) in the gitignored `.env` at the repo root, else the default install paths. When neither is there, ask the player for the folder and write `.env`.

## 0. The debug addon

Forever Enhanced Debug (`debug/`, see "Debug addon" in `AGENTS.md`) runs in the maintainer's game all the time and keeps its log across reloads and sessions. It must be junctioned into the game once (the player does it, in a Command Prompt):

```
mklink /J "<game>\_forever_\Interface\AddOns\ForeverEnhancedDebug" "<repo>\debug"
```

On its own it logs **incidents**: taint of the Blizzard state in its watch list (`debug/watches.lua`), our errors (through BugGrabber), anyone's blocked actions, and every "Interface action failed because of an AddOn" message with the stack that caused it (the panel manager and secure helpers show it with no event). Each one comes with its stack when known, the context (zone, instance, combat, active features) and the events just before it. Incidents stay out of chat unless the player turns that on with `/fedebug chat` (a chat line pointing to `/fedebug` for each).

**Start there.** For taint, errors and anything the player can't reproduce on demand, read the log first (`bun run debug-log --all`, or the session that just ended when the player has reloaded since the bug): the incident may already be in it. When a taint bug involves Blizzard state that isn't watched yet, add it to `WATCHES` (it stays: the list grows with every bug), then let the player play until it shows up.

## 1. Instrument

When the incidents don't settle it, add temporary calls in the addon code. They need no install: the debug addon loads before ForeverEnhanced.

- `ForeverEnhancedDebug:Log(tag, ...)`: one entry with any values (tables are dumped, widgets named). It never throws into the code it instruments.
- `ForeverEnhancedDebug:Events(tag, "EVENT_A", "EVENT_B", ...)`: logs each firing with its arguments (its own frame, independent of the feature lifecycle).
- `ForeverEnhancedDebug:Hook(tag, "GlobalFunction")` / `ForeverEnhancedDebug:Hook(tag, table, "method")`: logs each call after it ran, with its arguments (`hooksecurefunc`, permanent until `/reload`).
- `ForeverEnhancedDebug:Stack(tag)`: logs the caller's stack.

The log keeps the last 5000 entries across reloads and sessions.

### Probes

For questions about the game rather than the addon's code paths (a frame's state, what an API returns, which events fire, whether a Blizzard function runs), write a probe in `debug/probe.lua` instead of touching the addon: it runs at each load of the UI, inside the debug addon (`ns` is `ForeverEnhancedDebug`, the addon is `ForeverEnhanced`), and logs what it finds. `ns:Events` and `ns:Hook` work there as they are; anything reading state goes in `ns:AtLogin(tag, func)`, which runs once the player is logged in and the features enabled, and logs an error under `tag` instead of throwing:

```lua
ns:AtLogin("probe.bank", function()
    ns:Log("probe.bank", BankFrame:IsShown(), ForeverEnhanced:GetFeature("inventory", "bank"):IsActive())
end)
```

State that matters only at a given moment (when a window opens, after a click) is read from a hook or an event there. Probes only observe: never change game or addon state from one.

Before adding logs, write down the hypotheses, then log what tells them apart, so that **one** reproduction is enough:

- Inputs and state at the entry of the suspect code, and the state it leaves.
- Which branch was taken and why (the values of the conditions, not just "here").
- Event order around the bug: `ForeverEnhancedDebug:Events` on everything that could be involved, Blizzard's too.
- Blizzard functions the feature reacts to or depends on: `ForeverEnhancedDebug:Hook`.
- Return values of the client APIs the code trusts.

In combat, many APIs return secret values that addon code can pass along but not read: tostring, concatenation, comparisons and arithmetic on them throw (e.g. cooldown times, `SecretWhenCooldownsRestricted` in `Blizzard_APIDocumentationGenerated` on the `forever` branch). A throw in the instrumented code breaks what you're observing (a click stops halfway, its hooks don't run), so pass API results to `ForeverEnhancedDebug:Log` as they are and compute nothing from them for a log; when a value must be readable in combat, log the fields documented `NeverSecret` instead (`isActive`, `isOnGCD` of a cooldown). The fake client models no secrets, so the tests won't catch this.

Tags are `<module>.<feature>.<place>` (`inventory.transfers.plan`). Log on change, never every frame (`OnUpdate`, frequent events): throttle or compare with the last value. Logging too much in one round trip beats asking the player for another.

The tests load the debug addon too: keep `bun run test` green while debugging.

## 2. Hand off to the player

Start `bun run debug-log --wait` in the background, then tell the player exactly:

1. `/reload`: loads your logs and probes, and starts the session you'll read.
2. The precise steps that reproduce the bug, or "play until it happens again" when it can't be reproduced on demand (`/fedebug chat` first if they want a chat line when an incident is logged).
3. `/reload` again (or log out): the game saves the log. Nothing to copy: you read it from disk.

When the reproduction is the login itself, step 2 is a `/reload` too, or a relog. When it took several reloads or relogs, read it with `bun run debug-log --all`: each load of the UI is a session. `/fedebug clear` isn't needed (you read one session); the player may still use it to keep the log small.

If `bun run debug-log` can't run (no Lua CLI, another machine), fall back to the window: `/fedebug` opens with the whole log selected (This session / All sessions toggles which), Ctrl+C, paste in the chat.

## Reading the log

```
ForeverEnhanced 1.1.0, build 61234, frFR, exported 2026-11-15 21:04:10 (4521.870), 4 entries
== session 12, 2026-11-15 20:58:02 ==
[4518.204] inventory.transfers.plan: 4 {bag=0, slot=3, items={6948, 2589}}
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
- `blocked.other` / `blocked.macro`: another addon's or a macro's blocked action (the game shows the same red message). `blocked.message`: the red message itself, with the stack that showed it (only the first of a burst; `blocked.message.again (xN)` counts the rest).
- In the `/fedebug` window (not `bun run debug-log`), pipes are doubled (`||cff…`, `||Hitem:…`) so color codes and links stay text: read `||` as `|`.

If the log doesn't settle it, change the logs and probes and hand off again (the same three steps). Once the cause is known, fix it and, when the fake client can express it, add a test that fails without the fix (extend `tests/wow.lua` with the behavior the log showed, faithful to it). Tell the player what to check in game to confirm the fix, if useful.

## 3. Clean up

Required before committing, and before calling the bug done. Never commit temporary calls. Additions to the debug addon's watch list stay.

1. Remove every `ForeverEnhancedDebug:` call from the addon code, and anything added only to feed them (locals, counters, extra returns), and every probe from `debug/probe.lua` (back to its header).
2. Check nothing remains; this must print nothing:

   ```bash
   grep -rn "ForeverEnhancedDebug" core modules; git diff --stat -- debug/probe.lua
   ```

3. `git diff`: only the fix (and its test, and any new watch) is left.
4. `bun run format`, `bun run lint`, `bun run test`.
