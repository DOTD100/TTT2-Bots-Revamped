--[[
Picks the owner's own Ankh back up, so it can be put down somewhere safer (TTT-2/ttt2-role_pha).

The addon's pickup is `ENT:UseOverride`, the handler the engine calls when the `+use` key is *released* on the
ankh. Its own gate, `PHARAOH_HANDLER:CanPickUpAnkh`, wants a live round, the player to be the ankh's current
owner, one of the two ankh roles, and the matching pickup convar - `ttt_ankh_pharaoh_pickup` ships at 1 and
`ttt_ankh_graverobber_pickup` at 0, so by default only a Pharaoh may move its own ankh at all.

Why this node calls that handler instead of pressing and releasing the key: `UseOverride` refuses to pick up "if
the player was previously converting" (`self.last_activator`), and pressing `+use` is exactly what sets
`last_activator`, because the ankh is CONTINUOUS_USE and the engine calls `ENT:Use` the moment the key goes down.
A bot that pressed the key would be refused on release. Calling the release handler directly - with the addon's
own `CanPickUpAnkh` as the gate - is the same call the engine would make at the same moment, without the press
that would disqualify it. (This is also why this file needs no IN_USE hold: see behaviors/stealankh.lua for the
one that does.)

When moving it is worth it: the ankh is the owner's respawn point *and* a slow heal, so leaving it alone is the
default and moving it is the exception. The exception is being found - any living non-ally with line of sight to
it can shoot it down (500 health by default) or take it, and a hiding spot is what the relocation is for. The
budget is deliberately small (see the constants): while the owner carries the ankh it has no respawn point and
no heal, so a bot that keeps second-guessing the spot is worse off than one that commits to it.
]]

TTTBots.Behaviors.MoveAnkh = {}

local lib = TTTBots.Lib

local MoveAnkh = TTTBots.Behaviors.MoveAnkh
MoveAnkh.Name = "Move Ankh"
MoveAnkh.Description = "Pick the ankh up and put it down somewhere hidden"
MoveAnkh.Interruptible = true

local STATUS = TTTBots.STATUS

local ANKH_ENTITY = "ttt_ankh"
local ANKH_WEAPON = "weapon_ttt_ankh"

--- The addon's own use trace is 100 units; this is how close the bot gets before reaching for the ankh.
local PICKUP_DIST = 48
--- How far away a non-ally counts as having found the ankh.
local EXPOSED_RANGE = 1500
--- The exposure test walks the alive players, and is worth at most this often.
local EXPOSURE_CHECK_INTERVAL = 1
--- The owner is without its respawn while it carries the ankh, so one relocation earns a long rest.
local RELOCATE_COOLDOWN = 45
--- A round's worth of second thoughts. See the header.
local MAX_RELOCATIONS_PER_ROUND = 2
--- Give up rather than hold the ankh weapon forever if the addon refuses the pickup (no room in the inventory,
--- for instance - it refuses with a message a bot cannot read).
local MAX_DURATION = 6

--- The addon's own handler, or nil when the role addon is not installed.
---@return table?
local function getHandler()
    if not (PHARAOH_HANDLER and ROLE_PHARAOH) then return nil end

    return PHARAOH_HANDLER
end

--- The ankh this bot owns, found the way the addon's own code finds an owner: the entity's `GetOwner`.
---@param bot Bot
---@return Entity?
local function findOwnAnkh(bot)
    for _, ankh in ipairs(ents.FindByClass(ANKH_ENTITY)) do
        if IsValid(ankh) and ankh:GetOwner() == bot then return ankh end
    end

    return nil
end

--- Has any living non-ally got line of sight to this ankh?
---
--- Only ever asked for the bot that owns an ankh, because `Validate` bails out on the ownership check first.
---@param bot Bot
---@param ankh Entity
---@return boolean
local function isExposed(bot, ankh)
    local ankhPos = ankh:GetPos()

    for _, other in ipairs(TTTBots.Match.AlivePlayers) do
        if other == bot or not lib.IsPlayerAlive(other) then continue end
        if TTTBots.Roles.IsAllies(bot, other) then continue end
        if other:GetPos():Distance(ankhPos) > EXPOSED_RANGE then continue end
        if lib.SeenThisTick(other, ankh) then return true end
    end

    return false
end

--- Is the ankh exposed, asked at most once per `EXPOSURE_CHECK_INTERVAL`? Both halves of the question are
--- loops over live data, and a bot that checks once a tick would answer the same thing five times a second.
---@param bot Bot
---@param ankh Entity
---@return boolean
local function isExposedNow(bot, ankh)
    if (bot.ankhExposureCheckedAt or 0) > CurTime() then return bot.ankhExposureWanted == true end

    bot.ankhExposureCheckedAt = CurTime() + EXPOSURE_CHECK_INTERVAL
    bot.ankhExposureWanted = isExposed(bot, ankh)

    return bot.ankhExposureWanted
end

