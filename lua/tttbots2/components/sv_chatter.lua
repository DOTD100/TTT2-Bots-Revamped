---@class CChatter : Component
TTTBots.Components.Chatter = TTTBots.Components.Chatter or {}

local lib = TTTBots.Lib
---@class CChatter : Component
local BotChatter = TTTBots.Components.Chatter

function BotChatter:New(bot)
    local newChatter = {}
    setmetatable(newChatter, {
        __index = function(t, k) return BotChatter[k] end,
    })
    newChatter:Initialize(bot)

    local dbg = lib.GetConVarBool("debug_misc")
    if dbg then
        print("Initialized Chatter for bot " .. bot:Nick())
    end

    return newChatter
end

function BotChatter:Initialize(bot)
    -- print("Initializing")
    bot.components = bot.components or {}
    bot.components.Chatter = self

    self.componentID = string.format("Chatter (%s)", lib.GenerateID()) -- Component ID, used for debugging

    self.tick = 0                                                      -- Tick counter
    self.bot = bot
    self.rateLimitTbl = {}
end

--- Check the rate limit table for if we can say the line. If so, then return true and update the rate limit tbl.
---@param event string
---@return boolean
function BotChatter:CanSayEvent(event)
    local rateLimitTime = lib.GetConVarFloat("chatter_minrepeat")
    local lastSpeak = self.rateLimitTbl[event] or -math.huge

    if lastSpeak + rateLimitTime < CurTime() then
        self.rateLimitTbl[event] = CurTime()
        return true
    end

    return false
end

function BotChatter:SayRaw(text, teamOnly)
    if not IsValid(self.bot) then return end
    self.bot:Say(text, teamOnly)
end

local keyboardLayout = {
    ['q'] = { 'w', 'a' },
    ['w'] = { 'q', 'e', 's', 'a' },
    ['e'] = { 'w', 'r', 'd', 's' },
    ['r'] = { 'e', 't', 'f', 'd' },
    ['t'] = { 'r', 'y', 'g', 'f' },
    ['y'] = { 't', 'u', 'h', 'g' },
    ['u'] = { 'y', 'i', 'j', 'h' },
    ['i'] = { 'u', 'o', 'k', 'j' },
    ['o'] = { 'i', 'p', 'l', 'k' },
    ['p'] = { 'o', 'l' },
    ['a'] = { 'q', 'w', 's', 'z' },
    ['s'] = { 'w', 'e', 'd', 'a', 'z', 'x' },
    ['d'] = { 'e', 'r', 'f', 's', 'x', 'c' },
    ['f'] = { 'r', 't', 'g', 'd', 'c', 'v' },
    ['g'] = { 't', 'y', 'h', 'f', 'v', 'b' },
    ['h'] = { 'y', 'u', 'j', 'g', 'b', 'n' },
    ['j'] = { 'u', 'i', 'k', 'h', 'n', 'm' },
    ['k'] = { 'i', 'o', 'l', 'j', 'm' },
    ['l'] = { 'o', 'p', 'k' },
    ['z'] = { 'a', 's', 'x' },
    ['x'] = { 'z', 's', 'd', 'c' },
    ['c'] = { 'x', 'd', 'f', 'v' },
    ['v'] = { 'c', 'f', 'g', 'b' },
    ['b'] = { 'v', 'g', 'h', 'n' },
    ['n'] = { 'b', 'h', 'j', 'm' },
    ['m'] = { 'n', 'j', 'k' },
}

