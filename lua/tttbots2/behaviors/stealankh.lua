--[[
Converts a placed Ankh (TTT-2/ttt2-role_pha): the Graverobber stealing the Pharaoh's ankh, or the Pharaoh
taking back the one that was stolen from him.

The addon's rule, from `ENT:Use` and `PHARAOH_HANDLER:SetClientCanConvAnkh`, is not "press use on the ankh":

  * the activator has to be a Graverobber or a Pharaoh, and may only ever control one ankh;
  * a Graverobber may convert *any* ankh, but only while it owns none (so the second ankh of a round is out of
    its reach until it has placed, or lost, the first);
  * a Pharaoh may only convert the one ankh that is registered as having been *his*, and only while he does not
    control it any more - which is exactly "it was stolen from me";
  * the conversion then has to be *held*: `ENT:Use` stamps `t_transfer_start` on the first call and only
    transfers ownership once `ttt_ankh_conversion_time` (6 s by default) has passed, and the entity's own
    `Think` cancels the whole thing the moment the activator stops looking at it (a 100 unit `MASK_SHOT` trace
    from the eye) or stops holding `IN_USE`;
  * re-entering `Use` after that starts the clock again from zero, so a bot that loses the look loses the work.

Two things follow, and both are why this file exists:

  * A bot cannot send the key, so the key is *emulated*: `loco:SetHoldUse(true)` puts IN_USE on the command
    every tick (movement_conflicts.md #19), and this behaviour calls `Ankh:Use(bot, bot)` itself, the same way
    behaviors/usehealthstation.lua calls `station:Use(bot)` rather than waiting for the engine to dispatch a
    use that a bot's fake client may never make. Holding the key is still required, because the entity's Think
    reads `KeyDown(IN_USE)` and would otherwise cancel us.
  * A bot cannot be told about the on-screen progress bar, so the hold is bounded by its own timeout instead of
    by the HUD: `ttt_ankh_conversion_time` plus a couple of seconds of slack, and it gives up rather than
    standing there.

Nothing here invents ownership: every question goes to `PHARAOH_HANDLER`, which is the only thing that knows
about the original-owner/current-owner split a stolen ankh creates.
]]

TTTBots.Behaviors.StealAnkh = {}

local lib = TTTBots.Lib

local StealAnkh = TTTBots.Behaviors.StealAnkh
StealAnkh.Name = "Convert Ankh"
StealAnkh.Description = "Hold +use on an Ankh until it is ours"
StealAnkh.Interruptible = true

local STATUS = TTTBots.STATUS

local ANKH_ENTITY = "ttt_ankh"

--- The entity's own Think only keeps the conversion alive while its activator is within a 100 unit
--- `MASK_SHOT` trace, so "close enough to hold the key" is that, not arm's length. Standing a little closer
--- than the limit keeps the aim steady while the bot holds still.
local HOLD_DIST = 60
--- Where this node stops walking and starts converting.
local APPROACH_DIST = HOLD_DIST + 32
--- Slack over `ttt_ankh_conversion_time` before giving up: the addon rounds its convar to whole seconds and
--- compares `CurTime()` against a stamp it takes on our first call.
local CONVERSION_SLACK = 3

--- The window the addon makes the player hold the key for, in seconds.
---@return number
local function getConversionTime()
    local cv = GetConVar("ttt_ankh_conversion_time")

    return (cv and cv:GetInt()) or 6
end

--- The addon's own handler, or nil when the role addon is not installed.
---@return table?
local function getHandler()
    if not (PHARAOH_HANDLER and ROLE_PHARAOH) then return nil end

    return PHARAOH_HANDLER
end

--- May this bot convert *this* ankh? Mirrors the addon's own gate, in the order it asks it.
---@param bot Bot
---@param ankh Entity
---@param handler table
---@return boolean
local function canConvert(bot, ankh, handler)
    -- A player who already controls an ankh may not touch another one, whoever they are.
    if handler:PlayerControlsAnAnkh(bot) then return false end

    -- The owner is mid-revival: the addon refuses the conversion outright, because the ankh is busy.
    if ankh:GetNWBool("isReviving", false) then return false end

    local subrole = bot:GetSubRole()

    if ROLE_GRAVEROBBER and subrole == ROLE_GRAVEROBBER then
        -- Any ankh, but only while the Graverobber owns none at all.
        return not handler:PlayerOwnsAnAnkh(bot)
    end

    if subrole == ROLE_PHARAOH then
        -- Only the ankh that was stolen from *this* Pharaoh.
        return handler:PlayerIsOriginalOwnerOfThisAnkh(bot, ankh)
    end

    return false
end

--- The ankh this bot may convert right now, or nil.
---@param bot Bot
---@param handler table
---@return Entity?
local function findConvertibleAnkh(bot, handler)
    for _, ankh in ipairs(lib.GetAnkhs()) do
        if not IsValid(ankh) then continue end
        if canConvert(bot, ankh, handler) then return ankh end
    end

    return nil
end

---@param bot Bot
---@return boolean
function StealAnkh.Validate(bot)
    if not TTTBots.Match.IsRoundActive() then return false end
    if not lib.GetConVarBool("use_ankh") then return false end

    -- The cheap gate for every other role on the server: without the addon's handler there is no ankh at all,
    -- and the entity scan below never runs for a bot whose role cannot convert.
    local handler = getHandler()
    if not handler then return false end

    -- A fight comes first: an interrupted conversion starts from zero, so beginning one under fire is waste.
    if bot.attackTarget then return false end

    local subrole = bot:GetSubRole()
    if not ((ROLE_GRAVEROBBER and subrole == ROLE_GRAVEROBBER) or subrole == ROLE_PHARAOH) then return false end

    return findConvertibleAnkh(bot, handler) ~= nil
end

---@param bot Bot
function StealAnkh.OnStart(bot)
    local handler = getHandler()

    bot.ankhTarget = handler and findConvertibleAnkh(bot, handler) or nil
    bot.ankhHoldStartedAt = nil

    return STATUS.RUNNING
end

---@param bot Bot
---@return integer
function StealAnkh.OnRunning(bot)
    if not TTTBots.Match.IsRoundActive() then return STATUS.FAILURE end

    local handler = getHandler()
    if not handler then return STATUS.FAILURE end

    -- It is ours now. Ownership is the success signal, not the progress bar a player would be watching.
    if handler:PlayerControlsAnAnkh(bot) then return STATUS.SUCCESS end

    local ankh = bot.ankhTarget
    if not (IsValid(ankh) and ankh:GetClass() == ANKH_ENTITY) then
        -- The ankh was destroyed or picked up mid-approach. Look for another one before giving up: a
        -- Graverobber may convert any of them.
        ankh = findConvertibleAnkh(bot, handler)
        bot.ankhTarget = ankh

        if not ankh then return STATUS.FAILURE end
    end

    if not canConvert(bot, ankh, handler) then return STATUS.FAILURE end

    local loco = bot:BotLocomotor()
    local dist = bot:GetPos():Distance(ankh:GetPos())

    if dist > APPROACH_DIST then
        loco:SetSprint(true)
        loco:SetGoal(ankh:GetPos())

        return STATUS.RUNNING
    end

    -- In range: stand still, hold the key, and drive the conversion through the addon's own entry point.
    loco:ClearGoal()
    loco:SetSprint(false)
    loco:LookAt(ankh:WorldSpaceCenter())
    -- The repel shove would push the bot around mid-conversion, and `ENT:Use` restarts the clock the moment
    -- the activator stops looking at the ankh.
    loco:PauseRepel()
    loco:SetHoldUse(true)

    ankh:Use(bot, bot)

    bot.ankhHoldStartedAt = bot.ankhHoldStartedAt or CurTime()

    if CurTime() - bot.ankhHoldStartedAt > getConversionTime() + CONVERSION_SLACK then
        return STATUS.FAILURE
    end

    return STATUS.RUNNING
end

---@param bot Bot
function StealAnkh.OnEnd(bot)
    local loco = bot:BotLocomotor()

    loco:SetHoldUse(false)
    loco:ClearGoal()
    loco:SetSprint(false)
    loco:ResumeRepel()

    bot.ankhTarget = nil
    bot.ankhHoldStartedAt = nil
end
