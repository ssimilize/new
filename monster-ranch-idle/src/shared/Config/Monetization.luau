--[[
	Game passes, developer products and rewarded ads.
	Set `gamePassId` / `productId` after creating each item in the Creator Hub. Items with
	an id of 0 are shown in the store as "coming soon" and cannot be bought.

	Design rule: nothing here skips a timer. Robux buys parallel capacity, convenience,
	cosmetics and server-wide fun.
]]

local Monetization = {}

Monetization.Passes = {
	{ key = "autoCollect", name = "Auto-Collect", price = 149, gamePassId = 0, desc = "Coin jars collect themselves while you play." },
	{ key = "extraIncubator", name = "Extra Incubator", price = 199, gamePassId = 0, desc = "+1 incubator slot." },
	{ key = "bigBarn", name = "Big Barn", price = 199, gamePassId = 0, desc = "+100 monster storage." },
	{ key = "explorer", name = "Explorer", price = 249, gamePassId = 0, desc = "+1 expedition slot." },
	{ key = "breedingPod", name = "Breeding Pod", price = 249, gamePassId = 0, desc = "+1 breeding pod." },
	{ key = "vip", name = "VIP Rancher", price = 299, gamePassId = 0, desc = "+4 h coin jar cap, daily VIP crate, chat tag." },
	{
		key = "luckyHatcher",
		name = "Lucky Hatcher",
		price = 349,
		gamePassId = 0,
		desc = "Golden 1 in 30 and Rainbow 1 in 300 (instead of 1 in 40 and 1 in 400).",
	},
	{ key = "doubleCoins", name = "Double Coins", price = 399, gamePassId = 0, desc = "×2 coin income from every pen." },
}

-- grant: list of rewards, or `handler` = a key another system registers
-- (Monetization:RegisterProduct(handlerKey, fn)).
Monetization.Products = {
	{
		key = "starterPack",
		name = "Starter Pack",
		price = 99,
		productId = 0,
		oncePerAccount = true,
		grant = {
			{ kind = "egg", id = "crystal", amount = 1 },
			{ kind = "gems", amount = 300 },
			{ kind = "decor", id = "hay_bale", amount = 1 },
		},
	},
	{ key = "gems100", name = "100 Gems", price = 49, productId = 0, grant = { { kind = "gems", amount = 100 } } },
	{ key = "gems550", name = "550 Gems", price = 249, productId = 0, grant = { { kind = "gems", amount = 550 } } },
	{ key = "gems1200", name = "1,200 Gems", price = 499, productId = 0, grant = { { kind = "gems", amount = 1200 } } },
	{ key = "gems2600", name = "2,600 Gems", price = 999, productId = 0, grant = { { kind = "gems", amount = 2600 } } },
	{ key = "gems7000", name = "7,000 Gems", price = 2499, productId = 0, grant = { { kind = "gems", amount = 7000 } } },
	{ key = "totemRain", name = "Rain Totem", price = 49, productId = 0, handler = "Weather.Totem", args = { weather = "rain" } },
	{
		key = "totemThunder",
		name = "Thunderstorm Totem",
		price = 99,
		productId = 0,
		handler = "Weather.Totem",
		args = { weather = "thunderstorm" },
	},
	{
		key = "totemStarfall",
		name = "Starfall Totem",
		price = 249,
		productId = 0,
		handler = "Weather.Totem",
		args = { weather = "starfall" },
	},
	{ key = "ranchPass", name = "Ranch Pass (season)", price = 399, productId = 0, handler = "Quests.RanchPass" },
}

Monetization.PassByKey = {}
Monetization.PassById = {}
for _, p in Monetization.Passes do
	Monetization.PassByKey[p.key] = p
	if p.gamePassId ~= 0 then
		Monetization.PassById[p.gamePassId] = p
	end
end
Monetization.ProductByKey = {}
Monetization.ProductById = {}
for _, p in Monetization.Products do
	Monetization.ProductByKey[p.key] = p
	if p.productId ~= 0 then
		Monetization.ProductById[p.productId] = p
	end
end

-- Rewarded video ad placements and daily caps.
Monetization.Ads = {
	welcomeDouble = { cap = 4, desc = "×2 coins from your offline total" },
	hatchRush = { cap = 3, desc = "−15 minutes on one incubator", seconds = 900 },
	freeEgg = { cap = 1, desc = "A free Grove Egg", egg = "grove" },
	stageRetry = { cap = 5, desc = "Retry with +20% stats", statBonus = 0.2 },
}

-- Gems → Starlit eggs count as paid random items where restricted.
Monetization.PaidRandomEggs = { starlit = true }

-- Developer product receipts kept per player for idempotent ProcessReceipt (newest kept).
Monetization.ReceiptHistory = 200

return Monetization