local missKey = function(last, this, next)
    local typoOptions = keyboardLayout[this]
    if typoOptions then
        return typoOptions[math.random(#typoOptions)]
    else
        return this
    end
end

--- Intentionally inject typos into the text based on the chatter_typo_chance convars
---@param text string
---@return string result
function BotChatter:TypoText(text)
    local chance = lib.GetConVarFloat("chatter_typo_chance")

    local typoFuncs = {
        removeCharacter = function(last, this, next) return "" end,
        duplicateCharacter = function(last, this, next) return this .. this end,
        capitalizeCharacter = function(last, this, next) return string.upper(this) end,
        lowercaseCharacter = function(last, this, next) return string.lower(this) end,
        switchWithNext = function(last, this, next) return next .. this end,
        insertRandomCharacter = function(last, this, next) return this .. string.char(math.random(97, 122)) end,
        missKey = missKey
    }

    ---@type table<WeightedTable>
    local typoFuncsWeighted = {
        TTTBots.Lib.SetWeight(typoFuncs.removeCharacter, 20),
        TTTBots.Lib.SetWeight(typoFuncs.duplicateCharacter, 7),
        TTTBots.Lib.SetWeight(typoFuncs.capitalizeCharacter, 4),
        TTTBots.Lib.SetWeight(typoFuncs.lowercaseCharacter, 7),
        TTTBots.Lib.SetWeight(typoFuncs.switchWithNext, 12),
        TTTBots.Lib.SetWeight(typoFuncs.insertRandomCharacter, 14),
        TTTBots.Lib.SetWeight(typoFuncs.missKey, 30)
    }

    local result = ""
    local textLength = string.len(text)
    local placeholderEnd = 0 -- characters up to here are inside a {{placeholder}} and copied verbatim
    for i = 1, textLength do
        local char = string.sub(text, i, i)
        local last = i > 1 and string.sub(text, i - 1, i - 1) or ""
        local next = i < textLength and string.sub(text, i + 1, i + 1) or ""

        if i <= placeholderEnd then
            -- Inside a substitution token: never inject a typo here.
            result = result .. char
        elseif char == "{" and next == "{" then
            -- Start of a {{placeholder}}; copy it through verbatim.
            local close = string.find(text, "}}", i + 2, true)
            placeholderEnd = close and (close + 1) or i
            result = result .. char
        else
            if math.random(0, 100) < chance then
                local typoFunc = lib.RandomWeighted(typoFuncsWeighted)
                char = typoFunc(last, char, next)
            end

            result = result .. char
        end
    end

    return result
end

--- Order the bot to say a string of text in chat. This function is rate limited and types messages out at a somewhat random speed.
---@param text string The raw string of text to put in chat.
---@param teamOnly boolean|nil (OPTIONAL, =FALSE) Should the bot place the message in the team chat?
---@param ignoreDeath boolean|nil (OPTIONAL, =FALSE) Should the bot say the text despite being dead?
---@param callback nil|function (OPTIONAL) A callback function to call when the bot is done speaking.
---@return boolean chatting Returns true if we just ordered the bot to speak, otherwise returns false.
function BotChatter:Say(text, teamOnly, ignoreDeath, callback)
    -- Gate on `typingUntil` rather than `typing` so a stale latch expires on its own. The flag used to
    -- be able to stay set forever (see below), and a bot in that state can never start a new message,
    -- so it recovers here instead of being mute until it respawns.
    if self.typing and (self.typingUntil or 0) > CurTime() then return false end

    -- A cvar of 0 or less would give an infinite delay, and the timer below is what releases the typing
    -- latch, so clamp it instead of silencing the bot forever.
    local cps = lib.GetConVarFloat("chatter_cps")
    if not cps or cps <= 0 then cps = 1 end
    local delay = (string.len(text) / cps) * (math.random(75, 150) / 100)

    self.typing = true
    self.typingUntil = CurTime() + delay + 5 -- generous margin over the actual typing time

    -- remove "[BOT] " and "[bot] " occurences from the text
    text = string.gsub(text, "%[BOT%] ", "")
    text = string.gsub(text, "%[bot%] ", "")
    text = self:TypoText(text)
    timer.Simple(delay, function()
        -- Release the latch unconditionally, even when we end up not speaking. It used to be cleared only
        -- on the speaking path, so a bot that rolled a line while dead never said anything again for the
        -- rest of its life: every later Say() hit the `if self.typing` guard and returned false.
        self.typing = false
        self.typingUntil = nil

        if self.bot == NULL or not IsValid(self.bot) then return end
        if ignoreDeath or lib.IsPlayerAlive(self.bot) then
            self:SayRaw(text, teamOnly)
            if callback then callback() end
        end
    end)
    return true
end

local RADIO = {
    quick_traitor = "%s is a Traitor!",
    quick_suspect = "%s acts suspicious."
}
function BotChatter:QuickRadio(msgName, msgTarget)
    local txt = RADIO[msgName]
    if not txt then ErrorNoHaltWithStack("Unknown message type " .. msgName) end
    hook.Run("TTTPlayerRadioCommand", self.bot, msgName, msgTarget)
end

--- Whether the bot is up right now. Deliberately the live entity state rather than the cached
--- `lib.IsPlayerAlive`: that cache is rebuilt once a tick, so a bot revived on this tick would still read as
--- dead and would lose the line it came back to say.
---@param bot Bot
---@return boolean
local function isBotUp(bot)
    return IsValid(bot) and not bot:IsSpec() and bot:Alive() and bot:Health() > 0
end

--- The categories a dead bot may still say: the flavour line that was written for a spectating bot, and the line
--- said on a timer after joining.
local DEAD_ALLOWED = {
    SillyChatDead = true,
    ServerConnected = true,
}

--- The goodbye lines are named after the reason (`"Disconnect" .. reason`), so they are matched by prefix.
local DEAD_ALLOWED_PREFIX = "Disconnect"
---@param event_name string
---@return boolean
local function allowedWhileDead(event_name)
    if type(event_name) ~= "string" then return false end
    if DEAD_ALLOWED[event_name] then return true end

    return string.sub(event_name, 1, #DEAD_ALLOWED_PREFIX) == DEAD_ALLOWED_PREFIX
end

--- A generic wrapper for when an event happens, to be implemented further in the future
---@param event_name string
---@param args table<any>? A table of arguments passed to the event
function BotChatter:On(event_name, args, teamOnly)
    -- A dead bot has no business calling KOS, reporting a body, naming a traitor, narrating a plan or answering a
    -- life check: its information is stale by definition, and it is the living players who act on a callout. Only
    -- the lines written for the dead get through. This sits ahead of the rate limit so that a refused line does
    -- not spend the bot's one chance to say it once it is back up.
    --
    -- Dialog lines do not pass through here - sv_dialog.lua calls `Say` directly - which is exactly why a
    -- dead-only dialog still works.
    if not isBotUp(self.bot) and not allowedWhileDead(event_name) then return false end

    local dvlpr = lib.GetConVarBool("debug_misc")
    if dvlpr then
        print(string.format("Event %s called with %d args.", event_name, args and #args))
    end

    if not self:CanSayEvent(event_name) then return false end

    if event_name == "CallKOS" then
        local target = args and args.playerEnt
        if target and IsValid(target) then
            if (target.lastKOSTime or 0) + 5 > CurTime() then return false end
            target.lastKOSTime = CurTime()
        end
    end

    local difficulty = lib.GetConVarInt("difficulty")
    local kosChanceMult = lib.GetConVarFloat("chatter_koschance")

    --- Base chances to react to the events via chat
    local chancesOf100 = {
        InvestigateNoise = 15,
        InvestigateCorpse = 15,
        LifeCheck = 65,
        CallKOS = 15 * difficulty * kosChanceMult,
        FollowStarted = 10,
        ServerConnected = 45,
        SillyChat = 30,
        SillyChatDead = 15,
    }

    local personality = self.bot.components.personality --- @type CPersonality
    if chancesOf100[event_name] then
        local chance = chancesOf100[event_name]
        if math.random(0, 100) > (chance * personality:GetTraitMult("textchat")) then return false end
    end

    local localizedString = TTTBots.Locale.GetLocalizedLine(event_name, self.bot, args)
    local isCasual = personality:GetClosestArchetype() == TTTBots.Archetypes.Casual
    if localizedString then
        if isCasual then localizedString = string.lower(localizedString) end
        self:Say(localizedString, teamOnly, false, function()
            if event_name == "CallKOS" and args then
                self:QuickRadio("quick_traitor", args.playerEnt)
            end
        end)
        return true
    end

    return false
end

function BotChatter:Think()
end

-- hook for GM:PlayerCanSeePlayersChat(text, taemOnly, listener, sender)
hook.Add("PlayerCanSeePlayersChat", "TTTBots_PlayerCanSeePlayersChat", function(text, teamOnly, listener, sender)
    if not (IsValid(sender) and sender:IsBot() and teamOnly) then
        return
    end

    if not lib.IsPlayerAlive(sender) then
        return false
    end

    if listener:IsInTeam(sender) then
        return true
    end

    return false
end)


-- Define a hash table to hold our keywords and their corresponding events
local keywordEvents = {
    ["life check"] = "LifeCheck",
    ["who is alive"] = "LifeCheck",
    -- ["kos"] = "KOSCallout",
}

-- Helper function to handle the chat events
local function handleEvent(eventName)
    for i, v in pairs(TTTBots.Bots) do
        ---@cast v Bot
        local chatter = v:BotChatter()
        if not chatter then continue end
        chatter:On(eventName, {}, false)
    end
end

hook.Add("PlayerSay", "TTTBots.Chatter.PromptResponse", function(sender, text, teamChat)
    local text2 = string.lower(text) -- Convert text to lowercase for case-insensitive comparison

    for keyword, event in pairs(keywordEvents) do
        if string.find(text2, keyword) then
            handleEvent(event) -- Pass the full chat message to handleEvent
        end
    end
end)

timer.Create("TTTBots.Chatter.SillyChat", 20, 0, function()
    if math.random(1, 9) > 1 then return end -- Should average to about once every 3 minutes
    local targetBot = TTTBots.Bots[math.random(1, #TTTBots.Bots)]
    if not (targetBot and IsValid(targetBot)) then return end
    if not targetBot.components then return end

    local chatter = targetBot:BotChatter()
    if not chatter then return end

    local randomPlayer = TTTBots.Match.AlivePlayers[math.random(1, #TTTBots.Match.AlivePlayers)]
    if not randomPlayer or randomPlayer == targetBot then return end

    local eventName = lib.IsPlayerAlive(targetBot) and "SillyChat" or "SillyChatDead"
    chatter:On(eventName, { player = randomPlayer:Nick() })
end)

---@class Player
local plyMeta = FindMetaTable("Player")
---@return CChatter?
function plyMeta:BotChatter()
    ---@cast self Bot
    -- Nil unless this is a fully initialized bot; see plyMeta:BotMorality for why this cannot just read
    -- self.components.
    return self.components and self.components.chatter
end
