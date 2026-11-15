local _, ns = ...

ns:RegisterLocale("enUS", {
    ["quests.helpers.title"] = "Quest helpers",
    ["quests.helpers.description"] = "Tells you what your quest items are for, makes them sparkle, and keeps Questie and Polestar announcements out of group chat.",
    ["quests.helpers.sparkles"] = "Quest item sparkles",
    ["quests.helpers.sparkles.tooltip"] = "Makes quest items you can loot sparkle, along with some quest NPCs.",
    ["quests.helpers.sparkles.restart"] = "Restart the game to remove the sparkle from quest items.",
    ["quests.helpers.objectives"] = "Quest objectives in tooltips",
    ["quests.helpers.objectives.tooltip"] = "Shows the quests in your log that need an item, with your progress.",
    ["quests.helpers.objectives.line"] = "%s (%d/%d)",
    ["quests.helpers.leftovers"] = "Leftover quest items",
    ["quests.helpers.leftovers.tooltip"] = "Shows which quest items you no longer need, for quests you complete while this option is on.",
    ["quests.helpers.leftovers.line"] = "Quest completed: %s",
    ["quests.helpers.leftovers.lineUnknown"] = "Quest completed",
    ["quests.helpers.leftoverMark"] = "Show check mark",
    ["quests.helpers.leftoverMark.tooltip"] = "Shows a check mark on these items in your bags and bank.",
    ["quests.helpers.hideAnnouncements"] = "Hide quest addon announcements",
    ["quests.helpers.hideAnnouncements.tooltip"] = "Hides quest progress messages sent by other players' Questie or Polestar.",
})

ns:RegisterLocale("frFR", {
    ["quests.helpers.title"] = "Aides aux quêtes",
    ["quests.helpers.description"] = "Indique à quoi servent vos objets de quête, les fait scintiller et retire les annonces Questie et Polestar de la discussion de groupe.",
    ["quests.helpers.sparkles"] = "Objets de quête scintillants",
    ["quests.helpers.sparkles.tooltip"] = "Fait scintiller les objets de quête à ramasser, ainsi que certains PNJ de quête.",
    ["quests.helpers.sparkles.restart"] = "Redémarrez le jeu pour retirer le scintillement des objets de quête.",
    ["quests.helpers.objectives"] = "Objectifs dans les infobulles",
    ["quests.helpers.objectives.tooltip"] = "Affiche les quêtes de votre journal qui ont besoin de l’objet, avec votre progression.",
    ["quests.helpers.objectives.line"] = "%s (%d/%d)",
    ["quests.helpers.leftovers"] = "Objets de quête obsolètes",
    ["quests.helpers.leftovers.tooltip"] = "Indique les objets de quête dont vous n’avez plus besoin, pour les quêtes terminées pendant que l’option est activée.",
    ["quests.helpers.leftovers.line"] = "Quête terminée : %s",
    ["quests.helpers.leftovers.lineUnknown"] = "Quête terminée",
    ["quests.helpers.leftoverMark"] = "Afficher une coche",
    ["quests.helpers.leftoverMark.tooltip"] = "Affiche une coche sur ces objets dans vos sacs et votre banque.",
    ["quests.helpers.hideAnnouncements"] = "Masquer les annonces d’AddOns",
    ["quests.helpers.hideAnnouncements.tooltip"] = "Masque les messages de progression envoyés par les AddOns Questie et Polestar des autres joueurs.",
})
