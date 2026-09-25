if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_COLLUSIONIST then return false end

TEAM_JESTER = TEAM_JESTER or "jesters"

--[[
The Collusionist is the jester team's cousin: a neutral that cannot win on its own (the role sets
preventWin and disables its shop), cannot hurt or be hurt by players through its own weapons, and gets
somewhere by looting a dropped shop weapon - which puts it on the owner's team and hands the owner its
role, so the two of them trade places.

It is not a fighter, and the role data says so twice:

  * SetDealsNoDamage makes the Attack behavior refuse to take a target at all. The role's own hooks zero
    every point of damage it deals to a player - verified in its source, not assumed - so any fight it
    picks is one it cannot win, and the flag keeps the bot from walking into the open for nothing.
  * There is no FightBack and no Minge node in the tree for the same reason. Restore is kept, because
    GetWeapons is what walks the bot to a dropped weapon, and that pickup is the entire role.

It sits on the jester team rather than a private one, which is how the role registers itself, and that is
also what our fool-role checks read: every bot already knows the jester team is not to be shot at for
looking suspicious, and the role syncs itself to the traitors as a jester (or as nobody, depending on its
two appearance convars) on top of that.

Being damage-immune is deliberately *not* set here. The role blocks what it deals, not what it takes, so
the bots must still be free to shoot it, exactly as the players are.
]]

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    -- The Collusionist cannot damage anybody either, so in the post-round deathmatch it hides rather than
    -- wandering into the brawl (behaviors/evade.lua).
    _prior.Survive,
    _prior.Restore,
    _bh.Interact,
    _prior.Investigate,
    _prior.Patrol
}

local collusionist = TTTBots.RoleData.New("collusionist", TEAM_JESTER)
collusionist:SetDefusesC4(false)
collusionist:SetPlantsC4(false)
collusionist:SetCanCoordinate(false)
collusionist:SetStartsFights(false)
collusionist:SetUsesSuspicion(false)
collusionist:SetCanHide(true)
collusionist:SetCanSnipe(false)
collusionist:SetTeam(TEAM_JESTER)
collusionist:SetDealsNoDamage(true)
collusionist:SetBTree(bTree)
collusionist:SetAlliedTeams({ [TEAM_JESTER] = true })
TTTBots.Roles.RegisterRole(collusionist)

return true
