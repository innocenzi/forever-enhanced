local _, ns = ...

ns:RegisterModule("map", { order = 4 })

ns:RegisterLocale("enUS", {
    ["map.title"] = "Map",
    ["map.description"] = "Improves the map pin and shows your friends on the map.",
})

ns:RegisterLocale("frFR", {
    ["map.title"] = "Carte",
    ["map.description"] = "Améliore le repère sur la carte et y affiche vos amis.",
})
