
TTTBots.Behaviors.Wander = {}

local lib = TTTBots.Lib

local Wander = TTTBots.Behaviors.Wander
Wander.Name = "Wander"
Wander.Description = "Wanders around the map"
Wander.Interruptible = true
Wander.Debug = false

Wander.CHANCE_TO_HIDE_IF_TRAIT = 3 -- 1 in X chance of hiding (or going to sniper spot) if we have a relevant trait

--- Wandering is supposed to end in an arrival, and a flat clock cannot do that on a map whose crossings take a
--- minute to walk. The deadline is scaled to the trip, extended while the bot is still getting closer, and
--- capped so that no single destination can own the round.
local WALK_SPEED_ESTIMATE = 350 -- units/second, deliberately pessimistic
local TRIP_TIME_SLACK = 1.6     -- multiplier on the straight-line estimate
local TRIP_TIME_GRACE = 6       -- seconds of slack on top of it
local PROGRESS_EPSILON = 32     -- units; how much closer counts as progress worth granting more time
local PROGRESS_RENEW = 8        -- seconds granted each time the bot sets a new closest approach
local MAX_WANDER_TIME = 90      -- hard ceiling on one destination
local DIST_CLOSE_THRESH = 100   -- close enough, once the short clock has run out, to count as arrived

--- How far the bot will look for a popular destination, and how often it will prefer one over a random area.
--- Popularity is the addon's own running count of where players actually stand (sv_popularnavs.lua), which is
--- the closest thing to "where is everybody" that a bot is allowed to know: it describes where people have
--- *been*, not where they are now, so drifting towards it is something a player does too.
local POPULAR_SEEK_RADIUS = 2500
local POPULAR_CHANCE = 50
local POPULAR_MAX_RANK = 200 -- do not scan a whole map's worth of nav areas to find one

--- A bot that has not seen anybody for this long counts as out of contact. This is the case the round reports
--- as broken: with a couple of bots left on a big map, each one keeps picking destinations inside its own
--- navmesh region (see GetAnyRandomNav), so they orbit their separate corners and never meet. A bot with no
--- contact goes looking for people instead.
local LOST_CONTACT_WINDOW = 20
--- How far a lost-contact destination has to be to count as going somewhere. `POPULAR_SEEK_RADIUS` is the
--- opposite idea - a hangout to drift towards while nearby - and is useless once the other bots are a map
--- away from it.
local RELOCATE_MIN_DIST = 1500
--- How many of the most popular far-away areas to choose from, so several quiet bots do not all pick the same
--- one spot and arrive in single file.
local RELOCATE_SPREAD = 5

--- How long a bot stands at a destination it has actually reached, whatever the walk there was allowed to
--- take. The trip-scaled deadline is for *getting* there; waiting out the rest of it on arrival is what reads
--- as a bot that has gone idle.
local ARRIVED_LOITER = 5

--- How far a sniper perch is worth walking to. A perch is somewhere the bot means to shoot from rather than
--- just a destination, so a perch on the far side of the map is not a perch - it is a walk there and back.
local SNIPER_SEEK_RADIUS = 2500

local STATUS = TTTBots.STATUS

local function printf(...)
    print(string.format(...))
end

--- Validate the behavior
function Wander.Validate(bot)
    return true
end

--- Called when the behavior is started
function Wander.OnStart(bot)
    Wander.UpdateWanderGoal(bot) -- sets bot.wander
    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
