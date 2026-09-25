---@class RoleData
TTTBots.RoleData = {}
TTTBots.RoleData.__index = TTTBots.RoleData

local lib = TTTBots.Lib

---Creates a new RoleData object.
---@param rolename string
---@param roleteam? string A TEAM_ enum, or nil (defaults to TEAM_INNOCENT). This is usually a string, like 'jesters' or 'traitors'
---@return RoleData
function TTTBots.RoleData.New(rolename, roleteam)
    ---@class RoleData
    local newRole = {}
    setmetatable(newRole, TTTBots.RoleData)

    local getSet = lib.GetSet

    --- Get the name
    newRole.GetName, newRole.SetName = getSet("name", rolename)

    --- Enemies are players we know immediately that they are enemies.
    newRole.GetEnemies, newRole.SetEnemies = getSet("enemies", {})

    --- The behavior tree that is ran across this role
    newRole.GetBTree, newRole.SetBTree = getSet("btree", {})

    --- Get whether or not we are a "planting" role, aka we can plant C4.
    newRole.GetPlantsC4, newRole.SetPlantsC4 = getSet("plantsC4", false)

    --- Whether or not this role can defuse C4.
    newRole.GetDefusesC4, newRole.SetDefusesC4 = getSet("defusesC4", false)

    --- Get a list of weapon names
    newRole.GetBuyableWeapons, newRole.SetBuyableWeapons = getSet("buyableItems", {})

    --- Can this role simulate owning radar?
    newRole.GetCanHaveRadar, newRole.SetCanHaveRadar = getSet("canHaveRadar", false)

    --- Can/do we coordinate with other traitors?
    newRole.GetCanCoordinate, newRole.SetCanCoordinate = getSet("canCoordinate", false)

    --- Do we kill players that aren't on our team? Essentially, this disables/enables if the bot will
    --- "randomly" shoot at nearby non-allies. Particularly useful for traitors.
    newRole.GetStartsFights, newRole.SetStartsFights = getSet("killsNonAllies", false)

    --- Is auto-switch enabled/disabled? Auto-switch is what makes the bots automatically swap between weapons.
    --- This is useful if a role requires a specific weapon to be held.
    newRole.GetAutoSwitch, newRole.SetAutoSwitch = getSet("autoSwitch", true)

    --- Set the preferred weapon class to hold out at all times. This is useful for roles that require a specific weapon.
    --- You must disable SetAutoSwitch for this to work. You should control your bot weapon with the behavior tree if your role is more nuanced.
    newRole.GetPreferredWeapon, newRole.SetPreferredWeapon = getSet("preferredWeapon", nil)

    --- Get the team for this role. E.g., TEAM_INNOCENT, TEAM_INNOCENT, etc.
    newRole.GetTeam, newRole.SetTeam = getSet("team", roleteam or TEAM_INNOCENT)

    --- Some roles are more likely to follow due to their nature. This is a boolean that determines if this role is more likely to follow.
    --- This is particularly useful for traitors, because it tends to make them follow someone until they are alone.
    newRole.GetIsFollower, newRole.SetIsFollower = getSet("follower", false)

    --- If the bot can "look at the scoreboard" to see who is dead and alive. Functionally this just makes the bot know who is dead/alive at all times.
    newRole.GetKnowsLifeStates, newRole.SetKnowsLifeStates = getSet("knowsLifeStates", false)

    --- If the player appears as a police player. Useful for the 'defective' role, so bots trust them.
    newRole.GetAppearsPolice, newRole.SetAppearsPolice = getSet("appearsPolice", false)

    --- If the bot uses the suspicion system to determine who is good and bad.
    newRole.GetUsesSuspicion, newRole.SetUsesSuspicion = getSet("usesSuspicion", true)

    --- Allies are people we know for sure are on our team. For traitors, you want to also set "traitor" as one of these, because
    --- they know who each other are. This is particularly used for defending one another in combat.
    newRole.GetAlliedRoles, newRole.SetAlliedRoles = getSet("allies", { [rolename] = true })

    --- Allied teams are teams that are explicitly set as DO NOT ATTACK. This is helpful for allying jester towards traitors, for example. So they don't hurt each other.
    --- This should only be used for teams that know who each other are inherently. Such as omniscient roles.
    newRole.GetAlliedTeams, newRole.SetAlliedTeams = getSet("alliedTeams", { [newRole:GetTeam()] = true })

    --- If the bot can navigate to hiding spots instead of wandering randomly (applies to Wander behavior)
    newRole.GetCanHide, newRole.SetCanHide = getSet("canHide", false)

    --- If the bot can navigate to sniper spots instead of wandering randomly (applies to Wander behavior)
    newRole.GetCanSnipe, newRole.SetCanSnipe = getSet("canSnipe", true)

    --- If the bot automatically registers teammates via Player:GetTeam() as teammates. Used to consider Bodyguards as allies.
    newRole.GetLovesTeammates, newRole.SetLovesTeammates = getSet("lovesTeammates", false)

    --- If this role hunts a victim that its own addon publishes through TTT2's Player:SetTargetPlayer(), and
    --- the bot should go after it. Used by the Hitman and the Executioner. Note that TTT2 documents that pair
    --- as the target a player is *spectating* - what the HUD uses to show who you are looking at - so it is the
    --- role's addon that gives it meaning here; behaviors/hunttarget.lua is the only reader.
    newRole.GetHuntsTarget, newRole.SetHuntsTarget = getSet("huntsTarget", false)

    --- Some roles cannot be hurt by other players at all (the Swapper is one), which makes any fight
    --- against them a pure waste of ammo. Bots refuse to pick such players as targets or to chase
    --- them. This is read live rather than remembered, so it also covers roles that change hands
    --- mid-round (the Swapper hands its own role to whoever killed it).
    newRole.GetIsDamageImmune, newRole.SetIsDamageImmune = getSet("damageImmune", false)

    --- Some roles shop as a bluff rather than to arm themselves: the order is refused, nothing is handed
    --- over, and the traitors are told an item was bought so the buyer looks like one of them. TTT2's Spy
    --- is the role this exists for, and the gamemode gates it on a convar of its own, so this flag holds
    --- that convar's *name* and the buyables read it live rather than trusting a value captured at load.
    ---@see TTTBots.Buyables.FakesShopOrders
    newRole.GetFakeShopConvar, newRole.SetFakeShopConvar = getSet("fakeShopConvar", nil)

    --- Weapon classes that only this role is ever handed - its own loadout weapon, which no shop sells and
    --- no map spawns. The Arsonist's thrower and the Shanker's knife are the cases this exists for: an
    --- untradeable item that the role spawns with is proof of the role, unlike a shop weapon, which anyone
    --- who can afford it - or anyone who has looted a corpse - can be carrying.
    ---
    --- TTT2 gives role weapons no flag of their own, so roles declare theirs here and
    --- TTTBots.Roles.RegisterRole folds them into the lookup the morality component reads.
    ---@see TTTBots.Roles.GetRoleOfWeapon
    newRole.GetRoleWeapons, newRole.SetRoleWeapons = getSet("roleWeapons", nil)

    --- Some roles cannot hurt anyone at all: the addon that ships them zeroes every point of damage they
    --- deal to another player (the Beggar and the Collusionist both work this way - they are meant to
    --- change sides by looting a dropped shop weapon, not to fight). A bot in one of those roles must
    --- never take a target, because walking into the open to shoot somebody it cannot hurt only gets it
    --- killed. Read live rather than cached, since the Beggar's team - and with it its role - changes the
    --- moment it picks a shop weapon up.
    newRole.GetDealsNoDamage, newRole.SetDealsNoDamage = getSet("dealsNoDamage", false)

    --- Whether reviving a corpse turns it into an ally of this role, which makes *any* corpse worth the
    --- defibrillator rather than only a teammate's. The Mesmerist is the case this exists for: whoever its
    --- own defibrillator is used on comes back as a Thrall on its side, so a bot holding it should walk to
    --- the nearest body instead of waiting for one of its own to fall.
    ---@see TTTBots.Behaviors.Defib
    newRole.GetRevivesAnyCorpse, newRole.SetRevivesAnyCorpse = getSet("revivesAnyCorpse", false)

    --- Narrows the rule above to the innocent side. The Doctor is the case this exists for: it is an innocent
    --- with nothing but a defibrillator and no allies (the innocent roster deliberately declares none), so it
    --- needs the any-corpse rule to find a body at all - but a body that turns out to have been a traitor is
    --- worse than no revive, so its corpse is left where it lies. Fools (the Jester and friends) are
    --- deliberately still allowed through: raising one is a wash rather than a loss.
    ---@see TTTBots.Behaviors.Defib
    newRole.GetRevivesInnocentSide, newRole.SetRevivesInnocentSide = getSet("revivesInnocentSide", false)

    --- Some roles hide the dead from everybody else: while one of them is alive, TTT2 refuses every body
    --- search except that role's own, and the bodies are only identified in one go once the last one of
    --- them dies. The Blocker is the case this exists for.
    ---
    --- Other bots have to be told, because they do not search a body the way a player does: they call
    --- `CORPSE.ShowSearch` and `CORPSE.SetFound` **directly**, which is below the hook such a role
    --- installs, so without this flag a bot would walk over and identify exactly the bodies the role
    --- exists to keep anonymous - and would keep re-targeting them, because they never become found.
    ---@see TTTBots.Roles.IsCorpseIdentifyBlockedFor
    ---@see TTTBots.Behaviors.InvestigateCorpse
    newRole.GetBlocksCorpseIdentify, newRole.SetBlocksCorpseIdentify = getSet("blocksCorpseIdentify", false)

    return newRole
end

---Basically just returns if team == TEAM_TRAITOR
---@return boolean
function TTTBots.RoleData:IsTraitor()
    return self:GetTeam() == TEAM_TRAITOR
end
