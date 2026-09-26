---@class BDefib
TTTBots.Behaviors.Defib = {}

local lib = TTTBots.Lib

---@class BDefib
local Defib = TTTBots.Behaviors.Defib
Defib.Name = "Defib"
Defib.Description = "Use the defibrillator on a corpse."
Defib.Interruptible = true
--- Every class we are willing to treat as a defibrillator. weapon_ttt_defibrillator is the standalone
--- "[TTT2] Defibrillator" weapon the Detective's shop and the Doctor role hand out; the Mesmerist's own
--- defib is weapon_ttt_mesdefi, which is used the same way - held down with the eye trace on a corpse
--- until it charges - and differs only in what the body comes back as.
Defib.WeaponClasses = { "weapon_ttt_defibrillator", "weapon_ttt_mesdefi" }

--- The defibrillator only works when the trigger is held down with the eye trace on the corpse, so we
--- have to stand this close before we take it out. The weapon itself traces 100 units, but the bot
--- crouches over the body, and a little breathing room keeps the trace from sliding off it.
Defib.DefibReach = 70

--- TTT2's defibrillator refuses corpses that were killed with a headshot unless this is enabled.
local REVIVE_BRAINDEAD_CVAR = "ttt_defibrillator_revive_braindead"

--- The convars the two defibrillators use for how long the trigger has to be held.
---
--- Both of them start a *timed* revival on the press (`Player:Revive(delay, ...)`) and cancel it outright if the
--- button is released before the timer is up - the Mesmerist's own Think cancels on `not owner:KeyDown(IN_ATTACK)`,
--- on the eye trace leaving the body, or on the weapon being holstered - so a bot that lets go early is the
--- thing killing its own attempt. Both convars default to 3 s; the Mesmerist's own slider goes to 30, which is
--- why this is read at the point of use rather than assumed.
local REVIVE_TIME_CVARS = { "ttt_defibrillator_revive_time", "ttt2_mesdefi_revive_time" }

--- The shortest hold we will take, and the slack added to the weapon's own timer.
local DEFIB_MIN_HOLD = 6
local DEFIB_HOLD_SLACK = 4

--- How long we are willing to stand over a corpse holding the trigger.
---
--- The weapon's own timer always resolves inside this, so the budget is only ever reached by a defibrillator
--- that never fires at all. It used to be a flat 6 seconds, which is *shorter* than the hold a defibrillator is
--- configured for above that - and since releasing cancels the revival, that release was the bug (section 36).
---@return number
local function getHoldBudget()
    local longest = 0

    for _, name in ipairs(REVIVE_TIME_CVARS) do
        local cv = GetConVar(name)
        if cv then longest = math.max(longest, cv:GetFloat()) end
    end

    return math.max(DEFIB_MIN_HOLD, longest + DEFIB_HOLD_SLACK)
end

--- How long we leave a corpse alone after spending a charge on it, so we do not fixate on one body.
local RETRY_COOLDOWN = 30

local STATUS = TTTBots.STATUS

