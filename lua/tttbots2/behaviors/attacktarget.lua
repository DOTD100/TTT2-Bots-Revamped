
--[[
This behavior is not responsible for finding a target. It is responsible for attacking a target.

**It will only stop itself once the target is dead or nil. It must not be interrupted by another behavior.**
]]
---@class BAttack
TTTBots.Behaviors.AttackTarget = {}

local lib = TTTBots.Lib

---@class BAttack
local Attack = TTTBots.Behaviors.AttackTarget
Attack.Name = "AttackTarget"
Attack.Description = "Attacking target"
Attack.Interruptible = true

local STATUS = TTTBots.STATUS

---@enum ATTACKMODE
local ATTACKMODE = {
    Seeking = 2,  -- We have a target and we saw them recently or can see them but not shoot them
    Engaging = 3, -- We have a target and we know where they are, and we trying to shoot
}

--- Validate the behavior
function Attack.Validate(bot)
    return Attack.ValidateTarget(bot)
end

--- Called when the behavior is started
function Attack.OnStart(bot)
    return STATUS.RUNNING
end

function Attack.Seek(bot, targetPos)
    local target = bot.attackTarget
    local loco = bot:BotLocomotor() ---@type CLocomotor
    local inv = bot:BotInventory() ---@type CInventory
    if not (loco and inv) then return end
    loco.stopLookingAround = false
    loco:StopAttack()
    inv:ReloadIfNecessary()

    -- Seeking is chasing, and a melee bot has to do it at a run: at walking pace it matches the speed of
    -- anyone walking away from it and the trail goes cold before it arrives. Only while the trail is warm -
    -- running after a cold one is just jogging around the map - and only for a weapon that needs to close.
    local runToCatch = Attack.ShouldRunToCatch(inv:GetHeldWeaponInfo())

    ---@type CMemory
    local memory = bot.components.memory
    local lastKnownPos = memory:GetSuspectedPositionFor(target) or memory:GetKnownPositionFor(target)
    local lastSeenTime = memory:GetLastSeenTime(target)
    local secsSince = CurTime() - lastSeenTime

    -- While the trail is warm (target seen/heard within the last 4 seconds) move to and watch the
    -- last known position. Once it goes cold, wander instead of standing at a stale spot forever.
    if lastKnownPos and secsSince <= 4 then
        loco:SetSprint(runToCatch)
        loco:SetGoal(lastKnownPos)
        -- Look at the lead as a patch of ground rather than a point while the target is out of sight: the lead
        -- is usually a sound, and a sound does not arrive with coordinates (Lib.GetInferredLookPos). The
        -- *goal* stays exact, so the bot still walks to the right place - it just searches it on arrival
        -- instead of tracking a body it cannot see.
        -- The tick's shared answer (see Lib.SeenThisTick): the memory pass and the ADS check ask the same
        -- thing about the same pair in this tick.
        local visible = lib.SeenThisTick(bot, target)
        loco:LookAt(lib.GetInferredLookPos(bot, lastKnownPos + Vector(0, 0, 40), visible))
    else
        -- Trail gone cold: stop running, or the bot sprints across the map on a wander goal.
        if runToCatch then loco:SetSprint(false) end
        -- We have not heard nor seen the target in a while, so we will wander around - but around
        -- where we last knew they were, not wherever we happen to be standing. Walking off in a
        -- random direction while still nominally attacking made bots look like they had given up
        -- mid-fight.
        lib.CallEveryNTicks(
            bot,
            function()
                local searchRegion = lastKnownPos and lib.GetNearestRegion(lastKnownPos) or nil
                local wanderArea = (searchRegion and lib.GetRandomNavInRegion(searchRegion))
                    or TTTBots.Behaviors.Wander.GetAnyRandomNav(bot)

                if not IsValid(wanderArea) then return end
                loco:SetGoal(wanderArea:GetCenter())
            end,
            math.ceil(TTTBots.Tickrate * 5)
        )
    end

end

function Attack.GetTargetHeadPos(targetPly)
    local fallback = targetPly:EyePos()

    local head_bone_index = targetPly:LookupBone("ValveBiped.Bip01_Head1")
    if not head_bone_index then
        print("Returning fallback; no bone index for target.")
        return fallback
    end

    local head_pos = targetPly:GetBonePosition(head_bone_index)

    if head_pos then
        return head_pos
    else
        print("Returning fallback, couldn't retrieve head_pos from bone index " .. head_bone_index)
        return fallback
    end
end

function Attack.GetTargetBodyPos(targetPly)
    local fallback = targetPly:GetPos() + Vector(0, 0, 30)

    local spine_bone_index = targetPly:LookupBone("ValveBiped.Bip01_Spine2")
    if not spine_bone_index then
        print("Returning fallback; no bone index for target.")
        return fallback
    end

    local spine_pos = targetPly:GetBonePosition(spine_bone_index)

    if spine_pos then
        return spine_pos
    else
        print("Returning fallback, couldn't retrieve spine_pos from bone index " .. spine_bone_index)
        return fallback
    end
