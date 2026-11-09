local _, ns = ...

ns:RegisterLocale("enUS", {
    ["interface.waypoint.title"] = "Clear map pin on arrival",
    ["interface.waypoint.description"] = "Removes your map pin when you reach it.",
    ["interface.waypoint.range"] = "Arrival distance",
    ["interface.waypoint.range.tooltip"] = "Sets how close you need to get to the map pin.",
    ["interface.waypoint.range.format"] = "%d yd",
    ["interface.waypoint.announce"] = "Show arrival message",
    ["interface.waypoint.announce.tooltip"] = "Shows a message at the top of the screen when you reach the map pin.",
})

ns:RegisterLocale("frFR", {
    ["interface.waypoint.title"] = "Retirer le repère à l’arrivée",
    ["interface.waypoint.description"] = "Retire votre repère sur la carte lorsque vous l’atteignez.",
    ["interface.waypoint.range"] = "Distance d’arrivée",
    ["interface.waypoint.range.tooltip"] = "Définit à quelle distance du repère vous devez vous approcher.",
    ["interface.waypoint.range.format"] = "%d m",
    ["interface.waypoint.announce"] = "Afficher un message",
    ["interface.waypoint.announce.tooltip"] = "Affiche un message en haut de l’écran lorsque vous atteignez le repère.",
})
