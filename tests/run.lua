-- Test runner: `bun run test` (or `lua tests/run.lua` from the repo root).
-- Needs a Lua 5.2+ CLI for per-test environments; the addon code itself stays Lua 5.1.
--
-- Every test runs on a fresh fake client (tests/wow.lua) with the addon loaded
-- in TOC order and the player logged in, once per supported locale.

local LOCALES = { "enUS", "frFR" }
local TEST_FILES = {
    "tests/core_test.lua",
    "tests/locking_test.lua",
    "tests/sorting_test.lua",
    "tests/quests_test.lua",
    "tests/announce_test.lua",
    "tests/questie_test.lua",
    "tests/sparkles_test.lua",
    "tests/quest_tooltip_test.lua",
    "tests/leftovers_test.lua",
    "tests/reagents_test.lua",
    "tests/bank_test.lua",
    "tests/bank_transfers_test.lua",
    "tests/merchant_test.lua",
    "tests/junk_test.lua",
    "tests/marks_test.lua",
    "tests/notes_test.lua",
    "tests/windows_test.lua",
    "tests/waypoint_test.lua",
    "tests/way_test.lua",
    "tests/combopoints_test.lua",
    "tests/glow_test.lua",
    "tests/swaps_test.lua",
    "tests/ranks_test.lua",
    "tests/friends_test.lua",
    "tests/seamless_test.lua",
}

local function ReadAddonFiles()
    local files = {}
    for line in io.lines("ForeverEnhanced.toc") do
        local path = line:match("^%s*([^#].-%.lua)%s*$")
        if path then
            table.insert(files, (path:gsub("\\", "/")))
        end
    end
    return files
end

local ADDON_FILES = ReadAddonFiles()

local function Run(path, env, ...)
    return assert(loadfile(path, "t", env))(...)
end

-- A fresh fake client with the addon loaded and the player logged in.
-- `options.savedVariables(locale)` and `options.characterSavedVariables(locale)`
-- return the account and character saved tables the client loads before ADDON_LOADED.
local function Boot(locale, options)
    local env = setmetatable({ TEST_LOCALE = locale }, { __index = _G })
    env._G = env

    local world = Run("tests/wow.lua", env)
    local ns = {}
    for _, path in ipairs(ADDON_FILES) do
        Run(path, env, "ForeverEnhanced", ns)
    end
    if options and options.savedVariables then
        env.ForeverEnhancedDB = options.savedVariables(locale)
    end
    if options and options.characterSavedVariables then
        env.ForeverEnhancedCharacterDB = options.characterSavedVariables(locale)
    end
    world:Fire("ADDON_LOADED", "ForeverEnhanced")
    world:Fire("PLAYER_LOGIN")

    world.ns = ns
    world.L = ns.L
    world.env = env
    return world
end

-- Assertions available to test files.
local assertions = {}

function assertions.expect(condition, message)
    if not condition then
        error(message, 2)
    end
end

function assertions.equal(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local tests = {}

-- Test files see the globals of the client the current test runs on
-- (C_Container, MerchantFrame, ...), so they read like addon code.
local currentClientEnv

local function LoadTests(path)
    local env = setmetatable({}, {
        __index = function(_, key)
            return (currentClientEnv or _G)[key]
        end,
    })
    for name, func in pairs(assertions) do
        env[name] = func
    end
    -- options: { savedVariables = function(locale) return ForeverEnhancedDB end,
    --            characterSavedVariables = function(locale) return ForeverEnhancedCharacterDB end }
    function env.test(name, func, options)
        table.insert(tests, { file = path, name = name, func = func, options = options })
    end
    Run(path, env)
end

for _, path in ipairs(TEST_FILES) do
    LoadTests(path)
end

local passed, failed = 0, 0
for _, locale in ipairs(LOCALES) do
    for _, case in ipairs(tests) do
        local ok, err = pcall(function()
            local world = Boot(locale, case.options)
            currentClientEnv = world.env
            case.func(world)
        end)
        currentClientEnv = nil
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print(("FAIL [%s] %s > %s\n     %s"):format(locale, case.file, case.name, tostring(err)))
        end
    end
end

print(("%d passed, %d failed (%d tests x %d locales)"):format(passed, failed, #tests, #LOCALES))
os.exit(failed == 0 and 0 or 1)