end

function Attack.ShouldLookAtBody(bot, weapon)
    -- Short range weapons always go for the body. The arson thrower in particular has to land its flame
    -- on the target, and a head is a small, bobbing point that also floats above the aim point we lead
    -- with (Attack.PredictMovement). A headshotter aiming at head height simply sprays fire over the
    -- target's shoulder and damages nobody, so the victim never even learns it was attacked.
    if weapon.is_short_range then return true end

    local personality = bot:BotPersonality() ---@type CPersonality
    local isBodyShotter = not (personality.isHeadshotter or false)
    -- ... and so does a swung weapon, whether the inventory classifies it as melee or not (Attack.IsSwung):
    -- a melee weapon reaches by *tracing* through the point it is aimed at, and the head is the smallest
    -- and most mobile part of the hitbox, so a headshotter swinging one would sail over a crouched victim.
    -- The same rule shankerstalk.lua spells out for its knife.
    return isBodyShotter or (weapon.is_shotgun or Attack.IsSwung(weapon))
end

--- How long a bot keeps weaving one way before it reconsiders. Long enough that the movement reads as a
--- sidestep, short enough that it will change its mind again inside a fight.
local STRAFE_HOLD_MIN = 0.7
local STRAFE_HOLD_MAX = 1.5

--- Tells loco to strafe
---@param weapon WeaponInfo
---@param loco CLocomotor
function Attack.StrafeIfNecessary(bot, weapon, loco)
    if bot.canStrafe == false then return false end
    if not (bot.attackTarget and bot.attackTarget.GetPos) then return false end
    if weapon.is_melee then return false end

    -- Do not strafe if we are on a cliff. We will fall off.
    local isCliffed = loco:IsCliffed()
    if isCliffed then return false end

    local distToTarget = bot:GetPos():Distance(bot.attackTarget:GetPos())
    local shouldStrafe = (distToTarget > 200)

    if not shouldStrafe then return false end

    -- Pick a direction and keep it for a while.
    --
    -- This used to roll a fresh coin every tick and hand the result to Strafe, which refreshes its own
    -- one second timeout on every call - so the bot's side move flipped sign ten times a second. That is
    -- the left/right twitch: the bot moves nowhere, and because the shot is led by the target's velocity
    -- and only fired once the aim has settled, two bots doing it at each other can go seconds without
    -- either of them firing a shot.
    if (bot.strafeHoldUntil or 0) < CurTime() then
        bot.strafeDir = (math.random(0, 1) == 0) and "left" or "right"
        bot.strafeHoldUntil = CurTime() + math.Rand(STRAFE_HOLD_MIN, STRAFE_HOLD_MAX)
    end

    loco:Strafe(bot.strafeDir)

    return true -- We are strafing
end

local IDEAL_APPROACH_DIST = 200
local ENGAGE_THRESHOLD = 180     -- Aggressive engagement threshold (closer)
local DISENGAGE_THRESHOLD = 250  -- Conservative disengagement threshold (farther)

--- How close a *swing* has to be before it does anything, measured from the bot's eyes to the point it is
--- swinging at - which is how a melee weapon measures its own reach.
---
--- TTT2's melee weapons all trace from the eye and only damage whatever that trace lands on: the crowbar
--- (weapon_zm_improvised) and the knife (weapon_ttt_knife) both trace 100 units from it, the Shanker's
--- knife 80. This used to be 160 measured between the two players' *feet*, and 160 is past every one of
--- them, so a bot that had "closed to melee range" was still short of it and spent the fight swinging at
--- air - which, from the outside, looks exactly like a role fighting with a ranged weapon. For a role
--- whose only weapon is a swing (the Roider's crowbar, the Shinigami's knife) that is the whole round.
--- 75 is comfortably inside all of them, and is the same figure shankerstalk.lua uses for its knife.
local MELEE_SWING_REACH = 75
--- The same distance for a *short range gun* such as the arsonist's thrower: held like a gun, used up
--- close, but with far more reach than a swing. It keeps the old hand-to-hand distance.
local SHORT_RANGE_SWING_REACH = 160

--- The give-ground distances. A bot backs away from anything closer than BACKPEDAL_START and keeps going
--- until it is past BACKPEDAL_STOP. The 60 units between the two *is* the hysteresis: with a single
--- threshold a bot standing on it flipped its retreat on and off every tick (see the note in Engage).
local BACKPEDAL_START = 100
local BACKPEDAL_STOP = 160

