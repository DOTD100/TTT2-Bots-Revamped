if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_REVOLUTIONARY then return false end

--[[
A subrole of the Detective (roles.SetBaseRole(self, ROLE_DETECTIVE)) on the innocent team, with
unknownTeam set so other players see which role it is but not which team it belongs to. It declares
isPublicRole and isPolicingRole, and its shop does not belong to it: shopFallback = SHOP_FALLBACK_TRAITOR
means a Revolutionary shops from the *traitor* list, which is the whole gimmick - an innocent armed with
traitor equipment, hunting traitors with their own tools.

Two things follow for a bot, and they pull in different directions:

  * the policing profile of its base role: defuse, suspicion, and the detective behavior tree. It is
    also AppearsPolice, which is what keeps its own team off its back: BotMorality:ChangeSuspicion
    scales everything a bot holds against a police-looking player down to 30%, and Match.CallKOS turns a
    police-looking target down outright. Without the flag, a teammate spotting the traitor-exclusive
    weapon this role's borrowed shop hands it would be over the KOS threshold on the spot and shoot it.
  * the traitor shop. This file cannot grant that, because buyables are looked up by role name and team:
    Buyables.GetBorrowedShopRole reads TTT2's own shop fallback and adds the shop of the role named there,
    so the traitor entries come along with it and the bot buys what a player of the role would be offered.

Its loadout is item_ttt_armor, and the addon only hands that over on a role *change* (GiveRoleLoadout
returns early when isRoleChange is false), so a bot that spawns as one starts with nothing beyond the
traitor shop. Nothing here has to trigger that either way. It does not get its base role's DNA scanner
either, which is why it is left without the radar knowledge CanHaveRadar models.
]]

local revolutionary = TTTBots.RoleData.New("revolutionary", TEAM_INNOCENT)
revolutionary:SetDefusesC4(true)
revolutionary:SetTeam(TEAM_INNOCENT)
revolutionary:SetBTree(TTTBots.Behaviors.DefaultTrees.detective)
revolutionary:SetUsesSuspicion(true)
revolutionary:SetAppearsPolice(true)
-- No C4. The borrowed traitor shop offers it, so the role itself has to refuse: an innocent bot that
-- plants a bomb on its own initiative blows up its own team and gives every innocent in the round a
-- reason to shoot it. Buying one is refused in the buyable's CanBuy, which reads this flag.
revolutionary:SetPlantsC4(false)
TTTBots.Roles.RegisterRole(revolutionary)

return true
