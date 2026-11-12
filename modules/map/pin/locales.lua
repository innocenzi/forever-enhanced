local _, ns = ...

ns:RegisterLocale("enUS", {
    ["map.pin.title"] = "Map pin",
    ["map.pin.description"] = "Sets your map pin from TomTom's /way commands, and removes it when you reach it.",
    ["map.pin.commands"] = "TomTom commands",
    ["map.pin.commands.tooltip"] = "Sets your map pin from /way coordinates written for TomTom.",
    ["map.pin.track"] = "Track the map pin",
    ["map.pin.track.tooltip"] = "Shows the navigation arrow to pins set with /way.",
    ["map.pin.arrival"] = "Clear on arrival",
    ["map.pin.arrival.tooltip"] = "Removes your map pin when you reach it.",
    ["map.pin.range"] = "Arrival distance",
    ["map.pin.range.tooltip"] = "Sets how close you need to get to the map pin.",
    ["map.pin.range.format"] = "%d yd",
    ["map.pin.announce"] = "Show arrival message",
    ["map.pin.announce.tooltip"] = "Shows a message at the top of the screen when you reach the map pin.",
    ["map.pin.unknownZone"] = "Unknown zone: %s",
    ["map.pin.usage"] = "Usage: /way [zone] x y [description], /way reset, /wayb [description], /cway",
})

ns:RegisterLocale("frFR", {
    ["map.pin.title"] = "Repère sur la carte",
    ["map.pin.description"] = "Place votre repère sur la carte avec les commandes /way de TomTom, et le retire lorsque vous l’atteignez.",
    ["map.pin.commands"] = "Commandes TomTom",
    ["map.pin.commands.tooltip"] = "Place votre repère sur la carte à partir des coordonnées /way écrites pour TomTom.",
    ["map.pin.track"] = "Suivre le repère",
    ["map.pin.track.tooltip"] = "Affiche la flèche de navigation vers les repères placés avec /way.",
    ["map.pin.arrival"] = "Retirer à l’arrivée",
    ["map.pin.arrival.tooltip"] = "Retire votre repère sur la carte lorsque vous l’atteignez.",
    ["map.pin.range"] = "Distance d’arrivée",
    ["map.pin.range.tooltip"] = "Définit à quelle distance du repère vous devez vous approcher.",
    ["map.pin.range.format"] = "%d m",
    ["map.pin.announce"] = "Afficher un message",
    ["map.pin.announce.tooltip"] = "Affiche un message en haut de l’écran lorsque vous atteignez le repère.",
    ["map.pin.unknownZone"] = "Zone inconnue : %s",
    ["map.pin.usage"] = "Utilisation : /way [zone] x y [description], /way reset, /wayb [description], /cway",
})
