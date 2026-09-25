if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_BANDIT then return false end

TEAM_BANDIT = TEAM_BANDIT or "bandits"

--[[
The Bandit is one of the "neutral bad" roles, and the role file extracted from its workshop .gma (id
2749325128) settles the two things its description leaves open:

  * It is a team of its own. The file calls roles.InitCustomTeam("Bandit", ...) and sets defaultTeam to
    TEAM_BANDIT, not to the traitor team. With maximum = 2 two of them can spawn, and they are on the same
    side, so the bot allies with its own team and with nobody else - not with the traitors, who are not its
    friends and do not treat it as theirs either. That empty alliance in both directions is the whole
    "neutral" part: this bot fights everyone it meets and every other bot fights it.
  * It is a killer. It declares isPolicingRole, which is mirrored as AppearsPolice (see the Psychopath for
    what that means to our suspicion system), and it has no pacifist machinery of its own.

So: start fights, do not wait for suspicion to build, do not try to coordinate (there is nobody to
coordinate with unless a second Bandit spawned), and stalk rather than patrol. Its detective-menu shopping
is its own shopFallback, which our buyables follow automatically.

TTT2 keys the per-role convars off the role's abbr, which is "bandit" here.
]]

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _prior.FightBack,
    _prior.Restore,
    _bh.Stalk,
    _prior.Minge,
    _prior.Patrol
}

local bandit = TTTBots.RoleData.New("bandit", TEAM_BANDIT)
bandit:SetDefusesC4(false)
bandit:SetPlantsC4(false)
bandit:SetCanCoordinate(false)
bandit:SetStartsFights(true)
bandit:SetUsesSuspicion(false)
bandit:SetCanHaveRadar(true)
bandit:SetCanHide(true)
bandit:SetCanSnipe(true)
bandit:SetTeam(TEAM_BANDIT)
bandit:SetAppearsPolice(true)
bandit:SetBTree(bTree)
bandit:SetAlliedTeams({ [TEAM_BANDIT] = true })
TTTBots.Roles.RegisterRole(bandit)

return true
