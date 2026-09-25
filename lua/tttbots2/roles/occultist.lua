if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_OCCULTIST then return false end

--[[
An innocent subrole (roles.SetBaseRole(self, ROLE_INNOCENT)) with unknownTeam set, so other players
see it as a neutral/unknown role rather than an innocent. Its gimmick is a second life: the addon
drives the whole thing with hooks, so nothing here has to trigger it.

  * A Think hook marks the Occultist for revival as soon as its health drops to the
    ttt_occultist_health_threshold (25 by default), which is the "you have to nearly die first" part
    of the role.
  * On death the addon spawns ten env_fire at the body (ttt_occultist_fire_radius), then calls
    Player:Revive, bringing it back after ttt_occultist_respawn_time (10s) with full health and a
    fire immunity item, once per round. The fires ship with a damage scale of 0, so unless a server
    raises that they are theatre rather than a hazard worth pathing around.

So the bot does not need anything clever - it needs to be a competent innocent while alive, and to
put that second life to use afterwards. The latter is already handled by the morality component's
grudge: whoever killed us is remembered, and OnRevived sends the bot after them. This entry exists so
that team knowledge, suspicion, C4 duties and the behavior tree are the innocent ones rather than
whatever the generic fallback guessed.
]]

local occultist = TTTBots.RoleData.New("occultist", TEAM_INNOCENT)
occultist:SetDefusesC4(true)
occultist:SetTeam(TEAM_INNOCENT)
occultist:SetBTree(TTTBots.Behaviors.DefaultTrees.innocent)
occultist:SetCanHide(true)
occultist:SetCanSnipe(true)
occultist:SetUsesSuspicion(true)
occultist:SetAlliedRoles({})
occultist:SetAlliedTeams({})
TTTBots.Roles.RegisterRole(occultist)

return true