--- Vertical separation, in units, past which two players are on different floors. Roughly a player's
--- height: ramps, slopes and short stairs stay "same level", while a catwalk overhead or a basement
--- below means the only route between them is a path through the stairs, ramp or ladder.
local DIFFERENT_LEVEL_Z = 64

--- Half the width of a player's hull, in units. Used to size the aim tolerance below.
local AIM_TARGET_RADIUS = 16
--- Minimum aim tolerance, in degrees. Keeps the tolerance sane at very long range, where the
--- target's angular size is tiny, without letting the bot freeze up waiting for a perfect shot.
local AIM_TOLERANCE_MIN = 2.5

--- How long a bot will keep moving while it cannot line a shot up before it stops to shoot. Players plant
--- their feet when a shot will not come together; bots that never do stall each other out.
local AIM_PATIENCE = 1.5

--- Does this weapon have to be swung from arm's length?
---
--- That is everything the inventory does not count as a gun - the crowbar and the knives, whether the
--- weapon declares itself melee or not - and it is deliberately not the same question as `is_melee`, which
--- only asks whether the weapon has a clip. A short range gun is excluded: it is held and used like a
--- swung weapon, but it is a gun and its reach is longer.
---@param weapon WeaponInfo?
---@return boolean
function Attack.IsSwung(weapon)
    if not weapon then return false end
    if weapon.is_short_range then return false end

    return weapon.is_melee or not weapon.is_gun
end

--- The eye-to-swing-point distance at which attacking the current target starts doing damage. Only ever
--- asked in the close-quarters branch below, so a gun is never handed to it - but a short range gun can
--- be, and it answers with its own, longer distance (see MELEE_SWING_REACH).
---@param weapon WeaponInfo?
---@return number
function Attack.GetSwingReach(weapon)
    if Attack.IsSwung(weapon) then return MELEE_SWING_REACH end

    return SHORT_RANGE_SWING_REACH
end

function Attack.ShouldApproachWith(bot, weapon)
    return weapon.is_shotgun or Attack.IsSwung(weapon)
end

