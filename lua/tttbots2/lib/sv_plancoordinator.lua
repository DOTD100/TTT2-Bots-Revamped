--[[
    This module is primarily for coordinating traitor bots with one another.
]]
include("tttbots2/lib/sv_plans.lua")

TTTBots.PlanCoordinator = {}
local PlanCoordinator = TTTBots.PlanCoordinator
local Plans = TTTBots.Plans
local ACTIONS = Plans.ACTIONS
local PLANSTATES = Plans.PLANSTATES
local TARGETS = Plans.PLANTARGETS

local IsRoundActive = TTTBots.Match.IsRoundActive --- @type function

--- How many of the busiest places to try in turn when looking for a perch that overlooks one of them, and how
--- close that perch has to be to count as overlooking it. A job assignment is not a hot path, but the map is
--- large, so the anchor list is short and the scan per anchor is over the perch list rather than the navmesh.
local PERCH_ANCHOR_COUNT = 10
local PERCH_ANCHOR_RADIUS = 2000

--- How many of the busiest (or quietest) areas a "go where people are" job chooses between.
---
--- `GetTopNPopularNavs(1)` is one answer for the whole server, and several bots can hold the same job - TestJob
--- allows up to `MaxAssigned` of them - so a plan that sends bots to the popular place handed every one of them
--- the identical nav area and they walked there in single file. Same spread as behaviors/wander.lua.
local AREA_TARGET_SPREAD = 6

