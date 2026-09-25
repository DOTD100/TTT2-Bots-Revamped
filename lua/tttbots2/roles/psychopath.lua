if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_PSYCHOPATH then return false end

--[[
The Psychopath is a traitor that hides behind a detective's shop: it sits on the traitor team, but it sets
shopFallback = SHOP_FALLBACK_DETECTIVE so it buys police gear and passes for a Survivalist, and it declares
isPolicingRole, the flag TTT2 uses for a role it treats as police.

The addon does not publish its source, but it ships readable Lua, so this entry is written against the role
file extracted from the workshop .gma (id 2755155854) rather than against its description. Everything here
follows from what that file actually does:

  * defaultTeam = TEAM_TRAITOR with no base role override, so it is an ordinary traitor - it knows the other
    traitors, it plants, it coordinates, and it hunts the innocents.
  * isPolicingRole = true is mirrored as AppearsPolice, which is what makes the disguise work in our own
    morality system: a bot holds 30% of the suspicion it would otherwise hold against a policing-looking
    player, and Match.CallKOS refuses to call KOS on one at all. That is the deception, not an oversight.
  * shopFallback stays the role's business. Our buyables follow whichever TTT2 shop fallback a role names
    (Buyables.GetBorrowedShopRole), so this bot shops the detective list alongside the traitor list without
    anything in this file having to know the detective menu exists.

TTT2 keys the per-role convars off the role's abbr, which is "psychopath" here - the same string the credit
and shop lookups read.
]]

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
}

local psychopath = TTTBots.RoleData.New("psychopath", TEAM_TRAITOR)
psychopath:SetDefusesC4(false)
psychopath:SetPlantsC4(true)
psychopath:SetCanHaveRadar(true)
psychopath:SetCanCoordinate(true)
psychopath:SetStartsFights(true)
psychopath:SetUsesSuspicion(false)
psychopath:SetCanSnipe(true)
psychopath:SetTeam(TEAM_TRAITOR)
psychopath:SetAppearsPolice(true)
psychopath:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
psychopath:SetAlliedTeams(allyTeams)
psychopath:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(psychopath)

return true