--- Does closing the gap with this weapon have to be done at a run?
---
--- A weapon that only works at arm's length has to chase, and walking cannot chase: the bot matches the
--- speed of anybody walking away from it and never closes, which leaves the weapon - the whole role, for a
--- Roider with its crowbar - unusable. The Shanker's stalk has always run for this reason; this is the same
--- rule for every other melee weapon, applied wherever the closing happens rather than in one role's
--- behaviour. Short range weapons (the arsonist's thrower) count too: they are held like guns and used like
--- the crowbar.
---@param weapon WeaponInfo?
---@return boolean
function Attack.ShouldRunToCatch(weapon)
    if not weapon then return false end

    return Attack.IsSwung(weapon) or weapon.is_short_range
end

--- Tests if the target is next to an explosive barrel, if so, returns the barrel.
---@param bot Bot
---@param target Player
---@return Entity|nil barrel
function Attack.TargetNextToBarrel(bot, target)
    local lastBarrelTime = target.lastBarrelCheck or 0
    local targetBarrel = target.lastBarrel or nil
    local TIME_BETWEEN_BARREL_CHECKS = 3 -- 3 seconds

    -- The cache is checked for *validity* as well as for age, because of what it holds: a barrel is the one
    -- prop in the game that is designed to stop existing in the middle of a fight, and a destroyed entity is
    -- not nil - it is the NULL entity, which is truthy. Serving a cached NULL from here is what made
    -- `barrel:GetPos()` at the call site throw "Tried to use a NULL entity!", twice, once for each bot
    -- shooting at the same target: shoot a barrel next to somebody and up to three more seconds of bots kept
    -- reaching for it.
    if IsValid(targetBarrel) and (lastBarrelTime + TIME_BETWEEN_BARREL_CHECKS) > CurTime() then
        return targetBarrel
    end

    local barrel = lib.GetClosestBarrel(target)
    target.lastBarrel = barrel
    target.lastBarrelCheck = CurTime()
    return barrel
end

function Attack.ApproachIfNecessary(bot, weapon, loco)
    if not (bot.attackTarget and bot.attackTarget.GetPos) then return false end
    if not Attack.ShouldApproachWith(bot, weapon) then return false end

    local distToTarget = bot:GetPos():Distance(bot.attackTarget:GetPos())
    local shouldApproach = (distToTarget > IDEAL_APPROACH_DIST)
    local forceStop = (distToTarget < IDEAL_APPROACH_DIST)
    if forceStop then
        loco:SetForceForward(false)
        return false
    end -- Stop forcing forward if we are close enough
    if not shouldApproach then return false end

    loco:SetForceForward(true)

    return true -- We are approaching
end

--- Handles strafing, moving towards/away from our target, etc.
---@param weapon WeaponInfo
---@param loco CLocomotor
function Attack.HandleAttackMovement(bot, weapon, loco)
    Attack.StrafeIfNecessary(bot, weapon, loco)
    Attack.ApproachIfNecessary(bot, weapon, loco)
end

function Attack.GetPreferredBodyTarget(bot, wep, target)
    local body, head = Attack.GetTargetBodyPos(target), Attack.GetTargetHeadPos(target)
    if Attack.ShouldLookAtBody(bot, wep) then
        return body
    end

    return head
end

function Attack.Engage(bot, targetPos)
    local target = bot.attackTarget
    local inv = bot.components.inventory ---@type CInventory
    local weapon = inv:GetHeldWeaponInfo()
    if not weapon then return end
    -- Short range weapons (the arson thrower) are held like guns but have to be used like the
    -- crowbar. Treated as a rifle, the bot will happily stand at rifle range and torch the air in
    -- front of its target instead of closing the gap.
    local usingMelee = (not weapon.is_gun) or weapon.is_short_range
    -- ... and how close "close" actually is: the weapon's own reach, not a hand-to-hand guess.
    local swingReach = Attack.GetSwingReach(weapon)
    local loco = bot:BotLocomotor() ---@type CLocomotor
    loco.stopLookingAround = true

    local distToTarget = bot:GetPos():Distance(target:GetPos())

    -- The point a swing would land on, resolved once here: the reach test below and the aiming further
    -- down both want it, and each call costs a bone lookup.
    local aimPoint = Attack.GetPreferredBodyTarget(bot, weapon, target)

    -- A target a floor up or down cannot be walked into: pressing forward on this level only buries
    -- the bot face-first in the ceiling or the floor slab, where it stands firing into solid
    -- geometry. That is what made overhead and basement fights look like the bot had no idea what to
    -- do with its target. Hand the goal to the pathfinder instead, so it takes the stairs, ramp or
    -- ladder, and skip the distance-based walking below entirely. Aiming and firing are untouched,
    -- so the bot keeps shooting the target while it works its way over.
    local onDifferentLevel = math.abs(target:GetPos().z - bot:GetPos().z) > DIFFERENT_LEVEL_Z

    if onDifferentLevel then
        loco:SetGoal(targetPos)
        loco:SetForceForward(false)
        loco:SetForceBackward(false)
    else
        -- Close-quarters states, with hysteresis on the one boundary a bot can actually straddle.
        --
        -- Two things used to fight here, and between them they produced bots that walked forwards and
        -- backwards in front of their target before shooting:
        --
        --  * The stop state cleared the *forces* but left the bot's goal and its path alive, and StartCommand
        --    walks a bot forward whenever it has a movement vector and no force against it. So in the band
        --    between the backpedal distance and ENGAGE_THRESHOLD, a live path pushed the bot *into* a target
        --    it had just decided not to close on.
        --  * The backpedal trigger had no hysteresis, and every call refreshes the force's one-second timeout
        --    (BotLocomotor:SetForceBackward), so a bot crossing that distance either way flipped the force
        --    every tick and each flip outlived its own trigger. Path in, forced back, path in again.
        --
        -- So: back off below BACKPEDAL_START and keep backing off until BACKPEDAL_STOP, and in every state
        -- that is not "walk towards the target" drop the goal and the path as well - the same call the planted
        -- branch further down already makes, for the same reason. The forces are then the only thing steering
        -- the bot, and the boundaries they disagree at are 60 units apart.
        local backingOff = bot.attackBackingOff or false
        if distToTarget < BACKPEDAL_START then
            backingOff = true
        elseif distToTarget > BACKPEDAL_STOP then
            backingOff = false
        end
        bot.attackBackingOff = backingOff

        if usingMelee then
            -- Melee has its own distances, and they belong to the weapon: measured from the eye to the
            -- point we are swinging at, the way the weapon's own trace measures its reach. Comparing the
            -- two players' *feet* against a fixed 160 is what parked the bot in the one band where a swing
            -- does nothing at all (see MELEE_SWING_REACH).
            if bot:EyePos():Distance(aimPoint) > swingReach then
                -- Too far for melee, so path towards it - at a run, or the target simply walks away from a
                -- crowbar the way it always could from a knife (see Attack.ShouldRunToCatch).
                loco:SetSprint(true)
                loco:SetGoal(targetPos)
                loco:SetForceForward(true)
                loco:SetForceBackward(false)
            else
                -- In range: stop, stand up straight and swing.
                loco:SetSprint(false)
                loco:StopMoving()
                loco:SetForceForward(false)
                loco:SetForceBackward(false)
            end
        elseif backingOff and not loco:IsCliffed() then
            -- Give ground, but never backwards off an edge: with a drop behind it the bot stands and shoots
            -- instead, which is also what the branch below does, so it still falls through to something sane.
            loco:StopMoving()
            loco:SetForceBackward(true)
            loco:SetForceForward(false)
        elseif distToTarget > DISENGAGE_THRESHOLD then
            -- Too far to shoot from comfortably: close the gap.
            loco:SetForceForward(true)
            loco:SetForceBackward(false)
        elseif distToTarget >= ENGAGE_THRESHOLD then
            -- In the sweet spot between the two thresholds: keep what momentum we have.
            loco:SetForceForward(true)
            loco:SetForceBackward(false)
        else
            -- In range and not being crowded: hold position and shoot. No force *and* no goal, because the
            -- path alone would walk the bot forward again.
            loco:StopMoving()
            loco:SetForceForward(false)
            loco:SetForceBackward(false)
        end
    end

    local dvlpr = lib.GetDebugFor("attack")
    if dvlpr then
        TTTBots.DebugServer.DrawLineBetween(
            bot:EyePos(),
            targetPos,
            Color(255, 0, 0),
            0.1,
            bot:Nick() .. ".attack"
        )
    end

    if not usingMelee then
        local barrel = Attack.TargetNextToBarrel(bot, target)
        -- `IsValid`, never a truthiness test: an entity that has been removed is NULL, which passes `if
        -- barrel` and then errors on the first method call. The cache above re-validates what it serves;
        -- this is the local guard for anything else that hands a barrel in.
        if IsValid(barrel)
            and target:VisibleVec(barrel:GetPos())
            and bot:VisibleVec(barrel:GetPos())
        then
            aimPoint = barrel:GetPos() + barrel:OBBCenter()
        end
    end

    -- A bot that cannot get its aim to settle stops weaving and plants its feet, which is what lets the
    -- view angles catch up and the fight resolve. Two bots that keep strafing without either of them
    -- managing to line a shot up lock into a standoff until something else breaks it, which is exactly
    -- what a strafe that flipped direction every tick produced. Cleared the moment a shot is lined up.
    local planted = bot.attackCantAimSince and (CurTime() - bot.attackCantAimSince) > AIM_PATIENCE

    -- Strafing and the shotgun/melee approach are for fights on one level. When the target is on
    -- another floor the path above is already steering the bot, and forced movement would only fight
    -- it for control of the movement vector.
    if not onDifferentLevel then
        if planted then
            -- Stand still and shoot. This is `StopMoving` rather than plain `Strafe(nil)` because the bot
            -- usually still has a goal from whatever it was doing when the fight started, and path
            -- following would keep walking it along that goal while it is meant to be settling its aim.
            -- Clearing the goal is also what keeps the unstuck code out of the fight: without it the bot
            -- is still "trying to move", gets read as wedged after 1.5 s of standing still, and has its
            -- strafe flipped out from under it every tick (movement_conflicts.md #16).
            loco:StopMoving()
            Attack.ApproachIfNecessary(bot, weapon, loco) -- Still close in; just do not weave doing it
        else
            Attack.HandleAttackMovement(bot, weapon, loco)
        end
    end

    local predictedPoint = aimPoint + Attack.PredictMovement(target, 0.4)
    local inaccuracyOffset = Attack.CalculateInaccuracy(bot, aimPoint, target)
    local inaccuracyTarget = predictedPoint + inaccuracyOffset
    loco:LookAt(inaccuracyTarget)

    -- `LookAt` only sets the look *goal*; the view angles themselves are interpolated towards it
    -- over the following ticks (BotLocomotor:RotateEyeAnglesTo). Firing on this same tick therefore
    -- sends the bullet wherever the bot was already facing, which is why shots sailed past targets
    -- the bot had just noticed. Wait until the eye angles have actually caught up before firing.
    --
    -- Judged against the aim point *before* the spread offset, not after it. `CalculateInaccuracy`
    -- rolls a fresh VectorRand() every tick, so comparing our eye angles with the jittered point
    -- compares them with a target that teleports - and at range, where the spread is at its widest,
    -- the bot would stop firing mid-fight and just stand there aiming. The tolerance below already
    -- covers the spread's angular size, so settling anywhere inside that cone counts as aimed.
    if not Attack.IsAimedAt(bot, loco, predictedPoint, inaccuracyOffset) then
        -- Start the clock the standstill above reads. It is deliberately not reset until a shot is lined
        -- up, so a bot that keeps failing to aim keeps its feet planted rather than resuming the weave.
        bot.attackCantAimSince = bot.attackCantAimSince or CurTime()
        loco:StopAttack()
        return
    end

    bot.attackCantAimSince = nil

    -- Pull the trigger. `StartCommand` only sends IN_ATTACK while loco.attack is set, so the
    -- Attack behavior must start the attack itself. Hold fire if a teammate is in the line of fire.
    if Attack.WillShootingTeamkill(bot, target) then
        loco:StopAttack()
    else
        loco:StartAttack()
    end
end

--- Returns true when the bot's view angles point closely enough at the aim point for a shot to
--- plausibly land. The tolerance is the angular radius of a player-sized target at the current
--- range, widened by the angular size of the spread offset we deliberately applied, so a bot that
--- has settled anywhere inside its own spread cone counts as aimed.
---@param bot Bot
---@param loco CLocomotor
---@param aimPos Vector The point we are aiming at, before the spread offset is applied.
---@param spreadOffset Vector The spread offset that will be added to the aim point.
---@return boolean aimed
function Attack.IsAimedAt(bot, loco, aimPos, spreadOffset)
    local dist = math.max(bot:EyePos():Distance(aimPos), 1)
    local tolerance = math.deg(math.atan((AIM_TARGET_RADIUS + spreadOffset:Length()) / dist))
    tolerance = math.max(tolerance, AIM_TOLERANCE_MIN)

    local yawDiff, pitchDiff = loco:GetEyeAngleDiffTo(aimPos)
    return math.abs(yawDiff) <= tolerance and math.abs(pitchDiff) <= tolerance
end

local INACCURACY_BASE = 9  --- The higher this is, the more inaccurate the bots will be.
local INACCURACY_SMOKE = 5 --- The inaccuracy modifier when the bot or its target is in smoke.
--- Calculate the inaccuracy of agent 'bot' according to a) its personality and b) diff setts
---@param bot Bot The bot that is shooting.
---@param origin Vector The original aim point.
---@param target Player The target that is being shot at.
function Attack.CalculateInaccuracy(bot, origin, target)
    local personality = bot:BotPersonality()
    if not personality then return Vector(0, 0, 0) end
    local difficulty = math.max(lib.GetConVarInt("difficulty"), 1) -- int [1,5]

    local dist = bot:GetPos():Distance(origin)
    local distFactor = math.max((dist / 64) ^ 1.5, 0.5)
    local pressure = personality:GetPressure()   -- float [0,1]
    local rage = (personality:GetRage() * 2) + 1 -- float [1,3]

    -- 0.7 rather than 0.5. Halving the spread leaves a bot that does not miss a still target at range, which
    -- reads as an aimbot rather than as a good shot; a traitor is still visibly the best shooter in the round.
    local isTraitorFactor =
        (bot:GetRoleStringRaw() == "traitor" and lib.GetConVarBool("cheat_traitor_accuracy"))
        and 0.7 or 1

    local focus_factor = (1 - (bot.attackFocus or 0.01)) * 1.5

    local targetMoveFactor = 1
    local selfMoveFactor = bot:GetVelocity():LengthSqr() > 100 and 1.25 or 0.75
    if not (IsValid(target) and target:IsPlayer()) then
        targetMoveFactor = 0.5
    else
        local vel = target:GetVelocity():LengthSqr()
        targetMoveFactor = vel > 100 and 1.0 or 0.5
    end

    local smokeFn = TTTBots.Match.IsPlyNearSmoke
    local isInSmoke = (smokeFn(bot) or smokeFn(bot.attackTarget)) and INACCURACY_SMOKE or 1

    local inaccuracy_mod = (pressure / difficulty) -- The more pressure we have, the more inaccurate we are; decreased by difficulty
        * distFactor                               -- The further away we are, the more inaccurate we are
        * INACCURACY_BASE                          -- Obviously, multiply by a constant to make it more inaccurate
        * rage                                     -- The more rage we have, the more inaccurate we are
        * focus_factor                             -- The less focus we have, the more inaccurate we are
        * isInSmoke                                -- If we are in smoke, we are more inaccurate
        * isTraitorFactor                          -- Reduce aim difficulty if the cheat cvar is enabled
        * targetMoveFactor                         -- Reduce aim difficulty if the target is immobile
        * selfMoveFactor                           -- Increase inaccuracy if we are moving

    inaccuracy_mod = math.max(inaccuracy_mod, 0.1)

    local rand = VectorRand() * inaccuracy_mod
    -- TTTBots.DebugServer.DrawCross(origin + rand, 8, Color(0, 255, 0), 0.1, bot:Nick() .. ".attack.inaccuracy")
    return rand
