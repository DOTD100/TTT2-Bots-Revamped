---@class CInventory : Component
TTTBots.Components.Inventory = {}

local lib = TTTBots.Lib
---@class CInventory : Component
local BotInventory = TTTBots.Components.Inventory

function BotInventory:New(bot)
    local newInventory = {}
    setmetatable(newInventory, {
        __index = function(t, k) return BotInventory[k] end,
    })
    newInventory:Initialize(bot)

    local dbg = lib.GetConVarBool("debug_misc")
    if dbg then
        print("Initialized Inventory for bot " .. bot:Nick())
    end

    return newInventory
end

function BotInventory:Initialize(bot)
    -- print("Initializing")
    bot.components = bot.components or {}
    bot.components.Inventory = self

    self.componentID = string.format("inventory (%s)", lib.GenerateID()) -- Component ID, used for debugging

    self.tick = 0
    self.disabled = false

    self.bot = bot
end

---@class WeaponInfo Information about a weapon
---@field class string Classname of the weapon
---@field clip number CURRENT Ammo in the clip
---@field max_ammo number MAX Ammo in the clip
---@field ammo number Ammo in the inventory
---@field ammo_type number Ammo type of the weapon, https://wiki.facepunch.com/gmod/Default_Ammo_Types
---@field ammo_type_string string Ammo type of the string, after having been converted from the number. See ammo_type.
---@field slot string Slot of the weapon, functionally just a string version of the Kind
---@field hold_type string Hold type of the weapon, typically used for animations
---@field is_gun boolean If the weapon is a gun (that is, if it has a clip or not)
---@field needs_reload boolean If the bot needs to reload this weapon, because it has 0 shots left
---@field should_reload boolean If the weapon has less than 100% ammo remaining. Only reload during peace
---@field has_bullets boolean If the weapon has any bullets in the **INVENTORY** (not clip!)
---@field print_name string Name of the weapon, more human readable than class
---@field kind number Kind of the weapon, https://wiki.facepunch.com/gmod/Enums/WEAPON
---@field ammo_ent string Classname of the ammo entity
---@field is_traitor_weapon boolean If the weapon is a traitor weapon
---@field is_detective_weapon boolean If the weapon is a detective weapon
---@field silent boolean If the weapon is silent
---@field can_drop boolean If the weapon can be dropped
---@field damage number Damage of the weapon
---@field rpm number Rounds per minute of the weapon
---@field numshots number Number of shots per fire
---@field dps number Damage per second of the weapon
---@field time_to_kill number Time to kill of the weapon
---@field is_automatic boolean If the weapon is automatic
---@field is_sniper boolean If the weapon is a sniper
---@field is_shotgun boolean If the weapon is a shotgun
---@field is_melee boolean If the weapon is a shotgun
---@field timestamp number The CurTime() when this info was last updated

