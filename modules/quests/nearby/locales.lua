local _, ns = ...

ns:RegisterLocale("enUS", {
    ["quests.nearby.title"] = "Nearby Quests",
    ["quests.nearby.description"] = "Keeps the quests closest to you in the Objective Tracker and untracks the farthest ones as you move. Untrack a quest yourself to keep it out until you change zones.",
    ["quests.nearby.scope"] = "Quests to Track",
    ["quests.nearby.scope.tooltip"] = "Controls which quests the tracker shows: the closest ones, the ones within a set distance, or the ones in your current zone. The tracker never shows more than the Number of Quests set below.",
    ["quests.nearby.scope.closest"] = "Closest",
    ["quests.nearby.scope.range"] = "Within Range",
    ["quests.nearby.scope.zone"] = "Current Zone",
    ["quests.nearby.range"] = "Maximum Distance",
    ["quests.nearby.range.tooltip"] = "Quests whose nearest objective is farther away than this distance are not tracked.",
    ["quests.nearby.range.format"] = "%d yd",
    ["quests.nearby.count"] = "Number of Quests",
    ["quests.nearby.count.tooltip"] = "Sets how many nearby quests are tracked at once.",
    ["quests.nearby.keepManual"] = "Keep Manually Tracked Quests",
    ["quests.nearby.keepManual.tooltip"] = "Quests you track yourself stay tracked, even when far away. When disabled, they are untracked as soon as they are no longer among the nearby quests.",
})

ns:RegisterLocale("frFR", {
    ["quests.nearby.title"] = "Quêtes proches",
    ["quests.nearby.description"] = "Garde les quêtes les plus proches de vous dans le suivi des objectifs et arrête de suivre les plus éloignées à mesure que vous vous déplacez. Si vous arrêtez vous-même de suivre une quête, elle reste écartée jusqu’à votre prochain changement de zone.",
    ["quests.nearby.scope"] = "Quêtes à suivre",
    ["quests.nearby.scope.tooltip"] = "Contrôle les quêtes affichées dans le suivi : les plus proches, celles situées à une certaine distance ou celles de votre zone actuelle. Le suivi n’affiche jamais plus que le nombre de quêtes défini ci-dessous.",
    ["quests.nearby.scope.closest"] = "Les plus proches",
    ["quests.nearby.scope.range"] = "À portée",
    ["quests.nearby.scope.zone"] = "Zone actuelle",
    ["quests.nearby.range"] = "Distance maximale",
    ["quests.nearby.range.tooltip"] = "Les quêtes dont l’objectif le plus proche est situé au-delà de cette distance ne sont pas suivies.",
    ["quests.nearby.range.format"] = "%d m",
    ["quests.nearby.count"] = "Nombre de quêtes",
    ["quests.nearby.count.tooltip"] = "Règle le nombre de quêtes proches suivies en même temps.",
    ["quests.nearby.keepManual"] = "Garder mes quêtes suivies",
    ["quests.nearby.keepManual.tooltip"] = "Les quêtes que vous suivez vous-même restent suivies, même si elles sont éloignées. Si cette option est désactivée, leur suivi s’arrête dès qu’elles ne font plus partie des quêtes proches.",
})
