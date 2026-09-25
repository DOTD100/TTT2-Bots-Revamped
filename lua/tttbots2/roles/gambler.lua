if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_GAMBLER then return false end

--[[
The Gambler is a traitor with no shop budget: at the start of the round the role hands it a few random
traitor-shop items (ttt2_gambler_randomItems, 4 by default) and it is expected to make do with them. Its
extracted role file (workshop id 2809974123) confirms the details that matter to a bot:

  * defaultTeam = TEAM_TRAITOR with roles.SetBaseRole(self, ROLE_TRAITOR), so it is an ordinary traitor in
    every way that matters here - it knows the other traitors, it plants, it coordinates, it hunts.
  * credits = 0, which TTT2 turns into ttt_gambler_credits_starting - the very convar our buyables read
    (Buyables.GetCreditAllowanceFor). So the bot simply has nothing to spend, exactly like a player.
  * It never earns any either: the role returns false from TTT2CheckCreditAward and sets
    preventFindCredits, so no kill or corpse credit ever reaches it. The four items are the whole round,
    and nothing in this file has to enforce that - the allowance stays zero all round.

It also calls roles.InitCustomTeam with its own name, but defaultTeam is the traitor team, so that team is
registered and unused. The bot follows the role and stays a traitor.

The weapons and items it was handed are in its hands already, and it uses them like any other traitor.
]]

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
}

local gambler = TTTBots.RoleData.New("gambler", TEAM_TRAITOR)
gambler:SetDefusesC4(false)
gambler:SetPlantsC4(true)
gambler:SetCanHaveRadar(true)
gambler:SetCanCoordinate(true)
gambler:SetStartsFights(true)
gambler:SetUsesSuspicion(false)
gambler:SetCanSnipe(true)
gambler:SetTeam(TEAM_TRAITOR)
gambler:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
gambler:SetAlliedTeams(allyTeams)
gambler:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(gambler)

return true
