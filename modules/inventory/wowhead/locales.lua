local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.wowhead.title"] = "Wowhead link",
    ["inventory.wowhead.description"] = 'Adds "Wowhead link" to the item menu (Alt Right Click): it shows the item\'s Wowhead address, ready to copy.',
    ["inventory.wowhead.link"] = "Wowhead link",
    ["inventory.wowhead.prompt"] = "Press Ctrl+C to copy the Wowhead link for %s.",
    ["inventory.wowhead.url"] = "https://www.wowhead.com/forever/item=%s",
})

ns:RegisterLocale("frFR", {
    ["inventory.wowhead.title"] = "Lien Wowhead",
    ["inventory.wowhead.description"] = "Ajoute « Lien Wowhead » au menu des objets (Alt-clic droit) : il affiche l’adresse Wowhead de l’objet, prête à copier.",
    ["inventory.wowhead.link"] = "Lien Wowhead",
    ["inventory.wowhead.prompt"] = "Appuyez sur Ctrl+C pour copier le lien Wowhead de %s.",
    ["inventory.wowhead.url"] = "https://www.wowhead.com/forever/fr/item=%s",
})
