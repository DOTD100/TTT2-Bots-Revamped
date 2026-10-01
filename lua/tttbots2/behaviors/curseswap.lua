--[[
Hands the Cursed's curse to somebody else.

The Cursed (AaronMcKenney/ttt2-role_curs) has no team and cannot win: its own hooks zero every point of damage
it deals to a player, it has no shop, and it comes back from the dead `ttt2_cursed_seconds_until_respawn`
seconds after each death. The only thing it can do with a round is leave the role, and the only way out is a
role swap with another player. The addon ships two ways to do that, and *both* of them are things a bot cannot
reach on its own:

  * **Tagging** is a keypress. The client binds a key, sends "TTT2CursedSendTagRequest", and the server traces
    from the sender's eyes and calls `CURS_DATA.AttemptSwap(ply, tgt, dist)` with the distance that trace
    covered. A bot can never send that message - but `CURS_DATA` is an ordinary table of server-side
    functions, so this behaviour makes the call the message makes, with the same trace and the same distance.
  * **The RoleSwap Deagle** (`weapon_ttt2_role_swap_deagle`) swaps inside its bullet's callback, at any range,
    and refills itself on a *client-side* timer. Its `SWEP.Kind` is WEAPON_EXTRA, which this addon's inventory
    never equips, so the weapon is selected by hand here; and because a bot has no client, the refill its
    clients run is run for it here instead (see UpdateDeagleRefill) rather than leaving the weapon empty for
    the rest of the round.

The addon's own gate decides who can be tagged - `CURS_DATA.CanSwapRoles`, which is every rule it applies:
both players alive and in a round, the target not carrying "no backsies" from a swap they just made, the role
and team actually differing, and the detective convar. Nothing about who is worth tagging is decided here.

Fairness: the walk to a target uses the position the bot's *memory* has - seen or heard, and only while that
is fresher than CHASE_MEMORY - never the live position of somebody it cannot see. That is the same rule the
attack behaviour and the Shanker's stalk follow, and it is why the ranged route needs line of sight like
every other shot in this addon.
]]

TTTBots.Behaviors.CurseSwap = {}

local lib = TTTBots.Lib

---@class BCurseSwap
local CurseSwap = TTTBots.Behaviors.CurseSwap
CurseSwap.Name = "CurseSwap"
CurseSwap.Description = "Hand the curse to another player"
CurseSwap.Interruptible = true

local STATUS = TTTBots.STATUS

---@class Bot
---@field curseTarget Player? The player we are trying to hand the curse to.
---@field curseNextScan number? When a bot with no target may look for another one.
---@field curseDeagleRefillAt number? When our RoleSwap Deagle gets its round back.
---@field curseFiring boolean? Between pressing attack and the round being spent.

local DEAGLE = "weapon_ttt2_role_swap_deagle"

--- How long a remembered position stays worth walking to once the target is out of sight. The figure
--- Attack.Seek and the Shanker's stalk use: long enough to cross a corridor or two, short enough that the
--- bot does not tour the map on a trail that has gone cold.
local CHASE_MEMORY = 4
--- How often a bot with no target rescans for one. Every candidate costs a visibility trace, and a Cursed
--- has nothing else it needs to do, so there is no reason to look more often than this.
local RETARGET_INTERVAL = 1

--- Is this player the Cursed? The addon's own test is `ply:GetSubRole() == ROLE_CURSED`, and TTT2's ROLE_
--- constant for a role is its numeric index, so this is that comparison with a guard for the addon being
--- absent (`ROLE_CURSED` is only a global once the role has registered).
---@param ply Player?
---@return boolean
local function isCursed(ply)
    if not (ROLE_CURSED and IsValid(ply) and ply:IsPlayer()) then return false end

    return ply:GetSubRole() == ROLE_CURSED
end

--- Is the addon's own API here? `CURS_DATA` and its two functions are the entire interface used below.
---@return boolean
local function hasCursedAPI()
    return CURS_DATA ~= nil and isfunction(CURS_DATA.CanSwapRoles) and isfunction(CURS_DATA.AttemptSwap)
end

--- How far the tag reaches, straight off the addon's convar.
---@return number
local function getTagDist()
    local cv = GetConVar("ttt2_cursed_tag_dist")

    return (cv and cv:GetInt()) or 150
end

--- The switch the other in-game diagnostics use, so a test session can see which of the two routes the bot
--- took and whether the addon accepted it.
---@param bot Bot
---@param message string
local function debugLog(bot, message)
    if not lib.GetConVarBool("debug_misc") then return end

    print(string.format("[ttt2bots] %s (Cursed): %s", bot:Nick(), message))
end

