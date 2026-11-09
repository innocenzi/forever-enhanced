local _, ns = ...

ns:RegisterLocale("enUS", {
    ["quests.nearby.title"] = "Nearby Quests",
    ["quests.nearby.description"] = "Keeps the quests closest to you in the objective tracker and untracks the farthest ones as you move. Untrack a quest yourself to keep it out until you change zone.",
    ["quests.nearby.scope"] = "Quests to track",
    ["quests.nearby.scope.tooltip"] = "Which quests the tracker shows: the closest ones, the ones within a distance, or the ones in your current zone. Never more than the number of quests set below.",
    ["quests.nearby.scope.closest"] = "Closest",
    ["quests.nearby.scope.range"] = "Within range",
    ["quests.nearby.scope.zone"] = "Current zone",
    ["quests.nearby.range"] = "Maximum distance",
    ["quests.nearby.range.tooltip"] = "Quests whose nearest objective is farther away than this aren't tracked.",
    ["quests.nearby.range.format"] = "%d yd",
    ["quests.nearby.count"] = "Number of quests",
    ["quests.nearby.count.tooltip"] = "How many nearby quests to track at once.",
    ["quests.nearby.keepManual"] = "Keep quests I track",
    ["quests.nearby.keepManual.tooltip"] = "Quests you track yourself stay tracked, even far away. When this is off, they're untracked as soon as they aren't among the nearby quests.",
})

ns:RegisterLocale("frFR", {
    ["quests.nearby.title"] = "Quêtes proches",
    ["quests.nearby.description"] = "Garde les quêtes les plus proches de vous dans le suivi des objectifs et retire les plus éloignées à mesure que vous vous déplacez. Retirez vous-même une quête du suivi pour l'écarter jusqu'à votre prochain changement de zone.",
    ["quests.nearby.scope"] = "Quêtes à suivre",
    ["quests.nearby.scope.tooltip"] = "Les quêtes affichées dans le suivi : les plus proches, celles à une certaine distance ou celles de votre zone actuelle. Jamais plus que le nombre de quêtes défini ci-dessous.",
    ["quests.nearby.scope.closest"] = "Les plus proches",
    ["quests.nearby.scope.range"] = "À portée",
    ["quests.nearby.scope.zone"] = "Zone actuelle",
    ["quests.nearby.range"] = "Distance maximale",
    ["quests.nearby.range.tooltip"] = "Les quêtes dont l'objectif le plus proche est plus loin que cette distance ne sont pas suivies.",
    ["quests.nearby.range.format"] = "%d m",
    ["quests.nearby.count"] = "Nombre de quêtes",
    ["quests.nearby.count.tooltip"] = "Nombre de quêtes proches suivies en même temps.",
    ["quests.nearby.keepManual"] = "Garder mes quêtes suivies",
    ["quests.nearby.keepManual.tooltip"] = "Les quêtes que vous suivez vous-même restent suivies, même lointaines. Si cette option est désactivée, elles sont retirées du suivi dès qu'elles ne font plus partie des quêtes proches.",
})
