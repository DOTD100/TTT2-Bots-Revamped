TTTBots.Behaviors = {}

---@enum BStatus
TTTBots.STATUS = {
    RUNNING = 1,
    SUCCESS = 2,
    FAILURE = 3,
}

TTTBots.Lib.IncludeDirectory("tttbots2/behaviors")

---@alias Tree table<BBase|Tree>

TEAM_TRAITOR = TEAM_TRAITOR or "traitors"
TEAM_INNOCENT = TEAM_INNOCENT or "innocents"
TEAM_NONE = TEAM_NONE or "none"


local _bh = TTTBots.Behaviors

TTTBots.Behaviors.PriorityNodes = {
    --- Survive: what a bot does when it cannot fight at all.
    ---
    --- Every node in this table has to be inert for every bot it does not apply to, and this one is inert twice
    --- over: it only runs while the post-round deathmatch is on, and only for a role that cannot deal damage,
    --- cannot be damaged, or exists to be killed (`TTTBots.Roles.IsNonCombatant`). See behaviors/evade.lua.
    Survive = {
        _bh.Evade
    },
    --- Fight back vs the environment (blocking props) or other players.
    FightBack = {
        _bh.ClearBreakables,
        -- Before the attack node rather than after it. AttackTarget keeps a target it cannot see - the bot
        -- walks at the last known position and shoots when it can see them again - so a grenade node placed
        -- after it would never get a turn. What keeps the grenade out of gunfights is its own Validate: it
        -- refuses any target that is currently visible. See behaviors/throwgrenade.lua.
        _bh.ThrowGrenade,
        _bh.AttackTarget,
        -- After the attack node on purpose. Shooting a player comes first, and this one is a commitment
        -- rather than a reflex: the Pharaoh's Ankh has 500 health and a bot fires about once a second, so the
        -- node is interruptible and only runs while there is nobody to shoot. See behaviors/breakankh.lua.
        _bh.BreakAnkh
    },
    --- Restore values, like health, ammo, etc.
    --
    --- ...and, in practice, the place the "use the item I am carrying" nodes live: a soda can is a restore,
    --- a decoy can is a trap, and a mine is a trap. All of them are inert for a bot that is not holding one.
    Restore = {
        _bh.GetWeapons,
        _bh.UseHealthStation,
        -- A soda can is a restore too: health, armour or a combat buff, for the price of a walk.
        _bh.DrinkSoda,
        -- After it, not before: drinking a real can is what tells this one where a decoy belongs. Inert for
        -- any bot that is not carrying the fake soda. See behaviors/placefakesoda.lua.
        _bh.PlaceFakeSoda,
        -- Bought by both sides, so this one lives here rather than in the traitor tree.
        _bh.MineThrower,
        -- The Pharaoh's Ankh, all three of its verbs, and all three inert for every other role: placing it
        -- (the role's own loadout weapon), converting it (a Graverobber stealing it, or the Pharaoh taking his
        -- stolen one back) and picking it up to carry it somewhere better. They live in the shared groups
        -- rather than in a hand-written tree per role because both ankh roles are ordinary innocent/traitor
        -- roles in every other respect - the Graverobber is handed to a random traitor mid-round by the addon
        -- itself, not chosen at round start - so a custom tree would only be a copy of the default one with
        -- these nodes appended.
        _bh.PlaceAnkh,
        _bh.StealAnkh,
        _bh.MoveAnkh
    },
    --- Investigate corpses/noises.
    Investigate = {
        _bh.InvestigateCorpse,
        _bh.InvestigateNoise
    },
    --- Patrolling stuffs
    Patrol = {
        _bh.Follow,
        _bh.Wander
    },
    --- Minge around with others
    Minge = {
        _bh.MingeCrowbar,
    }
}

local _prior = TTTBots.Behaviors.PriorityNodes

--- Every tree starts with the same two groups in the same order: `Survive` first, so a role that cannot fight
--- never gets as far as the attack node, then `FightBack`. Everything after them is what makes each tree itself.
---@type table<string, Tree>
TTTBots.Behaviors.DefaultTrees = {
    innocent = {
        _prior.Survive,
        _prior.FightBack,
        _bh.Defuse,
        _prior.Restore,
        _bh.Interact,
        _prior.Investigate,
        _prior.Minge,
        _bh.Decrowd,
        _prior.Patrol
    },
    traitor = {
        _prior.Survive,
        _prior.FightBack,
        _bh.Defib,
        _bh.PlantBomb,
        -- A fake corpse to leave behind for whoever searches it: the same kind of set-up job as the bomb,
        -- and single use. Inert for anyone not carrying it. See behaviors/boombody.lua.
        _bh.BoomBody,
        -- The other single-use traitor item: this one is aimed at a remembered enemy rather than dropped.
        _bh.Thomas,
        _bh.InvestigateCorpse,
        _prior.Restore,
        _bh.FollowPlan,
        _bh.Interact,
        _prior.Minge,
        _prior.Investigate,
        _prior.Patrol
    },
    detective = {
        _prior.Survive,
        _prior.FightBack,
        _bh.Defib,
        _bh.Defuse,
        _prior.Restore,
        _bh.Interact,
        _prior.Minge,
        _prior.Investigate,
        _bh.Decrowd,
        _prior.Patrol
    }
}
TTTBots.Behaviors.DefaultTreesByTeam = {
    [TEAM_TRAITOR] = TTTBots.Behaviors.DefaultTrees.traitor,
    [TEAM_INNOCENT] = TTTBots.Behaviors.DefaultTrees.innocent,
    [TEAM_NONE] = TTTBots.Behaviors.DefaultTrees.innocent,
}

