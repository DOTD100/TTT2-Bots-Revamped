--[[
Fires the Thomas The Tank Engine gun (adigram/ttt_adithomas, class ttt_thomas_swep).

The weapon is a one-shot joke with a real sting. Firing it drops a Thomas 200 units in front of the shooter,
facing the way the shooter was looking, and that is the entire involvement of the weapon - it removes itself
from the inventory. The train then drives straight ahead at `ttt_thomas_speed` (350 u/s by default) for
`ttt_thomas_explode_time` (15 seconds) in MOVETYPE_NOCLIP, which means *through walls*, killing any alive
player it touches for 1,000 damage credited to the shooter, and finally exploding for a
`ttt_thomas_explode_radius` blast (512 units). The addon's own safety rails are that the shooter cannot be hit
by the train, and that a Detective who touches it stops it (and survives, by default).

So the addon picks nothing, and everything this behaviour has to get right is the *launch*: the train goes
wherever the bot happens to be looking. Three rules follow from how it kills:

- **Aim at somebody.** A remembered enemy position is what makes the launch worth a credit. The train covers
  about 5,000 units in its fifteen seconds, so a position through a wall is a real chance of a hit.
- **Not at our own feet.** The blast is 512 units and the train is stopped by nothing but a detective, so a
  target worth launching at is one that is not right next to the bot.
- **Not down a line with a teammate on it.** The train kills *any* alive player it touches - the addon makes no
  exception for the shooter's own team - so the first stretch of the line is checked and the launch is refused
  if an ally is standing in it.

Inert without the addon: the weapon class has to exist, and in an ordinary round the only bot holding it is a
traitor who bought it.
]]

TTTBots.Behaviors.Thomas = {}

local lib = TTTBots.Lib

local Thomas = TTTBots.Behaviors.Thomas
Thomas.Name = "Thomas"
Thomas.Description = "Fire the Thomas the Tank Engine gun at somebody"
Thomas.Interruptible = true

local STATUS = TTTBots.STATUS

---@class Bot
---@field thomasTargetPos Vector? Where the train is being sent.
---@field thomasStartedAt number? When this launch began, so it can give up.
---@field thomasAttacking boolean? Between pressing attack and the weapon being spent.

local WEP = "ttt_thomas_swep"

--- How far a launch can reach: `ttt_thomas_speed` for `ttt_thomas_explode_time` seconds - 350 u/s for 15
--- seconds by default, about 5,000 units. Aiming at something further away than that is a wasted credit.
local REACH = 5000
--- Closer than this and the train is as likely to kill the bot as anybody else: it explodes for 512 units
--- wherever it ends up, and the bot is the one player standing where it was launched from.
local MIN_FIRE_DIST = 600
--- How far along the line to look for a teammate, and how wide a corridor counts as "on the line". The train
--- goes through walls, so the straight line is the only thing that can be checked.
local ALLY_CLEAR_LENGTH = 1500
local ALLY_CLEAR_RADIUS = 200
--- How close the aim has to be before pressing: the train leaves along the aim vector.
local AIM_DOT = 0.97
--- Single press, so this is a safety net for a weapon that never fires.
local GIVE_UP_TIME = 15

---@return boolean
function Thomas.IsAvailable()
    return weapons.Get(WEP) ~= nil
end

---@param bot Bot
---@return Weapon?
function Thomas.GetWeapon(bot)
    if not bot:HasWeapon(WEP) then return nil end

    local wep = bot:GetWeapon(WEP)
    if not (IsValid(wep) and wep.Clip1 and wep:Clip1() > 0) then return nil end

    return wep
end

--- Distance from a point to a line segment.
---@param point Vector
---@param a Vector
---@param b Vector
---@return number
local function distToSegment(point, a, b)
    local ab = b - a
    if ab:LengthSqr() < 1 then return point:Distance(a) end

    local t = math.Clamp((point - a):Dot(ab) / ab:LengthSqr(), 0, 1)

    return point:Distance(a + ab * t)
end

