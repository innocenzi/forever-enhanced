local _, ns = ...

ns:RegisterModule("inventory", { order = 1 })

ns:RegisterLocale("enUS", {
    ["inventory.title"] = "Inventory",
    ["inventory.description"] = "Improves your bags and bank.",
})

ns:RegisterLocale("frFR", {
    ["inventory.title"] = "Inventaire",
    ["inventory.description"] = "Améliore vos sacs et votre banque.",
})