--- A hash table for the ammo_type field in an info table. See https://wiki.facepunch.com/gmod/Default_Ammo_Types
local ammoTypes = {
    [1] = { name = "ar2", description = "weapon_ar2 ammo" },
    [2] = { name = "ar2altfire", description = "weapon_ar2 altfire ammo" },
    [3] = { name = "pistol", description = "weapon_pistol ammo" },
    [4] = { name = "smg1", description = "weapon_smg1 ammo" },
    [5] = { name = "357", description = "weapon_357 ammo" },
    [6] = { name = "xbowbolt", description = "weapon_crossbow ammo" },
    [7] = { name = "buckshot", description = "weapon_shotgun ammo" },
    [8] = { name = "rpg_round", description = "weapon_rpg ammo" },
    [9] = { name = "smg1_grenade", description = "weapon_smg1 altfire ammo" },
    [10] = { name = "grenade", description = "weapon_frag ammo" },
    [11] = { name = "slam", description = "weapon_slam ammo" },
    [12] = { name = "alyxgun", description = "weapon_alyxgun ammo" },
    [13] = { name = "sniperround", description = "combine sniper ammo" },
    [14] = { name = "sniperpenetratedround", description = "combine sniper alternate ammo" },
    [15] = { name = "thumper", description = "" },
    [16] = { name = "gravity", description = "" },
    [17] = { name = "battery", description = "" },
    [18] = { name = "gaussenergy", description = "" },
    [19] = { name = "combinecannon", description = "" },
    [20] = { name = "airboatgun", description = "airboat mounted gun ammo" },
    [21] = { name = "striderminigun", description = "strider minigun ammo" },
    [22] = { name = "helicoptergun", description = "attack helicopter ammo" },
    [23] = { name = "9mmround", description = "hl:s pistol ammo" },
    [24] = { name = "357round", description = "hl:s .357 ammo" },
    [25] = { name = "buckshothl1", description = "hl:s shotgun ammo" },
    [26] = { name = "xbowbolthl1", description = "hl:s crossbow ammo" },
    [27] = { name = "mp5_grenade", description = "hl:s mp5 grenade ammo" },
    [28] = { name = "rpg_rocket", description = "hl:s rocket launcher ammo" },
    [29] = { name = "uranium", description = "hl:s gauss/gluon gun ammo" },
    [30] = { name = "grenadehl1", description = "hl:s grenade ammo" },
    [31] = { name = "hornet", description = "hl:s hornet ammo" },
    [32] = { name = "snark", description = "hl:s snark ammo" },
    [33] = { name = "tripmine", description = "hl:s tripmine ammo" },
    [34] = { name = "satchel", description = "hl:s satchel charge ammo" },
    [35] = { name = "12mmround", description = "hl:s related ammo (heavy turret entity?)" },
    [36] = { name = "striderminigundirect", description = "npc_strider \"enableaggressivebehavior\" ammo (less damage)" },
    [37] = { name = "combineheavycannon", description = "the \"combine autogun\" ammo from half-life 2: episode 2" }
}

BotInventory.kindHash = {
    [1] = "melee",
    [2] = "secondary",
    [3] = "primary",
    [4] = "grenade",
    [5] = "carry",
    [6] = "unarmed",
    [7] = "special",
    [8] = "extra",
    [9] = "class",
    
    melee = 1,
    secondary = 2,
    primary = 3,
    grenade = 4,
    carry = 5,
    unarmed = 6,
    special = 7,
    extra = 8,
    class = 9,
}

BotInventory.wInfoCache = {} ---@type table<Weapon, WeaponInfo>
BotInventory.wInfoCacheTime = 1 --- Number of seconds before a cached weapon info is invalidated.

---Validate the cache for the weapon. Also returns the WeaponInfo if it's valid, otherwise nil.
---@param wep Weapon
---@return WeaponInfo?
---Does this weapon info describe something we could actually shoot with right now?
---@param info WeaponInfo?
---@return boolean
local function wepInfoHasAmmo(info)
    if not info then return false end

    return (info.ammo > 0) or (info.clip > 0)
end

local function cacheValidate(wep)
    local timeNow = CurTime()
    local cachedWeapon = BotInventory.wInfoCache[wep]
    if not cachedWeapon then return nil end

    if timeNow - cachedWeapon.timestamp > BotInventory.wInfoCacheTime then
        BotInventory.wInfoCache[wep] = nil
        return nil
    end

    return cachedWeapon
end

