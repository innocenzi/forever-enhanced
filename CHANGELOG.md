# Changelog

## 1.7.0 - 2026-11-23


### Features
- **professions:** plan recipes to take their reagents from the bank at the next visit
- **map:** drag a map at Blizzard's widest view into the seamless view
- **inventory:** keep the best food and drink you carry on the action bar slots holding them
- **inventory:** never mark food, quest items, tools, reagents and other kept items as lowest value
- **map:** show on the world map how much of the map in view is explored


### Fixes
- **map:** name group members by their full name on the seamless view

## 1.6.0 - 2026-11-22


### Features
- **combat:** show on health bars what Death Mark will deal from the bleeds it stores
- **combat:** add the strikes and white swings Death Mark stores, through the target's armor, shown apart from the bleeds
- **combat:** show what Death Mark will deal from the health's end, the bleeds from the bar's left end
- **map:** zoom out past Blizzard's world map into a seamless view of the whole world


### Fixes
- **inventory:** close the gaps locked items leave when bags or bank are sorted

## 1.5.1 - 2026-11-20


### Features
- **combat:** hide the game's red error messages, for every spell or only chosen ones


### Fixes
- **map:** hide Swap layer from the player frame's menu while in a group
- **map:** merge Desolace's and Feralas' mountains on the seamless map
- **inventory:** put locked items back after a sort in two rounds at most
- **map:** make the Shimmering Flats' cliffs the seam between Thousand Needles and Tanaris on the seamless map
- **map:** update Blizzard's objective tracker again after combat once the seamless map's taint stopped it


### Performance
- **core:** send the item mover's swaps a few per frame

## 1.5.0 - 2026-11-19


### Features
- **inventory:** dim the rest of the bags and bank while Shift is held over an item, leaving its stacks lit
- **inventory:** make the merchant's Repair All Items button glow when equipped items fall under a durability threshold
- **map:** swap layers through LayerSwap's players from the player frame's menu


### Fixes
- **map:** merge the seamless map's west Kalimdor seams at their mountains and coasts
- **core:** show bag marks for a window opened after its event, like the mailbox's glow
- **map:** show the open sea north of Stormwind on the seamless map

## 1.4.0 - 2026-11-18


### Features
- **inventory:** mark items for mail to a character
- **core:** indent nested settings one step per level
- **inventory:** highlight items marked for mail while trading with their recipient
- **professions:** list poisons and gathering crafts in reagent tooltips
- **professions:** show more reagent recipes when the tooltip has room
- **interface:** grey out Save in the macro window when there's nothing to save
- **map:** show zoomed-in maps whole and blank land as plain paper
- **inventory:** reserve a bag or bank slot for an item
- **inventory:** mark the Waylaid Crate components the bags or bank hold enough of
- **inventory:** clean up the bank after deposits and withdrawals


### Fixes
- reword settings text to be clearer and closer to the game's own
- **map:** draw whole the zone the seamless map is on, well zoomed in
- **map:** draw the seamless map's border landmarks whole

## 1.3.0 - 2026-11-17


### Features
- **inventory:** add a search box to merchants
- **inventory:** let items be marked for both the auction house and the bank
- **interface:** add a search box to the macro icon picker
- **interface:** add a Duplicate button to the macro window
- **interface:** gather macro window options and group its buttons
- **interface:** hide macro names on action bars


### Fixes
- **professions:** stop the skinning chance from erroring on corpses whose unit is secret
- **combat:** spell action bars "barres d’actions" like the game in French


### Performance
- **quests:** stop rescanning bags for leftover quest items on quest progress
- **quests:** announce objectives from the quests that progressed
- **interface:** skip object glow refreshes on quest log updates without an object
- **quests:** leave the objective tracker alone when tracked quests are unchanged
- **core:** redraw bag and bank item marks only when they can change
- **combat:** stop rebuilding the action button list on every power tick

## 1.2.0 - 2026-11-15


### Features
- **inventory:** show the auction price right under the sell price and hide its age by default
- **professions:** show the chance of gaining skill in herb and ore node tooltips
- **inventory:** mark the lowest value items in the bags, optionally only when they are full
- **inventory:** leave the reagent bag out of the lowest value items by default
- **professions:** show the skill-up chance after the tooltip line instead of on its own line
- **core:** reorganize the settings into fewer, simpler options
- **combat:** show the replacement's cooldown on swapped buttons and refuse spells off the global cooldown
- **combat:** warn about spells off the global cooldown in swaps instead of refusing them
- **professions:** show the chance of gaining skill on skinnable corpses


### Fixes
- **quests:** leave group chat the client keeps secret instead of erroring on it
- **map:** open the world map in combat without a blocked action from friends' pins
- show the glow's glints and put CVars back after a reload
- **professions:** stop node tooltips from erroring when the game hides the node's name
- **core:** keep addon errors from breaking Blizzard's UI and other features
- **inventory:** stop the auction price tooltip from erroring on buyback items
- **inventory:** stop the auction price tooltip from erroring on buyback items again
- **core:** keep the quest log from rebuilding during our quest tracking changes
- **combat:** show the original's own cooldown over a replacement only when it has one
- **core:** make /fedebug clear work in the debugging addon
- **inventory:** show the auction price of the whole stack, like the sell price
- **inventory:** describe what bank, lowest value and merchant options do for the player
- **quests:** describe what leftover quest items shows for the player

## 1.1.0 - 2026-11-14


### Features
- **professions:** show the chance of gaining skill in a recipe's skill-up arrow tooltip
- **combat:** show on health bars the damage your damage over time effects will still deal
- **quests:** hide other players' Polestar announcements along with Questie's
- **inventory:** refill bag stacks and deposit marked items when opening the bank
- **inventory:** show the lowest auction house price in item tooltips


### Fixes
- **map:** share the map pin with Shift Click without a blocked action on the seamless map
- **quests:** hide the chat bubbles of other players' quest addon announcements
- **core:** keep the objective tracker from erroring on auras in combat after quest tracking or map pin changes

## 1.0.2 - 2026-11-12


### Features
- **inventory:** make items marked for bank glow while the bank is open
- **inventory:** disable bank transfers with nothing to move and list all matching items first on Deposit
- **quests:** show which quest items you no longer need
- **inventory:** move item notes to item marks and add a Wowhead link
- **interface:** move the world map by its title bar while it isn't maximized

## 1.0.1 - 2026-11-12


### Features
- **map:** show every quest on continents in the seamless world map


### Fixes
- **quests:** track dungeon quests on entering their dungeon


### Performance
- **map:** follow the seamless world map's view sooner after zooming or dragging

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

