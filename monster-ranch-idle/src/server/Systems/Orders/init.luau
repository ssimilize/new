--[[
	Orders (update 3.8): Ranch Orders. Buyers post Config.Orders.PerDay orders each UTC day on
	the Job Board: a Teen or Adult with good genes (breeding gives the target) or food of one
	flavour. Rules and numbers: Logic/Orders, Config/Orders.

	Save section (profile.Orders):
	  day      the UTC day the list was drawn (0 = never)
	  list     = { Order }   -- see Logic/Orders
	  rerolls  rerolls used today

	Actions:
	  Orders.Fill { index, id? }   -- a monster order takes monster `id` for good; a goods order
	                                  spends the food. Returns { rewards }
	  Orders.Reroll { index }      -- replaces one unfilled order (RerollsPerDay a day)

	Rules:
	  • unlock Config.Orders.Unlock; the list is drawn from a seed of (userId, day) when the day
	    changes (join, the minute timer, any action, reaching the unlock), at the level of that
	    moment, so rejoining never changes it; a reroll's seed adds the reroll count
	  • at most one goods order a day, rerolls included
	  • a monster handed over must exist, not be locked or busy, not be the last monster, be a
	    Teen or Adult and meet the order's genes; it leaves with reason "order"
	  • pay: coins = CoinMult × its sell price, plus the difficulty's gems and ribbons, plus the
	    order's egg (hard orders, rolled at the draw); goods pay gems and treats

	Bus: publishes OrderFilled { index, kind, difficulty, monster?, rewards }; WelcomeItem when a
	new day's orders are waiting on join.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Formulas = require(Shared.Logic.Formulas)
local OrdersLogic = require(Shared.Logic.Orders)

local Orders = {
	Name = "Orders",
	Dependencies = { "Currency", "Progression", "Rewards", "Monsters" },
}

local ctx
local Rules
local Currency, Progression, Rewards, Monsters

Orders.Profile = {
	Version = 1,
	Default = function()
		return { day = 0, list = {}, rerolls = 0 }
	end,
}

local function section(player)
	return ctx:Section(player)
end

local function userId(player): number
	return player.UserId or 0
end

-- Draws today's orders when the day changed and the feature is open. Returns true on a draw.
local function ensure(player): boolean
	local s = section(player)
	if not s or not Progression:IsUnlocked(player, Rules.Unlock) then
		return false
	end
	local today = ctx:Day()
	if s.day == today and type(s.list) == "table" then
		return false
	end
	s.day = today
	s.list = OrdersLogic.Draw(userId(player), today, Progression:GetLevel(player))
	s.rerolls = 0
	ctx:Dirty(player, "day")
	ctx:Dirty(player, "list")
	ctx:Dirty(player, "rerolls")
	return true
end

local function mustOrder(player, index: number)
	local order = section(player).list[index]
	if not order then
		ctx:Fail("That order doesn't exist")
	end
	if order.filled then
		ctx:Fail("That order is already filled")
	end
	return order
end

-- Actions ---------------------------------------------------------------------------------

local function fill(player, payload)
	Progression:Require(player, Rules.Unlock)
	ensure(player)
	local order = mustOrder(player, payload.index)
	local items, monsterId
	if order.kind == "goods" then
		Currency:Charge(player, { ["food." .. order.food] = order.amount }, "order")
		items = OrdersLogic.Pay(order)
	else
		if not payload.id then
			ctx:Fail("Choose a monster for this order")
		end
		local m = Monsters:Get(player, payload.id)
		if not m then
			ctx:Fail("That monster doesn't exist")
		end
		local name = Formulas.DisplayName(m)
		if m.locked then
			ctx:Fail(string.format("%s is locked. Unlock it to hand it over.", name))
		end
		if m.busy then
			ctx:Fail(string.format("%s is busy", name))
		end
		if Monsters:Count(player) <= 1 then
			ctx:Fail("You need to keep at least one monster")
		end
		if (m.stage or 1) < Rules.MinStage then
			ctx:Fail("Only Teens and Adults can fill an order")
		end
		if not OrdersLogic.Meets(order, m) then
			ctx:Fail(string.format("%s doesn't meet this order", name))
		end
		-- The price is read before the record leaves.
		items = OrdersLogic.Pay(order, m)
		if not Monsters:Remove(player, m.id, "order") then
			ctx:Fail(string.format("%s is busy", name))
		end
		monsterId = m.id
	end
	order.filled = true
	ctx:Dirty(player, "list")
	local granted = Rewards:Grant(player, items, "orders")
	ctx.Bus:Publish("OrderFilled", player, {
		index = payload.index,
		kind = order.kind,
		difficulty = order.difficulty,
		monster = monsterId,
		rewards = granted,
	})
	return { rewards = granted }
end

local function reroll(player, payload)
	Progression:Require(player, Rules.Unlock)
	ensure(player)
	local s = section(player)
	if (s.rerolls or 0) >= Rules.RerollsPerDay then
		ctx:Fail("You've used today's reroll. New orders tomorrow!")
	end
	local old = mustOrder(player, payload.index)
	local goodsElsewhere = false
	for i, order in s.list do
		if i ~= payload.index and order.kind == "goods" then
			goodsElsewhere = true
		end
	end
	s.rerolls = (s.rerolls or 0) + 1
	local order =
		OrdersLogic.Make(OrdersLogic.RerollSeed(userId(player), s.day, s.rerolls), Progression:GetLevel(player), not goodsElsewhere)
	order.id = string.format("%s-r%d", tostring(old.id), s.rerolls)
	s.list[payload.index] = order
	ctx:Dirty(player, "list")
	ctx:Dirty(player, "rerolls")
	return nil
end

-- Lifecycle -----------------------------------------------------------------------------------

function Orders.Init(context)
	ctx = context
	Rules = ctx.Config.Orders
	Currency = ctx:GetSystem("Currency")
	Progression = ctx:GetSystem("Progression")
	Rewards = ctx:GetSystem("Rewards")
	Monsters = ctx:GetSystem("Monsters")

	ctx.Net:Handle("Orders.Fill", fill)
	ctx.Net:Handle("Orders.Reroll", reroll)

	ctx.Bus:Subscribe("LevelUp", function(player)
		if player then
			ensure(player)
		end
	end)

	-- A new UTC day while online: the next day's orders appear without a rejoin.
	ctx:Every(60, function()
		for _, player in ctx:Players() do
			ensure(player)
		end
	end)
end

function Orders.PlayerAdded(player, _info)
	local s = section(player)
	if type(s.list) ~= "table" then
		s.list = {}
	end
	local seenBefore = (s.day or 0) > 0
	if ensure(player) and seenBefore then
		ctx.Bus:Publish("WelcomeItem", player, { kind = "orders", text = "New Ranch Orders on the Job Board" })
	end
end

return Orders
