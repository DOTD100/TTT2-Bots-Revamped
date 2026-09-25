if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_BLOCKER then return false end

--[[
The Blocker (ChrisScott9456/ttt_blocker_role) is a traitor whose entire job is to keep the dead
anonymous: while one is alive, the addon's own `TTTCanSearchCorpse` hook refuses every body search but
its own, and the moment the last Blocker dies every body is identified at once.

Everything here follows from the role file itself:

  * defaultTeam = TEAM_TRAITOR with roles.SetBaseRole(self, ROLE_TRAITOR), so it is an ordinary traitor:
    it knows the other traitors, it plants, it coordinates, and it hunts.
  * shopFallback = SHOP_FALLBACK_TRAITOR and credits = 1 are left to the gamemode. Our buyables follow
    whichever fallback a role names (Buyables.GetBorrowedShopRole), so nothing has to be said here.
  * isOmniscientRole is a HUD nicety in TTT2 - missing-in-action players and the haste timer - with no
    meaning for a bot.

The one thing that needs help is the passive. It is enforced with a hook, and bots do not go through
hooks to read a body: TTTBots.Behaviors.InvestigateCorpse calls `CORPSE.ShowSearch` and
`CORPSE.SetFound` directly, which sits below it. SetBlocksCorpseIdentify marks the role, and
TTTBots.Roles.IsCorpseIdentifyBlockedFor is what every other bot reads before walking to a corpse -
otherwise a bot would identify exactly the bodies the Blocker exists to hide, and would keep re-targeting
them because they never become found. Like the addon's own hook, the check exempts the Blocker itself.
]]

-- Filed under the role's *name*, which is what every lookup here uses: `GetRoleFor` reads
-- `Player:GetRoleStringRaw()`, and that returns `GetSubRoleData().name`.
--
-- `ROLE_BLOCKER` is deliberately NOT what this is registered under. It is the role's numeric *index*, not its
-- name - TTT2 gives every role one and publishes it as the ROLE_ global (`_G["ROLE_" .. NAME] = roleData.index`)
-- - so a profile registered under it is filed under a number that no lookup ever asks for, and every read of
-- the flag below silently falls back to the innocent profile. TTT2 publishes the role table itself as the
-- uppercase global, so the name is taken from there, with the literal as a fallback.
local blockerName = (BLOCKER and BLOCKER.name) or "blocker"
local blocker = TTTBots.RoleData.New(blockerName, TEAM_TRAITOR)
blocker:SetBlocksCorpseIdentify(true)
blocker:SetDefusesC4(false)
blocker:SetPlantsC4(true)
blocker:SetCanHaveRadar(true)
blocker:SetCanCoordinate(true)
blocker:SetStartsFights(true)
blocker:SetUsesSuspicion(false)
blocker:SetCanSnipe(true)
blocker:SetTeam(TEAM_TRAITOR)
blocker:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
blocker:SetAlliedTeams({
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
})
blocker:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(blocker)

return true
