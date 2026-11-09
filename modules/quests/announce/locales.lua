local _, ns = ...

ns:RegisterLocale("enUS", {
    ["quests.announce.title"] = "Objective Announcements",
    ["quests.announce.description"] = "Tells your group when you complete one of your quest objectives, with a message you write. Each objective is announced once.",
    ["quests.announce.template"] = "Message",
    ["quests.announce.template.tooltip"] = "Sets the message sent when you complete a quest objective. Variables: {quest} for the quest link, {objective} for the objective, {current} and {total} for its progress. Raid target icons like {rt1} are kept. Clear the field to restore the default message.",
    ["quests.announce.template.default"] = '[Forever Enhanced] I am done with "{objective}" ({current}/{total})',
    ["quests.announce.channel"] = "Channel",
    ["quests.announce.channel.tooltip"] = "Controls where the message is sent. Instance or Party: your instance group when you are in one, otherwise your party. Party Only: your party.",
    ["quests.announce.channel.instance"] = "Instance or Party",
    ["quests.announce.channel.party"] = "Party Only",
    ["quests.announce.solo"] = "Show When Solo",
    ["quests.announce.solo.tooltip"] = "Shows the message in your own chat when you complete an objective while not in a group. When disabled, nothing is shown outside a group.",
    ["quests.announce.hideQuestie"] = "Hide Questie Announcements",
    ["quests.announce.hideQuestie.tooltip"] = "Hides the quest progress messages that other players' Questie AddOn sends to your group. Chat that only mentions Questie is kept.",
})

ns:RegisterLocale("frFR", {
    ["quests.announce.title"] = "Annonce des objectifs",
    ["quests.announce.description"] = "Prévient votre groupe lorsque vous accomplissez un objectif de quête, avec un message que vous rédigez. Chaque objectif n’est annoncé qu’une fois.",
    ["quests.announce.template"] = "Message",
    ["quests.announce.template.tooltip"] = "Définit le message envoyé lorsque vous accomplissez un objectif de quête. Variables : {quest} pour le lien de la quête, {objective} pour l’objectif, {current} et {total} pour sa progression. Les icônes de cible comme {rt1} sont conservées. Videz le champ pour rétablir le message par défaut.",
    ["quests.announce.template.default"] = "[Forever Enhanced] J’ai fini « {objective} » ({current}/{total})",
    ["quests.announce.channel"] = "Canal",
    ["quests.announce.channel.tooltip"] = "Contrôle où le message est envoyé. Instance ou groupe : votre groupe d’instance si vous en faites partie, sinon votre groupe. Groupe uniquement : votre groupe.",
    ["quests.announce.channel.instance"] = "Instance ou groupe",
    ["quests.announce.channel.party"] = "Groupe uniquement",
    ["quests.announce.solo"] = "Afficher hors groupe",
    ["quests.announce.solo.tooltip"] = "Affiche le message dans votre propre fenêtre de discussion lorsque vous accomplissez un objectif sans être en groupe. Si cette option est désactivée, rien n’est affiché hors groupe.",
    ["quests.announce.hideQuestie"] = "Masquer les annonces Questie",
    ["quests.announce.hideQuestie.tooltip"] = "Masque les messages de progression de quête que l’AddOn Questie des autres joueurs envoie à votre groupe. Les messages qui mentionnent simplement Questie sont conservés.",
})