end

---Predict the (relative) movement of the target player using basic linear prediction
---@param target Player
---@return Vector predictedMovement
function Attack.PredictMovement(target, mult)
    local vel = target:GetVelocity()
    local predictionSecs = 1.0 / TTTBots.Tickrate
    local predictionMultSalt = math.random(95, 105) / 100.0
    local predictionMult = (1 + predictionMultSalt) * (mult or 0.5)
    local predictionRelative = (vel * predictionSecs * predictionMult)

    local dvlpr = lib.GetDebugFor("attack")
    if dvlpr then
        -- Draw a cross at the predicted position
        TTTBots.DebugServer.DrawCross(target:GetPos() + predictionRelative, 8, Color(255, 0, 0), predictionSecs,
            target:Nick() .. ".attack.prediction")
    end

    return predictionRelative
end

--- Returns true if shooting now would result in possibly shooting someone who isn't our target.
function Attack.WillShootingTeamkill(bot, target)
    -- The post-round deathmatch is a free for all, so "teammates" are just targets.
    if TTTBots.Match.IsDeathmatchActive() then return false end

    -- Get the eye trace of our bot.
    local eyeTrace = bot:GetEyeTrace()
    local ent = eyeTrace.Entity
    if not ent then return false end                                 -- We are not looking at anything important, we can shoot
    if ent == target then return false end                           -- We are looking at our target, we can shoot
    if IsValid(ent) and not ent:IsPlayer() then return false end     -- We are looking at something that is not a player, we can shoot
    if not TTTBots.Roles.IsAllies(bot, ent) then return false end    -- The entity we are looking at is not a teammate, we can shoot
    return true                                                      -- We are looking at a teammate, we cannot shoot
