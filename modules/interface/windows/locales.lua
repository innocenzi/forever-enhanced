local _, ns = ...

ns:RegisterLocale("enUS", {
    ["interface.windows.title"] = "Movable windows",
    ["interface.windows.description"] = "Lets you move windows and bags by dragging their title bar. Shift Right Click on a title bar resets its position.",
    ["interface.windows.modifier"] = "Drag key",
    ["interface.windows.modifier.tooltip"] = "Sets the key to hold to move a window.",
    ["interface.windows.modifier.none"] = "None",
    ["interface.windows.modifier.shift"] = "Shift",
    ["interface.windows.modifier.ctrl"] = "Ctrl",
    ["interface.windows.modifier.alt"] = "Alt",
})

ns:RegisterLocale("frFR", {
    ["interface.windows.title"] = "Fenêtres déplaçables",
    ["interface.windows.description"] = "Permet de déplacer les fenêtres et les sacs en faisant glisser leur barre de titre. Un Maj-clic droit sur une barre de titre rétablit sa position.",
    ["interface.windows.modifier"] = "Touche de déplacement",
    ["interface.windows.modifier.tooltip"] = "Définit la touche à maintenir pour déplacer une fenêtre.",
    ["interface.windows.modifier.none"] = "Aucune",
    ["interface.windows.modifier.shift"] = "Maj",
    ["interface.windows.modifier.ctrl"] = "Ctrl",
    ["interface.windows.modifier.alt"] = "Alt",
})
