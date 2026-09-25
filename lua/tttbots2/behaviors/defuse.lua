
TTTBots.Behaviors.Defuse = {}

local lib = TTTBots.Lib

local Defuse = TTTBots.Behaviors.Defuse
Defuse.Name = "Defuse"
Defuse.Description = "Defuse a spotted bomb"
Defuse.Interruptible = true

Defuse.DEFUSE_RANGE = 80       --- The maximum range that a defuse attempt can be made
Defuse.ABANDON_TIME = 5        --- Seconds until explosion to abandon defuse attempt
Defuse.DEFUSE_WIN_CHANCE = 3   --- 1 in X chance of a successful defuse
Defuse.DEFUSE_TRY_CHANCE = 30  --- 1 in X chance of attempting to defuse (per tick) if other conditions not met

--- Seconds spent dithering next to the bomb before working on it. Standing next to a live bomb is
--- something a person has to talk themselves into, and it is also the window everyone else gets to
--- notice what we are doing, so bots should not snap straight to it like a robot.
local HESITATE_MIN = 2
local HESITATE_MAX = 5
--- A defuse kit holder knows what they are doing, so they only pause to line up.
local KIT_HESITATE = 1.5
--- How long one attempt takes. A kit holder does the job properly; everyone else fumbles with it.
local WORK_TIME = 3
local KIT_WORK_TIME = 2.5
--- Bots without a kit may simply refuse to do the job at all.
local FLEE_CHANCE = 2    -- 1 in X chance of bottling it entirely
local FLEE_TIME = 5      -- how long to keep running once we have
local FLEE_DISTANCE = 800 -- how far away from the bomb we try to get
local SCARED_TIME = 20   -- how long we stay away from bombs afterwards, so we cannot oscillate

local STATUS = TTTBots.STATUS

---@class Bot
---@field defuseTarget Entity? The bomb we are working on right now
---@field requestedDefuseC4 Entity? A bomb a teammate asked us to deal with
---@field c4HesitateUntil number? When we stop dithering and start working on the bomb
---@field c4WorkUntil number? When the current attempt resolves
---@field c4WorkSuccess boolean? Whether that attempt is going to succeed
---@field c4FleeUntil number? While set, we are running away from the bomb we chickened out of
---@field c4ScaredUntil number? Keeps us from being dragged back to a bomb we already fled

---Returns true if a bot is able to defuse C4 per their role data.
---@param bot Bot
---@return boolean
function Defuse.IsBotEligableRole(bot)
    local role = TTTBots.Roles.GetRoleFor(bot) ---@type RoleData
    if not role then return false end
    return role:GetDefusesC4()
end

---True if the given entity is a player holding a defuse kit.
---@param ply Player
---@return boolean
function Defuse.HasDefuseKit(ply)
    return (IsValid(ply) and ply:HasWeapon("weapon_ttt_defuser")) or false
end

---Find the closest living ally that is allowed to defuse and is carrying a defuse kit. Used to
---delegate the defuse to the kit holder instead of every bot gambling on it.
---@param bot Bot
---@return Player? kitHolder
function Defuse.FindAliveAllyWithKit(bot)
    local allies = TTTBots.Roles.GetLivingAllies(bot)
    local botPos = bot:GetPos()
    local best, bestDist = nil, math.huge
    for _, ally in ipairs(allies) do
        if ally == bot then continue end
        if not IsValid(ally) then continue end
        if not Defuse.IsBotEligableRole(ally) then continue end
        if not Defuse.HasDefuseKit(ally) then continue end
        local dist = botPos:Distance(ally:GetPos())
        if dist < bestDist then
            bestDist = dist
            best = ally
        end
    end
    return best
end

---Return whether or not a bot is elligible to defuse a C4 (does not factor in if there is one nearby)
---@param bot Bot
---@return boolean
function Defuse.IsEligible(bot)
    if not lib.IsPlayerAlive(bot) then return false end
    if not Defuse.IsBotEligableRole(bot) then return false end

    local personality = bot:BotPersonality()
    if not personality then return false end

    local isDefuser = personality:GetTraitBool("defuser")
    local hasDefuseKit = Defuse.HasDefuseKit(bot)
    local chance = math.random(1, Defuse.DEFUSE_TRY_CHANCE) == 1

    if hasDefuseKit or isDefuser or chance then
        return true
    end

    return false
end

---Returns the first visible C4 that has been spotted
---@param bot Bot
---@return Entity|nil C4
function Defuse.GetVisibleC4(bot)
    local allC4 = TTTBots.Match.AllArmedC4s
    local closest = nil
    local closestDist = math.huge
    for bomb, _ in pairs(allC4) do
        if not Defuse.IsC4Defusable(bomb) then continue end
        if not lib.CanSeeArc(bot, bomb:GetPos() + Vector(0, 0, 16), 120) then continue end
        local dist = bot:GetPos():Distance(bomb:GetPos())
        if dist < closestDist then
            closestDist = dist
            closest = bomb
        end
    end

    return closest
