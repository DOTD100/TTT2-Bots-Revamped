if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_FUSE then return false end

--[[
The Fuse (TTT2Fuse) is a traitor on a clock. `ttt2_fuse_explode_timer` seconds after it takes the role - and
again after every kill it makes, because a kill puts the fuse back to full - it plays a lit-fuse sound and
three seconds later explodes where it stands: util.BlastDamage(ply, ply, pos, 300, 200). That is up to 200
damage inside 300 units with no team filter, so an ally standing next to it dies too, against a
teamkill score multiplier of -16.

There is no manual detonation for us to call, whatever the workshop blurb suggests - the explosion belongs to
the timer. So the one decision this role has is what to do with its last seconds, and that is
behaviors/fusecharge.lua: for the final 15 seconds the bot stops trying to survive and walks at the nearest
enemy position it remembers.

Everything else is an ordinary traitor that cannot afford to be passive. SetCanHide/SetCanSnipe keep the
wander behavior from parking it in a hiding spot or on a sniper perch, and SetIsFollower keeps it out of a
teammate's shadow - all three are ways to spend a fuse doing nothing. It still plants and coordinates, so
the tree is the traitor one with the charge inserted near the top of it.
]]

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

-- The traitor tree with the fuse charge added after the plant node. Order matters: FightBack still runs
-- first, so a bot with something to shoot shoots, and FuseCharge only owns the ticks where it does not.
local bTree = {
    _prior.FightBack,
    _bh.Defib,
    _bh.PlantBomb,
    _bh.FuseCharge,
    _bh.InvestigateCorpse,
    _prior.Restore,
    _bh.FollowPlan,
    _bh.Interact,
    _prior.Minge,
    _prior.Investigate,
    _prior.Patrol
}

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
}

local fuse = TTTBots.RoleData.New("fuse", TEAM_TRAITOR)
fuse:SetDefusesC4(false)
fuse:SetPlantsC4(true)
fuse:SetCanHaveRadar(true)
fuse:SetCanCoordinate(true)
fuse:SetStartsFights(true)
fuse:SetUsesSuspicion(false)
fuse:SetCanHide(false)
fuse:SetCanSnipe(false)
fuse:SetIsFollower(false)
fuse:SetTeam(TEAM_TRAITOR)
fuse:SetBTree(bTree)
fuse:SetAlliedTeams(allyTeams)
fuse:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(fuse)

return true
