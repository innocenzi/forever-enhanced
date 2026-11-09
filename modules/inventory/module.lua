local _, ns = ...

ns:RegisterModule("inventory", { order = 1 })

ns:RegisterLocale("enUS", {
    ["inventory.title"] = "Inventory",
    ["inventory.description"] = "Improvements to your bags and bank.",
})

ns:RegisterLocale("frFR", {
    ["inventory.title"] = "Inventaire",
    ["inventory.description"] = "Améliorations de vos sacs et de votre banque.",
})
