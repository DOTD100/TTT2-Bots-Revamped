if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_ROIDER then return false end

--[[
The Roider is a traitor that fights with the crowbar and nothing else. Its own hooks are what make that
true, and they are worth spelling out because they decide everything below:

  * PlayerTakeDamage zeroes every point of damage the Roider deals, unless the hit came from
    weapon_zm_improvised - the crowbar - which it instead sets to the ttt2_roid_cbdmg convar. So a gun in
    this role's hands is a prop: the bot would stand at rifle range firing at someone it cannot hurt.
    That covers thrown C4 and grenades too, since those damage events name the Roider as the attacker, so
    the role does not plant or take a defuse kit either.
  * TTT2PlayerPreventPush turns its crowbar into a shove, which the gamemode handles on its own.

That leaves the bot needing to fight with the crowbar, which is what SetAutoSwitch(false) plus
SetPreferredWeapon does: RoleData has declared both for a while and the inventory now honors them, so the
bot keeps the crowbar in hand instead of swapping to the pistol it also carries. The attack behavior treats
a held melee weapon as one - it closes to crowbar range and swings - and it now *runs* while it closes
(Attack.ShouldRunToCatch), which is the part that matters most here: at walking pace the bot matched the
speed of anybody walking away from it, so the crowbar could never catch a pistol. That run is the same
reason the Shanker's stalk sprints, applied generally instead of inside one role's behaviour.

The bot still shops like a traitor and will spend a credit on a gun it can never hurt anyone with. That is
wasteful rather than wrong, and the alternative - special-casing this role in the buyables - would be a
rule about a single addon living in the shop code.
]]

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
}

local roider = TTTBots.RoleData.New("roider", TEAM_TRAITOR)
roider:SetDefusesC4(false)
roider:SetPlantsC4(false)
roider:SetCanHaveRadar(true)
roider:SetCanCoordinate(true)
roider:SetStartsFights(true)
roider:SetUsesSuspicion(false)
roider:SetCanSnipe(false)
roider:SetTeam(TEAM_TRAITOR)
roider:SetAutoSwitch(false)
roider:SetPreferredWeapon("weapon_zm_improvised")
roider:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
roider:SetAlliedTeams(allyTeams)
roider:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(roider)

return true
