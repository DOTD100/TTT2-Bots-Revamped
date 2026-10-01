---@class BHiddenStalk
TTTBots.Behaviors.HiddenStalk = {}

local lib = TTTBots.Lib
local Stalk = TTTBots.Behaviors.HiddenStalk
Stalk.Name = "HiddenStalk"
Stalk.Description = "Become the stalker and hunt with the knife"
Stalk.Interruptible = true

local STATUS = TTTBots.STATUS

local KNIFE = "weapon_ttt_hd_knife"
local KNIFE_RANGE = 70   -- the knife's own reach, HitDistance 64 plus a little slack
local SEEK_RANGE = 1200  -- do not cross the map for a stranger
local CHASE_MEMORY = 4   -- keep chasing this long after losing sight, like Attack.Seek does

---@param bot Bot
---@return boolean
local function isStalker(bot)
    return bot:GetNWBool("ttt2_hd_stalker_mode", false) == true
end

--- Nearest living non-ally we can actually see. Deliberately not "everyone alive": the role's wallhack
--- only ever works while standing still, so the bot should not be handed knowledge it never earned.
---@param bot Bot
---@return Player? target
local function findTarget(bot)
    local closest, closestDist = nil, nil

    for _, ply in ipairs(TTTBots.Roles.GetNonAllies(bot)) do
        if not lib.IsPlayerAlive(ply) then continue end
        if not lib.CanSeeEntity(bot, ply) then continue end

        local dist = bot:GetPos():Distance(ply:GetPos())
        if dist > SEEK_RANGE then continue end
        if not closestDist or dist < closestDist then
            closest, closestDist = ply, dist
        end
    end

    return closest
end

--- Where we should be walking to reach the target, or nil if the trail has gone cold. The memory does
--- the same job for the attack behaviour, so this keeps the "warm trail" rule consistent with the rest
--- of the addon instead of tracking a living player through walls.
---@param bot Bot
---@param target Player
---@return Vector? pos
local function getChasePos(bot, target)
    local memory = bot.components.memory

    if lib.CanSeeEntity(bot, target) then
        memory:UpdateKnownPositionFor(target)
        return target:GetPos()
    end

    if (CurTime() - memory:GetLastSeenTime(target)) > CHASE_MEMORY then return nil end

    return memory:GetKnownPositionFor(target)
end

--- Validate the behavior
function Stalk.Validate(bot)
    if not lib.IsPlayerAlive(bot) then return false end
    if bot:GetSubRole() ~= ROLE_HIDDEN then return false end

    -- Not a stalker yet: transform first. The entry point grants 8 health per living player, so waiting
    -- only costs the bot health it will never get back.
    if not isStalker(bot) then return true end

    local target = bot.stalkTarget
    if IsValid(target) and lib.IsPlayerAlive(target) and getChasePos(bot, target) then return true end

    bot.stalkTarget = findTarget(bot)

    return bot.stalkTarget ~= nil
end

--- Called when the behavior is started
function Stalk.OnStart(bot)
    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
function Stalk.OnRunning(bot)
    if not isStalker(bot) then
        -- Enter stalker mode the way a player does. The role's own entry point is a KeyPress listener on
        -- IN_RELOAD, which boosts health, grants the knife, nade and climbing pick, and flips the mode.
        -- Simulating the press keeps us in step with it instead of copying its numbers here.
        hook.Run("KeyPress", bot, IN_RELOAD)

        return STATUS.RUNNING
    end

    local target = bot.stalkTarget
    if not (IsValid(target) and lib.IsPlayerAlive(target)) then return STATUS.FAILURE end

    local chasePos = getChasePos(bot, target)
    if not chasePos then return STATUS.FAILURE end

    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    bot:SelectWeapon(KNIFE)
    loco:LookAt(target:GetPos())

    if bot:GetPos():Distance(chasePos) > KNIFE_RANGE then
        loco:SetGoal(chasePos)
        return STATUS.RUNNING
    end

    -- In reach. Only the swing: the knife's secondary throws it away for good, so it is never worth it.
    loco:StopMoving()
    loco:StartAttack()

    return STATUS.RUNNING
end

--- Called when the behavior returns a success state
function Stalk.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Stalk.OnFailure(bot)
end

--- Called when the behavior ends
function Stalk.OnEnd(bot)
    bot.stalkTarget = nil

    local loco = bot:BotLocomotor()
    if loco then
        loco:StopMoving()
        loco:StopAttack()
    end
end
