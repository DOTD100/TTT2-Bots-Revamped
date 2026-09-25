if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_LOOTGOBLIN then return false end

TEAM_LOOTGOBLIN = TEAM_LOOTGOBLIN or 'lootgoblin'

--[[
A "jester style" survivor on its own team (roles.InitCustomTeam). When it spawns it shrinks to half
scale, halves its step and view offsets, runs at 600 and takes its health from ttt2_lootgoblin_health,
which makes it small, fast and fragile. The role also scales its own damage down - at best to a quarter
via ttt2_lootgoblin_damagescale, at worst to nothing - and its kill score is 0 while surviving is worth
2x, so its entire game is staying alive. If it outlives everyone it wins alone (its winning-alives hook
sets shouldWin), otherwise it joins whichever team won.

That is why there is no FightBack node here and why Investigate is left out entirely: the same reason
Drunk should not investigate noise, a goblin that walks towards a gunshot is a dead goblin.
]]

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _bh.Decrowd, -- getting away from people comes first, surviving is the whole role
    _bh.UseHealthStation,
    _bh.Interact,
    _prior.Minge,
    _prior.Patrol
}

local goblin = TTTBots.RoleData.New("lootgoblin", TEAM_LOOTGOBLIN)
goblin:SetDefusesC4(false)
goblin:SetPlantsC4(false)
goblin:SetCanHaveRadar(false)
goblin:SetCanCoordinate(false)
goblin:SetStartsFights(false)
goblin:SetUsesSuspicion(false)
goblin:SetCanHide(true)
goblin:SetCanSnipe(false)
goblin:SetTeam(TEAM_LOOTGOBLIN)
goblin:SetBTree(bTree)
goblin:SetAlliedRoles({})
goblin:SetAlliedTeams({})
TTTBots.Roles.RegisterRole(goblin)

return true
