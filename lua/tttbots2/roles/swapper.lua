if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_SWAPPER then return false end

TEAM_JESTER = TEAM_JESTER or 'jesters'

-- Cannot win (preventWin), deals no damage to players and takes none from them: its only job is to die
-- to a player, which swaps it into that player's role and hands the swapper role to the killer. It is
-- synced to everyone else as a jester, so it should not pick fights and should not hide - it roams.
--
-- Because player attacks cannot hurt it, other bots must never *fight* it: they would stand in the
-- open emptying magazines into someone who cannot be damaged, and because the role moves to whoever
-- killed the swapper, they would then do the same to the new holder of the role forever. The
-- damageImmune flag below makes every bot treat the current swapper as a non-combatant, evaluated
-- against the live role so the hand-off is handled automatically.
local allyTeams = {
    [TEAM_JESTER] = true,
    [TEAM_TRAITOR] = true,
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    -- First: the Swapper deals no damage and takes none, so it has nothing to do in the post-round deathmatch
    -- except stay out of it (behaviors/evade.lua). Inert during the round, where roaming is the whole point.
    _prior.Survive,
    _prior.FightBack,
    _prior.Restore,
    _bh.Interact,
    _prior.Minge,
    _prior.Investigate,
    _bh.Decrowd,
    _prior.Patrol
}

local swapper = TTTBots.RoleData.New("swapper", TEAM_JESTER)
swapper:SetDefusesC4(false)
swapper:SetPlantsC4(false)
swapper:SetCanCoordinate(false)
swapper:SetStartsFights(false)
swapper:SetUsesSuspicion(false)
swapper:SetCanHide(false)
swapper:SetCanSnipe(false)
swapper:SetTeam(TEAM_JESTER)
swapper:SetIsDamageImmune(true)
swapper:SetBTree(bTree)
swapper:SetAlliedTeams(allyTeams)
TTTBots.Roles.RegisterRole(swapper)

return true
