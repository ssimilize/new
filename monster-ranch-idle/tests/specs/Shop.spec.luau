-- S3 Shop: global restock, egg purchases (unlocks, stock, events, paid random, storage),
-- food, decor, themes and the daily free egg.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Restock = t.Shared("Logic.Restock")

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "WelcomeBack" }

	local function fakeMonetization()
		local m = { passes = {}, adResult = true, ads = {}, paidRandom = true }
		function m:HasPass(_player, key)
			return self.passes[key] == true
		end
		function m:WatchAd(_player, placement)
			table.insert(self.ads, placement)
			return self.adResult
		end
		function m:PaidRandomAllowed(_player)
			return self.paidRandom
		end
		return m
	end

	local function boot(opts)
		local o = opts or {}
		local stubs = {}
		local money
		if o.monetization ~= false then
			money = fakeMonetization()
			stubs.Monetization = money
		end
		local h = TestKernel.new({ systems = SYSTEMS, stubs = stubs, startTime = o.startTime })
		local p = h:Join()
		return h, p, money
	end

	local function levelTo(h, p, level: number)
		local s = h:Section(p, "Progression")
		local need = -s.xp
		for l = s.level, level - 1 do
			need += Config.Unlocks.XPToNext(l)
		end
		h:System("Progression"):AddXP(p, need, "test")
	end

	local function coins(h, p, n)
		h:System("Currency"):Add(p, "coins", n, "test")
	end

	-- Runs `fn` with an event active, restoring the flag even if it fails.
	local function withEvent(eventId, fn)
		local before = Config.Flags.ActiveEvent
		Config.Flags.ActiveEvent = eventId
		local ok, err = pcall(fn)
		Config.Flags.ActiveEvent = before
		assert(ok, err)
	end

	-- A window where the Grove Egg has stock (it always does) and the Crystal Egg doesn't.
	local function windowWith(predicate)
		for w = 5966667, 5966667 + 500 do
			if predicate(Restock.Roll(w)) then
				return w * Config.Eggs.RestockSeconds + 1
			end
		end
		error("no matching window")
	end

	describe("Shop", function()
		it("publishes the same global stock on every server", function()
			local h1, p1 = boot()
			local h2, p2 = boot()
			local g1, g2 = h1:Client(p1).global.Shop, h2:Client(p2).global.Shop
			local window = Restock.Window(h1.adapters.Clock.Now())
			expect(g1).toEqual(g2)
			expect(g1.window).toBe(window)
			expect(g1.endsAt).toBe(Restock.EndsAt(window))
			expect(g1.stock).toEqual(Restock.Roll(window))
			expect(g1.stock.meadow).toBe(-1)
			expect(g1.stock.stampede).toBeNil()
		end)

		it("restocks on the global clock and resets each player's allowance", function()
			local h, p = boot()
			local g = h:Client(p).global.Shop
			local window = g.window
			h:Section(p, "Shop").bought.grove = 2
			h:Advance(g.endsAt - h.adapters.Clock.Now() + 1)
			local client = h:Client(p)
			expect(client.global.Shop.window).toBe(window + 1)
			expect(client.global.Shop.stock).toEqual(Restock.Roll(window + 1))
			expect(client.profile.Shop.bought).toEqual({})
			expect(client.profile.Shop.window).toBe(window + 1)
		end)

		it("buys unlimited eggs for coins and grants XP", function()
			local h, p = boot()
			local bought, xp = nil, 0
			h.kernel.Bus:Subscribe("EggBought", function(_, d)
				bought = d
			end)
			h.kernel.Bus:Subscribe("RanchXP", function(_, d)
				if d.reason == "buyEgg" then
					xp += d.amount
				end
			end)
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "meadow", amount = 1 })).toBe("Not enough coins")
			coins(h, p, 400)
			local data = h:Call(p, "Shop.BuyEgg", { egg = "meadow", amount = 2 })
			expect(#data.eggs).toBe(2)
			expect(h:Section(p, "Currency").coins).toBe(100)
			expect(h:System("Eggs"):Count(p)).toBe(2)
			expect(bought).toEqual({ type = "meadow", amount = 2 })
			expect(xp).toBe(Config.Unlocks.XP.buyEgg * 2)
			expect(h:Client(p).profile.Eggs.list[data.eggs[1]].source).toBe("shop")
		end)

		it("requires the egg's unlock level", function()
			local h, p = boot()
			coins(h, p, 1e6)
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "grove", amount = 1 })).toBe("Unlocks at Ranch Level 3")
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "royal", amount = 1 })).toBe("Unlocks at Ranch Level 25")
			expect(h:Section(p, "Currency").coins).toBe(1e6)
		end)

		it("sells limited stock per player per restock", function()
			local start = windowWith(function(stock)
				return stock.crystal == 0 and stock.grove >= 3
			end)
			local h, p = boot({ startTime = start })
			local q = h:Join()
			levelTo(h, p, 10)
			levelTo(h, q, 3)
			coins(h, p, 1e7)
			coins(h, q, 1e6)
			local stock = h:Client(p).global.Shop.stock
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "crystal", amount = 1 })).toContain("Sold out")
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "grove", amount = stock.grove + 1 })).toBe(
				string.format("Only %d left in this restock", stock.grove)
			)
			h:Call(p, "Shop.BuyEgg", { egg = "grove", amount = stock.grove - 1 })
			h:Advance(1)
			h:Call(p, "Shop.BuyEgg", { egg = "grove", amount = 1 })
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "grove", amount = 1 })).toContain("Sold out")
			-- Stock is an allowance: the other player still gets the full amount.
			expect(#h:Call(q, "Shop.BuyEgg", { egg = "grove", amount = stock.grove }).eggs).toBe(stock.grove)
			-- The next restock refills it.
			h:Advance(Config.Eggs.RestockSeconds)
			expect(h:Section(p, "Shop").bought.grove).toBeNil()
		end)

		it("only sells event eggs during their event", function()
			local h, p = boot()
			h:System("Currency"):Add(p, "token.frostfall", 1000, "test")
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "stampede", amount = 1 })).toContain("isn't sold")
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "frostfall", amount = 1 })).toContain("isn't available right now")
			withEvent("frostfall", function()
				h:Advance(1) -- the shop notices the event on its next tick
				expect(h:Client(p).global.Shop.stock.frostfall).toBe(-1)
				h:Call(p, "Shop.BuyEgg", { egg = "frostfall", amount = 2 })
				expect(h:System("Currency"):Balance(p, "token.frostfall")).toBe(200)
			end)
			h:Advance(1)
			expect(h:Client(p).global.Shop.stock.frostfall).toBeNil()
		end)

		it("hides paid random eggs where they are restricted", function()
			local h, p, money = boot()
			levelTo(h, p, 5)
			h:System("Currency"):Add(p, "gems", 1000, "test")
			money.paidRandom = false
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "starlit", amount = 1 })).toContain("isn't available for your account")
			money.paidRandom = true
			h:Call(p, "Shop.BuyEgg", { egg = "starlit", amount = 2 })
			expect(h:Section(p, "Currency").gems).toBe(700)
		end)

		it("falls back to PolicyService without Monetization", function()
			local h, p = boot({ monetization = false })
			levelTo(h, p, 5)
			h:System("Currency"):Add(p, "gems", 1000, "test")
			h.adapters.restrictedPaidRandom[p.UserId] = true
			local q = h:Join()
			levelTo(h, q, 5)
			h:System("Currency"):Add(q, "gems", 1000, "test")
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "starlit", amount = 1 })).toContain("isn't available")
			h:Call(q, "Shop.BuyEgg", { egg = "starlit", amount = 1 })
		end)

		it("refuses purchases that would overflow egg storage", function()
			local h, p = boot()
			coins(h, p, 1e6)
			h:System("Eggs"):Add(p, "meadow", "test", Config.Economy.MaxEggs - 1)
			expect(h:Reject(p, "Shop.BuyEgg", { egg = "meadow", amount = 2 })).toContain("storage is full")
			h:Call(p, "Shop.BuyEgg", { egg = "meadow", amount = 1 })
			expect(h:Section(p, "Currency").coins).toBe(1e6 - 150)
		end)

		it("sells food for coins", function()
			local h, p = boot()
			coins(h, p, 100)
			h:Call(p, "Shop.BuyFood", { flavor = "sweet", amount = 5 })
			expect(h:Section(p, "Currency").food.sweet).toBe(5)
			expect(h:Section(p, "Currency").coins).toBe(100 - 5 * Config.Economy.FoodPrice)
			expect(h:Reject(p, "Shop.BuyFood", { flavor = "sour", amount = 1 })).toBe("Not enough coins")
			expect(h:Reject(p, "Shop.BuyFood", { flavor = "salty", amount = 1 })).toBe("BadRequest")
		end)

		it("sells decor for its currency and keeps it in storage", function()
			local h, p = boot()
			local Shop = h:System("Shop")
			coins(h, p, 600)
			h:Call(p, "Shop.BuyDecor", { decor = "hay_bale" })
			expect(Shop:DecorCount(p, "hay_bale")).toBe(1)
			expect(h:Client(p).profile.Shop.decor.hay_bale).toBe(1)
			expect(h:Reject(p, "Shop.BuyDecor", { decor = "mud_puddle" })).toBe("Not enough Friendship Points")
			h:System("Currency"):Add(p, "friendship", 40, "test")
			h:Call(p, "Shop.BuyDecor", { decor = "mud_puddle" })
			expect(h:Section(p, "Currency").friendship).toBe(0)
			expect(h:Reject(p, "Shop.BuyDecor", { decor = "snow_globe" })).toContain("isn't available right now")
			-- Public storage API used by Ranch and Rewards.
			expect(Shop:TakeDecor(p, "hay_bale")).toBe(true)
			expect(Shop:TakeDecor(p, "hay_bale")).toBe(false)
			Shop:ReturnDecor(p, "hay_bale")
			Shop:AddDecor(p, "lantern", 2)
			expect(Shop:DecorCount(p, "hay_bale")).toBe(1)
			expect(Shop:DecorCount(p, "lantern")).toBe(2)
		end)

		it("sells pen themes once", function()
			local h, p = boot()
			local Shop = h:System("Shop")
			expect(Shop:OwnsTheme(p, "wood")).toBe(true)
			expect(Shop:OwnsTheme(p, "stone")).toBe(false)
			expect(h:Reject(p, "Shop.BuyTheme", { theme = "wood" })).toContain("already own")
			expect(h:Reject(p, "Shop.BuyTheme", { theme = "stone" })).toBe("Not enough gems")
			h:System("Currency"):Add(p, "gems", 500, "test")
			h:Call(p, "Shop.BuyTheme", { theme = "stone" })
			expect(Shop:OwnsTheme(p, "stone")).toBe(true)
			expect(h:Section(p, "Currency").gems).toBe(300)
			h:Advance(1)
			expect(h:Reject(p, "Shop.BuyTheme", { theme = "stone" })).toContain("already own")
			expect(h:Reject(p, "Shop.BuyTheme", { theme = "snowglobe" })).toContain("isn't available right now")
		end)

		it("gives one free egg per day for an ad", function()
			local h, p, money = boot()
			money.adResult = false
			expect(h:Reject(p, "Shop.ClaimFreeEgg")).toBe("The ad didn't finish")
			money.adResult = true
			h:Advance(1)
			local data = h:Call(p, "Shop.ClaimFreeEgg")
			expect(data.type).toBe(Config.Monetization.Ads.freeEgg.egg)
			expect(h:System("Eggs"):Get(p, data.egg).type).toBe("grove")
			h:Advance(1)
			expect(h:Reject(p, "Shop.ClaimFreeEgg")).toContain("already claimed")
			expect(money.ads).toEqual({ "freeEgg", "freeEgg" })
			h.adapters.advance(86400)
			h:Advance(1)
			h:Call(p, "Shop.ClaimFreeEgg")
			expect(h:System("Eggs"):Count(p)).toBe(2)
			local h2, q = boot({ monetization = false })
			expect(h2:Reject(q, "Shop.ClaimFreeEgg")).toBe("Ads aren't available")
		end)
	end)
end
