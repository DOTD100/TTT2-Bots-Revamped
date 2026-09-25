--[[
Places the Pharaoh's Ankh (TTT-2/ttt2-role_pha).

The role's own loadout hands the Pharaoh `weapon_ttt_ankh`, and both of its attack buttons call `SWEP:AnkhStick`,
which is the only way an ankh ever enters the world. Nothing in this addon would ever press that button: the
weapon's `SWEP.Kind` is WEAPON_EXTRA, which the inventory never equips, so this behaviour selects it by hand -
the same shape as behaviors/usehealthstation.lua, which also equips a WEAPON_EXTRA item before firing it.

What the weapon itself decides, and therefore what this node has to satisfy first:

  * the trace is `ply:GetShootPos() + ply:GetAimVector() * 100` (`SWEP:AnkhStick`), measured from the **eye**;
  * the surface has to be flat: `acos(tr.HitNormal:Dot(Vector(0, 0, 1))) <= 0.2` rad;
  * a second, entity-aware trace has to report `HitWorld` - a prop's top passes every other test and then the
    placement silently does nothing;
  * `plyspawn.IsSpawnPointSafe` has to have room for the ankh's model, which this node cannot predict. That is
    what the retries are for: a refused attempt costs the weapon's 1 second `Primary.Delay` and nothing else,
    because the weapon only consumes itself (`SWEP:PlacedAnkh` -> `TakePrimaryAmmo(1)`) once an ankh exists.

The weapon is single use, so a few seconds of looking before pressing is worth more than a press per second.
For the same reason `Interruptible` is false: the tree cannot pull the bot away mid-attempt, and while it holds
the ankh it must never be handed to `Attack.Engage`, which would fire it at a player and - because the weapon's
own trace ignores players - place the ankh on the floor at that player's feet.

Relocation (the owner picking its own ankh up and putting it down somewhere safer) is the other half of this
node: behaviors/moveankh.lua picks the ankh up, sets `bot.ankhDestination` and `bot.ankhRelocateFrom`, and this
node walks there before placing. `PlayerOwnsAnAnkhOutsideOfLoadout` is false for an ankh that is back in its
owner's loadout, so the addon allows the second placement.
]]

TTTBots.Behaviors.PlaceAnkh = {}

local lib = TTTBots.Lib

local PlaceAnkh = TTTBots.Behaviors.PlaceAnkh
PlaceAnkh.Name = "Place Ankh"
PlaceAnkh.Description = "Place the Pharaoh's Ankh on the ground"
PlaceAnkh.Interruptible = false

local STATUS = TTTBots.STATUS

--- The role's own loadout weapon. See the header for why it has to be selected by hand.
local ANKH_WEAPON = "weapon_ttt_ankh"

--- The weapon's `Primary.Delay` is 1 second, so a retry sooner than that is a press the weapon will refuse.
local RETRY_DELAY = 1.1

--- The weapon refuses anything steeper than 0.2 rad from vertical; ask for the same flatness ourselves so a
--- steep floor is skipped before the one-shot weapon is spent.
local MIN_FLATNESS = math.cos(0.2)

--- Probe rings in front of the bot, and how far out each one looks. The eye sits ~64 units up, so even the far
--- probe stays inside the weapon's own 100 unit reach.
local PROBE_YAW_ANGLES = { 0, 30, -30, 60, -60, 90, -90, 180 }
local PROBE_DISTANCES = { 40, 70, 96 }

local MAX_ATTEMPTS = 4
--- A hard bound on the whole node, so a bot that cannot find anywhere to place its ankh goes back to playing
--- the round instead of standing still with a single-use weapon in its hands.
local MAX_DURATION = 8

--- How close a relocation gets to its chosen spot before the ankh goes down.
local DESTINATION_REACH = 40
--- A relocation has to actually move the ankh somewhere, or picking it up is only a delay.
local MIN_RELOCATION_DIST = 300
--- The furthest a relocation may drag the owner from where the ankh was. The ankh heals whoever is close to it,
--- so it has to stay somewhere its owner can come back to.
local MAX_RELOCATION_DIST = 2500

