if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_GRAVEROBBER then return false end

--[[
The Graverobber (TTT-2/ttt2-role_pha) - the traitor the Pharaoh's Ankh creates.

`notSelectable = true`: no round-start roll ever picks it. It exists only because the addon converts a random
live traitor at the moment a Pharaoh places its first ankh (`PHARAOH_HANDLER:PlacedAnkh` -> `SelectGraverobber`,
which prefers a vanilla traitor over another team-traitor role), and it keeps the role until every ankh is gone
- `RevertUnnecessaryGraverobbers` hands the original role back and clears `grav_prev_role`, including at the end
of the round. So this profile is read from the instant that `SetRole` lands, which is why it is written like the
traitor profile it replaces rather than as something exotic: the bot must not change how it plays except for the
one verb the role adds.

That verb is conversion: walking to a placed ankh, holding `+use` on it for `ttt_ankh_conversion_time` (6 s),
and taking it - behaviors/stealankh.lua, which asks the addon's own rule for this role ("any ankh, but only
while I own none") and is registered in the shared `PriorityNodes` groups, so the tree below stays the traitor
default.

Two things deliberately *not* in this file:

  * **the ankh weapon is not declared as a role weapon.** `TTTBots.Roles.m_roleWeapons` maps one weapon class to
    one role name, so a second registration would simply overwrite the Pharaoh's and leave whichever file loaded
    last as the answer. The weapon is the Pharaoh's; a Graverobber only ever holds it by picking the ankh up,
    which the addon gates behind `ttt_ankh_graverobber_pickup` (off by default - see roles/pharaoh.lua).
  * **no allied-roles entry.** `RoleData.New` already allies the role with itself, and the team entry below
    covers the rest of the traitors, which is the same shape as roles/traitor.lua.
]]

local allyTeams = {
    [TEAM_TRAITOR] = true,
    [TEAM_JESTER or "jesters"] = true,
}

local graverobber = TTTBots.RoleData.New((GRAVEROBBER and GRAVEROBBER.name) or "graverobber", TEAM_TRAITOR)
graverobber:SetDefusesC4(false)
graverobber:SetPlantsC4(true)
graverobber:SetCanHaveRadar(true)
graverobber:SetCanCoordinate(true)
graverobber:SetStartsFights(true)
graverobber:SetTeam(TEAM_TRAITOR)
graverobber:SetUsesSuspicion(false)
graverobber:SetCanSnipe(true)
graverobber:SetBTree(TTTBots.Behaviors.DefaultTrees.traitor)
graverobber:SetAlliedTeams(allyTeams)
graverobber:SetLovesTeammates(true)
TTTBots.Roles.RegisterRole(graverobber)

return true
