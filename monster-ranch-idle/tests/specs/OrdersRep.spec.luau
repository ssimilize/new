--[[
	OrdersRep (update 3.9): buyer reputation for Ranch Orders. The rules (Logic/Orders: buyer ids
	that match the 3.8 seed pick, points per difficulty, levels, the coin bonus, the 40% egg
	chance compared with the same roll, the favourite buyer) and the board on the server (the
	bonus in the fill payout, the level-up toast, the thank-you gift and the decor paid once, the
	favourite buyer order from its own seed at most once a day, and the version-1 migration).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local OrdersLogic = t.Shared("Logic.Orders")
	local Formulas = t.Shared("Logic.Formulas")

	local Rules = Config.Orders
	local Rep = Rules.Rep
	local DAY = 86400

	local function genes(overrides)
		local g = {}
		for _, stat in Config.Genetics.Stats do
			g[stat] = { 1, 1 }
		end
		for stat, pair in overrides or {} do
			g[stat] = pair
		end
		return g
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Shop", "Jobs", "Orders" }

	local function boot(level: number?)
		local h = TestKernel.new({ systems = SYSTEMS })
		local p = h:Join()
		levelTo(h, p, level or 10)
		return h, p, h:System("Monsters")
	end

	local function adult(M, p, spd: number?, rarity: number?)
		local m = M:Create(p, { line = "cindlet", rarity = rarity or 3, stage = 3, traits = { 7, 12 }, hidden = 9 }, "test", true)
		m.genes = genes({ spd = { spd or 5, spd or 5 } })
		return m
	end

	-- A medium SPD-B order from `buyer` (2 points).
	local function order(buyer: string, difficulty: string?)
		return {
			id = "t-" .. buyer,
			kind = "monster",
			difficulty = difficulty or "medium",
			stat = "spd",
			grade = "B",
			seed = 11,
			buyer = buyer,
			filled = false,
		}
	end

	-- Fills list[1] with a fresh qualifying monster; returns the monster's pay without a bonus.
	local function fillOne(h, p, M, o)
		local s = h:Section(p, "Orders")
		s.list[1] = o
		adult(M, p)
		local m = adult(M, p)
		local base = Rules.CoinMult * Formulas.SellPrice(m)
		h:Advance(1)
		h:Call(p, "Orders.Fill", { index = 1, id = m.id })
		return base
	end

	local function notes(h, p)
		local list = {}
		for _, e in h:Events(p, "Kernel.Notify") do
			table.insert(list, e.payload.text)
		end
		return list
	end

	describe("Buyer reputation rules", function()
		it("gives each buyer a stable id and keeps the 3.8 buyer of every seed", function()
			expect(#Rules.BuyerIds).toBe(#Rules.Buyers)
			for i, id in { "rosa", "pip", "milo", "wren", "ada", "juno", "tam", "hale" } do
				expect(Rules.BuyerIds[i]).toBe(id)
				expect(Rules.BuyerById[id].name).toBe(Rules.Buyers[i])
			end
			for _, o in OrdersLogic.Draw(4242, 20000, 30) do
				local index = (o.seed % #Rules.Buyers) + 1
				expect(o.buyer).toBe(Rules.BuyerIds[index])
				expect(OrdersLogic.Buyer(o)).toBe(Rules.Buyers[index])
			end
			-- A 3.8 order saved without an id reads the same buyer from its seed.
			local old = { seed = 13, kind = "monster", difficulty = "easy" }
			expect(OrdersLogic.BuyerId(old)).toBe(Rules.BuyerIds[(13 % 8) + 1])
			expect(OrdersLogic.Buyer(old)).toBe(Rules.Buyers[(13 % 8) + 1])
		end)

		it("earns 1 / 2 / 4 / 2 points and levels at 5, 15, 35 and 70", function()
			expect(OrdersLogic.RepPoints({ difficulty = "easy" })).toBe(1)
			expect(OrdersLogic.RepPoints({ difficulty = "medium" })).toBe(2)
			expect(OrdersLogic.RepPoints({ difficulty = "hard" })).toBe(4)
			expect(OrdersLogic.RepPoints({ difficulty = "goods" })).toBe(2)
			local cases = { [0] = 0, [4] = 0, [5] = 1, [14] = 1, [15] = 2, [34] = 2, [35] = 3, [69] = 3, [70] = 4, [500] = 4 }
			for points, level in cases do
				expect(OrdersLogic.RepLevel(points)).toBe(level)
			end
			local level, from, to = OrdersLogic.RepProgress(20)
			expect(level).toBe(2)
			expect(from).toBe(15)
			expect(to).toBe(35)
			level, from, to = OrdersLogic.RepProgress(80)
			expect(level).toBe(4)
			expect(from).toBe(70)
			expect(to).toBeNil()
			expect(OrdersLogic.CoinBonus(0)).toBe(0)
			expect(OrdersLogic.CoinBonus(1)).toBe(0.1)
			expect(OrdersLogic.CoinBonus(2)).toBe(0.1)
			expect(OrdersLogic.CoinBonus(3)).toBe(0.25)
			expect(OrdersLogic.CoinBonus(4)).toBe(0.25)
			expect(#Rep.Perks).toBe(#Rep.Levels)
		end)

		it("leaves the day's draw unchanged whatever the reputation", function()
			local rep = {}
			for _, id in Rules.BuyerIds do
				rep[id] = 70
			end
			for day = 1, 50 do
				local a = OrdersLogic.Draw(77, day, 30)
				local b = OrdersLogic.Draw(77, day, 30, rep)
				for i = 1, Rules.PerDay do
					expect(b[i].seed).toBe(a[i].seed)
					expect(b[i].kind).toBe(a[i].kind)
					expect(b[i].difficulty).toBe(a[i].difficulty)
					expect(b[i].stat).toBe(a[i].stat)
					expect(b[i].food).toBe(a[i].food)
					expect(b[i].amount).toBe(a[i].amount)
				end
			end
		end)

		it("rolls a level-2 buyer's Hard eggs at 40% from the same roll, deterministically", function()
			local hard, base, boosted = 0, 0, 0
			for seed = 1, 4000 do
				local plain = OrdersLogic.Make(seed, 30, false)
				if plain.difficulty == "hard" then
					hard += 1
					local rep = { [plain.buyer] = 15 }
					local o = OrdersLogic.Make(seed, 30, false, rep)
					local again = OrdersLogic.Make(seed, 30, false, rep)
					expect(again.egg).toBe(o.egg)
					expect(o.genesMin).toBe(plain.genesMin)
					expect(o.stat).toBe(plain.stat)
					if plain.egg then
						base += 1
						-- The same roll against a higher chance: every base egg stays.
						expect(o.egg).toBe(plain.egg)
					end
					if o.egg then
						boosted += 1
					end
					-- Level 1 is still 25%.
					expect(OrdersLogic.Make(seed, 30, false, { [plain.buyer] = 5 }).egg).toBe(plain.egg)
				end
			end
			expect(hard).toBeGreaterThan(500)
			expect(base / hard).toBeNear(0.25, 0.05)
			expect(boosted / hard).toBeNear(0.40, 0.05)
		end)

		it("picks the favourite from level 3+ buyers, the most points first and ties by id", function()
			expect(OrdersLogic.Favourite({})).toBeNil()
			expect(OrdersLogic.Favourite({ rosa = 34, hale = 20 })).toBeNil()
			expect(OrdersLogic.Favourite({ rosa = 35, hale = 60 })).toBe("hale")
			expect(OrdersLogic.Favourite({ tam = 40, pip = 40, rosa = 40 })).toBe("pip")
			local fav = OrdersLogic.DrawFavourite(5, 300, 30, { juno = 50 })
			expect(fav.buyer).toBe("juno")
			expect(fav.favourite).toBe(true)
			expect(fav.kind).toBe("monster")
			expect(fav.id).toBe("300-fav")
			local rng = t.Shared("Logic.Rng")
			local expectSeed = rng.new(OrdersLogic.FavSeed(5, 300)):Int(1, 2147483646)
			expect(fav.seed).toBe(expectSeed)
			expect(OrdersLogic.DrawFavourite(5, 300, 30, { juno = 20 })).toBeNil()
		end)
	end)

	describe("Buyer reputation on the board", function()
		it("adds the buyer's coin bonus to the fill payout and earns its points", function()
			local h, p, M = boot()
			local s = h:Section(p, "Orders")
			local cur = h:Section(p, "Currency")

			local coins = cur.coins
			local base = fillOne(h, p, M, order("rosa"))
			expect(cur.coins - coins).toBe(base)
			expect(s.rep.rosa).toBe(2)

			s.rep.rosa = 5 -- level 1: +10%
			coins = cur.coins
			base = fillOne(h, p, M, order("rosa"))
			expect(cur.coins - coins).toBe(math.floor(base * 1.1 + 0.5))
			expect(s.rep.rosa).toBe(7)

			s.rep.wren = 40 -- level 3: +25%
			s.gifts.wren = 2
			coins = cur.coins
			base = fillOne(h, p, M, order("wren", "hard"))
			expect(cur.coins - coins).toBe(math.floor(base * 1.25 + 0.5))
			expect(s.rep.wren).toBe(44)

			-- Goods orders earn 2 points for their buyer too.
			s.list[2] =
				{ id = "g", kind = "goods", difficulty = "goods", food = "sour", amount = 150, seed = 3, buyer = "ada", filled = false }
			h:System("Currency"):Add(p, "food.sour", 150, "test")
			h:Call(p, "Orders.Fill", { index = 2 })
			expect(s.rep.ada).toBe(2)
			for _, text in notes(h, p) do
				expect(string.find(text, "buyer!", 1, true)).toBeNil()
			end
			expect(h:Client(p).profile.Orders.rep.ada).toBe(2)
		end)

		it("toasts a new level and pays the level-2 thank-you gift exactly once", function()
			local h, p, M = boot()
			local s = h:Section(p, "Orders")
			local cur = h:Section(p, "Currency")
			s.rep.pip = 3
			fillOne(h, p, M, order("pip"))
			expect(table.find(notes(h, p), "Chef Pip is now a level 1 buyer!") ~= nil).toBe(true)
			expect(s.gifts.pip).toBeNil()

			s.rep.pip = 13
			local gems = cur.gems
			local food = table.clone(cur.food)
			fillOne(h, p, M, order("pip"))
			expect(s.rep.pip).toBe(15)
			expect(table.find(notes(h, p), "Chef Pip is now a level 2 buyer!") ~= nil).toBe(true)
			expect(cur.gems - gems).toBe(Rules.Difficulty.medium.gems + 20)
			local gained = 0
			for id, n in cur.food do
				gained += n - (food[id] or 0)
			end
			expect(gained).toBe(20)
			expect(s.gifts.pip).toBe(2)

			-- Dropping back under the level and climbing again pays nothing more.
			s.rep.pip = 13
			gems = cur.gems
			fillOne(h, p, M, order("pip"))
			expect(cur.gems - gems).toBe(Rules.Difficulty.medium.gems)
			expect(s.gifts.pip).toBe(2)
		end)

		it("grants the buyer's decor piece once at level 4", function()
			local h, p, M = boot()
			local s = h:Section(p, "Orders")
			local Shop = h:System("Shop")
			s.rep.hale = 68
			s.gifts.hale = 2
			fillOne(h, p, M, order("hale"))
			expect(s.rep.hale).toBe(70)
			expect(Shop:DecorCount(p, "rep_telescope")).toBe(1)
			expect(s.gifts.hale).toBe(4)
			s.rep.hale = 68
			fillOne(h, p, M, order("hale"))
			expect(Shop:DecorCount(p, "rep_telescope")).toBe(1)

			-- A buyer who reaches level 4 without the level-2 gift gets both, once each.
			s.rep.tam = 68
			local gems = h:Section(p, "Currency").gems
			fillOne(h, p, M, order("tam"))
			expect(Shop:DecorCount(p, "rep_lookout_sign")).toBe(1)
			expect(h:Section(p, "Currency").gems - gems).toBe(Rules.Difficulty.medium.gems + 20)
			expect(s.gifts.tam).toBe(4)
		end)

		it("has one never-sold decor piece per buyer", function()
			for _, id in Rules.BuyerIds do
				local def = Config.Decor.ById[Rules.BuyerById[id].decor]
				expect(def ~= nil).toBe(true)
				expect(def.price).toBeNil()
				expect(def.reward).toBe("orders_rep")
			end
		end)

		it("posts the favourite buyer order from its own seed, once a day, only for level 3+", function()
			local h, p, M = boot(9)
			local s = h:Section(p, "Orders")
			s.rep = { rosa = 40, pip = 40, tam = 20 }
			levelTo(h, p, 10)
			expect(#s.list).toBe(Rules.PerDay + 1)
			local normal = OrdersLogic.Draw(p.UserId, s.day, 10)
			for i = 1, Rules.PerDay do
				expect(s.list[i].seed).toBe(normal[i].seed)
			end
			local fav = s.list[Rules.PerDay + 1]
			expect(fav.buyer).toBe("pip")
			expect(fav.favourite).toBe(true)
			expect(fav.seed).toBe(OrdersLogic.DrawFavourite(p.UserId, s.day, 10, s.rep).seed)
			expect(s.favDay).toBe(s.day)

			-- It can be filled but never rerolled, and filling it posts no second one.
			expect(h:Reject(p, "Orders.Reroll", { index = Rules.PerDay + 1 }) ~= nil).toBe(true)
			local m = adult(M, p, 9)
			adult(M, p)
			fav.kind, fav.difficulty, fav.stat, fav.grade = "monster", "medium", "spd", "B"
			fav.twoStats, fav.genesMin = nil, nil
			h:Call(p, "Orders.Fill", { index = Rules.PerDay + 1, id = m.id })
			expect(fav.filled).toBe(true)
			expect(#s.list).toBe(Rules.PerDay + 1)
			local p2 = h:Rejoin(p, 60)
			expect(#h:Section(p2, "Orders").list).toBe(Rules.PerDay + 1)

			-- The next day brings the normal 3 and a new favourite order.
			h:Advance(DAY)
			s = h:Section(p2, "Orders")
			expect(#s.list).toBe(Rules.PerDay + 1)
			expect(s.list[Rules.PerDay + 1].filled).toBe(false)
			expect(s.list[Rules.PerDay + 1].id).toBe(string.format("%d-fav", s.day))
		end)

		it("posts no favourite order below level 3, and one the same day a buyer reaches it", function()
			local h, p, M = boot()
			local s = h:Section(p, "Orders")
			expect(#s.list).toBe(Rules.PerDay)
			s.rep.juno = 33
			fillOne(h, p, M, order("juno"))
			expect(s.rep.juno).toBe(35)
			expect(#s.list).toBe(Rules.PerDay + 1)
			expect(s.list[Rules.PerDay + 1].buyer).toBe("juno")
			-- Still one a day: another buyer reaching level 3 adds nothing.
			s.rep.milo = 33
			s.list[2] = order("milo")
			s.list[2].id = "t-milo2"
			adult(M, p)
			local m = adult(M, p)
			h:Advance(1)
			h:Call(p, "Orders.Fill", { index = 2, id = m.id })
			expect(s.rep.milo).toBe(35)
			expect(#s.list).toBe(Rules.PerDay + 1)
			expect(s.list[Rules.PerDay + 1].buyer).toBe("juno")
		end)

		it("migrates a version-1 save and keeps its drawn orders and their buyers", function()
			local h = boot()
			local Orders = h:System("Orders")
			expect(Orders.Profile.Version).toBe(2)
			local list = { { id = "9-1", kind = "monster", difficulty = "easy", stat = "spd", grade = "C", seed = 21, filled = false } }
			local migrated = Orders.Profile.Migrate({ day = 9, list = list, rerolls = 1 }, 1)
			expect(migrated.day).toBe(9)
			expect(migrated.rerolls).toBe(1)
			expect(migrated.list[1].seed).toBe(21)
			expect(next(migrated.rep)).toBeNil()
			expect(next(migrated.gifts)).toBeNil()
			expect(migrated.favDay).toBe(0)
			expect(OrdersLogic.BuyerId(migrated.list[1])).toBe(Rules.BuyerIds[(21 % 8) + 1])
		end)
	end)
end
