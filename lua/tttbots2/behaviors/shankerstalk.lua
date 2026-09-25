--- Claims the bot while the Shanker's knife is in hand and there is a victim worth creeping up on,
--- then runs the bot around to their back and stabs. Unlike AttackTarget it never shoots, so it
--- stays out of the way of the rest of the traitor tree whenever there is nothing to stab.
---@class BShankerStalk
TTTBots.Behaviors.ShankerStalk = {}

local lib = TTTBots.Lib

---@class BShankerStalk
local Stalk = TTTBots.Behaviors.ShankerStalk
Stalk.Name = "ShankerStalk"
Stalk.Description = "Stalk a player and shank them from behind"
Stalk.Interruptible = true

local STATUS = TTTBots.STATUS

local KNIFE = "weapon_ttt_shankknife"
-- The knife is a tracing melee weapon: it only accepts a hit whose trace ends under 80 units from the
-- attacker's eyes, deals 999 damage when the two players' yaw angles agree within 90 degrees, and 40
-- damage otherwise. Looking at somebody's back means facing the same way they do, so "get behind them
-- and aim at their back" is the whole of the role's damage problem.
local KNIFE_RANGE = 75   -- the weapon's own 80, minus a little slack for aiming at their chest
local SEEK_RANGE = 1200  -- do not cross the map for a stranger
local CHASE_MEMORY = 4   -- keep chasing this long after losing sight, like Attack.Seek does
local BEHIND_DIST = 50   -- how far behind the victim to walk before stopping and stabbing
local AIM_TOLERANCE = 12 -- degrees; the knife's reach is short, so this is deliberately loose
-- The knives are silent and leave no prints, so a victim who never sees us is free. A full target
-- scan costs a visibility trace per player, so it is rate limited while we have nobody to stalk.
local RETARGET_INTERVAL = 1

--- True when we are on the side of them they are not looking at. The weapon compares the two players'
--- yaw angles instead, which describes the same fact from the other end: looking at someone's back
--- means facing the same way they do.
---@param bot Bot
---@param victim Player
---@return boolean
local function isBehind(bot, victim)
    local toBot = bot:GetPos() - victim:GetPos()
    toBot.z = 0
    if toBot:LengthSqr() < 1 then return false end
    toBot:Normalize()

    local facing = victim:GetForward()
    facing.z = 0
    facing:Normalize()

    return facing:Dot(toBot) < 0
end

--- Roughly where the victim's back is. Walking at this rather than at the victim keeps us out of their
--- view cone on the way in, and gives the bot a point to circle around when it arrives in front.
---@param victim Player
---@return Vector
local function getBehindPos(victim)
    local facing = victim:GetForward()
    facing.z = 0
    if facing:LengthSqr() < 1 then facing = Vector(1, 0, 0) end
    facing:Normalize()

    return victim:GetPos() - facing * BEHIND_DIST
end

--- Are the view angles pointing at them yet? The eye angles are only rotated towards a new goal over
--- the following ticks (BotLocomotor:RotateEyeAnglesTo), so swinging on the same tick we decide to
--- stab would cut at whatever we happened to be facing.
---@param loco CLocomotor
---@param targetPos Vector
---@return boolean
local function isAimedAt(loco, targetPos)
    local yawDiff, pitchDiff = loco:GetEyeAngleDiffTo(targetPos)
    return math.abs(yawDiff) <= AIM_TOLERANCE and math.abs(pitchDiff) <= AIM_TOLERANCE
end

--- Best victim we can currently see. A turned back is worth walking a long way for, and every extra
--- witness is worth walking away from, because a 0.8 second stabbing next to a crowd is a death
--- sentence. Whoever scores best still wins, so the bot never ends up standing around doing nothing.
---@param bot Bot
---@return Player? target
local function findTarget(bot)
    local best, bestScore = nil, nil
    local nonAllies = TTTBots.Roles.GetNonAllies(bot)

    for _, ply in ipairs(nonAllies) do
        if not lib.IsPlayerAlive(ply) then continue end
        if not bot:Visible(ply) then continue end

        local dist = bot:GetPos():Distance(ply:GetPos())
        if dist > SEEK_RANGE then continue end

        local witnesses = table.Count(lib.GetAllWitnessesBasic(ply:GetPos(), nonAllies, bot))
        local score = (isBehind(bot, ply) and 0 or SEEK_RANGE) + (witnesses * 600) + dist

        if not bestScore or score < bestScore then
            best, bestScore = ply, score
        end
    end

    return best
