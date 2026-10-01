--[[
    This component defines the morality of the agent. It is primarily responsible for determining who to shoot.
    It also tells traitors who to kill.
]]
---@class CMorality : Component
TTTBots.Components.Morality = TTTBots.Components.Morality or {}

local lib = TTTBots.Lib
---@class CMorality : Component
local BotMorality = TTTBots.Components.Morality

--- A scale of suspicious events to apply to a player's suspicion value. Scale is normally -10 to 10.
--- Role-specific events are registered by their own role file on load through RegisterSuspicionReason
--- (the Paranoid's corpse reveal in roles/paranoid.lua is one), so this table is not a complete list of
--- every reason in the game.
---
--- Merged into whatever is already there instead of replaced: this file is included again when the addon
--- reloads, and a plain assignment builds a brand new table and silently drops every reason a role file
--- had registered into the old one. The symptom is "Invalid suspicion reason: <x>" for a reason that was
--- in fact registered correctly - just into a table nothing reads any more.
BotMorality.SUSPICIONVALUES = BotMorality.SUSPICIONVALUES or {}
table.Merge(BotMorality.SUSPICIONVALUES, {
    -- Killing another player
    Kill = 9,                -- This player killed someone in front of us
    KillTrusted = 10,        -- This player killed a Trusted in front of us
    KillTraitor = -10,       -- This player killed a traitor in front of us
    CorpseKiller = 8,        -- A body we searched named this player as its killer. Below an eyewitness `Kill`
                             -- (a deduction, not a sighting) and above the KOS threshold, so it acts on itself.
                             -- Set by behaviors/investigatecorpse.lua from TTT2's own recorded killer sample.
    Hurt = 4,                -- This player hurt someone in front of us
    HurtMe = 10,             -- This player hurt us
    HurtTrusted = 10,        -- This player hurt a Trusted in front of us
    HurtByTrusted = 4,       -- This player was hurt by a Trusted
    HurtByEvil = -2,         -- This player was hurt by a traitor
    KOSByTrusted = 10,       -- KOS called on this player by trusted innocent
    KOSByTraitor = -5,       -- KOS called on this player by known traitor
    KOSByOther = 5,          -- KOS called on this player
    AffirmingKOS = -3,       -- KOS called on a player we think is a traitor (rare, but possible)
    RoleWeapon = 10,         -- This player is holding a weapon only one role is ever given, so they are
                             -- that role. Over the KOS threshold on its own, see noticeRoleWeapons below.
    NearUnidentified = 2,    -- This player is near an unidentified body and hasn't identified it in more than a
                             -- few seconds (NEAR_BODY_SECONDS, below). Awarded by the corpse timer, not by sight.
    IdentifiedTraitor = -3,  -- This player has identified a traitor's corpse
    IdentifiedInnocent = -2, -- This player has identified an innocent's corpse
    IdentifiedTrusted = -2,  -- This player has identified a Trusted's corpse
    DefuseC4 = -7,           -- This player is defusing C4
    PlantC4 = 10,            -- This player is throwing down C4
    FollowingMe = 3,         -- This player has been following me for more than 10 seconds
    ShotAtMe = 7,            -- This player has been shooting at me
    ShotAt = 5,              -- This player has been shooting at someone
    ShotAtTrusted = 6,       -- This player has been shooting at a Trusted
    ThrowDiscombob = 2,      -- This player has thrown a discombobulator
    ThrowIncin = 8,          -- This player has thrown an incendiary grenade
    ThrowSmoke = 3,          -- This player has thrown a smoke grenade
    PersonalSpace = 2,       -- This player is standing too close to me for too long
    FightConfusion = 6,      -- This player was blamed for a fight it was only watching
})

BotMorality.SuspicionDescriptions = {
    ["10"] = "Definitely evil",
    ["9"] = "Almost certainly evil",
    ["8"] = "Highly likely evil", -- Declare them as evil
    ["7"] = "Very suspicious, likely evil",
    ["6"] = "Very suspicious",
    ["5"] = "Quite suspicious",
    ["4"] = "Suspicious", -- Declare them as suspicious
    ["3"] = "Somewhat suspicious",
    ["2"] = "A little suspicious",
    ["1"] = "Slightly suspicious",
    ["0"] = "Neutral",
    ["-1"] = "Slightly trustworthy",
    ["-2"] = "Somewhat trustworthy",
    ["-3"] = "Quite trustworthy",
    ["-4"] = "Very trustworthy", -- Declare them as trustworthy
    ["-5"] = "Highly likely to be innocent",
    ["-6"] = "Almost certainly innocent",
    ["-7"] = "Definitely innocent",
    ["-8"] = "Undeniably innocent", -- Declare them as innocent
    ["-9"] = "Absolutely innocent",
    ["-10"] = "Unwaveringly innocent",
}

BotMorality.Thresholds = {
    KOS = 7,
    Sus = 3,
    Trust = -3,
    Innocent = -5,
}

function BotMorality:New(bot)
    local newMorality = {}
    setmetatable(newMorality, {
        __index = function(t, k) return BotMorality[k] end,
    })
    newMorality:Initialize(bot)

    local dbg = lib.GetConVarBool("debug_misc")
    if dbg then
        print("Initialized Morality for bot " .. bot:Nick())
    end

    return newMorality
end

function BotMorality:Initialize(bot)
    -- print("Initializing")
    bot.components = bot.components or {}
    bot.components.Morality = self

    self.componentID = string.format("Morality (%s)", lib.GenerateID()) -- Component ID, used for debugging

    self.tick = 0                                                       -- Tick counter
    self.bot = bot ---@type Bot
    self.suspicions = {}                                                -- A table of suspicions for each player
end

--- Add a reason to the suspicion scale, or overwrite the weight of one. Role files register their own
--- events this way rather than writing into SUSPICIONVALUES directly: this resolves the table through
--- the component being used, so the entry lands where ChangeSuspicion will look it up even if the
--- component table has been rebuilt since the role file ran.
---@param reason string The key that ChangeSuspicion will be called with.
---@param value number Positive to make a player more suspicious, negative for less.
function BotMorality:RegisterSuspicionReason(reason, value)
    self.SUSPICIONVALUES = self.SUSPICIONVALUES or {}
    self.SUSPICIONVALUES[reason] = value
end

--- Increase/decrease the suspicion on the player for the given reason.
---@param target Player
---@param reason string The reason (matching a key in SUSPICIONVALUES)
function BotMorality:ChangeSuspicion(target, reason, mult)
    local roleDisablesSuspicion = not TTTBots.Roles.GetRoleFor(self.bot):GetUsesSuspicion()
    if roleDisablesSuspicion then return end
    if not mult then mult = 1 end
    if target == self.bot then return end                 -- Don't change suspicion on ourselves
    if TTTBots.Match.RoundActive == false then return end -- Don't change suspicion if the round isn't active, duh
    local targetIsPolice = TTTBots.Roles.GetRoleFor(target):GetAppearsPolice()
    if targetIsPolice then
        mult = mult * 0.3 -- Police are much less suspicious
    end

    mult = mult * (hook.Run("TTTBotsModifySuspicion", self.bot, target, reason, mult) or 1)

    local susValue = self.SUSPICIONVALUES[reason]
    if not susValue then
        ErrorNoHaltWithStack("Invalid suspicion reason: " .. tostring(reason) .. "\n")
        return
    end
    local increase = math.ceil(susValue * mult)
    local susFinal = ((self:GetSuspicion(target)) + (increase))
    self.suspicions[target] = math.floor(susFinal)

    self:AnnounceIfThreshold(target)
    self:SetAttackIfTargetSus(target)

    -- print(string.format("%s's suspicion on %s has changed by %d", self.bot:Nick(), target:Nick(), increase))
end

function BotMorality:GetSuspicion(target)
    return self.suspicions[target] or 0
end

--- Announce the suspicion level of the given player if it is above a certain threshold.
---@param target Player
function BotMorality:AnnounceIfThreshold(target)
    local sus = self:GetSuspicion(target)
    local chatter = self.bot:BotChatter()
    if not chatter then return end
    local KOSThresh = self.Thresholds.KOS
    local SusThresh = self.Thresholds.Sus
    local TrustThresh = self.Thresholds.Trust
    local InnocentThresh = self.Thresholds.Innocent

    -- Never call KOS on a role nobody can act on (the Swapper). Every bot already refuses to attack or
    -- chase it, so the callout - and the quick "traitor" radio mark that comes with it - would only ever
    -- get somebody else to kill it, which is exactly what that role is waiting for, and it costs whoever
    -- obliges their own role. Damage from it still builds suspicion, but that suspicion goes nowhere.
    local uncallable = TTTBots.Roles.IsPlayerDamageImmune(target)

    if sus >= KOSThresh and not uncallable then
        chatter:On("CallKOS", { player = target:Nick(), playerEnt = target })
        -- self.bot:Say("I think " .. target:Nick() .. " is evil!")
    elseif sus >= SusThresh then
        -- self.bot:Say("I think " .. target:Nick() .. " is suspicious!")
    elseif sus <= InnocentThresh then
        -- self.bot:Say("I think " .. target:Nick() .. " is innocent!")
    elseif sus <= TrustThresh then
        -- self.bot:Say("I think " .. target:Nick() .. " is trustworthy!")
    end
end

--- Set the bot's attack target to the given player if they seem evil.
function BotMorality:SetAttackIfTargetSus(target)
    if self.bot.attackTarget ~= nil then return end
    local sus = self:GetSuspicion(target)
    if sus >= self.Thresholds.KOS then
        self.bot:SetAttackTarget(target)
        return true
    end
    return false
end

function BotMorality:TickSuspicions()
    local roundStarted = TTTBots.Match.RoundActive
    if not roundStarted then
        self.suspicions = {}
        return
    end
end

--- Returns a random victim player, weighted off of each player's traits.
---@param playerlist table<Player>
---@return Player
function BotMorality:GetRandomVictimFrom(playerlist)
    if not playerlist or #playerlist == 0 then return nil end
    local tbl = {}

    for i, player in pairs(playerlist) do
        if player:IsBot() then
            local victim = player:GetTraitMult("victim")
            table.insert(tbl, lib.SetWeight(player, victim))
        else
            table.insert(tbl, lib.SetWeight(player, 1))
        end
    end

    if #tbl == 0 then return nil end
    return lib.RandomWeighted(tbl)
end

--- The players this bot can see right now, from the tick's shared answer (`Lib.SeenThisTick`) rather than a
--- fresh trace per candidate.
---
--- Every pass in this file asks some version of this question, in the same tick, and the memory pass has
--- already traced every one of these pairs for its own update - so the traces here were duplicates of work
--- done moments earlier in the same tick, and the passes could disagree with each other about the same pair.
---@param bot Bot
---@param players table<Player>? Defaults to the bot's non-allies.
---@return table<Player>
local function getSeenPlayers(bot, players)
    return lib.FilterTable(players or TTTBots.Roles.GetNonAllies(bot), function(other)
        if other == bot then return false end

        return lib.SeenThisTick(bot, other)
    end)
end

--- Makes it so that traitor bots will attack random players nearby.
function BotMorality:SetRandomNearbyTarget()
    if not (self.tick % TTTBots.Tickrate == 0) then return end -- Run only once every second
    local roundStarted = TTTBots.Match.RoundActive
    local targetsRandoms = TTTBots.Roles.GetRoleFor(self.bot):GetStartsFights()
    if not (roundStarted and targetsRandoms) then return end

    -- The deathmatch hands out its own targets (SetDeathmatchTarget below), and a bot that cannot fight must not
    -- pick one up from either producer. During a round this is inert - the Jester's fight-picking is how a fool
    -- gets itself killed, and it is meant to keep doing it.
    if TTTBots.Match.IsDeathmatchActive() and TTTBots.Roles.IsNonCombatant(self.bot) then return end
    if self.bot.attackTarget ~= nil then return end

    -- One gate for every unprovoked kill, shared with the plan system and the last-player-standing rule below:
    -- see Match.KillDelayElapsed. It replaces a bare `Match.Time() <= attack_delay` test here, which measured
    -- the round only - a bot that spawned late or was defibrillated back into a two-minute-old round walked
    -- straight through it and could shoot whoever was next to it. Provoked fights are unaffected.
    if not TTTBots.Match.KillDelayElapsed(self.bot) then return end

    -- `rage` is a 0-1 fraction (see CPersonality:AddRage / GetRage), so multiply by it directly.
    -- Previously this divided by 100, which floored aggression at 0.3 for every bot and made rage
    -- completely irrelevant to how readily a traitor starts fights.
    local personality = self.bot:BotPersonality()
    local rage = personality and personality:GetRage() or 0
    local aggression = math.max(self.bot:GetTraitMult("aggression") * rage, 0.3)
    local time_modifier = TTTBots.Match.SecondsPassed / 30 -- Increase chance to attack over time.

    local maxTargets = math.max(2, math.ceil(aggression * 2 * time_modifier))
    local targets = getSeenPlayers(self.bot)
    if (#targets > maxTargets) or (#targets == 0) then return end -- Don't attack if there are too many targets

    local base_chance = 4.5                                       -- X% chance to attack per second
    local chanceAttackPerSec = (
        base_chance
        * aggression
        * (maxTargets / #targets)
        * time_modifier
        * (#targets == 1 and 5 or 1)
    )
    if lib.TestPercent(chanceAttackPerSec) then
        local target = BotMorality:GetRandomVictimFrom(targets)
        self.bot:SetAttackTarget(target)
    end
end

function BotMorality:TickIfLastAlive()
    if not TTTBots.Match.RoundActive then return end
    -- The last two standing is a fight order like any other, so it waits like the others: with only two players
    -- alive this handed out a target on the very first tick of a round, which on a small server is somebody
    -- dying before anyone has moved. Once the round has been going for `ttt_bot_attack_delay` it is open again,
    -- which is every case this rule was written for.
    if not TTTBots.Match.KillDelayElapsed(self.bot) then return end

    -- `Match.AlivePlayers` rather than a fresh scan of every player: this runs on every tick for every bot,
    -- and building a table each time was pure allocation churn for an answer the match already refreshes
    -- three times a second. A third of a second of staleness changes nothing about who the last two are.
    local plys = TTTBots.Match.AlivePlayers
    if #plys > 2 then return end
    local otherPlayer = nil
    for i, ply in pairs(plys) do
        if ply ~= self.bot then
            otherPlayer = ply
            break
        end
    end

    self.bot:SetAttackTarget(otherPlayer)
end

---Once the round is over and the deathmatch has started, find someone to fight. Every bot does this,
---so the post-round turns into an actual brawl rather than a dozen bots wandering an empty map. The
---suspicion system is off by then, so the bot is handed its target's position too: without that it
---would pick a fight and then stand still, because the attack behavior only chases what memory knows.
function BotMorality:SetDeathmatchTarget()
    if not TTTBots.Match.IsDeathmatchActive() then return end
    if not lib.IsPlayerAlive(self.bot) then return end
    if self.tick % TTTBots.Tickrate ~= 0 then return end -- about once a second

    -- This rule had no role check at all: every living bot was handed a random victim, so a Jester or a Swapper
    -- spent the post-round walking into the open to shoot people it cannot damage (both addons zero that damage,
    -- and the Swapper cannot be damaged either). It now gets no target, and loses any it was handed a moment
    -- ago. What it does instead is behaviors/evade.lua, the first node of the shared `Survive` group.
    if TTTBots.Roles.IsNonCombatant(self.bot) then
        self.bot:SetAttackTarget(nil)

        return
    end

    local bot = self.bot
    local memory = bot:BotMemory()
    if not memory then return end

    local current = bot.attackTarget
    if IsValid(current) and current ~= bot and lib.IsPlayerAlive(current) then
        memory:UpdateKnownPositionFor(current)
        return
    end

    local candidates = lib.FilterTable(TTTBots.Match.AlivePlayers, function(ply)
        if ply == bot then return false end
        if not (IsValid(ply) and ply:IsPlayer()) then return false end
        return lib.IsPlayerAlive(ply)
    end)

    if #candidates == 0 then return end

    local target = table.Random(candidates)
    memory:UpdateKnownPositionFor(target)
    bot:SetAttackTarget(target)
end

function BotMorality:Think()
    self.tick = (self.bot.tick or 0)

    if not lib.IsPlayerAlive(self.bot) then
        -- We're dead. Flag that we should re-assert our killer memory when we come back to life
        -- (defibrillator / custom revive roles).
        self.bot.grudgeReasserted = false
        return
    end

    if self.bot.grudge and not self.bot.grudgeReasserted then
        self.bot.grudgeReasserted = true
        self:OnRevived()
    end

    self:TickSuspicions()
    self:SetRandomNearbyTarget()
    self:TickIfLastAlive()
    self:SetDeathmatchTarget()
end

---Called by OnWitnessHurt, but only if we (the owning bot) is a traitor.
---@param victim Player
---@param attacker Player
---@param healthRemaining number
---@param damageTaken number
---@return nil
function BotMorality:OnWitnessHurtIfAlly(victim, attacker, healthRemaining, damageTaken)
    if not TTTBots.Roles.IsAllies(victim, attacker) then return end

    if self.bot.attackTarget == nil then
        self.bot:SetAttackTarget(attacker)
    end
end

function BotMorality:OnKilled(attacker)
    if not (attacker and IsValid(attacker) and attacker:IsPlayer()) then
        self.bot.grudge = nil
        self.bot.grudgeReasserted = nil
        return
    end
    self.bot.grudge = attacker -- Set grudge to the attacker
    self.bot.grudgeTime = CurTime()
    -- Make sure we re-assert this memory if we get revived.
    self.bot.grudgeReasserted = false
end

--- Called when the bot comes back to life (defibrillator / custom revive roles). Re-applies what it
--- learned when it died, so a revived bot doesn't "forget" who killed it.
function BotMorality:OnRevived()
    local attacker = self.bot.grudge
    if not (IsValid(attacker) and attacker ~= self.bot) then return end

    -- Mark them as a threat in our memory (this can also trigger a KOS callout for suspicion roles).
    if TTTBots.Roles.GetRoleFor(self.bot):GetUsesSuspicion() then
        self:ChangeSuspicion(attacker, "HurtMe")
    end

    -- Say who put them there. A bot that has just been brought back knows exactly who killed it, and naming
    -- them is what a player does on the way back in.
    --
    -- This used to sit inside the "is the killer still alive?" branch below, which meant a bot revived after
    -- the fight was over said nothing at all - and that is the normal case for a defibrillator, since by the
    -- time anybody is standing over a body the person who made it is usually dead too. Knowing who killed you
    -- does not depend on them still being up.
    --
    -- Only during a round: the post-round deathmatch respawns bots that died, and nobody wants "X killed me!"
    -- every time the deathmatch resets.
    if TTTBots.Match.IsRoundActive() then
        local chatter = self.bot:BotChatter()
        if chatter then
            chatter:On("RevivedBy", { player = attacker:Nick(), playerEnt = attacker })
        end
    end

    -- And go after them, if they are still around.
    if not TTTBots.Lib.IsPlayerAlive(attacker) then return end

    -- Feed their position to memory as well. The attack behavior navigates purely from what the
    -- bot remembers, so without this a revived bot would pick the fight and then stand still,
    -- having no idea where the person who killed it went.
    local memory = self.bot:BotMemory()
    if memory then
        memory:UpdateKnownPositionFor(attacker)
    end

    self.bot:SetAttackTarget(attacker)

    -- Call it as well: a KOS announces it to every bot in the match, refuses roles that look like police and
    -- is capped by ttt_bot_kos_limit. Kept inside this branch on purpose - a KOS spends one of the few calls
    -- the bot has for the round, and spending it on somebody who is already dead would waste it.
    TTTBots.Match.CallKOS(self.bot, attacker)
end

function BotMorality:OnWitnessKill(victim, weapon, attacker)
    if (weapon and IsValid(weapon) and weapon.GetClass and weapon:GetClass() == "ttt_c4") then return end -- We don't know who killed who with C4, so we can't build sus on it.
    -- For this function, we will allow the bots to technically cheat and know what role the victim was. They will not know what role the attacker is.
    -- This allows us to save time and resources in optimization and let players have a more fun experience, despite technically being a cheat.
    if not lib.IsPlayerAlive(self.bot) then return end
    local vicIsTraitor = victim:GetTeam() == TEAM_TRAITOR

    -- change suspicion on the attacker by KillTraitor, KillTrusted, or Kill. Depending on role.
    if vicIsTraitor then
        self:ChangeSuspicion(attacker, "KillTraitor")
    elseif TTTBots.Roles.GetRoleFor(victim):GetAppearsPolice() then
        self:ChangeSuspicion(attacker, "KillTrusted")
    else
        self:ChangeSuspicion(attacker, "Kill")
    end
end

function BotMorality:OnKOSCalled(caller, target)
    if not lib.IsPlayerAlive(self.bot) then return end
    if not TTTBots.Roles.GetRoleFor(caller):GetUsesSuspicion() then return end

    local callerSus = self:GetSuspicion(caller)
    local callerIsPolice = TTTBots.Roles.GetRoleFor(caller):GetAppearsPolice()
    local targetSus = self:GetSuspicion(target)

    local TRAITOR = self.Thresholds.KOS
    local TRUSTED = self.Thresholds.Trust

    if targetSus > TRAITOR then
        self:ChangeSuspicion(caller, "AffirmingKOS")
    end

    if callerIsPolice or callerSus < TRUSTED then -- if we trust the caller or they are a detective, then:
        self:ChangeSuspicion(target, "KOSByTrusted")
    elseif callerSus > TRAITOR then               -- if we think the caller is a traitor, then:
        self:ChangeSuspicion(target, "KOSByTraitor")
    else                                          -- if we don't know the caller, then:
        self:ChangeSuspicion(target, "KOSByOther")
    end
end

hook.Add("PlayerDeath", "TTTBots.Components.Morality.PlayerDeath", function(victim, weapon, attacker)
    if not (IsValid(victim) and victim:IsPlayer()) then return end
    if not (IsValid(attacker) and attacker:IsPlayer()) then return end

    local timestamp = CurTime()
    if attacker:IsBot() then
        attacker.lastKillTime = timestamp
    end
    if victim:IsBot() then
        local victimMorality = victim.components and victim.components.morality
        if victimMorality then
            victimMorality:OnKilled(attacker)
        end
    end
    -- Being seen by the victim is what makes a kill "red handed": this is technically a cheat, but a
    -- necessary one. It only decides whether the killer is marked, though - it must not decide whether
    -- anybody else noticed. Returning here used to skip every witness, so a bot that killed from behind
    -- cover, or with fire or a grenade, was invisible to the whole room no matter who was watching.
    if victim:GetTeam() == TEAM_INNOCENT and lib.CanSeeEntity(victim, attacker) then
        local ttt_bot_cheat_redhanded_time = lib.GetConVarInt("cheat_redhanded_time")
        attacker.redHandedTime = timestamp +
            ttt_bot_cheat_redhanded_time -- Only assign red handed time if it was a direct attack
    end

    local witnesses = lib.GetAllWitnesses(attacker:EyePos(), true)
    table.insert(witnesses, victim)

    for i, witness in pairs(witnesses) do
        local morality = witness and witness.components and witness.components.morality
        if morality then
            morality:OnWitnessKill(victim, weapon, attacker)
        end
    end
end)

--- How close a fool-role player has to be to a fight to be mistaken for one of its participants, and how
--- often any one bot is allowed to make that mistake.
local CONFUSION_RANGE = 600
local CONFUSION_COOLDOWN = 20

--- Pick the wrong person to blame for a fight we just watched, if anyone.
---
--- A bot watching a scrap normally attributes it to whoever pulled the trigger. Sometimes it gets it wrong,
--- and the face it picks out of the chaos is the one playing the fool: the Jester and the Swapper both win
--- by being killed by the wrong person, so being blamed is the entire point of them wading in. The bot
--- blames them instead of the real attacker for this one event, which means the real attacker gets away
--- with it and the fool inherits the suspicion.
---@param bot Bot The witness.
---@param victim Player The player who was hurt.
---@return Player? fool
local function findFoolToBlame(bot, victim)
    -- Only roles that deal in suspicion can be confused in the first place. A traitor or one of its
    -- subroles knows who everybody is - and the jesters are allied to it besides - so misreading a scrap
    -- would only cost it the truth. Checked before the roll so such a bot never loses the attribution for
    -- the event, or gets distracted by a stare at somebody it already knows.
    if not TTTBots.Roles.GetRoleFor(bot):GetUsesSuspicion() then return nil end

    local chance = lib.GetConVarInt("confusion_chance")
    if chance <= 0 then return nil end
    if (bot.nextConfusion or 0) > CurTime() then return nil end
    if math.random(1, 100) > chance then return nil end

    local suspects = lib.FilterTable(TTTBots.Match.AlivePlayers, function(other)
        if other == bot or other == victim then return false end
        if not TTTBots.Roles.IsFoolRole(other) then return false end
        if TTTBots.Roles.IsAllies(bot, other) then return false end -- we do not doubt our own side
        -- In the fight, not watching it from across the map, and visible to us.
        if victim:GetPos():Distance(other:GetPos()) > CONFUSION_RANGE then return false end

        return lib.CanShoot(bot, other)
    end)

    if #suspects == 0 then return nil end

    bot.nextConfusion = CurTime() + CONFUSION_COOLDOWN

    return table.Random(suspects)
end

--- When we witness someone getting hurt.
function BotMorality:OnWitnessHurt(victim, attacker, healthRemaining, damageTaken)
    if damageTaken < 1 then return end -- Don't care.
    self:OnWitnessHurtIfAlly(victim, attacker, healthRemaining, damageTaken)
    if attacker == self.bot then       -- if we are the attacker, there is no sus to be thrown around.
        if victim == self.bot.attackTarget then
            local personality = self.bot:BotPersonality()
            if not personality then return end
            personality:OnPressureEvent("HurtEnemy")
        end
        return
    end
    if self.bot == victim then -- if we are the victim, just fight back instead of worrying about sus.
        self.bot:SetAttackTarget(attacker)
        local personality = self.bot:BotPersonality()
        if personality then
            personality:OnPressureEvent("Hurt")
        end
    end
    if self.bot == victim or self.bot == attacker then return end -- Don't build sus on ourselves
    if TTTBots.Roles.IsAllies(victim, attacker) then return end  -- Don't build sus for fights between allies
    -- If the target is disguised, we don't know who they are, so we can't build sus on them. Instead, ATTACK!
    if TTTBots.Match.IsPlayerDisguised(attacker) then
        if self.bot.attackTarget == nil then
            self.bot:SetAttackTarget(attacker)
        end
        return
    end

    -- Get it wrong, and think about it. A Jester ends up hunted, which is what it wanted; a Swapper
    -- inherits the suspicion but cannot be attacked or called out, so the witness only turns to stare at
    -- it. Either way the real attacker is off the hook for this event.
    local fool = findFoolToBlame(self.bot, victim)
    if fool then
        self:ChangeSuspicion(fool, "FightConfusion")
        local loco = self.bot:BotLocomotor()
        if loco then loco:LookAt(fool:GetPos(), 1.5) end
        return
    end

    local attackerSusMod = 1.0
    local victimSusMod = 1.0
    local can_cheat = lib.GetConVarBool("cheat_know_shooter")
    if can_cheat then
        local bad_guy = TTTBots.Match.WhoShotFirst(victim, attacker)
        if bad_guy == victim then
            victimSusMod = 2.0
            attackerSusMod = 0.5
        elseif bad_guy == attacker then
            victimSusMod = 0.5
            attackerSusMod = 2.0
        end
    end

    local impact = (damageTaken / victim:GetMaxHealth()) * 3 --- Percent of max health lost * 3. 50% health lost =  6 sus
    local victimIsPolice = TTTBots.Roles.GetRoleFor(victim):GetAppearsPolice()
    local attackerIsPolice = TTTBots.Roles.GetRoleFor(attacker):GetAppearsPolice()
    local attackerSus = self:GetSuspicion(attacker)
    local victimSus = self:GetSuspicion(victim)
    if victimIsPolice or victimSus < BotMorality.Thresholds.Trust then
        self:ChangeSuspicion(attacker, "HurtTrusted", impact * attackerSusMod) -- Increase sus on the attacker because we trusted their victim
    elseif attackerIsPolice or attackerSus < BotMorality.Thresholds.Trust then
        self:ChangeSuspicion(victim, "HurtByTrusted", impact * victimSusMod)   -- Increase sus on the victim because we trusted their attacker
    elseif attackerSus > BotMorality.Thresholds.KOS then
        self:ChangeSuspicion(victim, "HurtByEvil", impact * victimSusMod)      -- Decrease the sus on the victim because we know their attacker is evil
    else
        self:ChangeSuspicion(attacker, "Hurt", impact * attackerSusMod)        -- Increase sus on attacker because we don't trust anyone involved
    end

    -- self.bot:Say(string.format("I saw that! Attacker sus is %d; vic is %d", attackerSus, victimSus))
end

function BotMorality:OnWitnessFireBullets(attacker, data, angleDiff)
    -- angleDiff is how far our view is turned away from the shooter's: looking straight at them means
    -- the weapon is pointed roughly back at us, while looking the same way they are means it is
    -- pointed away from us. Scale the multiplier across that range, from the 0.1 floor up to a full
    -- ShotAt, so a burst aimed at us is worth much more than shots fired off in another direction.
    --
    -- This used to be `-1 * (1 - angleDiffPercent) / 4`, which is negative for every angle short of
    -- 150 degrees. The clamp below therefore flattened almost all witnessed gunfire to the floor, and
    -- the panic branch was unreachable dead code - bots never got spooked by shots aimed at them.
    local aimedAtUs = math.Clamp(angleDiff / 180, 0, 1)
    local sus = math.max(aimedAtUs, 0.1)

    if aimedAtUs > 0.75 then
        local personality = self.bot:BotPersonality()
        if personality then
            personality:OnPressureEvent("BulletClose")
        end
    end

    self:ChangeSuspicion(attacker, "ShotAt", sus)
end

hook.Add("EntityFireBullets", "TTTBots.Components.Morality.FireBullets", function(entity, data)
    if not (IsValid(entity) and entity:IsPlayer()) then return end
    local witnesses = lib.GetAllWitnesses(entity:EyePos(), true)

    local witnessSet = {}
    for i, witness in pairs(witnesses) do
        witnessSet[witness] = true
    end

    local lookAngle = entity:EyeAngles()

    -- Combined loop for all witnesses
    for i, witness in pairs(witnesses) do
        if not witness:IsBot() then continue end
        ---@cast witness Bot
        local morality = witness:BotMorality()
        if not morality then continue end

        -- We calculate the angle difference between the entity and the witness
        local witnessAngle = witness:EyeAngles()
        local angleDiff = lookAngle.y - witnessAngle.y

        -- Adjust angle difference to be between -180 and 180
        angleDiff = ((angleDiff + 180) % 360) - 180
        -- Absolute value to ensure angleDiff is non-negative
        angleDiff = math.abs(angleDiff)

        -- Remember where the shooting came from. The crowd behaviors use this to step out of the line
        -- of fire, which is the only sensible thing an innocent with no identified shooter can do.
        witness.lastGunfirePos = entity:GetPos()
        witness.lastGunfireTime = CurTime()

        morality:OnWitnessFireBullets(entity, data, angleDiff)
        hook.Run("TTTBotsOnWitnessFireBullets", witness, entity, data, angleDiff)
    end

    -- Bots that could NOT see the shooter should still react to rounds flying close past them
    -- (suppression). This is the "someone is shooting near me but nobody is visible" case.
    local src = data and data.Src
    local dir = data and data.Dir
    if not (src and dir) then return end

    local normalizedDir = dir:GetNormalized()
    local MAX_WHIZ_DIST = 150   -- how close a round must pass to be noticed
    local MAX_WHIZ_RANGE = 4000 -- ignore rounds fired from absurdly far along the path

    for _, other in pairs(TTTBots.Bots) do
        if not (IsValid(other) and lib.IsPlayerAlive(other)) then continue end
        if other == entity then continue end
        if witnessSet[other] then continue end -- witnesses already reacted above

        local toBot = other:GetPos() - src
        local along = toBot:Dot(normalizedDir)
        if along <= 0 or along > MAX_WHIZ_RANGE then continue end

        local closestPoint = src + normalizedDir * along
        if closestPoint:Distance(other:GetPos()) > MAX_WHIZ_DIST then continue end

        -- A round that passed this close counts as gunfire too, even though we never saw the shooter.
        other.lastGunfirePos = closestPoint
        other.lastGunfireTime = CurTime()

        local personality = other:BotPersonality()
        if personality then
            personality:OnPressureEvent("BulletClose")
        end

        -- Don't interrupt a bot that is already engaging a target; otherwise glance toward the shot.
        if other.attackTarget == nil then
            local loco = other:BotLocomotor()
            if loco then
                loco:LookAt(closestPoint, 0.75)
            end

            -- ...and fight back. A round passing this close tells the bot where it came from, which is what a
            -- player gets from the crack and the muzzle flash, so a bot that starts fights treats it as being
            -- shot at rather than as a noise: it takes the lead and goes looking. Two things keep it honest -
            -- identity stays behind the same cheat the damage handler uses, and the lead is a patch of ground
            -- rather than the shooter's position, because a bullet's path does not name anybody. The cooldown
            -- exists because this runs per bullet: a burst should be one reaction, not thirty.
            if lib.GetConVarBool("cheat_know_shooter")
                and TTTBots.Roles.GetRoleFor(other):GetStartsFights()
                and (other.bulletReactTime or 0) < CurTime()
            then
                other.bulletReactTime = CurTime() + 0.75

                local memory = other:BotMemory()
                if memory then
                    local lead = lib.GetInferredLookPos(other, entity:GetPos(), false)
                    memory:UpdateKnownPositionFor(entity, lead)
                end

                other:SetAttackTarget(entity)
            end
        end
    end
end)

--- A flame, a grenade or a thrown projectile reports itself - or nothing at all - as the attacker rather
--- than the player who set it off. Resolve that to whoever owns or created it, so the damage can be
--- attributed instead of ignored.
---@param source Entity? The damage source the engine handed us.
---@return Player? attacker
function BotMorality.GetDamageAttackerOf(source)
    if not IsValid(source) then return nil end
    if source:IsPlayer() then return source end

    for _, getter in ipairs({ "GetOwner", "GetCreator" }) do
        if source[getter] then
            local owner = source[getter](source)
            if IsValid(owner) and owner:IsPlayer() then return owner end
        end
    end

    return nil
end

hook.Add("PlayerHurt", "TTTBots.Components.Morality.PlayerHurt", function(victim, attacker, healthRemaining, damageTaken)
    if not (IsValid(victim) and victim:IsPlayer()) then return end

    -- Indirect damage (the arson thrower's fire, a grenade, a launched prop) used to fall straight through
    -- here because the source is not a player, which is why a bot on fire would stand there and ignore it.
    if not (IsValid(attacker) and attacker:IsPlayer()) then
        attacker = BotMorality.GetDamageAttackerOf(attacker)
    end

    if not (IsValid(attacker) and attacker:IsPlayer()) then return end
    if attacker == victim then return end -- our own fire, our own grenade

    if lib.CanSeeEntity(victim, attacker) then
        -- Direct, witnessed combat: build suspicion for the victim and everyone who can see the attacker.
        local witnesses = lib.GetAllWitnesses(attacker:EyePos(), true)
        table.insert(witnesses, victim)

        for i, witness in pairs(witnesses) do
            local morality = witness and witness.components and witness.components.morality
            if morality then
                morality:OnWitnessHurt(victim, attacker, healthRemaining, damageTaken)
                hook.Run("TTTBotsOnWitnessHurt", witness, victim, attacker, healthRemaining, damageTaken)
            end
        end
        return
    end

    -- The attacker is NOT visible to the victim (shot from behind/cover, or an indirect source like
    -- C4/fire). Previously this bailed out entirely, so hidden hits produced no reaction at all.
    if not victim:IsBot() then return end

    local personality = victim:BotPersonality()
    if personality then
        personality:OnPressureEvent("Hurt")
    end

    -- Glance toward the direction the damage came from: a patch of ground out that way, not the shooter.
    -- Looking at `attacker:GetPos()` meant looking at their live, exact position through any amount of
    -- geometry, which is what made a bot that was shot through a wall appear to lock onto the person
    -- shooting it.
    local loco = victim:BotLocomotor()
    if loco and victim.attackTarget == nil then
        loco:LookAt(lib.GetInferredLookPos(victim, attacker:GetPos(), false), 1)
    end

    -- Only reveal the attacker's identity when the shooter-knowledge cheat is enabled AND the role
    -- is a fight-starter. Survivor/defensive roles (e.g. Drunk) should only flinch and glance toward
    -- the shot, not hunt someone they cannot see -- that would just get them killed.
    if lib.GetConVarBool("cheat_know_shooter") and TTTBots.Roles.GetRoleFor(victim):GetStartsFights() then
        victim:SetAttackTarget(attacker)
    end
end)

hook.Add("TTTBodyFound", "TTTBots.Components.Morality.BodyFound", function(ply, deadply, rag)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if not (IsValid(deadply) and deadply:IsPlayer()) then return end
    local corpseIsTraitor = deadply:GetTeam() ~= TEAM_INNOCENT
    local corpseIsPolice = deadply:GetRoleStringRaw() == "detective"

    for i, bot in pairs(lib.GetAliveBots()) do
        local morality = bot.components and bot.components.morality
        if not morality or not TTTBots.Roles.GetRoleFor(bot):GetUsesSuspicion() then continue end
        if corpseIsTraitor then
            morality:ChangeSuspicion(ply, "IdentifiedTraitor")
        elseif corpseIsPolice then
            morality:ChangeSuspicion(ply, "IdentifiedTrusted")
        else
            morality:ChangeSuspicion(ply, "IdentifiedInnocent")
        end
    end
end)

--- The corpse this player is standing next to and has not identified, or nil.
---
--- Returns the corpse rather than a boolean because the caller has to know *which* body is being loitered over:
--- a bot only becomes suspicious of it if it can see that body for itself.
---@param ply Player
---@param corpses table
---@return Entity? corpse
function BotMorality.IsPlayerNearUnfoundCorpse(ply, corpses)
    local IsIdentified = CORPSE.GetFound
    for _, corpse in pairs(corpses) do
        if not IsValid(corpse) then continue end
        if IsIdentified(corpse) then continue end
        local dist = ply:GetPos():Distance(corpse:GetPos())
        local THRESHOLD = 500
        if lib.CanSeeEntity(ply, corpse) and (dist < THRESHOLD) then
            return corpse
        end
    end
    return nil
end

--- Table of [Player]=number showing seconds near unidentified corpses
--- Does not stack. If a player is near 2 corpses, it will only count as 1. This is to prevent innocents discovering massacres and being killed for it.
local playersNearBodies = {}

--- How many seconds of loitering over an unidentified body it takes before the bots that can see it start to
--- wonder why the person standing there has not identified it. Three, not five: a round is busy and a body is
--- usually either dealt with quickly or walked away from, so a shorter window catches the person who stopped to
--- look and chose not to identify it while still leaving a searcher - who is rewarded by `Identified*` the moment
--- the body is opened, which cancels this - alone for the seconds their search takes.
local NEAR_BODY_SECONDS = 3

--- Who has already been reported this visit. `NearUnidentified` is +2 and the scale tops out at 10, so awarding
--- it once a second would pin anybody who stands still for a few seconds at the ceiling.
local playersNearBodiesReported = {}

timer.Create("TTTBots.Components.Morality.PlayerCorpseTimer", 1, 0, function()
    if TTTBots.Match.RoundActive == false then return end
    local alivePlayers = TTTBots.Match.AlivePlayers
    local corpses = TTTBots.Match.Corpses

    for i, ply in pairs(alivePlayers) do
        if not IsValid(ply) then continue end
        local corpse = BotMorality.IsPlayerNearUnfoundCorpse(ply, corpses)

        if not corpse then
            playersNearBodies[ply] = math.max((playersNearBodies[ply] or 0) - 1, 0)
            if playersNearBodies[ply] <= 0 then
                playersNearBodiesReported[ply] = nil -- they left the body; a second visit is its own offence
            end
            continue
        end

        playersNearBodies[ply] = (playersNearBodies[ply] or 0) + 1
        if playersNearBodies[ply] < NEAR_BODY_SECONDS then continue end
        if playersNearBodiesReported[ply] then continue end
        playersNearBodiesReported[ply] = true

        -- `NearUnidentified` is the weight this tracker was written for - its own comment in SUSPICIONVALUES says
        -- "near an unidentified body and hasn't identified it in more than 5 seconds" - and until now nothing
        -- read the seconds it had been counting, so the reason had no caller at all.
        --
        -- Only bots that can see the body are told, which is what keeps this to knowledge a bot could really
        -- hold: it watched somebody stand over a body and leave it unidentified. What the body *contains* plays
        -- no part - nobody has identified it, so all anybody knows is that it is there.
        for j, bot in pairs(lib.GetAliveBots()) do
            if bot == ply then continue end
            local morality = bot.components and bot.components.morality
            if not morality or not TTTBots.Roles.GetRoleFor(bot):GetUsesSuspicion() then continue end
            if not bot:VisibleVec(corpse:GetPos() + Vector(0, 0, 16)) then continue end

            morality:ChangeSuspicion(ply, "NearUnidentified")
        end
    end
end)

-- Disguised player detection
timer.Create("TTTBots.Components.Morality.DisguisedPlayerDetection", 1, 0, function()
    if not TTTBots.Match.RoundActive then return end
    local alivePlayers = TTTBots.Match.AlivePlayers
    for i, ply in pairs(alivePlayers) do
        local isDisguised = TTTBots.Match.IsPlayerDisguised(ply)

        if isDisguised then
            local witnessBots = lib.GetAllWitnesses(ply:EyePos(), true)
            for i, bot in pairs(witnessBots) do
                ---@cast bot Bot
                if not IsValid(bot) then continue end
                if not TTTBots.Roles.GetRoleFor(bot):GetUsesSuspicion() then continue end
                local chatter = bot:BotChatter()
                if not chatter then continue end
                -- set attack target if we do not have one already
                bot:SetAttackTarget(bot.attackTarget or ply)
                bot:BotChatter():On("DisguisedPlayer")
            end
        end
    end
end)

---Keep killing any nearby non-allies if we're red-handed.
---@param bot Bot
local function continueMassacre(bot)
    local isRedHanded = bot.redHandedTime and (CurTime() < bot.redHandedTime)
    local isKillerRole = TTTBots.Roles.GetRoleFor(bot):GetStartsFights()

    if isRedHanded and isKillerRole then
        local nonAllies = TTTBots.Roles.GetNonAllies(bot)
        local closest = TTTBots.Lib.GetClosest(nonAllies, bot:GetPos())
        if closest and closest ~= NULL then
            bot:SetAttackTarget(closest)
        end
    end
end

local function preventAttackAlly(bot)
    local attackTarget = bot.attackTarget
    local isAllies = TTTBots.Roles.IsAllies(bot, attackTarget)
    if isAllies then
        bot:SetAttackTarget(nil)
    end
end

local PS_RADIUS = 100
local PS_INTERVAL = 5 -- time before we start caring about personal space
local function personalSpace(bot)
    bot.personalSpaceTbl = bot.personalSpaceTbl or {}
    local ticked = {}
    if not TTTBots.Roles.GetRoleFor(bot):GetUsesSuspicion() then return end
    if IsValid(bot.attackTarget) then return end -- don't care about personal space if we're attacking someone

    local withinPSpace = lib.FilterTable(TTTBots.Match.AlivePlayers, function(other)
        if other == bot then return false end
        if not IsValid(other) then return false end
        if not lib.IsPlayerAlive(other) then return false end
        -- The tick's shared answer: this pass runs once a second for every bot and asks about every other
        -- player, which is the same set of pairs the memory pass in the same tick already traced.
        if not lib.SeenThisTick(bot, other) then return false end
        if TTTBots.Roles.IsAllies(bot, other) then return false end -- don't care about allies

        local dist = bot:GetPos():Distance(other:GetPos())
        if dist > PS_RADIUS then return false end

        return true
    end)

    for i, other in pairs(withinPSpace) do
        bot.personalSpaceTbl[other] = (bot.personalSpaceTbl[other] or 0) + 0.5
        ticked[other] = true
    end

    for other, time in pairs(bot.personalSpaceTbl) do
        if not ticked[other] then
            bot.personalSpaceTbl[other] = math.max(time - 0.5, 0)
        end

        if (bot.personalSpaceTbl[other] or 0) <= 0 then
            bot.personalSpaceTbl[other] = nil
        end

        if (bot.personalSpaceTbl[other] or 0) >= PS_INTERVAL then
            local morality = bot:BotMorality() -- NOTE: the accessor is BotMorality, not GetMorality
            if morality then
                morality:ChangeSuspicion(other, "PersonalSpace")
            end
            local chatter = bot:BotChatter()
            if chatter then
                -- The localized lines use {{player}}, so we MUST pass the player or the raw
                -- placeholder leaks into chat (and then gets mangled by the typo pass).
                chatter:On("PersonalSpace", { player = other:Nick() })
            end
            bot.personalSpaceTbl[other] = nil
        end
    end
end

--- Why the weapon this player has out gives them away, or nil if there is nothing telling about it.
---
--- The only weapon that counts is one a role is given by its own loadout: the Arsonist's thrower, the
--- Shanker's knife. No shop sells it and no map spawns it, so somebody holding one is that role, and the
--- tell names a specific role rather than a team.
---
--- A shop weapon is deliberately NOT a tell. A role can borrow another team's shop (the Revolutionary
--- shops from the traitors'), the same weapon may be on sale to more than one team (the Dragon Elites is a
--- traitor and detective purchase), and anyone can loot one off a corpse - so carrying one says nothing
--- about who is holding it, and bots were shooting innocents over it.
---@param bot Bot The witness, which decides whether the weapon's role is on its own team.
---@param ply Player
---@return string? reason A key of SUSPICIONVALUES
local function getWeaponTell(bot, ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return nil end

    local roleName = TTTBots.Roles.GetRoleOfWeapon(wep:GetClass())
    if not roleName then return nil end

    -- A role weapon only gives somebody away when the role is not on our own team. Nothing registered is on
    -- the innocent team today, but a knife belonging to a friendlier role is exactly the shape of role
    -- weapon that would be a team kill to act on, and this should not depend on that staying true.
    if TTTBots.Roles.GetRole(roleName):GetTeam() == bot:GetTeam() then return nil end

    return "RoleWeapon"
end

--- Call out anybody walking around with a weapon that only one role is given.
---
--- The tell is worth a KOS on its own, which is why it sits at the top of the scale. The old version of
--- this check was pointing guns rather than raising suspicion - it called SetAttackTarget on whoever the
--- witness could see, so one witness's glance was an instant shooting order. Going through the scale means
--- the KOS is announced, other bots weigh it up like any other callout, and a role that appears to be
--- police stays dampened.
local function noticeRoleWeapons(bot)
    if not TTTBots.Roles.GetRoleFor(bot):GetUsesSuspicion() then return end

    local morality = bot:BotMorality()
    if not morality then return end

    local visible = getSeenPlayers(bot)

    for _, other in ipairs(visible) do
        -- This runs every second, and suspicion accumulates: once the holder is already over the KOS
        -- threshold there is nothing left to add. It also stops the scan from stacking on one player
        -- for as long as they keep the weapon out.
        if morality:GetSuspicion(other) >= morality.Thresholds.KOS then continue end
        if not TTTBots.Lib.CanSeeArc(bot, other:GetPos() + Vector(0, 0, 24), 90) then continue end

        local reason = getWeaponTell(bot, other)
        if not reason then continue end

        morality:ChangeSuspicion(other, reason)
        bot:BotChatter():On("HoldingTraitorWeapon", { player = other:Nick() })
    end
end

local function commonSense(bot)
    continueMassacre(bot)
    preventAttackAlly(bot)
    personalSpace(bot)
    noticeRoleWeapons(bot)
end

timer.Create("TTTBots.Components.Morality.CommonSense", 1, 0, function()
    if not TTTBots.Match.IsRoundActive() then return end
    for i, bot in pairs(TTTBots.Bots) do
        if not bot or bot == NULL or not IsValid(bot) then continue end
        if not (bot.components and bot.components.chatter) or not bot:BotLocomotor() then continue end
        if not lib.IsPlayerAlive(bot) then continue end
        commonSense(bot)
    end
end)

---@class Player
local plyMeta = FindMetaTable("Player")
---@return CMorality?
function plyMeta:BotMorality()
    ---@cast self Bot
    -- Nil for anything that is not a fully initialized bot, which callers already have to handle: bots are
    -- created as entities before their components exist, and a bot whose component creation failed is
    -- kicked while still valid. Returning nil here rather than reading components blindly is what a stale
    -- reference to such a bot would otherwise turn into an "attempt to index field 'components'" crash.
    -- Matches plyMeta:BotMemory.
    return self.components and self.components.morality
end
