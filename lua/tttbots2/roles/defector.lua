if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_DEFECTOR then return false end

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or 'jesters'] = true,
}

-- The Defector is never handed out at round start (notSelectable). It only exists because somebody took
-- the Defector Jihad item: whoever picks that item up is converted, handed a Jihad Bomb, and from then
-- on every point of damage it deals is zeroed unless it comes from an explosion. So a defector bot must
-- not waste time shooting, and must instead walk into someone and blow itself up.
TTTBots.Buyables.RegisterBuyable({
    Name = "Defector Jihad",
    Class = "weapon_ttt_defector_jihad",
    Price = 1,
    Priority = 1,
    RandomChance = 2, -- not every traitor has to volunteer for this
    Roles = { "traitor" },
    -- The item is only worth a credit while there is somebody left worth converting.
    CanBuy = function(ply)
        return TTTBots.Behaviors.DefectorDeliver.FindTarget(ply) ~= nil
    end,
})

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _bh.DefectorJihad,
    _prior.Restore,
    _bh.Interact,
    _prior.Minge,
    _prior.Investigate,
    _prior.Patrol
}

local defector = TTTBots.RoleData.New("defector", TEAM_TRAITOR)
defector:SetDefusesC4(false)
defector:SetPlantsC4(false)
defector:SetCanCoordinate(false)
-- Guns are worthless to this role, so picking fights or acting on suspicion is only wasted ammo and
-- wasted time it could spend getting into position. There is deliberately no FightBack node either.
defector:SetStartsFights(false)
defector:SetUsesSuspicion(false)
defector:SetCanSnipe(false)
defector:SetCanHide(false)
defector:SetTeam(TEAM_TRAITOR)
defector:SetBTree(bTree)
defector:SetAlliedTeams(allyTeams)
defector:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(defector)

return true
