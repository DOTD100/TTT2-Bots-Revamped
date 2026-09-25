TTTBots.Buyables = {}
TTTBots.Buyables.m_buyables = {}
TTTBots.Buyables.m_buyables_role = {}
local buyables = TTTBots.Buyables.m_buyables
local buyables_role = TTTBots.Buyables.m_buyables_role

---@class Buyable
---@field Name string - The pretty name of this item.
---@field Class string - The class of this item.
---@field Price number - The price of this item, in credits. Bots are given the same starting credits a player of their role gets - see TTTBots.Buyables.GetCreditAllowanceFor.
---@field Priority number - The priority of this item. Higher numbers = higher priority. Bots work down the list and buy everything they can afford, so an item with a lower priority is only reached once the better ones are paid for or skipped.
---@field OnBuy function? - Called when the bot successfully buys this item.
---@field CanBuy function? - Return false to prevent a bot from buying this item.
---@field Roles table<string> - A table of roles that can buy this item.
---@field Teams table<string>? - A table of teams that can buy this item. This is what lets a custom role inherit the base team's shop without being named in every entry: a traitor subrole can buy C4 because traitors can, not because somebody remembered to add it to the list.
---@field RandomChance number? - An integer from 1 to math.huge. Functionally the item will be selected if random(1, RandomChoice) == 1.
---@field ShouldAnnounce boolean? - Should this create a chatter event?
---@field AnnounceTeam boolean? - Is announcing team-only?
---@field BuyFunc function? - A function called to "buy" the Class. By default, just calls function(ply) ply:Give(Class) end
---@field TTT2 boolean? - Is this TTT2 specific?
---@field PrimaryWeapon boolean? - Should the bot use this over whatever other primaries they have? (affects autoswitch)
---@field Group string? - Optional, and rarely needed. Buyables that share a group compete for the same slot on the bot: only one of them is bought per round, picked at random from the ones that are affordable and available.
---@field Tier string? - "base" means the item is bought like any other shop item, in priority order, and can be bought alongside anything else. Anything else is a "custom" entry, which is the default for everything registered outside the base shop file, and a bot only ever buys one custom entry per round, picked at random from the ones it can afford. Set Tier = "base" on a custom entry to keep it out of that draw.
---@field ShortRange boolean? - Does this weapon only work at knife-to-knife range? Bots will only hold it while a fight is close, and will walk into range with it, instead of firing it from gun range.

--- A table of weapons that are preferred over primary weapons (PrimaryWeapon == true). Indexed by the weapon's classname.
---@type table<string, boolean>
TTTBots.Buyables.PrimaryWeapons = {}

--- The tier of the base game's shop: bought in priority order, as many as the credits allow.
TTTBots.Buyables.BASE_TIER = "base"
--- The tier of everything else. A bot buys at most one custom entry per round, at random.
TTTBots.Buyables.CUSTOM_TIER = "custom"
--- The group all custom buyables share unless they name a group of their own, which is what makes the custom
--- shop one draw.
TTTBots.Buyables.CUSTOM_GROUP = "custom"

--- Which tier buyables registered right now belong to. Only the base shop file changes this, at the bottom
--- of this file; anything registered outside it is custom, including role files and other addons' items.
---@type string
TTTBots.Buyables.m_registeringTier = TTTBots.Buyables.CUSTOM_TIER

--- The group a buyable competes in, or nil when it does not compete with anything.
---
--- This is what makes the custom shop varied without any bookkeeping from whoever adds an item: a lone
--- custom weapon would otherwise be bought alongside a whole pack of others, and the pack would be bought in
--- priority order, which is how "any new rifle" turns into "every bot carries the same one". Everything
--- outside the base shop shares the custom group, so one of those items is bought per round, at random.
---@param buyable Buyable
---@return string?
function TTTBots.Buyables.GetGroup(buyable)
    if buyable.Group then return buyable.Group end
    if buyable.Tier == TTTBots.Buyables.BASE_TIER then return nil end

    return TTTBots.Buyables.CUSTOM_GROUP
end

--- Weapons that stop working past spitting distance (the Arson Thrower). Bots treat these as melee
--- weapons for the purpose of closing the gap, and only keep one out while a target is actually
--- inside its range - otherwise they stand at rifle range squirting fire at nothing.
---@type table<string, boolean>
TTTBots.Buyables.ShortRangeWeapons = {}

--- How close a target has to be before a ShortRange weapon is worth holding in the first place.
TTTBots.Buyables.SHORT_RANGE_HOLD = 350

--- Is this weapon class one that only works up close?
---@param class string
---@return boolean
function TTTBots.Buyables.IsShortRangeWeapon(class)
    if not class then return false end

    return TTTBots.Buyables.ShortRangeWeapons[class] == true
end

