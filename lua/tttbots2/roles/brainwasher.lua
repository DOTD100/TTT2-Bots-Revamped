if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_BRAINWASHER then return false end

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or 'jesters'] = true,
}

-- A traitor subrole whose whole gimmick is the Slave Deagle: a one shot weapon (ClipSize 1, 0 damage)
-- that turns whoever it hits into a Slave of the shooter and then deletes itself. Missing costs a
-- long refill cooldown, so the shot is the only thing that matters about this role.
--
-- The entry below exists purely to make the bot hold that weapon: `PrimaryWeapon` adds the class to
-- Buyables.PrimaryWeapons, which is what GetSpecialPrimary reads, because the SWEP's Kind is
-- WEAPON_EXTRA and the inventory only maps melee/secondary/primary/grenade/carry/unarmed/special/
-- extra/class to slots - nothing ever equips the "extra" slot. An empty Roles list keeps it out of
-- every shop, so no bot ever spends a credit on a weapon the role is handed for free.
--
-- Preferring it is also correct for this weapon specifically: the deagle only wins while it still has
-- its single round, and once it is fired it is either deleted (hit) or empty until it refills, at
-- which point the bot drops straight back to its real guns.
TTTBots.Buyables.RegisterBuyable({
    Name = "Slave Deagle",
    Class = "weapon_ttt2_slavedeagle",
    Price = 1,
    Priority = 1,
    PrimaryWeapon = true,
    Roles = {},
})

local brainwasher = TTTBots.RoleData.New("brainwasher", TEAM_TRAITOR)
brainwasher:SetDefusesC4(false)
brainwasher:SetPlantsC4(true)
brainwasher:SetCanHaveRadar(true)
brainwasher:SetCanCoordinate(true)
brainwasher:SetStartsFights(true)
brainwasher:SetUsesSuspicion(false)
brainwasher:SetCanSnipe(true)
brainwasher:SetTeam(TEAM_TRAITOR)
-- The deagle is this role's own loadout weapon: handed over by the role, sold by no shop, and spawned on no
-- map. Seeing one is therefore proof of the role, and the morality scan treats it as a KOS tell.
brainwasher:SetRoleWeapons({ "weapon_ttt2_slavedeagle" })
brainwasher:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
brainwasher:SetAlliedTeams(allyTeams)
-- The role registers its own team through roles.InitCustomTeam, so ally by team membership as well as
-- by name: this keeps it allied to the traitors whatever that custom team ends up looking like.
brainwasher:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(brainwasher)

return true
