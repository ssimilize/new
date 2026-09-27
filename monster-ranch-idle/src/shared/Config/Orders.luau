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
	  Buyers          who posts an order (picked from the order's seed)
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

return Orders