end

---True while a bot is still keeping away from bombs it has already run from. Without this the
---behavior would be re-selected by Validate on the very next tick and the bot would oscillate
---between sprinting away and walking back to the bomb.
---@param bot Bot
---@return boolean
function Defuse.IsScaredOfBombs(bot)
    return CurTime() < (bot.c4ScaredUntil or 0)
end

---Decide that this bomb is somebody else's problem and run from it for a while.
---@param bot Bot
function Defuse.StartFleeing(bot)
    bot.c4FleeUntil = CurTime() + FLEE_TIME
    bot.c4ScaredUntil = CurTime() + FLEE_TIME + SCARED_TIME
end

--- Somewhere to be that is not next to a bomb that is about to go off.
---@param bot Bot
---@param c4 Entity
---@return Vector
function Defuse.GetFleePos(bot, c4)
    local away = bot:GetPos() - c4:GetPos()
    away.z = 0
    if away:LengthSqr() < 1 then
        away = Vector(1, 0, 0)
    else
        away:Normalize()
    end

    return c4:GetPos() + away * FLEE_DISTANCE
end

--- Validate the behavior
function Defuse.Validate(bot)
    if not lib.GetConVarBool("defuse_c4") then return false end -- This behavior is disabled per the user's choice.
    if not TTTBots.Match.IsRoundActive() then return false end
    if not Defuse.IsBotEligableRole(bot) then return false end

    -- If a teammate called us over to a specific bomb, go to it even if we cannot see it yet.
    if bot.requestedDefuseC4 and Defuse.IsC4Defusable(bot.requestedDefuseC4) then
        return true
    end

    -- Already on a bomb: let OnRunning decide what happens next, including walking away from one.
    if bot.defuseTarget ~= nil then return true end

    -- We bottled it out of a bomb recently. Let somebody else deal with this one.
    if Defuse.IsScaredOfBombs(bot) then return false end

    -- If we don't have a kit but a living ally does, leave the defuse to them instead of every bot
    -- suicidally gambling on it. The spotter calls them over from Match.OnBotSpotC4.
    if not Defuse.HasDefuseKit(bot) and Defuse.FindAliveAllyWithKit(bot) then return false end

    if not Defuse.IsEligible(bot) then return false end
    return Defuse.GetVisibleC4(bot) ~= nil
end

--- Called when the behavior is started
function Defuse.OnStart(bot)
    -- Prefer a bomb we were explicitly asked to come defuse (we may not be able to see it yet).
    if bot.requestedDefuseC4 and Defuse.IsC4Defusable(bot.requestedDefuseC4) then
        bot.defuseTarget = bot.requestedDefuseC4
        bot.requestedDefuseC4 = nil
    else
        bot.defuseTarget = Defuse.GetVisibleC4(bot)
    end

    bot.c4WorkUntil = nil
    bot.c4WorkSuccess = nil
    -- The dithering clock only starts once we are actually stood at the bomb, otherwise a long walk
    -- over would eat the whole hesitation before we even got there.
    bot.c4HesitateUntil = nil

    -- No kit, no obligation. Bots that always throw themselves onto a bomb make the C4 feel
    -- toothless, so some of them should simply leg it instead.
    if not Defuse.HasDefuseKit(bot) and math.random(1, FLEE_CHANCE) == 1 then
        Defuse.StartFleeing(bot)
    end

    return STATUS.RUNNING
end

function Defuse.IsC4Defusable(c4)
    if c4 == NULL then return false end
    if not IsValid(c4) then return false end
    if not c4:GetArmed() then return false end
    if c4:GetExplodeTime() <= CurTime() then return false end

    return true
end

function Defuse.GetTimeUntilExplode(c4)
    local explodeTime = c4:GetExplodeTime()
    local ct = CurTime()
    return explodeTime - ct
end

---Begins one attempt on the bomb. The outcome is rolled here but only applied once the work time has
---elapsed, so the bot can be made to stand still for the whole thing instead of walking off while a
---timer finishes the job behind it.
---@param bot Bot
---@param workTime number How long this attempt will take.
function Defuse.BeginAttempt(bot, workTime)
    bot.c4WorkUntil = CurTime() + workTime
    bot.c4WorkSuccess = Defuse.HasDefuseKit(bot) or (math.random(1, Defuse.DEFUSE_WIN_CHANCE) == 1)
end

