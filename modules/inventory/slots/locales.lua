local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.slots.title"] = "Reserved slots",
    ["inventory.slots.description"] = "Reserves a bag or bank slot for an item from the item menu (Alt Right Click): when you get the item again or clean up, it goes back to that slot.",
    ["inventory.slots.showIcon"] = "Show item in empty slots",
    ["inventory.slots.showIcon.tooltip"] = "Shows a faded icon of the reserved item while its slot is empty.",
    ["inventory.slots.reserve"] = "Reserve this slot",
})

ns:RegisterLocale("frFR", {
    ["inventory.slots.title"] = "Emplacements réservés",
    ["inventory.slots.description"] = "Réserve un emplacement de vos sacs ou de votre banque à un objet depuis le menu des objets (Alt-clic droit) : quand vous récupérez l’objet ou rangez vos sacs ou votre banque, il retourne à cet emplacement.",
    ["inventory.slots.showIcon"] = "Afficher l’objet réservé",
    ["inventory.slots.showIcon.tooltip"] = "Affiche l’icône estompée de l’objet réservé tant que son emplacement est vide.",
    ["inventory.slots.reserve"] = "Réserver cet emplacement",
})
