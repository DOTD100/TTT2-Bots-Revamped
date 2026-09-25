if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_BEGGAR then return false end

TEAM_BEGGAR = TEAM_BEGGAR or "beggars"

--[[
The Beggar is a neutral with no team of its own and no way to win by itself (the role sets preventWin and
disables its shop). It is harmless and it is meant to be: its own hooks zero every point of damage it
deals to a player, while leaving what it takes alone, so the only way it gets anywhere is by picking up a
shop weapon somebody else dropped - the gamemode then puts it onto that person's team and swaps the two
roles around.

Two things follow for a bot in this role, and both are in the role data rather than a behavior:

  * SetDealsNoDamage stops it from ever taking a target. The Attack behavior reads that flag and refuses
    to fight, because a bot that walks into the open to shoot somebody it cannot hurt only gets itself
    killed.
  * The tree has no FightBack and no Minge node for the same reason, but it does keep Restore - which is
    where GetWeapons lives. That is the whole role: walking to a dropped gun and picking it up is what
    defects it, so the looting behavior is the point rather than an afterthought.

The Beggar takes damage like anyone else, so it is not marked damage-immune: everyone is still allowed to
kill it, which its own addon says by blocking only the damage it *deals*.

Its team name only ever matters for team comparisons - two beggars are allies, and no one else is.
]]

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    -- In the post-round deathmatch a Beggar has nothing to gain from the brawl and hides instead
    -- (behaviors/evade.lua). It keeps `Restore` because looting a dropped shop weapon is the whole role.
    _prior.Survive,
    _prior.Restore,
    _bh.Interact,
    _prior.Investigate,
    _prior.Patrol
}

local beggar = TTTBots.RoleData.New("beggar", TEAM_BEGGAR)
beggar:SetDefusesC4(false)
beggar:SetPlantsC4(false)
beggar:SetCanCoordinate(false)
beggar:SetStartsFights(false)
beggar:SetUsesSuspicion(false)
beggar:SetCanHide(true)
beggar:SetCanSnipe(false)
beggar:SetTeam(TEAM_BEGGAR)
beggar:SetDealsNoDamage(true)
beggar:SetBTree(bTree)
beggar:SetAlliedTeams({ [TEAM_BEGGAR] = true })
TTTBots.Roles.RegisterRole(beggar)

return true
