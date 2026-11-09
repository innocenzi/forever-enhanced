local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.transfers.title"] = "Bank transfers",
    ["inventory.transfers.description"] = "Adds Deposit and Withdraw buttons to your bank, to fill existing stacks or move all matching items. Locked items are never moved.",
    ["inventory.transfers.deposit"] = "Deposit",
    ["inventory.transfers.withdraw"] = "Withdraw",
    ["inventory.transfers.deposit.tooltip"] = "Moves items from your bags to your bank.",
    ["inventory.transfers.withdraw.tooltip"] = "Moves items from your bank to your bags.",
    ["inventory.transfers.stacks"] = "Fill existing stacks",
    ["inventory.transfers.all"] = "All matching items",
})

ns:RegisterLocale("frFR", {
    ["inventory.transfers.title"] = "Transferts avec la banque",
    ["inventory.transfers.description"] = "Ajoute les boutons Dépôt et Retrait à votre banque, pour compléter les piles existantes ou déplacer tous les objets correspondants. Les objets verrouillés ne sont jamais déplacés.",
    ["inventory.transfers.deposit"] = "Dépôt",
    ["inventory.transfers.withdraw"] = "Retrait",
    ["inventory.transfers.deposit.tooltip"] = "Déplace des objets de vos sacs vers votre banque.",
    ["inventory.transfers.withdraw.tooltip"] = "Déplace des objets de votre banque vers vos sacs.",
    ["inventory.transfers.stacks"] = "Compléter les piles existantes",
    ["inventory.transfers.all"] = "Tous les objets correspondants",
})
