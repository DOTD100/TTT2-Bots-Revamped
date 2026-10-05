---@class Match
TTTBots.Match = {}
---@type table<Bot>
TTTBots.Bots = {} --- Bots in the game right now. We have to do this because of a silly bug with TTTBots.Bots

timer.Create("TTTBots.Match.UpdateBotsTable", 1, 0, function()
    TTTBots.Bots = {}
    for i, v in pairs(player.GetAll()) do
        -- Only bots that finished initializing. A bot's entity exists from player.CreateNextBot, which is
        -- *before* createPlayerBot builds its components, and a bot whose component creation failed is
        -- kicked but stays a valid entity until the kick lands - so the list used to hand out bots with no
        -- components, and every caller that reached for one crashed on the nil (BotMorality in CallKOS
        -- being the one that got caught in the wild). Everything in this list is ticked, so nothing that
        -- is not fully built belongs in it.
        if v:IsBot() and v.components then
            table.insert(TTTBots.Bots, v)
        end
    end
end)

---@class Match
local Match = TTTBots.Match

Match.RoundActive = Match.RoundActive or false
---Set while the post-round deathmatch is running, i.e. between TTTEndRound and the next round's
---prep. Detected from the round hooks rather than a round state enum, so it works on both TTT and
---TTT2 and needs no knowledge of the gamemode's timing.
Match.DeathmatchActive = false
--- This is not a table of ragdolls but a table of corpse data.
Match.Corpses = Match.Corpses or {}
--- List of players in the round. Does not tell you if they are alive or not.
Match.PlayersInRound = Match.PlayersInRound or {}
Match.ConfirmedDead = Match.ConfirmedDead or {}
Match.DamageLogs = Match.DamageLogs or {}
Match.AlivePlayers = {}
Match.AliveTraitors = {} ---@deprecated
Match.AliveHumanTraitors = {} ---@deprecated
Match.AliveNonEvil = {} ---@deprecated
Match.AlivePolice = {} ---@deprecated
Match.DisguisedPlayers = {}
Match.SecondsPassed = 0 --- Time since match began. This is important for traitor bots.
Match.KOSCounter = {} ---@type table<Player, number>
--- List of active KOS calls. Indexed by person called out, with each value being a table of people who called them out.
Match.KOSList = {} ---@type table<Player, table<Player>>
Match.SpottedC4s = {} ---@type table<Entity, boolean> Armed C4 that has been spotted by the innocent bots at least once. key and value are the same entity
Match.AllArmedC4s = {} ---@type table<Entity, boolean>
Match.C4s = {} ---@type table<Entity> every C4 in the world, armed or not, refreshed once a second by UpdateC4List
Match.Smokes = {}

--- Stamp (or clear) each bot's life clock for Match.KillDelayElapsed.
---
--- Bots are not recreated between rounds and a revive is not an event this addon owns, so the clock is derived
--- from what the tick can see: alive and unstamped means this life started now, dead means the next life gets
--- its own clock. That covers a round spawn, a respawn, a defibrillator revive and a role change that changes
--- nothing about being alive, without a hook for each of them.
local function updateKillDelayClocks()
    local now = CurTime()
    for _, bot in pairs(TTTBots.Bots) do
        if not (IsValid(bot) and bot.components) then continue end

        if TTTBots.Lib.IsPlayerAlive(bot) then
            bot.killDelayAliveSince = bot.killDelayAliveSince or now
        else
            bot.killDelayAliveSince = nil
        end
    end
end

function Match.Tick()
    if not Match.RoundActive then return end
    Match.CleanupNullCorpses()
    Match.SecondsPassed = (Match.Time()) + (1 / TTTBots.Tickrate)

    if SERVER then updateKillDelayClocks() end
end

--- Returns true if enough time, as defined by plans_mindelay and _maxdelay, has passed since the round began. Used for automatic plan execution by bots.
---@realm server
function Match.PlansCanStart()
    if not Match.RoundActive then return false end
    local minTime = TTTBots.Lib.GetConVarFloat("plans_mindelay")
    local time = Match.Time()
    if time < minTime then return false end
    local maxTime = TTTBots.Lib.GetConVarFloat("plans_maxdelay")
    if time > maxTime then return true end
    local minInt = math.floor(minTime)
    local maxInt = math.floor(maxTime)
    if maxInt < minInt then maxInt = minInt end
    local randi = math.random(minInt, maxInt)
    return time > randi
end

