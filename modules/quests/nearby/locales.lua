local _, ns = ...

ns:RegisterLocale("enUS", {
    ["quests.nearby.title"] = "Nearby quests",
    ["quests.nearby.description"] = "Tracks the quests closest to you as you move. A quest you untrack stays untracked until you change zones.",
    ["quests.nearby.scope"] = "Quests to track",
    ["quests.nearby.scope.tooltip"] = "Controls which quests are tracked, up to the number of quests set below.",
    ["quests.nearby.scope.closest"] = "Closest",
    ["quests.nearby.scope.range"] = "Within range",
    ["quests.nearby.scope.zone"] = "Current zone",
    ["quests.nearby.range"] = "Maximum distance",
    ["quests.nearby.range.tooltip"] = "Quests farther away than this are not tracked.",
    ["quests.nearby.range.format"] = "%d yd",
    ["quests.nearby.count"] = "Number of quests",
    ["quests.nearby.count.tooltip"] = "Sets how many quests are tracked at once.",
    ["quests.nearby.keepManual"] = "Keep manually tracked quests",
    ["quests.nearby.keepManual.tooltip"] = "Keeps quests you track yourself, even when they are far away.",
})

ns:RegisterLocale("frFR", {
    ["quests.nearby.title"] = "Quêtes proches",
    ["quests.nearby.description"] = "Suit les quêtes les plus proches de vous à mesure que vous vous déplacez. Une quête que vous ne suivez plus reste écartée jusqu’au prochain changement de zone.",
    ["quests.nearby.scope"] = "Quêtes à suivre",
    ["quests.nearby.scope.tooltip"] = "Contrôle les quêtes suivies, dans la limite du nombre de quêtes défini ci-dessous.",
    ["quests.nearby.scope.closest"] = "Les plus proches",
    ["quests.nearby.scope.range"] = "À portée",
    ["quests.nearby.scope.zone"] = "Zone actuelle",
    ["quests.nearby.range"] = "Distance maximale",
    ["quests.nearby.range.tooltip"] = "Les quêtes plus éloignées ne sont pas suivies.",
    ["quests.nearby.range.format"] = "%d m",
    ["quests.nearby.count"] = "Nombre de quêtes",
    ["quests.nearby.count.tooltip"] = "Définit le nombre de quêtes suivies en même temps.",
    ["quests.nearby.keepManual"] = "Garder mes quêtes suivies",
    ["quests.nearby.keepManual.tooltip"] = "Garde les quêtes que vous suivez vous-même, même si elles sont éloignées.",
})
