--[[
Throws the grenade the bot is carrying.

The TTT2 grenade is not a click-to-shoot weapon. `weapon_tttbasegrenade:PrimaryAttack` only *pulls the
pin*; its `Think` then throws the grenade the moment the attack button is **released**. Holding the button
instead cooks it, and `detonate_timer` (5 s) later it goes off in the holder's hands. So the gesture a bot
has to perform is "press, wait a moment, let go" - which is what this behavior asks the locomotor for, and
why it never holds the attack button for longer than PIN_HOLD plus a tick.

Where to throw is the whole decision, and it has to be careful: a grenade does not check teams.

  * The spot is where the bot knows an enemy is - it takes `attackTarget`'s position - but that enemy has to
    be *out of sight*, which is the one case where shooting cannot reach and a grenade can. This is also why
    the node runs *before* the attack node: a target that broke line of sight is still a valid attack target
    (the bot walks at its last known position), so a grenade node placed after it would never get a turn.
  * A damaging grenade (incendiary, or anything not recognised) additionally demands that no teammate is
    standing near enough to the spot to be caught by it. A harmless one (smoke, the discombobulator) demands
    enough distance for it to be worth throwing at all.

Nothing here is tied to a class list: a grenade is recognised by the pin on the weapon (`GetPin`/`PullPin`
from TTT2's base), so a custom grenade built on that base gets the same treatment for free, and anything
that is not a pinned throwable is left alone.
]]

TTTBots.Behaviors.ThrowGrenade = {}

local lib = TTTBots.Lib

local ThrowGrenade = TTTBots.Behaviors.ThrowGrenade
ThrowGrenade.Name = "Throw Grenade"
ThrowGrenade.Description = "Throw a carried grenade at a position it knows an enemy is on"
ThrowGrenade.Interruptible = false

local STATUS = TTTBots.STATUS

---@class Bot
---@field grenadeTargetPos Vector?
---@field grenadeThrowStart number?
---@field grenadeCooldown number?

--- Grenades that are not meant to kill. Anything else, including a grenade from another addon, is treated
--- as lethal, which is the safe way round: the cost of over-caution is a grenade not thrown.
local HARMLESS = {
    weapon_ttt_smokegrenade = true,
    weapon_ttt_confgrenade = true,
}

local MIN_THROW_DIST = 250      -- inside this the bot is in its own blast
local MAX_THROW_DIST = 1100     -- beyond it the arc will not carry
local UTILITY_MIN_DIST = 450    -- a smoke grenade is only worth it once the enemy is this far off
local ALLY_SAFE_DIST = 250      -- no teammate may be this close to where the grenade is going
local PIN_HOLD = 0.5            -- how long the attack button stays down before the throw
local THROW_SETTLE = 0.4        -- let the throw animation finish before reporting success
local EQUIP_TIMEOUT = 2.5       -- give up if the grenade never comes to hand
local COOLDOWN = 12

--- The bot's grenade, if it is a TTT2-style pinned throwable. Slot 4 can hold things that are not thrown
--- grenades (a radio, a C4), and those are not this behavior's business.
---@param bot Bot
---@return Weapon?
function ThrowGrenade.GetGrenade(bot)
    local grenade = bot:BotInventory():GetGrenade()
    if not IsValid(grenade) then return nil end
    if not (grenade.GetPin and grenade.PullPin) then return nil end

    return grenade
end

---@param grenade Weapon
---@return boolean
function ThrowGrenade.IsHarmless(grenade)
    return HARMLESS[grenade:GetClass()] == true
end

--- Where a grenade is worth throwing, if anywhere. Returns nil when the bot has no target it knows about,
--- when the range is wrong for the grenade it is holding, or when a teammate is standing too close to the
--- spot for a damaging grenade to be safe.
---@param bot Bot
---@return Vector?
function ThrowGrenade.FindTarget(bot)
    local target = bot.attackTarget
    if not (IsValid(target) and lib.IsPlayerAlive(target)) then return nil end
    if TTTBots.Roles.IsAllies(bot, target) then return nil end

    local targetPos = target:GetPos()
    local dist = bot:GetPos():Distance(targetPos)
    if dist < MIN_THROW_DIST or dist > MAX_THROW_DIST then return nil end

    local grenade = ThrowGrenade.GetGrenade(bot)
    if not grenade then return nil end

    -- Only ever at an enemy the bot cannot shoot at. A target standing in the open belongs to the gunfight.
    if lib.CanSeeEntity(bot, target) then return nil end

    local harmful = not ThrowGrenade.IsHarmless(grenade)
    if not harmful and dist < UTILITY_MIN_DIST then return nil end

    -- The check is on the spot, not on the target: a teammate standing next to the enemy is exactly who a
    -- damaging grenade kills by accident.
    if harmful then
        for _, other in pairs(TTTBots.Match.AlivePlayers) do
            if other == bot then continue end
            if not TTTBots.Roles.IsAllies(bot, other) then continue end
            if other:GetPos():Distance(targetPos) < ALLY_SAFE_DIST then return nil end
        end
    end

    return targetPos
end

---@param bot Bot
---@return boolean
function ThrowGrenade.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("throw_nades") then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if (bot.grenadeCooldown or 0) > CurTime() then return false end

    local grenade = ThrowGrenade.GetGrenade(bot)
    if not grenade then return false end

    -- The pin is already out, so TTT2 owns this weapon until it has been thrown. Never interfere.
    if grenade:GetPin() then return false end

    local pos = ThrowGrenade.FindTarget(bot)
    if not pos then return false end

    bot.grenadeTargetPos = pos
    return true
end

---@param bot Bot
---@return BStatus
function ThrowGrenade.OnStart(bot)
    local inventory = bot:BotInventory()
    inventory:PauseAutoSwitch()
    inventory:EquipGrenade()

    bot.grenadeThrowStart = nil
    bot.grenadeBehaviorStart = CurTime()
    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function ThrowGrenade.OnRunning(bot)
    local loco = bot:BotLocomotor()
    local inventory = bot:BotInventory()
    local grenade = ThrowGrenade.GetGrenade(bot)
    local pos = bot.grenadeTargetPos

    if not (pos and TTTBots.Match.IsRoundActive() and lib.IsPlayerAlive(bot)) then
        loco:StopAttack()
        return STATUS.FAILURE
    end

    -- Wait until the grenade is actually in hand: TTT2 throws from the held weapon, and holding attack
    -- during a deploy is not the same gesture as holding it with the grenade ready.
    if not (grenade and bot:GetActiveWeapon() == grenade) then
        -- It was in hand a moment ago and now it is gone, which is the throw having happened.
        if bot.grenadeThrowStart then
            loco:StopAttack()
            return STATUS.SUCCESS
        end

        if (CurTime() - (bot.grenadeBehaviorStart or 0)) > EQUIP_TIMEOUT then
            return STATUS.FAILURE
        end

        inventory:EquipGrenade()
        return STATUS.RUNNING
    end

    -- Standing on the spot is our own blast, so walk away from the throw instead.
    if bot:GetPos():Distance(pos) < MIN_THROW_DIST then
        loco:StopAttack()
        return STATUS.FAILURE
    end

    loco:LookAt(pos)

    if not bot.grenadeThrowStart then bot.grenadeThrowStart = CurTime() end
    local elapsed = CurTime() - bot.grenadeThrowStart

    -- Phase 1: hold the attack button. That is what pulls the pin.
    if elapsed < PIN_HOLD then
        loco:StartAttack()
        return STATUS.RUNNING
    end

    -- Phase 2: let go. TTT2 sees the pin set with the button up and throws, and the SWEP removes itself as
    -- it creates the projectile - so from here on a missing grenade means the throw landed, not a failure.
    loco:StopAttack()

    if not ThrowGrenade.GetGrenade(bot) or elapsed >= (PIN_HOLD + THROW_SETTLE) then
        return STATUS.SUCCESS
    end

    return STATUS.RUNNING
end

---@param bot Bot
function ThrowGrenade.OnEnd(bot)
    local loco = bot:BotLocomotor()
    loco:StopAttack()
    bot:BotInventory():ResumeAutoSwitch()

    bot.grenadeTargetPos = nil
    bot.grenadeThrowStart = nil
    bot.grenadeBehaviorStart = nil
    bot.grenadeCooldown = CurTime() + COOLDOWN
end

---@param bot Bot
function ThrowGrenade.OnSuccess(bot) end

---@param bot Bot
function ThrowGrenade.OnFailure(bot) end
