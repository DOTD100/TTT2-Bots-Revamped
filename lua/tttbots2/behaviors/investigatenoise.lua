---@class InvestigateNoise
TTTBots.Behaviors.InvestigateNoise = {}

local lib = TTTBots.Lib

---@class InvestigateNoise
local InvestigateNoise = TTTBots.Behaviors.InvestigateNoise
InvestigateNoise.Name = "Investigate Noise"
InvestigateNoise.Description = "Investigates a suspicious noises"

InvestigateNoise.INVESTIGATE_CATEGORIES = {
    Gunshot = true,
    Death = true,
    C4Beep = false, -- Disabled due to behavior where bot would hover around an armed bomb that's about to explode
    Explosion = true
}

--- How close the bot has to get to a remembered noise before the investigation is over. There is nothing to see
--- once it is there - whatever made the noise has moved on - so arriving is the whole of it. Without this the bot
--- re-issued the same goal from the same remembered sound every tick and stood on the spot staring at it until
--- the sound was culled from memory, which is the "bot goes AFK after hearing something" report.
local INVESTIGATE_ARRIVE_DIST = 120

--- How recently a gunshot has to have been heard for it to be urgent enough to skip the dice roll below. A shot
--- means something is happening *now*, and a bot that weighs that up with a random chance instead is the reason
--- it could stand still while a fight carried on a floor above it.
local GUNSHOT_URGENT_WINDOW = 2

--- How long one committed noise investigation may take before the bot gives up on it. A source it cannot reach -
--- across a gap, or behind a path that keeps failing - must not hold the behaviour for the rest of the round.
local INVESTIGATE_TIMEOUT = 20

---@class Bot
---@field investigateNoiseTimer number The last time the bot investigated a noise
---@field investigateNoiseTarget table? The noise this bot is walking to, if any

local STATUS = TTTBots.STATUS

function InvestigateNoise.GetInterestingSounds(bot)
    ---@type CMemory
    local memory = bot.components.memory
    local sounds = memory:GetRecentSounds()
    local interesting = {}
    for i, v in pairs(sounds) do
        local wasme = v.ent == bot or v.ply == bot
        if not wasme and InvestigateNoise.INVESTIGATE_CATEGORIES[v.sound] then
            table.insert(interesting, v)
        end
    end
    return interesting
end

function InvestigateNoise.FindClosestSound(bot, mustBeVisible)
    mustBeVisible = mustBeVisible or false
    local sounds = InvestigateNoise.GetInterestingSounds(bot)
    local closestSound = nil
    local closestDist
    for i, v in pairs(sounds) do
        local dist = bot:GetPos():Distance(v.pos)
        local visible = (mustBeVisible and bot:VisibleVec(v.pos)) or not mustBeVisible
        if (closestDist == nil or dist < closestDist) and visible then
            closestDist = dist
            closestSound = v
        end
    end
    return closestSound
end

--- Whether this noise is urgent enough to skip the dice roll: a gunshot heard moments ago means something is
--- happening right now, and going to look immediately is what a player does.
---@param sound table A recentSounds entry
---@return boolean
function InvestigateNoise.IsUrgentNoise(sound)
    return sound.sound == "Gunshot" and (CurTime() - sound.time) <= GUNSHOT_URGENT_WINDOW
end

--- The noise this bot has committed to, or nil.
---
--- Committing is what stops several shots from taking turns as "the closest noise" and flipping the goal between
--- two positions every tick, which is a bot shuffling on the spot; the bot picks once, walks the whole way, and
--- only picks again once it arrives (where a newer shot, if there is one, wins).
---@param bot Bot
---@return table? noise
function InvestigateNoise.GetCommittedNoise(bot)
    local noise = bot.investigateNoiseTarget
    if not noise then return nil end

    if (CurTime() - noise.committedAt) > INVESTIGATE_TIMEOUT then
        bot.investigateNoiseTarget = nil
        return nil
    end

    return noise
end

function InvestigateNoise.OnStart(bot)
    bot.components.chatter:On("InvestigateNoise", {})
    return STATUS.RUNNING
end

function InvestigateNoise.OnRunning(bot)
    local loco = bot:BotLocomotor()

    local noise = InvestigateNoise.GetCommittedNoise(bot)
    if not noise then
        -- Visibility no longer decides anything: the bot used to look at a noise it could see the source of and
        -- walk only to one it could not - and because a visibility trace passes through stairwells, railings and
        -- glass, "it can see the gunshot" was often a shooter one floor up. Every noise is walked to now.
        local closest = InvestigateNoise.FindClosestSound(bot, false)
        if not closest then return STATUS.SUCCESS end

        -- The dice roll decides whether we bother at all, and it is asked once per commitment rather than once
        -- per tick - except for a fresh gunshot, which is not something to weigh up.
        if not InvestigateNoise.IsUrgentNoise(closest) and not InvestigateNoise.ShouldInvestigateNoise(bot) then
            return STATUS.FAILURE
        end

        noise = {
            pos = closest.pos,
            sound = closest.sound,
            heardAt = closest.time,
            committedAt = CurTime(),
        }
        bot.investigateNoiseTarget = noise
    end

    -- Arrived, and there is nothing here to see: the investigation is over.
    if bot:GetPos():Distance(noise.pos) < INVESTIGATE_ARRIVE_DIST then
        bot.investigateNoiseTarget = nil
        return STATUS.SUCCESS
    end

    loco:LookAt(noise.pos + Vector(0, 0, 72))
    loco:SetGoal(noise.pos)
    return STATUS.RUNNING
end

--- Return true/false based off of a random chance. This is meant to be called every tick (5x per sec as of writing), so the chance is low by default.
---@param bot Bot
function InvestigateNoise.ShouldInvestigateNoise(bot)
    local MTB = lib.GetConVarInt("noise_investigate_mtb")
    if bot.investigateNoiseTimer and bot.investigateNoiseTimer > CurTime() then
        return false
    else
        bot.investigateNoiseTimer = CurTime() + MTB
    end
    local mult = bot:GetTraitMult("investigateNoise")
    local baseChance = lib.GetConVarInt("noise_investigate_chance")
    local pct = baseChance * mult

    local passed = lib.TestPercent(pct)
    return passed
end

function InvestigateNoise.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end

    -- A committed walk outlives the sound it came from. Memory drops a noise as soon as the bot can see where it
    -- came from (Memory:CullSoundMemory), and a bot walking towards a noise is looking straight at it - so
    -- without this the walk would end half way there and the bot would stop in the open.
    if bot.investigateNoiseTarget then return true end

    return #InvestigateNoise.GetInterestingSounds(bot) > 0
end

function InvestigateNoise.OnFailure(bot) end

function InvestigateNoise.OnSuccess(bot) end

function InvestigateNoise.OnEnd(bot)
    -- Whatever interrupted the walk (a fight, a corpse, the tree moving on) ends the commitment with it.
    bot.investigateNoiseTarget = nil
end
