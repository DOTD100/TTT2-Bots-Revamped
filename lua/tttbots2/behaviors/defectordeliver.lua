---@class BDefectorDeliver
TTTBots.Behaviors.DefectorDeliver = {}

local lib = TTTBots.Lib
local Deliver = TTTBots.Behaviors.DefectorDeliver
Deliver.Name = "DefectorDeliver"
Deliver.Description = "Hand the Defector Jihad to an Innocent player"
Deliver.Interruptible = true

local STATUS = TTTBots.STATUS

local JIHAD_ITEM = "weapon_ttt_defector_jihad"
local DELIVER_RANGE = 120

--- The Defector Jihad converts whoever picks it up, but its own WeaponEquip hook only ever converts a
--- player whose base role is Innocent and whose team is Innocent - a Detective counts, since their
--- base role is still innocent. Anyone else just carries the item around doing nothing.
---@param ply Player
---@return boolean
function Deliver.IsConvertableTarget(ply)
    if not IsValid(ply) or not lib.IsPlayerAlive(ply) then return false end
    if ply:GetRole() ~= ROLE_INNOCENT or ply:GetTeam() ~= TEAM_INNOCENT then return false end

    -- Mirrors the weapon's own toggleable exception for Pharaohs. ROLE_PHARAOH only exists when that
    -- role is installed.
    local convertPharaoh = GetConVar("ttt_defector_convert_pharaoh")
    local pharaohAllowed = convertPharaoh and convertPharaoh:GetBool() or false
    if ROLE_PHARAOH and ply:GetSubRole() == ROLE_PHARAOH and not pharaohAllowed then return false end

    return true
end

---@param bot Bot
---@return Weapon? item
function Deliver.GetItem(bot)
    if not bot:HasWeapon(JIHAD_ITEM) then return nil end

    local item = bot:GetWeapon(JIHAD_ITEM)
    return IsValid(item) and item or nil
end

---@param bot Bot
---@return Player? target
function Deliver.FindTarget(bot)
    local closest, closestDist = nil, nil

    for _, ply in ipairs(TTTBots.Match.AlivePlayers) do
        if ply == bot then continue end
        if not Deliver.IsConvertableTarget(ply) then continue end

        local dist = bot:GetPos():Distance(ply:GetPos())
        if not closestDist or dist < closestDist then
            closest, closestDist = ply, dist
        end
    end

    return closest
end

--- Validate the behavior
function Deliver.Validate(bot)
    if not Deliver.GetItem(bot) then return false end

    local target = bot.deliverTarget
    if not Deliver.IsConvertableTarget(target) then
        target = Deliver.FindTarget(bot)
        bot.deliverTarget = target
    end

    return target ~= nil
end

--- Called when the behavior is started
function Deliver.OnStart(bot)
    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
function Deliver.OnRunning(bot)
    local target = bot.deliverTarget
    if not Deliver.IsConvertableTarget(target) then return STATUS.FAILURE end

    local item = Deliver.GetItem(bot)
    if not item then return STATUS.SUCCESS end -- we no longer have it to give away

    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    loco:LookAt(target:GetPos())

    if bot:GetPos():Distance(target:GetPos()) > DELIVER_RANGE then
        loco:SetGoal(target:GetPos())
        return STATUS.RUNNING
    end

    -- Close enough: put it on the floor at their feet. The weapon converts on pickup and TTT weapons
    -- are picked up by walking over them, so this gives them the shortest possible trip to it.
    loco:StopMoving()
    bot:SelectWeapon(JIHAD_ITEM)
    bot:DropWeapon(item)

    return STATUS.SUCCESS
end

--- Called when the behavior returns a success state
function Deliver.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Deliver.OnFailure(bot)
end

--- Called when the behavior ends
function Deliver.OnEnd(bot)
    bot.deliverTarget = nil

    local loco = bot:BotLocomotor()
    if loco then loco:StopMoving() end
end
