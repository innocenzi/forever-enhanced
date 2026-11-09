local _, ns = ...

ns:RegisterLocale("enUS", {
    ["quests.announce.title"] = "Objective announcements",
    ["quests.announce.description"] = "Tells your group when you complete a quest objective.",
    ["quests.announce.template"] = "Message",
    ["quests.announce.template.tooltip"] = "Sets the message sent to your group. {quest}: quest link, {objective}: objective, {current} and {total}: progress. Leave blank to restore the default.",
    ["quests.announce.template.default"] = '[Forever Enhanced] I am done with "{objective}" ({current}/{total})',
    ["quests.announce.channel"] = "Channel",
    ["quests.announce.channel.tooltip"] = "Controls where the message is sent.",
    ["quests.announce.channel.instance"] = "Instance or party",
    ["quests.announce.channel.party"] = "Party only",
    ["quests.announce.solo"] = "Show when solo",
    ["quests.announce.solo.tooltip"] = "Shows the message in your chat when you are not in a group.",
    ["quests.announce.hideQuestie"] = "Hide Questie announcements",
    ["quests.announce.hideQuestie.tooltip"] = "Hides quest progress messages sent by other players' Questie.",
})

ns:RegisterLocale("frFR", {
    ["quests.announce.title"] = "Annonce des objectifs",
    ["quests.announce.description"] = "Prévient votre groupe lorsque vous accomplissez un objectif de quête.",
    ["quests.announce.template"] = "Message",
    ["quests.announce.template.tooltip"] = "Définit le message envoyé à votre groupe. {quest} : lien de la quête, {objective} : objectif, {current} et {total} : progression. Laissez vide pour rétablir le message par défaut.",
    ["quests.announce.template.default"] = "[Forever Enhanced] J’ai fini « {objective} » ({current}/{total})",
    ["quests.announce.channel"] = "Canal",
    ["quests.announce.channel.tooltip"] = "Contrôle où le message est envoyé.",
    ["quests.announce.channel.instance"] = "Instance ou groupe",
    ["quests.announce.channel.party"] = "Groupe uniquement",
    ["quests.announce.solo"] = "Afficher hors groupe",
    ["quests.announce.solo.tooltip"] = "Affiche le message dans votre fenêtre de discussion lorsque vous n’êtes pas en groupe.",
    ["quests.announce.hideQuestie"] = "Masquer les annonces Questie",
    ["quests.announce.hideQuestie.tooltip"] = "Masque les messages de progression envoyés par l’AddOn Questie des autres joueurs.",
})
