
---@class InvestigateCorpse
TTTBots.Behaviors.InvestigateCorpse = {}

local lib = TTTBots.Lib
---@class InvestigateCorpse
local InvestigateCorpse = TTTBots.Behaviors.InvestigateCorpse
InvestigateCorpse.Name = "InvestigateCorpse"
InvestigateCorpse.Description = "Investigate the corpse of a fallen player"
InvestigateCorpse.Interruptible = true

local STATUS = TTTBots.STATUS

---@deprecated deprecated until distance check, technically works tho
function InvestigateCorpse.GetVisibleCorpses(bot)
    local corpses = TTTBots.Match.Corpses
    local visibleCorpses = {}
    for i, corpse in pairs(corpses) do
        local visible = bot:VisibleVec(corpse:GetPos())
        if visible then
            table.insert(visibleCorpses, corpse)
        end
    end
    return visibleCorpses
end

local CORPSE_MAXDIST = 2000
function InvestigateCorpse.GetVisibleUnidentified(bot)
    local corpses = TTTBots.Match.Corpses
    local results = {}
    for i, corpse in pairs(corpses) do
        if not IsValid(corpse) then continue end
        if InvestigateCorpse.IsOurBoomBody(bot, corpse) then continue end
        local visible = lib.CanSeeEntity(bot, corpse)
        local found = CORPSE.GetFound(corpse, false)
        local distTo = bot:GetPos():Distance(corpse:GetPos())
        -- TTTBots.DebugServer.DrawCross(corpse:GetPos(), 10, Color(255, 0, 0), 1, "body")
        if not found and visible and distTo < CORPSE_MAXDIST then
            table.insert(results, corpse)
        end
    end
    return results
end

--- Called every tick; basically just rolls a dice for if we should investigate any corpses this tick
function InvestigateCorpse.GetShouldInvestigateCorpses(bot)
    local BASE_PCT = 75
    local MIN_PCT = 5
    local personality = bot:BotPersonality()
    if not personality then return false end
    local mult = personality:GetTraitMult("investigateCorpse")
    return lib.TestPercent(
        math.max(MIN_PCT, BASE_PCT * mult)
    )
end

--- Is this a Boom Body trap *we* set?
---
--- Its owner is the one player the addon tells: they get marker vision for the body and the option to pick
--- their weapon back up. Searching it is what detonates it, so a traitor bot that read its own trap would
--- blow itself up with it. Nobody else is told anything, which is why this asks only about our own.
---@param bot Bot
---@param rag Entity
---@return boolean
function InvestigateCorpse.IsOurBoomBody(bot, rag)
    if not IsValid(rag) or not rag.isBoomBody then return false end
    if not rag.GetNWEntity then return false end

    return rag:GetNWEntity("boom_body_owner") == bot
end

function InvestigateCorpse.CorpseValid(rag, bot)
    if rag == nil then return false, "nil" end                         -- The corpse is nil.
    if not IsValid(rag) then return false, "invalid" end               -- The corpse is invalid.
    if not lib.IsValidBody(rag) then return false, "invalidbody" end   -- The corpse is not a valid body.
    if CORPSE.GetFound(rag, false) then return false, "discovered" end -- The corpse was discovered.
    if bot and InvestigateCorpse.IsOurBoomBody(bot, rag) then return false, "our own trap" end

    return true, "valid"
end

