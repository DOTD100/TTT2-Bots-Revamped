if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_CURSED then return false end

--[[
The Cursed (AaronMcKenney/ttt2-role_curs) is the only role in this tree with no team at all: its file sets
`defaultTeam = TEAM_NONE` with `unknownTeam`, `preventWin = true`, every score multiplier to zero, no credits
and a shop that is disabled outright. It cannot win, and it cannot make anybody else lose - its own
`EntityTakeDamage` hook zeroes every point of damage a Cursed deals to a player, and it revives itself
`ttt2_cursed_seconds_until_respawn` seconds after each death for as long as the round lasts. The only move it
has is to hand the curse to somebody else, and both of the addon's ways of doing that are things a bot cannot
reach by itself - behaviors/curseswap.lua is that half.

What is left for this profile is almost entirely declarative:

  * **SetDealsNoDamage is the flag the role hangs on.** It is the flag the Beggar and the Collusionist already
    use: behaviors/attacktarget.lua reads it and refuses to hold a target at all, because walking into the
    open to shoot somebody you cannot hurt is only a way to die. The tree below has no FightBack node for the
    same reason.
  * **No team means no allies**, so the default (everybody on your team is a friend) is replaced with an empty
    set. A Cursed is nobody's friend and everybody's target, which is exactly how the addon scores it.
  * **The ranged route is given, not bought**: the role's own loadout hands out the RoleSwap Deagle, so there
    is nothing to add to the buyables. Its `SWEP.Kind` is WEAPON_EXTRA, which this addon's inventory never
    equips, so the behaviour that wants it selects it by hand.
  * **Damage immunity is a convar, not a fixed trait.** `ttt2_cursed_damage_immunity` ships at 0, and the same
    hook above zeroes every point of damage aimed at the Cursed once it is turned on - so the flag is answered
    from the convar at the point of use instead of sampled while this file loads, the way the addon reads it.
]]

local _bh = TTTBots.Behaviors
local _prior = TTTBots.Behaviors.PriorityNodes

-- Handing the curse over *is* the role. The noise node is how the bot finds people to hand it to - gunfire is
-- where the players are, and a Cursed has no other use for a sound - and Patrol is what it does in between.
local bTree = {
    -- Handing the curse on is the whole round for this role, but the post-round deathmatch is not the round: a
    -- Cursed cannot hurt anybody, so it hides there instead (behaviors/evade.lua).
    _prior.Survive,
    _bh.CurseSwap,
    _bh.InvestigateNoise,
    _prior.Patrol
}

-- A profile is filed under the role's *name*, which is what `GetRoleFor` looks up (`Player:GetRoleStringRaw`
-- returns `GetSubRoleData().name`). `ROLE_CURSED` is not that name: TTT2 gives every role a numeric index and
-- publishes it as the ROLE_ global (`_G["ROLE_" .. NAME] = roleData.index`), so a profile registered under it
-- would be filed under a number and never found, silently falling back to the innocent profile. TTT2 also
-- publishes the role table itself as the uppercase global, so ask it rather than hard-coding the spelling.
local cursedName = (CURSED and CURSED.name) or "cursed"
local cursedTeam = TEAM_NONE or "none"

--- Mirrors `ttt2_cursed_damage_immunity` at the point of use.
---
--- Read live rather than stored because the convar can be flipped between rounds, and every reader of this
--- flag - the attack behaviour, the morality component - asks it live for the same reason.
---@return boolean
local function readDamageImmunity()
    local cv = GetConVar("ttt2_cursed_damage_immunity")

    return (cv and cv:GetBool()) or false
end

local cursed = TTTBots.RoleData.New(cursedName, cursedTeam)
cursed:SetDefusesC4(false)
cursed:SetPlantsC4(false)
cursed:SetCanHaveRadar(false)
cursed:SetCanCoordinate(false)
cursed:SetStartsFights(false)
cursed:SetUsesSuspicion(false)
cursed:SetCanHide(false)
cursed:SetCanSnipe(false)
cursed:SetDealsNoDamage(true)
cursed:SetTeam(cursedTeam)
cursed:SetBTree(bTree)
cursed:SetAlliedRoles({})
cursed:SetAlliedTeams({})
-- The getter, not the flag: see readDamageImmunity.
cursed.GetIsDamageImmune = readDamageImmunity
TTTBots.Roles.RegisterRole(cursed)

return true
