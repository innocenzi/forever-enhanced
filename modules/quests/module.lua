local _, ns = ...

ns:RegisterModule("quests", { order = 2 })

ns:RegisterLocale("enUS", {
    ["quests.title"] = "Quests",
    ["quests.description"] = "Improvements to quest tracking.",
})

ns:RegisterLocale("frFR", {
    ["quests.title"] = "Quêtes",
    ["quests.description"] = "Améliorations du suivi des quêtes.",
})