function Wander.OnRunning(bot)
    if not bot.wander then return Wander.OnStart(bot) end -- force reboot :P

    local hasExpired = Wander.HasExpired(bot)
    if hasExpired then return STATUS.SUCCESS end

    local wanderPos = bot.wander.targetPos
    local loco = bot:BotLocomotor()

    -- Give up on a destination the pathfinder cannot reach: off the navmesh, or across a gap this map does
    -- not connect. `cantReachGoal` is set by the locomotor and was read by nothing at all, so such a bot
    -- simply stood where it was - and with the destination-scaled deadline that can now be a minute and a
    -- half of standing. Failing makes the tree pick somewhere else on the next tick.
    if loco.cantReachGoal then
        -- ...and stay in the region it is actually standing in for a while, rather than rolling the dice on
        -- the far side of the map again and failing in exactly the same way.
        bot.wanderStayClose = CurTime() + 20
        return STATUS.FAILURE
    end

    loco:SetGoal(wanderPos)

    if loco:IsCloseEnough(wanderPos) then
        Wander.StareAtNearbyPlayers(bot, loco)
    end

    return STATUS.RUNNING
end

---Make the bot stare at the nearest player. Useful for when the bot is standing still.
---
--- Re-scan at most this often. `GetAllVisible` traces from every player on the server to the bot's position, and
--- this runs every tick a bot stands at its goal - so an every-tick answer is `players` traces per bot for a look
--- that only has to look natural. The chosen target is held between scans and re-issued each tick.
local STARE_INTERVAL = 1

---@param bot Bot
---@param locomotor CLocomotor
function Wander.StareAtNearbyPlayers(bot, locomotor)
    if (bot.wanderStareAt or 0) <= CurTime() then
        bot.wanderStareAt = CurTime() + STARE_INTERVAL
        bot.wanderStareTarget = lib.GetClosest(lib.GetAllVisible(bot:GetPos(), false), bot:GetPos())
    end

    local target = bot.wanderStareTarget
    if target and IsValid(target) then
        locomotor:LookAt(target:GetPos())
    end
end

--- Called when the behavior returns a success state
function Wander.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Wander.OnFailure(bot)
end

--- Called when the behavior ends
function Wander.OnEnd(bot)
    bot.wander = nil
end

function Wander.DestinationCloseEnough(bot)
    if not bot.wander then return true end
    local dest = bot.wander.targetPos
    local pos = bot:GetPos()
    local dist = pos:Distance(dest)
    return dist < 100
end

--- Called every tick, so this is also where progress is noticed: a bot that keeps setting a new closest
--- approach to its destination keeps its deadline, and one that is wedged against geometry runs out of it and
--- picks somewhere else.
function Wander.HasExpired(bot)
    local wander = bot.wander
    -- A wander with no destination at all (the navmesh gave us nothing) has nothing to wait for. This used to
    -- be an error, because the distance is read below.
    if not (wander and wander.targetPos) then return true end

    local ctime = CurTime()
    local dist = bot:GetPos():Distance(wander.targetPos)

    -- Progress, not the clock, is what should end a wander. The deadline used to be a flat 6-24 seconds
    -- whatever the distance, so on a large map it expired halfway through every trip: the bot dropped the
    -- goal, rolled a new one, and the map filled with bots who were always on their way and never arriving.
    if dist + PROGRESS_EPSILON < (wander.lastDist or math.huge) then
        wander.lastDist = dist
        wander.timeEndFar = math.max(wander.timeEndFar, ctime + PROGRESS_RENEW)
    end

    -- ...but never indefinitely: one destination must not own the whole round.
    if (ctime - (wander.timeStart or ctime)) > MAX_WANDER_TIME then return true end

    -- Arriving deserves its own short clock. The deadline above is sized to how long the walk there might
    -- take, so a bot that gets there early used to spend the remainder of that allowance standing still -
    -- on a long trip, minutes of it. Give the arrival its own allowance and a long walk stops also being a
    -- long stand.
    if dist < DIST_CLOSE_THRESH then
        wander.arrivedAt = wander.arrivedAt or ctime
        if (ctime - wander.arrivedAt) >= ARRIVED_LOITER then return true end
    else
        wander.arrivedAt = nil -- moving again: pushed off the goal, or chasing one that moved
    end

    local closeEnough = (ctime > wander.timeEndClose) and (dist < DIST_CLOSE_THRESH)

    return closeEnough or (wander.timeEndFar < ctime)
end

