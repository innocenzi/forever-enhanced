local _, ns = ...

ns:RegisterLocale("enUS", {
    ["combat.swaps.title"] = "Ability swaps",
    ["combat.swaps.description"] = "While a spell can be cast, shows it on the button of the spell it replaces, and that button casts it. Otherwise, the button casts its own spell when you release the key.",
    ["combat.swaps.ambush"] = "Ambush on Backstab",
    ["combat.swaps.ambush.tooltip"] = "Shows Ambush on your Backstab buttons whenever you can cast it, like after Ghostly Strike.",
    ["combat.swaps.garrote"] = "Garrote on Sinister Strike",
    ["combat.swaps.garrote.tooltip"] = "Shows Garrote on your Sinister Strike buttons whenever you can cast it, like after Ghostly Strike.",
})

ns:RegisterLocale("frFR", {
    ["combat.swaps.title"] = "Remplacement de sorts",
    ["combat.swaps.description"] = "Tant qu’un sort peut être lancé, l’affiche sur le bouton du sort qu’il remplace, qui le lance alors. Sinon, le bouton lance son propre sort quand vous relâchez la touche.",
    ["combat.swaps.ambush"] = "Embuscade sur Attaque sournoise",
    ["combat.swaps.ambush.tooltip"] = "Affiche Embuscade sur vos boutons Attaque sournoise dès que vous pouvez la lancer, par exemple après Frappe fantomatique.",
    ["combat.swaps.garrote"] = "Garrot sur Attaque pernicieuse",
    ["combat.swaps.garrote.tooltip"] = "Affiche Garrot sur vos boutons Attaque pernicieuse dès que vous pouvez le lancer, par exemple après Frappe fantomatique.",
})
