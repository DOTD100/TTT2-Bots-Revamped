--- Additional buyables for the bots.
---
--- This is the file to add new purchases in. Everything here is registered after the base game items in
--- data/sv_default_buyables.lua, and none of it is required for the bots to work: drop a new entry in
--- the table below and the bots will consider it every round.
---
--- See TTTBots.Buyables.RegisterBuyable (lib/sv_buyables.lua) for the full field list, or the Buyable
--- class annotation at the top of that file. The short version:
---   Name          The pretty name. Also the key the item is registered under.
---   Class         The weapon/entity class to give the bot.
---   Price         Cost in credits. Bots are given the starting credits the gamemode hands a player of
---                 their role (ttt_traitor_credits_starting and friends in TTT2), so tuning the server's
---                 credit settings changes what bots can afford.
---   Priority      Higher numbers are bought first.
---   RandomChance  1 = always considered, N = considered one round in N.
---   CanBuy        Return false to veto the purchase for this bot this round.
---   Roles         Role strings that can buy it (e.g. "traitor", "detective", "shanker").
---   Teams         Teams that can buy it. This is how a custom role inherits its team's shop without
---                 being named in every entry.
---   TTT2          true if the item only exists on TTT2. Skips it when the class is missing.
---   PrimaryWeapon true to prefer this over the bot's other primaries.
---   ShortRange    true if it only works at knife range. Bots will close in before holding it.
---
--- Nothing beyond an entry is needed to get an item into the bots' hands. Everything registered in this file
--- is a *custom* buyable (see lib/sv_buyables.lua for the tiers), and a bot buys at most one custom item per
--- round, drawn at random from the ones it can afford - so a new weapon competes with the rest of this file
--- by simply existing. Two optional fields exist for the cases that need them: Group, to make one random
--- pick from a specific set of entries instead of the whole custom shop, and Tier = "base", to have an item
--- bought like a base game item - in priority order, as many as the credits allow - instead of joining the
--- draw.
---
--- Perks - the passive items TTT calls perks, which live under lua/terrortown/entities/items - are bought
--- like anything else, with one difference: they need a BuyFunc, because an item is handed over with
--- Player:GiveItem, which is also what runs the item's own Bought hook, while the default purchase only does
--- Player:Give for weapons. Registry.Martyrdom at the bottom of this file is a worked example.

local Registry = {}

---@return boolean
local function testPlyIsArchetype(ply, archetype, N)
    local personality = ply:BotPersonality()
    if not personality then return false end
    return (personality:GetClosestArchetype() == archetype) or math.random(1, N) == 1
end

---@type Buyable
--- `weapon_ttt_defibrillator` is the TTT2 defibrillator (TTT-2/ttt2-wep_defi). That addon ships a
--- reworked weapon under the class TTT already uses, so one entry covers both, and the defib behavior
--- in behaviors/defib.lua knows the class (see its WeaponClasses list).
---
--- The behavior drives the weapon itself instead of reviving directly: it walks up to the corpse,
--- crouches over it and holds +attack, letting the weapon run its own charge and roll its own success
--- chance, so the bot's revive odds are the same as a player's.
---
--- The audience matches the weapon's own SWEP.CanBuy = { ROLE_TRAITOR, ROLE_DETECTIVE }: a survivalist
--- used to be offered it here, which no survivalist could buy from a real shop.
Registry.Defib = {
    Name = "Defibrillator",
    Class = "weapon_ttt_defibrillator",
    Price = 1,
    Priority = 2, -- higher priority because this is an objectively useful item
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        return testPlyIsArchetype(ply, TTTBots.Archetypes.Teamer, 3)
    end,
    Roles = { "detective", "traitor" },
    Teams = { TEAM_TRAITOR, TEAM_DETECTIVE or "detectives" },
}

