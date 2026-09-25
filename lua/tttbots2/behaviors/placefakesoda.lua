--[[
Places a Fake Soda can (mexikoedi/ttt2_fake_soda) where a player will find it.

That addon's decoy is the weapon `weapon_ttt2_fake_soda`: a traitor's can that looks exactly like a Super
Soda can and poisons whoever drinks it (health, armour, credits, speed, damage dealt, fire rate or jump
height, depending on which of its seven cans it happened to be). It holds `ttt2_fake_soda_amount` cans
(3 by default) and its primary attack drops one, but the *mode* is the whole trick: the weapon starts in
throw mode, and pressing reload toggles it to place mode. Placing traces 100 units along the **aim vector**
and only accepts a mostly-horizontal surface (hit normal z >= 0.5), which is why this behaviour walks the
bot to the spot, faces it, and presses attack exactly once.

Where to put it is the human part, and it is the same instinct a player has: a can is worth drinking where
cans are. So:

1. **Where a real can just was.** The drink behaviour records the position of every can it empties, and the
   first thing this behaviour tries is dropping the decoy on that spot - the one place somebody has just
   been reminded that a can lives. (The real can is gone by then: the Super Soda addon removes it on pickup.)
2. **Beside a real can that is still there.** A can on the floor has neighbours drop cans next to it.

Both are then checked for a surface to stand it on and for not stacking it on top of a can that is already
there. Without either - a map with no cans left - the bot simply does not spend the trip.

Inert without the addon: the weapon class and the addon's own FAKESODA table have to exist.
]]

TTTBots.Behaviors.PlaceFakeSoda = {}

local lib = TTTBots.Lib

local PlaceFakeSoda = TTTBots.Behaviors.PlaceFakeSoda
PlaceFakeSoda.Name = "Place Fake Soda"
PlaceFakeSoda.Description = "Leave a fake soda can where players look for cans"
PlaceFakeSoda.Interruptible = true

local STATUS = TTTBots.STATUS

---@class Bot
---@field sodaDrankPos Vector? Where the drink behaviour emptied its last can.
---@field sodaDrankAt number? When that was.
---@field fakeSodaSpot Vector? The spot this behaviour decided to leave a can on.
---@field fakeSodaStartedAt number? When the trip began, so it can give up.
---@field fakeSodaCooldown number? Until this time, do not start another placement.
---@field fakeSodaAttacking boolean? Set between pressing attack and checking whether it worked.
---@field fakeSodaClipBefore number? The can count before that press.

local WEP = "weapon_ttt2_fake_soda"

--- The trace in the weapon's own place mode runs 100 units from the eyes, so the bot has to stand inside
--- that - and the eye is about 64 units up, which is why this is well under 100.
local PLACE_RANGE = 60
--- How close the bot's actual aim has to be to the spot before it presses the button. The placement trace
--- uses the aim vector, so pressing early would put the can on whatever the bot happens to be facing.
local AIM_DOT = 0.97
--- Real cans worth walking to, and how recently a can has to have been drunk for its spot to still count.
local SEARCH_RADIUS = 2500
local DRANK_MEMORY = 60
--- Nothing gets placed within this of a can that is already there, or the two models overlap and the decoy
--- stops looking like a can somebody dropped.
local CAN_CLEARANCE = 28
--- A placement needs a surface at least this horizontal. Same rule as the weapon's own trace.
local SURFACE_Z = 0.5
--- Long enough to walk to a can across most maps, short enough that a bot does not spend the round trying.
local GIVE_UP_TIME = 20
--- Keeps a bot from spending all three of its cans in as many seconds: the first placement is the one that
--- matters, the rest are for later in the round.
local COOLDOWN = 25

--- Offsets tried around a real can, so the decoy lands *next to* it rather than inside it.
local OFFSETS = {
    Vector(48, 0, 0),
    Vector(-48, 0, 0),
    Vector(0, 48, 0),
    Vector(0, -48, 0),
}

---@return boolean
function PlaceFakeSoda.IsAvailable()
    return weapons.Get(WEP) ~= nil and FAKESODA ~= nil
end

---@param bot Bot
---@return Weapon? wep
function PlaceFakeSoda.GetWeapon(bot)
    if not bot:HasWeapon(WEP) then return nil end

    local wep = bot:GetWeapon(WEP)
    if not (IsValid(wep) and wep.Clip1 and wep:Clip1() > 0) then return nil end

    return wep
end

---@param ent Entity
---@return boolean
local function isASoda(ent)
    if not IsValid(ent) then return false end

    return string.find(ent:GetClass(), "soda") ~= nil
end

--- Is there a can on the floor the bot could leave a decoy beside? Used by the purchase, so that a traitor
--- only pays a credit for the decoy while there is somewhere to hide it.
---@param ply Player
---@return boolean
function PlaceFakeSoda.HasDecoyGround(ply)
    if not PlaceFakeSoda.IsAvailable() then return false end

    for _, can in ipairs(ents.FindByClass("soda_*")) do
        if IsValid(can) then return true end
    end

    return false
end

--- The surface point nearest a candidate position, or nil when there is nothing to stand a can on there or
--- something is already sitting on it.
---@param bot Bot
---@param candidate Vector
---@return Vector?
function PlaceFakeSoda.GetGroundSpot(bot, candidate)
    local tr = util.TraceLine({
        start = candidate + Vector(0, 0, 64),
        endpos = candidate - Vector(0, 0, 64),
        filter = bot,
        mask = MASK_NPCWORLDSTATIC,
    })
    if not tr.Hit then return nil end
    if tr.HitNormal.z < SURFACE_Z then return nil end

    for _, ent in ipairs(ents.FindInSphere(tr.HitPos + Vector(0, 0, 8), CAN_CLEARANCE)) do
        if ent ~= bot and isASoda(ent) then return nil end
    end

    return tr.HitPos
