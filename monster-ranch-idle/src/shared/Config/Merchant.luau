--[[
	Travelling Merchant (update 3.11 · Seasons & secrets). A caravan parks in the Market Square
	for Stay seconds out of every Cycle (visit k runs from k * Cycle + Offset), the same on every
	server. Each visit sells Slots offers rolled from Offers with a seed of ("merchant", visit), so
	every player sees the same stock; each player may buy an offer up to its `limit` per visit.
	Rules in Logic/Merchant, the server in Systems/Merchant.

	Offer: { id, kind, name, desc, amount, weight, limit, unlock?, pay = { Pay, Pay? }, ... }
	  kind    scroll (Trait Scroll) · seeds (Kitchen:AddSeeds) · bait (Fishing:AddBait) ·
	          shovels (DigSite:AddShovels) · decor (`decor` = index into Merchant.Decor, rotating
	          by visit) · egg (`eggs` = weighted egg ids from Config.Eggs)
	          · tower_retry (TrialTower:AddRetries, 3.12)
	  unlock  the player needs this feature to buy it; an unlock key missing from Config.Unlocks
	          keeps the offer out of the roll entirely (the Dig Site before it ships)
	Pay: { kind, amount?, seconds? }  one way to pay, all or nothing:
	  coins (`seconds` of ranch income, at least MinCoins) · gems · amber · fish (Fishing:SpendFish)
	  · dishes (Kitchen pantry dishes, the most plentiful first)
]]

local Merchant = {}

Merchant.Unlock = "merchant"
Merchant.Cycle = 6 * 3600 -- a visit every 6 hours
Merchant.Stay = 2 * 3600 -- the caravan stays 2 of them
Merchant.Offset = 3 * 3600 -- visits start at 03:00, 09:00, 15:00 and 21:00 UTC
Merchant.Slots = 6
Merchant.MinCoins = 500
Merchant.ScrollCap = 99

-- The caravan in the Market Square's west corner, between the Workshop and the path to plot 1
-- (clear of every hub building, egg-hunt spot and path). Scenery keeps off it (Config.World).
Merchant.World = {
	position = { -104, 0, -42 },
	radius = 14, -- the keep-out circle round it
	promptDistance = 14,
}

-- Merchant-only decor (Config.Decor, reward = "merchant"): two of them each visit, rotating.
Merchant.Decor = { "caravan_lantern", "spice_crates", "silk_canopy" }

Merchant.Offers = {
	{
		id = "trait_scroll",
		kind = "scroll",
		name = "Trait Scroll",
		desc = "Rerolls one visible trait of a monster.",
		amount = 1,
		weight = 8,
		limit = 1,
		pay = { { kind = "gems", amount = 80 }, { kind = "amber", amount = 10 } },
	},
	{
		id = "seed_pouch",
		kind = "seeds",
		name = "Golden Seed",
		desc = "Plant it in the Feed Garden for golden produce.",
		amount = 1,
		weight = 12,
		limit = 3,
		unlock = "kitchen",
		pay = { { kind = "coins", seconds = 900 }, { kind = "fish", amount = 3 } },
	},
	{
		id = "seed_sack",
		kind = "seeds",
		name = "Golden Seed Sack",
		desc = "Three Golden seeds for the Feed Garden.",
		amount = 3,
		weight = 6,
		limit = 1,
		unlock = "kitchen",
		pay = { { kind = "gems", amount = 40 }, { kind = "amber", amount = 6 } },
	},
	{
		id = "bait_bundle",
		kind = "bait",
		name = "Bait Bundle",
		desc = "Five extra casts at the Fishing Pond.",
		amount = 5,
		weight = 12,
		limit = 2,
		unlock = "fishing",
		pay = { { kind = "coins", seconds = 600 }, { kind = "dishes", amount = 1 } },
	},
	{
		id = "bait_crate",
		kind = "bait",
		name = "Bait Crate",
		desc = "Fifteen extra casts at the Fishing Pond.",
		amount = 15,
		weight = 5,
		limit = 1,
		unlock = "fishing",
		pay = { { kind = "gems", amount = 45 }, { kind = "dishes", amount = 3 } },
	},
	{
		id = "shovel_bundle",
		kind = "shovels",
		name = "Shovel Bundle",
		desc = "Three extra digs at the Dig Site.",
		amount = 3,
		weight = 10,
		limit = 2,
		unlock = "dig_site",
		pay = { { kind = "coins", seconds = 900 }, { kind = "fish", amount = 3 } },
	},
	-- 3.12: a Trial Tower Retry token (TrialTower:AddRetries).
	{
		id = "tower_retry",
		kind = "tower_retry",
		name = "Retry Token",
		desc = "One more Trial Tower fight when today's attempts are out.",
		amount = 1,
		weight = 8,
		limit = 2,
		unlock = "trial_tower",
		pay = { { kind = "gems", amount = 30 }, { kind = "coins", seconds = 1200 } },
	},
	{
		id = "decor_a",
		kind = "decor",
		decor = 0, -- Merchant.Decor[(visit + 0) % #Decor + 1]
		amount = 1,
		weight = 10,
		limit = 1,
		pay = { { kind = "gems", amount = 120 }, { kind = "amber", amount = 12 } },
	},
	{
		id = "decor_b",
		kind = "decor",
		decor = 1,
		amount = 1,
		weight = 6,
		limit = 1,
		pay = { { kind = "coins", seconds = 3600 }, { kind = "dishes", amount = 4 } },
	},
	{
		id = "egg_basket",
		kind = "egg",
		eggs = { { id = "grove", weight = 3 }, { id = "crystal", weight = 2 } },
		amount = 1,
		weight = 10,
		limit = 1,
		pay = { { kind = "coins", seconds = 2400 }, { kind = "fish", amount = 6 } },
	},
	{
		id = "egg_royal",
		kind = "egg",
		eggs = { { id = "royal", weight = 1 } },
		amount = 1,
		weight = 3,
		limit = 1,
		pay = { { kind = "gems", amount = 150 }, { kind = "amber", amount = 20 } },
	},
}

Merchant.ById = {}
for _, offer in Merchant.Offers do
	assert(Merchant.ById[offer.id] == nil, "[Config.Merchant] duplicate offer " .. offer.id)
	assert(#offer.pay >= 1 and #offer.pay <= 2, "[Config.Merchant] 1 or 2 ways to pay: " .. offer.id)
	Merchant.ById[offer.id] = offer
end
Merchant.Ids = {}
for _, offer in Merchant.Offers do
	table.insert(Merchant.Ids, offer.id)
end

return Merchant
