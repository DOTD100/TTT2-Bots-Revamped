---@class BDefectorJihad
TTTBots.Behaviors.DefectorJihad = {}

local lib = TTTBots.Lib
local Jihad = TTTBots.Behaviors.DefectorJihad
Jihad.Name = "DefectorJihad"
Jihad.Description = "Charge an enemy and detonate the Jihad Bomb"
-- Once we are running at someone holding a bomb, nothing should be able to talk us out of it.
Jihad.Interruptible = false

local STATUS = TTTBots.STATUS

local BOMB = "weapon_ttt_jihad_bomb"
-- The bomb deals 125+ damage out to 357 units through walls (inner radius 550 with a 0.65 falloff
-- floor) and adds blast damage out to about 632, so priming from inside this range is already lethal.
-- There is no need to stand on top of anyone.
local DETONATE_RANGE = 350
local SEEK_RANGE = 800 -- only worth walking this far to die on someone

---@param bot Bot
---@return Weapon? bomb
function Jihad.GetBomb(bot)
    if not bot:HasWeapon(BOMB) then return nil end

    local bomb = bot:GetWeapon(BOMB)
    return IsValid(bomb) and bomb or nil
end

--- The nearest living player we are allowed to hurt. The defector is a traitor with a bomb, so this
--- uses the same allied/enemy rules as every other role.
---@param bot Bot
---@return Player? target
function Jihad.FindTarget(bot)
    local closest, closestDist = nil, nil

    for _, ply in ipairs(TTTBots.Roles.GetNonAllies(bot)) do
        if not lib.IsPlayerAlive(ply) then continue end

        local dist = bot:GetPos():Distance(ply:GetPos())
        if dist > SEEK_RANGE then continue end
        if not closestDist or dist < closestDist then
            closest, closestDist = ply, dist
        end
    end

    return closest
end

--- Validate the behavior
function Jihad.Validate(bot)
    if not lib.IsPlayerAlive(bot) then
        -- We are meant to die on this run, so OnEnd - which is what puts the inventory back on
        -- auto-switch - frequently never runs. pauseAutoSwitch is a latch on the component that
        -- survives death and even round changes, so release it here instead of leaving the dead bot's
        -- inventory paused forever. This node is the first in the defector's tree, so it is reached
        -- every tick and the latch never outlives the tick we died on.
        local inv = bot:BotInventory()
        if inv then inv:ResumeAutoSwitch() end

        return false
    end

    if not Jihad.GetBomb(bot) then return false end

    local target = Jihad.FindTarget(bot)
    bot.jihadTarget = target

    return target ~= nil
end

--- Called when the behavior is started
function Jihad.OnStart(bot)
    local inv = bot:BotInventory()
    -- The bomb is equipment, so the inventory would never pick it back up for us if it swapped away.
    if inv then inv:PauseAutoSwitch() end

    return STATUS.RUNNING
end

--- Called when the behavior's last state is running
function Jihad.OnRunning(bot)
    local bomb = Jihad.GetBomb(bot)
    if not bomb then return STATUS.SUCCESS end -- it is gone, which is what we wanted

    local target = bot.jihadTarget
    if not (IsValid(target) and lib.IsPlayerAlive(target)) then
        target = Jihad.FindTarget(bot)
        bot.jihadTarget = target
        if not target then return STATUS.FAILURE end
    end

    local loco = bot:BotLocomotor()
    if not loco then return STATUS.FAILURE end

    bot:SelectWeapon(BOMB)
    loco:LookAt(target:GetPos())

    if bot:GetPos():Distance(target:GetPos()) > DETONATE_RANGE then
        loco:SetGoal(target:GetPos())
        return STATUS.RUNNING
    end

    -- In range: prime the bomb the way a player would, via the attack button for the held weapon.
    -- The fuse is a little over 2 seconds and the bomb only goes off if we are still holding it when
    -- the fuse runs out, so keep closing on them while it burns down rather than standing still and
    -- letting them walk out of the blast. Re-pressing is harmless: the weapon rate-limits itself.
    loco:SetGoal(target:GetPos())
    loco:StartAttack()

    return STATUS.RUNNING
end

--- Called when the behavior returns a success state
function Jihad.OnSuccess(bot)
end

--- Called when the behavior returns a failure state
function Jihad.OnFailure(bot)
end

--- Called when the behavior ends
function Jihad.OnEnd(bot)
    bot.jihadTarget = nil

    local loco = bot:BotLocomotor()
    if loco then
        loco:StopMoving()
        loco:StopAttack()
    end

    local inv = bot:BotInventory()
    if inv then inv:ResumeAutoSwitch() end
end
