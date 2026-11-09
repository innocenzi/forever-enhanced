local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.bank.title"] = "Saved Bank",
    ["inventory.bank.description"] = "Keeps a copy of your bank every time you visit a banker, so you can browse it anywhere, along with the saved banks of your other characters on the same ruleset. Open it from the tab on the side of your bags.",
    ["inventory.bank.openWithBags"] = "Open with bags",
    ["inventory.bank.openWithBags.tooltip"] = "Open your saved bank whenever you open your bags.",
    ["inventory.bank.tooltipCount"] = "Bank count in tooltips",
    ["inventory.bank.tooltipCount.tooltip"] = 'Add a line like "7 in the bank" to item tooltips, from this character\'s saved bank.',
    ["inventory.bank.tooltipLine"] = "%d in the bank",
    ["inventory.bank.tabTooltip"] = "Saved Bank",
    ["inventory.bank.frameTitle"] = "%s's Bank",
    ["inventory.bank.empty"] = "No saved bank yet. Visit a banker with this character to save it.",
    ["inventory.bank.forget"] = "Forget",
    ["inventory.bank.forgetConfirm"] = "Forget %s's saved bank?",
})

ns:RegisterLocale("frFR", {
    ["inventory.bank.title"] = "Banque enregistrée",
    ["inventory.bank.description"] = "Garde une copie de votre banque à chaque visite chez un banquier, pour la consulter n'importe où, ainsi que les banques enregistrées de vos autres personnages du même ensemble de règles. Ouvrez-la avec l'onglet sur le côté de vos sacs.",
    ["inventory.bank.openWithBags"] = "Ouvrir avec les sacs",
    ["inventory.bank.openWithBags.tooltip"] = "Ouvre votre banque enregistrée chaque fois que vous ouvrez vos sacs.",
    ["inventory.bank.tooltipCount"] = "Quantité en banque",
    ["inventory.bank.tooltipCount.tooltip"] = "Ajoute une ligne comme « 7 en banque » aux infobulles des objets, d'après la banque enregistrée de ce personnage.",
    ["inventory.bank.tooltipLine"] = "%d en banque",
    ["inventory.bank.tabTooltip"] = "Banque enregistrée",
    ["inventory.bank.frameTitle"] = "Banque de %s",
    ["inventory.bank.empty"] = "Aucune banque enregistrée. Rendez-vous chez un banquier avec ce personnage pour l'enregistrer.",
    ["inventory.bank.forget"] = "Oublier",
    ["inventory.bank.forgetConfirm"] = "Oublier la banque enregistrée de %s ?",
})