--- Somewhere better to put the ankh, asked at call time rather than at load: the two behaviour files are
--- included from one directory and either may load first.
---@param bot Bot
---@param from Vector
---@return Vector?
local function getRelocationSpot(bot, from)
    local placeAnkh = TTTBots.Behaviors.PlaceAnkh
    if not (placeAnkh and placeAnkh.GetRelocationSpot) then return nil end

    return placeAnkh.GetRelocationSpot(bot, from)
end

---@param bot Bot
---@return boolean
function MoveAnkh.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_ankh") then return false end

    local handler = getHandler()
    if not handler then return false end

    if bot.attackTarget then return false end
    if (bot.ankhRelocations or 0) >= MAX_RELOCATIONS_PER_ROUND then return false end
    if (bot.ankhNextRelocateAt or 0) > CurTime() then return false end

    -- Only the ankh's current owner may pick it up.
    if not handler:PlayerControlsAnAnkh(bot) then return false end

    local ankh = findOwnAnkh(bot)
    if not ankh then return false end

    -- The addon's own gate: live round, ownership, the role, and the pickup convar for that role.
    if not handler:CanPickUpAnkh(ankh, bot) then return false end
    if not isExposedNow(bot, ankh) then return false end

    -- Nowhere better to put it means no move at all: picking it up and putting it straight back down is the
    -- owner losing its respawn for the time it takes to carry the ankh around.
    return getRelocationSpot(bot, ankh:GetPos()) ~= nil
end

---@param bot Bot
function MoveAnkh.OnStart(bot)
    local ankh = findOwnAnkh(bot)

    bot.ankhTarget = ankh
    -- Recorded now and handed to PlaceAnkh only if the pickup actually happens, so a refused pickup cannot
    -- leave a stale "move it away from here" behind.
    bot.ankhPickupFrom = IsValid(ankh) and ankh:GetPos() or nil
    bot.ankhDeadline = CurTime() + MAX_DURATION

    return STATUS.RUNNING
end

---@param bot Bot
---@return integer
function MoveAnkh.OnRunning(bot)
    if not TTTBots.Match.IsRoundActive() then return STATUS.FAILURE end

    -- The ankh is back in the inventory as its weapon: the pickup went through, and PlaceAnkh is the node that
    -- finishes the job (this is the only signal the addon gives a bot - a player would see it in their hands).
    if bot:HasWeapon(ANKH_WEAPON) then
        bot.ankhRelocateFrom = bot.ankhPickupFrom
        bot.ankhRelocations = (bot.ankhRelocations or 0) + 1
        bot.ankhNextRelocateAt = CurTime() + RELOCATE_COOLDOWN

        return STATUS.SUCCESS
    end

    if CurTime() > (bot.ankhDeadline or 0) then return STATUS.FAILURE end

    local handler = getHandler()
    if not handler then return STATUS.FAILURE end
    if not handler:PlayerControlsAnAnkh(bot) then return STATUS.FAILURE end

    local ankh = bot.ankhTarget
    if not (IsValid(ankh) and ankh:GetClass() == ANKH_ENTITY) then return STATUS.FAILURE end
    if not handler:CanPickUpAnkh(ankh, bot) then return STATUS.FAILURE end

    local loco = bot:BotLocomotor()

    if bot:GetPos():Distance(ankh:GetPos()) > PICKUP_DIST then
        loco:SetSprint(true)
        loco:SetGoal(ankh:GetPos())

        return STATUS.RUNNING
    end

    loco:ClearGoal()
    loco:SetSprint(false)
    loco:PauseRepel()
    loco:LookAt(ankh:WorldSpaceCenter())

    -- The engine's release handler, with the addon's own gate checked above and without the press that would
    -- have set `last_activator` and had this refused. See the header.
    ankh:UseOverride(bot)

    return bot:HasWeapon(ANKH_WEAPON) and STATUS.SUCCESS or STATUS.RUNNING
end

---@param bot Bot
function MoveAnkh.OnEnd(bot)
    local loco = bot:BotLocomotor()

    loco:ClearGoal()
    loco:SetSprint(false)
    loco:ResumeRepel()

    bot.ankhTarget = nil
    bot.ankhPickupFrom = nil
    bot.ankhDeadline = nil
    -- `ankhRelocateFrom` and `ankhDestination` are deliberately left alone on a successful pickup: they are how
    -- this node hands its destination over to behaviors/placeankh.lua, which clears them when it has placed.
end

--- The budget above is per *round*, so it is reset with the round rather than per life. A Pharaoh who died and
--- came back at its ankh has not moved the ankh any less, and a reset on respawn would hand it a fresh budget
--- every time it died - which is exactly the loop the cap exists to stop.
hook.Add("TTTBeginRound", "TTTBots.Ankh.RelocationBudget", function()
    for _, bot in ipairs(TTTBots.Bots) do
        if not IsValid(bot) then continue end

        bot.ankhRelocations = nil
        bot.ankhNextRelocateAt = nil
        bot.ankhExposureCheckedAt = nil
        bot.ankhExposureWanted = nil
    end
end)
