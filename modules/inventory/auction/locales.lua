local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.auction.title"] = "Auction house prices",
    ["inventory.auction.description"] = "Shows in item tooltips the lowest buyout price seen at the auction house.",
    ["inventory.auction.scan"] = "Scan on opening",
    ["inventory.auction.scan.tooltip"] = "Records the price of every auction when you open the auction house, at most every 15 minutes.",
    ["inventory.auction.stack"] = "Stack price",
    ["inventory.auction.stack.tooltip"] = "Also shows the price of the whole stack while you hold Shift.",
    ["inventory.auction.age"] = "Price age",
    ["inventory.auction.age.tooltip"] = "Shows how long ago the price was seen, once it is over an hour old.",
    ["inventory.auction.price"] = "Auction price: %s",
    ["inventory.auction.priceAge"] = "Auction price (%s): %s",
    ["inventory.auction.stackPrice"] = "Auction price x%d: %s",
    ["inventory.auction.hoursAgo"] = "%d |4hour:hours; ago",
    ["inventory.auction.daysAgo"] = "%d |4day:days; ago",
})

ns:RegisterLocale("frFR", {
    ["inventory.auction.title"] = "Prix de l’hôtel des ventes",
    ["inventory.auction.description"] = "Affiche dans l’infobulle des objets le prix d’achat immédiat le plus bas relevé à l’hôtel des ventes.",
    ["inventory.auction.scan"] = "Analyser à l’ouverture",
    ["inventory.auction.scan.tooltip"] = "Enregistre le prix de toutes les enchères quand vous ouvrez l’hôtel des ventes, au plus toutes les 15 minutes.",
    ["inventory.auction.stack"] = "Prix de la pile",
    ["inventory.auction.stack.tooltip"] = "Affiche aussi le prix de la pile entière quand vous maintenez Maj.",
    ["inventory.auction.age"] = "Ancienneté du prix",
    ["inventory.auction.age.tooltip"] = "Affiche depuis quand le prix a été relevé, s’il date de plus d’une heure.",
    ["inventory.auction.price"] = "Prix aux enchères : %s",
    ["inventory.auction.priceAge"] = "Prix aux enchères (%s) : %s",
    ["inventory.auction.stackPrice"] = "Prix aux enchères x%d : %s",
    ["inventory.auction.hoursAgo"] = "il y a %d |4heure:heures;",
    ["inventory.auction.daysAgo"] = "il y a %d |4jour:jours;",
})
