--- Plants a bomb in a safe location. Does not do anything if the bot does not have C4 in its inventory.


TTTBots.Behaviors.PlantBomb = {}

local lib = TTTBots.Lib

local PlantBomb = TTTBots.Behaviors.PlantBomb
PlantBomb.Name = "PlantBomb"
PlantBomb.Description = "Plant a bomb in a safe location"
PlantBomb.Interruptible = true

PlantBomb.PLANT_RANGE = 80 --- Distance to the site to which we can plant the bomb
--- The fuse bots arm their C4 with. TTT2 clamps a player-armed bomb to C4_MINIMUM_TIME..C4_MAXIMUM_TIME
--- (45..600), so bots always use the shortest legal fuse. The planting weapon itself leaves the bomb
--- unarmed - arming it is a separate step the planter normally does from the C4's config menu - so
--- this call is the only thing that sets the timer on a bot-planted bomb.
PlantBomb.C4_FUSE = 45
--- Seconds spent standing at the site with the C4 in hand before actually planting it. A player has
--- to hold the C4 out, place it and arm it; doing that in one tick made bots look like they were
--- arming a bomb from across the room and gave anyone nearby no chance to catch them doing it.
PlantBomb.PLANT_TIME = 3

--- How far apart two bombs have to be to count as being in different places.
---
--- There was a 512 unit rule already, but it only ever looked at bombs that were *already in the world*, and it
--- is small enough that two C4s 600 units apart still read as the same corner of the map. Two traitors with a
--- plant job start on the same tick, both see no bombs, and both take the single best-weighted spot - so the
--- separation has to be generous, and spots have to be reserved before the bomb exists.
PlantBomb.C4_MIN_SEPARATION = 1024

local STATUS = TTTBots.STATUS

---@class Bot
---@field bombFailCounter number The number of times the bot has failed to plant a bomb.

function PlantBomb.HasBomb(bot)
    return bot:HasWeapon("weapon_ttt_c4")
end

function PlantBomb.IsPlanterRole(bot)
    local role = TTTBots.Roles.GetRoleFor(bot) ---@type RoleData
    return role:GetPlantsC4()
end

--- How many accumulated plant failures before a bot backs off. The counter decays over time.
PlantBomb.PLANT_FAIL_LIMIT = 6

--- Validate the behavior
function PlantBomb.Validate(bot)
    if not lib.GetConVarBool("plant_c4") then return false end -- This behavior is disabled per the user's choice.
    -- Back off after repeated failures so a bot can't try to plant indefinitely. Decayed by
    -- the PreventInfinitePlants timer below.
    if (bot.bombFailCounter or 0) >= PlantBomb.PLANT_FAIL_LIMIT then return false end
    local inRound = TTTBots.Match.IsRoundActive()
    local isPlanter = PlantBomb.IsPlanterRole(bot)
    local hasBomb = PlantBomb.HasBomb(bot)
    return inRound and isPlanter and hasBomb
end

---@type table<Vector, number> -- A list of spots that have been penalized for being impossible to plant at.
local penalizedBombSpots = {}

--- Spots a bot has committed to but has not planted at yet, with who took it and when.
---
--- A bomb that does not exist yet pushes nobody away, so without this two bots planning on the same tick both
--- choose the one best-weighted spot and plant within `PLANT_RANGE` of each other. Reserving is what makes the
--- second bot look at the next spot instead.
---@type table<Vector, {bot: Bot, time: number}>
local claimedSpots = {}

--- How long a reservation survives without being released. A plant resolves in well under this (a walk plus the
--- wind-up), so it only ever cleans up after a behaviour that ended without releasing - a bot that died on the
--- way to the spot, say - and it does that without needing a hook to watch for deaths.
local CLAIM_LIFETIME = 60

--- Whether somebody else has already committed to this spot.
---@param spot Vector|nil
---@param bot Bot
---@return boolean
function PlantBomb.IsSpotClaimed(spot, bot)
    if not spot then return false end

    local claim = claimedSpots[spot]
    if not claim then return false end

    if (CurTime() - claim.time) > CLAIM_LIFETIME then
        claimedSpots[spot] = nil -- stale: whoever took it is not coming
        return false
    end

    return claim.bot ~= bot -- your own reservation is not in your way
end

---@param bot Bot
---@param spot Vector
function PlantBomb.ClaimSpot(bot, spot)
    claimedSpots[spot] = { bot = bot, time = CurTime() }
end