---Returns the WeaponInfo table of the given entity
---@param wep Weapon
---@return WeaponInfo
function BotInventory:GetWeaponInfo(wep)
    if not (wep and IsValid(wep)) then
        ErrorNoHaltWithStack("Invalid weapon object passed to GetWeaponInfo")
        error("Invalid weapon object passed to GetWeaponInfo")
    end

    local cache = cacheValidate(wep)
    if cache then return cache end

    local info = {
        __tostring = function(obj) return BotInventory:GetWepInfoText(obj) end
    }
    -- Class of the weapon
    info.class = wep:GetClass()
    -- Ammo in the clip
    info.clip = wep:Clip1()
    -- Max ammo in the clip
    info.max_ammo = wep:GetMaxClip1()
    -- Ammo in the inventory
    info.ammo = self.bot:GetAmmoCount(wep:GetPrimaryAmmoType())
    -- Ammo type of the weapon
    info.ammo_type = wep:GetPrimaryAmmoType()
    -- The string version of the ammo type
    info.ammo_type_string = ammoTypes[info.ammo_type] and ammoTypes[info.ammo_type].name or "unknown"
    -- Slot of the weapon, functionally just a string version of the Kind
    info.slot = self.kindHash[wep.Kind] or "unknown"
    -- Hold type of the weapon
    info.hold_type = wep:GetHoldType()
    -- If the weapon is a gun
    info.is_gun = info.max_ammo > 0
    -- If the bot needs to reload this weapon (urgent)
    info.needs_reload = info.clip == 0
    -- If the bot should reload this weapon (non-urgent)
    info.should_reload = info.clip < info.max_ammo
    -- If the bot has bullets for this weapon
    info.has_bullets = info.ammo > 0
    -- Name of the weapon
    info.print_name = wep:GetPrintName()

    --[[
        info.kind:
        | WEAPON_PISTOL: small arms like the pistol and the deagle.
        | WEAPON_HEAVY: rifles, shotguns, machineguns.
        | WEAPON_NADE: grenades.
        | WEAPON_EQUIP1: special equipment, typically bought with credits and Traitor/Detective-only.
        | WEAPON_EQUIP2: same as above, secondary equipment slot. Players can carry one of each.
        | WEAPON_ROLE: special equipment that is default equipment for a role, like the DNA Scanner.
        | WEAPON_MELEE: only for the crowbar players get by default.
        | WEAPON_CARRY: only for the Magneto-stick, default equipment.
    ]]
    info.kind = wep.Kind -- Kind of the weapon
    --[[
        info.ammo_ent:
        | item_ammo_pistol_ttt: Pistol and M16 ammo.
        | item_ammo_smg1_ttt: SMG ammo, used by MAC10 and UMP.
        | item_ammo_revolver_ttt: Desert eagle ammo.
        | item_ammo_357_ttt: Sniper rifle ammo.
        | item_box_buckshot_ttt: Shotgun ammo.
    ]]
    info.ammo_ent = wep.AmmoEnt
    -- If the weapon is a traitor weapon
    info.is_traitor_weapon = table.HasValue(wep.CanBuy or {}, ROLE_TRAITOR)
    -- If the weapon is a detective weapon
    info.is_detective_weapon = table.HasValue(wep.CanBuy or {}, ROLE_DETECTIVE)
    -- If the weapon is silent
    info.silent = wep.IsSilent
    -- If we can drop it
    info.can_drop = wep.AllowDrop
    -- If it is a shotgun
    info.is_shotgun = string.find(info.ammo_type_string or "", "buckshot") ~= nil
    -- If it is melee
    info.is_melee = info.clip == -1
    -- If it only works at close range. These are held like guns (they have a clip) but have to be
    -- used like the crowbar, so both the inventory and the attack behavior treat them specially.
    info.is_short_range = TTTBots.Buyables.IsShortRangeWeapon(info.class)

    info.damage = wep.Primary and wep.Primary.Damage or 1
    local rps = wep.Primary and (1 / (wep.Primary.Delay or 1)) or 1
    info.rpm = math.ceil(rps * 60) or 1
    info.numshots = wep.Primary and wep.Primary.NumShots or 1
    info.dps = math.max(math.ceil(info.damage * info.numshots * rps), 1)
    info.time_to_kill = math.ceil((100 / info.dps) * 100) / 100

    info.is_automatic = (wep.Primary and wep.Primary.Automatic) or false
    -- we can infer if this is a sniper based off of the damage and if it's automatic
    info.is_sniper = (info.damage and info.damage > 40 and not info.is_automatic) or false

    info.timestamp = CurTime()

    -- Place this wep/info into the cache.
    BotInventory.wInfoCache[wep] = info

    return info
end

function BotInventory:GetAllWeaponInfo()
    local weapons = self.bot:GetWeapons()
    local weapon_info = {}
    for _, wep in pairs(weapons) do
        local info = self:GetWeaponInfo(wep)
        table.insert(weapon_info, info)
    end
    return weapon_info
end

--- How far away somebody has to be for a bot to draw its special weapon, and how much better a swap has to
--- be to be worth interrupting a fight for. The draw range is deliberately longer than any fight range:
--- the weapon should already be out when the shooting starts.
local SPECIAL_DRAW_RANGE = 1200
local SWAP_UPGRADE_MULT = 1.25

