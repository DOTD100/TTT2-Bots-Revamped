if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_SHINIGAMI then return false end

-- Plays as a normal hidden innocent while alive. Once it dies, TTT2 revives it into a knife-only
-- killer that loses health every second, cannot pick up any other weapon, and is shown every traitor.
local NWBOOL_SPAWNED = "SpawnedAsShinigami"
local HUNT_DELAY = 1 / TTTBots.Tickrate

local shinigami = TTTBots.RoleData.New("shinigami", TEAM_INNOCENT)
shinigami:SetDefusesC4(true)
shinigami:SetCanHide(true)
shinigami:SetCanSnipe(true)
shinigami:SetUsesSuspicion(true)
-- The score is killsMultiplier 2 / teamKillsMultiplier -8, so it must never start random fights.
-- Everything it attacks comes from the traitor targeting below, which only ever aims at traitors.
shinigami:SetStartsFights(false)
shinigami:SetTeam(TEAM_INNOCENT)
-- Its knife is NOT registered as a role weapon, deliberately. The knife only exists once TTT2 revives this
-- role into its undead form, and that form is still on the innocent team and is punished hard for
-- teamkills, so a KOS tell on the knife would have every innocent bot shoot a teammate. Role weapons are
-- registered for roles whose holder is fair game - the Arsonist, the Shanker and their kind.
shinigami:SetBTree(TTTBots.Behaviors.DefaultTrees.innocent)
shinigami:SetAlliedRoles({})
shinigami:SetAlliedTeams({})
TTTBots.Roles.RegisterRole(shinigami)

---@param ply Player
---@return boolean
local function isSpawnedShinigami(ply)
    if not IsValid(ply) then return false end
    if ply:GetSubRole() ~= ROLE_SHINIGAMI then return false end

    return ply:GetNWBool(NWBOOL_SPAWNED, false) == true
end

-- The spawned Shinigami is shown every traitor by TTT2, so this skips visibility on purpose.
---@param bot Bot
---@return Player? traitor
local function getNearestKnownTraitor(bot)
    local closest, closestDist = nil, nil

    for _, ply in ipairs(TTTBots.Match.AlivePlayers) do
        if ply == bot then continue end
        if not TTTBots.Lib.IsPlayerAlive(ply) then continue end
        if not TTTBots.Roles.IsTraitor(ply) then continue end
        if TTTBots.Roles.IsAllies(bot, ply) then continue end

        local dist = bot:GetPos():Distance(ply:GetPos())
        if not closestDist or dist < closestDist then
            closest, closestDist = ply, dist
        end
    end

    return closest
end

-- FightBack is the first node of the tree and hands bot.attackTarget straight to the normal
-- AttackTarget logic, so combat stays in one place.
---@param bot Bot
local function hunt(bot)
    if not isSpawnedShinigami(bot) then return end
    if not TTTBots.Lib.IsPlayerAlive(bot) then return end

    -- Hold on to a living traitor, sight or no sight, so we do not swap targets mid-fight. The old condition
    -- also demanded `bot:Visible(current)`, which swapped the target precisely when the fight target stepped
    -- behind cover - and every swap is a fresh acquisition for the bot (`locomotor:OnNewTarget`: look speed x5
    -- plus a new reaction delay), so a fight against somebody using cover was a flicker. Anything that is not a
    -- living traitor is still replaced by the nearest known one: a dead target, the grudge we keep from whoever
    -- killed us - that killer may well have been an innocent, and this role is punished hard for teamkills.
    local current = bot.attackTarget
    if IsValid(current) and TTTBots.Roles.IsTraitor(current) and TTTBots.Lib.IsPlayerAlive(current) then return end

    local traitor = getNearestKnownTraitor(bot)
    if not traitor then return end

    bot:SetAttackTarget(traitor)

    -- Attack.Seek navigates from memory alone (it ignores the position it is passed), so what this
    -- role knows about the traitors has to be written there. Without it the bot has no last known
    -- position to walk to, so Seek takes its wander branch and calls StopAttack - the bot just stands
    -- on the spot it revived on until the next 5 second wander tick.
    bot.components.memory:UpdateKnownPositionFor(traitor)
end

-- Gated the same way the role addon's own Think hook is, so we scan on the bot tick, not every frame.
local nextHunt = 0
hook.Add("Think", "TTTBots.shinigami.hunt", function()
    local time = CurTime()
    if time < nextHunt then return end
    nextHunt = time + HUNT_DELAY

    for _, bot in ipairs(TTTBots.Bots or {}) do
        if not IsValid(bot) then continue end
        hunt(bot)
    end
end)

return true