--- May this bot pick a fight of its own accord yet?
---
--- Every path that hands a bot a victim **without** being provoked has to ask this first: the random-nearby
--- roll and the last-player-standing rule in components/sv_morality.lua, and the plan system's attack orders in
--- lib/sv_plancoordinator.lua. Everything provoked stays outside it - being shot at or hurt, seeing a teammate
--- shot, a KOS from another bot - because a bot must always be allowed to shoot back, and that is the line this
--- gate draws. A role whose job is murder on contract (the Hitman, the Executioner) is left alone as well: its
--- victim comes from its own addon, so holding it back would break the role rather than the round's opening.
---
--- Two clocks have to have run out, and `ttt_bot_attack_delay` is both of them:
---
---   * the **round's** age, which is what stops a traitor picking its victim on the first tick of a round, and
---   * the age of the bot's own **life**, which the round clock alone cannot cover: a bot that spawns late or
---     is brought back by a defibrillator is a fresh arrival at a round that may already be minutes old and
---     would otherwise be free to kill the moment it stands up. `bot.killDelayAliveSince` is stamped and
---     cleared by Match.Tick while the bot lives and dies.
---
--- This is the same shape as the RDM delay, which needed exactly this pair of clocks for the same reason. The
--- RDM feature keeps its own copy (`bot.rdmAliveSince`) on purpose: that one is about a bot which has had
--- enough of the server, and it has to keep working when this gate is wide open.
---@param bot Bot
---@return boolean
function Match.KillDelayElapsed(bot)
    if not Match.RoundActive then return false end
    if not (IsValid(bot) and bot.killDelayAliveSince) then return false end

    local delay = TTTBots.Lib.GetConVarFloat("attack_delay")
    if Match.Time() < delay then return false end

    return (CurTime() - bot.killDelayAliveSince) >= delay
end

--- Check if the match should trust this individual's KOS. This is used to limit KOS calls to 1 per user per round;
--- for bots it is used to prevent chat spam.
---@param ply Player
---@param dontIterate nil|boolean (OPTIONAL=false)
---@return boolean is_trustworthy - if we can trust this player's KOS
---@realm server
function Match.KOSIsApproved(ply, dontIterate)
    if not Match.IsRoundActive() then return false end
    local MAX_KOS_PER_PLY = TTTBots.Lib.GetConVarInt("kos_limit")
    local amt = Match.KOSCounter[ply] or 0

    if amt < MAX_KOS_PER_PLY then
        Match.KOSCounter[ply] = amt + (dontIterate and 0 or 1)
        return true
    end

    return false -- do not trust; if bot, then prevent chatting
end

--- Handles the heavy lifting for a KOS call. After verifying the caller hasn't hit the limit, this calls OnKOSCalled across each TTTBot in the match.
---@param caller Player
---@param target Player
---@return boolean success
---@realm server
function Match.CallKOS(caller, target)
    if not Match.IsRoundActive() then return false end
    if TTTBots.Roles.GetRoleFor(target):GetAppearsPolice() then return false end
    local isApproved = Match.KOSIsApproved(caller)
    if not isApproved then return false end

    Match.KOSList[target] = Match.KOSList[target] or {}
    Match.KOSList[target][caller] = caller

    for i, bot in pairs(TTTBots.Bots) do
        local morality = bot:BotMorality()
        if not morality then continue end
        morality:OnKOSCalled(caller, target)
    end

    return true
end

--- Returns the time in seconds since the match began.
---@return number seconds
---@realm shared
function Match.Time()
    return (Match.RoundActive and Match.SecondsPassed) or 0
end

---@realm shared
function Match.IsRoundActive()
    return Match.RoundActive
end

---True during the post-round deathmatch. The round is over, dead players have respawned, and everyone
---is allowed to kill everyone, so bots stop caring about teams until the next round starts.
---@realm shared
---@return boolean
function Match.IsDeathmatchActive()
    if not Match.DeathmatchActive then return false end
    if not TTTBots.Lib.GetConVarBool("deathmatch") then return false end

    return true
end

---@realm shared
function Match.CleanupNullCorpses()
    local corpses = Match.Corpses
    for i = #corpses, 1, -1 do
        local v = corpses[i]
        if not IsValid(v) or v == NULL then
            table.remove(corpses, i)
        end
    end
end

---@realm shared
function Match.ResetStats(roundActive)
    Match.RoundActive = roundActive or false
    Match.Corpses = {}
    Match.ConfirmedDead = {}
    Match.PlayersInRound = {}
    Match.DamageLogs = {}
    Match.AlivePlayers = {}
    Match.SecondsPassed = 0
    Match.DisguisedPlayers = {}
    Match.KOSCounter = {}
    Match.KOSList = {}
    Match.SpottedC4s = {}
    Match.AllArmedC4s = {}
    Match.RoundID = TTTBots.Lib.GenerateID()
    Match.Smokes = {}

    if SERVER then
        -- This runs on TTTPrepareRound, TTTBeginRound *and* TTTEndRound. TTTBots.Bots is only
        -- refreshed once a second by a timer, so a bot that has just been removed - the addon kicks
        -- and recreates its own bots over time - can still be listed here. Calling into a dead
        -- entity is what used to break the round boundary.
        for i, v in pairs(TTTBots.Bots) do
            if not (IsValid(v) and v.components) then continue end
            v:SetAttackTarget(nil)
            -- Clear per-round grudges so a bot cannot carry "who killed me" from a previous round
            -- into a fresh one (the bot entities persist across rounds).
            v.grudge = nil
            v.grudgeReasserted = nil
            -- And hand every bot a fresh life clock for Match.KillDelayElapsed: Match.Tick does not run
            -- during the preparation phase, so a stamp from the last round would otherwise still be sitting
            -- there when the next one begins.
            v.killDelayAliveSince = nil
        end
    end
