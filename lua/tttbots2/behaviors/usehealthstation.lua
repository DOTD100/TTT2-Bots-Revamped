
TTTBots.Behaviors.UseHealthStation = {}

local lib = TTTBots.Lib

local UseHealthStation = TTTBots.Behaviors.UseHealthStation
UseHealthStation.Name = "Use Health Station"
UseHealthStation.Description = "Use or place a health station"
UseHealthStation.Interruptible = true
UseHealthStation.UseRange = 50 --- The range at which we can use a health station

UseHealthStation.TargetClass = "ttt_health_station"

local STATUS = TTTBots.STATUS

function UseHealthStation.HasHealthStation(bot)
    if not lib.GetConVarBool("plant_health") then return false end -- This behavior is disabled per the user's choice.
    return bot:HasWeapon("weapon_ttt_health_station")
end

function UseHealthStation.IsHurt(bot)
    local health = bot:Health()
    local maxHealth = bot:GetMaxHealth()
    return health + 1 < maxHealth
end

function UseHealthStation.ValidateStation(hs)
    local isvalid = (
        IsValid(hs)
        and hs:GetClass() == UseHealthStation.TargetClass
        and hs:GetStoredHealth() > 0
    )
    return isvalid
end

local STATION_CACHE_TIME = 1
local stationCache, stationCacheAt = nil, 0

--- The stations on the map that still have health in them, refreshed at most once a second.
---
--- `ents.FindByClass` builds a fresh list on every call, so scanning here cost every bot a world scan on every pass
--- through the tree whether or not it was hurt. The set changes only as stations are drained, and holding a
--- station nobody can use for an extra second is harmless: `OnRunning` re-validates the one it is walking to on
--- every tick regardless, and drops the behaviour when it is empty.
---@return table<Entity>
local function getValidStations()
    local now = CurTime()
    if not stationCache or (now - stationCacheAt) >= STATION_CACHE_TIME then
        local validStations = {}
        for _, v in ipairs(ents.FindByClass(UseHealthStation.TargetClass)) do
            if UseHealthStation.ValidateStation(v) then
                table.insert(validStations, v)
            end
        end

        stationCache, stationCacheAt = validStations, now
    end

    return stationCache
end

function UseHealthStation.GetNearestStation(bot)
    local nearestStation = lib.GetClosest(getValidStations(), bot:GetPos())
    return nearestStation
end

function UseHealthStation.TakeHealthFrom(bot, station)
    station:Use(bot)
end

--- Validate the behavior
function UseHealthStation.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if bot.attackTarget ~= nil then return false end             --- We are preoccupied with an attacker.
    if not lib.GetConVarBool("use_health") then return false end -- This behavior is disabled per the user's choice.

    -- Ordered so that the scan is the last thing paid for, and only by a bot that has a use for it: carrying a
    -- station is reason enough on its own (a weapon lookup, not a scan), and a bot at full health has nothing to
    -- walk to one for. This used to compute the scan *before* the short-circuit below, so every healthy bot on
    -- the server paid for a world scan on every pass through the tree.
    if UseHealthStation.HasHealthStation(bot) then return true end
    if not UseHealthStation.IsHurt(bot) then return false end

    -- `IsValid` rather than a truthiness test, because this is a *cached* entity: a station that has been removed
    -- is the NULL entity, which is truthy (section 8). An invalid one is ignored so the nearest is looked up
    -- again, which is what `OnStart` does with the result anyway.
    if IsValid(bot.targetStation) then return true end

    return UseHealthStation.GetNearestStation(bot) ~= nil
end

--- Called when the behavior is started
function UseHealthStation.OnStart(bot)
    if UseHealthStation.HasHealthStation(bot) then
        local inventory = bot:BotInventory()
        inventory:PauseAutoSwitch()
        return STATUS.RUNNING
    end

    local station = UseHealthStation.GetNearestStation(bot)
    bot.targetStation = station
    return STATUS.RUNNING
end

function UseHealthStation.PlaceHealthStation(bot)
    local locomotor = bot:BotLocomotor()
    bot:SelectWeapon("weapon_ttt_health_station")
    locomotor:StartAttack()
end

--- Called when the behavior's last state is running
function UseHealthStation.OnRunning(bot)
    if UseHealthStation.HasHealthStation(bot) then
        UseHealthStation.PlaceHealthStation(bot)
        return STATUS.RUNNING
    end

    if not UseHealthStation.IsHurt(bot) then
        return STATUS.SUCCESS
    end

    if not UseHealthStation.ValidateStation(bot.targetStation) then
        return STATUS.FAILURE
    end

    local station = bot.targetStation
    local locomotor = bot:BotLocomotor()
    locomotor:SetGoal(station:GetPos())
    locomotor:PauseRepel()
    local distToStation = bot:GetPos():Distance(station:GetPos())

    if distToStation < 300 then
        locomotor:LookAt(station:GetPos())
    end

    return STATUS.RUNNING
end

--- Called when the behavior returns a success state
function UseHealthStation.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function UseHealthStation.OnFailure(bot)
end

--- Called when the behavior ends
function UseHealthStation.OnEnd(bot)
    bot.targetStation = nil
    local locomotor = bot:BotLocomotor()
    local inventory = bot:BotInventory()
    inventory:ResumeAutoSwitch()
    locomotor:StopAttack()
    locomotor:ResumeRepel()
end

timer.Create("TTTBots.Behaviors.UseHealthStation.UseNearbyStations", 0.5, 0, function()
    for i, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and lib.IsPlayerAlive(bot)) then continue end
        local healthStation = bot.targetStation
        if not (healthStation and UseHealthStation.ValidateStation(healthStation)) then continue end
        local distToStation = bot:GetPos():Distance(healthStation:GetPos())
        if distToStation < UseHealthStation.UseRange then
            UseHealthStation.TakeHealthFrom(bot, healthStation)
        end
    end
end)