--- Is somebody around worth having the special weapon out for?
---
--- Answered from the bot's memory rather than by tracing line of sight: the memory already tracks who this
--- bot is aware of - seen, heard or inferred, with its own forget rules - and this only has to answer "am
--- I expecting trouble", not "can I shoot somebody right now".
---@return boolean
function BotInventory:EnemyInDrawRange()
    local target = self.bot.attackTarget
    if IsValid(target) and lib.IsPlayerAlive(target) then return true end

    local memory = self.bot:BotMemory()
    if not memory then return false end

    local myPos = self.bot:GetPos()

    for _, other in ipairs(memory:GetKnownAlivePlayers()) do
        if other == self.bot then continue end
        if TTTBots.Roles.IsAllies(self.bot, other) then continue end

        local knownPos = memory:GetKnownPositionFor(other)
        if knownPos and myPos:Distance(knownPos) <= SPECIAL_DRAW_RANGE then return true end
    end

    return false
end

--- True if a special weapon is worth having in hand right now.
---
--- Bots keep a real gun out until a target is inside a short range weapon's reach, because the flame does
--- not reach any further, but they never put it away and stand there empty handed either.
---
--- Every other special is a shop weapon, and a shop weapon is a giveaway: walking the map with a traitor
--- exclusive in hand announces what you are to anybody who sees it, and the role weapons (the Arsonist's
--- thrower, the Shanker's knife) are read as a KOS tell by the other bots. A player walks with their pistol
--- out and draws when they see somebody, so that is the rule here - hold it while there is somebody to use
--- it on, put it away when the map is clear.
---
--- The fallback matters in both cases: a bot whose only loaded gun *is* the special keeps holding it, so a
--- role that spawns with one is never left empty handed.
---@param special WeaponInfo?
---@return boolean
function BotInventory:ShouldHoldSpecial(special)
    if not special then return false end

    if special.is_short_range then
        local target = self.bot.attackTarget
        if IsValid(target) and self.bot:GetPos():Distance(target:GetPos()) <= TTTBots.Buyables.SHORT_RANGE_HOLD then
            return true
        end
    elseif self:EnemyInDrawRange() then
        return true
    end

    -- Nothing to use it on. Prefer a gun, unless there is nothing else with ammo to hold instead.
    local _, primary = self:GetPrimary()
    local _, secondary = self:GetSecondary()

    return not (wepInfoHasAmmo(primary) or wepInfoHasAmmo(secondary))
end

--- The best special primary the bot is carrying.
---
--- Several of them can share the equipment slot - the AK, the Silenced M4A1, the AWP, the Gauss Rifle
--- and the defibrillator all live there - so a bot that bought two weapons can own both at once.
--- Returning whichever one pairs() reached first would leave the bot holding an empty rifle while a
--- loaded one sat unused in its inventory, and the auto manager would fall straight through to the
--- pistol instead. So prefer what can actually shoot, and among those the hardest hitting.
---@return Weapon?
function BotInventory:GetSpecialPrimary()
    local specialClasses = TTTBots.Buyables.PrimaryWeapons
    local best, bestDps, fallback, fallbackDps = nil, nil, nil, nil

    for class, _ in pairs(specialClasses) do
        local wep = self.bot:GetWeapon(class)
        if not IsValid(wep) then continue end

        local info = self:GetWeaponInfo(wep)
        local dps = info.dps or 0

        if wepInfoHasAmmo(info) then
            if not best or dps > bestDps then
                best, bestDps = wep, dps
            end
        elseif not fallback or dps > fallbackDps then
            -- Nothing loaded: keep the best of them so the callers that test for ammo themselves
            -- (HasNoWeaponAvailable, the auto manager) still see a weapon rather than nothing.
            fallback, fallbackDps = wep, dps
        end
    end

    return best or fallback
end

---Return true if the bot has a valid WeaponInfo wep and it has > 0 bullets in the clip. Tests for nil.
---@param wepInfo WeaponInfo?
---@return boolean
function BotInventory:WepInfoHasClip(wepInfo)
    return (wepInfo and wepInfo.has_bullets and wepInfo.clip > 0) or false
end

function BotInventory:WepHasClip(wep)
    return (wep and IsValid(wep) and wep:Clip1() > 0) or false
end

---Get if the bots has no other weapons besides melee (false) or not (true)
---@param attackMode boolean Set to true if you want to check the weapons have ammo in reserve, not just in the clip
---@return boolean
function BotInventory:HasNoWeaponAvailable(attackMode)
    local toCheck = {
        self:GetSpecialPrimary(),
        self:GetPrimary(),
        self:GetSecondary()
    }

    for i, v in pairs(toCheck) do
        if not IsValid(v) then continue end
        local wInfo = self:GetWeaponInfo(v)
        local hasReserve = wInfo.has_bullets
        local hasAmmo = wInfo.clip > 0

        if attackMode then
            if hasReserve and hasAmmo then return false end
        else
            if hasReserve then return false end
        end
    end

    return true
end

---Equip the debug_forceweapon convar class if it is set. Returns true if it is set and we equipped it, false if not.
---@return boolean
function BotInventory:ManageDebugWeapon()

    local forcedClass = lib.GetConVarString('debug_forceweapon')
    if forcedClass ~= "" then
        if not self.bot:HasWeapon(forcedClass) then
            self.bot:Give(forcedClass)
        end
        self.bot:SelectWeapon(forcedClass)

        local held = self:GetHeldWeaponInfo()
        if not held then return true end
        if not held.needs_reload then return true end

        local loco = self.bot:BotLocomotor()

        if not loco then return true end
        loco:Reload()

        return true
    end

    return false
end

--- Would pulling out a different weapon right now cost us the fight?
---
--- Switching weapons is not free: the engine deploys the new one, and a weapon that is being deployed
--- cannot fire until that animation is done. A bot that swaps guns mid-fight therefore spends the best
--- part of a second unable to shoot at someone who is shooting back - which is what a bot pulling out
--- its traitor weapon in the middle of a firefight looks like from the outside. A player would keep
--- firing and swap afterwards, so wait for the fight to end, or for what we are holding to run dry.
---@return boolean hold
function BotInventory:ShouldHoldCurrentWeapon()
    local held = self:GetHeldWeaponInfo()
    if not (held and held.is_gun) then return false end
    if held.clip <= 0 and held.ammo <= 0 then return false end -- nothing left to shoot with

    local target = self.bot.attackTarget
    if not (IsValid(target) and lib.IsPlayerAlive(target)) then return false end
    if not lib.CanShoot(self.bot, target) then return false end

    -- ... unless this is the moment to draw the special we holstered, because a weapon that is a real
    -- upgrade is worth the deploy animation. Deferring every swap meant a bot that put its special away (see
    -- ShouldHoldSpecial) was never allowed to take it back out again: by the time it had a target it was
    -- "mid-fight", so it fought the whole round - and the whole shootout - with its pistol. Drawing a
    -- clearly better weapon is what a player does; shuffling between two comparable ones is what this waits
    -- on, and that is what the multiplier decides.
    local special = self:GetSpecialPrimary()
    if IsValid(special) then
        local specialInfo = self:GetWeaponInfo(special)
        if wepInfoHasAmmo(specialInfo) and (specialInfo.dps or 0) > ((held.dps or 0) * SWAP_UPGRADE_MULT) then
            return false
        end
    end

    return true
end

--- Manage our own inventory by selecting the best weapon, queueing a reload if necessary, etc.
function BotInventory:AutoManageInventory()
    local SLOWDOWN = math.max(math.floor(TTTBots.Tickrate / 2), 1) -- about twice per second
    if self.tick % SLOWDOWN ~= 0 or self.disabled then return end

    if self:ManageDebugWeapon() then return end

    local w_special = self:GetSpecialPrimary()
    local special = w_special and self:GetWeaponInfo(w_special) or nil
    local w_primary, primary = self:GetPrimary()
    local w_secondary, secondary = self:GetSecondary()

    -- A short range special is only worth holding once the fight is close. Taking it out of the
    -- running here lets the priority list below fall through to a real gun.
    if not self:ShouldHoldSpecial(special) then
        w_special, special = nil, nil
    end

    -- Armed and mid-fight: leave the weapon in our hands alone.
    local holdCurrent = self:ShouldHoldCurrentWeapon()
    local activeWeapon = self.bot:GetActiveWeapon()

    -- Ordered by priority: special > primary > secondary
    local options = {
        { func = self.EquipSpecial, info = special, wep = w_special },
        { func = self.EquipPrimary, info = primary, wep = w_primary },
        { func = self.EquipSecondary, info = secondary, wep = w_secondary },
    }

    local foundGun = false
    for _, option in ipairs(options) do
        local wepInfo = option.info
        if wepInfo and (wepInfo.ammo > 0 or wepInfo.clip > 0) then
            -- Still counted as a usable gun even when we are holding off on the switch, so that the
            -- melee fallback below does not mistake this for having nothing to shoot with.
            if not holdCurrent or option.wep == activeWeapon then
                option.func(self)
            end
            foundGun = true
            break
        end
    end

    if not foundGun and self:HasNoWeaponAvailable(false) then
        self:EquipMelee()
    end

    local current = self:GetHeldWeaponInfo()
    if not (current and current.is_gun) then return end

    local locomotor = self.bot:BotLocomotor()
    if current.needs_reload then
        locomotor:StopAttack()
        locomotor:Reload()
    end
end

--- Reload the currently held weapon if it has less ammo in the 1st clip than its maximum, if it also has ammo in reserve.
---@return boolean reloading If we are reloading
function BotInventory:ReloadIfNecessary()
    local heldWep = self:GetHeldWeaponInfo(self.bot)
    if not (heldWep and heldWep.is_gun) then return false end

    local reload = heldWep.should_reload

    if reload then
        local loco = self.bot:BotLocomotor() ---@type CLocomotor
        loco:StopAttack()
        loco:StopAttack2()
        loco:Reload()
    end

    return reload
end

--- Gives the bot weapon_ttt_c4 if he doesn't have it already.
function BotInventory:GiveC4()
    local hasC4 = false
    local weapons = self.bot:GetWeapons()
    for _, wep in pairs(weapons) do
        if wep:GetClass() == "weapon_ttt_c4" then
            hasC4 = true
            break
        end
    end

    if not hasC4 then
        self.bot:Give("weapon_ttt_c4")
    end
end

function BotInventory:PauseAutoSwitch()
    self.pauseAutoSwitch = true
end

function BotInventory:ResumeAutoSwitch()
    self.pauseAutoSwitch = false
end

--- Hold the one weapon this role fights with, for a role that has restricted itself to one.
---
--- RoleData declares both halves of this (SetAutoSwitch and SetPreferredWeapon) and nothing used to read
--- them, so a role could turn the automatic swapping off and name the weapon to keep in hand while the
--- bot went on swapping guns regardless. That quietly made the roles it exists for harmless: the Roider's
--- own addon zeroes every point of damage it deals with anything other than the crowbar, so a bot that
--- picks its pistol back up cannot hurt anybody.
---
--- Returning false hands the bot back to the normal management, which is what we want the moment the
--- preferred weapon is not in the inventory - a weapon can be stripped mid-round, and refusing to touch
--- the inventory at all would leave the bot standing there empty-handed.
---@return boolean handled
function BotInventory:HandlePreferredWeapon()
    local roleData = TTTBots.Roles.GetRoleFor(self.bot)
    if roleData:GetAutoSwitch() then return false end

    local preferred = roleData:GetPreferredWeapon()
    if not preferred then return false end

    if not self.bot:HasWeapon(preferred) then return false end

    self:SelectIfNotHeld(preferred)

    return true
end

function BotInventory:Think()
    if not lib.IsPlayerAlive(self.bot) then return end
    if lib.GetDebugFor("inventory") then
        self:PrintInventory()
    end
    self.tick = self.tick + 1

    if not IsValid(self.bot.attackTarget) then
        self:ReloadIfNecessary()
    end

    -- Manage our own inventory, but only if we have not been paused
    if self.pauseAutoSwitch then return end
    -- ... or if the role only ever fights with one weapon, which it must keep in hand.
    if self:HandlePreferredWeapon() then return end
    self:AutoManageInventory()
end

--- Return the jackal gun (weapon_ttt2_sidekickdeagle) if it has >0 shots. If not, then return nil.
---@return WeaponInfo?
function BotInventory:GetJackalGun()
    local hasWeapon = self.bot:HasWeapon("weapon_ttt2_sidekickdeagle")
    if not hasWeapon then return end
    local wep = self.bot:GetWeapon("weapon_ttt2_sidekickdeagle")
    if not IsValid(wep) then return end

    return wep:Clip1() > 0 and wep or nil
end

--- Return the sheriff gun (weapon_ttt2_deputydeagle) if it has >0 shots. If not, then return mil.
---@return WeaponInfo?
function BotInventory:GetSheriffGun()
    local hasWeapon = self.bot:HasWeapon("weapon_ttt2_deputydeagle")
    if not hasWeapon then return end
    local wep = self.bot:GetWeapon("weapon_ttt2_deputydeagle")
    if not IsValid(wep) then return end

    return wep:Clip1() > 0 and wep or nil
end
--- Equip the Jackal's Sidekick Deagle if we have it. Returns true if we equipped it, false if we didn't.
--- Doesn't error if we don't have it.
---@return boolean
function BotInventory:EquipJackalGun()
    local gun = self:GetJackalGun()
    if not gun then return false end
    self.bot:SetActiveWeapon(gun)
    return true
end

--- Equip the Sheriff's Deputy Deagle if we have it. Returns true if we equipped it, false if we didn't.
--- Doesn't error if we don't have it.
---@return boolean
function BotInventory:EquipSheriffGun()
    local gun = self:GetSheriffGun()
    if not gun then return false end
    self.bot:SetActiveWeapon(gun)
    return true
end
---Returns the weapon info table for the weapon we are holding, or what the target is holding if any.
---@param target Player|nil
---@return WeaponInfo?
function BotInventory:GetHeldWeaponInfo(target)
    if not target then
        local wep = self.bot:GetActiveWeapon()

        if not (wep and IsValid(wep)) then return nil end

        return self:GetWeaponInfo(wep)
    end

    local wep = target:GetActiveWeapon()
    if not IsValid(wep) then return nil end
    return self:GetWeaponInfo(wep)
end

---@return Weapon?, WeaponInfo?
function BotInventory:GetPrimary()
    return self:GetBySlot("primary")
end

---@return Weapon?, WeaponInfo?
function BotInventory:GetSecondary()
    return self:GetBySlot("secondary")
end

---@return Weapon?, WeaponInfo?
function BotInventory:GetCrowbar()
    return self:GetBySlot("melee")
end

---@return Weapon?, WeaponInfo?
function BotInventory:GetGrenade()
    return self:GetBySlot("grenade")
end

--- Return the first weapon of slot 'slot'. Also returns weaponinfo if it exists.
---@param slot string
---@return Weapon?, WeaponInfo?
function BotInventory:GetBySlot(slot)
    local weapons = self.bot:GetWeapons()
    for _, wep in pairs(weapons) do
        local info = self:GetWeaponInfo(wep)
        if info.slot == slot then
            return wep, info
        end
    end

    return nil
end

function BotInventory:HasPrimary()
    return self:GetByKindRaw(BotInventory.kindHash.primary) ~= nil
end

function BotInventory:HasSecondary()
    return self:GetByKindRaw(BotInventory.kindHash.secondary) ~= nil
end

---Returns the first Weapon in the bots weapons list of int "kind"
---Does NOT get the weapon info
---@param kind integer The kind number of the weapon
---@return Weapon?
function BotInventory:GetByKindRaw(kind)
    local weapons = self.bot:GetWeapons()
    for _,wep in pairs(weapons) do
        if not wep then continue end
        if wep.Kind == kind then
            return wep
        end
    end
end

---@return WeaponInfo?
function BotInventory:GetWeaponByName(name)
    local weapons = self.bot:GetWeapons()
    for _, wep in pairs(weapons) do
        local info = self:GetWeaponInfo(wep)
        if info.print_name == name then
            return info
        end
    end

    return nil
end

--- Gets the debug/stylized text for the given weapon info. Used to check the ammo and weapon type.
---@param wepInfo any
---@return string str Formatted info string
function BotInventory:GetWepInfoText(wepInfo)
    if not wepInfo then return "nil" end
    local ammoLeft = wepInfo.clip or 0
    local ammoMax = wepInfo.max_ammo or 0
    local heldAmmo = wepInfo.ammo or 0
    local wepText = string.format("%s (%d/%d) [%d left]", wepInfo.print_name, ammoLeft, ammoMax, heldAmmo)

    return wepText
end

--- Puts a weapon in the bot's hands, unless it is already there.
---
--- Re-selecting the weapon the bot is already holding makes the engine deploy it a second time, and a
--- weapon that is mid-deploy cannot fire for the length of that animation. The auto manager runs twice a
--- second, so without this check every bot was re-deploying whatever it was holding all round long.
---@param wep Weapon|string Weapon object or class name.
---@return boolean equipped
function BotInventory:SelectIfNotHeld(wep)
    local class = type(wep) == "string" and wep or (IsValid(wep) and wep:GetClass())
    if not class then return false end

    local active = self.bot:GetActiveWeapon()
    if IsValid(active) and active:GetClass() == class then return true end -- already in hand

    self.bot:SelectWeapon(class)

    return true
end

--- Equips the wep in the bot's hands. wep can be a string or a weapon object. If it is a string then it has the following opts:
--- 1. "primary": equips the bot's primary weapon
--- 2. "secondary": equips the bot's secondary weapon
--- 3. "melee": equips the bot's melee weapon
--- 4. "grenade": equips the bot's grenade
--- 5. "weapon_name": equips the bot's weapon with the given name
---<p>Otherwise, wep is a weapon object and it is equipped.</p>
function BotInventory:Equip(wep)
    local found
    if type(wep) == "string" then
        local funcTbl = {
            primary = self.GetPrimary,
            secondary = self.GetSecondary,
            melee = self.GetCrowbar,
            grenade = self.GetGrenade,
        }
        if funcTbl[wep] then
            found = funcTbl[wep](self)
        else
            found = self:GetWeaponByName(wep)
        end
    else
        found = wep
    end

    if found then
        -- GetWeaponByName returns a WeaponInfo, everything else returns a Weapon.
        self:SelectIfNotHeld(type(found) == "table" and found.class or found)
    end

    return (found ~= nil)
end

function BotInventory:EquipSpecial()
    local firstSpecial = self:GetSpecialPrimary()
    if not (firstSpecial and IsValid(firstSpecial)) then return false end

    return self:SelectIfNotHeld(firstSpecial)
end

function BotInventory:EquipPrimary()
    return self:Equip("primary")
end

function BotInventory:EquipSecondary()
    return self:Equip("secondary")
end

function BotInventory:EquipMelee()
    -- Equip whatever is actually in our melee slot first. The original implementation hard-coded the
    -- crowbar, which left a melee-only role that does not carry one without a weapon in hand - and
    -- the Attack behaviour bails out early whenever GetHeldWeaponInfo() returns nil, so such a role
    -- could never attack at all. The Shinigami (weapon_ttt_shinigamiknife) is exactly that case.
    -- The crowbar stays as a fallback so every normal role behaves as before.
    return self:Equip("melee") or self:SelectIfNotHeld("weapon_zm_improvised")
end

function BotInventory:EquipGrenade()
    return self:Equip("grenade")
end

function BotInventory:GetInventoryString()
    local weapons = self.bot:GetWeapons()
    local str = ""
    for _, wep in pairs(weapons) do
        local info = self:GetWeaponInfo(wep)
        local slot = info.slot
        local name = info.print_name
        local dps = info.dps
        local ttk = info.time_to_kill
        local clip = info.clip or 0
        local max = info.max_ammo or 0
        local total = info.ammo --- how much ammo in inv
        local needsReload = info.needs_reload

        local shotstring = info.is_shotgun and "(shotgun)" or ""

        -- example "\nPrimary weapon_name (DPS: 100; TTK: 2.5s) [8/10 shots, of %d]"
        str = str ..
            string.format("\n%s %s %s (DPS: %s; TTK: %ss) [%d/%d shots, of %d]. {NeedsReload=%s, ammo_type_string=%s}",
                slot, shotstring, name, dps, ttk, clip, max, total, needsReload, info.ammo_type_string)
    end
    return str
end

local function printf(str, ...)
    print(string.format(str, ...))
end

function BotInventory:PrintInventory()
    printf("===III=== Inventory for bot %s ===III===", self.bot:Nick())
    printf(self:GetInventoryString())
    printf("===III=== End inventory ===III===")
end

---@class Player
local plyMeta = FindMetaTable("Player")

---@return CInventory?
function plyMeta:BotInventory()
    ---@cast self Bot
    -- Nil unless this is a fully initialized bot; see plyMeta:BotMorality.
    return self.components and self.components.inventory
end