--- A random point in one of the given ranked nav areas, or nil when none of them resolve.
---@param navTbls table<table<number, number>> the result of GetTopNPopularNavs / GetTopNUnpopularNavs
---@return Vector?
local function randomPointInRankedAreas(navTbls)
    local areas = {}
    for i = 1, #navTbls do
        local nav = navmesh.GetNavAreaByID(navTbls[i][1])
        if nav then areas[#areas + 1] = nav end
    end

    if #areas == 0 then return nil end

    local area = table.Random(areas)
    return area and area:GetRandomPoint() or nil
end

-- hook.Add("TTTBeginRound", "TTTBots.PlanCoordinator.OnRoundStart", PlanCoordinator.OnRoundStart)
-- hook.Add("TTTEndRound", "TTTBots.PlanCoordinator.OnRoundEnd", PlanCoordinator.OnRoundEnd)

--- NOTE: due to how this function works, job chances are calculated PER assignment; it is possible to assign 1 bot when the max is 2 if the chance < 100%
function PlanCoordinator.TestJob(job, shouldModify, bot)
    local conditions = job.Conditions
    if job.Skip then return false end
    local jobValid = TTTBots.Plans.AreConditionsValid(job)
    job.Skip = not jobValid
    if not jobValid then return false end

    local nAssigned = job.NumAssigned or 0
    local maxAssigned = job.MaxAssigned or 99

    if nAssigned >= maxAssigned then
        job.Skip = true
        return false
    end

    job.AssignedBots = job.AssignedBots or {}

    if (not job.Repeat) and job.AssignedBots[bot] then -- Do not repeat a job that has already been assigned to this bot
        return false
    end

    if shouldModify then
        job.NumAssigned = nAssigned + 1
        job.AssignedBots[bot] = true
    end

    return true
end

--- The actions that hand a bot a victim, rather than a place to be or somebody to walk next to.
---
--- These are the only jobs the kill-delay gate below holds back. Gathering, following somebody peacefully,
--- planting and taking an angle are all things a traitor can usefully do in the opening seconds of a round, so
--- this is a skip rather than a blanket "no plans yet".
---@type table<string, boolean>
local ATTACK_ACTIONS = {
    [ACTIONS.ATTACK] = true,
    [ACTIONS.ATTACKANY] = true,
}

--- Returns the next unassigned job in the assigned Plan's sequence.
---@param isAssignment boolean|nil if this is being used to assign a job. default to false. if true then removes a/the job from stack
---@param caller Player|nil the player who is calling this function. used for calculating targets if isAssignment is true. otherwise optional
function PlanCoordinator.GetNextJob(isAssignment, caller)
    if not IsRoundActive() then return nil end
    local selectedPlan = Plans.SelectedPlan
    if not selectedPlan then return nil end
    local jobs = selectedPlan.Jobs
    local assignedJob = { -- default job
        Action = ACTIONS.ATTACKANY,
        Target = TARGETS.NEAREST_ENEMY,
    }
    -- Nobody is handed a victim before the round - and the bot's own life - have been running for
    -- `ttt_bot_attack_delay` seconds (Match.KillDelayElapsed). The *fallback* below was the real hole here: it
    -- is an attack order aimed at the nearest non-ally's live position, so a traitor whose plan offered nothing
    -- better spent the opening seconds walking at somebody it should not have known about yet. Attack jobs are
    -- skipped rather than failing, so they keep their chances and the rest of the plan still runs.
    local mayAttack = TTTBots.Match.KillDelayElapsed(caller)

    for i, job in pairs(jobs) do
        if not mayAttack and ATTACK_ACTIONS[job.Action] then continue end

        local test = PlanCoordinator.TestJob(job, isAssignment, caller)
        if test then
            assignedJob = table.Copy(job) -- create a deep copy of the job
            break
        end
    end

    -- The default job is an attack order too, so a bot with nothing else to do patrols instead of hunting.
    if not mayAttack and ATTACK_ACTIONS[assignedJob.Action] then return nil end

    if isAssignment then
        assignedJob = PlanCoordinator.CalculateTargetForJob(assignedJob, caller)
        local timeNow = CurTime()
        assignedJob.TimeAssigned = timeNow
        assignedJob.ExpiryTime = timeNow + math.random((assignedJob.MinDuration or 15), (assignedJob.MaxDuration or 60))
    end
    return assignedJob
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcBombSpot(caller)
    local coverSpots = TTTBots.Spots.GetSpotsInCategory("hiding")
    local getWitnesses = TTTBots.Lib.GetAllWitnessesBasic

    for i, spot in pairs(coverSpots) do
        local witnesses = getWitnesses(spot, TTTBots.Match.AlivePlayers, caller) -- get all living witnesses to spot except caller
        if #witnesses == 0 then
            return spot
        end
    end

    return nil
end

--- A Target Hashtable function to calculate a target for a job. One of the busiest few places rather than the
--- single busiest: the ranking is still respected, but two bots given the same job no longer stand on each other.
---@param caller Player
function PlanCoordinator.CalcPopularArea(caller)
    return randomPointInRankedAreas(TTTBots.Lib.GetTopNPopularNavs(AREA_TARGET_SPREAD)) or
        PlanCoordinator.CalcRandFriendly(caller)
end

--- A Target Hashtable function to calculate a target for a job. The quiet counterpart, spread the same way.
---@param caller Player
function PlanCoordinator.CalcUnpopularArea(caller)
    return randomPointInRankedAreas(TTTBots.Lib.GetTopNUnpopularNavs(AREA_TARGET_SPREAD)) or
        PlanCoordinator.CalcRandFriendly(caller)
end

local function getClosestVec(origin, vecs)
    local closestVec = nil
    local closestDist = 0
    for i, vec in pairs(vecs) do
        local dist = vec:Distance(origin)
        if not closestVec or dist < closestDist then
            closestVec = vec
            closestDist = dist
        end
    end
    return closestVec, closestDist
end

local function getFarthestVec(origin, vecs)
    local farthestVec = nil
    local farthestDist = 0
    for i, vec in pairs(vecs) do
        local dist = vec:Distance(origin)
        if not farthestVec or dist > farthestDist then
            farthestVec = vec
            farthestDist = dist
        end
    end
    return farthestVec, farthestDist
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcFarthestHidingSpot(caller)
    local spots = TTTBots.Spots.GetSpotsInCategory("hiding")
    local callerPos = caller:GetPos()
    local farthestSpot, farthestDist = getFarthestVec(callerPos, spots)

    return farthestSpot
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcFarthestSniperSpot(caller)
    local spots = TTTBots.Spots.GetBestSniperSpots()
    local callerPos = caller:GetPos()
    local farthestSpot, farthestDist = getFarthestVec(callerPos, spots)

    return farthestSpot
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcNearestEnemy(caller)
    local closestInnocent = nil --TTTBots.Lib.GetClosest(TTTBots.Match.AliveNonEvil, caller:GetPos())
    local closestDist = math.huge

    for i, v in pairs(TTTBots.Match.AlivePlayers) do
        if v == caller then continue end
        if not TTTBots.Lib.IsPlayerAlive(v) then continue end
        if TTTBots.Roles.IsAllies(caller, v) then continue end
        local dist = v:GetPos():Distance(caller:GetPos())
        if dist < closestDist then
            closestInnocent = v
            closestDist = dist
        end
    end

    return closestInnocent
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcNearestHidingSpot(caller)
    local spots = TTTBots.Spots.GetSpotsInCategory("hiding")
    local callerPos = caller:GetPos()
    local closestSpot, closestDist = getClosestVec(callerPos, spots)

    return closestSpot
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcNearestSnipeSpot(caller)
    local spots = TTTBots.Spots.GetBestSniperSpots()
    local callerPos = caller:GetPos()
    local closestSpot, closestDist = getClosestVec(callerPos, spots)

    return closestSpot
end

--- A sniper perch that overlooks somewhere the round actually goes.
---
--- The perch lists on their own are only half an answer: "a good angle" means nothing by itself, because a
--- perch nobody walks past is just a room, and a bot sent to the nearest one may be holding an angle on
--- nowhere. This anchors the choice to the popularity map - the addon's own running count of where players
--- stand (sv_popularnavs.lua) - by taking the nearest perch to the busiest place, working down the ranking
--- until one resolves. The bot walks to an angle on the part of the map that keeps being used instead.
---
--- Distances are straight-line, so this deliberately does *not* ask for the farthest perch: on a big map the
--- farthest one is the most likely to have no route to it at all, and a DEFEND job has no path-failure
--- recovery of its own (see behaviors/followplan.lua) - it would spend its whole duration walking into
--- geometry. Proximity is also what makes the perch reachable in seconds rather than in half a round.
---@param caller Player
---@return Vector?
function PlanCoordinator.CalcPopularSniperSpot(caller)
    -- The other way a bot ends up on a perch is Wander.FindSpotFor, and both now ask this first: a bot with
    -- nothing that can use a long sightline has no business holding an angle. Returning nil fails the job on the
    -- spot, which is exactly what the DEFEND guard in behaviors/followplan.lua is for, so the bot picks up the
    -- next job in the plan instead of standing on a perch with a pistol.
    if not TTTBots.Lib.HoldsLongRangeWeapon(caller) then return nil end

    local perches = TTTBots.Spots.GetBestSniperSpots()
    if #perches == 0 then return PlanCoordinator.CalcNearestSnipeSpot(caller) end

    local popularNavs = TTTBots.Lib.GetTopNPopularNavs(PERCH_ANCHOR_COUNT)
    for rank = 1, #popularNavs do
        local navTbl = popularNavs[rank]
        if not navTbl then break end

        local area = navmesh.GetNavAreaByID(navTbl[1])
        if not area then continue end

        local perch, dist = getClosestVec(area:GetCenter(), perches)
        if perch and dist <= PERCH_ANCHOR_RADIUS then
            return perch
        end
    end

    -- Either the popularity map has nothing in it yet (the first seconds of a fresh map) or every busy place on
    -- this map is further from a perch than the radius allows. A nearby angle still beats no angle at all.
    return PlanCoordinator.CalcNearestSnipeSpot(caller)
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcRandEnemy(caller)
    local nonAllies = TTTBots.Lib.FilterTable(TTTBots.Match.AlivePlayers,
        function(ply) return not TTTBots.Roles.IsAllies(caller, ply) end)
    if #nonAllies == 0 then return nil end

    return table.Random(nonAllies)
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcRandFriendly(caller)
    local allies = TTTBots.Lib.FilterTable(TTTBots.Match.AlivePlayers,
        function(ply) return TTTBots.Roles.IsAllies(caller, ply) end)
    if #allies == 0 then return nil end

    return table.Random(allies)
end

--- Is another bot already shadowing this player?
---
--- The claim is another bot's live job rather than a table kept here, so it lapses by itself when that job ends
--- or the bot dies - nothing to clean up. It matters because `RAND_FRIENDLY_HUMAN` on a server with a single
--- human traitor - the normal case - resolved to that one person for every bot while the job's `MaxAssigned` of
--- 99 let the whole team take it, so the entire team announced and then followed the same player in single file.
---@param caller Player
---@param ply Player
---@return boolean
local function isBeingFollowed(caller, ply)
    for _, bot in ipairs(TTTBots.Bots) do
        if bot == caller then continue end
        if not TTTBots.Lib.IsPlayerAlive(bot) then continue end

        local job = bot.Job
        if not (job and job.Action == ACTIONS.FOLLOW) then continue end
        if job.TargetObj == ply then return true end
    end

    return false
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcRandFriendlyHuman(caller)
    local alliesHuman = TTTBots.Lib.FilterTable(TTTBots.Match.AlivePlayers, function(ply)
        return TTTBots.Roles.IsAllies(caller, ply) and not ply:IsBot()
    end)
    if #alliesHuman == 0 then return PlanCoordinator.CalcRandFriendly(caller) end

    -- Somebody nobody is already shadowing, when there is one. Falling back to the full list keeps the job
    -- working on a server with one human traitor: the follower is then a duplicate rather than a no-op.
    local unshadowed = TTTBots.Lib.FilterTable(alliesHuman, function(ply)
        return not isBeingFollowed(caller, ply)
    end)

    return table.Random(#unshadowed > 0 and unshadowed or alliesHuman)
end

--- A Target Hashtable function to calculate a target for a job.
function PlanCoordinator.CalcRandPolice(caller)
    local police = TTTBots.Lib.FilterTable(TTTBots.Match.AlivePlayers,
        function(ply) return ply:GetRoleStringRaw() == "detective" end)
    if #police == 0 then return nil end

    local unshadowed = TTTBots.Lib.FilterTable(police, function(ply)
        return not isBeingFollowed(caller, ply)
    end)

    return table.Random(#unshadowed > 0 and unshadowed or police)
end

local P = PlanCoordinator
local targetHashTable = {
    [TARGETS.ANY_BOMBSPOT] = P.CalcBombSpot,
    [TARGETS.FARTHEST_HIDINGSPOT] = P.CalcFarthestHidingSpot,
    [TARGETS.FARTHEST_SNIPERSPOT] = P.CalcFarthestSniperSpot,
    [TARGETS.NEAREST_ENEMY] = P.CalcNearestEnemy,
    [TARGETS.NEAREST_HIDINGSPOT] = P.CalcNearestHidingSpot,
    [TARGETS.NEAREST_SNIPERSPOT] = P.CalcNearestSnipeSpot,
    [TARGETS.POPULAR_SNIPERSPOT] = P.CalcPopularSniperSpot,
    [TARGETS.NOT_APPLICABLE] = function() return nil end,
    [TARGETS.RAND_ENEMY] = P.CalcRandEnemy,
    [TARGETS.RAND_FRIENDLY] = P.CalcRandFriendly,
    [TARGETS.RAND_FRIENDLY_HUMAN] = P.CalcRandFriendlyHuman,
    [TARGETS.RAND_POLICE] = P.CalcRandPolice,
    [TARGETS.RAND_POPULAR_AREA] = P.CalcPopularArea,
    [TARGETS.RAND_UNPOPULAR_AREA] = P.CalcUnpopularArea,
}

--- Calculates the target for a job, based upon the job's Target string.
---@param job table
---@return table Job the job, with the TargetObj field set. The TargetObj can also be retrieved with the second return value.
---@return Player|Vector|nil TargetObj the target object, depending on the target type.
function PlanCoordinator.CalculateTargetForJob(job, caller)
    local target = job.Target
    local targetFunc = targetHashTable[target]
    if not targetFunc then
        ErrorNoHaltWithStack("TargetFunc is not a real Target: " .. tostring(target) .. "\n")
        job.TargetObj = nil
        return job, nil
    end

    job.TargetObj = targetFunc(caller)
    return job, job.TargetObj
end

function PlanCoordinator.Tick()
    Plans.Tick()
end
