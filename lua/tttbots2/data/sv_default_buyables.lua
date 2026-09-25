--- The base game purchases: the utility items TTT and TTT2 ship with.
---
--- Add new purchases to data/sv_buyables_expanded.lua instead of here, so this file stays a mirror of
--- what the game itself sells, and updates to the base shop are easy to diff.

local Registry = {}

local function testPlyHasTrait(ply, trait, N)
    local personality = ply:BotPersonality()
    if not personality then return false end
    return (personality:GetTraitBool(trait)) or math.random(1, N) == 1
end

---@type Buyable
Registry.C4 = {
    Name = "C4",
    Class = "weapon_ttt_c4",
    Price = 1,
    Priority = 1,
    RandomChance = 1, -- 1 since chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        -- The role data decides whether a bot can use C4 at all, so a subrole that cannot plant (the
        -- Defector, for one) never wastes a credit on it.
        if not TTTBots.Roles.GetRoleFor(ply):GetPlantsC4() then return false end

        return testPlyHasTrait(ply, "planter", 6)
    end,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
}

---@type Buyable
Registry.HealthStation = {
    Name = "Health Station",
    Class = "weapon_ttt_health_station",
    Price = 1,
    Priority = 1,
    RandomChance = 1, -- 1 since chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    -- The healer trait (data/sh_traits.lua) is the only thing that sets this, so before it existed this
    -- gate was a flat 1-in-3 roll for every bot regardless of personality.
    CanBuy = function(ply)
        return testPlyHasTrait(ply, "healer", 3)
    end,
    Roles = { "detective", "survivalist" },
    Teams = { TEAM_DETECTIVE or "detectives" },
}

---@type Buyable
Registry.Defuser = {
    Name           = "Defuser",
    Class          = "weapon_ttt_defuser",
    Price          = 1,
    -- Above every other detective purchase, including the weapons added on top of it, because a policing
    -- role with one credit has to come out of the shop holding the kit.
    Priority       = 4,
    RandomChance   = 1, -- 1 since chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam   = false,
    -- Policing roles should ALWAYS carry a defuse kit. It used to be `testPlyHasTrait(ply, "defuser", 3)`
    -- (only a 1-in-3 chance, and it often lost the last credit to another priority-1 buyable), which
    -- meant bombs frequently went un-defused.
    CanBuy         = function(ply)
        return true
    end,
    Roles          = { "detective", "deputy", "sheriff" },
    Teams          = { TEAM_DETECTIVE or "detectives" },
}

---@type Buyable
Registry.Stungun = {
    Name = "UMP Prototype",
    Class = "weapon_ttt_stungun",
    Price = 1,
    Priority = 1,
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    Roles = { "detective", "survivalist" },
    PrimaryWeapon = true,
}

--- The three TTT2 grenades. They are side purchases, so their Priority sits below every weapon and kit: a
--- bot with one credit should arm itself first and only carry a grenade when it has a credit to spare. Each
--- is gated on a personality too, so a round does not turn into everyone lobbing incendiaries.
---
--- The team split follows the flavour of TTT2's own equipment lists: smoke is a defensive tool for the
--- innocent side, the incendiary and the discombobulator are offensive ones for the traitors. Moving a
--- grenade to the other team is a one-line change to the Teams list.

---@type Buyable
Registry.SmokeGrenade = {
    Name = "Smoke Grenade",
    Class = "weapon_ttt_smokegrenade",
    Price = 1,
    Priority = 0,
    RandomChance = 1, -- 1 since chance is calculated in CanBuy
    ShouldAnnounce = false,
    AnnounceTeam = false,
    -- Smoke is for a bot that would rather break a fight up than win it.
    CanBuy = function(ply)
        return testPlyHasTrait(ply, "cautious", 6)
    end,
    Teams = { TEAM_INNOCENT },
}

---@type Buyable
Registry.IncendiaryGrenade = {
    Name = "Incendiary Grenade",
    Class = "weapon_zm_molotov",
    Price = 1,
    Priority = 0,
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        return testPlyHasTrait(ply, "bomber", 6)
    end,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
}

---@type Buyable
Registry.ConfGrenade = {
    Name = "Discombobulator",
    Class = "weapon_ttt_confgrenade",
    Price = 1,
    Priority = 0,
    RandomChance = 1,
    ShouldAnnounce = false,
    AnnounceTeam = false,
    CanBuy = function(ply)
        return testPlyHasTrait(ply, "aggressive", 6)
    end,
    Roles = { "traitor" },
    Teams = { TEAM_TRAITOR },
}

for key, data in pairs(Registry) do
    TTTBots.Buyables.RegisterBuyable(data)
end
