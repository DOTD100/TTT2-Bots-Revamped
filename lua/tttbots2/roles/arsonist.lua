if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_ARSONIST then return false end

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or 'jesters'] = true,
}

-- A traitor subrole with a flamethrower and fire immunity. The thrower is handed out by the role's
-- own loadout, so this entry exists purely to make the bot prefer holding it: `PrimaryWeapon` adds the
-- class to Buyables.PrimaryWeapons, which is what GetSpecialPrimary reads. Without it the bot would
-- never equip the weapon, because its Kind is WEAPON_EQUIP and the inventory only maps
-- melee/secondary/primary/grenade/carry/unarmed/special/extra/class to a slot. The empty Roles list
-- means no role is ever offered it for purchase, so bots never spend a credit on a free weapon.
--
-- `ShortRange` is what keeps that preference honest. The thrower is a gun as far as the inventory is
-- concerned (it has a clip), so without it the bot would hold it permanently and shoot it from rifle
-- range, where the flame does not reach. It makes the inventory put the thrower away for a real gun
-- until a target is close, and makes the attack behavior walk into torching distance while holding it.
TTTBots.Buyables.RegisterBuyable({
    Name = "Arson Thrower",
    Class = "weapon_ttt2_arsonthrower",
    Price = 1,
    Priority = 1,
    PrimaryWeapon = true,
    ShortRange = true,
    Roles = {},
})

local arsonist = TTTBots.RoleData.New("arsonist", TEAM_TRAITOR)
arsonist:SetDefusesC4(false)
arsonist:SetPlantsC4(true)
arsonist:SetCanHaveRadar(true)
arsonist:SetCanCoordinate(true)
arsonist:SetStartsFights(true)
arsonist:SetUsesSuspicion(false)
arsonist:SetCanSnipe(true)
arsonist:SetTeam(TEAM_TRAITOR)
-- The thrower is this role's own loadout weapon: handed over by the role, sold by no shop, and spawned on
-- no map. Seeing one is therefore proof of the role, and the morality scan treats it as a KOS tell.
arsonist:SetRoleWeapons({ "weapon_ttt2_arsonthrower" })
arsonist:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
arsonist:SetAlliedTeams(allyTeams)
arsonist:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(arsonist)

return true
