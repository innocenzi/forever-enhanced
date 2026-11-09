local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.merchant.title"] = "Merchant",
    ["inventory.merchant.description"] = "Sells your junk and repairs your items when you open a merchant. Locked items are never sold.",
    ["inventory.merchant.autoSellJunk"] = "Auto Sell Junk",
    ["inventory.merchant.autoSellJunk.tooltip"] = "Sells your junk when you open a merchant, like Sell All Junk Items. Locked items are kept.",
    ["inventory.merchant.autoRepair"] = "Auto Repair",
    ["inventory.merchant.autoRepair.tooltip"] = "Repairs all your items when you open a merchant that can repair.",
    ["inventory.merchant.repairFunds"] = "Repair With",
    ["inventory.merchant.repairFunds.tooltip"] = "Controls who pays for repairs. Guild funds are used when your guild allows it, otherwise your own gold.",
    ["inventory.merchant.repairFunds.player"] = "Own Gold",
    ["inventory.merchant.repairFunds.guild"] = "Guild Funds First",
    ["inventory.merchant.announce"] = "Announce in Chat",
    ["inventory.merchant.announce.tooltip"] = "Displays a chat message with the money earned from junk and spent on repairs.",
    ["inventory.merchant.sold"] = "Sold %d junk |4item:items; for %s.",
    ["inventory.merchant.repaired"] = "Repaired all items for %s.",
    ["inventory.merchant.repairedGuild"] = "Repaired all items for %s using guild funds.",
    ["inventory.merchant.notEnoughMoney"] = "You don't have enough money to repair your items.",
})

ns:RegisterLocale("frFR", {
    ["inventory.merchant.title"] = "Marchand",
    ["inventory.merchant.description"] = "Vend votre camelote et répare vos objets quand vous ouvrez un marchand. Les objets verrouillés ne sont jamais vendus.",
    ["inventory.merchant.autoSellJunk"] = "Vendre la camelote",
    ["inventory.merchant.autoSellJunk.tooltip"] = "Vend votre camelote quand vous ouvrez un marchand, comme « Vendre toute la camelote ». Les objets verrouillés sont conservés.",
    ["inventory.merchant.autoRepair"] = "Réparer l’équipement",
    ["inventory.merchant.autoRepair.tooltip"] = "Répare tous vos objets quand vous ouvrez un marchand qui peut réparer.",
    ["inventory.merchant.repairFunds"] = "Payer avec",
    ["inventory.merchant.repairFunds.tooltip"] = "Contrôle qui paie les réparations. Les fonds de guilde sont utilisés quand votre guilde le permet, sinon votre argent.",
    ["inventory.merchant.repairFunds.player"] = "Votre argent",
    ["inventory.merchant.repairFunds.guild"] = "Fonds de guilde d’abord",
    ["inventory.merchant.announce"] = "Annoncer dans la discussion",
    ["inventory.merchant.announce.tooltip"] = "Affiche un message dans la fenêtre de discussion avec l’argent gagné grâce à la camelote et dépensé en réparations.",
    ["inventory.merchant.sold"] = "Camelote vendue : %d |4objet:objets; pour %s.",
    ["inventory.merchant.repaired"] = "Tous les objets ont été réparés pour %s.",
    ["inventory.merchant.repairedGuild"] = "Tous les objets ont été réparés pour %s avec les fonds de guilde.",
    ["inventory.merchant.notEnoughMoney"] = "Vous n’avez pas assez d’argent pour réparer vos objets.",
})
