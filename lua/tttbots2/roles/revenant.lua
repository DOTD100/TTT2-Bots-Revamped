if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_REVENANT then return false end

--[[
The Revenant (TaintedEnergy/ttt2-role-reven) is one role in two states, and the state is not the subrole - it is
`ply.revenant_state`, kept by the addon and read live here:

  * **state 1 (or nil)** - what it spawns as. It is an innocent: `defaultTeam = TEAM_INNOCENT`, no shop, no
    credits, `unknownTeam`, and `TTT2SpecialRoleSyncing` shows it as ROLE_INNOCENT to itself and ROLE_NONE to
    everybody else, so nobody - player or bot - can tell what it is. Its corpse is rewritten to an innocent's in
    the addon's own `TTTCanSearchCorpse`/`TTT2ConfirmPlayer` hooks.
  * **state 2** - what its death turns it into. `TTT2PostPlayerDeath` calls `ply:Revive(ttt2_reven_revival_time)`
    and the revive callback sets state 2 and calls **`ply:UpdateTeam(TEAM_REVENANT)`**, its own custom team
    (`roles.InitCustomTeam`): a neutral killer on nobody's side, with 1 + `ttt2_reven_damage_bonus` damage. From
    that moment the addon stops disguising it, so its team and role are public.

The whole design of this profile follows from that switch:

  * **The team change is handled by `SetLovesTeammates(true)`** and nothing else. `TTTBots.Roles.IsAllies` has a
    branch for roles whose team "is adjusted on the fly": if either side loves teammates, the two players are
    allies exactly when `ply:GetTeam()` matches - which is live. So in state 1 the Revenant's team is the
    innocents' and it is their ally (the disguise holds, and a bot will not fire at it), and in state 2 its team
    is TEAM_REVENANT and it is allied with nobody. Both the static allied sets are cleared deliberately: leaving
    `TEAM_INNOCENT` in the allied-teams table would keep a *revived* Revenant treating innocents as friends, and
    that is the entire second half of the role.
  * **The aggression cannot be a profile flag**, because a flag is declared once and this role is two roles. It
    lives in the hunt below, keyed on the state, the same way the Shinigami's hunt drives its post-death form.
  * **The reveal** is the other half of "the addon stops hiding it": a bot cannot read a HUD, so the suspicion
    system is told what the HUD says (see revealRevivedRevenants).

Two upstream notes, recorded rather than worked around: their `ScalePlayerDamage` checks `ply.revenant_state` -
the *victim's* state, not the attacker's - so the damage bonus only lands when one revived Revenant shoots
another, and `dmginfo:GetAttacker()` is used without a player check, so an environmental kill would error in
their hook. Neither is ours to fix, and neither is mirrored here.
]]

local lib = TTTBots.Lib

local revenant = TTTBots.RoleData.New("revenant", TEAM_INNOCENT)
revenant:SetDefusesC4(true) -- it is an ordinary innocent for as long as it lives
revenant:SetPlantsC4(false)
revenant:SetCanHaveRadar(false)
revenant:SetCanCoordinate(false) -- unknownTeam: it does not know the traitors to coordinate with
revenant:SetStartsFights(false) -- state 1 must not pick fights; the state 2 hunt below is what does
revenant:SetUsesSuspicion(true)
revenant:SetCanHide(true)
revenant:SetCanSnipe(true)
revenant:SetTeam(TEAM_INNOCENT)
revenant:SetBTree(TTTBots.Behaviors.DefaultTrees.innocent)
revenant:SetAlliedRoles({})
revenant:SetAlliedTeams({})
-- The live team rule: see the header. This is what makes the disguise and the revenge both work.
revenant:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(revenant)

--- The weights this role's reveal uses. Registered through the component (not only at load) because the
--- component table is rebuilt whenever the addon is reloaded, and a rebuild after this file has run would leave
--- the live component without the key while this file's hook stayed installed. See roles/paranoid.lua, which
--- documents the same trap.
local SUSPICION_REASONS = {
    RevenantRevealed = 10, -- A revived Revenant, which the addon itself has stopped disguising
}

---@param morality CMorality
local function registerSuspicionReasons(morality)
    local values = morality.SUSPICIONVALUES or {}
    for reason, value in pairs(SUSPICION_REASONS) do
        if values[reason] ~= value then
            morality:RegisterSuspicionReason(reason, value)
        end
    end
end

registerSuspicionReasons(TTTBots.Components.Morality)

--- How often the hunt runs, and how often the reveal is looked for.
local HUNT_INTERVAL = 1 / TTTBots.Tickrate
local REVEAL_INTERVAL = 1

