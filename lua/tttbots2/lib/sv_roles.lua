--- This module is an abstraction layer for TTT/2 compatibility.

TTTBots.Roles = {}

local lib = TTTBots.Lib
TTTBots.Roles.m_roles = {}

--- Weapon class -> the one role that is ever handed it. Built from the roles' own declarations
--- (RoleData:SetRoleWeapons), because TTT2 marks nothing on the weapon itself.
---@type table<string, string>
TTTBots.Roles.m_roleWeapons = {}

include("sv_roledata.lua")

function TTTBots.Roles.RegisterRole(roleData)
    TTTBots.Roles.m_roles[roleData:GetName()] = roleData

    for _, class in pairs(roleData:GetRoleWeapons() or {}) do
        TTTBots.Roles.m_roleWeapons[class] = roleData:GetName()
    end
end

--- The role a weapon class belongs to, if it is that role's own exclusive weapon.
---
--- A role weapon is not a shop item: it is handed to the role by its own loadout, so it cannot be bought
--- and it does not spawn on the map. That is what makes seeing one proof of the holder's role - the
--- Arsonist's thrower means an Arsonist - as opposed to a shop weapon, which a bot may legitimately own
--- (a role borrowing another team's shop) or simply have picked up.
---@param class string
---@return string? roleName
function TTTBots.Roles.GetRoleOfWeapon(class)
    if not class then return nil end

    return TTTBots.Roles.m_roleWeapons[class]
end

--- Return a role by its name.
---@param name string
---@return RoleData
---@return boolean - Whether or not the role is the default role.
function TTTBots.Roles.GetRole(name)
    local selected = TTTBots.Roles.m_roles[name]
    local isDefault = false
    if not selected then
        selected = TTTBots.Roles.m_roles["innocent"]
        isDefault = true
    end

    return selected, isDefault
end

---Returns the RoleData of the player, else nil if it doesn't exist.
---@param ply Player
---@return RoleData
---@return boolean - Whether or not the role is the default role.
function TTTBots.Roles.GetRoleFor(ply)
    local roleString = ply:GetRoleStringRaw()
    return TTTBots.Roles.GetRole(roleString)
end

--- Is body identification impossible for this player right now, because of somebody else's role?
---
--- The Blocker works this way: while one is alive its addon makes TTT2's `TTTCanSearchCorpse` hook
--- refuse every search but the Blocker's own, and every body is then identified at once when the last
--- Blocker dies. Anything that identifies a body has to ask this first, because the call our own
--- behavior makes (`CORPSE.ShowSearch`) sits *below* the hook that role installs and so ignores it.
---
--- Read live rather than cached: the answer changes the instant the last Blocker dies, and again if
--- one is defibrillated back into the round.
---@param ply Player
---@return boolean
function TTTBots.Roles.IsCorpseIdentifyBlockedFor(ply)
    for _, other in pairs(TTTBots.Match.AlivePlayers) do
        if other ~= ply and TTTBots.Roles.GetRoleFor(other):GetBlocksCorpseIdentify() then
            return true
        end
    end

    return false
end

--- Return a comprehensive table of the defined roles.
---@return table<RoleData>
function TTTBots.Roles.GetRoles() return TTTBots.Roles.m_roles end

function TTTBots.Roles.GetLivingAllies(player)
    local alive = TTTBots.Match.AlivePlayers
    return TTTBots.Lib.FilterTable(alive, function(other)
        return TTTBots.Roles.IsAllies(player, other)
    end)
end

---Gets if the player is the ally of another player. This is based on the role's allies.
---@param ply1 Player
---@param ply2 Player
---@return boolean
function TTTBots.Roles.IsAllies(ply1, ply2)
    if not (IsValid(ply1) and IsValid(ply2)) then return false end
    local role1 = TTTBots.Roles.GetRoleFor(ply1)
    local role2 = TTTBots.Roles.GetRoleFor(ply2)

    -- Workaround for roles like Bodyguard where player team is adjusted on-the-fly
    if (
        (role1:GetLovesTeammates() or role2:GetLovesTeammates())
        and (ply1:GetTeam() == ply2:GetTeam())
    ) then return true end

    -- Now just testing if the roles are setup to care about each other.
    local allied1 = role1:GetAlliedRoles()[role2:GetName()] or role1:GetAlliedTeams()[role2:GetTeam()] or false
    local allied2 = role2:GetAlliedRoles()[role1:GetName()] or role2:GetAlliedTeams()[role1:GetTeam()] or false

    -- Using 'or' here intentionally, as the mode does not currently support one-sided alliances.
    return allied1 or allied2
end

--- Returns true if the player's current role cannot be hurt by other players, meaning attacking
--- them accomplishes nothing. Read live rather than cached, so a role swapping to a different
--- player (as the Swapper does on death) is picked up immediately.
---@param ply Player
---@return boolean
function TTTBots.Roles.IsPlayerDamageImmune(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    return TTTBots.Roles.GetRoleFor(ply):GetIsDamageImmune()
end

--- Does this player play the fool - a role that wins by being blamed and killed for it?
---
--- The Jester and the Swapper are the shipped ones and both sit on the jesters' team, which is what this
--- checks, so any other role that adds itself to that team is covered too.
---@param ply Player
---@return boolean
function TTTBots.Roles.IsFoolRole(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end

    return ply:GetTeam() == (TEAM_JESTER or "jesters")
end

--- Can this player take part in a shooting fight at all?
---
--- Two ways a role cannot: its own addon zeroes every point of damage it deals to a player (the Beggar, the
--- Collusionist, the Cursed), or nobody can damage *it* (the Swapper, which exists to be killed by somebody who
--- then inherits the role). The fool roles cover the rest of the jesters' team: their whole purpose is to be
--- killed, so asking one of them to shoot somebody is asking it to lose - and in the post-round deathmatch
--- there is not even a role left to play.
---
--- Read live, like every other role query in this file: the Beggar's team, and with it its role, changes the
--- moment it picks a dropped shop weapon up, and the Swapper hands its role to whoever killed it.
---
--- The one reader is the deathmatch, where this is what decides whether a bot is handed a target at all and
--- whether behaviors/evade.lua takes it out of the fight. During the round it changes nothing: a Jester still
--- picks its fights, which is how a fool gets itself killed.
---@param ply Player
---@return boolean
function TTTBots.Roles.IsNonCombatant(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end

    local role = TTTBots.Roles.GetRoleFor(ply)
    if role:GetDealsNoDamage() or role:GetIsDamageImmune() then return true end

    return TTTBots.Roles.IsFoolRole(ply)
end

---Get a table of players that are not allies with ply1, and are alive.
---Damage-immune roles are excluded: they cannot be hurt, so they are not valid opponents.
---@param ply1 Player
---@return table<Player>
function TTTBots.Roles.GetNonAllies(ply1)
    local alive = TTTBots.Match.AlivePlayers
    return TTTBots.Lib.FilterTable(alive, function(other)
        if not (IsValid(other) and lib.IsPlayerAlive(other)) then return false end
        if TTTBots.Roles.IsPlayerDamageImmune(other) then return false end
        return not TTTBots.Roles.IsAllies(ply1, other)
    end)
end

---Returns if the bot's team is that of a traitor. Not recommende for determining who is friendly, as this is only based on the team, and not the role's allies.
---@param bot any
---@return boolean
function TTTBots.Roles.IsTraitor(bot)
    return bot:GetTeam() == TEAM_TRAITOR
end

--- Walk up the TTT2 baserole chain and return the RoleData of the nearest ancestor we have ACTUALLY
--- registered, plus its name. Unregistered intermediaries are skipped rather than silently
--- falling back to the innocent defaults.
---@param roleObj table The TTT2 role object
---@return RoleData? ancestorData
---@return string? ancestorName
local function GetRegisteredAncestorRoleData(roleObj)
    local seen = {}
    local current = roleObj
    while current and current.baserole do
        local base = roles.GetByIndex(current.baserole)
        if not base or seen[base.name] then break end
        seen[base.name] = true

        local baseData, baseIsDefault = TTTBots.Roles.GetRole(base.name)
        if baseData and not baseIsDefault then
            return baseData, base.name
        end

        current = base
    end
    return nil
end

--- Determine whether a role is "killer/traitor-like" so it reliably gets fight-starting behavior.
--- Walks the inheritance chain, so traitor subroles that use a custom team but inherit from a
--- traitor-ish role are still treated as aggressors.
---@param roleObj table
---@return boolean isKillerLike
local function IsKillerLikeRole(roleObj)
    local seen = {}
    local current = roleObj
    while current do
        if current.defaultTeam == TEAM_TRAITOR then return true end
        if not current.baserole or seen[current.baserole] then break end
        seen[current.baserole] = true
        current = roles.GetByIndex(current.baserole)
    end
    return false
end

--- Role names whose profile was invented by GenerateRegisterForRole rather than claimed by a file of ours.
---
--- The distinction matters because a generated profile is registered under the same name, so `GetRole` stops
--- reporting the role as unknown the moment one exists - and a stand-in would then shadow the real file for the
--- rest of the session, which is the Blocker's whole problem in one sentence.
---@type table<string, boolean>
local autoGeneratedRoles = {}

--- Tries to automatically register a role, based on its base role or role info. This is far from perfect, but it's better than nothing.
---@param roleString string
---@return boolean - Whether or not we successfully registered a role.
function TTTBots.Roles.GenerateRegisterForRole(roleString)
    -- If we are in this function, this is definitely TTT2. But check anyway :)))
    if not TTTBots.Lib.IsTTT2() then return false end
    local roleObj = roles.GetByName(roleString)
    if not roleObj then return false end

    -- Prefer cloning the nearest registered ancestor (handles multi-level inheritance and
    -- unregistered intermediaries). We only clone real registrations, never the innocent default.
    local ancestorData, ancestorName = GetRegisteredAncestorRoleData(roleObj)
    if ancestorData then
        local copy = table.Copy(ancestorData)
        setmetatable(copy, TTTBots.RoleData) -- table.Copy drops the metatable; restore it
        copy:SetName(roleString)
        TTTBots.Roles.RegisterRole(copy)
        autoGeneratedRoles[roleString] = true
        print(string.format("[TTT Bots 2] Auto-registered role '%s' based off of '%s'", roleString, ancestorName))
        return true
    end

    local roleTeam = roleObj.defaultTeam
    local isOmniscient = roleObj.isOmniscientRole or false
    -- local isPublicRole = role.isPublicRole or false     -- If the role is known to everyone. Unused here
    local isPolicingRole = roleObj.isPolicingRole or false -- if the role is a policing role
    local isKillerLike = IsKillerLikeRole(roleObj)

    local data = TTTBots.RoleData.New(roleString)
    data:SetTeam(roleTeam)
    data:SetUsesSuspicion(not (isKillerLike or isOmniscient))
    data:SetCanCoordinate(isKillerLike)
    data:SetCanHaveRadar(isPolicingRole or isKillerLike)
    data:SetKnowsLifeStates(isOmniscient)
    data:SetBTree(
        TTTBots.Behaviors.DefaultTreesByTeam[roleTeam]
        or (isKillerLike and TTTBots.Behaviors.DefaultTrees.traitor)
        or TTTBots.Behaviors.DefaultTrees.innocent
    )
    data:SetStartsFights(isKillerLike)

    -- Killer-like roles must be treated as allies of the traitor team, otherwise the traitor
    -- tree (AttackTarget on non-allies) would have them fight their own team.
    local alliedRoles = { [roleString] = true }
    if isKillerLike then
        alliedRoles["traitor"] = true
    end
    data:SetAlliedRoles(alliedRoles)

    local alliedTeams = {}
    if roleTeam then
        alliedTeams[roleTeam] = true
    end
    if isKillerLike and TEAM_TRAITOR then
        alliedTeams[TEAM_TRAITOR] = true
        alliedTeams[TEAM_JESTER or "jesters"] = true
    end
    data:SetAlliedTeams(alliedTeams)

    if roleString ~= 'none' then
        local registeredManually = hook.Run("TTTBotsRoleRegistered", data)
        print(string.format("[TTT Bots 2] Registered role '%s' as a part of team '%s'!", roleString, data:GetTeam()))
        if not registeredManually then
            print(
                "[TTT Bots 2] The above role was not caught by any compatibility scripts! You may experience strange bot behavior for this role.")
        end
    end
    TTTBots.Roles.RegisterRole(data)
    autoGeneratedRoles[roleString] = true
    return true
end

--- Give our own hand-written profile for a role another chance, at the point the role turns up in play.
---
--- Every file in `tttbots2/roles/` guards on the role's global (`if not ROLE_BLOCKER then return false end`) and
--- they are all included while *this* addon loads. GMod decides for itself which addon's files run first, so an
--- addon that loads after ours leaves its global nil, that file quietly returns false, and the auto-registration
--- below then registers a **clone of the base role's profile** instead - which is precisely where a role's
--- hand-written flags go missing. The Blocker is what exposed it: its profile is a traitor clone with no
--- `blocksCorpseIdentify`, so every other bot went back to identifying the bodies the role exists to hide.
---@param roleString string
---@return boolean - Whether one of our own files registered the role this time.
local function tryIncludingRoleFile(roleString)
    local path = "tttbots2/roles/" .. roleString .. ".lua"
    if not file.Exists(path, "LUA") then return false end

    include(path) -- a no-op if the role's global is still missing: the file returns false immediately

    local _, isDefault = TTTBots.Roles.GetRole(roleString)
    return not isDefault
end

--- Create a timer on 2-second intervals to auto-generate roles if round started and we find an unknown role
---
--- Every *alive player* is checked, not just the bots: a human's profile is read by bots constantly - is their
--- role immune, does it look like police, does it hide the dead from us - so a human role we never registered
--- makes all of those answers wrong for everybody, and the Blocker is the clearest example of it. The timer
--- used to iterate `TTTBots.Bots` alone, which is why a human Blocker could hide the dead from every bot while
--- no bot believed anybody was doing it.
timer.Create("TTTBots.AutoRegisterRoles", 2, 0, function()
    for _, ply in pairs(TTTBots.Match.AlivePlayers) do
        if not IsValid(ply) then continue end

        local roleString = ply:GetRoleStringRaw()
        local _, isDefault = TTTBots.Roles.GetRole(roleString)

        -- `isDefault` means nothing has claimed this name at all. The marker means a *generated* stand-in did, and
        -- a stand-in is a clone of the base role with none of the role's own flags - so it has to keep giving way
        -- to the real file for as long as the addon defining it takes to load.
        local oursIsMissing = isDefault or autoGeneratedRoles[roleString] == true
        if not oursIsMissing then continue end

        if tryIncludingRoleFile(roleString) then
            autoGeneratedRoles[roleString] = nil
            print(string.format(
                "[TTT Bots 2] Registered role '%s' late: its addon loaded after this one, so its file had nothing to register against the first time.",
                roleString))
        elseif isDefault then
            TTTBots.Roles.GenerateRegisterForRole(roleString)
        end
    end
end)

local includedFilesTbl = TTTBots.Lib.IncludeDirectory("tttbots2/roles")
local includedFilesStr = TTTBots.Lib.StringifyTable(includedFilesTbl)
print("[TTT Bots 2] Registered officially supported roles: " .. string.gsub(includedFilesStr, ".lua", ""))

if TTTBots.Lib.IsTTT2() then return end

local plyMeta = FindMetaTable("Player")

function plyMeta:GetTeam()
    if self:IsTraitor() then return 'traitors' end
    if self:IsDetective() then return 'detectives' end
    return 'innocents'
end

function plyMeta:IsInTeam(other)
    if not (IsValid(self) and IsValid(other)) then return false end
    return self:Team() == other:Team()
end
