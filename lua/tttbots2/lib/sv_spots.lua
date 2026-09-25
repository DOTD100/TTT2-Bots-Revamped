TTTBots.Spots = {}

--- Go to through all of the spots on the navmesh and categorize them ourselves.
---@return table<Vector>
function TTTBots.Spots.CacheAllSpots()
    TTTBots.Spots.CachedSpots = {
        ["all"] = {},
    }
    -- The categories are rebuilt from scratch below, so anything derived from them has to go too.
    TTTBots.Spots.CachedBestSniperSpots = nil
    local allNavs = navmesh.GetAllNavAreas()
    for i, v in pairs(allNavs) do
        local exposedSpots = v:GetExposedSpots()
        local hidingSpots = v:GetHidingSpots()
        for i, v in pairs(exposedSpots) do
            table.insert(TTTBots.Spots.CachedSpots["all"], v)
        end
        for i, v in pairs(hidingSpots) do
            table.insert(TTTBots.Spots.CachedSpots["all"], v)
        end
    end
    TTTBots.Spots.CacheSpecialSpots()

    return TTTBots.Spots.CachedSpots["all"]
end

function TTTBots.Spots.GetAllSpots()
    return TTTBots.Spots.CachedSpots["all"]
end

--- Return the nearest spot of a given category to pos. Also returns the distance to that spot.
---@param pos Vector
---@param category string
---@return Vector|nil, number
function TTTBots.Spots.GetNearestSpotOfCategory(pos, category)
    local spots = TTTBots.Spots.GetSpotsInCategory(category)
    local nearestSpot = nil
    local nearestDist = math.huge
    for i, spot in pairs(spots) do
        local dist = spot:Distance(pos)
        if dist < nearestDist then
            nearestDist = dist
            nearestSpot = spot
        end
    end
    return nearestSpot, nearestDist
end

function TTTBots.Spots.RegisterSpotCategory(title, spotValidCallback)
    TTTBots.Spots.CachedSpots[title] = {}
    TTTBots.Spots.CachedSpots[title].IsValid = spotValidCallback
    TTTBots.Spots.CachedSpots[title].Spots = {}

    local spotsToFilter = TTTBots.Spots.GetAllSpots()
    for i, spot in pairs(spotsToFilter) do
        if spotValidCallback(spot) then
            table.insert(TTTBots.Spots.CachedSpots[title].Spots, spot)
        end
    end

    print(string.format("[TTT Bots 2] Registered spot category '%s' with %d spots.", title,
        #TTTBots.Spots.CachedSpots[title].Spots))
end

function TTTBots.Spots.GetSpotsInCategory(title)
    return TTTBots.Spots.CachedSpots[title].Spots
end

--- Measure the visibility around the spot by tracing some lines in a circle around it, and return the average percentage of visibility.
function TTTBots.Spots.MeasureSpotVisibility(vec, radius)
    local total = 0
    local count = 0
    local offset = Vector(0, 0, 32)
    local angles = TTTBots.Lib.GetAngleTable(16)
    for i, angle in pairs(angles) do
        local x = math.cos(math.rad(angle)) * radius
        local y = math.sin(math.rad(angle)) * radius
        local trace = TTTBots.Lib.TracePercent(vec + offset, vec + Vector(x, y, 0) + offset)
        total = total + trace
        count = count + 1
    end
    return total / count
end

function TTTBots.Spots.CacheSpecialSpots()
    local SNIPER_MIN_TO_BE_CONSIDERED = 5
    local SniperExclusionaryFunc = function(spot)
        local visibleNavs = 0
        local myNav = navmesh.GetNearestNavArea(spot)
        if not myNav then return false end
        local navsICanSee = myNav:GetVisibleAreas()
        for i, nav in pairs(navsICanSee) do
            if not nav:IsPartiallyVisible(spot) then -- If we can see them, but they can't see us (this is for exclusionary)
                visibleNavs = visibleNavs + 1
            end
        end
        return visibleNavs >= SNIPER_MIN_TO_BE_CONSIDERED
    end

    local HIDING_MAX_VIS_PCT = 41
    local HidingFunc = function(spot)
        local visibAvg = TTTBots.Spots.MeasureSpotVisibility(spot, 256)

        return visibAvg <= HIDING_MAX_VIS_PCT
    end

    local SNIPER_MIN_VIS_PCT = 60
    local SniperFunc = function(spot)
        local visibAvg = TTTBots.Spots.MeasureSpotVisibility(spot, 512)

        return visibAvg >= SNIPER_MIN_VIS_PCT
    end

    local BOMB_MAX_VIS_PCT = 41
    local BombFunc = function(spot)
        local visibAvg = TTTBots.Spots.MeasureSpotVisibility(spot, 256)

        return visibAvg <= BOMB_MAX_VIS_PCT
    end

    TTTBots.Spots.RegisterSpotCategory("sniperExclusionary", SniperExclusionaryFunc)
    TTTBots.Spots.RegisterSpotCategory("hiding", HidingFunc)
    TTTBots.Spots.RegisterSpotCategory("sniper", SniperFunc)
    TTTBots.Spots.RegisterSpotCategory("bomb", BombFunc)
end

--- The sniper spots actually worth using: the ones with open sightlines (the "sniper" category) that
--- also have plenty of nearby nav areas which cannot see them (the "sniperExclusionary" category). A
--- spot that passes only the first test is a perch in the middle of an open room - the bot can shoot
--- from it, but everyone can shoot back.
---
--- Cached, because it is walked once per map and the answer only changes when the spot cache is rebuilt.
---@return table<Vector>
function TTTBots.Spots.GetBestSniperSpots()
    if TTTBots.Spots.CachedBestSniperSpots then return TTTBots.Spots.CachedBestSniperSpots end
    if not TTTBots.Spots.CachedSpots then return {} end -- asked before the spots were ever cached

    local sniperSpots = TTTBots.Spots.GetSpotsInCategory("sniper")
    local exclusionarySpots = TTTBots.Spots.GetSpotsInCategory("sniperExclusionary")

    -- Both categories are filtered from the same list, so a spot that passes both is the same Vector in
    -- each of them, and can simply be looked up by identity.
    local covered = {}
    for i, spot in ipairs(exclusionarySpots) do
        covered[spot] = true
    end

    local best = {}
    for i, spot in ipairs(sniperSpots) do
        if covered[spot] then
            table.insert(best, spot)
        end
    end

    -- Some maps have no spot satisfying both halves. Falling back to every sniper spot beats handing the
    -- caller an empty list it cannot tell apart from "this map has no sniper spots at all".
    if #best == 0 then
        best = sniperSpots
    end

    TTTBots.Spots.CachedBestSniperSpots = best

    return best
end
