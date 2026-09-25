if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_EXECUTIONER then return false end

TEAM_JESTER = TEAM_JESTER or 'jesters'

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

-- A traitor with a contract and a penalty clause. It deals double damage to the victim the gamemode
-- assigns it (ttt2_executioner_target_multiplier) and half damage to everyone else
-- (ttt2_executioner_non_target_multiplier), and killing anyone who is not its victim - and not on the
-- role's exclusion list - breaks the contract: it loses its target for
-- ttt2_executioner_punishment_time seconds. Staying on the contract is therefore the whole job, and
-- behaviors/hunttarget.lua is what keeps the bot pointed at it.
local executioner = TTTBots.RoleData.New("executioner", TEAM_TRAITOR)
executioner:SetDefusesC4(false)
executioner:SetPlantsC4(false)
executioner:SetCanHaveRadar(true)
executioner:SetCanCoordinate(false)
executioner:SetStartsFights(false)
executioner:SetTeam(TEAM_TRAITOR)
executioner:SetUsesSuspicion(false)
executioner:SetKnowsLifeStates(true) -- the role is flagged isOmniscientRole
executioner:SetHuntsTarget(true)
executioner:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
executioner:SetAlliedTeams(allyTeams)
executioner:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(executioner)

return true
