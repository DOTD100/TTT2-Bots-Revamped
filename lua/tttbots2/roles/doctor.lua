if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_DOCTOR then return false end

--[[
The Doctor is an innocent with a defibrillator and no other ability of its own. Its extracted role file
(workshop id 2755172511) says so plainly, and it confirms the piece that matters most here:

    function ROLE:GiveRoleLoadout(ply) ply:GiveEquipmentWeapon("weapon_ttt_defibrillator") end

That is the exact class the Defib behavior already recognises, so the bot does not need anything new to use
it. The rest of the file is what shapes this entry:

  * defaultTeam = TEAM_INNOCENT with roles.SetBaseRole(self, ROLE_INNOCENT), so it is an innocent.
  * isPolicingRole = true, mirrored as AppearsPolice, which keeps the suspicion the bots hold against a
    policing-looking player down and stops them calling KOS on it. For an innocent that is simply what the
    role is.
  * shopFallback = SHOP_NONE, so the role has no shop at all: the defibrillator is handed over by the
    loadout rather than bought, and the bot has nothing to spend credits on.

The behavior tree is the detective's - the innocent tree with Defib slotted in between fight-back and the
C4 work - since that is the one tree that already carries a defib node.

Two role flags are what make a Doctor bot's defib worth carrying, and they work together:

  * SetRevivesAnyCorpse - the behavior's default is teammates only, and the innocent side declares no allies
    on purpose (innocents do not know who is who), so an ally-only defib would leave this bot walking past
    every corpse in the round. This is what lets it look at a body at all.
  * SetRevivesInnocentSide - and this is what makes it *choose*. Of the bodies it can reach, it brings back
    the ones on its own side and leaves the traitors where they lie, because a revived traitor is worse than
    no revive. The body's role is read off the ragdoll, which is the same licence the corpse investigation
    and the Paranoid's reveal already take - a body is unidentified to a player, so there is no other way to
    know which corpse the Doctor would want. Detectives need no special case: they are on the innocent team
    like everyone else on that side, so choosing "not a traitor" already chooses them.

The defibrillator is exclusive to this role, but it is deliberately not declared as a role weapon. Holding
a defibrillator is not an act of aggression, and a morality tell on one would make every bot shoot whoever
is standing over a body - the opposite of what the role is for.
]]

local doctor = TTTBots.RoleData.New("doctor", TEAM_INNOCENT)
doctor:SetDefusesC4(true)
doctor:SetPlantsC4(false)
doctor:SetStartsFights(false)
doctor:SetUsesSuspicion(true)
doctor:SetCanHide(true)
doctor:SetCanSnipe(true)
doctor:SetTeam(TEAM_INNOCENT)
doctor:SetAppearsPolice(true)
doctor:SetRevivesAnyCorpse(true)
doctor:SetRevivesInnocentSide(true)
doctor:SetBTree(TTTBots.Behaviors.DefaultTrees.detective)
doctor:SetAlliedRoles({})
doctor:SetAlliedTeams({})
TTTBots.Roles.RegisterRole(doctor)

return true
