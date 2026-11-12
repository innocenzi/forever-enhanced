local _, ns = ...

ns:RegisterLocale("enUS", {
    ["combat.swaps.title"] = "Spell swaps",
    ["combat.swaps.description"] = "Shows a spell in place of another on your action bars while you can cast it.",
    ["combat.swaps.edit"] = "Edit",
    ["combat.swaps.editor.hint"] = "The spell on the right replaces the spell on the left on your action bars while you can cast it.",
    ["combat.swaps.editor.original"] = "Spell to replace",
    ["combat.swaps.editor.replacement"] = "Replace with",
    ["combat.swaps.editor.pick"] = "Click to choose a spell.",
    ["combat.swaps.editor.notSpell"] = "Only spells can be placed here.",
    ["combat.swaps.editor.sameSpell"] = "A spell can't replace itself.",
    ["combat.swaps.editor.alreadySwapped"] = "That spell is already replaced.",
})

ns:RegisterLocale("frFR", {
    ["combat.swaps.title"] = "Remplacement de sorts",
    ["combat.swaps.description"] = "Affiche un sort à la place d’un autre sur vos barres d’action tant que vous pouvez le lancer.",
    ["combat.swaps.edit"] = "Modifier",
    ["combat.swaps.editor.hint"] = "Le sort de droite remplace celui de gauche sur vos barres d’action tant que vous pouvez le lancer.",
    ["combat.swaps.editor.original"] = "Sort à remplacer",
    ["combat.swaps.editor.replacement"] = "Remplacer par",
    ["combat.swaps.editor.pick"] = "Cliquez pour choisir un sort.",
    ["combat.swaps.editor.notSpell"] = "Seuls des sorts peuvent être placés ici.",
    ["combat.swaps.editor.sameSpell"] = "Un sort ne peut pas se remplacer lui-même.",
    ["combat.swaps.editor.alreadySwapped"] = "Ce sort est déjà remplacé.",
})