--- Does this defibrillator use charges (TTT2's does, one per purchase)?
---@param defib Weapon
---@return number? charge nil when the weapon is not charge-based
function Defib.GetCharge(defib)
    if not IsValid(defib) then return nil end

    local maxClip = defib:GetMaxClip1()
    if not (maxClip and maxClip > 0) then return nil end -- no clip: assume it always works

    return defib:Clip1()
end

--- Does this defibrillator have a charge left to spend?
---@param defib Weapon
---@return boolean
function Defib.HasCharge(defib)
    if not IsValid(defib) then return false end

    local charge = Defib.GetCharge(defib)
    if charge == nil then return true end

    return charge > 0
end

--- TTT2's defibrillator refuses headshot corpses unless the server allows it. When the cvar is missing
--- we stay conservative, matching TTTBots.Lib.GetRevivableCorpses.
---@return boolean
function Defib.CanReviveHeadshot()
    local cvar = GetConVar(REVIVE_BRAINDEAD_CVAR)
    if not cvar then return false end

    return cvar:GetBool()
end

--- Can this ragdoll be revived by the weapon we are holding?
---@param rag Entity
---@return boolean
function Defib.IsRevivableBody(rag)
    if not lib.IsValidBody(rag) then return false end
    if not CORPSE.WasHeadshot(rag) then return true end

    return Defib.CanReviveHeadshot()
end

--- Nitpick: the victim should wait a moment before we try again, since the weapon has to be re-bought.
---@param target Player
function Defib.CooldownCorpse(target)
    if not IsValid(target) then return end

    target.reviveCooldown = CurTime() + RETRY_COOLDOWN
end

--- Get the closest revivable corpse to our bot. Unlike TTTBots.Lib.GetClosestRevivable, this respects
--- the headshot rule of the defibrillator itself.
---@param bot Bot
---@param allyOnly boolean
---@return Player? closest
---@return any? ragdoll
function Defib.GetCorpse(bot, allyOnly)
    local cTime = CurTime()
    local closest, closestDist, closestRag

    for i, rag in pairs(TTTBots.Match.Corpses) do
        if not Defib.IsRevivableBody(rag) then continue end

        local sid64 = rag.sid64
        if not sid64 then continue end

        local deadply = player.GetBySteamID64(sid64)
        if not IsValid(deadply) then continue end
        if deadply == bot then continue end
        if allyOnly and not TTTBots.Roles.IsAllies(bot, deadply) then continue end
        if Defib.RevivesInnocentSide(bot) and not Defib.IsInnocentSide(deadply) then continue end
        if (deadply.reviveCooldown or 0) > cTime then continue end

        local dist = bot:GetPos():Distance(rag:GetPos())
        if closestDist and dist >= closestDist then continue end

        closest, closestDist, closestRag = deadply, dist, rag
    end

    return closest, closestRag
end

--- Does a corpse of *anyone* come back as one of ours, rather than only a teammate's?
---
--- The Mesmerist's defibrillator rebuilds whoever it is used on as a Thrall on the Mesmerist's team, so
--- for that role the nearest body is the right target instead of the nearest friendly one. Read from the
--- role data so the behaviour itself stays role-agnostic.
---@param bot Bot
---@return boolean
function Defib.RevivesAnyone(bot)
    return TTTBots.Roles.GetRoleFor(bot):GetRevivesAnyCorpse() and true or false
end

--- Should this role choose the innocent side, even though it will look at any corpse at all?
---
--- The Doctor is the case this exists for. It has no allies to speak of, so it needs the any-corpse rule just
--- to find a body - but it is an innocent, and the body it is standing over may have been a traitor, in which
--- case reviving it is worse than walking away. The Mesmerist has no such problem (whoever its defib is used
--- on comes back on its own side), which is why this is a separate flag rather than another reading of the
--- one above. Read from the role data so the behaviour stays role-agnostic.
---@param bot Bot
---@return boolean
function Defib.RevivesInnocentSide(bot)
    return TTTBots.Roles.GetRoleFor(bot):GetRevivesInnocentSide() and true or false
end

--- Is this corpse somebody the innocent side would want back?
---
--- The body's own role is read directly. That is the same licence the corpse investigation and the Paranoid's
--- reveal already take, and it is the only way "choose to revive the innocent one" can exist: to a player the
--- body is unidentified, so a bot doing this is deliberately a little better informed than they are.
---@param deadply Player
---@return boolean
function Defib.IsInnocentSide(deadply)
    if not IsValid(deadply) then return false end

    return not TTTBots.Roles.IsTraitor(deadply)
end

function Defib.HasDefib(bot)
    for i, class in pairs(Defib.WeaponClasses) do
        if bot:HasWeapon(class) then return true end
    end

    return false
end

---Get the defib weapon, if the bot has one.
---@param bot Bot
---@return Weapon?
function Defib.GetDefib(bot)
    for i, class in pairs(Defib.WeaponClasses) do
        local wep = bot:GetWeapon(class)
        if IsValid(wep) then return wep end
    end
end

--- Stop driving the weapon and stand back up. Safe to call at any point, even outside of a revive.
---@param bot Bot
---@param inventory CInventory?
---@param loco BotLocomotor?
function Defib.StopReviving(bot, inventory, loco)
    inventory = inventory or bot:BotInventory()
    loco = loco or bot:BotLocomotor()
    if not (inventory and loco) then return end

    loco:StopAttack()
    loco:SetHoldAttack(false)
    loco:Crouch(false)
    loco:SetHalt(false)
    loco:ResumeRepel()
    inventory:ResumeAutoSwitch()

    bot.defibStartTime = nil
    bot.defibClipAtStart = nil
end

function Defib.ValidateCorpse(bot, corpse)
    return Defib.IsRevivableBody(corpse or bot.defibRag)
end

function Defib.Validate(bot)
    if not TTTBots.Lib.IsTTT2() then return false end -- This is TTT2-specific.
    if not TTTBots.Match.IsRoundActive() then return false end
    if bot.preventDefib then return false end         -- just an extra feature to prevent defibbing

    -- cant defib without defib
    local defib = Defib.GetDefib(bot)
    if not IsValid(defib) then return false end

    -- a spent defibrillator is just a brick in our hands
    if not Defib.HasCharge(defib) then return false end

    -- re-use existing
    local hasCorpse = Defib.ValidateCorpse(bot, bot.defibRag)
    if hasCorpse then return true end

    -- get new target
    local corpse, rag = Defib.GetCorpse(bot, not Defib.RevivesAnyone(bot))
    if not corpse then return false end

    -- one last valid check
    local cValid = Defib.ValidateCorpse(bot, rag)
    if not cValid then return false end

    return true
end

function Defib.OnStart(bot)
    bot.defibTarget, bot.defibRag = Defib.GetCorpse(bot, not Defib.RevivesAnyone(bot))


    return STATUS.RUNNING
end

function Defib.GetSpinePos(rag)
    local default = rag:GetPos()

    local spineName = "ValveBiped.Bip01_Spine"
    local spine = rag:LookupBone(spineName)

    if spine then
        return rag:GetBonePosition(spine)
    end

    return default
end

---@class Bot
---@field defibTarget Player? The PLAYER of the defibRag we found
---@field defibRag Entity? The ragdoll we found to defib
---@field defibStartTime number? When we started defibbing our defibTarget
---@field defibClipAtStart number? The charge of the defibrillator when we started holding the trigger

--- Drives the defibrillator the way a player would: walk up to the body, crouch over it, then hold the
--- trigger down and let the weapon run its own charge and its own success roll.
---
--- Holding is the mechanic, not politeness: the weapon starts a timed revival on the press and cancels it
--- outright if the trigger comes back up, so every exit below has to be one the weapon agrees with. Nothing in
--- here may release the button for a reason the weapon would not act on itself.
---@param bot Bot
function Defib.OnRunning(bot)
    local inventory, loco = bot:BotInventory(), bot:BotLocomotor()
    if not (inventory and loco) then return STATUS.FAILURE end

    local defib = Defib.GetDefib(bot)
    local target = bot.defibTarget
    local rag = bot.defibRag
    if not (IsValid(defib) and IsValid(target)) then return STATUS.FAILURE end

    -- The weapon resolved the attempt and revived them.
    if target:Alive() then return STATUS.SUCCESS end

    local holding = bot.defibStartTime ~= nil

    -- A spent defibrillator is a brick, but only worth giving up on *before* the trigger is down: once it is
    -- down, the charge dropping means the weapon finished the attempt, which the exit further below reads.
    if not holding and not Defib.HasCharge(defib) then return STATUS.FAILURE end

    if not IsValid(rag) then return STATUS.FAILURE end -- the corpse was taken from us

    -- Asked before the hold, never during it. Once the trigger is down the weapon is the authority on the body -
    -- it cancels its own revival if the body stops qualifying - so a second opinion here can only take the
    -- button back out of the bot's hands, and releasing is exactly what cancels the attempt.
    if not holding and not Defib.IsRevivableBody(rag) then return STATUS.FAILURE end

    local ragPos = Defib.GetSpinePos(rag)
    loco:LookAt(ragPos)

    --- 🚶 WALK UP TO THE BODY, weapon holstered and trigger released.
    if bot:GetPos():Distance(ragPos) > Defib.DefibReach then
        Defib.StopReviving(bot, inventory, loco)
        loco:SetGoal(ragPos)
        return STATUS.RUNNING
    end

    --- 🤔 HESITATE if there are onlookers, so we do not raise the dead in front of an audience.
    local numWitnesses = #lib.GetAllWitnessesBasic(bot:GetPos(), TTTBots.Roles.GetNonAllies(bot))
    if numWitnesses > 1 and bot.defibStartTime == nil then return STATUS.RUNNING end

    --- ⚡ HOLD THE TRIGGER. The weapon charges while +attack is held, so we must never let it go.
    inventory:PauseAutoSwitch()
    bot:SetActiveWeapon(defib)
    loco:ClearGoal() -- stop moving
    loco:Crouch(true)
    loco:PauseRepel()
    loco:SetHoldAttack(true)
    loco:StartAttack()

    if bot.defibStartTime == nil then
        bot.defibStartTime = CurTime()
        bot.defibClipAtStart = Defib.GetCharge(defib)
    end

    -- The weapon spends its charge the moment it resolves the revive, win or lose.
    local charge = Defib.GetCharge(defib)
    local spent = (charge ~= nil and bot.defibClipAtStart ~= nil and charge < bot.defibClipAtStart)
    if spent or (bot.defibStartTime + getHoldBudget()) < CurTime() then
        Defib.CooldownCorpse(target)
        Defib.StopReviving(bot, inventory, loco)
        return STATUS.SUCCESS
    end

    return STATUS.RUNNING
end

function Defib.OnSuccess(bot)
end

function Defib.OnFailure(bot)
end

--- Called when the behavior succeeds or fails. Useful for cleanup, as it is always called once the behavior is a) interrupted, or b) returns a success or failure state.
---@param bot Bot
function Defib.OnEnd(bot)
    bot.defibTarget, bot.defibRag = nil, nil
    Defib.StopReviving(bot)

    local loco = bot:BotLocomotor()
    if not loco then return end

    loco:ResumeAttackCompat()
end
