local _, ns = ...

ns:RegisterLocale("enUS", {
    ["combat.errors.title"] = "Hide error messages",
    ["combat.errors.description"] = 'Hides the red error messages in the middle of the screen, such as "Not enough mana" or "Out of range", and their voice lines: all of them, or only those of the spells you choose.',
    ["combat.errors.choose"] = "Choose spells",
    ["combat.errors.spells"] = "Chosen spells only",
    ["combat.errors.spells.tooltip"] = "Hides only the errors shown when you cast a spell picked with Choose spells.",
    ["combat.errors.combat"] = "Hide only in combat",
    ["combat.errors.combat.tooltip"] = "Keeps showing error messages out of combat.",
    ["combat.errors.editor.hint"] = "Hides the error messages shown when you cast these spells.",
    ["combat.errors.editor.add"] = "Add a spell",
    ["combat.errors.editor.pick"] = "Click to choose a spell, or drop one here.",
    ["combat.errors.editor.remove"] = "<Right Click to remove>",
    ["combat.errors.editor.notSpell"] = "Only spells can be placed here.",
    ["combat.errors.editor.alreadyChosen"] = "That spell is already on the list.",
})

ns:RegisterLocale("frFR", {
    ["combat.errors.title"] = "Masquer les messages d’erreur",
    ["combat.errors.description"] = "Masque les messages d’erreur rouges au centre de l’écran, comme « Pas assez de mana » ou « Hors de portée », et les messages vocaux qui les accompagnent : tous, ou seulement ceux des sorts que vous choisissez.",
    ["combat.errors.choose"] = "Choisir les sorts",
    ["combat.errors.spells"] = "Sorts choisis uniquement",
    ["combat.errors.spells.tooltip"] = "Masque seulement les erreurs qui s’affichent quand vous lancez un sort choisi avec Choisir les sorts.",
    ["combat.errors.combat"] = "Masquer uniquement en combat",
    ["combat.errors.combat.tooltip"] = "Continue d’afficher les messages d’erreur hors combat.",
    ["combat.errors.editor.hint"] = "Masque les messages d’erreur qui s’affichent quand vous lancez ces sorts.",
    ["combat.errors.editor.add"] = "Ajouter un sort",
    ["combat.errors.editor.pick"] = "Cliquez pour choisir un sort, ou déposez-en un ici.",
    ["combat.errors.editor.remove"] = "<Clic droit pour retirer>",
    ["combat.errors.editor.notSpell"] = "Seuls des sorts peuvent être placés ici.",
    ["combat.errors.editor.alreadyChosen"] = "Ce sort est déjà dans la liste.",
})
