local _, ns = ...

ns:RegisterLocale("enUS", {
    ["professions.plans.title"] = "Planned recipes",
    ["professions.plans.description"] = "Adds a button on a recipe's icon to plan it: on your next visit to the bank, the reagents your bags lack for it are taken out, once.",
    ["professions.plans.announce"] = "Announce in chat",
    ["professions.plans.announce.tooltip"] = "Shows in chat the reagents taken from the bank, and those still missing.",
    ["professions.plans.button"] = "Plan this recipe",
    ["professions.plans.button.tooltip"] = "Takes the reagents your bags lack from the bank on your next visit.",
    ["professions.plans.planned"] = "Planned crafts: %d",
    ["professions.plans.leftClick"] = "Left Click: plan a number of crafts",
    ["professions.plans.rightClick"] = "Right Click: remove from planned recipes",
    ["professions.plans.prompt"] = "How many times do you want to craft %s?",
    ["professions.plans.item"] = "%s x%d",
    ["professions.plans.withdrawn"] = "Taken from the bank for your planned recipes: %s.",
    ["professions.plans.missing"] = "Still missing for your planned recipes: %s.",
})

ns:RegisterLocale("frFR", {
    ["professions.plans.title"] = "Recettes planifiées",
    ["professions.plans.description"] = "Ajoute un bouton sur l’icône d’une recette pour la planifier : à votre prochaine visite à la banque, les composants qui manquent dans vos sacs en sont retirés, une seule fois.",
    ["professions.plans.announce"] = "Annoncer dans la discussion",
    ["professions.plans.announce.tooltip"] = "Affiche dans la discussion les composants retirés de la banque, et ceux qui manquent encore.",
    ["professions.plans.button"] = "Planifier cette recette",
    ["professions.plans.button.tooltip"] = "Retire de la banque, à votre prochaine visite, les composants qui manquent dans vos sacs.",
    ["professions.plans.planned"] = "Fabrications planifiées : %d",
    ["professions.plans.leftClick"] = "Clic gauche : planifier un nombre de fabrications",
    ["professions.plans.rightClick"] = "Clic droit : retirer des recettes planifiées",
    ["professions.plans.prompt"] = "Combien de fois voulez-vous fabriquer %s ?",
    ["professions.plans.item"] = "%s x%d",
    ["professions.plans.withdrawn"] = "Retiré de la banque pour vos recettes planifiées : %s.",
    ["professions.plans.missing"] = "Manquant pour vos recettes planifiées : %s.",
})
