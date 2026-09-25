if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_SHERIFF then return false end

local allyRoles = {
    sheriff = true
}

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _prior.FightBack,
    _bh.Defuse,
    _prior.Restore,
    _prior.Minge,
    -- `_prior.Investigate`, not `_bh.Investigate`: there is no behaviour of that name (the nodes are
    -- InvestigateCorpse and InvestigateNoise, and Investigate is the group that holds them). A nil node in a
    -- table constructor is simply dropped, so the typo did not error - it silently left this role as the only
    -- one in the addon with no investigate group at all, so deputies never walked to a corpse or a noise.
    _prior.Investigate,
    _bh.Decrowd,
    _prior.Patrol
}

local deputy = TTTBots.RoleData.New("deputy", TEAM_INNOCENT)
deputy:SetDefusesC4(true)
deputy:SetCanCoordinate(false)
deputy:SetStartsFights(false)
deputy:SetUsesSuspicion(true)
deputy:SetTeam(TEAM_INNOCENT)
deputy:SetBTree(bTree)
deputy:SetLovesTeammates(true)
deputy:SetAppearsPolice(true)
deputy:SetAlliedRoles(allyRoles)
TTTBots.Roles.RegisterRole(deputy)

-- Sidekick help master when shooting a victim
hook.Add("TTTBotsOnWitnessFireBullets", "TTTBotsOnWitnessFireBullets", function(witness, attacker, data, angleDiff)
    local attackerRole = attacker:GetRoleStringRaw()
    local witnessRole = witness:GetRoleStringRaw()

    if witnessRole == 'deputy' and attackerRole == 'sheriff' then
        -- HitPos is a Vector, not an entity; IsValid would always be false here.
        local eyeTrace = attacker:GetEyeTrace()
        local hitPos = eyeTrace.HitPos
        if not hitPos then return end
        local target = TTTBots.Lib.GetClosest(TTTBots.Roles.GetNonAllies(witness), hitPos)
        if not target then return end
        witness:SetAttackTarget(target)
    end
end)

-- Sidekick help its master when he's attacked
hook.Add("TTTBotsOnWitnessHurt", "TTTBotsOnWitnessHurt",
    function(witness, victim, attacker, healthRemaining, damageTaken)
        if not IsValid(attacker) then return end

        local victimRole = victim:GetRoleStringRaw()
        local witnessRole = witness:GetRoleStringRaw()

        if witnessRole == 'deputy' and victimRole == 'sheriff' then
            witness:SetAttackTarget(attacker)
        end
    end)

return true
