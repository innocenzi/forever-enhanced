local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.transfers.title"] = "Bank Transfers",
    ["inventory.transfers.description"] = "Adds Deposit and Withdraw buttons to your bank. Each one either completes the partial stacks on the other side, or moves every item the other side already holds. Locked items never move.",
    ["inventory.transfers.deposit"] = "Deposit",
    ["inventory.transfers.withdraw"] = "Withdraw",
    ["inventory.transfers.deposit.tooltip"] = "Move items from your bags into your bank.",
    ["inventory.transfers.withdraw.tooltip"] = "Move items from your bank into your bags.",
    ["inventory.transfers.stacks"] = "Stack onto existing stacks",
    ["inventory.transfers.all"] = "All matching items",
})

ns:RegisterLocale("frFR", {
    ["inventory.transfers.title"] = "Transferts avec la banque",
    ["inventory.transfers.description"] = "Ajoute les boutons Déposer et Retirer à votre banque. Chacun complète les piles incomplètes de l'autre côté, ou déplace tous les objets que l'autre côté contient déjà. Les objets verrouillés ne bougent jamais.",
    ["inventory.transfers.deposit"] = "Déposer",
    ["inventory.transfers.withdraw"] = "Retirer",
    ["inventory.transfers.deposit.tooltip"] = "Déplace des objets de vos sacs vers votre banque.",
    ["inventory.transfers.withdraw.tooltip"] = "Déplace des objets de votre banque vers vos sacs.",
    ["inventory.transfers.stacks"] = "Compléter les piles existantes",
    ["inventory.transfers.all"] = "Tous les objets correspondants",
})