end

---Gets the difficulty scoring of the given bot. Returns -1 if the bot is not a TTTBot.
---@param bot Bot
---@return number difficulty
---@realm server
function Match.GetBotDifficulty(bot)
    local personality = bot:BotPersonality()
    if not personality then return -1 end
    local diff = personality:GetDifficulty()
    return diff
end

--- Returns a table of all bots in the game, indexed by bot object, with each key as the estimated difficulty score.
---@return table<Bot, number> botDifficulty
---@realm server
function Match.GetBotsDifficulty()
    local tbl = {}
    for i, bot in pairs(TTTBots.Bots) do
        local diff = Match.GetBotDifficulty(bot)
        tbl[bot] = diff
    end
    return tbl
end

--- Comb thru the damage logs and find the player who shot the other first.
---@realm server
function Match.WhoShotFirst(ply1, ply2)
    local hansolo = nil
    local oldestTime = math.huge
    for i, log in pairs(Match.DamageLogs) do
        if (log.victim == ply1 or log.attacker == ply1) and (log.victim == ply2 or log.attacker == ply2) then
            if log.time < oldestTime then
                oldestTime = log.time
                hansolo = log.attacker
            end
        end
    end
    return hansolo -- hehehehe get it?
end

---@realm shared
function Match.UpdateAlivePlayers()
    Match.AlivePlayers = {}
    Match.DisguisedPlayers = {}
    for bot, isAlive in pairs(TTTBots.Lib.GetPlayerLifeStates()) do
        if not (bot and isAlive) or bot == NULL or not IsValid(bot) then continue end
        table.insert(Match.AlivePlayers, bot)
        -- Check if player is disguised, and if so, add them to the disguised tbl
        local isDisguised = bot:GetNWBool("disguised", false)
        if isDisguised then
            Match.DisguisedPlayers[bot] = true
        end
    end
end

---@realm shared
function Match.IsPlayerDisguised(ply)
    return Match.DisguisedPlayers[ply] or false
end

---Event called when an innocent bot spots a C4.
---@param bot Bot
---@param c4 Entity
---@realm server
function Match.OnBotSpotC4(bot, c4)
    local chatter = bot:BotChatter()
    local locomotor = bot:BotLocomotor()
    if not chatter then return end
    chatter:On("SpottedC4", {}, false)
    if locomotor and IsValid(c4) then
        locomotor:LookAt(c4:GetPos())
    end

    -- Don't let every non-kit bot gamble on a defuse. If a living ally is carrying a defuse kit,
    -- call them over instead (and if that ally is a bot, send them to the bomb directly).
    -- Delayed so it doesn't collide with the "SpottedC4" line (chatter only speaks one at a time).
    timer.Simple(2, function()
        if not (IsValid(bot) and IsValid(c4)) then return end
        local Defuse = TTTBots.Behaviors and TTTBots.Behaviors.Defuse
        if not Defuse then return end
        if Defuse.HasDefuseKit(bot) then return end

        local kitHolder = Defuse.FindAliveAllyWithKit(bot)
        if not kitHolder then return end

        local respotterChatter = bot:BotChatter()
        if not respotterChatter then return end
        -- Public to match the existing SpottedC4 / DefusingC4 callouts.
        respotterChatter:On("RequestDefuser", { player = kitHolder:Nick() }, false)

        if kitHolder:IsBot() then
            kitHolder.requestedDefuseC4 = c4
        end
    end)
end

---@realm server
function Match.BotsTrySpotC4()
    for i, bot in pairs(TTTBots.Bots) do
        if not TTTBots.Lib.IsPlayerAlive(bot) then continue end
        if not TTTBots.Roles.GetRoleFor(bot):GetDefusesC4() then continue end

        for c4, _ in pairs(Match.AllArmedC4s) do
            if not IsValid(c4) then continue end

            if not Match.SpottedC4s[c4] then
                local canSee = TTTBots.Lib.CanSeeArc(bot, c4:GetPos() + Vector(0, 0, 16), 120)
                if canSee and (bot:GetPos():Distance(c4:GetPos()) < 2000) then
                    Match.SpottedC4s[c4] = true
                    Match.OnBotSpotC4(bot, c4)
                end
            end
        end
    end