--- Return a buyable item by its name.
---@param name string - The name of the buyable item.
---@return Buyable|nil - The buyable item, or nil if it does not exist.
function TTTBots.Buyables.GetBuyable(name) return buyables[name] end

---Return a list of buyables for the given rolestring. Defaults to an empty table.
---The result is ALWAYS sorted by priority, descending.
---@param roleString string
---@return table<Buyable>
function TTTBots.Buyables.GetBuyablesFor(roleString) return buyables_role[roleString] or {} end

---Adds the given Buyable data to the roleString. This is called automatically when registering a Buyable, but exists for sanity.
---@param buyable Buyable
---@param roleString string
function TTTBots.Buyables.AddBuyableToRole(buyable, roleString)
    buyables_role[roleString] = buyables_role[roleString] or {}
    table.insert(buyables_role[roleString], buyable)
    table.sort(buyables_role[roleString], function(a, b) return a.Priority > b.Priority end)
end

--- The role whose shop this role borrows, by name, or nil when it shops for itself.
---
--- TTT2 lets a role point its shop at another role with ttt_<abbr>_shop_fallback, and the shop a player
--- sees is then that role's list. Reading the same setting is what lets a role the gamemode treats as a
--- traitor shopper - the Revolutionary, an innocent with the traitor shop - buy what traitors buy,
--- without this file knowing anything about it.
---@param bot Bot
---@return string? roleString
function TTTBots.Buyables.GetBorrowedShopRole(bot)
    if not TTTBots.Lib.IsTTT2() then return nil end
    if not (bot.GetSubRoleData and GetGlobalString) then return nil end

    local roleData = bot:GetSubRoleData()
    if not (roleData and roleData.abbr) then return nil end

    -- SHOP_DISABLED is "no shop at all", SHOP_UNSET is "keep the role's own", and a role name is
    -- "borrow that role's".
    local fallback = GetGlobalString("ttt_" .. roleData.abbr .. "_shop_fallback")
    if not fallback then return nil end
    if fallback == SHOP_DISABLED or fallback == SHOP_UNSET then return nil end
    if fallback == bot:GetRoleStringRaw() then return nil end -- pointed at itself, so it is its own

    return fallback
end

---Every buyable this bot can pick from: the ones listed for its role, plus the ones listed for its team.
---Role entries are collected first so they win ties on priority. Deduplicated by class, so an item
---listed for both the role and the team is only ever considered once.
---@param bot Bot
---@return table<Buyable>
function TTTBots.Buyables.GetBuyablesForBot(bot)
    local options = {}
    local seen = {}

    local function add(list)
        for _, buyable in ipairs(list) do
            local key = buyable.Class or buyable.Name
            if seen[key] then continue end

            seen[key] = true
            table.insert(options, buyable)
        end
    end

    add(TTTBots.Buyables.GetBuyablesFor(bot:GetRoleStringRaw()))
    add(TTTBots.Buyables.GetBuyablesFor(bot:GetTeam()))

    -- A role can borrow another role's shop, so buy what that role buys.
    local borrowed = TTTBots.Buyables.GetBorrowedShopRole(bot)
    if borrowed then add(TTTBots.Buyables.GetBuyablesFor(borrowed)) end

    -- Shuffle before sorting so equally prioritised items land in a different order for every bot. The
    -- sort is unstable, and the list it is given is always built the same way, so without this every bot
    -- on the server would resolve a tie identically - which is how five differently priced rifles of the
    -- same priority ended up as "everybody buys the AK" rather than a mixed-up shop.
    for i = #options, 2, -1 do
        local j = math.random(i)
        options[i], options[j] = options[j], options[i]
    end

    table.sort(options, function(a, b) return a.Priority > b.Priority end)

    return options
end

--- Starting credits to assume when the gamemode names none. Matches TTT1's and TTT2's default grant.
TTTBots.Buyables.DEFAULT_CREDITS = 2

--- How many credits this bot may spend this round.
---
--- This used to be a hard-coded 2, which ignored the server entirely. What a player is given is a per-role
--- convar in TTT2 (ttt_traitor_credits_starting, ttt_det_credits_starting, ...) rather than TTT1's single
--- ttt_credits_starting, so read the same value the gamemode itself hands out - including the
--- TTT2ModifyDefaultTraitorCredits hook, which is how other addons adjust the traitor grant.
---@param bot Bot
---@return number allowance
function TTTBots.Buyables.GetCreditAllowanceFor(bot)
    local cvarName

    if TTTBots.Lib.IsTTT2() and bot.GetSubRoleData then
        local roleData = bot:GetSubRoleData()
        if roleData and roleData.abbr then
            cvarName = "ttt_" .. roleData.abbr .. "_credits_starting"
        end
    end

    -- TTT1's single cvar, and the fallback for any role TTT2 did not name.
    local cvar = (cvarName and GetConVar(cvarName)) or GetConVar("ttt_credits_starting")
    if not cvar then return TTTBots.Buyables.DEFAULT_CREDITS end

    -- GetFloat and ceil, exactly as TTT2's own grant routine reads it.
    local credits = math.ceil(cvar:GetFloat())

    if bot:GetTeam() == TEAM_TRAITOR then
        credits = hook.Run("TTT2ModifyDefaultTraitorCredits", bot, credits) or credits
    end

    return math.max(credits, 0)