end

--- Where the knife should be pointed, which is the middle of their back rather than their head. The knife
--- is a tracing melee weapon, so the kill depends on the trace landing on the victim at all; the head is
--- the smallest and most mobile part of the hitbox, and a swing at head height also sails over a victim
--- who is crouched or standing lower on a slope. Aiming at the torso is also what fixes the older bug of
--- aiming at GetPos(), which is at their feet - the trace then ran into the floor in front of them.
---@param victim Player
---@return Vector
local function getStabPos(victim)
    return TTTBots.Behaviors.AttackTarget.GetTargetBodyPos(victim)
end

--- Where we should be walking to reach the target, or nil if the trail has gone cold. The memory does
--- the same job for the attack behaviour, so this keeps the "warm trail" rule consistent with the rest
--- of the addon instead of tracking a living player through walls.
---@param bot Bot
---@param target Player
---@return Vector? pos
local function getChasePos(bot, target)
    local memory = bot.components.memory

    if bot:Visible(target) then
        memory:UpdateKnownPositionFor(target)
        return target:GetPos()
    end

    if (CurTime() - memory:GetLastSeenTime(target)) > CHASE_MEMORY then return nil end

    return memory:GetKnownPositionFor(target)
end

--- Validate the behavior
function Stalk.Validate(bot)
    if not lib.IsPlayerAlive(bot) then
        -- OnEnd does not always run for a bot that dies mid-stalk, and pauseAutoSwitch is a latch on
        -- the inventory component that survives death and round changes, so release it here instead of
        -- leaving a dead bot's inventory paused forever. Same for the sprint, which would otherwise keep
        -- the next bot to be given this player object running.
        local inv = bot:BotInventory()
        if inv then inv:ResumeAutoSwitch() end

        local loco = bot:BotLocomotor()
        if loco then loco:SetSprint(false) end

        return false
    end

    if not TTTBots.Match.IsRoundActive() then return false end
    if not bot:HasWeapon(KNIFE) then return false end
    -- Already committed to a fight: let the attack behavior handle it with a real weapon. This also
    -- means being shot at takes priority over stalking, since FightBack sets the target.
    if bot.attackTarget ~= nil then return false end

    local target = bot.shankTarget
    if IsValid(target) and lib.IsPlayerAlive(target) and getChasePos(bot, target) then return true end

    if CurTime() < (bot.shankNextScan or 0) then return false end
    bot.shankNextScan = CurTime() + RETARGET_INTERVAL

    bot.shankTarget = findTarget(bot)

    return bot.shankTarget ~= nil
end

--- Called when the behavior is started
function Stalk.OnStart(bot)
    local inv = bot:BotInventory()
    -- The knife is equipment, so the inventory would never pick it back up for us if it swapped away.
    if inv then inv:PauseAutoSwitch() end

    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
function Stalk.OnRunning(bot)
    local target = bot.shankTarget
    if not (IsValid(target) and lib.IsPlayerAlive(target)) then return STATUS.FAILURE end

    local chasePos = getChasePos(bot, target)
    if not chasePos then return STATUS.FAILURE end

    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    local stabPos = getStabPos(target)

    bot:SelectWeapon(KNIFE)
    loco:LookAt(stabPos)

    -- Measured to the spot we are actually stabbing at, which is what the weapon's own range check does
    -- with the position its trace ended on.
    local inReach = bot:EyePos():Distance(stabPos) <= KNIFE_RANGE
    if not (inReach and bot:Visible(target) and isBehind(bot, target)) then
        -- Not in position yet. Working around to their back rather than at the victim themselves keeps
        -- the bot from walking straight into their face and eating a shotgun for it. Run while doing it:
        -- at walking pace the bot matches the speed of anyone walking away from it and can never close,
        -- which leaves the knife - the entire role - unusable.
        loco:SetSprint(true)
        loco:SetGoal(getBehindPos(target))
        return STATUS.RUNNING
    end

    -- In position: stop running, hold still and let the view angles settle before swinging.
    loco:SetSprint(false)
    loco:StopMoving()
    if isAimedAt(loco, stabPos) then
        loco:StartAttack()
    else
        loco:StopAttack()
    end

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
    bot.shankTarget = nil

    local loco = bot:BotLocomotor()
    if loco then
        loco:StopMoving()
        loco:StopAttack()
        loco:SetSprint(false)
    end

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end