local STATUS = TTTBots.STATUS

---@class Bot
---@field lastBehavior BBase?

--- Returns the highest priority tree that has a callback which returned true on this bot.
---@param bot Bot
---@return Tree
function TTTBots.Behaviors.GetTreeFor(bot)
    return TTTBots.Roles.GetRoleFor(bot):GetBTree()
end

--- Call one of a behavior's callbacks, if it actually has one. Not every node implements all of
--- them - a node that never returns SUCCESS has no use for OnSuccess, for instance - and the runner
--- used to call them unconditionally, which threw "attempt to call field 'OnFailure' (a nil value)"
--- the first time it switched away from such a node and left the rest of that bot's tree unrun.
---@param node BBase
---@param callbackName string
---@param bot Bot
local function callBehaviorCallback(node, callbackName, bot)
    local callback = node[callbackName]
    if not callback then return end

    callback(bot)
end

--- Iterates over the node (or Tree if you're pedantic)
--- and performs logic accordingly. Can set bot.lastBehavior if successful
---@param bot Bot
---@param tree Tree
---@return boolean yield Should we stop any further calls?
function TTTBots.Behaviors.IterateNode(bot, tree)
    local lastBehavior = bot.lastBehavior
    -- Iterate through each node in this tree to see if we can find something that will work.
    for _, node in ipairs(tree) do
        if node.Validate == nil then
            -- If validate is nil then this is another Tree within this Tree, which is acceptable.
            local yield = TTTBots.Behaviors.IterateNode(bot, node)
            if yield then return true end

            -- If our tree-child didn't want us to yield, let's keep iterating through our other kiddos.
            -- Continue to the next node.
            continue
        end

        ---@cast node BBase
        local valid = node.Validate(bot)
        if not valid then continue end

        if lastBehavior == node then
            -- If we have already ran this action once just now, then try OnRunning instead.
            local onRunning = node.OnRunning
            if not onRunning then
                -- A node that cannot run can never finish, so drop it instead of stalling the bot on it.
                bot.lastBehavior = nil
                callBehaviorCallback(node, "OnFailure", bot)
                callBehaviorCallback(node, "OnEnd", bot)

                return true
            end

            local ranResult = onRunning(bot)

            if ranResult == STATUS.RUNNING then
                return true
            elseif ranResult == STATUS.FAILURE then
                bot.lastBehavior = nil
                callBehaviorCallback(node, "OnFailure", bot)
                callBehaviorCallback(node, "OnEnd", bot)
            elseif ranResult == STATUS.SUCCESS then
                bot.lastBehavior = nil
                callBehaviorCallback(node, "OnSuccess", bot)
                callBehaviorCallback(node, "OnEnd", bot)
            end

            return true
        end

        if lastBehavior ~= nil then
            -- If we have a last behavior, then we need to end it.
            callBehaviorCallback(lastBehavior, "OnFailure", bot)
            callBehaviorCallback(lastBehavior, "OnEnd", bot)
        end

        -- We just got here. Run OnStart.
        callBehaviorCallback(node, "OnStart", bot)
        bot.lastBehavior = node

        return true
    end

    return false
end

---Executes the tree of a bot
---@param bot Bot
---@param tree Tree
function TTTBots.Behaviors.RunTree(bot, tree)
    local lastBehavior = bot.lastBehavior

    -- Obligatory nil-safety.
    if not (bot and IsValid(bot)) then return end
    if not bot.initialized then return end

    -- If we have a behavior that is currently running and cannot be suddenly stopped, then we must
    -- try to run it again and see what happens.
    if lastBehavior and not lastBehavior.Interruptible then
        local result = lastBehavior.OnRunning(bot)
        if result == STATUS.RUNNING then return end
    end

    -- Now we've either finished the last behavior or it was interruptible.
    -- Try running the tree.
    TTTBots.Behaviors.IterateNode(bot, tree)
end

function TTTBots.Behaviors.RunTreeOnBots()
    for _, bot in ipairs(TTTBots.Bots) do
        -- GetTreeFor reads the bot's role out of it, so a bot that was removed since the last
        -- refresh of TTTBots.Bots would throw here on every single tick until the next one.
        if not (bot and IsValid(bot)) then continue end

        TTTBots.Behaviors.RunTree(
            bot,
            TTTBots.Behaviors.GetTreeFor(bot)
        )
    end
end


timer.Create("TTTBots.Debug.Brain", 0.5, 0, function()
    if not TTTBots.DebugServer then return end
    if not TTTBots.Lib.GetConVarBool("debug_brain") then return end

    for _, bot in ipairs(TTTBots.Bots) do
        if not (bot and IsValid(bot)) then continue end
        if not (TTTBots.Lib.IsPlayerAlive(bot)) then continue end
        if not (bot.lastBehavior and bot.lastBehavior.Name) then continue end

        TTTBots.DebugServer.DrawText(
            bot:GetPos(),
            bot:Nick() .. ": " .. bot.lastBehavior.Name,
            Color(255, 255, 255),
            0.5,
            bot:Nick() .. "_behavior"
        )
    end
end)