local _, ns = ...

ns:RegisterLocale("enUS", {
    ["interface.windows.title"] = "Movable windows",
    ["interface.windows.description"] = "Drag windows and bags by their title bar to move them. Shift Right Click a title bar to reset its position.",
    ["interface.windows.modifier"] = "Drag key",
    ["interface.windows.modifier.tooltip"] = "Sets the key to hold to move a window.",
    ["interface.windows.modifier.none"] = "None",
    ["interface.windows.modifier.shift"] = "Shift",
    ["interface.windows.modifier.ctrl"] = "Ctrl",
    ["interface.windows.modifier.alt"] = "Alt",
})

ns:RegisterLocale("frFR", {
    ["interface.windows.title"] = "Fenêtres déplaçables",
    ["interface.windows.description"] = "Faites glisser les fenêtres et les sacs par leur barre de titre pour les déplacer. Maj-clic droit sur une barre de titre pour rétablir sa position.",
    ["interface.windows.modifier"] = "Touche de déplacement",
    ["interface.windows.modifier.tooltip"] = "Définit la touche à maintenir pour déplacer une fenêtre.",
    ["interface.windows.modifier.none"] = "Aucune",
    ["interface.windows.modifier.shift"] = "Maj",
    ["interface.windows.modifier.ctrl"] = "Ctrl",
    ["interface.windows.modifier.alt"] = "Alt",
})