--- The addon's own handler. Ownership is asked of it rather than tracked here: it is the only thing that knows
--- about the original-owner/current-owner split a stolen ankh creates.
---@return table?
local function getHandler()
    if not (PHARAOH_HANDLER and ROLE_PHARAOH) then return nil end

    return PHARAOH_HANDLER
end

--- Does the bot already own an ankh that is outside its loadout (in the world, or in somebody else's hands)?
--- That is both the state the addon refuses a second placement from and how this node knows it has finished.
---@param handler table
---@param bot Bot
---@return boolean
local function ownsAnkh(handler, bot)
    return handler:PlayerOwnsAnAnkhOutsideOfLoadout(bot) == true
end

--- Flat, world floor within the weapon's reach and in front of the bot.
---
--- The `HitWorld` half is the part that matters: a prop's top passes the flatness test, and `SWEP:AnkhStick`
--- then finds `HitWorld` false and gives up without saying anything, which would look like a wasted ankh.
---@param bot Bot
---@return Vector?
local function findGroundSpot(bot)
    local eyePos = bot:EyePos()
    local baseYaw = bot:EyeAngles().y

    for _, yaw in ipairs(PROBE_YAW_ANGLES) do
        local dir = Angle(0, baseYaw + yaw, 0):Forward()

        for _, dist in ipairs(PROBE_DISTANCES) do
            local probe = bot:GetPos() + dir * dist
            local floor = util.TraceLine({
                start = probe + Vector(0, 0, 16),
                endpos = probe - Vector(0, 0, 96),
                filter = bot,
                mask = MASK_SOLID
            })

            if floor.Hit and floor.HitWorld and floor.HitNormal:Dot(Vector(0, 0, 1)) >= MIN_FLATNESS then
                -- Now ask the question the weapon will ask: is the ray from the eye to that spot clear, flat
                -- and hitting the world? The endpoint is pushed a few units below the surface so the ray
                -- certainly lands on the floor rather than on its far edge.
                local aimSpot = floor.HitPos
                local check = util.TraceLine({
                    start = eyePos,
                    endpos = aimSpot - Vector(0, 0, 8),
                    filter = bot,
                    mask = MASK_SOLID
                })

                if check.Hit and check.HitWorld and eyePos:Distance(aimSpot) <= 100
                    and check.HitNormal:Dot(Vector(0, 0, 1)) >= MIN_FLATNESS then
                    return aimSpot
                end
            end
        end
    end

    return nil
end

--- Where a relocation should put the ankh: the nearest hiding spot that is far enough from the old one to be a
--- real move and close enough for the owner to keep using it.
---
--- Public because behaviors/moveankh.lua refuses to pick the ankh up unless this can find somewhere to put it:
--- a relocation with no destination costs the owner its respawn point for the ten seconds it takes to carry the
--- ankh somewhere and put it down again, which is worse than leaving the ankh where it is.
---@param bot Bot
---@param from Vector The position the ankh is being moved away from.
---@return Vector?
function PlaceAnkh.GetRelocationSpot(bot, from)
    if not from then return nil end

    local cache = TTTBots.Spots.CachedSpots
    if not (cache and cache["hiding"]) then return nil end

    local spots = TTTBots.Spots.GetSpotsInCategory("hiding")
    local best, bestDist = nil, nil

    for _, spot in ipairs(spots) do
        if spot:Distance(from) < MIN_RELOCATION_DIST then continue end

        local myDist = spot:Distance(bot:GetPos())
        if myDist > MAX_RELOCATION_DIST then continue end

        if not bestDist or myDist < bestDist then
            best, bestDist = spot, myDist
        end
    end

    return best
end

---@param bot Bot
---@return boolean
function PlaceAnkh.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_ankh") then return false end

    local handler = getHandler()
    if not handler then return false end

    -- Never while a fight is on: the weapon is single use, and an ankh placed in the open mid-fight is a gift
    -- to whoever is shooting at the bot. It is also the state in which the ankh weapon must not be held at all.
    if bot.attackTarget then return false end
    -- One ankh at a time. The addon would refuse the second placement anyway.
    if ownsAnkh(handler, bot) then return false end

    return bot:HasWeapon(ANKH_WEAPON)
end

---@param bot Bot
function PlaceAnkh.OnStart(bot)
    bot.ankhAttempts = 0
    bot.ankhSpot = nil
    bot.ankhNextTry = nil
    bot.ankhDeadline = CurTime() + MAX_DURATION

    return STATUS.RUNNING
end

---@param bot Bot
---@return integer
function PlaceAnkh.OnRunning(bot)
    if not TTTBots.Match.IsRoundActive() then return STATUS.FAILURE end

    local handler = getHandler()
    if not handler then return STATUS.FAILURE end

    if not bot:HasWeapon(ANKH_WEAPON) then
        -- The weapon consumes itself on a successful placement, so this is the success path; a weapon that is
        -- gone with no ankh behind it was taken from the bot, which is nothing left to do here.
        return ownsAnkh(handler, bot) and STATUS.SUCCESS or STATUS.FAILURE
    end

    local loco = bot:BotLocomotor()
    local inventory = bot:BotInventory()

    if CurTime() > (bot.ankhDeadline or 0) then return STATUS.FAILURE end

    -- A relocation walks to its spot first, ankh in hand, and only then looks for floor to place it on.
    local destination = bot.ankhDestination
    if not destination and bot.ankhRelocateFrom then
        destination = PlaceAnkh.GetRelocationSpot(bot, bot.ankhRelocateFrom)
        bot.ankhDestination = destination
    end

    if destination then
        bot.ankhDestination = destination

        if bot:GetPos():Distance(destination) > DESTINATION_REACH then
            loco:SetSprint(true)
            loco:SetGoal(destination)

            return STATUS.RUNNING
        end
    end

    loco:ClearGoal()
    loco:SetSprint(false)

    if ownsAnkh(handler, bot) then return STATUS.SUCCESS end

    -- Respect the weapon's own cooldown between presses; a press inside it does nothing at all.
    local now = CurTime()
    if bot.ankhNextTry and now < bot.ankhNextTry then return STATUS.RUNNING end

    local spot = bot.ankhSpot
    if not spot then
        spot = findGroundSpot(bot)

        if not spot then
            bot.ankhAttempts = bot.ankhAttempts + 1
            if bot.ankhAttempts > MAX_ATTEMPTS then return STATUS.FAILURE end

            -- Walk on a little: standing on the same square finds the same refused spot again.
            loco:SetGoal(bot:GetPos() + bot:GetForward() * 96)

            return STATUS.RUNNING
        end

        bot.ankhSpot = spot
    end

    -- The ankh weapon is WEAPON_EXTRA, which the inventory's auto-switch never equips, so pause it and take
    -- the weapon out by hand - exactly what behaviors/usehealthstation.lua does before it fires its own item.
    inventory:PauseAutoSwitch()
    inventory:SelectIfNotHeld(ANKH_WEAPON)
    loco:LookAt(spot)

    local held = bot:GetActiveWeapon()
    if IsValid(held) and held:GetClass() == ANKH_WEAPON then
        loco:StartAttack()

        -- One press per `RETRY_DELAY`, and the probe finds a fresh spot for the next one: if this press is
        -- refused by the room test, the same aim will be refused again.
        bot.ankhNextTry = now + RETRY_DELAY
        bot.ankhSpot = nil
        bot.ankhAttempts = bot.ankhAttempts + 1
    end

    return STATUS.RUNNING
end

---@param bot Bot
function PlaceAnkh.OnEnd(bot)
    local loco = bot:BotLocomotor()
    local inventory = bot:BotInventory()

    loco:StopAttack()
    loco:ClearGoal()
    loco:SetSprint(false)
    inventory:ResumeAutoSwitch()

    bot.ankhSpot = nil
    bot.ankhAttempts = nil
    bot.ankhNextTry = nil
    bot.ankhDeadline = nil
    bot.ankhDestination = nil
    bot.ankhRelocateFrom = nil
    bot.ankhRelocating = nil
end
