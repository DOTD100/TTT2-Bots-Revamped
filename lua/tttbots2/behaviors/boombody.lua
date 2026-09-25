--[[
Uses the Boom Body (TTT-2/ttt2-wep_boom_body), a traitor's fake corpse.

There is nothing to aim and nothing to choose. The weapon's primary attack builds a corpse of a *random*
player (CORPSE.Create), marks it so its owner can see it, and then removes itself from the inventory: one
use, one body, wherever the addon decides to put it. The trap is in the corpse - TTT2 runs TTTCanSearchCorpse
when a player searches a body, and that addon's hook refuses the search and detonates the body instead (160
units, 350 damage, credited to the owner with a chalk outline and a scorch mark left behind).

The owner is the only player told anything about it, and the only one who can take it back (covertly, which is
not something this layer can perform). So the whole decision here is *when*: a fake corpse earns its keep while
people are still searching bodies rather than shooting each other, and setting one up means holding the weapon
long enough to fire it, which is not something to do mid-fight.

Inert without the addon - the weapon has to exist for the class check to pass, and the only entry in an
ordinary round is a traitor who bought it.
]]

TTTBots.Behaviors.BoomBody = {}

local lib = TTTBots.Lib

local BoomBody = TTTBots.Behaviors.BoomBody
BoomBody.Name = "Boom Body"
BoomBody.Description = "Set up a fake corpse that explodes when it is searched"
BoomBody.Interruptible = true

local STATUS = TTTBots.STATUS

---@class Bot
---@field boomBodyStartedAt number? When this setup began, so it can give up.
---@field boomBodyAttacking boolean? Between pressing attack and the weapon being spent.

local WEP = "weapon_ttt_boom_body"

--- Only worth setting up early. The trap works on players who are still searching bodies, which is the first
--- half of a round; after that the bodies that matter are already confirmed.
local SETUP_WINDOW = 150
--- Single press, so this is only a safety net for a weapon that never fires.
local GIVE_UP_TIME = 15

---@return boolean
function BoomBody.IsAvailable()
    return weapons.Get(WEP) ~= nil
end

---@param bot Bot
---@return Weapon?
function BoomBody.GetWeapon(bot)
    if not bot:HasWeapon(WEP) then return nil end

    local wep = bot:GetWeapon(WEP)
    if not (IsValid(wep) and wep.Clip1 and wep:Clip1() > 0) then return nil end

    return wep
end

---@param bot Bot
---@return boolean
function BoomBody.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_boom_body") then return false end
    if not lib.IsPlayerAlive(bot) then return false end
    if not BoomBody.IsAvailable() then return false end
    if TTTBots.Match.Time() > SETUP_WINDOW then return false end

    -- Not with something to shoot. Firing this means holding a bundle of C4 instead of a gun for a moment.
    if bot.attackTarget ~= nil then return false end
    if not BoomBody.GetWeapon(bot) then return false end

    return true
end

---@param bot Bot
---@return BStatus
function BoomBody.OnStart(bot)
    bot.boomBodyStartedAt = CurTime()
    bot.boomBodyAttacking = false

    return STATUS.RUNNING
end

---@param bot Bot
---@return BStatus
function BoomBody.OnRunning(bot)
    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    -- The weapon is removed from the inventory the moment it fires, so its absence *is* the success signal.
    local wep = BoomBody.GetWeapon(bot)
    if not wep then return STATUS.SUCCESS end
    if (CurTime() - (bot.boomBodyStartedAt or CurTime())) > GIVE_UP_TIME then return STATUS.FAILURE end

    local inv = bot:BotInventory()
    if inv then inv:PauseAutoSwitch() end
    bot:SelectWeapon(WEP)

    if bot.boomBodyAttacking then
        loco:StopAttack()
        bot.boomBodyAttacking = false

        if not bot:HasWeapon(WEP) then return STATUS.SUCCESS end
    end

    bot.boomBodyAttacking = true
    loco:StartAttack()

    return STATUS.RUNNING
end

---@param bot Bot
function BoomBody.OnEnd(bot)
    bot.boomBodyStartedAt = nil
    bot.boomBodyAttacking = false

    local loco = bot:BotLocomotor()
    if loco then loco:StopAttack() end

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end

---@param bot Bot
function BoomBody.OnSuccess(bot) end

---@param bot Bot
function BoomBody.OnFailure(bot) end