---@type Buyable
--- `weapon_ttt_ak47` is Zaratusa's AK-47 (github.com/Zaratusa/ttt-ak47): a TTT weapon rather than a TTT2
--- one, hence its own SWEP.CanBuy = { ROLE_TRAITOR }, and hence its Kind of WEAPON_EQUIP1 - the old name
--- for WEAPON_SPECIAL, so it rides in the equipment slot instead of the primary one.
---
--- `PrimaryWeapon` is what makes the bots actually use it. It registers the class in
--- Buyables.PrimaryWeapons, which is the list GetSpecialPrimary reads to decide what belongs in the bot's
--- hands. Without it the AK would sit in the equipment slot, bought and never fired, because the
--- inventory only ever looks at the primary/secondary/special slots for something to hold.
---
--- The weapon sets SWEP.LimitedStock = true (one per round) and carries no price of its own, so one
--- credit is what a player pays for it in a TTT2 shop.
---
--- It is a 30 round automatic rifle at 21 damage and a 0.1s delay, so it is worth buying before anything
--- else a traitor can afford: hence a priority above the utility items.
---
--- Being a custom buyable is what stops every traitor walking out with this rifle. A bot buys one custom
--- item per round, drawn at random from the ones it can afford, so this competes with the rest of the pack
--- rather than winning on priority: the pack's entries do not need to know about each other.
Registry.AK47 = {
    Name = "AK-47",
    Class = "weapon_ttt_ak47",
    Price = 1,
    Priority = 4,
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    PrimaryWeapon = true,
}

--- Everything below is the rest of Zaratusa's weapon pack: same author, same shape as the AK (a TTT
--- weapon, WEAPON_EQUIP1, LimitedStock, no price of its own), so the same one credit and the same
--- PrimaryWeapon flag apply. All of them are WEAPON_EQUIP1, which TTT2 remaps to WEAPON_SPECIAL, so they
--- share the equipment slot with each other and with the defibrillator: a bot can own several and still
--- only hold one, and the inventory picks the best loaded one (see GetSpecialPrimary).
---
--- All of these are custom buyables, so they are one draw: a bot takes one of them - at random - and spends
--- its other credit on something else instead of arming itself twice. The priorities below are only a
--- readable order for this list; they do not decide which of these a bot ends up with.

---@type Buyable
--- The Silenced M4A1 (github.com/Zaratusa/ttt-m4a1, class weapon_ttt_silm4a1). SWEP.IsSilent = true, so
--- its kills do not scream - which the bots do understand, since IsSilent is what the memory component
--- reads when a sound gives a shooter away.
Registry.SilencedM4A1 = {
    Name = "Silenced M4A1",
    Class = "weapon_ttt_silm4a1",
    Price = 1,
    Priority = 4, -- the AK's equal: a 30 round automatic rifle is what a traitor wants in hand first
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    PrimaryWeapon = true,
}

---@type Buyable
--- The AWP (github.com/Zaratusa/ttt-awp). 125 damage and a x6 headshot multiplier, but only a two round
--- clip and SWEP.Primary.Ammo = "none", so its own Reload can never find ammo: two shots for the round.
--- Bots handle that the same way they handle the Gauss - when it is empty the inventory treats it as a
--- spent weapon and falls back to whatever else it is carrying.
Registry.AWP = {
    Name = "AWP",
    Class = "weapon_ttt_awp",
    Price = 1,
    Priority = 3, -- two shots for the round, so it is the specialist's draw rather than the default one
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    PrimaryWeapon = true,
}

---@type Buyable
--- The Gauss Rifle (github.com/Zaratusa/ttt-gauss-rifle). One round per clip with a two second delay, so
--- it is a single devastating shot rather than a rifle: 75 damage on the hit plus a 250 unit blast. Its
--- SWEP.Initialize hands the owner one "thumper" round in reserve, which is what lets the bot reload it
--- once; after that both clip and reserve are empty and it is skipped.
Registry.GaussRifle = {
    Name = "Gauss Rifle",
    Class = "weapon_ttt_gauss_rifle",
    Price = 1,
    Priority = 3,
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    PrimaryWeapon = true,
}

