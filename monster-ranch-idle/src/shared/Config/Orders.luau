--[[
	Orders (update 3.8): Ranch Orders. Buyers post PerDay orders a UTC day on the Job Board, for a
	Teen or Adult with good genes or for food. Logic/Orders draws and checks them; Systems/Orders
	keeps the day's list.

	  Unlock          the feature key (Config/Unlocks)
	  PerDay          orders drawn each UTC day, from a seed of (userId, day): rejoining never
	                  rerolls them
	  RerollsPerDay   free rerolls a day; each replaces one unfilled order
	  MinStage        monster orders take Teens and Adults only
	  CoinMult        a monster order pays this many times the monster's sell price in coins
	  GoodsChance     each order's chance to ask for food instead, at most one goods order a day
	  Weights         monster order difficulty weights, below and from HardLevel
	  Difficulty      the gene requirement and the fixed pay of each difficulty:
	                    easy    one stat at `grade` or better
	                    medium  one stat at `grade` or better
	                    hard    one stat at `grade`, OR two stats at `twoGrade`, OR a gene total of
	                            at least `genesMin` (of Logic/Genetics.MaxTotal)
	  EggChance       a hard order's chance of an egg on top, rolled when the order is drawn
	  Eggs            which egg, by weight, among the eggs whose unlock the player has reached
	  Goods           food amount: Base + PerLevel for each level past the unlock, plus a random
	                  0..Spread steps of Step, rounded to Step and kept within Min..Max; pays gems
	                  and treats in the given ranges
	  Buyers          who posts an order (picked from the order's seed); BuyerIds are their stable
	                  ids in the same order (3.9), BuyerById[id] = { id, name, index, decor }
	  Rep (3.9)       buyer reputation: filling an order earns its buyer Points[difficulty];
	                  Levels are the point thresholds of levels 1..#Levels. Perks by level:
	                    CoinBonus[level]  extra coins on that buyer's monster orders (fraction)
	                    EggLevel          from this level their Hard orders roll eggs at EggChance
	                    FavLevel          the highest such buyer posts one extra order a day
	                    Gifts             one-time gifts on reaching a level (decor = the buyer's
	                                      piece in Config.Decor, never sold)
	                    Perks[level]      the perk in words, for the Buyers panel
]]

local Orders = {}

Orders.Unlock = "orders"
Orders.PerDay = 3
Orders.RerollsPerDay = 1
Orders.MinStage = 2
Orders.CoinMult = 3
Orders.GoodsChance = 0.2
Orders.HardLevel = 20

Orders.Weights = {
	low = { easy = 60, medium = 40, hard = 0 }, -- below HardLevel
	high = { easy = 35, medium = 40, hard = 25 },
}

Orders.DifficultyIds = { "easy", "medium", "hard" }
Orders.Difficulty = {
	easy = { name = "Easy", color = "#5DBB63", grade = "C", gems = 5, ribbons = 2 },
	medium = { name = "Medium", color = "#4E9BF2", grade = "B", gems = 10, ribbons = 5 },
	hard = { name = "Hard", color = "#B06AE8", grade = "A", twoGrade = "B", genesMin = 60, gems = 25, ribbons = 10 },
	goods = { name = "Goods", color = "#E8A23B" },
}

Orders.EggChance = 0.25
Orders.Eggs = {
	{ egg = "crystal", weight = 3, unlock = "egg_crystal" },
	{ egg = "royal", weight = 1, unlock = "egg_royal" },
}

Orders.Goods = {
	Min = 150,
	Max = 400,
	Base = 150,
	PerLevel = 5,
	Step = 10,
	Spread = 5,
	Gems = { 10, 20 },
	Treats = { 5, 10 },
}

Orders.Buyers = {
	"Farmer Rosa",
	"Chef Pip",
	"Baker Milo",
	"Captain Wren",
	"Doctor Ada",
	"Collector Juno",
	"Ranger Tam",
	"Professor Hale",
}

-- 3.9 · Buyer reputation --------------------------------------------------------------------

Orders.BuyerIds = { "rosa", "pip", "milo", "wren", "ada", "juno", "tam", "hale" }

local BUYER_DECOR = {
	rosa = "rep_scarecrow",
	pip = "rep_stove",
	milo = "rep_bread_oven",
	wren = "rep_anchor",
	ada = "rep_medicine_cabinet",
	juno = "rep_display_case",
	tam = "rep_lookout_sign",
	hale = "rep_telescope",
}

Orders.BuyerById = {}
for i, id in Orders.BuyerIds do
	Orders.BuyerById[id] = { id = id, name = Orders.Buyers[i], index = i, decor = BUYER_DECOR[id] }
end

Orders.Rep = {
	Points = { easy = 1, medium = 2, hard = 4, goods = 2 },
	Levels = { 5, 15, 35, 70 },
	CoinBonus = { 0.10, 0.10, 0.25, 0.25 },
	EggLevel = 2,
	EggChance = 0.40,
	FavLevel = 3,
	Gifts = {
		{ level = 2, gems = 20, food = 20 },
		{ level = 4, decor = true },
	},
	Perks = {
		"+10% coins on their monster orders",
		"40% egg chance on their Hard orders, and a thank-you gift",
		"+25% coins, and a daily favourite buyer order",
		"A thank-you decor piece",
	},
}

return Orders
