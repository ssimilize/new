--[[
	Orders (update 3.8): Ranch Orders. The order rules (Logic/Orders: the seeded daily draw, the
	level gates, the gene checks, the egg roll, goods amounts) and the board on the server (the
	unlock, a rejoin that keeps the list, every refused hand-over, pay, goods, the daily reroll
	and the day rollover).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local OrdersLogic = t.Shared("Logic.Orders")
	local Formulas = t.Shared("Logic.Formulas")

	local Rules = Config.Orders
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

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Jobs", "Orders" }

	local function boot(level: number?)
		local h = TestKernel.new({ systems = SYSTEMS })
		local p = h:Join()
		levelTo(h, p, level or 10)
		return h, p, h:System("Monsters")
	end

	local function adult(M, p, fields)
		local spec = { line = "cindlet", rarity = 3, stage = 3, traits = { 7, 12 }, hidden = 9 }
		local g
		for k, v in fields or {} do
			if k == "genes" then
				g = v
			else
				spec[k] = v
			end
		end
		local m = M:Create(p, spec, "test", true)
		m.genes = g or genes()
		return m
	end

	local function spdOrder(grade: string?)
		return {
			id = "t-1",
			kind = "monster",
			difficulty = if grade == "C" then "easy" else "medium",
			stat = "spd",
			grade = grade or "B",
			seed = 11,
			filled = false,
		}
	end

	describe("Order rules", function()
		it("draws the same orders for the same player and day, and new ones the next day", function()
			local a = OrdersLogic.Draw(4242, 20000, 30)
			local b = OrdersLogic.Draw(4242, 20000, 30)
			expect(#a).toBe(Rules.PerDay)
			for i = 1, Rules.PerDay do
				expect(a[i].seed).toBe(b[i].seed)
				expect(a[i].kind).toBe(b[i].kind)
				expect(a[i].stat).toBe(b[i].stat)
				expect(a[i].egg).toBe(b[i].egg)
				expect(a[i].filled).toBe(false)
			end
			local c = OrdersLogic.Draw(4242, 20001, 30)
			local d = OrdersLogic.Draw(4243, 20000, 30)
			expect(c[1].seed ~= a[1].seed).toBe(true)
			expect(d[1].seed ~= a[1].seed).toBe(true)
		end)

		it("keeps Hard orders for Lv 20+ and posts at most one goods order a day", function()
			local seen = { low = {}, high = {} }
			local goodsDays = 0
			for day = 1, 400 do
				for key, level in { low = 10, high = 30 } do
					local goods = 0
					for _, order in OrdersLogic.Draw(99, day, level) do
						seen[key][order.difficulty] = true
						if order.kind == "goods" then
							goods += 1
							expect(Config.Food.ById[order.food] ~= nil).toBe(true)
						else
							expect(order.genesMin or order.twoStats or table.find(Config.Genetics.Stats, order.stat)).toBeTruthy()
						end
					end
					expect(goods <= 1).toBe(true)
					if goods == 1 then
						goodsDays += 1
					end
				end
			end
			expect(seen.low.hard).toBeNil()
			expect(seen.low.easy).toBe(true)
			expect(seen.low.medium).toBe(true)
			expect(seen.high.hard).toBe(true)
			expect(goodsDays).toBeGreaterThan(100)
		end)

		it("reads the requirement from the gene grades", function()
			local easy = spdOrder("C")
			local medium = spdOrder("B")
			expect(OrdersLogic.Qualifies(easy, { stage = 2, genes = genes({ spd = { 3, 2 } }) })).toBe(true)
			expect(OrdersLogic.Qualifies(easy, { stage = 2, genes = genes({ spd = { 2, 2 } }) })).toBe(false)
			expect(OrdersLogic.Qualifies(medium, { stage = 3, genes = genes({ spd = { 5, 5 } }) })).toBe(true)
			expect(OrdersLogic.Qualifies(medium, { stage = 3, genes = genes({ spd = { 5, 4 }, atk = { 10, 10 } }) })).toBe(false)
			expect(OrdersLogic.Qualifies(medium, { stage = 1, genes = genes({ spd = { 10, 10 } }) })).toBe(false)
			local two = { kind = "monster", difficulty = "hard", twoStats = { "hp", "def" }, grade = "B", seed = 1 }
			expect(OrdersLogic.Qualifies(two, { stage = 3, genes = genes({ hp = { 5, 5 }, def = { 6, 4 } }) })).toBe(true)
			expect(OrdersLogic.Qualifies(two, { stage = 3, genes = genes({ hp = { 5, 5 }, def = { 4, 4 } }) })).toBe(false)
			local total = { kind = "monster", difficulty = "hard", genesMin = 60, seed = 1 }
			local rich = {}
			for _, stat in Config.Genetics.Stats do
				rich[stat] = { 6, 6 }
			end
			expect(OrdersLogic.Qualifies(total, { stage = 3, genes = rich })).toBe(true)
			rich.luck = { 5, 6 }
			expect(OrdersLogic.Qualifies(total, { stage = 3, genes = rich })).toBe(false)
			expect(OrdersLogic.RequirementText(medium)).toBe("A Teen or Adult with SPD grade B or better")
		end)

		it("rolls a Hard order's egg about a quarter of the time, and Royal only from Lv 25", function()
			local hard, eggs, kinds = 0, 0, { [20] = {}, [30] = {} }
			for _, level in { 20, 30 } do
				for seed = 1, 4000 do
					local order = OrdersLogic.Make(seed * 7919, level, false)
					if order.difficulty == "hard" then
						hard += 1
						if order.egg then
							eggs += 1
							kinds[level][order.egg] = true
						end
						expect(OrdersLogic.Make(seed * 7919, level, false).egg).toBe(order.egg)
					else
						expect(order.egg).toBeNil()
					end
				end
			end
			expect(eggs / hard).toBeNear(Rules.EggChance, 0.04)
			expect(kinds[20].crystal).toBe(true)
			expect(kinds[20].royal).toBeNil()
			expect(kinds[30].royal).toBe(true)
		end)

		it("asks for more food at higher levels, 150-400, and pays 10-20 gems and 5-10 treats", function()
			local sums, counts = { [10] = 0, [60] = 0 }, { [10] = 0, [60] = 0 }
			for _, level in { 10, 60 } do
				for seed = 1, 2000 do
					local order = OrdersLogic.Make(seed * 104729, level, true)
					if order.kind == "goods" then
						expect(order.amount >= 150 and order.amount <= 400).toBe(true)
						sums[level] += order.amount
						counts[level] += 1
						local pay = OrdersLogic.Pay(order)
						expect(pay[1].kind).toBe("gems")
						expect(pay[1].amount >= 10 and pay[1].amount <= 20).toBe(true)
						expect(pay[2].kind).toBe("treats")
						expect(pay[2].amount >= 5 and pay[2].amount <= 10).toBe(true)
					end
				end
			end
			expect(counts[10]).toBeGreaterThan(200)
			expect(sums[60] / counts[60]).toBeGreaterThan(sums[10] / counts[10] + 150)
		end)
	end)

	describe("Ranch Orders", function()
		it("opens at Ranch Level 10 with the seeded list, which a rejoin keeps", function()
			local h, p = boot(9)
			expect(#h:Section(p, "Orders").list).toBe(0)
			expect(h:Reject(p, "Orders.Reroll", { index = 1 })).toContain("Ranch Level 10")
			levelTo(h, p, 10)
			local s = h:Section(p, "Orders")
			expect(#s.list).toBe(Rules.PerDay)
			local expected = OrdersLogic.Draw(p.UserId, s.day, 10)
			for i = 1, Rules.PerDay do
				expect(s.list[i].seed).toBe(expected[i].seed)
			end
			local seeds = { s.list[1].seed, s.list[2].seed, s.list[3].seed }
			local p2 = h:Rejoin(p, 60)
			local again = h:Section(p2, "Orders")
			for i = 1, Rules.PerDay do
				expect(again.list[i].seed).toBe(seeds[i])
			end
			expect(#h:Client(p2).profile.Orders.list).toBe(Rules.PerDay)
		end)

		it("refuses locked, busy, missing, too weak and Baby monsters, and the last monster", function()
			local h, p, M = boot()
			local s = h:Section(p, "Orders")
			s.list[1] = spdOrder("B")
			local good = adult(M, p, { genes = genes({ spd = { 5, 5 } }) })
			local weak = adult(M, p, { genes = genes({ spd = { 4, 4 } }) })
			local baby = adult(M, p, { stage = 1, genes = genes({ spd = { 9, 9 } }) })
			expect(h:Reject(p, "Orders.Fill", { index = 1 })).toContain("Choose a monster")
			expect(h:Reject(p, "Orders.Fill", { index = 1, id = "m999" })).toContain("doesn't exist")
			expect(h:Reject(p, "Orders.Fill", { index = 1, id = weak.id })).toContain("doesn't meet")
			expect(h:Reject(p, "Orders.Fill", { index = 1, id = baby.id })).toContain("Teens and Adults")
			h:Advance(2)
			good.locked = true
			expect(h:Reject(p, "Orders.Fill", { index = 1, id = good.id })).toContain("locked")
			good.locked = false
			M:SetBusy(p, good.id, "job")
			expect(h:Reject(p, "Orders.Fill", { index = 1, id = good.id })).toContain("busy")
			M:SetBusy(p, good.id, false)
			h:Advance(2)
			local list = h:Section(p, "Monsters").list
			for id in list do
				if id ~= good.id then
					list[id] = nil
				end
			end
			expect(h:Reject(p, "Orders.Fill", { index = 1, id = good.id })).toContain("at least one monster")
			expect(M:Get(p, good.id)).toBe(good)
			expect(s.list[1].filled).toBe(false)
		end)

		it("pays 3x the sell price, the gems, ribbons and egg, and the monster leaves for good", function()
			local h, p, M = boot()
			local s = h:Section(p, "Orders")
			s.list[1] = {
				id = "t-1",
				kind = "monster",
				difficulty = "hard",
				stat = "atk",
				grade = "A",
				seed = 5,
				egg = "crystal",
				filled = false,
			}
			adult(M, p)
			local m = adult(M, p, { rarity = 4, genes = genes({ atk = { 7, 7 } }) })
			local removed
			h.kernel.Bus:Subscribe("MonsterRemoved", function(_, detail)
				removed = detail
			end)
			local cur = h:Section(p, "Currency")
			local coins, gems, ribbons = cur.coins, cur.gems, cur.ribbons
			local eggs = h:System("Eggs"):Count(p)
			local price = Formulas.SellPrice(m)
			local res = h:Call(p, "Orders.Fill", { index = 1, id = m.id })
			expect(cur.coins - coins).toBe(Rules.CoinMult * price)
			expect(cur.gems - gems).toBe(Rules.Difficulty.hard.gems)
			expect(cur.ribbons - ribbons).toBe(Rules.Difficulty.hard.ribbons)
			expect(h:System("Eggs"):Count(p)).toBe(eggs + 1)
			expect(#res.rewards).toBe(4)
			expect(M:Get(p, m.id)).toBeNil()
			expect(removed.reason).toBe("order")
			expect(s.list[1].filled).toBe(true)
			expect(h:Reject(p, "Orders.Fill", { index = 1, id = adult(M, p).id })).toContain("already filled")
		end)

		it("spends the food of a goods order and pays its gems and treats", function()
			local h, p = boot()
			local order = { id = "t-2", kind = "goods", difficulty = "goods", food = "sour", amount = 200, seed = 77, filled = false }
			h:Section(p, "Orders").list[2] = order
			local cur = h:Section(p, "Currency")
			cur.food.sour = 150
			expect(h:Reject(p, "Orders.Fill", { index = 2 })).toContain("Not enough Zing Limes")
			h:System("Currency"):Add(p, "food.sour", 100, "test")
			local gems, treats = cur.gems, cur.treats
			local pay = OrdersLogic.Pay(order)
			h:Call(p, "Orders.Fill", { index = 2 })
			expect(cur.food.sour).toBe(50)
			expect(cur.gems - gems).toBe(pay[1].amount)
			expect(cur.treats - treats).toBe(pay[2].amount)
			expect(order.filled).toBe(true)
		end)

		it("rerolls one unfilled order once a day and draws new orders the next day", function()
			local h, p = boot()
			local s = h:Section(p, "Orders")
			local day = s.day
			local keep = s.list[1].seed
			local old = s.list[2].seed
			h:Call(p, "Orders.Reroll", { index = 2 })
			expect(s.list[2].seed).toBe(OrdersLogic.RerollSeed(p.UserId, day, 1))
			expect(s.list[2].seed ~= old).toBe(true)
			expect(s.list[1].seed).toBe(keep)
			expect(s.rerolls).toBe(1)
			expect(h:Reject(p, "Orders.Reroll", { index = 3 })).toContain("today's reroll")

			h:Advance(DAY)
			expect(s.day).toBe(day + 1)
			expect(s.rerolls).toBe(0)
			local expected = OrdersLogic.Draw(p.UserId, day + 1, 10)
			for i = 1, Rules.PerDay do
				expect(s.list[i].seed).toBe(expected[i].seed)
			end
			s.list[1].filled = true
			expect(h:Reject(p, "Orders.Reroll", { index = 1 })).toContain("already filled")
			h:Call(p, "Orders.Reroll", { index = 3 })
			expect(s.rerolls).toBe(1)
		end)

		it("never rerolls a second goods order into the day", function()
			local h, p = boot()
			local s = h:Section(p, "Orders")
			s.list[1] = { id = "t-3", kind = "goods", difficulty = "goods", food = "sweet", amount = 150, seed = 3, filled = false }
			-- Many rerolls in one day (the limit lifted for the test): a goods order would have come
			-- up if the guard were missing.
			local limit = Rules.RerollsPerDay
			Rules.RerollsPerDay = 1000
			local couldBeGoods = 0
			for n = 1, 60 do
				if OrdersLogic.Make(OrdersLogic.RerollSeed(p.UserId, s.day, n), 10, true).kind == "goods" then
					couldBeGoods += 1
				end
				h:Advance(1)
				h:Call(p, "Orders.Reroll", { index = 2 })
				expect(s.list[2].kind).toBe("monster")
			end
			Rules.RerollsPerDay = limit
			expect(couldBeGoods).toBeGreaterThan(0)
			expect(s.rerolls).toBe(60)
		end)
	end)
end
