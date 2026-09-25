--[[
Uses the Minethrower (mexikoedi/ttt_ttt2_minethrower, class weapon_ttt_ttt2_minethrower), which fires stock
HL2 hopper mines: combine mines that arm where they land and then go for whoever comes near them.

The weapon carries two mines (`Primary.ClipSize = 2`) and spends one per press, whichever button is used.
`PrimaryAttack` throws a mine with a 7,000 unit force applied to its physics object; `SecondaryAttack` drops
one 30 units in front of the player with a bare nudge. Both spawn it at `EyePos + aim * 30` facing the eye
angles, and the addon credits whatever it kills to whoever placed it (its `EntityTakeDamage` hook rewrites the
attacker to the mine's owner, so its `owner.origin` marker is also how a placed mine can be recognised as one
of ours).

A hopper mine does not check teams and the addon does nothing to change that, so its own owner is exactly as
valid a target as anybody else. That decides both branches here:

- **Throw** one at an enemy the bot remembers but cannot shoot at. 7,000 units of force is the entire point
  of the item: the mine lands where they are going, arms there, and the bot is nowhere near it. Only inside
  `MAX_THROW_DIST`, and never closer than `MIN_THROW_DIST` - which is the "do not drop it on ourselves" rule.
- **Place** one only from a doorway the bot is standing in and not about to walk out of, and then leave. The
  place button is the trap use - a mine in a corridor is what the item is for - but it goes down 30 units in
  front of the bot, so the bot has to be there while it arms and then not be. Hence the chokepoint test, the
  stationary requirement, the ally check, and the walk-away phase that follows a placement.

Inert without the addon, and inert once the two mines are spent: the weapon cannot reload (Primary.Ammo is
"none"), so an empty minethrower is a brick.
]]

TTTBots.Behaviors.MineThrower = {}

local lib = TTTBots.Lib

local MineThrower = TTTBots.Behaviors.MineThrower
MineThrower.Name = "Minethrower"
MineThrower.Description = "Throw or place a combine mine"
MineThrower.Interruptible = true

local STATUS = TTTBots.STATUS

---@class Bot
---@field mineTargetPos Vector? Where a thrown mine is being aimed.
---@field minePlacedAt Vector? Where a placed mine went down, so the bot can clear the area.
---@field mineStartedAt number? When this began, so it can give up.
---@field mineAttacking boolean? Between pressing a button and the mine count dropping.
---@field mineClipBefore number? The mines left before that press.
---@field mineCooldown number? Until this time, no more mines.

local WEP = "weapon_ttt_ttt2_minethrower"

--- A thrown mine goes far, but only aim at something the throw can actually reach. The lower bound is the
--- safety rule: the mine arms where it lands and does not care whose mine it is.
local MAX_THROW_DIST = 3000
local MIN_THROW_DIST = 300

--- Walls this close on both sides make a doorway or a corridor, which is the only place a placed mine earns
--- its keep. Measured at chest height, since that is where a corridor is narrow.
local CORRIDOR_WIDTH = 120
--- Where the mine lands: the place attack drops it 30 units along the aim vector, so the bot looks a little
--- further ahead than that and lets it fall.
local PLACE_LOOKAHEAD = 60
--- Clear this far from a mine we just put down. A hopper mine hops at whoever comes near it.
local WALK_AWAY_DIST = 500
--- Nothing inside this of a placement spot, or the teammate triggers the mine before the enemy does.
local ALLY_CLEAR_DIST = 400
--- How close the aim has to be before pressing: both attacks spawn the mine along the aim vector.
local AIM_DOT = 0.97
--- Two mines, so this is only a safety net for a button that never registers.
local GIVE_UP_TIME = 15
--- Two mines a round is the whole budget; this only stops the bot from stacking them on one doorway in a
--- single quiet minute.
local COOLDOWN = 45

---@return boolean
function MineThrower.IsAvailable()
    return weapons.Get(WEP) ~= nil
end

---@param bot Bot
---@return Weapon?
function MineThrower.GetWeapon(bot)
    if not bot:HasWeapon(WEP) then return nil end

    local wep = bot:GetWeapon(WEP)
    if not (IsValid(wep) and wep.Clip1 and wep:Clip1() > 0) then return nil end

    return wep
end

--- The nearest remembered enemy position a throw could reach, or nil.
---@param bot Bot
---@return Vector?
function MineThrower.FindThrowTarget(bot)
    local memory = bot:BotMemory()
    if not memory then return nil end

    local pos = bot:GetPos()
    local bestPos, bestDist = nil, nil
    for ply, knownPos in pairs(memory:GetKnownPlayersPos()) do
        if not IsValid(ply) then continue end
        if not lib.IsPlayerAlive(ply) then continue end
        if TTTBots.Roles.IsAllies(bot, ply) then continue end

        local dist = pos:Distance(knownPos)
        if dist < MIN_THROW_DIST then continue end
        if dist > MAX_THROW_DIST then continue end

        if not bestDist or dist < bestDist then
            bestPos, bestDist = knownPos, dist
        end
    end

    return bestPos
end

--- Is the bot standing in a doorway or a corridor? Walls close on both sides and room ahead is what makes a
--- placed mine a trap rather than a decoration.
---@param bot Bot
---@return boolean
function MineThrower.IsInChokepoint(bot)
    local pos = bot:GetPos() + Vector(0, 0, 40)
    local right = bot:GetRight()

    local function blocked(dir)
        local tr = util.TraceLine({
            start = pos,
            endpos = pos + dir * CORRIDOR_WIDTH,
            filter = bot,
            mask = MASK_PLAYERSOLID,
        })
        return tr.Hit
    end

    return blocked(right) and blocked(-right)