---Finishes an attempt.
---@param bot Bot
---@param c4 Entity
---@return boolean|nil - nil while the attempt is still in progress, true if it worked, false if not.
function Defuse.ResolveAttempt(bot, c4)
    local workUntil = bot.c4WorkUntil
    if not workUntil then return nil end
    if CurTime() < workUntil then return nil end

    local succeeded = bot.c4WorkSuccess
    bot.c4WorkUntil = nil
    bot.c4WorkSuccess = nil

    if not (IsValid(bot) and lib.IsPlayerAlive(bot)) then return false end
    if not Defuse.IsC4Defusable(c4) then return false end

    if succeeded then
        c4:Disarm(bot)

        local chatter = bot:BotChatter()
        if chatter then
            chatter:On("DefusingSuccessful")
        end

        -- Disarm may have already removed the entity; only clean up if it still exists.
        if IsValid(c4) then
            Defuse.DestroyC4(c4)
        end
        return true
    end

    -- A fumbled attempt. In TTT this is what sets the bomb off, so there is nothing to say about it.
    c4:FailedDisarm(bot)
    return false
end

function Defuse.DestroyC4(c4)
    util.EquipmentDestroyed(c4:GetPos())
    c4:Remove()
end

function Defuse.ShouldAbandon(c4)
    local timeUntilExplode = Defuse.GetTimeUntilExplode(c4)
    return timeUntilExplode <= Defuse.ABANDON_TIME
end

--- Called when the behavior's last state is running
function Defuse.OnRunning(bot)
    local bomb = bot.defuseTarget
    if not Defuse.IsC4Defusable(bomb) then
        return STATUS.FAILURE
    end

    local locomotor = bot:BotLocomotor()
    if not locomotor then return STATUS.FAILURE end

    local bombPos = bomb:GetPos()
    local bombCenter = (bomb.WorldSpaceCenter and bomb:WorldSpaceCenter()) or bombPos

    -- Chickened out, or left it too late: keep running until the panic passes, then hand the bomb
    -- back to the rest of the tree.
    if bot.c4FleeUntil then
        if CurTime() >= bot.c4FleeUntil then return STATUS.FAILURE end
        locomotor:SetHalt(false)
        locomotor:SetGoal(Defuse.GetFleePos(bot, bomb))
        return STATUS.RUNNING
    end

    if Defuse.ShouldAbandon(bomb) then
        Defuse.StartFleeing(bot)
        return STATUS.RUNNING
    end

    -- Approach until we are actually close enough to work on the bomb. Move freely while doing so.
    if bot:GetPos():Distance(bombCenter) > Defuse.DEFUSE_RANGE then
        locomotor:SetHalt(false)
        locomotor:SetGoal(bombPos)
        locomotor:LookAt(bombCenter)
        return STATUS.RUNNING
    end

    -- In range: hold still and face the bomb so it is clear we are defusing it, instead of
    -- shuffling around it (which made bots look like they were just staring at the C4).
    locomotor:SetHalt(true)
    locomotor:LookAt(bombCenter)

    -- Dither at it for a moment first: standing next to a live bomb is something a person has to
    -- talk themselves into. A kit holder only pauses to line up.
    if not bot.c4WorkUntil then
        local hasKit = Defuse.HasDefuseKit(bot)

        local hesitateUntil = bot.c4HesitateUntil
        if not hesitateUntil then
            hesitateUntil = CurTime() + (hasKit and KIT_HESITATE or math.random(HESITATE_MIN, HESITATE_MAX))
            bot.c4HesitateUntil = hesitateUntil
        end

        if CurTime() < hesitateUntil then return STATUS.RUNNING end

        local chatter = bot:BotChatter()
        if chatter then
            chatter:On("DefusingC4")
        end

        Defuse.BeginAttempt(bot, hasKit and KIT_WORK_TIME or WORK_TIME)
        return STATUS.RUNNING
    end

    -- Working on it. The attempt takes real time, and the bot stays put for all of it.
    local result = Defuse.ResolveAttempt(bot, bomb)
    if result == nil then return STATUS.RUNNING end

    return result and STATUS.SUCCESS or STATUS.FAILURE
end

--- Called when the behavior returns a success state
function Defuse.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Defuse.OnFailure(bot)
end

--- Called when the behavior ends
function Defuse.OnEnd(bot)
    bot.defuseTarget = nil
    bot.requestedDefuseC4 = nil
    bot.c4HesitateUntil = nil
    bot.c4WorkUntil = nil
    bot.c4WorkSuccess = nil
    -- Never leave the bot halted after the behavior ends.
    local locomotor = bot:BotLocomotor()
    if locomotor then
        locomotor:SetHalt(false)
    end
end
