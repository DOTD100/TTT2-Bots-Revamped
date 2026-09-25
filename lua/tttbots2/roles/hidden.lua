if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_HIDDEN then return false end

TEAM_HIDDEN = TEAM_HIDDEN or 'hidden'

--[[
A lone wolf on its own team (roles.InitCustomTeam), with no base role and nobody to ally with: everyone
is fair game. Its gimmick is stalker mode, entered by a KeyPress listener on IN_RELOAD: that boosts its
health by 8 per living player, cloaks it, speeds it up by 1.6x, strips every normal weapon and hands it
a throwing knife, a special nade and a climbing pick.

Two consequences shape this file:

  * Outside stalker mode it only deals 20% damage, so guns are close to worthless. There is deliberately
    no FightBack node - the knife behaviour below is the only offence it should be using.
  * While in stalker mode the addon strips its weapons and blocks every pickup except its own knife and
    nade, so GetWeapons would send it walking to guns it can never take. UseHealthStation is kept, but
    the Restore priority node (which contains GetWeapons) is not.
]]

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _bh.HiddenStalk,
    _bh.UseHealthStation,
    _prior.Minge,
    _prior.Investigate,
    _prior.Patrol
}

local hidden = TTTBots.RoleData.New("hidden", TEAM_HIDDEN)
hidden:SetDefusesC4(false)
hidden:SetPlantsC4(false)
hidden:SetCanHaveRadar(false)
hidden:SetCanCoordinate(false)
-- It has no gun worth firing and a knife for everything else, so do not let it pick fights on its own.
hidden:SetStartsFights(false)
hidden:SetUsesSuspicion(false)
hidden:SetCanHide(false)
hidden:SetCanSnipe(false)
hidden:SetTeam(TEAM_HIDDEN)
-- The stalker knife is this role's own weapon: handed over when it enters stalker mode, sold by no shop,
-- and spawned on no map. Seeing one is therefore proof of the role, and the morality scan treats it as a
-- KOS tell.
hidden:SetRoleWeapons({ "weapon_ttt_hd_knife" })
hidden:SetBTree(bTree)
hidden:SetAlliedRoles({})
hidden:SetAlliedTeams({})
TTTBots.Roles.RegisterRole(hidden)

return true
