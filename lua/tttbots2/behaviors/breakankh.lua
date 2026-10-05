--[[
Shoots a placed Ankh down (TTT-2/ttt2-role_pha).

The ankh is damageable by anybody: `ENT:OnTakeDamage` subtracts whatever hits it - 500 health by default
(`ttt_ankh_health`) - until it removes itself. Destroying it costs its owner the respawn point *and* the slow
heal that keeps them coming back to it. Destroying one while its owner is reviving does more than that: the
addon's `DestroyAnkh` swaps the "you are coming back" popup for "revival canceled" and calls
`revivingPlayer:CancelRevival()`, so that death becomes permanent. That is the case worth the ammunition.

Two limits, both of them properties of this addon rather than caution for its own sake:

  * the attack path lets a bot fire about once a second (`BotLocomotor:TestShouldPreventFire`, which exists so
    modded guns do not jam), so 500 health is a long job. The node is a commitment for as long as it runs, and
    it gives up after `MAX_DURATION` instead of standing there indefinitely;
  * it is placed *after* `AttackTarget` in `FightBack` and is interruptible, so it only ever runs when there is
    no player to deal with and yields the tick one appears. Shooting an object while a person walks up behind
    the bot is how a bot loses a round it was winning.

Fairness: it shoots what a player could see and shoot, and asks for the same line of sight (`Lib.SeenThisTick`),
so an ankh behind a wall is invisible to it. Roles that deal no damage are skipped outright: the addon asks
`TTT2PharaohPreventDamageToAnkh` before it applies any damage, and for those roles that hook says no, so firing
at an ankh would only tell its owner where that bot is.
]]

TTTBots.Behaviors.BreakAnkh = {}

local lib = TTTBots.Lib

local BreakAnkh = TTTBots.Behaviors.BreakAnkh
BreakAnkh.Name = "Break Ankh"
BreakAnkh.Description = "Shoot down an enemy's Ankh"
BreakAnkh.Interruptible = true

local STATUS = TTTBots.STATUS

local ANKH_WEAPON = "weapon_ttt_ankh"

--- Past this it is not shooting, it is a walk across the map to shoot an object.
local MAX_RANGE = 900
--- See the header: 500 health at roughly one shot a second.
local MAX_DURATION = 20

--- The ankh list is cached in the lib (`Lib.GetAnkhs`), keyed on the tick, so `breakankh`, `moveankh` and
--- `stealankh` share one entity scan per tick instead of each scanning the world on their own.

--- The addon's own handler, or nil when the role addon is not installed.
---@return table?
local function getHandler()
    if not (PHARAOH_HANDLER and ROLE_PHARAOH) then return nil end

    return PHARAOH_HANDLER
end

--- Is this ankh still worth shooting? Its owner has to be a non-ally who would actually benefit from it.
---@param bot Bot
---@param ankh Entity
---@return boolean
local function isWorthBreaking(bot, ankh)
    local owner = ankh:GetOwner()
    if not IsValid(owner) then return false end
    if TTTBots.Roles.IsAllies(bot, owner) then return false end

    -- Alive: it is that player's respawn point and heal. Reviving: it is the only reason a dead one is coming
    -- back at all. A dead owner who is not reviving has nothing left for the ankh to do.
    return lib.IsPlayerAlive(owner) or ankh:GetNWBool("isReviving", false)
end

--- The nearest ankh this bot could shoot right now, or nil.
---@param bot Bot
---@return Entity?
local function findTarget(bot)
    local myPos = bot:GetPos()

    for _, ankh in ipairs(lib.GetAnkhs()) do
        if not IsValid(ankh) then continue end
        if not isWorthBreaking(bot, ankh) then continue end
        if myPos:Distance(ankh:GetPos()) > MAX_RANGE then continue end
        if not lib.SeenThisTick(bot, ankh) then continue end

        return ankh
    end

    return nil
end

--- Aimed well enough to be worth a bullet, using the attack behaviour's own tolerance so this matches the
--- standard the bot shoots players to.
---@param bot Bot
---@param loco CLocomotor
---@param pos Vector
---@return boolean
local function isAimedAt(bot, loco, pos)
    local attack = TTTBots.Behaviors.AttackTarget

    if attack and attack.IsAimedAt then
        return attack.IsAimedAt(bot, loco, pos, Vector(0, 0, 0))
    end

    local yawDiff, pitchDiff = loco:GetEyeAngleDiffTo(pos)

    return math.abs(yawDiff) <= 8 and math.abs(pitchDiff) <= 8
end

---@param bot Bot
---@return boolean
function BreakAnkh.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_ankh") then return false end

    -- Cheap gate for every bot on a server without the addon, and for every bot on one with it until an ankh
    -- is actually placed (the scan below then finds nothing and returns false).
    if not getHandler() then return false end

    if bot.attackTarget then return false end
    if TTTBots.Roles.GetRoleFor(bot):GetDealsNoDamage() then return false end

    local wep = bot:GetActiveWeapon()
    if not IsValid(wep) then return false end
    -- The ankh weapon must never be aimed at anything: its own trace ignores players, so a shot "at" somebody
    -- lands on the floor at their feet and places an ankh. Same note as behaviors/placeankh.lua.
    if wep:GetClass() == ANKH_WEAPON then return false end

    return findTarget(bot) ~= nil
end

---@param bot Bot
function BreakAnkh.OnStart(bot)
    bot.ankhTarget = findTarget(bot)
    bot.ankhDeadline = CurTime() + MAX_DURATION

    return STATUS.RUNNING
end

---@param bot Bot
---@return integer
function BreakAnkh.OnRunning(bot)
    if not TTTBots.Match.IsRoundActive() then return STATUS.FAILURE end

    local ankh = bot.ankhTarget

    -- Gone: either it is broken, which is the point, or somebody else broke it. Either way this is finished.
    if not IsValid(ankh) then return STATUS.SUCCESS end

    if CurTime() > (bot.ankhDeadline or 0) then return STATUS.FAILURE end
    if not isWorthBreaking(bot, ankh) then return STATUS.FAILURE end

    local loco = bot:BotLocomotor()
    local aimPos = ankh:WorldSpaceCenter()

    loco:ClearGoal()
    loco:LookAt(aimPos)

    -- Never fire while the bot is still turning: its first shots would go wherever it used to be looking.
    if isAimedAt(bot, loco, aimPos) then
        loco:StartAttack()
    else
        loco:StopAttack()
    end

    return STATUS.RUNNING
end

---@param bot Bot
function BreakAnkh.OnEnd(bot)
    local loco = bot:BotLocomotor()

    loco:StopAttack()
    loco:ClearGoal()

    bot.ankhTarget = nil
    bot.ankhDeadline = nil
end
