local _, ns = ...

ns:RegisterLocale("enUS", {
    ["interface.glow.title"] = "Glow on nearest object",
    ["interface.glow.description"] = "Makes the nearest herb, ore vein or quest object glow while out of combat: bright when you can use it, gray when you can't. While it's on, helpful spells cast with no target may land on a nearby character instead of you.",
    ["interface.glow.herbs"] = "Herbs",
    ["interface.glow.ore"] = "Ore veins",
    ["interface.glow.quest"] = "Quest objects",
    ["interface.glow.other"] = "Other objects",
    ["interface.glow.other.tooltip"] = "Also makes chests, doors and other objects you can use glow.",
    ["interface.glow.icon"] = "Show icon",
    ["interface.glow.icon.tooltip"] = "Shows the interaction icon above glowing objects.",
    ["interface.glow.range"] = "Range",
    ["interface.glow.range.tooltip"] = "Sets how far away an object can glow.",
    ["interface.glow.range.format"] = "%d yd",
})

ns:RegisterLocale("frFR", {
    ["interface.glow.title"] = "Lueur de l’objet proche",
    ["interface.glow.description"] = "Fait briller la plante, le filon ou l’objet de quête le plus proche hors combat : vif quand vous pouvez l’utiliser, gris sinon. Tant que l’option est activée, les sorts bénéfiques lancés sans cible peuvent toucher un personnage proche au lieu de vous.",
    ["interface.glow.herbs"] = "Plantes",
    ["interface.glow.ore"] = "Filons",
    ["interface.glow.quest"] = "Objets de quête",
    ["interface.glow.other"] = "Autres objets",
    ["interface.glow.other.tooltip"] = "Fait aussi briller les coffres, les portes et les autres objets utilisables.",
    ["interface.glow.icon"] = "Afficher l’icône",
    ["interface.glow.icon.tooltip"] = "Affiche l’icône d’interaction au-dessus des objets qui brillent.",
    ["interface.glow.range"] = "Portée",
    ["interface.glow.range.tooltip"] = "Définit la distance jusqu’à laquelle un objet peut briller.",
    ["interface.glow.range.format"] = "%d m",
})
