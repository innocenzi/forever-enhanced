// Prints the debug addon's log (debug/) from its saved variables file, the same
// text /fedebug shows, so the debugging skill reads it without a copy-paste.
// The game writes the file at each /reload and logout, and the debug addon
// exports the log into it then (`export` in debug/log.lua).
//
//   bun run debug-log          the session that just ended (before the last /reload)
//   bun run debug-log --all    every session kept
//   bun run debug-log --wait   waits for the next save (the player's /reload), then prints
//
// The game folder (`_forever_`) comes from WOW_FOREVER_DIR (bun loads it from
// a gitignored .env at the repo root), else from the default install paths.
// Needs the Lua CLI the tests use.

import { stat } from "node:fs/promises";
import path from "node:path";

const DEFAULT_GAME_DIRS = [
  "C:\\Program Files (x86)\\World of Warcraft\\_forever_",
  "C:\\Program Files\\World of Warcraft\\_forever_",
];
const SAVED_VARIABLES = "WTF/Account/*/SavedVariables/ForeverEnhancedDebug.lua";
const POLL_MS = 500;
const SETTLE_MS = 1000; // the game writes the file in steps: wait for it to stay still

const args = process.argv.slice(2);
const scope = args.includes("--all") ? "all" : "session";
const wait = args.includes("--wait");

async function exists(dir: string) {
  return (await stat(dir).catch(() => null))?.isDirectory() ?? false;
}

async function findGameDir() {
  const configured = process.env.WOW_FOREVER_DIR;
  if (configured) {
    if (!(await exists(configured))) {
      throw new Error(`WOW_FOREVER_DIR is not a folder: ${configured}`);
    }
    return configured;
  }
  for (const dir of DEFAULT_GAME_DIRS) {
    if (await exists(dir)) {
      return dir;
    }
  }
  throw new Error("Game folder not found: set WOW_FOREVER_DIR (the _forever_ folder) in .env");
}

// The most recently saved file, when several accounts have one.
async function findSavedVariables(gameDir: string) {
  let newest: { file: string; mtimeMs: number } | undefined;
  for await (const relative of new Bun.Glob(SAVED_VARIABLES).scan({ cwd: gameDir })) {
    const file = path.join(gameDir, relative);
    const { mtimeMs } = await stat(file);
    if (!newest || mtimeMs > newest.mtimeMs) {
      newest = { file, mtimeMs };
    }
  }
  if (!newest) {
    throw new Error(`No ${path.basename(SAVED_VARIABLES)} under ${gameDir}: /reload once with the debug addon on`);
  }
  return newest;
}

async function waitForSave(file: string, since: number) {
  let last = since;
  let stillSince = 0;
  for (;;) {
    await Bun.sleep(POLL_MS);
    const mtimeMs = (await stat(file).catch(() => null))?.mtimeMs ?? last;
    if (mtimeMs !== last) {
      last = mtimeMs;
      stillSince = Date.now();
    } else if (last !== since && Date.now() - stillSince >= SETTLE_MS) {
      return;
    }
  }
}

// The file is plain Lua: let Lua read it.
function readExport(file: string) {
  const code = [
    'dofile(os.getenv("FE_SAVED_VARIABLES"))',
    "local db = ForeverEnhancedDebugDB",
    'local text = type(db) == "table" and type(db.export) == "table" and db.export[os.getenv("FE_SCOPE")]',
    'if type(text) ~= "string" then os.exit(2) end',
    "io.write(text)",
  ].join(" ");
  const result = Bun.spawnSync(["lua", "-e", code], {
    env: { ...process.env, FE_SAVED_VARIABLES: file, FE_SCOPE: scope },
  });
  if (result.exitCode === 2) {
    throw new Error("No export in the file yet: /reload once with this version of the debug addon");
  }
  if (result.exitCode !== 0) {
    throw new Error(`lua failed: ${result.stderr.toString()}`);
  }
  return result.stdout.toString();
}

function describeAge(mtimeMs: number) {
  const minutes = Math.round((Date.now() - mtimeMs) / 60000);
  const date = new Date(mtimeMs).toLocaleString("sv-SE"); // YYYY-MM-DD HH:MM:SS
  return minutes < 1 ? `${date}, just now` : `${date}, ${minutes} min ago`;
}

try {
  const gameDir = await findGameDir();
  const saved = await findSavedVariables(gameDir);
  if (wait) {
    console.error(`Waiting for the next /reload (${saved.file})...`);
    await waitForSave(saved.file, saved.mtimeMs);
    saved.mtimeMs = (await stat(saved.file)).mtimeMs;
  }
  console.log(`Saved ${describeAge(saved.mtimeMs)}: ${saved.file}`);
  console.log(readExport(saved.file));
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
