--[[
	Apiary (update 3.12 · Honey & stars) on the server: the hive rules (Logic/Apiary: rate by SPD,
	the Sprout bonus, the cap, the season split), unlock gates per hive, keepers (busy tag, Adults
	only, unassign), offline accrual with its Welcome Back line, Royal Jelly seeded per player and
	collect, the HoneyCollected topic, selling, Kitchen honey recipes and the Royal Jelly dish, the
	Merchant's honey barter, the weekly goal honey_40 and the Rewards kind honey.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Apiary")
	local Seasons = t.Shared("Logic.Seasons")
	local Objectives = t.Shared("Logic.Objectives")
	local Formulas = t.Shared("Logic.Formulas")
	local MerchantLogic = t.Shared("Logic.Merchant")

	local Rules = Config.Apiary
	local HOUR = 3600
	local START = 1790000000

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Apiary" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(opts)
		opts = opts or {}
		local systems = table.clone(opts.systems or SYSTEMS)
		local h = TestKernel.new({ systems = systems, startTime = opts.at or START, stubs = opts.stubs })
		local p = h:Join(opts.userId)
		levelTo(h, p, opts.level or 14)
		return h, p
	end

	-- A line with (or without) the Sprout element, picked the same way every run.
	local function lineWith(sprout: boolean): string
		local ids = {}
		for id, def in Config.Species.ById do
			if table.find(def.elements, "sprout") ~= nil == sprout then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		return ids[1]
	end

	local function adult(h, p, fields)
		local spec = { line = lineWith(false), rarity = 3, stage = 3, traits = {}, hidden = 0 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return h:System("Monsters"):Create(p, spec, "test", true)
	end

	local function topics(h, name: string)
		local seen = {}
		h.kernel.Bus:Subscribe(name, function(_, detail)
			table.insert(seen, detail)
		end)
		return seen
	end

	describe("Apiary rules", function()
		it("has four honey kinds, one per season, and Royal Jelly in the same store", function()
			expect(Rules.Ids).toEqual({ "blossom", "clover", "heather", "frost" })
			expect(Rules.AllIds[5]).toBe("royal_jelly")
			for _, def in Config.Seasons.List do
				expect(Rules.BySeason[def.id] ~= nil).toBe(true)
			end
			expect(Logic.HiveCount(function(key)
				return key == "apiary" or key == "apiary_hive_2"
			end)).toBe(2)
			expect(Logic.HiveCount(function()
				return false
			end)).toBe(0)
		end)

		it("rates a keeper by SPD like the Job Board (√W), with +25% for Sprout monsters", function()
			local plain = { id = "a", line = lineWith(false), rarity = 3, stage = 3, lv = 10, traits = {}, hidden = 0 }
			local sprout = { id = "b", line = lineWith(true), rarity = 3, stage = 3, lv = 10, traits = {}, hidden = 0 }
			local w = (Formulas.Stats(plain).spd or 0) / Config.Jobs.RefBase.spd
			expect(math.abs(Logic.PerHour(plain) - Rules.BasePerHour * math.sqrt(w)) < 1e-9).toBe(true)
			local ws = (Formulas.Stats(sprout).spd or 0) / Config.Jobs.RefBase.spd
			expect(math.abs(Logic.PerHour(sprout) - Rules.BasePerHour * math.sqrt(ws) * Rules.SproutBonus) < 1e-9).toBe(true)
			expect(Logic.Cap(plain)).toBe(Logic.PerHour(plain) * Rules.CapHours)
			expect(Logic.Cap(plain, 4)).toBe(Logic.PerHour(plain) * (Rules.CapHours + 4))
		end)

		it("stops at the cap and splits a stretch across the season turnover", function()
			local m = { id = "a", line = lineWith(false), rarity = 5, stage = 3, lv = 20, traits = {}, hidden = 0 }
			local now = START
			local hive = { monster = "a", at = now, stored = {} }
			local full = Logic.Settle(hive, m, now + 30 * HOUR)
			expect(math.abs(Logic.Total(full) - Logic.Cap(m)) < 1e-6).toBe(true)
			expect(Logic.SecondsToFull(hive, m, now + 30 * HOUR)).toBe(0)

			local turn = Seasons.At(now).endsAt
			local before, after = Logic.KindAt(turn - 1), Logic.KindAt(turn)
			expect(before ~= after).toBe(true)
			local split = Logic.Settle({ monster = "a", at = turn - HOUR, stored = {} }, m, turn + HOUR)
			local rate = Logic.PerHour(m)
			expect(math.abs(split[before] - rate) < 1e-6).toBe(true)
			expect(math.abs(split[after] - rate) < 1e-6).toBe(true)

			local whole, rest = Logic.Take({ clover = 2.5, frost = 0.25 })
			expect(whole).toEqual({ clover = 2 })
			expect(rest).toEqual({ clover = 0.5, frost = 0.25 })
		end)
	end)

	describe("Apiary server", function()
		it("opens hive 1 at Level 14, hive 2 at 27 and hive 3 at 42", function()
			local h, p = boot({ level = 13 })
			local a = adult(h, p)
			expect(string.find(h:Reject(p, "Apiary.Assign", { hive = 1, id = a.id }), "14") ~= nil).toBe(true)
			levelTo(h, p, 14)
			expect(h:Session(p, "Apiary").hives).toBe(1)
			expect(h:Reject(p, "Apiary.Assign", { hive = 2, id = a.id })).toBe("Beehive 2 opens at Ranch Level 27")
			h:Advance(2)
			h:Call(p, "Apiary.Assign", { hive = 1, id = a.id })
			levelTo(h, p, 27)
			expect(h:Session(p, "Apiary").hives).toBe(2)
			local b = adult(h, p)
			h:Advance(2)
			expect(h:Reject(p, "Apiary.Assign", { hive = 3, id = b.id })).toBe("Beehive 3 opens at Ranch Level 42")
			h:Advance(2)
			h:Call(p, "Apiary.Assign", { hive = 2, id = b.id })
			levelTo(h, p, 42)
			expect(h:Session(p, "Apiary").hives).toBe(3)
		end)

		it("takes free Adults only, tags them busy and gives them back on Unassign with the honey", function()
			local h, p = boot()
			local teen = adult(h, p, { stage = 2 })
			expect(h:Reject(p, "Apiary.Assign", { hive = 1, id = teen.id })).toBe("Only Adults can tend a beehive")
			local a = adult(h, p, { rarity = 5 })
			h:Call(p, "Apiary.Assign", { hive = 1, id = a.id })
			local M = h:System("Monsters")
			expect(M:Get(p, a.id).busy).toBe("apiary")
			expect(h:Reject(p, "Apiary.Assign", { hive = 1, id = teen.id })).toBe("This beehive already has a keeper")
			expect(h:Reject(p, "Apiary.Unassign", { hive = 2 })).toBe("That beehive has no keeper")

			h:Advance(2 * HOUR)
			local res = h:Call(p, "Apiary.Unassign", { hive = 1 })
			local kind = Logic.KindAt(START)
			expect(res.honey[kind]).toBe(math.floor(Logic.PerHour(M:Get(p, a.id)) * 2 + 1e-6))
			expect(not M:Get(p, a.id).busy).toBe(true)
			expect(h:Section(p, "Apiary").hives[1].monster).toBe(false)
			expect(h:System("Apiary"):Have(p, kind)).toBe(res.honey[kind])
		end)

		it("fills while away up to the cap, says so on return, and collects every hive in one tap", function()
			local h, p = boot()
			local a = adult(h, p, { rarity = 4 })
			h:Call(p, "Apiary.Assign", { hive = 1, id = a.id })
			local welcome = topics(h, "WelcomeItem")
			local collected = topics(h, "HoneyCollected")
			local p2 = h:Rejoin(p, 3 * 24 * HOUR)
			local found = false
			for _, item in welcome do
				if item.kind == "apiary" then
					found = true
					expect(item.text).toBe("A beehive filled with honey")
				end
			end
			expect(found).toBe(true)
			expect(h:System("Monsters"):Get(p2, a.id).busy).toBe("apiary")
			local cap = Logic.Cap(h:System("Monsters"):Get(p2, a.id))
			local res = h:Call(p2, "Apiary.Collect")
			local total = 0
			for kind, n in res.honey do
				if kind ~= "royal_jelly" then
					total += n
				end
			end
			expect(total >= math.floor(cap) - 1 and total <= math.floor(cap)).toBe(true)
			local published = 0
			for _, d in collected do
				if d.kind ~= "royal_jelly" then
					published += d.amount
					expect(d.honey).toBe(true)
				end
			end
			expect(published).toBe(total)
			expect(h:Reject(p2, "Apiary.Collect")).toBe("No honey to collect yet")
		end)

		it("pays both honeys for a stretch across the Saturday turnover", function()
			local turn = Seasons.At(START).endsAt
			local h, p = boot({ at = turn - HOUR })
			local a = adult(h, p, { rarity = 5 })
			h:Call(p, "Apiary.Assign", { hive = 1, id = a.id })
			local collected = topics(h, "HoneyCollected")
			h:Advance(2 * HOUR)
			local res = h:Call(p, "Apiary.Collect")
			local before, after = Logic.KindAt(turn - 1), Logic.KindAt(turn)
			expect((res.honey[before] or 0) >= 1).toBe(true)
			expect((res.honey[after] or 0) >= 1).toBe(true)
			local kinds = {}
			for _, d in collected do
				kinds[d.kind] = (kinds[d.kind] or 0) + 1
			end
			expect(kinds[before]).toBe(1)
			expect(kinds[after]).toBe(1)
		end)

		it("rolls Royal Jelly from a seed per player and collect number", function()
			local lucky, unlucky
			for id = 5000, 9000 do
				local hit = Logic.RoyalJelly(id, 1)
				if hit and not lucky then
					lucky = id
				elseif not hit and not unlucky then
					unlucky = id
				end
				if lucky and unlucky then
					break
				end
			end
			for _, case in { { lucky, 1 }, { unlucky, 0 } } do
				local h, p = boot({ userId = case[1] })
				local a = adult(h, p, { rarity = 5 })
				h:Call(p, "Apiary.Assign", { hive = 1, id = a.id })
				local collected = topics(h, "HoneyCollected")
				h:Advance(HOUR)
				local res = h:Call(p, "Apiary.Collect")
				expect(res.honey.royal_jelly or 0).toBe(case[2])
				expect(h:System("Apiary"):Have(p, "royal_jelly")).toBe(case[2])
				local royal = 0
				for _, d in collected do
					if d.kind == "royal_jelly" then
						royal += d.amount
						expect(d.honey).toBe(false)
					end
				end
				expect(royal).toBe(case[2])
				expect(h:Section(p, "Apiary").collects).toBe(1)
			end
		end)

		it("sells honey and Royal Jelly for ranch income, all or nothing", function()
			local h, p = boot()
			local A = h:System("Apiary")
			expect(h:Reject(p, "Apiary.Sell", { kind = "clover", amount = 1 })).toBe("Not enough Clover Honey")
			expect(A:AddHoney(p, "clover", 10)).toBe(10)
			A:AddHoney(p, "royal_jelly", 1)
			local income = h:System("Ranch"):IncomePerSecond(p)
			local coins = h:Section(p, "Currency").coins
			local res = h:Call(p, "Apiary.Sell", { kind = "clover", amount = 10 })
			expect(res.coins).toBe(math.floor(math.max(100, income * Rules.SellSeconds.clover * 10)))
			expect(h:Section(p, "Currency").coins).toBe(coins + res.coins)
			expect(A:Have(p, "clover")).toBe(0)
			local jelly = h:Call(p, "Apiary.Sell", { kind = "royal_jelly", amount = 1 })
			expect(jelly.coins).toBe(math.floor(math.max(100, income * Rules.SellSeconds.royal_jelly)))
			expect(A:SpendHoney(p, "frost", 1)).toBe(false)
			expect(A:AddHoney(p, "nectar", 3)).toBe(0)
		end)

		it("grants honey through Rewards (kind honey)", function()
			local h, p = boot()
			h:System("Rewards"):Grant(p, { { kind = "honey", id = "frost", amount = 3 } }, "test")
			expect(h:System("Apiary"):Have(p, "frost")).toBe(3)
			expect(h:System("Apiary"):Honey(p).frost).toBe(3)
		end)
	end)

	describe("Honey in the Kitchen", function()
		local KSYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Bond", "Kitchen", "Apiary" }

		it("cooks a honey recipe from the Apiary's store in any season", function()
			local h, p = boot({ systems = KSYSTEMS })
			local r = Config.Kitchen.ById.blossom_honey_bun
			h:System("Currency"):Add(p, "food.sweet", 10, "test")
			expect(h:Reject(p, "Kitchen.Cook", { recipe = r.id })).toBe("Not enough Blossom Honey")
			local A = h:System("Apiary")
			A:AddHoney(p, "blossom", 5)
			h:Call(p, "Kitchen.Cook", { recipe = r.id })
			expect(A:Have(p, "blossom")).toBe(2)
			expect(h:System("Currency"):Balance(p, "food.sweet")).toBe(7)
		end)

		it("refuses honey recipes without the Apiary", function()
			local h, p = boot({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Bond", "Kitchen" } })
			h:System("Currency"):Add(p, "food.sour", 10, "test")
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "clover_honey_tea" })).toBe("Needs honey from the Apiary")
		end)

		it("serves the Royal Jelly Tart: +1 Bond heart and full Mood", function()
			local h, p = boot({ systems = KSYSTEMS })
			local r = Config.Kitchen.ById.royal_jelly_tart
			expect(r.effect).toBe("royal")
			h:System("Currency"):Add(p, "food.sweet", 10, "test")
			h:System("Apiary"):AddHoney(p, "royal_jelly", 1)
			h:Call(p, "Kitchen.Cook", { recipe = r.id })
			expect(h:System("Apiary"):Have(p, "royal_jelly")).toBe(0)
			h:Advance(r.minutes * 60 + 1)
			h:Call(p, "Kitchen.Collect")
			local m = adult(h, p)
			m.mood = 10
			local hearts = h:System("Bond"):Hearts(p, m.id)
			expect(h:Call(p, "Kitchen.Serve", { id = m.id, dish = r.id }).effect).toBe("royal")
			expect(h:System("Bond"):Hearts(p, m.id)).toBe(hearts + 1)
			expect(h:System("Monsters"):Get(p, m.id).mood).toBe(Config.Economy.Mood.max)
		end)
	end)

	describe("Honey elsewhere", function()
		it("barters honey at the Travelling Merchant, the most plentiful kind first", function()
			local k = MerchantLogic.Visit(START)
			local at
			for i = 0, 3000 do
				if MerchantLogic.Find(k + i, "honey_seeds") then
					at = (k + i) * Config.Merchant.Cycle + Config.Merchant.Offset + 60
					break
				end
			end
			expect(at ~= nil).toBe(true)
			local h, p = boot({
				at = at,
				level = 20,
				systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Ranch", "Kitchen", "Merchant", "Apiary" },
			})
			local slot = MerchantLogic.Find(MerchantLogic.Visit(at), "honey_seeds")
			local i = if slot.pay[1].kind == "honey" then 1 else 2
			expect(slot.pay[i].kind).toBe("honey")
			expect(MerchantLogic.PayText(slot.pay[i], 8)).toBe("Pay 8 Honey")
			local A = h:System("Apiary")
			A:AddHoney(p, "royal_jelly", 20)
			expect(h:Reject(p, "Merchant.Buy", { offer = "honey_seeds", pay = i })).toBe("Not enough honey")
			A:AddHoney(p, "clover", 6)
			A:AddHoney(p, "frost", 3)
			local seeds = h:Section(p, "Kitchen").seeds
			h:Call(p, "Merchant.Buy", { offer = "honey_seeds", pay = i })
			expect(h:Section(p, "Kitchen").seeds).toBe(seeds + slot.amount)
			-- 8 honey: all 6 clover first, then 2 frost; Royal Jelly is never spent.
			expect(A:Have(p, "clover")).toBe(0)
			expect(A:Have(p, "frost")).toBe(1)
			expect(A:Have(p, "royal_jelly")).toBe(20)
		end)

		it("has the weekly goal honey_40 counting honey, not Royal Jelly", function()
			local def = Config.Weekly.ById.honey_40
			expect(def.family).toBe("apiary")
			expect(def.unlock).toBe("apiary")
			expect(def.topic).toBe("HoneyCollected")
			expect(Objectives.Matches(def.filter, { kind = "clover", amount = 7, honey = true })).toBe(true)
			expect(Objectives.Matches(def.filter, { kind = "royal_jelly", amount = 1, honey = false })).toBe(false)
			expect(Objectives.Amount(Config.Quests.CountField, def.topic, { kind = "clover", amount = 7, honey = true })).toBe(7)
		end)

		it("counts collected honey on the weekly board", function()
			local h, p = boot({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Weekly", "Apiary" } })
			h.kernel.Bus:Publish("HoneyCollected", p, { kind = "clover", amount = 5, honey = true })
			h.kernel.Bus:Publish("HoneyCollected", p, { kind = "royal_jelly", amount = 1, honey = false })
			local w = h:Section(p, "Weekly")
			for _, g in w.goals or {} do
				if g.id == "honey_40" then
					expect(g.progress).toBe(5)
				end
			end
		end)
	end)
end
