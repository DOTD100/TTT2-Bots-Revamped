--- Similar to BWander's decrowding mechanic, 
--- but this behavior is specifically focused on preventing overcrowding.



---@class BDecrowd : BBase
TTTBots.Behaviors.Decrowd = {}

local lib = TTTBots.Lib

---@class BDecrowd
local Decrowd = TTTBots.Behaviors.Decrowd
Decrowd.Name = "Decrowd"
Decrowd.Description = "Try to prevent overcrowding."
Decrowd.Interruptible = true
Decrowd.MaxNearbyPlayers = 3
Decrowd.NearbyThreshold = 800 --- How close a player has to be to be considered "nearby"
--- How recently we must have seen or heard gunfire for it to still shape what we do.
Decrowd.GunfireMemory = 6
--- Shots this close are worth moving away from even when the room is not crowded.
Decrowd.GunfireRadius = 700
--- How much ground to put between ourselves and the shooting.
Decrowd.BackOffDistance = 500

---@class Bot
---@field targetRetreatPos Vector?
---@field lastGunfirePos Vector? Where the last shooting we saw, or that passed close by, came from
---@field lastGunfireTime number? When that was

local STATUS = TTTBots.STATUS

---@param bot Bot
function Decrowd.Validate(bot)
    -- Bullets in the air are a reason to move on their own, crowded room or not. We are only reached
    -- without a target of our own (FightBack outranks us), so this is a "get out of the line of fire"
    -- move rather than cowardice: any bot that knows who to shoot is already shooting them.
    local gunfirePos = Decrowd.GetRecentGunfirePos(bot)
    if gunfirePos and bot:GetPos():Distance(gunfirePos) <= Decrowd.GunfireRadius then
        return true
    end

    -- Always fail if the bot loves crowding.
    local personality = bot:BotPersonality()
    if personality:GetTraitBool("lovesCrowds") then return false end

    -- Only return true if there are too many people around us.
    local memory = bot:BotMemory()
    local visiblePlys = memory:GetRecentlySeenPlayers(5)

    local count = Decrowd.CountNearby(bot, visiblePlys)

    return (count > Decrowd.MaxNearbyPlayers)
end

--- Where the most recent shooting we saw - or that passed close enough to notice - came from, or nil
--- once it is old enough that it should not shape what we do.
---@param bot Bot
---@return Vector? pos
function Decrowd.GetRecentGunfirePos(bot)
    if not bot.lastGunfireTime then return nil end
    if (CurTime() - bot.lastGunfireTime) > Decrowd.GunfireMemory then return nil end

    return bot.lastGunfirePos
end

--- Somewhere on the far side of us from the shooting.
---@param bot Bot
---@param threatPos Vector
---@return Vector
function Decrowd.GetBackOffPos(bot, threatPos)
    local away = bot:GetPos() - threatPos
    away.z = 0
    if away:LengthSqr() < 1 then
        away = Vector(1, 0, 0)
    else
        away:Normalize()
    end

    return bot:GetPos() + away * Decrowd.BackOffDistance
end

function Decrowd.CountNearby(bot, plyTable)
    local count = 0
    for i, ply in pairs(plyTable) do
        local plyPos = ply:GetPos()
        local dist = bot:GetPos():Distance(plyPos)
        if dist < Decrowd.NearbyThreshold then
            count = count + 1
        end
    end
    return count

end

---Returns the number of living witnesses currently that can see pos (and are close-ish to it).
---@param bot Bot
---@param pos Vector
---@return number
function Decrowd.GetWitnessesAround(bot, pos)

    local witnesses = TTTBots.Lib.GetAllWitnessesBasic(
        pos,
        TTTBots.Match.AlivePlayers,
        bot
    )

    local count = Decrowd.CountNearby(bot, witnesses)

    return count
end

---Tries to locate a hiding spot without a lot of witnesses.
---Is not guaranteed to come up with a result due to performance reasons.
---@param bot Bot
---@return Vector?
function Decrowd.FindRetreatSpot(bot)
    local spots = TTTBots.Spots.GetSpotsInCategory("hiding")
    if not spots or #spots == 0 then return nil end

    for i = 1, 5 do
        local randomSpot = table.Random(spots)
        local nWitnesses = Decrowd.GetWitnessesAround(bot, randomSpot)

        if nWitnesses <= 1 then
            return randomSpot
        end
    end
end

function Decrowd.FindRetreatArea(bot)
    local botRegion = TTTBots.Lib.GetNearestRegion(bot:GetPos())
    if botRegion then
        for i = 1, 5 do
            local randomArea = TTTBots.Lib.GetRandomNavInRegion(botRegion)
            if not randomArea then continue end
            local nWitnesses = Decrowd.GetWitnessesAround(bot, randomArea:GetCenter())

            if nWitnesses <= 1 then
                return randomArea
            end
        end
    end

    -- Fallback just in case.
    local allNavs = navmesh.GetAllNavAreas()
    if not allNavs or #allNavs == 0 then return nil end
    return table.Random(allNavs)
end

---@param bot Bot
function Decrowd.OnStart(bot)
    -- Backing away from a firefight and leaving an overcrowded room are different problems, so they get
    -- different answers: one is about leaving the line of fire, not about finding somewhere to hide.
    local gunfirePos = Decrowd.GetRecentGunfirePos(bot)
    if gunfirePos then
        bot.targetRetreatPos = Decrowd.GetBackOffPos(bot, gunfirePos)
        return STATUS.RUNNING
    end

    local retreatArea = Decrowd.FindRetreatArea(bot)
    bot.targetRetreatPos = (
        Decrowd.FindRetreatSpot(bot)
        or (retreatArea and retreatArea:GetCenter())
    )
    return STATUS.RUNNING
end

---@param bot Bot
function Decrowd.OnRunning(bot)
    if not bot.targetRetreatPos then return Decrowd.OnStart(bot) end

    local loco = bot:BotLocomotor()
    loco:SetGoal(bot.targetRetreatPos)

    -- Keep watching the shooting while we pull back. A bot that turns its back on a firefight is just
    -- waiting to be shot in the back of it.
    local gunfirePos = Decrowd.GetRecentGunfirePos(bot)
    if gunfirePos then
        loco:LookAt(gunfirePos)
    end

    return STATUS.RUNNING
end

---@param bot Bot
function Decrowd.OnSuccess(bot)
end

---@param bot Bot
function Decrowd.OnFailure(bot)
end

---@param bot Bot
function Decrowd.OnEnd(bot)
    bot:BotLocomotor():StopMoving()
end
