if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_MESMERIST then return false end

--[[
The Mesmerist is a traitor that spawns with its own defibrillator (weapon_ttt_mesdefi) and rebuilds
whoever it is used on as a Thrall - a traitor - on its own team. It is an otherwise ordinary traitor, and
the ordinary traitor tree already runs the Defib behavior, so the only thing this role has to change is
who that behavior is willing to revive.

That is SetRevivesAnyCorpse. The behavior's default is "teammates only", which is a filter about not
spending a charge on the wrong person; for the Mesmerist every body is the right person, because whatever
comes back gets up on its team. It also matters mechanically: roles that declare no allies (which the
innocent side of the roster does on purpose, since innocents do not know who is who) would otherwise never
satisfy the ally filter at all and would carry the defib around all round without using it.

The defib is deliberately not declared as a role weapon. It is a medical tool rather than a weapon, and
the morality scan treats a held role weapon as proof of the role and a reason to shoot - nobody should be
killed for standing over a body holding a defibrillator.

The role's own radar, which shows it every corpse on the map, is left alone: the Defib behavior reads the
corpse list the match already keeps, so it finds bodies without it.
]]

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
}

local mesmerist = TTTBots.RoleData.New("mesmerist", TEAM_TRAITOR)
mesmerist:SetDefusesC4(false)
mesmerist:SetPlantsC4(true)
mesmerist:SetCanHaveRadar(true)
mesmerist:SetCanCoordinate(true)
mesmerist:SetStartsFights(true)
mesmerist:SetUsesSuspicion(false)
mesmerist:SetCanSnipe(true)
mesmerist:SetTeam(TEAM_TRAITOR)
mesmerist:SetRevivesAnyCorpse(true)
mesmerist:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
mesmerist:SetAlliedTeams(allyTeams)
mesmerist:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(mesmerist)

return true
