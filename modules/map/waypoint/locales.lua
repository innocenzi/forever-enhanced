local _, ns = ...

ns:RegisterLocale("enUS", {
    ["map.waypoint.title"] = "Clear map pin on arrival",
    ["map.waypoint.description"] = "Removes your map pin when you reach it.",
    ["map.waypoint.range"] = "Arrival distance",
    ["map.waypoint.range.tooltip"] = "Sets how close you need to get to the map pin.",
    ["map.waypoint.range.format"] = "%d yd",
    ["map.waypoint.announce"] = "Show arrival message",
    ["map.waypoint.announce.tooltip"] = "Shows a message at the top of the screen when you reach the map pin.",
})

ns:RegisterLocale("frFR", {
    ["map.waypoint.title"] = "Retirer le repère à l’arrivée",
    ["map.waypoint.description"] = "Retire votre repère sur la carte lorsque vous l’atteignez.",
    ["map.waypoint.range"] = "Distance d’arrivée",
    ["map.waypoint.range.tooltip"] = "Définit à quelle distance du repère vous devez vous approcher.",
    ["map.waypoint.range.format"] = "%d m",
    ["map.waypoint.announce"] = "Afficher un message",
    ["map.waypoint.announce.tooltip"] = "Affiche un message en haut de l’écran lorsque vous atteignez le repère.",
})
