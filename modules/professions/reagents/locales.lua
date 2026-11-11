local _, ns = ...

ns:RegisterLocale("enUS", {
    ["professions.reagents.title"] = "Reagent uses",
    ["professions.reagents.description"] = "Shows in an item's tooltip which recipes use it while you hold Shift.",
    ["professions.reagents.professions"] = "Professions shown",
    ["professions.reagents.professions.tooltip"] = "Controls which professions' recipes are listed.",
    ["professions.reagents.professions.all"] = "All",
    ["professions.reagents.professions.mine"] = "Yours",
    ["professions.reagents.recipe"] = "  %s x%d",
    ["professions.reagents.more"] = "  and %d |4more recipe:more recipes;",
})

ns:RegisterLocale("frFR", {
    ["professions.reagents.title"] = "Usage des composants",
    ["professions.reagents.description"] = "Affiche dans l’infobulle d’un objet les recettes qui l’utilisent quand vous maintenez Maj.",
    ["professions.reagents.professions"] = "Métiers affichés",
    ["professions.reagents.professions.tooltip"] = "Contrôle les métiers dont les recettes sont affichées.",
    ["professions.reagents.professions.all"] = "Tous",
    ["professions.reagents.professions.mine"] = "Les vôtres",
    ["professions.reagents.recipe"] = "  %s x%d",
    ["professions.reagents.more"] = "  et %d |4autre recette:autres recettes;",
})