--- Returns a random nav area in the nearest region to the bot
function Wander.GetRandomNavInRegion(bot)
    if not (bot and bot.GetPos) then
        error("Unknown bot ent: " .. tostring(bot), 5)
        return nil
    end
    return lib.GetRandomNavInNearestRegion(bot:GetPos())
end

--- Gets a random nav area from the entire navmesh
function Wander.GetRandomNav()
    local areas = navmesh.GetAllNavAreas()
    if not areas or #areas == 0 then return nil end
    return table.Random(areas)
end

---Return if the role can see all C4s inherently, or if it must have someone spot it first
---@param bot Bot
---@return boolean
function Wander.BotCanSeeAllC4(bot)
    local role = TTTBots.Roles.GetRoleFor(bot)
    local canPlant = role:GetPlantsC4()

    return canPlant
end

--- Returns a random nav with preference to the current area
function Wander.GetAnyRandomNav(bot, level)
    level = level or 0
    -- 80% chance of getting a random nav in the nearest region, 20% chance of getting a random nav from the entire navmesh
    local area = (math.random(1, 5) <= 4 and Wander.GetRandomNavInRegion(bot)) or Wander.GetRandomNav()
    if not area then return nil end

    if level < 5 then
        -- Test if the area is near a known bomb
        local omniscient = Wander.BotCanSeeAllC4(bot)
        local bombs = (omniscient and TTTBots.Match.AllArmedC4s) or TTTBots.Match.SpottedC4s

        for bomb, _ in pairs(bombs) do
            if not IsValid(bomb) then continue end
            local bombPos = bomb:GetPos()
            local dist = bombPos:Distance(area:GetCenter())
            if dist < 1000 then
                return Wander.GetAnyRandomNav(bot, level + 1)
            end
        end
    end

    return area
end

--- A sniper perch close enough to be worth walking to, drawn from the perches that pass *both* spot tests:
--- they have open sightlines, and plenty of nearby nav areas cannot see them back. The plain
--- `GetNearestSpotOfCategory` answers with the nearest spot carrying the "sniper" label instead, which can be
--- a perch in the middle of an open room - a spot the bot can shoot from and everybody can shoot back at.
---
--- Returns nil when this map has no such perch inside `SNIPER_SEEK_RADIUS`, so the caller falls back to the
--- nearest-of-category answer and a map without perches behaves exactly as it did before.
---@param bot Bot
---@return Vector?
function Wander.GetSniperSpotNear(bot)
    local spots = TTTBots.Spots.GetBestSniperSpots()
    if #spots == 0 then return nil end

    local pos = bot:GetPos()
    local closest, closestDist = nil, math.huge
    -- Deliberately a full scan rather than a capped one: the list is not ordered by anything a bot cares
    -- about, so stopping early would sample an arbitrary subset instead of the nearest perches. It costs one
    -- distance test per perch, and only runs behind the same two rolls that gate every spot destination.
    for i = 1, #spots do
        local spot = spots[i]
        local dist = pos:Distance(spot)
        if dist <= SNIPER_SEEK_RADIUS and dist < closestDist then
            closest, closestDist = spot, dist
        end
    end

    return closest
end

