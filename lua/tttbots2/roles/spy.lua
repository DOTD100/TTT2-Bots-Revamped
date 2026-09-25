if not TTTBots.Lib.IsTTT2() then return false end
if not ROLE_SPY then return false end

--[[
An innocent subrole (roles.SetBaseRole(self, ROLE_INNOCENT)) with unknownTeam set and a *fake* traitor
shop: while ttt2_spy_fake_buy is on, ordering from it is refused - the Spy is handed nothing - and the
traitors are told an item was bought, so it looks like one of them. With that convar off it buys from the
traitor list for real. The rest of the act is the addon's own: traitors see it as a traitor on the role sync
and radar, its presence jams their chat and voice, and its corpse confirms as one.

The only bot-side piece is the bluff, because bots skip the shop entirely. The role names the gamemode's
convar with SetFakeShopConvar, and the buyables send the same notification the role's own hook would.

Left as TTT2 has it: no police appearance, so innocents can still call it out for traitor gear exactly as
they would a player Spy, and no allies, because IsAllies is symmetric and allying it with the innocents
would also make it untouchable after shooting one.
]]

local spy = TTTBots.RoleData.New("spy", TEAM_INNOCENT)
spy:SetDefusesC4(true)
spy:SetTeam(TEAM_INNOCENT)
spy:SetBTree(TTTBots.Behaviors.DefaultTrees.innocent)
spy:SetCanHide(true)
spy:SetCanSnipe(true)
spy:SetUsesSuspicion(true)
spy:SetAlliedRoles({})
spy:SetAlliedTeams({})
-- Our shop orders are a bluff, gated on the role's own convar.
spy:SetFakeShopConvar("ttt2_spy_fake_buy")
-- Refused either way: with the bluff off the Spy really receives what it orders, and a bot planting bombs
-- as an innocent blows up its own team. The buyable's CanBuy reads this flag.
spy:SetPlantsC4(false)
TTTBots.Roles.RegisterRole(spy)

return true