end

function Attack.LookingCloseToTarget(bot, target)
    local targetPos = target:GetPos()
    ---@type CLocomotor
    local locomotor = bot:BotLocomotor()
    -- GetEyeAngleDiffTo returns (yawDiff, pitchDiff); use the yaw difference.
    local yawDiff = locomotor:GetEyeAngleDiffTo(targetPos)
    local degDiff = math.abs(yawDiff)

    local THRESHOLD = 10
    local isLookingClose = degDiff < THRESHOLD

    return isLookingClose
end

--- Determine what mode of attack (attackMode) we are in.
---@param bot Bot
---@return ATTACKMODE mode
function Attack.RunningAttackLogic(bot)
    ---@type CMemory
    local memory = bot.components.memory
    local target = bot.attackTarget
    local targetPos = memory:GetCurrentPosOf(target)
    local mode = ATTACKMODE.Seeking -- Default to seeking
    local canShoot = lib.CanShoot(bot, target)

    if canShoot then mode = ATTACKMODE.Engaging end -- We can shoot them, we are engaging

    local switchcase = {
        [ATTACKMODE.Seeking] = Attack.Seek,
        [ATTACKMODE.Engaging] = Attack.Engage,
    }
    switchcase[mode](bot, targetPos) -- Call the function
    return mode
