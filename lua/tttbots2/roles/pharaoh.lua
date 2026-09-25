if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_PHARAOH then return false end

--[[
The Pharaoh (TTT-2/ttt2-role_pha) - one half of a duo whose other half the addon creates by itself.

It is an ordinary innocent with one extra item: `defaultTeam = TEAM_INNOCENT` with `unknownTeam` (its own file
hides it from everybody, including itself: `preventFindCredits`, no shop, `credits = 0`), `maximum = 1` per
round, `minPlayers = 6`, and a loadout that hands it `weapon_ttt_ankh`. Everything it *does* is that Ankh, and
every verb of it is a behaviour rather than a profile flag:

  * placing it earns the role its name - and converts a random live traitor into the Graverobber the moment the
    first one goes down (`PHARAOH_HANDLER:PlacedAnkh` -> `SelectGraverobber`), which is why the two roles cannot
    be supported separately - behaviors/placeankh.lua;
  * a stolen ankh can be taken back, and only by the Pharaoh it was taken from (the addon's own rule), or
    converted by the Graverobber - behaviors/stealankh.lua;
  * the ankh is its respawn point and a slow heal, so it may carry it somewhere safer when it has been found -
    behaviors/moveankh.lua, which is also the only one of the three the addon gates behind a convar
    (`ttt_ankh_pharaoh_pickup`, on by default).

All three are registered in the shared `PriorityNodes` groups, so the tree below is the innocent default and
there is no tree to copy.

The respawn itself is not ours to implement and is worth knowing about when reading a bot's behaviour:
`TTT2PostPlayerDeath` calls `Revive(ttt_ankh_respawn_time, ...)` for the ankh's current owner, so a bot Pharaoh
already comes back at its ankh with 50 health - no input, no behaviour, and nothing in this file.

Why a role file exists at all when the tree is the default one: a role is only *known* to this addon when a
profile is registered under its **name** (the string `Player:GetRoleStringRaw()` returns, which is what
`GetRoleFor` looks up - the `ROLE_X` global is a numeric index and filing a profile under it means no lookup
ever finds it, which is the Blocker's whole story in the notes). Without this file the Pharaoh would be
auto-registered as a clone of the innocent profile: nearly right, and it would quietly lose the role-weapon
registration below.
]]

local pharaoh = TTTBots.RoleData.New((PHARAOH and PHARAOH.name) or "pharaoh", TEAM_INNOCENT)
pharaoh:SetDefusesC4(true)
pharaoh:SetPlantsC4(false)
pharaoh:SetCanHaveRadar(false)
pharaoh:SetCanCoordinate(false) -- unknownTeam: it does not know the traitors, and they do not know it
pharaoh:SetStartsFights(false)
pharaoh:SetUsesSuspicion(true)
pharaoh:SetCanHide(true)
pharaoh:SetCanSnipe(true)
pharaoh:SetTeam(TEAM_INNOCENT)
pharaoh:SetBTree(TTTBots.Behaviors.DefaultTrees.innocent)
-- The innocent profile's empty allied sets, kept deliberately (roles/innocent.lua sets the same two):
-- innocents do not know each other, and this role is no more omniscient than they are.
pharaoh:SetAlliedRoles({})
pharaoh:SetAlliedTeams({})

-- The Ankh weapon is handed out by the role's own loadout, so this is what tells the rest of the addon that
-- whoever is holding it is the Pharaoh. What that actually does today, since it is easy to over-read:
--
--   * the only reader is `getWeaponTell` in components/sv_morality.lua, and it is team-guarded on purpose - a
--     role weapon "only gives somebody away when the role is not on our own team". So for every innocent-side
--     bot this registration is deliberately *not* a tell, and it never becomes a reason to shoot the Pharaoh;
--     this is the first innocent-team weapon the map has ever held, and that guard is what makes it safe.
--   * a bot on another team that uses suspicion will read it as a tell that the holder is a Pharaoh. Traitors
--     will not: they do not use suspicion at all. A Jester or another neutral role would, and its chatter line
--     for a role weapon is worded for a *traitor's* weapon - a cosmetic wart recorded in the notes rather than
--     worked around here.
--   * the exposure is small: the weapon is single use, so it is only ever held before the first placement or
--     after a pickup. A Graverobber can only hold it at all if a server turns `ttt_ankh_graverobber_pickup` on
--     (it ships off), and then bots on other teams would read the thief as the Pharaoh - which is the mistake
--     the addon would have made anyway, since the ankh has changed hands.
pharaoh:SetRoleWeapons({ "weapon_ttt_ankh" })

TTTBots.Roles.RegisterRole(pharaoh)

return true