end

--- Somewhere worth putting a mine down: the floor just ahead of the bot, or nil.
---@param bot Bot
---@return Vector?
function MineThrower.FindPlaceSpot(bot)
    if not MineThrower.IsInChokepoint(bot) then return nil end
    if not TTTBots.Lib.IsPlayerAlive(bot) then return nil end
    if bot:BotLocomotor():IsTryingToMove() then return nil end -- mid-walk is not the moment to stop and arm one
    if bot:BotLocomotor():IsCliffed() then return nil end

    local pos = bot:GetPos()
    local look = bot:GetAimVector()
    look.z = 0
    if look:LengthSqr() < 1 then return nil end
    look:Normalize()

    local ahead = pos + look * PLACE_LOOKAHEAD
    local ground = util.TraceLine({
        start = ahead + Vector(0, 0, 48),
        endpos = ahead - Vector(0, 0, 64),
        filter = bot,
        mask = MASK_PLAYERSOLID,
    })
    if not ground.Hit then return nil end
    if ground.HitNormal.z < 0.5 then return nil end -- a wall, not a floor

    -- Nobody of ours near enough to set it off first. The mine does not check teams.
    for _, ally in ipairs(TTTBots.Match.AlivePlayers) do
        if not IsValid(ally) then continue end
        if not lib.IsPlayerAlive(ally) then continue end
        if not TTTBots.Roles.IsAllies(bot, ally) then continue end
        if ally:GetPos():Distance(ground.HitPos) < ALLY_CLEAR_DIST then return nil end
    end

    return ground.HitPos
end

---@param bot Bot
---@return boolean
function MineThrower.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_minethrower") then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not MineThrower.IsAvailable() then return false end
    if (bot.mineCooldown or 0) > CurTime() then return false end
    if not MineThrower.GetWeapon(bot) then return false end

    -- A fight comes first: the throw is for an enemy we know about but cannot shoot at, and a firefight is no
    -- time to be holding a mine.
    if bot.attackTarget ~= nil then return false end

    local throwPos = MineThrower.FindThrowTarget(bot)
    bot.mineTargetPos = throwPos
    if throwPos then return true end

    -- Nothing to throw at, so consider the trap use instead.
    bot.minePlacePos = MineThrower.FindPlaceSpot(bot)
    return bot.minePlacePos ~= nil
end

---@param bot Bot
---@return BStatus
function MineThrower.OnStart(bot)
    bot.mineStartedAt = CurTime()
    bot.mineAttacking = false
    bot.minePlacedAt = nil

    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function MineThrower.OnRunning(bot)
    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end
    if (CurTime() - (bot.mineStartedAt or CurTime())) > GIVE_UP_TIME then return STATUS.FAILURE end

    -- The walk-away phase of a placement: a hopper mine goes for whoever comes near it, and the bot just
    -- stood over it.
    local placedAt = bot.minePlacedAt
    if placedAt then
        if bot:GetPos():Distance(placedAt) >= WALK_AWAY_DIST then return STATUS.SUCCESS end

        local away = bot:GetPos() - placedAt
        away.z = 0
        if away:LengthSqr() < 1 then away = -bot:GetForward() end

        loco:SetGoal(bot:GetPos() + away:GetNormalized() * WALK_AWAY_DIST)
        return STATUS.RUNNING
    end

    local wep = MineThrower.GetWeapon(bot)
    if not wep then return STATUS.SUCCESS end -- both mines are spent, which is the whole job

    local inv = bot:BotInventory()
    if inv then inv:PauseAutoSwitch() end
    bot:SelectWeapon(WEP)

    -- Did the press we made last tick spend a mine?
    if bot.mineAttacking then
        loco:StopAttack()
        loco:StopAttack2()
        bot.mineAttacking = false

        if wep:Clip1() < (bot.mineClipBefore or 0) then
            -- Placed rather than thrown: the mine is on the floor in front of us, so leave it alone.
            if bot.minePlacePos then
                bot.minePlacedAt = bot.minePlacePos
                return STATUS.RUNNING
            end

            return STATUS.SUCCESS
        end
    end

    local throwPos = bot.mineTargetPos
    if throwPos then
        loco:LookAt(throwPos)
    else
        local placePos = bot.minePlacePos
        if not placePos then return STATUS.FAILURE end

        loco:LookAt(placePos)
    end

    -- Both attacks spawn the mine along the aim vector, so wait until the bot is actually looking at the spot
    -- rather than pressing at whatever it happens to be facing.
    local aimAt = throwPos or bot.minePlacePos
    local toSpot = aimAt - bot:EyePos()
    if toSpot:LengthSqr() < 1 then return STATUS.RUNNING end
    toSpot:Normalize()

    if bot:GetAimVector():Dot(toSpot) < AIM_DOT then return STATUS.RUNNING end

    bot.mineClipBefore = wep:Clip1()
    bot.mineAttacking = true

    if throwPos then
        loco:StartAttack()
    else
        loco:StartAttack2()
    end

    return STATUS.RUNNING
end

---@param bot Bot
function MineThrower.OnEnd(bot)
    bot.mineTargetPos = nil
    bot.minePlacePos = nil
    bot.minePlacedAt = nil
    bot.mineStartedAt = nil
    bot.mineAttacking = false
    bot.mineClipBefore = nil
    bot.mineCooldown = CurTime() + COOLDOWN

    local loco = bot:BotLocomotor()
    if loco then
        loco:StopAttack()
        loco:StopAttack2()
    end

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end

---@param bot Bot
function MineThrower.OnSuccess(bot) end

---@param bot Bot
function MineThrower.OnFailure(bot) end
