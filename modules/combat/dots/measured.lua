-- What the client's data doesn't say, measured in game against the combat log
-- (or, where marked unmeasured, taken from the spell's description).
-- Each value says how it was measured, or that it wasn't, so a content patch
-- can be checked the same way. data.lua (generated) holds the rest.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

DoTs.Measured = {
    -- Spell key -> how the server adds the player's attack power, in its own
    -- code (the data says nothing): `attackPower`, the share of it each tick
    -- adds (one per combo point for a finishing move), and `talentsRaiseBonus`,
    -- whether the talents raising the effect (data.lua) raise what attack power
    -- and spell power add too, or only the base damage.
    spells = {
        -- TBC's coefficient (18% over its 6 ticks), Opportunity raising it too.
        -- Build 70888: ticks of 65 with 236 and 241 attack power, Opportunity 5/5
        -- (+20%): (47 + 0.03 * 241) * 1.2 = 65.1.
        garrote = { attackPower = 0.03, talentsRaiseBonus = true },
        -- Classic's coefficients (4, 10, 18, 21 and 24% over 4 to 8 ticks), added
        -- after Serrated Blades. Build 70888, Serrated Blades 3/3: 3 points ticked
        -- 26 with 241 attack power, 87 / 6 * 1.3 + 0.03 * 241 = 26.1, and 5 points
        -- 30 with 236, 144 / 8 * 1.3 + 0.03 * 236 = 30.5. 1, 2 and 4 points
        -- unmeasured.
        rupture = { attackPower = { 0.01, 0.02, 0.03, 0.03, 0.03 }, talentsRaiseBonus = false },
        -- Unmeasured: neither the data nor the description mentions attack power
        -- (Garrote's and Rupture's descriptions do), and classic's have none.
        rend = { attackPower = 0, talentsRaiseBonus = true },
        rake = { attackPower = 0, talentsRaiseBonus = true },
        -- Unmeasured: the data's spell power coefficients, raised by talents like
        -- Garrote's attack power.
        moonfire = { attackPower = 0, talentsRaiseBonus = true },
        insect_swarm = { attackPower = 0, talentsRaiseBonus = true },
        shadow_word_pain = { attackPower = 0, talentsRaiseBonus = true },
        holy_fire = { attackPower = 0, talentsRaiseBonus = true },
        corruption = { attackPower = 0, talentsRaiseBonus = true },
        immolate = { attackPower = 0, talentsRaiseBonus = true },
        flame_shock = { attackPower = 0, talentsRaiseBonus = true },
    },
    -- Talent spell ID -> spell key -> the bonus at each rank, replacing the
    -- data's where it was measured to differ. None so far.
    talents = {},
    -- Mark key -> `stores`: spell key -> how many times the share its description
    -- gives ("60% stored" with 5 points) the mark stores of that effect's ticks
    -- (once that share of the strikes and white swings).
    marks = {
        -- Build 70959, 5 points (60% stored), the damage it stores being what the
        -- combat log shows of each hit while it lasts, dealt whole: 234 with two
        -- Garrote ticks of 96 alone (0.6 * 2 * 192 = 230), 247 with white
        -- swings alone of 407 to 414 (244 to 248), 455 with a Garrote tick of 96
        -- and strikes and swings of 560 (451; 522 without a swing that landed
        -- with the cast, 428). Rupture's twice the rate unmeasured (the
        -- description's "Garrote and Rupture damage is stored at twice the
        -- rate"), and that casting it again replaces the mark.
        death_mark = { stores = { garrote = 2, rupture = 2 } },
    },
    -- The share of the player's white swings that land, for the swings a mark
    -- stores (their damage in combat can't be told: an average is counted).
    -- Build 70959: 16 of 20 swings landed in Death Mark's windows (misses,
    -- dodges and parries) against level 35-38 beasts, by a level 40 rogue dual
    -- wielding.
    swingsLanded = 0.8,
    -- Not counted: poisons and procs. Armor: armor.lua.
}
