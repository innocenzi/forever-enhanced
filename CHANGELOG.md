# Changelog

## 1.0.0 - 2026-11-12


### Features
- **core:** show chat messages like the game's system messages, without the addon prefix
- **inventory:** keep the item menu open after releasing Alt, and mark junk from Merchant
- **map:** show the world map as one seamless map, zoomed and panned across zones
- **map:** group TomTom commands and clearing the pin on arrival under Map pin
- **inventory:** mark items as junk, for the auction house or for the bank, and choose what Alt Left Click does
- **core:** order settings by interest, make presets consistent and hide Questie announcements on their own
- **inventory:** make items marked for the auction house glow while it is open
- **inventory:** stop announcing item locks in chat
- **quests:** stop showing objective announcements in chat when solo
- **combat:** let the spell swaps editor move like other windows


### Fixes
- **interface:** shorten the French object glow title to fit the settings list

## 0.4.0 - 2026-11-12


### Features
- **professions:** mark the recipes in reagent tooltips the bags hold the reagents for
- **inventory:** open an item menu on Alt Right Click, and mark items as junk

## 0.3.0 - 2026-11-11


### Features
- **quests:** optionally track dungeon quests only inside their dungeon
- **interface:** optionally cast a spell from the button of the spell it replaces while it can be cast
- **interface:** replace spells on action bars with their new rank when learned
- **quests:** optionally sort tracked quests by distance
- **core:** reorganize the options into clearer pages
- **combat:** let players choose their own ability swaps
- **professions:** list the recipes that use a reagent while Shift is held


### Fixes
- **map:** name and color friends on the map who were never met nearby
- **core:** keep the settings search from blocking the push-to-talk keybinding
- **interface:** stop action buttons staying pressed after Ambush breaks Stealth
- **combat:** hide the errors of ability swaps' failed casts and let their spells be dragged

## 0.2.0 - 2026-11-10


### Features
- **core:** let players choose the addon's language
- merge related settings into bank and quest helpers features
- **map:** set the map pin with TomTom's /way commands
- **core:** add minimal and enhanced setting presets
- **map:** show friends who use the addon on the world map
- **map:** optionally show friends who use OpenMap on the world map


### Fixes
- **quests:** keep nearby tracking from erroring while the zone has no quest data
- **map:** pin /way coordinates on the zone from starting areas, caves and buildings
- **core:** keep the settings panel from blocking Blizzard's audio options
- **quests:** hide the chat bubbles of other players' Questie announcements
- **quests:** show quest objectives in item tooltips on non-English clients
- **map:** tell players that friends on the map and the Enhanced preset share their position

## 0.1.0 - 2026-11-10


### Features
- **core:** add module and feature framework with a generated settings panel
- **inventory:** lock items to protect them from being sold, moved or deleted
- **core:** show the addon icon in the AddOns list
- **inventory:** keep locked items in place when sorting
- **inventory:** sell unlocked junk when some junk is locked
- **quests:** track the quests nearest to you
- **inventory:** browse your saved bank and your alts' banks anywhere
- **inventory:** deposit and withdraw items between bags and bank
- **inventory:** show how many of an item your saved bank holds in its tooltip
- **inventory:** mark recipe reagents your saved bank can supply
- **interface:** move windows and bags by their title bar
- **interface:** remove the map pin when arriving near it
- **quests:** announce completed quest objectives to the group
- **inventory:** sell junk and repair automatically at merchants
- **interface:** show combo points on enemy nameplates
- **inventory:** write notes on locked items, shown in their tooltip
- **quests:** keep the sparkle on lootable quest items after picking a graphics preset
- **interface:** make the nearest herb, ore vein or quest object glow
- **quests:** show in item tooltips the quests that need the item
- **quests:** turn nearby quests off by default


### Fixes
- **inventory:** keep the deposit and withdraw buttons clear of the bank's money frame
- **inventory:** fill locked stacks when transferring items
- **core:** word every setting and message like the game's own text
- **interface:** put windows back at once on Shift Right Click
- **core:** wait for the end of combat before moving items
- **interface:** keep combo points under the cast bar in combat without errors

