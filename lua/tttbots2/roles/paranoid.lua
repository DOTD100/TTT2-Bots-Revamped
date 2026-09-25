if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_PARANOID then return false end

--[[
An innocent subrole (roles.SetBaseRole(self, ROLE_INNOCENT)) with unknownTeam set, so other players see
it as a neutral/unknown role rather than an innocent.

Its whole gimmick belongs to the addon, not to us: the loadout hands it item_ttt_dms, and when the
Paranoid dies that item makes the corpse glow. The glow is a statement about the body - the person who
put them there, and whoever is standing over them, are both worth a hard look.

So there is nothing to do while a Paranoid bot is alive, and it needs the ordinary innocent profile:
defuse, suspicion, fight back, investigate. The half that matters for bots is the one that reads the
body, which lives at the bottom of this file: the reveal is public knowledge (the corpse glows for
everybody), so the reader runs for every living bot, not just for the role itself.
]]

local lib = TTTBots.Lib

local paranoid = TTTBots.RoleData.New("paranoid", TEAM_INNOCENT)
paranoid:SetDefusesC4(true)
paranoid:SetTeam(TEAM_INNOCENT)
paranoid:SetBTree(TTTBots.Behaviors.DefaultTrees.innocent)
paranoid:SetCanHide(true)
paranoid:SetCanSnipe(true)
paranoid:SetUsesSuspicion(true)
paranoid:SetAlliedRoles({})
paranoid:SetAlliedTeams({})
TTTBots.Roles.RegisterRole(paranoid)

-- The weights this role's reveal uses. The events they describe only exist for this role, and
-- ChangeSuspicion refuses a reason it cannot find, so they are registered through the component.
--
-- Registering only at load is not enough. The component table is rebuilt whenever the addon is
-- (re)loaded, and a rebuild that happens after this file has run leaves the live component without
-- these keys while this file's hook stays installed, which surfaces as "Invalid suspicion reason:
-- ParanoidKiller". readCorpse therefore re-asserts them on the component it is about to use, which
-- costs two table writes a second and heals such a rebuild. See readCorpse for each weight's meaning.
local SUSPICION_REASONS = {
    ParanoidKiller = 10, -- The Paranoid's glowing corpse named this player as its killer
    ParanoidLurker = 5,  -- This player was standing over the Paranoid's corpse
}

---@param morality CMorality
local function registerSuspicionReasons(morality)
    local values = morality.SUSPICIONVALUES or {}
    for reason, value in pairs(SUSPICION_REASONS) do
        if values[reason] ~= value then
            morality:RegisterSuspicionReason(reason, value)
        end
    end
end

registerSuspicionReasons(TTTBots.Components.Morality)

--- Who killed whom, so a dead Paranoid's corpse can name its killer. Cleared every round: the player
--- entities persist across rounds, so a stale entry would name the previous round's killer.
---@type table<Player, Player>
local lastKillers = {}

--- Which corpses each bot has already taken the reveal off, so a bot only reacts to a body once. Keyed
--- by bot and then by ragdoll, and cleared every round because neither keys nor ragdolls survive one.
---@type table<Bot, table<Entity, boolean>>
local corpsesRead = {}

local function clearRoundMemory()
    lastKillers = {}
    corpsesRead = {}
end

hook.Add("TTTPrepareRound", "TTTBots.paranoid.ClearRoundMemory", clearRoundMemory)
hook.Add("TTTBeginRound", "TTTBots.paranoid.ClearRoundMemory", clearRoundMemory)

--- How close a bot has to be to a Paranoid's corpse to read the reveal off it, and how close another
--- player has to be to that corpse to count as loitering over it.
local REVEAL_RANGE = 900
local LURKER_RANGE = 300

--- Once a second is plenty for looking at a body.
local READ_INTERVAL = 1
local nextRead = 0

--- The living player standing over a body, if anyone is. Only players actually beside the corpse count:
--- a lead against whoever happens to be the closest person on the map would mean nothing.
---@param observer Bot The bot doing the looking; it is not a suspect to itself.
---@param rag Entity The corpse.
---@return Player? lurker
local function getPlayerLoiteringOver(observer, rag)
    local closest, closestDist = nil, nil
    local corpsePos = rag:GetPos()

    for _, ply in ipairs(TTTBots.Match.AlivePlayers) do
        if ply == observer then continue end
        if not (IsValid(ply) and ply:IsPlayer()) then continue end
        if not lib.IsPlayerAlive(ply) then continue end

        local dist = corpsePos:Distance(ply:GetPos())
        if dist > LURKER_RANGE then continue end
        if not closestDist or dist < closestDist then
            closest, closestDist = ply, dist
        end
    end

    return closest
end

--- Read the glowing corpse of a Paranoid for what the role exists to say: who put them there, and who
--- is standing over the body. The killer is a fact, so it lands at KOS weight - the bot calls it out and
--- acts on it. Nobody is ever proven by proximity, so standing over the body is only a lead: it lands
--- below the KOS threshold and tips a bot over only alongside other evidence.
---
--- Traitors cannot learn anything from this; ChangeSuspicion refuses for roles that do not use
--- suspicion at all.
---@param bot Bot
local function readCorpse(bot)
    local morality = bot:BotMorality()
    if not morality then return end

    -- Re-assert this role's weights on the component we are about to talk to. See SUSPICION_REASONS.
    registerSuspicionReasons(morality)

    local read = corpsesRead[bot]
    if not read then
        read = {}
        corpsesRead[bot] = read
    end

    for _, rag in ipairs(TTTBots.Match.Corpses) do
        if read[rag] then continue end
        if not IsValid(rag) then continue end

        local victim = CORPSE.GetPlayer(rag)
        if not (IsValid(victim) and victim:IsPlayer()) then continue end
        if victim:GetRoleStringRaw() ~= "paranoid" then continue end

        -- The glow is the entire signal, so do not read a body we cannot actually see.
        if bot:GetPos():Distance(rag:GetPos()) > REVEAL_RANGE then continue end
        if not bot:VisibleVec(rag:GetPos() + Vector(0, 0, 16)) then continue end

        local killer = lastKillers[victim]
        if IsValid(killer) and lib.IsPlayerAlive(killer) then
            morality:ChangeSuspicion(killer, "ParanoidKiller")
        end

        local lurker = getPlayerLoiteringOver(bot, rag)
        if lurker then
            morality:ChangeSuspicion(lurker, "ParanoidLurker")
        end

        read[rag] = true
    end
end

--- Walk every living bot past the Paranoid bodies it can see, on its own clock so the role does not
--- need the morality component to tick it.
hook.Add("Think", "TTTBots.paranoid.ReadCorpses", function()
    local time = CurTime()
    if time < nextRead then return end
    nextRead = time + READ_INTERVAL

    if not TTTBots.Match.IsRoundActive() then return end

    for _, bot in ipairs(TTTBots.Bots or {}) do
        if not IsValid(bot) then continue end
        if not lib.IsPlayerAlive(bot) then continue end
        if not bot:BotMorality() then continue end

        readCorpse(bot)
    end
end)

--- Record who killed whom, so a corpse read later on can name them. A death with no attacker (a fall, a
--- barrel) has nobody to name, so it is deliberately not recorded.
hook.Add("PlayerDeath", "TTTBots.paranoid.PlayerDeath", function(victim, weapon, attacker)
    if not (IsValid(victim) and victim:IsPlayer()) then return end
    if not (IsValid(attacker) and attacker:IsPlayer()) then return end

    lastKillers[victim] = attacker
end)

return true
