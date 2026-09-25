if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_SHANKER then return false end

--[[
A traitor subrole (roles.SetBaseRole(ROLE_TRAITOR)) whose loadout is the Shanking Knife: a silent,
print-free melee weapon that reaches 80 units and deals 999 damage when it lands on a victim's back,
40 when it does not. Its Kind is WEAPON_EQUIP, which the inventory maps to the "extra" slot and never
auto-equips, so the ShankerStalk behavior has to select the knife itself (and hold the inventory's
auto-switch off while it does).

Two consequences shape this file:

  * The knife is the role, so StartsFights is off. A traitor that picks random gunfights never gets to
    use it; leaving the pistol for FightBack makes the bot stalk by default and shoot only when it is
    actually being attacked.
  * It is otherwise an ordinary traitor: it still buys, coordinates, plants and defends its teammates,
    so the tree is the normal traitor one with the stalk behavior slotted in after FightBack.
]]

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or 'jesters'] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _prior.FightBack,
    _bh.ShankerStalk,
    _bh.Defib,
    _bh.PlantBomb,
    _bh.InvestigateCorpse,
    _prior.Restore,
    _bh.FollowPlan,
    _bh.Interact,
    _prior.Minge,
    _prior.Investigate,
    _prior.Patrol
}

local shanker = TTTBots.RoleData.New("shanker", TEAM_TRAITOR)
shanker:SetDefusesC4(false)
shanker:SetPlantsC4(true)
shanker:SetCanHaveRadar(true)
shanker:SetCanCoordinate(true)
-- The knife is the offence, so do not let it pick gunfights on its own. It still fights back.
shanker:SetStartsFights(false)
shanker:SetUsesSuspicion(false)
shanker:SetCanSnipe(true)
shanker:SetTeam(TEAM_TRAITOR)
-- The knife is this role's own loadout weapon: handed over by the role, sold by no shop, and spawned on no
-- map. Seeing one is therefore proof of the role, and the morality scan treats it as a KOS tell.
shanker:SetRoleWeapons({ "weapon_ttt_shankknife" })
shanker:SetBTree(bTree)
shanker:SetAlliedTeams(allyTeams)
shanker:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(shanker)

return true