end

--- Validates if the target is extant and alive. True if valid.
---@param bot Bot
---@return boolean isValid
function Attack.ValidateTarget(bot)
    local target = bot.attackTarget

    local hasTarget = (target and target ~= NULL) and true or false
    if target == NULL or not IsValid(target) then return false end
    local targetIsValid = target and target:IsValid() or false
    local targetIsAlive = target and target:Alive() or false
    local targetIsPlayer = target and target:IsPlayer() or false
    local targetIsNPC = target and target:IsNPC() or false
    local targetIsPlayerAndAlive = targetIsPlayer and TTTBots.Lib.IsPlayerAlive(target) or false
    local targetIsNPCAndAlive = targetIsNPC and target:Health() > 0 or false
    local targetIsPlayerOrNPCAndAlive = targetIsPlayerAndAlive or targetIsNPCAndAlive or false
    -- Roles can change hands mid-round (the Swapper hands its role to whoever killed it), so never
    -- trust the role the target had when we picked them: if they can no longer be hurt by players,
    -- our bullets are pointless and we must break off rather than keep firing forever.
    local targetIsHurtable = not (targetIsPlayer and TTTBots.Roles.IsPlayerDamageImmune(target))

    -- Some roles cannot hurt anybody at all - the Beggar and the Collusionist have every point of damage
    -- they deal zeroed by their own addon - so a bot in one of them must not hold a target either. The
    -- mirror image of the check above: there the target cannot be hurt, here *we* cannot hurt anybody, and
    -- either way walking into the open to shoot is only a way to die. Read live, because the Beggar's
    -- team, and with it its role, changes the moment it picks a dropped shop weapon up.
    if TTTBots.Roles.GetRoleFor(bot):GetDealsNoDamage() then
        bot:SetAttackTarget(nil)
        return false
    end

    local checkPassed = (
        hasTarget
        and targetIsValid
        and targetIsAlive
        and targetIsPlayerOrNPCAndAlive
        and targetIsHurtable
    )

    if not checkPassed then
        bot:SetAttackTarget(nil)
    end

    return checkPassed
end

function Attack.IsTargetAlly(bot)
    if not (IsValid(bot.attackTarget) and bot.attackTarget:IsPlayer()) then return false end
    -- Nobody is an ally during the post-round deathmatch.
    if TTTBots.Match.IsDeathmatchActive() then return false end

    return TTTBots.Roles.IsAllies(bot, bot.attackTarget)