end

--- The nearest real can worth walking to, or nil.
---@param bot Bot
---@return Entity?
function PlaceFakeSoda.FindNearbyCan(bot)
    local myPos = bot:GetPos()
    local best, bestDist = nil, nil

    for _, can in ipairs(ents.FindByClass("soda_*")) do
        if not IsValid(can) then continue end

        local dist = myPos:Distance(can:GetPos())
        if dist > SEARCH_RADIUS then continue end
        if not bestDist or dist < bestDist then
            best, bestDist = can, dist
        end
    end

    return best
end

--- Where to leave this can, or nil when there is nowhere worth leaving one.
---
--- The spot a real can was just drunk from comes first, then the space beside a can that is still there.
---@param bot Bot
---@return Vector?
function PlaceFakeSoda.FindSpot(bot)
    local drankPos = bot.sodaDrankPos
    if drankPos and (CurTime() - (bot.sodaDrankAt or 0)) < DRANK_MEMORY then
        local spot = PlaceFakeSoda.GetGroundSpot(bot, drankPos)
        if spot then return spot end
    end

    local can = PlaceFakeSoda.FindNearbyCan(bot)
    if not can then return nil end

    for _, offset in ipairs(OFFSETS) do
        local spot = PlaceFakeSoda.GetGroundSpot(bot, can:GetPos() + offset)
        if spot then return spot end
    end

    return nil
end

---@param bot Bot
---@return boolean
function PlaceFakeSoda.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("place_fake_soda") then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not PlaceFakeSoda.IsAvailable() then return false end
    if (bot.fakeSodaCooldown or 0) > CurTime() then return false end

    -- A fight comes first, and so does anything else the bot was in the middle of: a decoy is a quiet-round
    -- errand, not something to stop for.
    if bot.attackTarget ~= nil then return false end
    if not PlaceFakeSoda.GetWeapon(bot) then return false end

    local spot = PlaceFakeSoda.FindSpot(bot)
    if not spot then return false end

    bot.fakeSodaSpot = spot
    return true
end

---@param bot Bot
---@return BStatus
function PlaceFakeSoda.OnStart(bot)
    bot.fakeSodaStartedAt = CurTime()
    bot.fakeSodaAttacking = false

    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function PlaceFakeSoda.OnRunning(bot)
    local loco = bot:BotLocomotor()
    local wep = PlaceFakeSoda.GetWeapon(bot)
    local spot = bot.fakeSodaSpot

    if not (loco and wep and spot) then return STATUS.FAILURE end
    if (CurTime() - (bot.fakeSodaStartedAt or CurTime())) > GIVE_UP_TIME then return STATUS.FAILURE end

    -- The decoy has to stay in hand to be placed at all, and the inventory would swap it away for a gun.
    local inv = bot:BotInventory()
    if inv then inv:PauseAutoSwitch() end
    bot:SelectWeapon(WEP)

    -- Place mode. A player presses reload; in the weapon's default throw mode the primary attack hurls the
    -- can instead of putting it down, which would defeat the point of choosing a spot.
    if not wep.Reloaded then
        wep:Reload()
        return STATUS.RUNNING
    end

    -- Last tick we pressed the button. Did it put a can down? If not (an awkward surface, the weapon's own
    -- fire delay), fall through and try again while the clock lasts.
    if bot.fakeSodaAttacking then
        loco:StopAttack()
        bot.fakeSodaAttacking = false

        if wep:Clip1() < (bot.fakeSodaClipBefore or 0) then return STATUS.SUCCESS end
    end

    if bot:GetPos():Distance(spot) > PLACE_RANGE then
        loco:SetGoal(spot)
        loco:LookAt(spot + Vector(0, 0, 8))
        return STATUS.RUNNING
    end

    loco:StopMoving()
    loco:LookAt(spot + Vector(0, 0, 8))

    -- The placement traces along the aim vector, so wait until the bot is really looking at the spot rather
    -- than pressing at whatever it is walking past.
    local toSpot = spot + Vector(0, 0, 8) - bot:EyePos()
    if toSpot:LengthSqr() < 1 then return STATUS.RUNNING end
    toSpot:Normalize()

    if bot:GetAimVector():Dot(toSpot) < AIM_DOT then return STATUS.RUNNING end

    bot.fakeSodaClipBefore = wep:Clip1()
    bot.fakeSodaAttacking = true
    loco:StartAttack()

    return STATUS.RUNNING
end

---@param bot Bot
function PlaceFakeSoda.OnEnd(bot)
    bot.fakeSodaSpot = nil
    bot.fakeSodaStartedAt = nil
    bot.fakeSodaAttacking = false
    bot.fakeSodaClipBefore = nil
    bot.fakeSodaCooldown = CurTime() + COOLDOWN

    -- The spot a can was drunk from has served its purpose once a decoy is on it, and reusing it would
    -- stack cans on one another.
    bot.sodaDrankPos = nil
    bot.sodaDrankAt = nil

    local loco = bot:BotLocomotor()
    if loco then
        loco:StopAttack()
        loco:StopMoving()
    end

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end

---@param bot Bot
function PlaceFakeSoda.OnSuccess(bot) end

---@param bot Bot
function PlaceFakeSoda.OnFailure(bot) end
