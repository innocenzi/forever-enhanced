local _, ns = ...

ns:RegisterModule("quests", { order = 2 })

ns:RegisterLocale("enUS", {
    ["quests.title"] = "Quests",
    ["quests.description"] = "Improves quest tracking and group questing.",
})

ns:RegisterLocale("frFR", {
    ["quests.title"] = "Quêtes",
    ["quests.description"] = "Améliore le suivi des quêtes et les quêtes en groupe.",
})
