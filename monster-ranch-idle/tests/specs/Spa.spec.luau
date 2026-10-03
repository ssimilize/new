--[[
	Spa (update 3.13 · Wild things) on the server: the soak rules (Logic/Spa), unlock gates per
	pool, soaking (busy tag, Teens and Adults, Warm Soak for growing monsters only), bath salts
	paid in honey through the Apiary and food, no soaks without the Apiary, timers and a soak that
	finishes offline with its Welcome Back line, collect -> buff + SpaSoaked, every buff reaching
	its consumer (growth meals, the Job Board, Apiary honey, Mood and Bond) and nothing without a
	buff, buff expiry, and the weekly goal spa_5.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Spa")
	local ApiaryLogic = t.Shared("Logic.Apiary")
	local JobsLogic = t.Shared("Logic.Jobs")
	local Objectives = t.Shared("Logic.Objectives")

	local Rules = Config.Spa
	local HOUR = 3600
	local START = 1790000000

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Bond", "Jobs", "Apiary", "Spa" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(opts)
		opts = opts or {}
		local h = TestKernel.new({ systems = table.clone(opts.systems or SYSTEMS), startTime = START })
		local p = h:Join()
		levelTo(h, p, opts.level or 29)
		return h, p
	end

	local function monster(h, p, fields)
		local spec = { line = "cindlet", rarity = 3, stage = 3, traits = {}, hidden = 0 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return h:System("Monsters"):Create(p, spec, "test", true)
	end

	local function stock(h, p)
		h:System("Apiary"):AddHoney(p, "clover", 20)
		local C = h:System("Currency")
		for _, flavour in { "spicy", "savory", "sweet" } do
			C:Add(p, "food." .. flavour, 20, "test")
		end
	end

	local function topics(h, name: string)
		local seen = {}
		h.kernel.Bus:Subscribe(name, function(_, detail)
			table.insert(seen, detail)
		end)
		return seen
	end

	local function buff(h, p, id: string, soak: string, hours: number?)
		local now = h.adapters.Clock.Now()
		h:Section(p, "Spa").buffs[id] = { soak = soak, from = now, endsAt = now + (hours or 4) * HOUR }
	end

	describe("Spa rules", function()
		it("opens two pools with the spa and the third at spa_pool_3, and prices each salt", function()
			expect(Rules.PoolUnlocks[1]).toBe("spa")
			expect(Config.Unlocks.Features.spa).toBe(29)
			expect(Config.Unlocks.Features.spa_pool_3).toBe(45)
			expect(Logic.PoolCount(function(key)
				return key == "spa"
			end)).toBe(2)
			expect(Logic.PoolCount(function()
				return true
			end)).toBe(3)
			expect(Logic.Cost("warm")).toEqual({ honey = 2, food = { spicy = 5 } })
			expect(Logic.Cost("mineral")).toEqual({ honey = 2, food = { savory = 5 } })
			expect(Logic.Cost("herbal")).toEqual({ honey = 3, food = { sweet = 5 } })
			expect(Logic.Seconds("warm")).toBe(30 * 60)
			expect(Logic.Seconds("herbal")).toBe(2 * HOUR)
			for _, def in Rules.Soaks do
				expect(Config.Food.ById[def.food] ~= nil).toBe(true)
			end
		end)

		it("takes Teens and Adults, and a Warm Soak only for a monster that still grows", function()
			expect(Logic.CanTake({ stage = 1 }, "herbal")).toBe(false)
			expect(Logic.CanTake({ stage = 2 }, "warm")).toBe(true)
			expect(Logic.CanTake({ stage = 3 }, "mineral")).toBe(true)
			local ok, why = Logic.CanTake({ stage = 3 }, "warm")
			expect(ok).toBe(false)
			expect(why).toBe("Only a growing monster gains from a Warm Soak")
		end)

		it("keeps a buff only until it ends and gives multipliers of exactly 1 without one", function()
			local b = { soak = "warm", from = 100, endsAt = 200 }
			expect(Logic.GrowthMult(b, 150)).toBe(1 + 0.20)
			expect(Logic.GrowthMult(b, 200)).toBe(1)
			expect(Logic.GrowthMult(nil, 150)).toBe(1)
			expect(Logic.OutputBoosts(b)).toBe(nil)
			expect(Logic.OutputBoosts({ soak = "mineral", from = 100, endsAt = 200 })).toEqual({ { from = 100, to = 200, pct = 0.15 } })
		end)
	end)

	describe("Spa server", function()
		it("opens pools 1 and 2 at Level 29 and pool 3 at 45", function()
			local h, p = boot({ level = 28 })
			stock(h, p)
			local a = monster(h, p)
			expect(h:Reject(p, "Spa.Soak", { pool = 1, id = a.id, soak = "mineral" })).toContain("29")
			levelTo(h, p, 29)
			expect(h:Session(p, "Spa").pools).toBe(2)
			expect(h:Session(p, "Spa").apiary).toBe(true)
			h:Advance(2)
			expect(h:Reject(p, "Spa.Soak", { pool = 3, id = a.id, soak = "mineral" })).toBe("Spa pool 3 opens at Ranch Level 45")
			h:Advance(2)
			h:Call(p, "Spa.Soak", { pool = 2, id = a.id, soak = "mineral" })
			levelTo(h, p, 45)
			expect(h:Session(p, "Spa").pools).toBe(3)
			local b = monster(h, p)
			h:Advance(2)
			h:Call(p, "Spa.Soak", { pool = 3, id = b.id, soak = "mineral" })
			expect(h:Section(p, "Spa").pools[3].monster).toBe(b.id)
		end)

		it("pays the bath salt in honey and food, tags the monster busy and refuses a full pool", function()
			local h, p = boot()
			local a, b = monster(h, p), monster(h, p)
			expect(h:Reject(p, "Spa.Soak", { pool = 1, id = a.id, soak = "herbal" })).toBe("A bath salt needs 3 honey")
			h:System("Apiary"):AddHoney(p, "clover", 2)
			h:System("Apiary"):AddHoney(p, "frost", 2)
			h:Advance(2)
			expect(h:Reject(p, "Spa.Soak", { pool = 1, id = a.id, soak = "herbal" })).toContain("Sweet Berries")
			h:System("Currency"):Add(p, "food.sweet", 7, "test")
			h:Advance(2)
			local res = h:Call(p, "Spa.Soak", { pool = 1, id = a.id, soak = "herbal" })
			expect(res.endsAt).toBe(h.adapters.Clock.Now() + 2 * HOUR)
			expect(h:System("Apiary"):HoneyCount(p)).toBe(1)
			expect(h:System("Currency"):Balance(p, "food.sweet")).toBe(2)
			expect(h:System("Monsters"):Get(p, a.id).busy).toBe("spa")
			h:Advance(2)
			expect(h:Reject(p, "Spa.Soak", { pool = 1, id = b.id, soak = "herbal" })).toBe("Someone is already soaking in this pool")
			local baby = monster(h, p, { stage = 1 })
			stock(h, p)
			h:Advance(2)
			expect(h:Reject(p, "Spa.Soak", { pool = 2, id = baby.id, soak = "herbal" })).toBe("Only Teens and Adults can soak in the spa")
			h:Advance(2)
			expect(h:Reject(p, "Spa.Soak", { pool = 2, id = b.id, soak = "warm" })).toBe("Only a growing monster gains from a Warm Soak")
			h:Advance(2)
			-- Stop: the monster is freed and the salt is lost.
			h:Call(p, "Spa.Cancel", { pool = 1 })
			expect(not h:System("Monsters"):Get(p, a.id).busy).toBe(true)
			expect(h:Section(p, "Spa").pools[1].monster).toBe(false)
			expect(h:System("Spa"):Buff(p, a.id)).toBe(nil)
		end)

		it("offers no soak without the Apiary", function()
			local h, p = boot({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Spa" } })
			local a = monster(h, p)
			expect(h:Session(p, "Spa").apiary).toBe(false)
			expect(h:Reject(p, "Spa.Soak", { pool = 1, id = a.id, soak = "mineral" })).toBe("Bath salts need honey from the Apiary")
		end)

		it("finishes on the server clock, offline too, and collects into a buff with SpaSoaked", function()
			local h, p = boot()
			stock(h, p)
			local a = monster(h, p)
			h:Call(p, "Spa.Soak", { pool = 1, id = a.id, soak = "mineral" })
			h:Advance(30 * 60)
			expect(h:Reject(p, "Spa.Collect", { pool = 1 })).toBe("The soak isn't done yet")
			local welcome = topics(h, "WelcomeItem")
			local soaked = topics(h, "SpaSoaked")
			local p2 = h:Rejoin(p, 2 * HOUR)
			local found = false
			for _, item in welcome do
				if item.kind == "spa" then
					found = true
					expect(item.text).toBe("A spa soak finished")
				end
			end
			expect(found).toBe(true)
			expect(h:System("Monsters"):Get(p2, a.id).busy).toBe("spa")
			local res = h:Call(p2, "Spa.Collect", { pool = 1 })
			local now = h.adapters.Clock.Now()
			expect(res.soak).toBe("mineral")
			expect(res.endsAt).toBe(now + Rules.BuffHours * HOUR)
			expect(not h:System("Monsters"):Get(p2, a.id).busy).toBe(true)
			expect(h:System("Spa"):Buff(p2, a.id)).toEqual({ soak = "mineral", endsAt = now + Rules.BuffHours * HOUR })
			expect(#soaked).toBe(1)
			expect(soaked[1]).toEqual({ monsterId = a.id, soak = "mineral" })
			expect(h:Section(p2, "Spa").soaks).toBe(1)
			-- The buff ends after BuffHours and is pruned on the next join.
			h:Advance(Rules.BuffHours * HOUR)
			expect(h:System("Spa"):Buff(p2, a.id)).toBe(nil)
			local p3 = h:Rejoin(p2, 60)
			expect(h:Section(p3, "Spa").buffs[a.id]).toBe(nil)
		end)

		it("gives a herbal soak full Mood and bond points when collected", function()
			local h, p = boot()
			stock(h, p)
			local a = monster(h, p)
			local M = h:System("Monsters")
			M:Get(p, a.id).mood = 10
			h:Call(p, "Spa.Soak", { pool = 1, id = a.id, soak = "herbal" })
			h:Advance(2 * HOUR)
			h:Call(p, "Spa.Collect", { pool = 1 })
			expect(M:Get(p, a.id).mood).toBe(Config.Economy.Mood.max)
			expect(h:System("Bond"):Points(p, a.id)).toBe(3)
			expect(h:System("Bond"):Hearts(p, a.id)).toBe(2)
		end)

		it("feeds a warm-soaked monster 20% more growth, and exactly the same without a buff", function()
			local h, p = boot()
			local a, b = monster(h, p, { stage = 2 }), monster(h, p, { stage = 2 })
			h:System("Currency"):Add(p, "food.spicy", 10, "test")
			buff(h, p, a.id, "warm")
			h:Call(p, "Monsters.Feed", { id = a.id, flavor = "spicy", amount = 1 })
			h:Advance(2)
			h:Call(p, "Monsters.Feed", { id = b.id, flavor = "spicy", amount = 1 })
			local M = h:System("Monsters")
			expect(M:Get(p, a.id).meals.spicy).toBe(1 * 1.2)
			expect(M:Get(p, b.id).meals.spicy).toBe(1)
			expect(M:AddMeals(p, a.id, "sweet", 2)).toBe(2 * 1.2)
			expect(M:AddMeals(p, b.id, "sweet", 2)).toBe(2)
			-- Once the buff ends, meals are plain again.
			h:Advance(4 * HOUR)
			expect(M:AddMeals(p, a.id, "sour", 1)).toBe(1)
		end)

		it("makes a mineral-soaked miner earn 15% more while the buff lasts", function()
			local h, p = boot()
			local m = monster(h, p, { rarity = 5 })
			h:Call(p, "Jobs.Assign", { slot = 1, job = "miner", id = m.id })
			local slot = h:Section(p, "Jobs").slots[1]
			slot.since = h.adapters.Clock.Now()
			slot.carry = 0
			buff(h, p, m.id, "mineral")
			h:Advance(3 * HOUR)
			local record = h:System("Monsters"):Get(p, m.id)
			local plain = JobsLogic.Pending(slot, record, h.adapters.Clock.Now(), {})[1].amount
			local coins = h:Call(p, "Jobs.Recall", { slot = 1 }).rewards[1].amount
			expect(coins / plain).toBeNear(1.15, 0.01)
		end)

		it("pays the same Job Board coins as before with no buff or an ended one", function()
			local h, p = boot()
			local m = monster(h, p, { rarity = 5 })
			h:Call(p, "Jobs.Assign", { slot = 1, job = "miner", id = m.id })
			local slot = h:Section(p, "Jobs").slots[1]
			slot.since = h.adapters.Clock.Now()
			slot.carry = 0
			buff(h, p, m.id, "mineral", -1)
			h:Advance(3 * HOUR)
			local record = h:System("Monsters"):Get(p, m.id)
			local plain = JobsLogic.Pending(slot, record, h.adapters.Clock.Now(), {})[1].amount
			expect(h:Call(p, "Jobs.Recall", { slot = 1 }).rewards[1].amount).toBe(plain)
		end)

		it("makes a mineral-soaked beekeeper make 15% more honey, and the other one the same as before", function()
			local h, p = boot()
			local a, b = monster(h, p, { rarity = 5 }), monster(h, p, { rarity = 5 })
			local M = h:System("Monsters")
			h:Call(p, "Apiary.Assign", { hive = 1, id = a.id })
			h:Advance(2)
			h:Call(p, "Apiary.Assign", { hive = 2, id = b.id })
			local hives = h:Section(p, "Apiary").hives
			local now = h.adapters.Clock.Now()
			hives[1].at, hives[2].at = now, now
			buff(h, p, a.id, "mineral")
			h:Advance(4 * HOUR)
			local expectPlain = ApiaryLogic.Total(ApiaryLogic.Settle(hives[2], M:Get(p, b.id), h.adapters.Clock.Now()))
			local function total(res)
				local n = 0
				for _, v in res.honey do
					n += v
				end
				return n
			end
			local boosted = total(h:Call(p, "Apiary.Unassign", { hive = 1 }))
			h:Advance(2)
			local plain = total(h:Call(p, "Apiary.Unassign", { hive = 2 }))
			expect(plain).toBe(math.floor(expectPlain + 1e-6))
			expect(boosted / expectPlain).toBeNear(1.15, 0.05)
			expect(boosted > plain).toBe(true)
		end)

		it("clears a pool and a buff when the monster leaves the ranch", function()
			local h, p = boot()
			stock(h, p)
			local a = monster(h, p)
			h:Call(p, "Spa.Soak", { pool = 1, id = a.id, soak = "mineral" })
			buff(h, p, a.id, "herbal")
			h.kernel.Bus:Publish("MonsterRemoved", p, { id = a.id })
			expect(h:Section(p, "Spa").pools[1].monster).toBe(false)
			expect(h:Section(p, "Spa").buffs[a.id]).toBe(nil)
		end)

		it("has the weekly goal spa_5 counting collected soaks", function()
			local def = Config.Weekly.ById.spa_5
			expect(def.family).toBe("spa")
			expect(def.unlock).toBe("spa")
			expect(def.topic).toBe("SpaSoaked")
			expect(def.target).toBe(5)
			expect(Objectives.Matches(def.filter, { monsterId = "m1", soak = "warm" })).toBe(true)
			local list = table.clone(SYSTEMS)
			table.insert(list, "Weekly")
			local h, p = boot({ systems = list })
			local s = h:Section(p, "Weekly")
			s.goals = { { id = "spa_5", progress = 0 } }
			h.kernel.Bus:Publish("SpaSoaked", p, { monsterId = "m1", soak = "warm" })
			h.kernel.Bus:Publish("SpaSoaked", p, { monsterId = "m2", soak = "herbal" })
			expect(s.goals[1].progress).toBe(2)
		end)
	end)
end