---Finds a place to hide/snipe at. Returns if we found a spot and where it is (or nil)
---@param bot Bot
---@return boolean foundSpot
---@return Vector? pos pos or nil if we didn't find a spot
function Wander.FindSpotFor(bot)
    local personality = bot:BotPersonality()
    if not personality then return false, nil end

    local randomChance = math.random(1, 10) == 1

    local isHidingRole = TTTBots.Roles.GetRoleFor(bot):GetCanHide()
    local canHide = isHidingRole and (personality:GetTraitBool("hider") or randomChance)

    local isSnipingRole = TTTBots.Roles.GetRoleFor(bot):GetCanSnipe()
    local canSnipe = isSnipingRole and (personality:GetTraitBool("sniper") or randomChance)

    local randomChanceTrait = math.random(1, Wander.CHANCE_TO_HIDE_IF_TRAIT) == 1

    if (canHide or canSnipe) and randomChanceTrait then
        local kindStr = (canHide and "hiding") or "sniper"

        -- A perch is only worth walking to with something that can use the sightline. Nothing here used to look at
        -- the weapon at all, so a bot holding a pistol - or a shotgun, or a crowbar - would take a perch and stand
        -- on it, which from the outside is a bot "sniping" with a pistol. Without a long-range weapon it takes
        -- cover instead, and a role that is not allowed to want cover either goes nowhere and wanders normally.
        if kindStr == "sniper" and not lib.HoldsLongRangeWeapon(bot) then
            kindStr = isHidingRole and "hiding" or nil
        end

        if not kindStr then return false, nil end

        -- Hiding is left alone: a hiding spot is picked for what it hides, and the nearest one is already the
        -- right kind of answer. The sniper half is the one that has to be a good place to shoot from.
        local spot
        if kindStr == "sniper" then
            spot = Wander.GetSniperSpotNear(bot)
        end
        spot = spot or TTTBots.Spots.GetNearestSpotOfCategory(bot:GetPos(), kindStr)
        if spot then
            if Wander.Debug then
                printf("Bot %s wandering to a %s spot", bot:Nick(), kindStr)
            end
            return true, spot + Vector(0, 0, 64)
        end
    end
    return false, nil
end