---@param spot Vector|nil
function PlantBomb.ReleaseSpot(spot)
    if spot then claimedSpots[spot] = nil end
end

---Gets the best spot to plant a bomb around the bot.
---@param bot Bot
---@return Vector|nil
function PlantBomb.FindPlantSpot(bot)
    local options = TTTBots.Spots.GetSpotsInCategory("bomb")
    local weightedOptions = {}
    local extantBombs = ents.FindByClass("ttt_c4")
    -- The roomiest spot that failed the separation test, kept in case this map has nowhere that qualifies at all.
    local fallbackSpot, fallbackDist = nil, -math.huge

    -- We will use a weighting system for this.
    for _, spot in pairs(options) do
        -- ❌ Disqualify spots that have failed to be reached too many times
        if penalizedBombSpots[spot] and penalizedBombSpots[spot] > 25 then continue end

        -- 🙋🏽 Disqualify spots another bot has already committed to but not planted at yet
        if PlantBomb.IsSpotClaimed(spot, bot) then continue end

        -- 💣 Disqualify spots that already have a bomb within `C4_MIN_SEPARATION`, and remember the least
        -- crowded of those in case none of them qualify.
        local nearestBomb = math.huge
        for _, bomb in pairs(extantBombs) do
            local dist = bomb:GetPos():Distance(spot)
            if dist < nearestBomb then nearestBomb = dist end
        end

        if nearestBomb < PlantBomb.C4_MIN_SEPARATION then
            if nearestBomb > fallbackDist then
                fallbackDist = nearestBomb
                fallbackSpot = spot
            end
            continue
        end

        -- Witnesses are only needed by the weighting below, so the list is built for surviving spots alone.
        local witnesses = lib.GetAllVisible(spot, true, bot)

        -- Build the weight only for spots that survived disqualification, so a disqualified spot
        -- can never linger in the table with a default weight and be picked as "best".
        local weight = 0

        -- 👀 Bonus if visible
        if bot:VisibleVec(spot) then
            weight = weight + 2
        end

        -- 🧍🏽Big penalty for current witnesses
        weight = weight - (2 * #witnesses) -- Get a list of all non-evils that can see this pos

        -- ❌ Penalize suspected broken spots
        if penalizedBombSpots[spot] then
            weight = weight - penalizedBombSpots[spot]
        end

        -- 🤏🏽Penalize or reward based on distance to targets
        for _, ply in pairs(player.GetAll()) do
            if not (not TTTBots.Roles.IsAllies(bot, ply) and lib.IsPlayerAlive(ply)) then continue end

            --- We want to find spots in the 'goldilocks zone' -- not too close to targets, but not too far away either.
            local distToSpot = ply:GetPos():Distance(spot)
            if distToSpot < 256 then
                weight = weight - 1
            elseif distToSpot < 1024 then
                weight = weight + 0.5
            elseif distToSpot > 2048 then
                weight = weight - 0.5
            end
        end

        weightedOptions[spot] = weight
    end

    local bestSpot = nil
    local bestWeight = -math.huge
    for spot, weight in pairs(weightedOptions) do
        if weight > bestWeight then
            bestWeight = weight
            bestSpot = spot
        end
    end

    -- Every candidate was too close to a bomb already in the world. Planting in the roomiest corner of a small
    -- map still beats not planting at all, and it is still the pair of bombs that ends up furthest apart - so
    -- this cannot turn into "the bot stands at the spot and never plants" on a tight map.
    if not bestSpot then
        bestSpot = fallbackSpot
    end

    if not bestSpot then
        bot.bombFailCounter = (bot.bombFailCounter or 0) + 1
    end

    return bestSpot
end

--- Called when the behavior is started
function PlantBomb.OnStart(bot)
    local spot = PlantBomb.FindPlantSpot(bot)
    if not spot then
        -- No suitable spot is available right now (common). Fail quietly; the fail counter
        -- incremented by FindPlantSpot provides backoff via Validate.
        return STATUS.FAILURE
    end
    local inventory = bot:BotInventory()
    inventory:PauseAutoSwitch()

    bot.bombPlantSpot = spot
    PlantBomb.ClaimSpot(bot, spot) -- held until this attempt ends, so no other bot takes the same spot
    bot.c4PlantStart = nil -- every attempt does its own wind-up
    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
function PlantBomb.OnRunning(bot)
    local spot = bot.bombPlantSpot
    if not spot then return STATUS.FAILURE end

    local distToSpot = bot:GetPos():Distance(spot)
    local locomotor = bot:BotLocomotor()
    locomotor:SetGoal(spot)

    if locomotor.status == locomotor.PATH_STATUSES.IMPOSSIBLE then
        penalizedBombSpots[spot] = (penalizedBombSpots[spot] or 0) + 3
        bot.bombFailCounter = (bot.bombFailCounter or 0) +
            2 -- Increment by 2 specifically to prevent the bot from trying to plant indefinitely.
        return STATUS.FAILURE
    end

    if distToSpot > PlantBomb.PLANT_RANGE then
        return STATUS.RUNNING
    end
    -- We are close enough to plant.
    local witnesses = lib.GetAllVisible(spot, true, bot)
    local currentTime = CurTime()

    if #witnesses > 0 then
        bot.lastWitnessTime = currentTime
        -- Somebody turned up. Abandon the wind-up and start over later instead of planting in front
        -- of an audience.
        bot.c4PlantStart = nil
        locomotor:SetHalt(false)
        return STATUS.RUNNING
    elseif bot.lastWitnessTime and currentTime - bot.lastWitnessTime <= 3 then
        bot.c4PlantStart = nil
        locomotor:SetHalt(false)
        return STATUS.RUNNING
    end

    -- Take our time over it. Hold the C4 out at the site for a few seconds before the weapon is
    -- allowed to place anything, which is also the window in which someone can walk in on us.
    -- Starting the clock on this tick means this tick is always the first of the wind-up.
    local plantStart = bot.c4PlantStart or currentTime
    bot.c4PlantStart = plantStart

    if currentTime - plantStart < PlantBomb.PLANT_TIME then
        locomotor:SetHalt(true)
        bot:SelectWeapon("weapon_ttt_c4")
        locomotor:LookAt(spot)
        return STATUS.RUNNING
    end

    -- We are safe to plant, and have been standing here long enough to do it.
    locomotor:SetHalt(false)
    bot:SelectWeapon("weapon_ttt_c4")
    locomotor:LookAt(spot)
    locomotor:StartAttack()

    -- If planting consumed the C4 weapon, arm the placed bomb and finish. Otherwise we keep
    -- running; Validate (which requires HasBomb) will end us once the weapon is gone.
    if not PlantBomb.HasBomb(bot) then
        bot.c4PlantStart = nil
        PlantBomb.ArmNearbyBomb(bot)
        return STATUS.SUCCESS
    end

    return STATUS.RUNNING -- This behavior depends on the validation call ending it.
end

--- Called when the behavior returns a success state
function PlantBomb.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function PlantBomb.OnFailure(bot)
end

function PlantBomb.ArmNearbyBomb(bot)
    local bombs = ents.FindByClass("ttt_c4")
    local closestBomb = nil
    local closestDist = math.huge
    for _, bomb in pairs(bombs) do
        if bomb:GetArmed() then continue end
        local dist = bot:GetPos():Distance(bomb:GetPos())
        if dist < closestDist then
            closestDist = dist
            closestBomb = bomb
        end
    end

    if closestBomb and closestDist < PlantBomb.PLANT_RANGE then
        -- Arm it with TTT2's own minimum rather than a copy of the number, so the fuse stays correct
        -- even if a server changes it.
        closestBomb:Arm(bot, C4_MINIMUM_TIME or PlantBomb.C4_FUSE)
        local chatter = bot:BotChatter()
        if chatter then
            chatter:On("BombArmed", {}, true)
        end
        return true
    end

    return false
end

--- Called when the behavior ends
function PlantBomb.OnEnd(bot)
    PlantBomb.ReleaseSpot(bot.bombPlantSpot)
    bot.bombPlantSpot = nil
    bot.c4PlantStart = nil
    local locomotor = bot:BotLocomotor()
    local inventory = bot:BotInventory()
    inventory:ResumeAutoSwitch()
    locomotor:StopAttack()
    -- Never leave the bot rooted to the spot after the behavior ends.
    locomotor:SetHalt(false)
    PlantBomb.ArmNearbyBomb(bot)
end

-- This part of the code is referencing preevnting a bot trying to plant indefinitely (and thus failing)
-- Specifically, we decrement the 'bomb fail' counter on each bot once per 20 seconds as to not break the behavior.
timer.Create("TTTBots.Behavior.PlantBomb.PreventInfinitePlants", 20, 0, function()
    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot ~= NULL and bot.components) then continue end
        bot.bombFailCounter = math.max(bot.bombFailCounter or 0, 0) - 1
    end
end)
