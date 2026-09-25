if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_THRALL then return false end

--[[
The Thrall is not handed out at round start (the role marks itself notSelectable): it is what a corpse
becomes when the Mesmerist revives it. It takes the Mesmerist's team, or the traitor team when the
server's ttt2_thr_team_inherit convar is off.

Bot-side it is simply a traitor, which is what this describes: it knows the traitors, it plants, it
coordinates, and it hunts the innocents. A bot that is converted mid-round picks this up immediately, as
the role data is looked up by role name every time it is read rather than cached at spawn.

Its credits are named by the role's own TTT2 convar, so a converted bot that already spent its allowance
for this round does not get a second one from us - whatever the gamemode handed the role is what the
Buyables allowance reads.
]]

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
}

local thrall = TTTBots.RoleData.New("thrall", TEAM_TRAITOR)
thrall:SetDefusesC4(false)
thrall:SetPlantsC4(true)
thrall:SetCanHaveRadar(true)
thrall:SetCanCoordinate(true)
thrall:SetStartsFights(true)
thrall:SetUsesSuspicion(false)
thrall:SetCanSnipe(true)
thrall:SetTeam(TEAM_TRAITOR)
thrall:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
thrall:SetAlliedTeams(allyTeams)
thrall:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(thrall)

return true
