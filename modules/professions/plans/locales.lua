local _, ns = ...

ns:RegisterLocale("enUS", {
    ["professions.plans.title"] = "Tracked recipes",
    ["professions.plans.description"] = "Asks how many times you want to craft a recipe when you track it: the objective tracker shows the reagents for all of them, and stops tracking the recipe once the last one is made.",
    ["professions.plans.withdraw"] = "Take reagents from the bank",
    ["professions.plans.withdraw.tooltip"] = "Takes only what your bags lack for your tracked recipes, each time you visit the bank.",
    ["professions.plans.announce"] = "Announce in chat",
    ["professions.plans.announce.tooltip"] = "Shows in chat the reagents taken from the bank, and those still missing.",
    ["professions.plans.setCount"] = "Set number of crafts",
    ["professions.plans.header"] = "%s x%d",
    ["professions.plans.item"] = "%s x%d",
    ["professions.plans.withdrawn"] = "Taken from the bank for your tracked recipes: %s.",
    ["professions.plans.missing"] = "Still missing for your tracked recipes: %s.",
})

ns:RegisterLocale("frFR", {
    ["professions.plans.title"] = "Recettes suivies",
    ["professions.plans.description"] = "Demande combien de fois fabriquer une recette quand vous la suivez : le suivi des objectifs affiche les composants de toutes ces fabrications, puis cesse de la suivre après la dernière.",
    ["professions.plans.withdraw"] = "Retirer les composants de la banque",
    ["professions.plans.withdraw.tooltip"] = "Ne retire que les composants qui manquent dans vos sacs pour vos recettes suivies, à chaque visite à la banque.",
    ["professions.plans.announce"] = "Annoncer dans la discussion",
    ["professions.plans.announce.tooltip"] = "Affiche dans la discussion les composants retirés de la banque, et ceux qui manquent encore.",
    ["professions.plans.setCount"] = "Définir le nombre de fabrications",
    ["professions.plans.header"] = "%s x%d",
    ["professions.plans.item"] = "%s x%d",
    ["professions.plans.withdrawn"] = "Retiré de la banque pour vos recettes suivies : %s.",
    ["professions.plans.missing"] = "Il manque encore pour vos recettes suivies : %s.",
})