---@type Buyable
--- The P90 (github.com/Zaratusa/ttt-p90). The odd one out of the pack: SWEP.CanBuy = { ROLE_DETECTIVE },
--- so it is the detectives' purchase, not the traitors'. A 50 round automatic at a 0.06s delay, and it
--- takes normal SMG1 ammo, so unlike the AWP and the Gauss it can be topped up from ammo entities.
Registry.P90 = {
    Name = "P90",
    Class = "weapon_ttt_p90",
    Price = 1,
    Priority = 3, -- below the defuse kit, so a one credit policing role still leaves the shop with it
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "detective" },
    Teams = { TEAM_DETECTIVE or "detectives" },
    PrimaryWeapon = true,
}

---@type Buyable
--- The Dragon Elites (github.com/Zaratusa/ttt-dragon-elites, class weapon_ttt_dragon_elites): a shop
--- weapon in its own right, unlike its brother. SWEP.CanBuy = { ROLE_DETECTIVE, ROLE_TRAITOR } with
--- LimitedStock, and AutoSpawnable = false, so it is only ever bought.
---
--- 22 damage at a 0.1s delay with a x2.97 headshot multiplier, out of a 30 round clip on pistol ammo, and
--- its own Initialize hands the owner a spare magazine. That is 220 dps - as hard hitting as the AK-47 -
--- so it sits in the specialist tier rather than being treated as a backup pistol.
---
--- No PrimaryWeapon flag, because it is a WEAPON_PISTOL and the inventory finds it in the secondary slot by
--- itself. It is a custom buyable like the rest of the pack, so the single custom pick a bot makes each
--- round can land here instead of on a rifle. That is a fair draw rather than a downgrade: 220 dps is a
--- match for the AK.
Registry.DragonElites = {
    Name = "Dragon Elites",
    Class = "weapon_ttt_dragon_elites",
    Price = 1,
    Priority = 3,
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "detective", "traitor" },
    Teams = { TEAM_TRAITOR, TEAM_DETECTIVE or "detectives" },
}

