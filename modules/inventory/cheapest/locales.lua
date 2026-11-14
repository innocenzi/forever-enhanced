local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.cheapest.title"] = "Lowest value items",
    ["inventory.cheapest.description"] = "Marks the items in your bags worth the least, by sell or auction price, so you know what to destroy.",
    ["inventory.cheapest.onlyWhenFull"] = "Only when bags are full",
    ["inventory.cheapest.onlyWhenFull.tooltip"] = "Shows the mark only while your bags have no free slot.",
    ["inventory.cheapest.indicator"] = "Indicator",
    ["inventory.cheapest.indicator.tooltip"] = "Controls how the lowest value items are marked.",
    ["inventory.cheapest.indicator.glow"] = "Red glow",
    ["inventory.cheapest.indicator.cross"] = "Red cross",
    ["inventory.cheapest.indicator.coin"] = "Copper coin",
})

ns:RegisterLocale("frFR", {
    ["inventory.cheapest.title"] = "Objets de moindre valeur",
    ["inventory.cheapest.description"] = "Marque les objets de vos sacs qui valent le moins, au prix de vente ou aux enchères, pour savoir lesquels détruire.",
    ["inventory.cheapest.onlyWhenFull"] = "Seulement si sacs pleins",
    ["inventory.cheapest.onlyWhenFull.tooltip"] = "Affiche la marque seulement quand vos sacs n’ont plus d’emplacement libre.",
    ["inventory.cheapest.indicator"] = "Indicateur",
    ["inventory.cheapest.indicator.tooltip"] = "Contrôle comment les objets de moindre valeur sont signalés.",
    ["inventory.cheapest.indicator.glow"] = "Lueur rouge",
    ["inventory.cheapest.indicator.cross"] = "Croix rouge",
    ["inventory.cheapest.indicator.coin"] = "Pièce de cuivre",
})