end

--- Called when the behavior's last state is running
---@param bot Bot
---@return BStatus status
function Attack.OnRunning(bot)
    local target = bot.attackTarget
    -- We could probably do Attack.Validate but this is more explicit:
    if not Attack.ValidateTarget(bot) then return STATUS.FAILURE end -- Target is not valid
    if Attack.IsTargetAlly(bot) then return STATUS.FAILURE end       -- Target is an ally. No attack!
    if target == bot then
        bot:SetAttackTarget(nil)
        return STATUS.FAILURE
    end

    local isNPC = target:IsNPC()
    local isPlayer = target:IsPlayer()
    if not isNPC and not isPlayer then
        ErrorNoHaltWithStack("Wtf has bot.attackTarget been assigned to? Not NPC nor player... target: " ..
            tostring(bot.attackTarget))
    end -- Target is not a player or NPC

    local attack = Attack.RunningAttackLogic(bot)
    bot.attackBehaviorMode = attack

    return STATUS.RUNNING
end

--- Called when the behavior returns a success state
function Attack.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Attack.OnFailure(bot)
end

--- Called when the behavior ends
function Attack.OnEnd(bot)
    -- Only drop a target that is genuinely finished. This used to clear unconditionally, which threw the fight
    -- away whenever a node ahead of AttackTarget in FightBack displaced it (ClearBreakables and ThrowGrenade sit
    -- in front of it): the target was cleared, whoever provided it handed it straight back, and the bot paid a
    -- whole new acquisition - look speed x5 and a fresh reaction delay - for an enemy it had already been
    -- fighting. The conditions below mirror ValidateTarget plus IsTargetAlly, so the clear still happens exactly
    -- when the fight really is over: target gone, target dead, target immune, or target now an ally.
    -- NPC targets are supported by ValidateTarget, so "alive" has to mean the same thing here as it does there -
    -- `lib.IsPlayerAlive` is false for every NPC, and using it would have started dropping living ones.
    local target = bot.attackTarget
    local targetIsNPC = IsValid(target) and target:IsNPC() or false
    local targetIsAlive = (targetIsNPC and target:Health() > 0) or TTTBots.Lib.IsPlayerAlive(target)
    local stillFightable = IsValid(target)
        and targetIsAlive
        and not TTTBots.Roles.IsPlayerDamageImmune(target)
        and not (target:IsPlayer() and not TTTBots.Match.IsDeathmatchActive() and TTTBots.Roles.IsAllies(bot, target))

    if not stillFightable then
        -- Temporary, alongside the provider's own log: a hunt role that keeps ending here is the flick loop.
        if TTTBots.Lib.GetConVarBool("debug_misc") and TTTBots.Roles.GetRoleFor(bot):GetHuntsTarget() then
            print(string.format("[ttt2bots] Attack.OnEnd cleared %s's target (%s)",
                bot:Nick(), IsValid(target) and target:Nick() or "none"))
        end
        bot:SetAttackTarget(nil)
    end
    -- Fight over: forget how long we had been failing to aim, drop the strafe so the next fight starts a
    -- fresh weave rather than resuming the last one mid-step, and let go of the retreat latch so the next
    -- target is met on distance rather than on how close the last one got.
    bot.attackCantAimSince = nil
    bot.strafeDir = nil
    bot.strafeHoldUntil = nil
    bot.attackBackingOff = nil

    local loco = bot:BotLocomotor()
    loco.stopLookingAround = false
    loco:Strafe(nil)
    loco:StopAttack()
    -- The chase sprint is a latch on the locomotor, so it has to be handed back with the rest of the fight
    -- state or the bot keeps running while it patrols. (ResetLifeState covers a bot that dies mid-chase.)
    loco:SetSprint(false)
    -- Forced movement forces are tick-based and linger past the end of combat, which would make
    -- the bot keep marching in the last combat direction long after the fight ended.
    loco:SetForceForward(nil)
    loco:SetForceBackward(nil)
end

local FOCUS_DECAY = 0.02
function Attack.UpdateFocus(bot)
    local factor = -FOCUS_DECAY
    factor = factor * (bot.attackTarget ~= nil and -2.5 or 1)
    factor = factor * (bot:GetTraitMult("focus") or 1)
    bot.attackFocus = (bot.attackFocus or 0.1) + factor
    bot.attackFocus = math.Clamp(bot.attackFocus, 0.1, 1)
end

timer.Create("TTTBots_AttackFocus", 1 / TTTBots.Tickrate, 0, function()
    for _, bot in ipairs(TTTBots.Bots) do
        if not IsValid(bot) then continue end
        Attack.UpdateFocus(bot)
    end
end)