---@type Buyable
--- The Martyrdom perk (workshop id 1630269736, NickCloudAT's "TTT2 Martyrdom [Updated]"): whoever dies drops
--- a live grenade that goes off ttt_martyr_time seconds later (3 by default).
---
--- It is a *perk*, which in TTT2 means a passive item rather than a weapon. Items are handed over with
--- Player:GiveItem, and that call is what runs the item's own Bought hook - the hook sets the shouldmartyr
--- flag, and the addon's own PlayerDeath hook drops the grenade. Player:Give is for weapons and would only
--- spawn an entity that does nothing, hence the BuyFunc. Nothing else has to be written for it: the item is
--- passive, so buying it is the whole of it.
---
--- The item is the addon's item_ttt_martyrdom, whose CanBuy is { ROLE_TRAITOR } - hence the roles below, with
--- traitor subroles covered through the team.
---
--- The Group keeps a perk from being drawn in place of a bot's weapon: it is its own draw, so a bot takes one
--- alongside a gun rather than trading the gun for it. RandomChance 2 keeps it to about every other round.
---
--- There is deliberately no Class field - the class check in the purchase loop is a weapon check, and an item
--- class would fail it - so the class is named in the BuyFunc.
Registry.Martyrdom = {
    Name = "Martyrdom",
    Price = 1,
    Priority = 3,
    RandomChance = 2,
    Group = "perk",
    ShouldAnnounce = false,
    AnnounceTeam = false,
    TTT2 = true,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    -- Nothing is sold when the addon is not installed, so a traitor never spends a credit on nothing.
    CanBuy = function() return items and items.IsItem("item_ttt_martyrdom") end,
    BuyFunc = function(ply)
        ply:GiveItem("item_ttt_martyrdom")
    end,
}

---@type Buyable
--- The Fake Soda (github.com/mexikoedi/ttt2_fake_soda, class weapon_ttt2_fake_soda): a traitor's decoy can.
--- It is indistinguishable from a Super Soda can and poisons whoever drinks it - health, armour, credits,
--- speed, damage dealt, fire rate or jump height, depending on which of its seven cans it happened to be.
---
--- A side purchase, on the grenades' reasoning: it costs a credit, and a credit spent on a decoy is a credit
--- not spent on something that shoots. RandomChance 2 keeps it to about every other round.
---
--- The CanBuy gate is what makes it worth buying rather than random: the decoy is only useful where cans
--- are, so a bot only pays for it while the map has a real can to sit it beside (or, later in the round, a
--- spot one has just been drunk from - see behaviors/placefakesoda.lua). It is also the check that keeps a
--- traitor from buying it on a server without the addon.
Registry.FakeSoda = {
    Name = "Fake Soda",
    Class = "weapon_ttt2_fake_soda",
    Price = 1,
    Priority = 0,
    RandomChance = 2,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    CanBuy = function(ply)
        return TTTBots.Behaviors.PlaceFakeSoda.HasDecoyGround(ply)
    end,
}

---@type Buyable
--- The Boom Body (TTT-2/ttt2-wep_boom_body, class weapon_ttt_boom_body): a traitor's fake corpse. The weapon
--- fires once and leaves a ragdoll of a *random* player wherever the addon decides to put it; whoever
--- searches that body sets it off instead (160 units, 350 damage, credited to the owner).
---
--- A side purchase on the grenades' reasoning - a credit spent on a trap is a credit not spent on something
--- that shoots - and RandomChance 2 keeps it to about every other round. The CanBuy check is the addon's own
--- presence, so nothing is bought on a server that does not run it.
Registry.BoomBody = {
    Name = "Boom Body",
    Class = "weapon_ttt_boom_body",
    Price = 1,
    Priority = 0,
    RandomChance = 2,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    CanBuy = function()
        return TTTBots.Lib.WepClassExists("weapon_ttt_boom_body")
    end,
}

---@type Buyable
--- The Thomas The Tank Engine gun (adigram/ttt_adithomas, class ttt_thomas_swep): a one-shot traitor joke
--- weapon with a real sting. It drops a train 200 units ahead of the shooter, facing where they were looking,
--- which then drives straight ahead at 350 u/s for 15 seconds in NOCLIP - through walls - killing any alive
--- player it touches for 1,000 damage and exploding for a 512 unit blast at the end of it. The shooter cannot
--- be hit by the train itself, and a Detective who touches it stops it and survives.
---
--- Deliberately **not** a PrimaryWeapon: the weapon removes itself when it fires, so a bot should never be
--- holding this instead of a gun. behaviors/thomas.lua is what picks it up and aims it.
Registry.Thomas = {
    Name = "Thomas The Tank Engine",
    Class = "ttt_thomas_swep",
    Price = 1,
    Priority = 0,
    RandomChance = 2,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
    CanBuy = function()
        return TTTBots.Lib.WepClassExists("ttt_thomas_swep")
    end,
}

---@type Buyable
--- The Minethrower (mexikoedi/ttt_ttt2_minethrower, class weapon_ttt_ttt2_minethrower): a two-shot launcher
--- for stock HL2 hopper mines. Primary throws one with a 7,000 unit force applied to its physics object;
--- secondary drops one 30 units in front of the player. The addon's own CanBuy is
--- { ROLE_DETECTIVE, ROLE_TRAITOR }, so this is one of the few purchases both sides share.
---
--- A side purchase and not a PrimaryWeapon: the weapon cannot reload (Primary.Ammo is "none"), so once its two
--- mines are gone it is a brick that a bot must not be holding instead of a gun. behaviors/minethrower.lua is
--- what picks it up, and it lives in _prior.Restore rather than the traitor tree for the same reason this
--- entry is open to both teams.
Registry.MineThrower = {
    Name = "Minethrower",
    Class = "weapon_ttt_ttt2_minethrower",
    Price = 1,
    Priority = 0,
    RandomChance = 2,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "traitor", "detective" },
    Teams = { TEAM_TRAITOR, TEAM_DETECTIVE or "detectives" },
    CanBuy = function()
        return TTTBots.Lib.WepClassExists("weapon_ttt_ttt2_minethrower")
    end,
}

for key, data in pairs(Registry) do
    TTTBots.Buyables.RegisterBuyable(data)
end