--- Where to send the train: the nearest enemy position we still remember, or nil.
---@param bot Bot
---@return Vector?
function Thomas.FindLaunchTarget(bot)
    local memory = bot:BotMemory()
    if not memory then return nil end

    local pos = bot:GetPos()
    local bestPos, bestDist = nil, nil
    for ply, knownPos in pairs(memory:GetKnownPlayersPos()) do
        if not IsValid(ply) then continue end
        if not lib.IsPlayerAlive(ply) then continue end
        if TTTBots.Roles.IsAllies(bot, ply) then continue end

        local dist = pos:Distance(knownPos)
        if dist < MIN_FIRE_DIST then continue end
        if dist > REACH then continue end

        -- Nearest first: the train is single use, and the shorter line is the likelier hit.
        if not bestDist or dist < bestDist then
            bestPos, bestDist = knownPos, dist
        end
    end

    return bestPos
end

--- Is a teammate standing on the line we would launch along? It kills them as readily as the enemy.
---@param bot Bot
---@param targetPos Vector
---@return boolean
function Thomas.HasAllyOnTheLine(bot, targetPos)
    local pos = bot:GetPos()

    local dir = targetPos - pos
    dir.z = 0 -- the train is at head height along the way; the slope it flies at is not what endangers an ally
    if dir:LengthSqr() < 1 then return true end

    local lineEnd = pos + dir:GetNormalized() * ALLY_CLEAR_LENGTH
    for _, other in ipairs(TTTBots.Match.AlivePlayers) do
        if not IsValid(other) then continue end
        if other == bot then continue end
        if not lib.IsPlayerAlive(other) then continue end
        if not TTTBots.Roles.IsAllies(bot, other) then continue end

        if distToSegment(other:GetPos(), pos, lineEnd) < ALLY_CLEAR_RADIUS then return true end
    end

    return false
end

---@param bot Bot
---@return boolean
function Thomas.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_thomas") then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not Thomas.IsAvailable() then return false end

    -- Not while we have something to shoot: a fight is over long before the train arrives, and the launch
    -- means holding a pistol model instead of a gun for a moment. When the trail goes cold and the target is
    -- dropped, the remembered position is exactly what this behaviour is for.
    if bot.attackTarget ~= nil then return false end
    if not Thomas.GetWeapon(bot) then return false end

    local targetPos = Thomas.FindLaunchTarget(bot)
    if not targetPos then return false end
    if Thomas.HasAllyOnTheLine(bot, targetPos) then return false end

    bot.thomasTargetPos = targetPos
    return true
end

---@param bot Bot
---@return BStatus
function Thomas.OnStart(bot)
    bot.thomasStartedAt = CurTime()
    bot.thomasAttacking = false

    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function Thomas.OnRunning(bot)
    local loco = bot:BotLocomotor()
    local targetPos = bot.thomasTargetPos

    if not (loco and targetPos) then return STATUS.FAILURE end
    if (CurTime() - (bot.thomasStartedAt or CurTime())) > GIVE_UP_TIME then return STATUS.FAILURE end

    -- The weapon is removed from the inventory when it fires, so its absence *is* the success signal.
    local wep = Thomas.GetWeapon(bot)
    if not wep then return STATUS.SUCCESS end

    local inv = bot:BotInventory()
    if inv then inv:PauseAutoSwitch() end
    bot:SelectWeapon(WEP)

    if bot.thomasAttacking then
        loco:StopAttack()
        bot.thomasAttacking = false

        if not bot:HasWeapon(WEP) then return STATUS.SUCCESS end
    end

    loco:LookAt(targetPos)
    loco:StopMoving()

    -- The train is created 200 units along the aim vector and keeps that direction, so the bot has to be
    -- actually looking at the spot before the button goes down.
    local toTarget = targetPos - bot:EyePos()
    if toTarget:LengthSqr() < 1 then return STATUS.RUNNING end
    toTarget:Normalize()

    if bot:GetAimVector():Dot(toTarget) < AIM_DOT then return STATUS.RUNNING end

    bot.thomasAttacking = true
    loco:StartAttack()

    return STATUS.RUNNING
end

---@param bot Bot
function Thomas.OnEnd(bot)
    bot.thomasTargetPos = nil
    bot.thomasStartedAt = nil
    bot.thomasAttacking = false

    local loco = bot:BotLocomotor()
    if loco then
        loco:StopAttack()
        loco:StopMoving()
    end

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end

---@param bot Bot
function Thomas.OnSuccess(bot) end

---@param bot Bot
function Thomas.OnFailure(bot) end