end

--- Is this bot's shop a bluff rather than a way to arm itself?
---
--- TTT2's Spy is the case this exists for: it shops from the traitor list, but ordering something is
--- refused - nothing is handed over - and the traitors are told an item was bought, so it looks like it
--- is shopping alongside them. The gamemode decides whether that bluff is on with a convar, which the
--- role data names for us.
---@param bot Bot
---@return boolean bluff
function TTTBots.Buyables.FakesShopOrders(bot)
    local cvarName = TTTBots.Roles.GetRoleFor(bot):GetFakeShopConvar()
    if not cvarName then return false end

    local cvar = GetConVar(cvarName)

    -- Only when the gamemode explicitly says so. If the convar is missing then the gamemode's own hook is
    -- not faking anything either, and a player ordering the item would receive it - so do not fake where
    -- a player could not, and do fake where they could.
    return (cvar ~= nil) and cvar:GetBool()
end

--- Tell the traitors that this bot bought something, without handing anything over.
---
--- This is the notification TTT2's Spy sends from its TTTCanOrderEquipment hook: the equipment buyers'
--- notification addon listens for it, the Spy only sends it when that addon is installed, and it only goes
--- to traitors whose own team is not hidden from them.
---@param bot Bot
---@param buyable Buyable
function TTTBots.Buyables.AnnounceFakePurchase(bot, buyable)
    if not buyable.Class then return end
    -- Only if the notifying addon registered the message: sending an unregistered one would error.
    if util.NetworkStringToID("TEBN_ItemBought") == 0 then return end

    local traitors = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply:IsActive() and ply:IsTraitor() and not ply:GetSubRoleData().unknownTeam then
            traitors[#traitors + 1] = ply
        end
    end

    if #traitors == 0 then return end

    -- Field for field what TTT2's Spy sends, because the receiver decodes this order and looks the class
    -- up with weapons.GetStored when it is not an item, which is what gives the notification its name.
    net.Start("TEBN_ItemBought")
    net.WriteEntity(bot)
    net.WriteString(buyable.Class)
    net.WriteBool(items and items.IsItem(buyable.Class) or false)
    net.Send(traitors)
end

--- One entry from a group, chosen at random, or nil when nothing in the group can be bought this round.
---
--- Buyables that share a slot on the bot cannot all be bought, so a group has to be resolved to a single
--- purchase. Taking whichever one the priority sort happened to put first meant every bot bought the same
--- item no matter how many were on offer - which is how a pack of five different rifles turned into "every
--- traitor carries the AK". Picking uniformly is what makes a shop varied.
---
--- The same availability rules the purchase loop applies are applied here, so a candidate cannot be picked
--- and then fail anyway: the class has to exist, the price has to fit what is left of the allowance, CanBuy
--- has to allow it, and RandomChance still works as "considered this round" - so an item can stay rare
--- inside its group.
---@param options table<Buyable> Every buyable this bot may choose from, in priority order.
---@param group string
---@param bot Bot
---@param creditAllowance number What the bot can still afford.
---@return Buyable?
function TTTBots.Buyables.PickFromGroup(options, group, bot, creditAllowance)
    local candidates = {}

    for _, option in ipairs(options) do
        if TTTBots.Buyables.GetGroup(option) ~= group then continue end
        if option.TTT2 and not TTTBots.Lib.IsTTT2() then continue end
        if option.Price > creditAllowance then continue end
        if option.Class and not TTTBots.Lib.WepClassExists(option.Class) then continue end
        if option.CanBuy and not option.CanBuy(bot) then continue end
        if option.RandomChance and math.random(1, option.RandomChance) ~= 1 then continue end

        candidates[#candidates + 1] = option
    end

    if #candidates == 0 then return nil end

    return candidates[math.random(#candidates)]
end

---Purchases any registered buyables for the given bot's role and team. Returns a table of Buyables that were successfully purchased.
---@param bot Bot
---@return table<Buyable>
function TTTBots.Buyables.PurchaseBuyablesFor(bot)
    local options = TTTBots.Buyables.GetBuyablesForBot(bot)
    local creditAllowance = TTTBots.Buyables.GetCreditAllowanceFor(bot)
    local purchased = {}
    local fakeOrders = TTTBots.Buyables.FakesShopOrders(bot)
    local filledGroups = {} -- Groups the bot has already spent on this round

    for i, option in pairs(options) do
        if option.TTT2 and not TTTBots.Lib.IsTTT2() then continue end                      -- for mod compat.
        if option.Class and not TTTBots.Lib.WepClassExists(option.Class) then
            -- Silently skipping here is why a role can appear to "never buy" an item.
            if TTTBots.Lib.GetDebugFor("misc") then
                print(string.format("[TTT Bots 2] Skipping buyable '%s': weapon class '%s' not found.",
                    tostring(option.Name), tostring(option.Class)))
            end
            continue
        end
        if option.Price > creditAllowance then continue end
        if option.CanBuy and not option.CanBuy(bot) then continue end
        if option.RandomChance and math.random(1, option.RandomChance) ~= 1 then continue end

        -- Anything that competes for the same slot as something else is resolved once per round, by a
        -- random pick from what the bot can afford - see GetGroup. For custom entries that group is
        -- implicit: the whole custom shop is one draw, so a weapon added to the expanded file joins it
        -- without the author declaring a group, a tier or anything else.
        local group = TTTBots.Buyables.GetGroup(option)
        if group then
            if filledGroups[group] then continue end

            local picked = TTTBots.Buyables.PickFromGroup(options, group, bot, creditAllowance)
            if not picked then continue end

            filledGroups[group] = true
            option = picked
        end

        creditAllowance = creditAllowance - option.Price
        table.insert(purchased, option)

        if fakeOrders then
            -- A bluff: the bot gets nothing, and the traitors are told it bought the item. No OnBuy
            -- either, since nothing was actually bought.
            TTTBots.Buyables.AnnounceFakePurchase(bot, option)
        else
            local buyfunc = option.BuyFunc or (function(ply) ply:Give(option.Class) end)
            buyfunc(bot)
            if option.OnBuy then option.OnBuy(bot) end
        end

        if option.ShouldAnnounce then
            local chatter = bot:BotChatter()
            if not chatter then continue end
            chatter:On("Buy" .. option.Name, {}, option.AnnounceTeam or false)
        end
    end

    return purchased
end

--- Register a buyable item. This is useful for modders wanting to add custom buyable items.
---@param data Buyable - The data of the buyable item.
---@return boolean - Whther or not the override was successful.
function TTTBots.Buyables.RegisterBuyable(data)
    if not (data and data.Name) then
        ErrorNoHaltWithStack("TTT Bots: attempted to register a buyable without a Name\n")
        return false
    end
    -- Which half of the shop this belongs to. The base game's items are registered while m_registeringTier
    -- says so (see the includes at the bottom); a role file or another addon's buyable gets the default,
    -- which is the custom tier, and therefore a place in the one-per-round custom draw.
    data.Tier = data.Tier or TTTBots.Buyables.m_registeringTier or TTTBots.Buyables.CUSTOM_TIER

    buyables[data.Name] = data

    for _, roleString in pairs(data.Roles or {}) do
        TTTBots.Buyables.AddBuyableToRole(data, roleString)
    end

    for _, teamString in pairs(data.Teams or {}) do
        TTTBots.Buyables.AddBuyableToRole(data, teamString)
    end

    if data.PrimaryWeapon then
        TTTBots.Buyables.PrimaryWeapons[data.Class] = true
    end

    if data.ShortRange then
        TTTBots.Buyables.ShortRangeWeapons[data.Class] = true
    end

    return true
end

-- hook for TTTBeginRound
hook.Add("TTTBeginRound", "TTTBots_Buyables", function()
    -- The two second delay can avoid a bunch of confusing errors. Don't ask why, I don't fucking know.
    timer.Simple(2,
        function()
            if not TTTBots.Match.IsRoundActive() then return end
            for _, bot in pairs(TTTBots.Bots) do
                if not TTTBots.Lib.IsPlayerAlive(bot) then continue end
                if bot == NULL then continue end
                TTTBots.Buyables.PurchaseBuyablesFor(bot)
            end
        end)
end)

-- Import default data. Anything registered while this says "base" is the base game's shop: bought in
-- priority order, as many as the bot can afford. It is the only file that gets that tier.
TTTBots.Buyables.m_registeringTier = TTTBots.Buyables.BASE_TIER
include("tttbots2/data/sv_default_buyables.lua")
TTTBots.Buyables.m_registeringTier = TTTBots.Buyables.CUSTOM_TIER

-- Import additional data. This is the file to add new purchases in, and it is deliberately kept
-- separate from the base game items above. Everything registered from here on - including the role files
-- and any other addon's buyables - is custom, so it takes part in the random custom pick described at
-- GetGroup. Adding an item is one entry and nothing else.
include("tttbots2/data/sv_buyables_expanded.lua")
