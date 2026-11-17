local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.merchant.title"] = "Merchant",
    ["inventory.merchant.description"] = "Adds a search box to merchants, and can sell your junk and repair your items for you.",
    ["inventory.merchant.search"] = "Search box",
    ["inventory.merchant.search.tooltip"] = "Searches a merchant's items across all pages.",
    ["inventory.merchant.autoSellJunk"] = "Auto sell junk",
    ["inventory.merchant.autoSellJunk.tooltip"] = "Sells your junk when you visit a merchant.",
    ["inventory.merchant.autoRepair"] = "Auto repair",
    ["inventory.merchant.autoRepair.tooltip"] = "Repairs your items when you visit a merchant who can repair.",
    ["inventory.merchant.guildFunds"] = "Use guild funds first",
    ["inventory.merchant.guildFunds.tooltip"] = "Pays for repairs with guild funds when your guild allows it.",
    ["inventory.merchant.announce"] = "Announce in chat",
    ["inventory.merchant.announce.tooltip"] = "Shows in chat what you earned from junk and spent on repairs.",
    ["inventory.merchant.sold"] = "Sold %d |4junk item:junk items; for %s.",
    ["inventory.merchant.repaired"] = "Repaired your items for %s.",
    ["inventory.merchant.repairedGuild"] = "Repaired your items for %s with guild funds.",
    ["inventory.merchant.notEnoughMoney"] = "You don't have enough money to repair.",
})

ns:RegisterLocale("frFR", {
    ["inventory.merchant.title"] = "Marchand",
    ["inventory.merchant.description"] = "Ajoute un champ de recherche aux marchands, et peut vendre votre camelote et réparer vos objets à votre place.",
    ["inventory.merchant.search"] = "Champ de recherche",
    ["inventory.merchant.search.tooltip"] = "Recherche parmi les objets d’un marchand, sur toutes ses pages.",
    ["inventory.merchant.autoSellJunk"] = "Vendre la camelote",
    ["inventory.merchant.autoSellJunk.tooltip"] = "Vend votre camelote quand vous parlez à un marchand.",
    ["inventory.merchant.autoRepair"] = "Réparer l’équipement",
    ["inventory.merchant.autoRepair.tooltip"] = "Répare vos objets quand vous parlez à un marchand qui peut réparer.",
    ["inventory.merchant.guildFunds"] = "Utiliser les fonds de guilde",
    ["inventory.merchant.guildFunds.tooltip"] = "Paie les réparations avec les fonds de guilde quand votre guilde le permet.",
    ["inventory.merchant.announce"] = "Annoncer dans la discussion",
    ["inventory.merchant.announce.tooltip"] = "Affiche dans la discussion l’argent gagné avec la camelote et dépensé en réparations.",
    ["inventory.merchant.sold"] = "Camelote vendue : %d |4objet:objets; pour %s.",
    ["inventory.merchant.repaired"] = "Objets réparés pour %s.",
    ["inventory.merchant.repairedGuild"] = "Objets réparés pour %s avec les fonds de guilde.",
    ["inventory.merchant.notEnoughMoney"] = "Vous n’avez pas assez d’argent pour réparer.",
})
