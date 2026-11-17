local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.auction.title"] = "Auction house prices",
    ["inventory.auction.description"] = "Shows in item tooltips the lowest buyout price seen at the auction house.",
    ["inventory.auction.scan"] = "Scan when opened",
    ["inventory.auction.scan.tooltip"] = "Records the price of every auction when you open the auction house.",
    ["inventory.auction.unit"] = "Unit price",
    ["inventory.auction.unit.tooltip"] = "Shows the price per item of a stack while you hold Shift.",
    ["inventory.auction.age"] = "Price age",
    ["inventory.auction.age.tooltip"] = "Shows how long ago the price was seen.",
    ["inventory.auction.price"] = "Auction price: %s",
    ["inventory.auction.priceAge"] = "Auction price (%s): %s",
    ["inventory.auction.unitPrice"] = "Auction unit price: %s",
    ["inventory.auction.hoursAgo"] = "%d |4hour:hours; ago",
    ["inventory.auction.daysAgo"] = "%d |4day:days; ago",
})

ns:RegisterLocale("frFR", {
    ["inventory.auction.title"] = "Prix de l’hôtel des ventes",
    ["inventory.auction.description"] = "Affiche dans l’infobulle des objets le prix d’achat immédiat le plus bas relevé à l’hôtel des ventes.",
    ["inventory.auction.scan"] = "Analyser à l’ouverture",
    ["inventory.auction.scan.tooltip"] = "Enregistre le prix de toutes les enchères quand vous ouvrez l’hôtel des ventes.",
    ["inventory.auction.unit"] = "Prix unitaire",
    ["inventory.auction.unit.tooltip"] = "Affiche le prix à l’unité d’une pile quand vous maintenez Maj.",
    ["inventory.auction.age"] = "Ancienneté du prix",
    ["inventory.auction.age.tooltip"] = "Affiche depuis quand le prix a été relevé.",
    ["inventory.auction.price"] = "Prix aux enchères : %s",
    ["inventory.auction.priceAge"] = "Prix aux enchères (%s) : %s",
    ["inventory.auction.unitPrice"] = "Prix unitaire aux enchères : %s",
    ["inventory.auction.hoursAgo"] = "il y a %d |4heure:heures;",
    ["inventory.auction.daysAgo"] = "il y a %d |4jour:jours;",
})