--- Validate the behavior
function InvestigateCorpse.Validate(bot)
    -- A role on the server can hide the dead from everybody else (TTT2's Blocker): while one is alive,
    -- nothing but that role may identify a body. Bots learn a body's role with a direct CORPSE.ShowSearch
    -- call rather than through the hook such a role installs, so without this the bot would walk over and
    -- identify the very bodies it is supposed to be kept out of - and would then re-target them forever,
    -- since they never become found.
    if TTTBots.Roles.IsCorpseIdentifyBlockedFor(bot) then return false end

    if not InvestigateCorpse.GetShouldInvestigateCorpses(bot) then return false end

    -- First, let's prevent traitors from immediately self-reporting.
    local lastKillTime = bot.lastKillTime or 0
    local killedRecently = (CurTime() - lastKillTime) < 7 -- killed someone within X seconds
    if killedRecently then return false end

    local curCorpse = bot.corpseTarget
    if InvestigateCorpse.CorpseValid(curCorpse) then
        return true
    end

    local options = InvestigateCorpse.GetVisibleUnidentified(bot)
    -- Roles that are told where bodies are (the Amnesiac's radar, for one) can offer candidates we
    -- have not laid eyes on yet. They get the same filtering as a visible corpse, minus line of sight,
    -- so a listener can never hand us an invalid body or send us across the whole map. With no
    -- listeners registered this stays a plain visibility check.
    if #options == 0 then
        local known = hook.Run("TTTBotsGetKnownCorpses", bot)
        if type(known) == "table" then
            options = lib.FilterTable(known, function(rag)
                if not IsValid(rag) then return false end
                if InvestigateCorpse.IsOurBoomBody(bot, rag) then return false end
                if CORPSE.GetFound(rag, false) then return false end

                return bot:GetPos():Distance(rag:GetPos()) < CORPSE_MAXDIST
            end)
        end
    end
    if #options == 0 then return false end

    local closest = lib.GetClosest(options, bot:GetPos())
    if not InvestigateCorpse.CorpseValid(closest) then return false end

    -- local unreachable = TTTBots.PathManager.IsUnreachableVec(bot:GetPos(), closest:GetPos())
    -- if not unreachable then
    --     print("Found corpse but it was unreachable")
    --     return false
    -- end

    bot.corpseTarget = closest
    return true
end

--- Called when the behavior is started
function InvestigateCorpse.OnStart(bot)
    bot.components.chatter:On("InvestigateCorpse", { corpse = bot.corpseTarget })
    return STATUS.RUNNING
end

--- Take from the body what a searching player is shown, and hold it against whoever it names.
---
--- TTT2 records the killer on the ragdoll (`rag.killer_sample.killer`) when its own forensics say a trace was
--- left: within `ttt_killer_dna_range` (550 units by default) and before `ttt_killer_dna_basetime` has run out.
--- That is the same information the search window and a DNA scan give a player, so a bot that has just carried
--- out the search is entitled to it - and TTT2's own rules are what limit it. A killing from further away, or a
--- sample that had decayed, leaves nothing behind and this does nothing at all.
---
--- What the bot then does with it is the judgement the witnessed-kill path already makes (BotMorality's
--- Kill/KillTrusted/KillTraitor trio), so a body naming the killer of a traitor is good news to a traitor, and
--- a body naming the killer of an innocent is worth a KOS.
---@param bot Bot
---@param rag Entity
local function readKillerFromCorpse(bot, rag)
    local sample = rag.killer_sample
    local killer = sample and sample.killer
    if not (IsValid(killer) and killer:IsPlayer()) then return end
    -- Nothing to act on if they are already dead, and announcing a KOS against a corpse is the mistake the
    -- revived-callout fix made once already.
    if not lib.IsPlayerAlive(killer) then return end

    local victim = CORPSE.GetPlayer(rag)
    if not IsValid(victim) then return end
    -- A fool's corpse says nothing about its killer: the Jester and the Swapper are *meant* to be killed, and
    -- whoever obliged them is not a traitor for it. Same test the rest of the addon uses for that team.
    if TTTBots.Roles.IsFoolRole(victim) then return end

    local morality = bot:BotMorality() -- the accessor, not components.morality: a bot without one is not a bot
    if not morality then return end

    if TTTBots.Roles.IsTraitor(victim) then
        morality:ChangeSuspicion(killer, "KillTraitor")
    elseif TTTBots.Roles.GetRoleFor(victim):GetAppearsPolice() then
        morality:ChangeSuspicion(killer, "KillTrusted")
    else
        morality:ChangeSuspicion(killer, "CorpseKiller")
    end
end

--- Called when the behavior's last state is running
function InvestigateCorpse.OnRunning(bot)
    local validation = InvestigateCorpse.CorpseValid(bot.corpseTarget, bot)
    if not validation then
        return STATUS.FAILURE
    end
    -- Identification can become impossible again while the bot is already walking to a body: a
    -- defibrillator can put the role that blocks it back into the round. Stop instead of standing over
    -- a body that will not open.
    if TTTBots.Roles.IsCorpseIdentifyBlockedFor(bot) then
        return STATUS.FAILURE
    end
    local loco = bot:BotLocomotor()
    loco:LookAt(bot.corpseTarget:GetPos())
    loco:SetGoal(bot.corpseTarget:GetPos())

    local distToBody = bot:GetPos():Distance(bot.corpseTarget:GetPos())
    if distToBody < 80 then
        loco:StopMoving()

        -- Search the way a player does, which means giving the game its say first. TTT2 runs
        -- TTTCanSearchCorpse as part of a player's search and only a `false` stops it, and roles hang real
        -- mechanics off that hook: the Blocker refuses every search but its own, and the Amnesiac does not
        -- identify the body at all - it *becomes* the dead player and then answers whether the body should
        -- also be confirmed. Our direct CORPSE.ShowSearch call sits below all of it, which is why an Amnesiac
        -- bot could never convert and why a bot that was meant to be kept out of a body still read it.
        if hook.Run("TTTCanSearchCorpse", bot, bot.corpseTarget, false) == false then
            return STATUS.SUCCESS
        end

        -- Whether somebody had already opened this body decides whether our search is the one that learns
        -- anything: an identified corpse has no fresh trace left to read, and re-reading one would let a second
        -- bot act on evidence it did not gather itself.
        local wasIdentified = CORPSE.GetFound(bot.corpseTarget, false)

        CORPSE.ShowSearch(bot, bot.corpseTarget, false, false)
        CORPSE.SetFound(bot.corpseTarget, true)

        if not wasIdentified then
            readKillerFromCorpse(bot, bot.corpseTarget)
        end

        return STATUS.SUCCESS
    end
    return STATUS.RUNNING
end

--- Called when the behavior returns a success state
function InvestigateCorpse.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function InvestigateCorpse.OnFailure(bot)
end

--- Called when the behavior ends
function InvestigateCorpse.OnEnd(bot)
    bot.corpseTarget = nil
end