--- Has this player been through the Revenant's death and come back as the killer?
---
--- `revenant_state` is the addon's own field: nil or 1 is the hidden innocent it spawns as, 2 is the neutral
--- killer the revive makes it. It is reset to 0 for everybody at the end of a round and before the next one, so
--- this is a live question a round long, which is the point - the role changes state mid-round.
---@param ply Player?
---@return boolean
local function isRevivedRevenant(ply)
    if not (ROLE_REVENANT and IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:GetSubRole() ~= ROLE_REVENANT then return false end

    return ply.revenant_state == 2
end

--- Send a revived Revenant after the nearest player it can actually see.
---
--- A role profile cannot express this: the subrole never changes, so `GetStartsFights` would either have the bot
--- hunting while it is supposed to be a hidden innocent or never hunting at all. Keyed on the state instead,
--- exactly as the Shinigami's hunt drives its post-death form.
---
--- Fairness: it hunts what it can *see* (`Lib.SeenThisTick`, the tick's shared visibility answer), the same way
--- the random-nearby rule works for a traitor. Nothing is read that a player in the same seat would not see -
--- and once it is revived, everybody can see it too.
---@param bot Bot
local function hunt(bot)
    local current = bot.attackTarget
    if IsValid(current) and lib.IsPlayerAlive(current) then return end

    local nearest, nearestDist = nil, nil
    local myPos = bot:GetPos()

    for _, other in ipairs(TTTBots.Match.AlivePlayers) do
        if other == bot then continue end
        if not lib.IsPlayerAlive(other) then continue end
        if TTTBots.Roles.IsPlayerDamageImmune(other) then continue end -- shooting it would do nothing
        if not lib.SeenThisTick(bot, other) then continue end

        local dist = myPos:Distance(other:GetPos())
        if not nearestDist or dist < nearestDist then
            nearest, nearestDist = other, dist
        end
    end

    if not nearest then return end

    bot:SetAttackTarget(nearest)

    -- The attack behaviour navigates purely from what the bot remembers, so it has to be told where the target
    -- is or it picks the fight and then stands still. Same note as the Shinigami's hunt.
    bot.components.memory:UpdateKnownPositionFor(nearest)
end

--- Show every bot what the addon has stopped hiding.
---
--- While a Revenant lives, `TTT2SpecialRoleSyncing` rewrites its role to NONE for everybody but itself, so
--- nothing may fire. After the revive that hook no longer applies to it: its own team and role are public, which
--- is exactly what a player reads off the scoreboard before shooting it. A bot cannot read a HUD, so this tells
--- the suspicion system the same thing - a KOS-weight reason on every bot that can see it, which then announces
--- the callout and hands out the target through machinery that already exists.
---
--- A suspicion weight rather than a direct attack order, for the reason `noticeRoleWeapons` gives: the KOS is
--- announced, the other bots weigh it like any callout, and the per-player KOS cap applies. It is added once per
--- observer while that observer is below the KOS threshold, so it cannot stack every second.
local function revealRevivedRevenants()
    for _, revenantPly in ipairs(TTTBots.Match.AlivePlayers) do
        if not isRevivedRevenant(revenantPly) then continue end

        for _, bot in ipairs(TTTBots.Bots or {}) do
            if not (IsValid(bot) and bot.components) then continue end
            if bot == revenantPly then continue end
            if not lib.IsPlayerAlive(bot) then continue end
            if not TTTBots.Roles.GetRoleFor(bot):GetUsesSuspicion() then continue end

            local morality = bot:BotMorality()
            if not morality then continue end

            -- Re-assert this role's weight on the component we are about to talk to. See SUSPICION_REASONS.
            registerSuspicionReasons(morality)

            if morality:GetSuspicion(revenantPly) >= morality.Thresholds.KOS then continue end
            if not lib.SeenThisTick(bot, revenantPly) then continue end

            morality:ChangeSuspicion(revenantPly, "RevenantRevealed")
        end
    end
end

--- Drive both passes on their own clocks, the way roles/paranoid.lua does: the hunt runs on the bot tick and the
--- reveal is looked for once a second, because a visibility check per bot is what the reveal costs.
local nextHunt = 0
local nextReveal = 0

hook.Add("Think", "TTTBots.revenant", function()
    local time = CurTime()

    if time >= nextHunt then
        nextHunt = time + HUNT_INTERVAL

        for _, bot in ipairs(TTTBots.Bots or {}) do
            if not (IsValid(bot) and bot.components) then continue end
            if not isRevivedRevenant(bot) then continue end
            if not lib.IsPlayerAlive(bot) then continue end

            hunt(bot)
        end
    end

    if time >= nextReveal then
        nextReveal = time + REVEAL_INTERVAL

        revealRevivedRevenants()
    end
end)

return true
