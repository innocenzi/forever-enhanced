local _, ns = ...

ns:RegisterLocale("enUS", {
    ["inventory.food.title"] = "Food on action bars",
    ["inventory.food.description"] = "Replaces the food and drink you put on your action bars with the best you carry, as soon as you get it.",
    ["inventory.food.pick"] = "Priority",
    ["inventory.food.pick.tooltip"] = "Chooses which food or drink goes on your bars when you carry several kinds. Conjured food and water always come first.",
    ["inventory.food.pick.level"] = "Restores the most",
    ["inventory.food.pick.cheapest"] = "Lowest sell price",
    ["inventory.food.pick.largest"] = "Largest stack",
    ["inventory.food.pick.smallest"] = "Smallest stack",
    ["inventory.food.buffFood"] = "Include buff food",
    ["inventory.food.buffFood.tooltip"] = "Also puts food that makes you Well Fed on your bars. When disabled, buff food on your bars stays as it is.",
})

ns:RegisterLocale("frFR", {
    ["inventory.food.title"] = "Nourriture sur les barres",
    ["inventory.food.description"] = "Remplace la nourriture et les boissons que vous placez sur vos barres d’actions par les meilleures que vous avez sur vous, dès que vous les obtenez.",
    ["inventory.food.pick"] = "Priorité",
    ["inventory.food.pick.tooltip"] = "Choisit la nourriture ou la boisson placée sur vos barres quand vous en avez plusieurs sortes. La nourriture et l’eau invoquées passent toujours en premier.",
    ["inventory.food.pick.level"] = "Meilleure récupération",
    ["inventory.food.pick.cheapest"] = "Prix de vente le plus bas",
    ["inventory.food.pick.largest"] = "Plus grande pile",
    ["inventory.food.pick.smallest"] = "Plus petite pile",
    ["inventory.food.buffFood"] = "Inclure la nourriture à bonus",
    ["inventory.food.buffFood.tooltip"] = "Place aussi sur vos barres la nourriture qui donne l’effet Bien nourri. Si cette option est désactivée, celle déjà sur vos barres reste en place.",
})
