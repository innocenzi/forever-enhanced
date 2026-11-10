local _, ns = ...

ns:RegisterLocale("enUS", {
    ["map.way.title"] = "TomTom commands",
    ["map.way.description"] = "Sets your map pin from /way coordinates written for TomTom.",
    ["map.way.track"] = "Track the map pin",
    ["map.way.track.tooltip"] = "Shows the navigation arrow to pins set with /way.",
    ["map.way.unknownZone"] = "Unknown zone: %s",
    ["map.way.usage"] = "Usage: /way [zone] x y [description], /way reset, /wayb [description], /cway",
})

ns:RegisterLocale("frFR", {
    ["map.way.title"] = "Commandes TomTom",
    ["map.way.description"] = "Place votre repère sur la carte à partir des coordonnées /way écrites pour TomTom.",
    ["map.way.track"] = "Suivre le repère",
    ["map.way.track.tooltip"] = "Affiche la flèche de navigation vers les repères placés avec /way.",
    ["map.way.unknownZone"] = "Zone inconnue : %s",
    ["map.way.usage"] = "Utilisation : /way [zone] x y [description], /way reset, /wayb [description], /cway",
})
