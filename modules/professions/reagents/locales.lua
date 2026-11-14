local _, ns = ...

ns:RegisterLocale("enUS", {
    ["professions.reagents.title"] = "Reagent uses",
    ["professions.reagents.description"] = "Shows in an item's tooltip which recipes use it while you hold Shift.",
    ["professions.reagents.onlyMine"] = "Only your professions",
    ["professions.reagents.onlyMine.tooltip"] = "Lists only the recipes of the professions you know.",
    ["professions.reagents.recipe"] = "  %s x%d",
    ["professions.reagents.more"] = "  and %d |4more recipe:more recipes;",
})

ns:RegisterLocale("frFR", {
    ["professions.reagents.title"] = "Usage des composants",
    ["professions.reagents.description"] = "Affiche dans l’infobulle d’un objet les recettes qui l’utilisent quand vous maintenez Maj.",
    ["professions.reagents.onlyMine"] = "Limiter à vos métiers",
    ["professions.reagents.onlyMine.tooltip"] = "Affiche seulement les recettes des métiers que vous connaissez.",
    ["professions.reagents.recipe"] = "  %s x%d",
    ["professions.reagents.more"] = "  et %d |4autre recette:autres recettes;",
})
