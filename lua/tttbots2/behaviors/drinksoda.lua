--[[
Drinks a Super Soda can (TTT-2/ttt2-super-soda) that the bot has found.

The addon hands its cans out through a server-side `KeyPress` hook - press +use while looking at the can -
and a bot never sends input, so that hook can never fire for one. Its own entry point has to be called
instead: `SUPERSODA:PickupSoda`. That is the addon's intended API rather than a shortcut around it - it does
every check that matters itself (100 units, the per-player limit convar, single-use cans, `CanPickupWeapon`)
and removes the can when it succeeds - so this behavior only has to choose a can and walk the bot to it.

Which can is worth the trip is sorted by what the bot actually needs: a hurt bot drinks health first, a
healthy one takes armour or a combat buff, and a full-health bot does not cross the map for a heal can.
Cans replace the map's own item spawns, so they are always somewhere the bot can path to.

Inert without the addon: everything is behind `SUPERSODA` existing.
]]

TTTBots.Behaviors.DrinkSoda = {}

local lib = TTTBots.Lib

local DrinkSoda = TTTBots.Behaviors.DrinkSoda
DrinkSoda.Name = "Drink Soda"
DrinkSoda.Description = "Drink a Super Soda can"
DrinkSoda.Interruptible = true

local STATUS = TTTBots.STATUS

---@class Bot
---@field sodaTarget Entity?
---@field sodaCooldown number?

local SEARCH_RADIUS = 2500
local DRINK_RANGE = 70 -- the addon itself refuses past 100 units
local COOLDOWN = 4 -- keeps a bot from emptying three cans into itself in one second

--- Priority of each can for a bot with nothing wrong with it; the lowest is drunk first.
local BASE_PRIORITY = {
    soda_healup = 1,
    soda_armorup = 2,
    soda_shootup = 3,
    soda_speedup = 4,
    soda_jumpup = 5,
    soda_rageup = 6,
    soda_creditup = 7,
}

---@return boolean
function DrinkSoda.IsAvailable()
    return SUPERSODA ~= nil and type(SUPERSODA.PickupSoda) == "function"
end

--- The addon's own per-player limit, when the server enabled it.
---@param bot Bot
---@return boolean
function DrinkSoda.CanDrinkAny(bot)
    local limit = GetConVar("ttt_soda_limit_one_per_player")
    if not (limit and limit:GetBool()) then return true end
    if not bot.SodaAmountDrunk then return true end

    return bot:SodaAmountDrunk() < 1
end

---@param bot Bot
---@param can Entity
---@return number
function DrinkSoda.GetPriority(bot, can)
    local hurt = (bot:Health() + 1) < bot:GetMaxHealth()
    if hurt and can:GetClass() == "soda_healup" then return 0 end

    return BASE_PRIORITY[can:GetClass()] or 99
end

--- The cans in the world, refreshed at most once a second.
---
--- `FindCan` runs from `Validate`, which is every tick for every bot, and `ents.FindByClass` builds a fresh list
--- on every call - so the whole world was rescanned per bot per tick for a set that only changes when somebody
--- drinks a can. A second of staleness costs nothing (a can that has just been taken is filtered by the
--- `IsValid` check in the loop below), and every bot shares the one list.
local canCache, canCacheAt = nil, 0
local CAN_CACHE_TIME = 1

---@return table<Entity>
local function getCans()
    local now = CurTime()
    if not canCache or (now - canCacheAt) >= CAN_CACHE_TIME then
        canCache, canCacheAt = ents.FindByClass("soda_*"), now
    end

    return canCache
end

--- The can worth walking to, or nil. Cheapest trip wins unless something is more urgent, which is what the
--- priority multiplied by the search radius does: a lower priority always beats any distance.
---@param bot Bot
---@return Entity?
function DrinkSoda.FindCan(bot)
    local myPos = bot:GetPos()
    local best, bestScore = nil, nil

    for _, can in pairs(getCans()) do
        if not IsValid(can) then continue end
        -- A single-use can the bot has already had does nothing but make it stand there.
        if can.soda_type == "SINGLEUSE" and bot.HasDrunkSoda and bot:HasDrunkSoda(can:GetClass()) then continue end
        if bot.CanPickupWeapon and not bot:CanPickupWeapon(can, true) then continue end

        local dist = myPos:Distance(can:GetPos())
        if dist > SEARCH_RADIUS then continue end

        local score = DrinkSoda.GetPriority(bot, can) * SEARCH_RADIUS + dist
        if not bestScore or score < bestScore then
            best, bestScore = can, score
        end
    end

    return best
end

---@param bot Bot
---@return boolean
function DrinkSoda.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_soda") then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not DrinkSoda.IsAvailable() then return false end
    if (bot.sodaCooldown or 0) > CurTime() then return false end

    -- A fight comes first: a bot standing still to drink is a bot not shooting.
    if bot.attackTarget ~= nil then return false end
    if not DrinkSoda.CanDrinkAny(bot) then return false end

    local can = DrinkSoda.FindCan(bot)
    if not IsValid(can) then return false end

    bot.sodaTarget = can
    return true
end

---@param bot Bot
---@return BStatus
function DrinkSoda.OnStart(bot)
    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function DrinkSoda.OnRunning(bot)
    local loco = bot:BotLocomotor()
    local can = bot.sodaTarget

    if not (IsValid(can) and DrinkSoda.IsAvailable() and DrinkSoda.CanDrinkAny(bot)) then
        return STATUS.FAILURE
    end

    loco:SetGoal(can:GetPos())
    loco:LookAt(can:GetPos())

    if bot:GetPos():Distance(can:GetPos()) > DRINK_RANGE then
        return STATUS.RUNNING
    end

    -- Reaching the can is the whole trip: a bot cannot press +use at anything, so the addon's own pickup
    -- is called with the bot as the drinker.
    --
    -- The spot is worth remembering: placefakesoda.lua drops a decoy can exactly where this one was, which
    -- is the one place a player has just been reminded that a can lives.
    bot.sodaDrankPos = can:GetPos()
    bot.sodaDrankAt = CurTime()

    SUPERSODA:PickupSoda(bot, can)
    loco:StopMoving()

    return STATUS.SUCCESS
end

---@param bot Bot
function DrinkSoda.OnEnd(bot)
    bot.sodaTarget = nil
    bot.sodaCooldown = CurTime() + COOLDOWN
    bot:BotLocomotor():StopMoving()
end

---@param bot Bot
function DrinkSoda.OnSuccess(bot) end

---@param bot Bot
function DrinkSoda.OnFailure(bot) end
