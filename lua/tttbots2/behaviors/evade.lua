--[[
What a bot that cannot fight does while the post-round deathmatch runs: it hides.

The deathmatch hands every living bot a target once a second (see `BotMorality:SetDeathmatchTarget`), which is
what turns the post-round into a brawl - and that is the point of it. A bot whose role cannot fight, though, has
nothing to gain from the brawl. It walks into the open and shoots at people it cannot damage, or stands there
being shot at, until somebody ends it. This node takes those bots out of the fight and puts them somewhere out
of sight instead.

*Which* bots those are is one question with one answer, `TTTBots.Roles.IsNonCombatant`: the addon zeroes every
point of damage they deal (the Beggar, the Collusionist, the Cursed), or nobody can damage them (the Swapper,
which exists to be killed by somebody who then inherits its role), or they are a fool role whose whole purpose is
to be killed (the Jester and its neighbours on the jesters' team).

Three decisions worth knowing when reading a bot's behaviour:

  * **Deathmatch only, deliberately.** The rest of the round is where a fool's job *is* to be killed, and
    `roles/jester.lua` keeps picking fights for exactly that reason. Only after the round is over - when there is
    no role left to play and no win condition to serve - does "cannot fight" turn into "must not fight".
  * **It wins the tree, not the target producers.** It is the first node of the shared `Survive` group, which
    every tree this can matter to puts at its head, so a bot running it never reaches `AttackTarget`, `Stalk` or
    `MingeCrowbar` even if something handed it a target a tick ago. `SetDeathmatchTarget` also refuses to give a
    non-combatant a target at all - both halves are wanted, because the morality path is once a second and the
    tree path is every tick.
  * **Hiding means a spot from the spot system**, chosen so that no living player can see it and as far as
    possible from whoever is nearest, and re-chosen when somebody does see the bot rather than standing in the
    open. The candidate spots are *sampled* rather than scanned: the hiding category can hold thousands of
    positions, this runs for as long as the deathmatch lasts, and out of sight and far away is not worth an
    exhaustive search.
]]

TTTBots.Behaviors.Evade = {}

local lib = TTTBots.Lib

local Evade = TTTBots.Behaviors.Evade
Evade.Name = "Evade"
Evade.Description = "Hide from everybody while the post-round deathmatch runs"
Evade.Interruptible = true

local STATUS = TTTBots.STATUS

--- How far from the bot a hiding spot may be.
local MAX_SPOT_DIST = 3000
--- How many hiding spots to sample per pick.
local SPOT_SAMPLES = 12
--- How close to the spot counts as arrived.
local ARRIVED_DIST = 64
--- A player this close, in sight, sends the bot looking for somewhere else.
local TOO_CLOSE_DIST = 500
--- Do not re-pick more often than this, however the bot was seen.
local REPICK_INTERVAL = 2

--- Every living player other than the bot.
---@param bot Bot
---@return table<Player>
local function getOthers(bot)
    local others = {}

    for _, other in ipairs(TTTBots.Match.AlivePlayers) do
        if other ~= bot and lib.IsPlayerAlive(other) then
            others[#others + 1] = other
        end
    end

    return others
end

--- Can any of these players see that position?
---
--- `TTTBots.Lib.CanSeeArc` with a full arc is this framework's position-based visibility test: the arc half of it
--- cannot fail at 360 degrees, and what is left is `Player:VisibleVec(pos)`. `Player:Visible` is *not* usable
--- here - it takes an entity, and a hiding spot is a position - which is what the first version of this file got
--- wrong: it threw "bad argument #1 to 'Visible' (Entity expected, got userdata)" once a tick for every bot
--- running it (section 38).
---
--- The probe is aimed a body's height above the spot. A nav position sits *on* the floor, and a trace to it ends
--- in the floor it is standing on, which reads as blocked by anything: the same reason the morality component
--- aims at `+24` when it asks whether a bot can see somebody.
---@param pos Vector
---@param others table<Player>
---@return boolean
local function isSeen(pos, others)
    local probe = pos + Vector(0, 0, 24)

    for _, other in ipairs(others) do
        if TTTBots.Lib.CanSeeArc(other, probe, 360) then return true end
    end

    return false
end

--- How far the nearest of these players is from that position.
---@param pos Vector
---@param others table<Player>
---@return number
local function nearestDist(pos, others)
    local nearest = math.huge

    for _, other in ipairs(others) do
        local dist = other:GetPos():Distance(pos)
        if dist < nearest then nearest = dist end
    end

    return nearest
end

--- Sample hiding spots and keep the best one: out of everybody's sight, and as far from the nearest player as
--- the samples allow.
---@param bot Bot
---@param others table<Player>
---@return Vector?
local function pickSpot(bot, others)
    local cache = TTTBots.Spots.CachedSpots
    if not (cache and cache["hiding"]) then return nil end

    local spots = TTTBots.Spots.GetSpotsInCategory("hiding")
    local count = #spots
    if count == 0 then return nil end

    local myPos = bot:GetPos()
    local best, bestScore = nil, nil

    for _ = 1, math.min(SPOT_SAMPLES, count) do
        local spot = spots[math.random(1, count)]
        if spot:Distance(myPos) > MAX_SPOT_DIST then continue end
        if isSeen(spot, others) then continue end

        local score = nearestDist(spot, others)
        if not bestScore or score > bestScore then
            best, bestScore = spot, score
        end
    end

    return best
end

---@param bot Bot
---@return boolean
function Evade.Validate(bot)
    if not TTTBots.Match.IsDeathmatchActive() then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not TTTBots.Roles.IsNonCombatant(bot) then return false end

    -- Nothing to hide from, and nowhere to hide: both leave the bot to the rest of its tree rather than
    -- standing it still in the open.
    if #getOthers(bot) == 0 then return false end

    return TTTBots.Spots.CachedSpots and TTTBots.Spots.CachedSpots["hiding"] ~= nil
end

---@param bot Bot
function Evade.OnStart(bot)
    bot.evadeNextPick = 0
    bot.evadeSpot = nil

    return STATUS.RUNNING
end

---@param bot Bot
---@return integer
function Evade.OnRunning(bot)
    -- The deathmatch is over, we died, or our role changed under us (the Beggar gunned somebody down and picked
    -- their weapon up): whatever the reason, this is no longer what the bot should be doing.
    if not TTTBots.Match.IsDeathmatchActive() then return STATUS.SUCCESS end
    if not lib.IsPlayerAlive(bot) then return STATUS.SUCCESS end
    if not TTTBots.Roles.IsNonCombatant(bot) then return STATUS.SUCCESS end

    local loco = bot:BotLocomotor()
    local others = getOthers(bot)
    if #others == 0 then return STATUS.SUCCESS end

    -- Never shoot, whatever a node before us left behind: this bot cannot hurt anybody.
    loco:StopAttack()

    local now = CurTime()
    local spot = bot.evadeSpot
    local nearest = nearestDist(bot:GetPos(), others)
    local seenNow = nearest < TOO_CLOSE_DIST and isSeen(bot:GetPos(), others)

    -- Re-pick when we have nowhere to go, when we have been seen this close, or when somebody is standing
    -- almost on top of the spot we chose - but never more often than REPICK_INTERVAL, because sampling spots
    -- means line-of-sight traces and this runs every tick.
    local needsPick = (spot == nil) or seenNow or (spot and nearestDist(spot, others) < TOO_CLOSE_DIST)

    if needsPick and now >= (bot.evadeNextPick or 0) then
        bot.evadeSpot = pickSpot(bot, others)
        bot.evadeNextPick = now + REPICK_INTERVAL
        spot = bot.evadeSpot
    end

    if not spot then
        -- Nowhere is hidden from whoever is alive. Standing still is still better than walking at them, which
        -- is what the rest of this bot's tree would do.
        loco:ClearGoal()
        loco:SetSprint(false)

        return STATUS.RUNNING
    end

    if bot:GetPos():Distance(spot) <= ARRIVED_DIST then
        loco:ClearGoal()
        loco:SetSprint(false)

        return STATUS.RUNNING
    end

    loco:SetSprint(true)
    loco:SetGoal(spot)

    return STATUS.RUNNING
end

---@param bot Bot
function Evade.OnEnd(bot)
    local loco = bot:BotLocomotor()

    loco:StopAttack()
    loco:ClearGoal()
    loco:SetSprint(false)

    bot.evadeSpot = nil
    bot.evadeNextPick = nil
end
