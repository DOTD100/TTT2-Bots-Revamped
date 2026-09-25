---@class BHuntTarget
TTTBots.Behaviors.HuntTarget = {}

local lib = TTTBots.Lib
local HuntTarget = TTTBots.Behaviors.HuntTarget
HuntTarget.Name = "HuntTarget"
HuntTarget.Description = "Hunt the victim the gamemode assigned to this role"

--[[
This is deliberately NOT a tree node. It is a passive target provider for roles that are handed a designated
victim, which is how both the Hitman and the Executioner work, and it exists so those roles do not each need
their own targeting logic.

Where the victim comes from: `Player:GetTargetPlayer()`. That is TTT2's *spectating* target - its own
documentation calls it "the target a Player is spectating", the HUD uses it to show who you are looking at,
and its other writers are client-side - so it is not a contract API. It is only meaningful here because the
role's own addon publishes its contract through it, which is worth re-checking in game before trusting it: if
that addon sets it for humans only, this provider never sees a victim and the role has no targeting at all.

Assigning bot.attackTarget is all that is needed: FightBack is the first node of the traitor tree and leads
with AttackTarget, which validates as soon as the target is a living player. Combat therefore stays in one
place, and this file only decides *who* to fight.

**Filling an empty slot only is the whole discipline.** `SetAttackTarget` treats every change as a brand new
acquisition - `locomotor:OnNewTarget` applies a 5x look-speed burst and re-arms the reaction delay the bot has
to wait out before firing - so a provider that re-asserts its victim every tick fights with `Attack.OnEnd`,
which ends the target, and the bot flickers without ever settling into a shot. Hence: refresh the victim's
memory entry every tick, but only *claim* the attack slot when the bot has nobody.
]]

local HUNT_INTERVAL = 1 / TTTBots.Tickrate

---@param bot Bot
---@return Player? victim
local function getAssignedVictim(bot)
    local victim = bot:GetTargetPlayer()
    if not (IsValid(victim) and victim ~= bot and lib.IsPlayerAlive(victim)) then return nil end

    return victim
end

--- Prints what this provider does and why, so a target set/clear loop can be watched in a live session
--- instead of inferred. Temporary: gated on ttt_bot_debug_misc, and it only ever speaks for roles that hunt.
--- Delete once the loop is confirmed or gone.
---@param bot Bot
---@param message string
local function debugLog(bot, message)
    if not lib.GetConVarBool("debug_misc") then return end
    print(string.format("[ttt2bots] HuntTarget %s: %s", bot:Nick(), message))
end

---@param bot Bot
local function hunt(bot)
    if not lib.IsPlayerAlive(bot) then return end

    -- Checked before the role lookup because it is much cheaper and most bots have no assigned victim.
    local victim = getAssignedVictim(bot)
    if not victim then return end

    local role = TTTBots.Roles.GetRoleFor(bot)
    if not (role and role:GetHuntsTarget()) then return end

    -- Attack.Seek navigates from memory alone (it ignores the position it is handed), so what the gamemode
    -- told this role has to be kept written there, or the trail goes cold and the bot stops closing in. It
    -- sits above the reasons to leave the attack slot alone because it is not part of claiming that slot.
    bot.components.memory:UpdateKnownPositionFor(victim)

    -- Somebody already in hand is left alone, whether or not we can see them this instant. The condition
    -- used to also demand `bot:Visible(current)`, which handed the enemy behind cover away every tick - and
    -- each handover ended AttackTarget (clearing the target) and cost a fresh acquisition when this put it
    -- back. That is a Hitman flicking without ever landing a shot.
    local current = bot.attackTarget
    if IsValid(current) and lib.IsPlayerAlive(current) then return end

    -- A victim this bot could never hurt is not a target. SetAttackTarget refuses allies and damage-immune
    -- roles anyway, so asking is a wasted call every tick - and it means a contract on a Jester or a Swapper
    -- (the jesters' team, which the Hitman lists as allied) is left alone rather than fought over all round.
    if TTTBots.Roles.IsAllies(bot, victim) or TTTBots.Roles.IsPlayerDamageImmune(victim) then
        debugLog(bot, "cannot hurt " .. victim:Nick())
        return
    end

    debugLog(bot, "claiming " .. victim:Nick())
    bot:SetAttackTarget(victim)
end

-- Gated to the bot tick, like the other passive providers.
local nextHunt = 0
hook.Add("Think", "TTTBots.hunttarget", function()
    local time = CurTime()
    if time < nextHunt then return end
    nextHunt = time + HUNT_INTERVAL

    for _, bot in ipairs(TTTBots.Bots or {}) do
        if not IsValid(bot) then continue end
        hunt(bot)
    end
end)
