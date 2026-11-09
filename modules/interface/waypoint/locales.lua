local _, ns = ...

ns:RegisterLocale("enUS", {
    ["interface.waypoint.title"] = "Clear Map Pin on Arrival",
    ["interface.waypoint.description"] = "Removes your map pin once you get close to it, whether you are tracking it or not. A pin placed where you already stand stays until you walk away and come back.",
    ["interface.waypoint.range"] = "Arrival Distance",
    ["interface.waypoint.range.tooltip"] = "Sets how close you need to get to the map pin for it to be removed.",
    ["interface.waypoint.range.format"] = "%d yd",
    ["interface.waypoint.announce"] = "Show Arrival Message",
    ["interface.waypoint.announce.tooltip"] = "Shows a message at the top of the screen when the map pin is removed. When disabled, the pin disappears silently.",
})

ns:RegisterLocale("frFR", {
    ["interface.waypoint.title"] = "Retirer le repère à l’arrivée",
    ["interface.waypoint.description"] = "Retire votre repère sur la carte dès que vous vous en approchez, que vous le suiviez ou non. Un repère placé là où vous vous trouvez déjà reste en place jusqu’à ce que vous vous éloigniez puis reveniez.",
    ["interface.waypoint.range"] = "Distance d’arrivée",
    ["interface.waypoint.range.tooltip"] = "Règle la distance à laquelle vous devez vous approcher du repère pour qu’il soit retiré.",
    ["interface.waypoint.range.format"] = "%d m",
    ["interface.waypoint.announce"] = "Afficher un message",
    ["interface.waypoint.announce.tooltip"] = "Affiche un message en haut de l’écran lorsque le repère est retiré. Si cette option est désactivée, le repère disparaît sans message.",
})
