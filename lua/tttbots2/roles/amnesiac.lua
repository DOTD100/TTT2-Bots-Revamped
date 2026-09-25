if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_AMNESIAC then return false end

-- A teamless role that cannot win (preventWin) and is punished hard for killing (-12/-16). It has no
-- identity of its own: searching an unconfirmed corpse makes it adopt that corpse's role and team, so
-- its whole job is to find bodies and search them. It also carries a radar of unconfirmed bodies.
--
-- The conversion lives in the addon's own TTTCanSearchCorpse hook - it does the SetRole itself - and that
-- is why InvestigateCorpse now runs that hook before identifying a body by itself. A bot's direct
-- CORPSE.ShowSearch call sits *below* the hook, so before that change an Amnesiac bot could search every
-- body in the round and never become anything: the one thing the role exists to do was unreachable.
local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes
local bTree = {
    _prior.FightBack,
    _prior.Investigate,
    _prior.Restore,
    _bh.Interact,
    _prior.Minge,
    _bh.Decrowd,
    _prior.Patrol
}

local amnesiac = TTTBots.RoleData.New("amnesiac", TEAM_NONE)
amnesiac:SetDefusesC4(false)
amnesiac:SetStartsFights(false)
amnesiac:SetUsesSuspicion(false)
-- The role's loadout hands it item_ttt_radar, so the bot gets the same radar treatment every other
-- radar-carrying role gets (the position simulation in sv_memory.lua).
amnesiac:SetCanHaveRadar(true)
amnesiac:SetTeam(TEAM_NONE)
amnesiac:SetBTree(bTree)
amnesiac:SetAlliedRoles({})
amnesiac:SetAlliedTeams({})
TTTBots.Roles.RegisterRole(amnesiac)

-- The role's own radar (ROLE.CustomRadar) reveals every unconfirmed body, so the bot is allowed the
-- same knowledge instead of having to stumble onto one. Bodies are only offered when the role's own
-- search hook (TTTCanSearchCorpse) would actually convert us, which is the same condition the radar
-- uses to decide what it is allowed to show.
hook.Add("TTTBotsGetKnownCorpses", "TTTBots.amnesiac.radar", function(bot)
    if not IsValid(bot) or bot:GetSubRole() ~= ROLE_AMNESIAC then return end

    local limitToUnconfirmed = GetConVar("ttt2_amnesiac_limit_to_unconfirmed")
    local onlyUnconfirmed = limitToUnconfirmed and limitToUnconfirmed:GetBool() or false

    local corpses = {}
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not rag.player_ragdoll then continue end
        if onlyUnconfirmed and (CORPSE.GetFound(rag, false) or not DetectiveMode()) then continue end

        corpses[#corpses + 1] = rag
    end

    return corpses
end)

return true
