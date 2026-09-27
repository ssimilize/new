--[[
	Orders (update 3.8): Ranch Orders. Pure rules shared by the server (the daily draw, fill
	checks, pay) and the client (card text, the monster picker). Numbers live in Config.Orders.

	Order (profile.Orders.list[i]):
	  { id, kind = "monster"|"goods", difficulty = "easy"|"medium"|"hard"|"goods", seed,
	    stat?, grade?          -- one stat at this grade or better
	    twoStats?, grade?      -- both stats at this grade or better (hard)
	    genesMin?              -- a gene total of at least this (hard)
	    food?, amount?         -- goods: this much food of one flavour
	    egg?                   -- hard: an egg on top, rolled when drawn
	    buyer                  -- 3.9: the buyer id (Config.Orders.BuyerIds); orders drawn
	                              before 3.9 have none and read it from the seed
	    favourite?             -- 3.9: the day's extra favourite buyer order
	    filled }

	  Orders.Available(level) -> boolean            the feature is open at this Ranch Level
	  Orders.DaySeed(userId, day) -> number         the day's draw seed
	  Orders.RerollSeed(userId, day, n) -> number   the n-th reroll's seed that day
	  Orders.Make(seed, level, allowGoods, rep?, buyer?) -> Order
	                                                one order from its own seed (no id); the
	                                                buyer comes from the seed unless given, and
	                                                its reputation sets the egg chance
	  Orders.Draw(userId, day, level, rep?) -> { Order }
	                                                the day's PerDay orders, at most one goods
	  Orders.GradeMin(grade) -> number              pair points a grade starts at
	  Orders.Meets(order, m) -> boolean             the monster's genes meet the order
	  Orders.Qualifies(order, m) -> boolean         Meets and a Teen or Adult
	  Orders.Pay(order, m?, repLevel?) -> { Reward } what filling it pays (coins need the
	                                                monster; the buyer's level adds its bonus)
	  Orders.Coins(m, repLevel?) -> number          a monster order's coins for this monster
	  Orders.Buyer(order) -> string                 the buyer's display name
	  Orders.BuyerId(order) -> string               the buyer id (stored, or from the seed)

	Buyer reputation (3.9), rep = profile.Orders.rep = { [buyerId] = points }:
	  Orders.RepPoints(order) -> number             points filling it earns its buyer
	  Orders.RepLevel(points) -> number             0..#Rep.Levels
	  Orders.RepProgress(points) -> (level, from, to?)  the level, its threshold and the next
	  Orders.CoinBonus(level) -> number             the coin bonus fraction at this level
	  Orders.EggChanceAt(level) -> number           a Hard order's egg chance at this level
	  Orders.Favourite(rep) -> string?              the highest buyer at FavLevel+ (ties: id)
	  Orders.FavSeed(userId, day) -> number         the favourite order's own seed
	  Orders.DrawFavourite(userId, day, level, rep) -> Order?   the day's extra order, if any
	  Orders.GiftsBetween(from, to) -> { Gift }     Rep.Gifts for levels in (from, to]
	  Orders.GiftItems(gift, buyerId, userId) -> { Reward }
	  Orders.RequirementText(order) -> string
]]

local Config = require(script.Parent.Parent.Config)
local Rng = require(script.Parent.Rng)
local Genetics = require(script.Parent.Genetics)
local Formulas = require(script.Parent.Formulas)

local Rules = Config.Orders
local StatNames = Config.Genetics.StatNames

local Orders = {}

local SEED_MAX = 2147483646

function Orders.Available(level: number): boolean
	return level >= (Config.Unlocks.Features[Rules.Unlock] or math.huge)
end

function Orders.DaySeed(userId: number, day: number): number
	return Rng.seed("orders", userId, day)
end

function Orders.RerollSeed(userId: number, day: number, n: number): number
	return Rng.seed("orders", userId, day, "reroll", n)
end

function Orders.GradeMin(grade: string): number
	for _, g in Config.Genetics.Grades do
		if g.grade == grade then
			return g.min
		end
	end
	return math.huge
end

local function eggFor(rng, level: number): string
	local pool, weights = {}, {}
	for _, entry in Rules.Eggs do
		if level >= (Config.Unlocks.Features[entry.unlock] or 0) then
			table.insert(pool, entry.egg)
			table.insert(weights, entry.weight)
		end
	end
	if #pool == 0 then
		return Rules.Eggs[1].egg
	end
	return pool[rng:Weighted(weights)]
end

local function goodsAmount(rng, level: number): number
	local g = Rules.Goods
	local past = math.max(0, level - (Config.Unlocks.Features[Rules.Unlock] or 0))
	local raw = g.Base + past * g.PerLevel + rng:Int(0, g.Spread) * g.Step
	local rounded = math.floor(raw / g.Step + 0.5) * g.Step
	return math.clamp(rounded, g.Min, g.Max)
end

-- Two different stats, in Config.Genetics.Stats order.
local function twoStats(rng)
	local stats = table.clone(Config.Genetics.Stats)
	local a = table.remove(stats, rng:Int(1, #stats))
	local b = stats[rng:Int(1, #stats)]
	local order = Config.Genetics.Stats
	if (table.find(order, a) :: number) > (table.find(order, b) :: number) then
		a, b = b, a
	end
	return { a, b }
end

function Orders.Make(seed: number, level: number, allowGoods: boolean, rep: { [string]: number }?, buyer: string?)
	local rng = Rng.new(seed)
	local buyerId = buyer or Orders.BuyerId({ seed = seed })
	local order: { [string]: any } = { seed = seed, buyer = buyerId, filled = false }
	if allowGoods and rng:Chance(Rules.GoodsChance) then
		order.kind = "goods"
		order.difficulty = "goods"
		order.food = rng:Pick(Config.Food.Ids)
		order.amount = goodsAmount(rng, level)
		return order
	end
	order.kind = "monster"
	local weights = if level >= Rules.HardLevel then Rules.Weights.high else Rules.Weights.low
	local list = {}
	for _, id in Rules.DifficultyIds do
		table.insert(list, weights[id] or 0)
	end
	local difficulty = Rules.DifficultyIds[rng:Weighted(list)]
	local d = Rules.Difficulty[difficulty]
	order.difficulty = difficulty
	local stats = Config.Genetics.Stats
	if difficulty == "hard" then
		local variant = rng:Int(1, 3)
		if variant == 1 then
			order.stat = stats[rng:Int(1, #stats)]
			order.grade = d.grade
		elseif variant == 2 then
			order.twoStats = twoStats(rng)
			order.grade = d.twoGrade
		else
			order.genesMin = d.genesMin
		end
		-- The same roll as before 3.9; only the chance it is compared with depends on the buyer.
		local points = if type(rep) == "table" then tonumber(rep[buyerId]) or 0 else 0
		if rng:Chance(Orders.EggChanceAt(Orders.RepLevel(points))) then
			order.egg = eggFor(rng, level)
		end
	else
		order.stat = stats[rng:Int(1, #stats)]
		order.grade = d.grade
	end
	return order
end

function Orders.Draw(userId: number, day: number, level: number, rep: { [string]: number }?)
	local rng = Rng.new(Orders.DaySeed(userId, day))
	local list, goods = {}, false
	for i = 1, Rules.PerDay do
		local order = Orders.Make(rng:Int(1, SEED_MAX), level, not goods, rep)
		order.id = string.format("%d-%d", day, i)
		goods = goods or order.kind == "goods"
		list[i] = order
	end
	return list
end

function Orders.Meets(order, m): boolean
	if type(order) ~= "table" or order.kind ~= "monster" or type(m) ~= "table" then
		return false
	end
	local genes = m.genes
	if order.genesMin then
		return Genetics.Total(genes) >= order.genesMin
	end
	local min = Orders.GradeMin(order.grade)
	if order.twoStats then
		for _, stat in order.twoStats do
			if Genetics.Points(genes, stat) < min then
				return false
			end
		end
		return true
	end
	return Genetics.Points(genes, order.stat) >= min
end

function Orders.Qualifies(order, m): boolean
	return type(m) == "table" and (m.stage or 1) >= Rules.MinStage and Orders.Meets(order, m)
end

function Orders.Coins(m, repLevel: number?): number
	local base = Rules.CoinMult * Formulas.SellPrice(m)
	local bonus = Orders.CoinBonus(repLevel or 0)
	if bonus <= 0 then
		return base
	end
	return math.floor(base * (1 + bonus) + 0.5)
end

-- Goods pay comes from its own stream of the order's seed, so it never shifts the draw.
local function goodsPay(order): (number, number)
	local rng = Rng.new(Rng.seed(order.seed or 0, "pay"))
	local g = Rules.Goods
	return rng:Int(g.Gems[1], g.Gems[2]), rng:Int(g.Treats[1], g.Treats[2])
end

function Orders.Pay(order, m, repLevel: number?)
	local items = {}
	if order.kind == "goods" then
		local gems, treats = goodsPay(order)
		table.insert(items, { kind = "gems", amount = gems })
		table.insert(items, { kind = "treats", amount = treats })
		return items
	end
	local d = Rules.Difficulty[order.difficulty] or Rules.Difficulty.easy
	if m then
		table.insert(items, { kind = "coins", amount = Orders.Coins(m, repLevel) })
	end
	table.insert(items, { kind = "gems", amount = d.gems })
	table.insert(items, { kind = "ribbons", amount = d.ribbons })
	if order.egg then
		table.insert(items, { kind = "egg", id = order.egg, amount = 1 })
	end
	return items
end

function Orders.BuyerId(order): string
	if type(order) == "table" and type(order.buyer) == "string" and Rules.BuyerById[order.buyer] then
		return order.buyer
	end
	-- Orders drawn before 3.9 carry no id: the buyer was always read from the seed this way.
	local seed = if type(order) == "table" then tonumber(order.seed) or 0 else 0
	return Rules.BuyerIds[(seed % #Rules.BuyerIds) + 1]
end

function Orders.Buyer(order): string
	return Rules.BuyerById[Orders.BuyerId(order)].name
end

-- Buyer reputation (3.9) -----------------------------------------------------------------------

local Rep = Rules.Rep

function Orders.RepPoints(order): number
	return if type(order) == "table" then Rep.Points[order.difficulty] or 0 else 0
end

function Orders.RepLevel(points: number?): number
	local level = 0
	for i, need in Rep.Levels do
		if (tonumber(points) or 0) >= need then
			level = i
		end
	end
	return level
end

function Orders.RepProgress(points: number?): (number, number, number?)
	local level = Orders.RepLevel(points)
	return level, Rep.Levels[level] or 0, Rep.Levels[level + 1]
end

function Orders.CoinBonus(level: number): number
	return Rep.CoinBonus[level] or 0
end

function Orders.EggChanceAt(level: number): number
	return if level >= Rep.EggLevel then Rep.EggChance else Rules.EggChance
end

function Orders.Favourite(rep): string?
	if type(rep) ~= "table" then
		return nil
	end
	local best, bestPoints = nil, -1
	for _, id in Rules.BuyerIds do
		local points = tonumber(rep[id]) or 0
		if Orders.RepLevel(points) >= Rep.FavLevel and (points > bestPoints or (points == bestPoints and id < best)) then
			best, bestPoints = id, points
		end
	end
	return best
end

function Orders.FavSeed(userId: number, day: number): number
	return Rng.seed("orders_fav", userId, day)
end

function Orders.DrawFavourite(userId: number, day: number, level: number, rep)
	local buyer = Orders.Favourite(rep)
	if not buyer then
		return nil
	end
	local rng = Rng.new(Orders.FavSeed(userId, day))
	local order = Orders.Make(rng:Int(1, SEED_MAX), level, false, rep, buyer)
	order.id = string.format("%d-fav", day)
	order.favourite = true
	return order
end

function Orders.GiftsBetween(from: number, to: number)
	local list = {}
	for _, gift in Rep.Gifts do
		if gift.level > from and gift.level <= to then
			table.insert(list, gift)
		end
	end
	return list
end

function Orders.GiftItems(gift, buyerId: string, userId: number)
	local items = {}
	if gift.gems then
		table.insert(items, { kind = "gems", amount = gift.gems })
	end
	if gift.food then
		-- The flavour comes from its own seed, so the gift never moves another roll.
		local rng = Rng.new(Rng.seed("orders_rep_gift", userId, buyerId, gift.level))
		table.insert(items, { kind = "food", id = rng:Pick(Config.Food.Ids), amount = gift.food })
	end
	if gift.decor then
		local b = Rules.BuyerById[buyerId]
		if b and b.decor then
			table.insert(items, { kind = "decor", id = b.decor, amount = 1 })
		end
	end
	return items
end

function Orders.RequirementText(order): string
	if order.kind == "goods" then
		local food = Config.Food.ById[order.food]
		return string.format("Deliver %d %s", order.amount or 0, if food then food.name else "food")
	elseif order.genesMin then
		return string.format("A Teen or Adult with a gene total of %d or more", order.genesMin)
	elseif order.twoStats then
		return string.format(
			"A Teen or Adult with %s and %s at grade %s or better",
			StatNames[order.twoStats[1]] or order.twoStats[1],
			StatNames[order.twoStats[2]] or order.twoStats[2],
			order.grade
		)
	end
	return string.format("A Teen or Adult with %s grade %s or better", StatNames[order.stat] or order.stat, order.grade)
end

return Orders