--- The most popular nav area near the bot, or nil when there is nothing popular within reach. Popularity is
--- sorted, so the first area inside the radius is the best one there is; the scan is capped because a big map
--- has thousands of areas and this runs when a bot picks a destination, not every tick.
---@param bot Bot
---@return CNavArea?
function Wander.GetPopularAreaNear(bot)
    local popularNavs = TTTBots.Lib.PopularNavsSorted
    if #popularNavs == 0 then return nil end

    local pos = bot:GetPos()
    for rank = 1, math.min(#popularNavs, POPULAR_MAX_RANK) do
        local navTbl = popularNavs[rank]
        if not navTbl then break end

        local nav = navmesh.GetNavAreaByID(navTbl[1])
        if not nav then continue end
        if pos:Distance(nav:GetCenter()) > POPULAR_SEEK_RADIUS then continue end

        return nav
    end

    return nil
end

--- Whether the bot has gone a while without seeing anybody. Not knowing where anyone is, it is allowed to
--- know where people *have* been - that is what the popularity map is - so this is the honest way to send a
--- bot looking for the rest of a quiet round.
---@param bot Bot
---@return boolean
function Wander.LostContact(bot)
    local memory = bot:BotMemory()
    if not memory then return true end -- no memory yet means no contact to speak of

    return #memory:GetRecentlySeenPlayers(LOST_CONTACT_WINDOW) == 0
end

--- A popular area far enough away to be a trip rather than a shuffle, picked from the busiest few so that
--- several quiet bots do not all converge on one nav area at once. Returns nil when this map has nobody's
--- habits recorded yet, or when every popular area is right here.
---@param bot Bot
---@return CNavArea?
function Wander.GetDistantPopularArea(bot)
    local popularNavs = TTTBots.Lib.PopularNavsSorted
    if #popularNavs == 0 then return nil end

    local pos = bot:GetPos()
    local candidates = {}
    for rank = 1, math.min(#popularNavs, POPULAR_MAX_RANK) do
        local navTbl = popularNavs[rank]
        if not navTbl then break end

        local nav = navmesh.GetNavAreaByID(navTbl[1])
        if not nav then continue end
        if pos:Distance(nav:GetCenter()) < RELOCATE_MIN_DIST then continue end

        table.insert(candidates, nav)
        if #candidates >= RELOCATE_SPREAD then break end
    end

    return table.Random(candidates)
end

function Wander.UpdateWanderGoal(bot)
    local targetArea
    local targetPos
    -- `isSpot` is declared where the spot is actually found, further down. There used to be a second
    -- declaration up here that nothing ever read, and it shadowed the real one.
    local personality = bot:BotPersonality()
    if not personality then return end

    ---------------------------------------------
    -- relevant personality traits: loner, lovescrowds
    ---------------------------------------------
    local isLoner = personality:GetTraitBool("loner")
    local lovesCrowds = personality:GetTraitBool("lovesCrowds")
    local popularNavs = TTTBots.Lib.PopularNavsSorted
    local adhereToPersonality = (isLoner or lovesCrowds) and math.random(1, 5) <= 4
    if adhereToPersonality and #popularNavs > 10 then
        local topNNavs = {}
        local bottomNNavs = {}
        local N = 4

        for i = 1, N do
            if not popularNavs[i] then break end
            table.insert(topNNavs, popularNavs[i])
        end
        for i = #popularNavs - N, #popularNavs do
            if not popularNavs[i] then break end
            table.insert(bottomNNavs, popularNavs[i])
        end

        if lovesCrowds then
            targetArea = navmesh.GetNavAreaByID(table.Random(topNNavs)[1])
            if Wander.Debug then
                printf("Bot %s wandering to a popular area", bot:Nick())
            end
        else
            targetArea = navmesh.GetNavAreaByID(table.Random(bottomNNavs)[1])
            if Wander.Debug then
                printf("Bot %s wandering to an unpopular area", bot:Nick())
            end
        end
    end

    ---------------------------------------------
    -- relevant personality traits: hider, sniper
    -- everyone can hide or go to a sniper spot, but the above traits do it more
    ---------------------------------------------
    local isSpot, newPos = Wander.FindSpotFor(bot)
    if newPos then targetPos = newPos end

    if not targetArea then
        if (bot.wanderStayClose or 0) > CurTime() then
            -- We just failed to reach somewhere, so pick inside the region we are standing in.
            targetArea = Wander.GetRandomNavInRegion(bot) or Wander.GetAnyRandomNav(bot)
        elseif Wander.LostContact(bot) then
            -- Nobody has been seen for a while, so this is the quiet tail of a round and the region the bot
            -- is standing in is very likely empty. Head for one of the places people actually gather instead
            -- of another patch of nowhere - that is what lets the last bots of a round find each other.
            targetArea = Wander.GetDistantPopularArea(bot) or Wander.GetPopularAreaNear(bot) or
                Wander.GetAnyRandomNav(bot)
        else
            -- A random area used to be the only answer here, which on a big map is as likely to be the far
            -- corner as anywhere people go. Half the time the bot now heads for the busiest place it can
            -- reach instead, so bots meet each other because they are drifting towards the same few areas
            -- rather than because they know where each other are.
            targetArea = (math.random(1, 100) <= POPULAR_CHANCE and Wander.GetPopularAreaNear(bot)) or
                Wander.GetAnyRandomNav(bot)
        end
    end

    if targetArea and not targetPos then
        targetPos = targetArea:GetRandomPoint()
    elseif targetPos and not targetArea then
        targetArea = navmesh.GetNearestNavArea(targetPos)
    end

    local time = CurTime()
    local tripDist = targetPos and bot:GetPos():Distance(targetPos) or 0
    local tripTime = (tripDist / WALK_SPEED_ESTIMATE) * TRIP_TIME_SLACK + TRIP_TIME_GRACE

    local wanderTbl = {
        targetArea = targetArea,
        targetPos = targetPos,
        timeStart = time,
        -- The destination's own walking time, not a flat roll of the dice: a 4000 unit trip gets a deadline
        -- it can be finished inside, and a short one is not given a long one (see the constants at the top).
        timeEndFar = time +
            math.min(tripTime + math.random(4, 10), MAX_WANDER_TIME) * (isSpot and 1.5 or 1),
        timeEndClose = time + math.random(3, 12) * (isSpot and 1.5 or 1),
        lastDist = tripDist,
    }

    bot.wander = wanderTbl

    return wanderTbl
end