--- Where to walk to reach them, and whether that is them in sight right now.
---
--- Read through the memory rather than off the player for anything we cannot see, so this role does not track
--- somebody through walls - the same rule the attack behaviour and the Shanker's stalk follow.
---@param bot Bot
---@param target Player
---@return Vector? pos
---@return boolean visible
function CurseSwap.GetChasePos(bot, target)
    local memory = bot:BotMemory()
    if not memory then return nil, false end

    if lib.CanSeeEntity(bot, target) then
        memory:UpdateKnownPositionFor(target)

        return target:GetPos(), true
    end

    if (CurTime() - memory:GetLastSeenTime(target)) > CHASE_MEMORY then return nil, false end

    return memory:GetKnownPositionFor(target), false
end

--- The RoleSwap Deagle, if the bot is carrying one with its round still in it.
---
--- The addon hands the weapon to whoever holds the role and strips it again when the role is handed over, so
--- whose it is needs no tracking here - and an empty one is no use, which is what the clip test says.
---@param bot Bot
---@return Weapon?
function CurseSwap.GetLoadedDeagle(bot)
    if not bot:HasWeapon(DEAGLE) then return nil end

    local wep = bot:GetWeapon(DEAGLE)
    if not (IsValid(wep) and wep.Clip1 and wep:Clip1() > 0) then return nil end

    return wep
end

--- Finishes the refill the addon's client-side timer would have done.
---
--- On a failed shot the server tells the shooter's *client*, which starts a timer and, when it ends, sends
--- "ttt_role_swap_deagle_refilled" back so the weapon is given its single round again. A bot has no client, so
--- that round trip never happens and its deagle would be one shot per round instead of one attempt per
--- `ttt2_role_swap_deagle_refill_time`. This runs the same cooldown on the server for the bot, which puts it
--- on exactly the footing the convar describes for a player.
---@param bot Bot
function CurseSwap.UpdateDeagleRefill(bot)
    local refillAt = bot.curseDeagleRefillAt
    if not refillAt then return end
    if CurTime() < refillAt then return end

    bot.curseDeagleRefillAt = nil

    local wep = bot:GetWeapon(DEAGLE)
    if IsValid(wep) and wep.Clip1 and wep:Clip1() <= 0 then
        wep:SetClip1(1)
        debugLog(bot, "RoleSwap Deagle refilled")
    end
end

--- Starts that cooldown. Called once the shot has left, so a *miss* costs what the addon says it costs.
---@param bot Bot
function CurseSwap.NoteDeagleSpent(bot)
    if bot.curseDeagleRefillAt then return end

    local cv = GetConVar("ttt2_role_swap_deagle_refill_time")
    local cooldown = (cv and cv:GetInt()) or 0
    if cooldown <= 0 then return end

    bot.curseDeagleRefillAt = CurTime() + cooldown
end

--- The nearest player the addon would let us swap with, or nil.
---
--- `CURS_DATA.CanSwapRoles` is asked with a distance of zero, which turns it into "would this swap be legal at
--- point-blank range" - the round state, both players alive, the target not already carrying "no backsies" for
--- a swap they just made, the role and team actually differing, and the detective convar. That is the addon's
--- own answer to who can be tagged, so nothing is added to it here; the only thing this skips is *another*
--- Cursed, because the addon refuses that swap with a warning and nothing would come of it.
---
--- Somebody in sight beats somebody merely remembered, wherever they are: the visible one can be handed the
--- curse where they stand, while the remembered one is a walk to somewhere they may no longer be. Among
--- equals, the nearest.
---@param bot Bot
---@return Player?
function CurseSwap.FindTarget(bot)
    local myPos = bot:GetPos()
    local bestVisible, bestVisibleDist = nil, nil
    local bestKnown, bestKnownDist = nil, nil

    for _, other in ipairs(TTTBots.Match.AlivePlayers) do
        if other == bot then continue end
        if not lib.IsPlayerAlive(other) then continue end
        if isCursed(other) then continue end
        if not CURS_DATA.CanSwapRoles(bot, other, 0) then continue end

        local chasePos, visible = CurseSwap.GetChasePos(bot, other)
        if not chasePos then continue end

        local dist = myPos:Distance(chasePos)

        if visible then
            if not bestVisibleDist or dist < bestVisibleDist then
                bestVisible, bestVisibleDist = other, dist
            end
        elseif not bestKnownDist or dist < bestKnownDist then
            bestKnown, bestKnownDist = other, dist
        end
    end

    return bestVisible or bestKnown
end

--- Validate the behavior
---
--- The refill is ticked before every early return on purpose: it is a timer on the bot rather than a property
--- of having a target, so it has to keep running while the bot wanders with an empty deagle in its inventory.
---@param bot Bot
---@return boolean
function CurseSwap.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not isCursed(bot) then return false end
    if not hasCursedAPI() then return false end

    CurseSwap.UpdateDeagleRefill(bot)

    -- Keep the target we already have while it is still taggable and still remembered: a rescan costs a
    -- visibility trace per alive player, and there is nothing to gain by shopping around mid-walk.
    local target = bot.curseTarget
    if IsValid(target) and lib.IsPlayerAlive(target) and CURS_DATA.CanSwapRoles(bot, target, 0) then
        local chasePos = CurseSwap.GetChasePos(bot, target)
        if chasePos then return true end
    end

    if CurTime() < (bot.curseNextScan or 0) then return false end
    bot.curseNextScan = CurTime() + RETARGET_INTERVAL

    bot.curseTarget = CurseSwap.FindTarget(bot)

    return bot.curseTarget ~= nil