end

function Match.IsSmokeDataActive(data)
    local timeNow = CurTime()
    local startTime = data.startTime
    local endTime = data.endTime
    return not (timeNow > endTime or timeNow < startTime)
end

local SMOKE_DIST = 256
function Match.IsPlyNearSmoke(ply)
    local smokes = Match.Smokes
    local plyPos = ply:GetPos()
    for i, data in pairs(smokes) do
        if not Match.IsSmokeDataActive(data) then continue end

        local center = data.center
        local dist = plyPos:Distance(center)
        if dist < SMOKE_DIST then
            return true
        end
    end

    return false
end

timer.Create("TTTBots.Match.UpdateAlivePlayers", 0.34, 0, function()
    Match.UpdateAlivePlayers()
end)

hook.Add("TTTBeginRound", "TTTBots.Match.BeginRound", function()
    Match.ResetStats(true)
    for _, ply in pairs(player.GetAll()) do
        if TTTBots.Lib.IsPlayerAlive(ply) then
            Match.PlayersInRound[ply] = true
        end
    end
    Match.UpdateAlivePlayers()
end)

hook.Add("TTTEndRound", "TTTBots.Match.EndRound", function()
    Match.ResetStats(false)
end)

hook.Add("TTTPrepareRound", "TTTBots.Match.PrepareRound", function()
    Match.ResetStats(false)
end)

-- The deathmatch window opens when the round ends and closes the moment the next one begins.
hook.Add("TTTEndRound", "TTTBots.Match.Deathmatch.Start", function()
    Match.DeathmatchActive = true
end)

hook.Add("TTTPrepareRound", "TTTBots.Match.Deathmatch.Stop", function()
    Match.DeathmatchActive = false
end)

hook.Add("TTTBeginRound", "TTTBots.Match.Deathmatch.Stop", function()
    Match.DeathmatchActive = false
end)

if SERVER then
    hook.Add("TTTOnCorpseCreated", "TTTBots.Match.OnCorpseCreated", function(corpse)
        if not Match.RoundActive then return end
        table.insert(Match.Corpses, corpse)
    end)

    hook.Add("TTTBodyFound", "TTTBots.Match.BodyFound", function(discoverer, deceased, ragdoll)
        if not Match.RoundActive then return end
        if not IsValid(deceased) then return end
        if not deceased:IsPlayer() then return end
        if not Match.PlayersInRound[deceased] then return end
        Match.ConfirmedDead[deceased] = true
    end)

    hook.Add("PlayerHurt", "TTTBots.Match.PlayerHurt", function(victim, attacker, healthRemaining, damageTaken)
        if not Match.RoundActive then return end
        if not (IsValid(victim) and IsValid(attacker) and victim:IsPlayer() and attacker:IsPlayer()) then return end
        table.insert(Match.DamageLogs, {
            victim = victim,
            attacker = attacker,
            healthRemaining = healthRemaining,
            damageTaken = damageTaken,
            time = CurTime()
        })
    end)

    hook.Add("TTTPlayerRadioCommand", "TTTBots.Match.TTTRadioMessage", function(ply, msgName, msgTarget)
        if msgName ~= "quick_traitor" then return end
        if not (ply and msgTarget) then return end
        if not (IsValid(ply) and IsValid(msgTarget)) then return end
        local callerAlive = TTTBots.Lib.IsPlayerAlive(ply)
        local targetAlive = TTTBots.Lib.IsPlayerAlive(msgTarget)
        if not (callerAlive and targetAlive) then return end
        Match.CallKOS(ply, msgTarget)
    end)

    timer.Create("TTTBots.Match.UpdateC4List", 1, 0, function()
        if not Match.RoundActive then return end
        local bombs = ents.FindByClass("ttt_c4")

        Match.AllArmedC4s = {}
        Match.C4s = {}

        for i, c4 in pairs(bombs) do
            if not IsValid(c4) then continue end
            Match.C4s[#Match.C4s + 1] = c4
            if not c4:GetArmed() then continue end
            Match.AllArmedC4s[c4] = true
        end

        Match.BotsTrySpotC4()
    end)

    hook.Add("EntityRemoved", "TTTBots.Match.UpdateSmokes", function(ent, fullUpdate)
        if not IsValid(ent) then return end
        local class = ent:GetClass()
        if string.find(class, "smoke") and ent.was_thrown and ent.GetDetTime then
            local data = {
                startTime = ent:GetDetTime(),
                endTime = ent:GetDetTime() + 30,
                center = ent:GetPos(),
                ent = ent
            }
            table.insert(Match.Smokes, data)
        end
    end)
end
