---@class BFuseCharge
TTTBots.Behaviors.FuseCharge = {}

local lib = TTTBots.Lib
local FuseCharge = TTTBots.Behaviors.FuseCharge
FuseCharge.Name = "FuseCharge"
FuseCharge.Description = "Run at the enemy once the fuse is nearly out"
-- The bot is three seconds away from being a bomb: nothing should be able to talk it out of walking at
-- somebody.
FuseCharge.Interruptible = false

local STATUS = TTTBots.STATUS

--[[
The Fuse (TTT2Fuse) is a traitor on a fuse: `ttt2_fuse_explode_timer` seconds after it takes the role - and
again after every kill it makes, because a kill puts the fuse back to full - it plays a lit-fuse sound and
three seconds later explodes where it stands. The blast is util.BlastDamage(ply, ply, pos, 300, 200): up to
200 damage inside 300 units with no team filter, so an ally standing next to it dies too.

That makes the end of the fuse a decision rather than an accident. A bot that spends its last seconds
wandering, hiding or backing out of a fight dies for nothing; a bot that walks into somebody takes them
along. This node is that decision: for the last CHARGE_TIME seconds it puts the bot on the nearest enemy
position it remembers. It is placed after the attack nodes, so shooting still wins - the charge only owns
the ticks where the bot has nothing to shoot at anyway.

The remaining time cannot be read from the server. STATUS:AddTimedStatus only networks a duration to the
client, so the server keeps no countdown to ask for. The deadline is reconstructed instead, from the same
two events the role itself uses - the start of a life and a kill - plus the duration convar. Being a second
or two out only changes when the bot starts running, which is why this does not need to be exact.
]]

--- Seconds left on the fuse before the bot gives up on surviving it and goes looking for somebody to take
--- with it. Long enough to cross a room, short enough that the bot is not suicidal for a whole round.
local CHARGE_TIME = 15
--- How far away a remembered enemy position is still worth running at. Further than this and the bot will
--- not reach it before going off, so it is better off doing whatever else it was doing.
local SEEK_RANGE = 2500
--- Close enough to a remembered position to count as having got there, which sends the bot looking for
--- somewhere else rather than standing on a guess.
local ARRIVE_DIST = 250

--- The role's own convar, or nil when that addon is not installed.
---@return number?
local function getDuration()
    local cv = GetConVar("ttt2_fuse_explode_timer")
    if not cv then return nil end

    return cv:GetInt()
end

---@param ply Player
---@return boolean
function FuseCharge.IsFuse(ply)
    return IsValid(ply) and ply.GetRoleStringRaw ~= nil and ply:GetRoleStringRaw() == "fuse"
end

--- Start this bot's fuse again. Mirrors the role's own GiveRoleLoadout, which is what arms it.
---@param bot Player
function FuseCharge.RestartFuse(bot)
    local duration = getDuration()
    if not duration then return end

    bot.fuseDeadline = CurTime() + duration
end

--- Seconds until this bot explodes, or nil when it is not a Fuse or the addon is absent.
---@param bot Bot
---@return number?
function FuseCharge.GetTimeLeft(bot)
    if not FuseCharge.IsFuse(bot) then return nil end

    -- A round that started before the deadline was recorded, or a role handed out mid-round: both are
    -- covered by starting the fuse the first time anybody asks.
    if not bot.fuseDeadline then FuseCharge.RestartFuse(bot) end
    if not bot.fuseDeadline then return nil end

    return bot.fuseDeadline - CurTime()
end

--- The nearest place we have a reason to believe an enemy is, or nil when we know of none.
---
--- Only positions this bot has actually seen - its own memory - and only for players it is allowed to
--- kill. The blast has no team filter, so charging at an ally's last known position would take a teammate
--- with us, and the role's own teamkill penalty is severe.
---@param bot Bot
---@return Vector?
function FuseCharge.FindChargeSpot(bot)
    local memory = bot:BotMemory()
    if not memory then return nil end

    local closest, closestDist = nil, nil
    for ply, pos in pairs(memory:GetKnownPlayersPos()) do
        if not IsValid(ply) then continue end
        if not lib.IsPlayerAlive(ply) then continue end
        if TTTBots.Roles.IsAllies(bot, ply) then continue end

        local dist = bot:GetPos():Distance(pos)
        if dist > SEEK_RANGE then continue end
        if not closestDist or dist < closestDist then
            closest, closestDist = pos, dist
        end
    end

    return closest
end

--- Validate the behavior
function FuseCharge.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.IsPlayerAlive(bot) then return false end

    local timeLeft = FuseCharge.GetTimeLeft(bot)
    if not timeLeft or timeLeft > CHARGE_TIME then return false end

    -- A target in hand is better than a remembered position: the attack node above us is already walking
    -- at them and shooting.
    if bot.attackTarget ~= nil then return false end

    local spot = FuseCharge.FindChargeSpot(bot)
    bot.fuseChargePos = spot

    return spot ~= nil
end

--- Called when the behavior is started
function FuseCharge.OnStart(bot)
    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
function FuseCharge.OnRunning(bot)
    local timeLeft = FuseCharge.GetTimeLeft(bot)
    -- Either a kill reset the fuse or we are no longer the Fuse at all; either way, stand down.
    if not timeLeft or timeLeft > CHARGE_TIME then return STATUS.SUCCESS end

    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    local spot = bot.fuseChargePos
    if not spot then return STATUS.FAILURE end

    if bot:GetPos():Distance(spot) < ARRIVE_DIST then
        -- Got there and nobody was home. Drop this guess so the next tick picks the next one.
        bot.fuseChargePos = nil
        return STATUS.FAILURE
    end

    loco:SetGoal(spot)

    return STATUS.RUNNING
end

--- Called when the behavior ends
function FuseCharge.OnEnd(bot)
    bot.fuseChargePos = nil

    local loco = bot:BotLocomotor()
    if loco then loco:StopMoving() end
end

--- A life begins with a full fuse.
hook.Add("PlayerSpawn", "TTTBots.FuseCharge.RestartOnSpawn", function(ply)
    if not ply:IsBot() then return end

    FuseCharge.RestartFuse(ply)
end)

hook.Add("TTTBeginRound", "TTTBots.FuseCharge.RestartOnRound", function()
    for _, bot in pairs(TTTBots.Bots or {}) do
        if not IsValid(bot) then continue end

        FuseCharge.RestartFuse(bot)
    end
end)

--- A kill puts the fuse back to full, which is the same rule the role applies in its own
--- TTT2PostPlayerDeath hook. Any death this Fuse caused counts, including its own explosion.
hook.Add("PlayerDeath", "TTTBots.FuseCharge.KillResets", function(victim, inflictor, attacker)
    if not (IsValid(attacker) and attacker:IsPlayer()) then return end
    if not FuseCharge.IsFuse(attacker) then return end

    FuseCharge.RestartFuse(attacker)
end)
