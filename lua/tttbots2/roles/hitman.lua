if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_HITMAN then return false end

TEAM_JESTER = TEAM_JESTER or 'jesters'

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER] = true,
}

-- A traitor with a contract. The contract is published by the Hitman addon itself - not by TTT2, which does
-- not ship this role, and whose Player:SetTargetPlayer()/GetTargetPlayer() pair is documented as the target a
-- player is *spectating* (the HUD uses it to show who you are looking at, and its other writers are
-- client-side). behaviors/hunttarget.lua reads that and re-checks it every tick, treating any value it cannot
-- use as "no contract at all". Killing anybody but the contract can reveal the hitman outright, so it stays on
-- its contract rather than picking fights, and the addon reassigns a fresh victim whenever the last one dies.
--
-- Two contract types can never be fulfilled, and the provider leaves them alone rather than fighting over
-- them: a Jester or a Swapper sits on the jesters' team, which this role lists as an allied team, and a Swapper
-- is damage-immune on top of that.
local hitman = TTTBots.RoleData.New("hitman", TEAM_TRAITOR)
hitman:SetDefusesC4(false)
hitman:SetPlantsC4(false)
hitman:SetCanHaveRadar(true)
hitman:SetCanCoordinate(false)
hitman:SetStartsFights(false)
hitman:SetTeam(TEAM_TRAITOR)
hitman:SetUsesSuspicion(false)
hitman:SetKnowsLifeStates(true) -- the role is flagged isOmniscientRole
hitman:SetHuntsTarget(true)
hitman:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
hitman:SetAlliedTeams(allyTeams)
hitman:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(hitman)

return true
