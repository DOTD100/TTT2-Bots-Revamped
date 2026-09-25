
TTTBots.Behaviors.Follow = {}

local lib = TTTBots.Lib

local Follow = TTTBots.Behaviors.Follow
Follow.Name = "Follow"
Follow.Description = "Follow a player non-descreetly."
Follow.Interruptible = true

local STATUS = TTTBots.STATUS

--- Return if whether or not the bot is a follower per their personality. That is, if they are a traitor or have a following trait.
---@param bot Bot
---@return boolean
function Follow.IsFollowerPersonality(bot)
    local personality = bot:BotPersonality()
    if not personality then return false end

    local hasTrait = personality:GetTraitBool("follower") or personality:GetTraitBool("followerAlways")

    return hasTrait
end

--- Return if the bot is a follower role, like a traitor.
---@param bot any
function Follow.IsFollowerRole(bot)
    local role = TTTBots.Roles.GetRoleFor(bot) ---@type RoleData
    if not role then return false end

    return role:GetIsFollower()
end

--- Similar to IsFollower, but returns mathematical chance of deciding to follow a new person this tick.
function Follow.GetFollowChance(bot)
    local BASE_CHANCE = 0.1 -- X % chance per tick
    local debugging = false
    local chance = BASE_CHANCE * (Follow.IsFollowerPersonality(bot) and 2 or 1) * (Follow.IsFollowerRole(bot) and 2 or 1)

    local personality = bot:BotPersonality()
    if not personality then return chance end
    local alwaysFollows = personality:GetTraitBool("followerAlways")

    return (
        ((debugging or alwaysFollows) and 100) or -- if debugging return 100% always.
        chance                                    -- otherwise return the actual chance.
    )
end

function Follow.GetFollowTargets(bot)
    local targets = {}
    local isFollowerRole = Follow.IsFollowerRole(bot)
    local followTeammates = isFollowerRole -- and bot:HasTrait("teamplayer") -- Only applies for traitors

    ---@type CMemory
    local memory = bot.components.memory
    local recentPlayers = memory:GetRecentlySeenPlayers(8)

    -- For this function we are going to cheat and assume we know the updated positions of every player we've seen recently.
    for i, other in pairs(recentPlayers) do
        if not lib.IsPlayerAlive(other) then continue end
        if other == bot then continue end -- shouldn't be possible but neither should a lot of things.
        if other:IsBot() then
            local otherFollowTarget = other.followTarget
            if otherFollowTarget == bot then continue end              -- don't follow bots that are following us. This will create a death spiral.
        end
        if followTeammates and TTTBots.Roles.IsAllies(bot, other) then -- we are following teammates and this player is evil (like ourselves).
            table.insert(targets, other)
        elseif not followTeammates then                                -- we are not following teammates so just add everyone.
            table.insert(targets, other)
        end
    end

    return targets
end

--- Get a random point in the list of CNavAreas
---@param navList table<CNavArea>
---@return Vector
function Follow.GetRandomPointInList(navList)
    local nav = table.Random(navList)
    local pos = nav:GetRandomPoint()
    return pos
end

--- Validate the behavior
function Follow.Validate(bot)
    -- `bot.followTarget` is shared with the plan system (see followplan.lua), which can point it at
    -- a player we have never actually seen. TTT players also stay valid after dying, so `IsValid`
    -- alone is not enough. Clear it as soon as it stops being followable.
    if bot.followTarget and not (IsValid(bot.followTarget) and lib.IsPlayerAlive(bot.followTarget)) then
        bot.followTarget = nil
    end
    if not TTTBots.Match.IsRoundActive() then return false end

    -- Already following someone. OnStart can use this target directly, so it does not matter that
    -- the target may not be in our "recently seen" list.
    if bot.followTarget then return true end

    local shouldFollow = lib.TestPercent(Follow.GetFollowChance(bot))
    -- OnStart picks a random entry from this list and `table.Random` returns nil for an empty
    -- table, so we must not start a brand new follow without at least one candidate.
    return shouldFollow and #Follow.GetFollowTargets(bot) > 0
end

--- Called when the behavior is started
function Follow.OnStart(bot)
    -- The plan system can hand us a target we have not seen recently, so it never shows up in this
    -- list. Prefer an assigned target over a random pick, and never let a nil target through:
    -- `table.Random` returns nil for an empty table, which used to raise an error here.
    local target = table.Random(Follow.GetFollowTargets(bot)) or bot.followTarget

    if not (target and IsValid(target) and lib.IsPlayerAlive(target)) then
        bot.followTarget = nil
        return STATUS.FAILURE
    end

    bot.followTarget = target
    bot.followEndTime = CurTime() + math.random(12, 24)

    local chatter = bot:BotChatter()
    chatter:On("FollowStarted", { player = bot.followTarget:Nick() })

    return STATUS.RUNNING
end

function Follow.GetFollowPoint(target)
    return target:GetPos()
end

--- Called when the behavior's last state is running
function Follow.OnRunning(bot)
    local target = bot.followTarget

    if not IsValid(target) or not lib.IsPlayerAlive(target) then
        return STATUS.FAILURE
    end

    if CurTime() > (bot.followEndTime or 0) then
        return STATUS.FAILURE
    end

    -- if bot.botFollowPoint ~= nil and bot:GetPos():Distance(bot.botFollowPoint) < 100 then
    --     return STATUS.SUCCESS
    -- end

    local loco = bot:BotLocomotor()
    bot.botFollowPoint = Follow.GetFollowPoint(target)

    if bot.botFollowPoint == false then return STATUS.FAILURE end

    local distToPoint = bot:GetPos():Distance(bot.botFollowPoint)

    -- Close enough: stop where we are instead of asking to walk to the spot we are already standing on. A
    -- goal that tracks our own position is one we can never "arrive" at in the 32-unit sense the path
    -- manager uses, so the locomotion set/clear path flapped between arrived and has-a-goal and the bot
    -- stuttered in place (movement_conflicts.md #9). StopMoving is the same arrival signal every other
    -- behaviour uses, and it also drops the stale movement vector.
    if distToPoint < 250 then
        loco:StopMoving()
        return STATUS.RUNNING
    end

    loco:SetGoal(bot.botFollowPoint)
end

--- Called when the behavior returns a success state
function Follow.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Follow.OnFailure(bot)
end

--- Called when the behavior ends
function Follow.OnEnd(bot)
    timer.Remove("TTTBots.Follow." .. bot:Nick())
    bot.followTarget = nil
    bot.botFollowPoint = nil
    bot.followEndTime = nil
    bot:BotLocomotor():StopMoving()
end