end

--- Called when the behavior is started
---@param bot Bot
---@return BStatus
function CurseSwap.OnStart(bot)
    bot.curseFiring = false

    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
---@param bot Bot
---@return BStatus
function CurseSwap.OnRunning(bot)
    local target = bot.curseTarget
    if not (IsValid(target) and lib.IsPlayerAlive(target)) then return STATUS.FAILURE end

    -- The swap changes *our* role, so once it has landed there is nothing left for this behaviour to do - and
    -- it is what the tests further down are protecting, since nothing else here would notice.
    if not isCursed(bot) then return STATUS.SUCCESS end
    if not CURS_DATA.CanSwapRoles(bot, target, 0) then return STATUS.FAILURE end

    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    -- The deagle's single round, watched rather than repeated: the clip being empty is what says the shot
    -- left, and an empty deagle is what sends the bot back to walking.
    if bot.curseFiring then
        loco:StopAttack()
        bot.curseFiring = false

        if not CurseSwap.GetLoadedDeagle(bot) then
            CurseSwap.NoteDeagleSpent(bot)

            return STATUS.RUNNING
        end
    end

    local tagDist = getTagDist()
    local distToTarget = bot:EyePos():Distance(target:GetPos())

    loco:LookAt(TTTBots.Behaviors.AttackTarget.GetTargetBodyPos(target))

    -- The trace the tag key takes, taken the same way: from the eyes, with the mask the addon uses. It reads
    -- the bot's *view angles*, which the locomotor interpolates towards the look goal over the following
    -- ticks, so it is false for a moment after the goal changes - which is the wait a swing or a shot needs
    -- anyway.
    local eyeTrace = bot:GetEyeTrace(MASK_SHOT_HULL)
    local traceHit = (eyeTrace.Entity == target)

    -- Looking at them and inside the tag's reach: this is the keypress, verbatim.
    if traceHit then
        local traceDist = eyeTrace.StartPos:Distance(eyeTrace.HitPos)

        if traceDist <= tagDist then
            if CURS_DATA.AttemptSwap(bot, target, traceDist) then
                debugLog(bot, "tagged " .. target:Nick())

                return STATUS.SUCCESS
            end

            -- The addon refused a swap its own gate had just allowed, which happens when the roles and teams
            -- turn out to match after all. Standing here repeating it would never get anywhere, so take
            -- another look at who else is around.
            return STATUS.FAILURE
        end
    end

    -- Out of the tag's reach, in sight, and holding the ranged route: take the shot instead of walking the
    -- map after somebody who can see the Cursed coming. The deagle's own swap has no range limit.
    if distToTarget > tagDist and lib.SeenThisTick(bot, target) then
        local inv = bot:BotInventory()
        local deagle = CurseSwap.GetLoadedDeagle(bot)

        if inv and deagle then
            inv:PauseAutoSwitch()
            -- `SelectIfNotHeld`, never a bare SelectWeapon: re-selecting the weapon already in hand makes the
            -- engine deploy it again, and a weapon mid-deploy cannot fire.
            inv:SelectIfNotHeld(DEAGLE)

            loco:StopMoving()

            if traceHit then
                bot.curseFiring = true
                loco:StartAttack()
            end

            return STATUS.RUNNING
        end
    end

    -- Otherwise close the distance on foot and tag. At a run: this role's own addon gives it more speed and
    -- cheaper stamina than anybody else precisely so it can catch somebody, and a walk can never catch up
    -- with a walk - the same reason attacktarget.lua runs a melee weapon into its range.
    local chasePos = CurseSwap.GetChasePos(bot, target)
    if not chasePos then return STATUS.FAILURE end

    loco:SetSprint(true)
    loco:SetGoal(chasePos)

    return STATUS.RUNNING
end

--- Called when the behavior succeeds or fails. Useful for cleanup, as it is always called once the behavior is a) interrupted, or b) returns a success or failure state.
---@param bot Bot
function CurseSwap.OnEnd(bot)
    bot.curseTarget = nil
    bot.curseNextScan = nil
    bot.curseFiring = nil
    -- Left alone: `bot.curseDeagleRefillAt`, which belongs to the weapon rather than to this attempt.

    local loco = bot:BotLocomotor()
    if loco then
        loco:StopAttack()
        -- Clears the goal and the forces. The sprint is a latch of its own and has to be handed back
        -- explicitly, or the bot keeps running once its role has been handed over.
        loco:StopMoving()
        loco:SetSprint(false)
    end

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end

---@param bot Bot
function CurseSwap.OnSuccess(bot) end

---@param bot Bot
function CurseSwap.OnFailure(bot) end
