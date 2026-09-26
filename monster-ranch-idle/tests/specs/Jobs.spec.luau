--[[
	Jobs (update 3.7): the Job Board and Luck that counts. The job rules (Logic/Jobs), the
	board on the server (slots, assign, recall, collect, flavours, guards, herders, rejoin),
	Luck in battles and on expeditions, and the fifth (Luck) gene with its save migration.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local JobsLogic = t.Shared("Logic.Jobs")
	local Formulas = t.Shared("Logic.Formulas")
	local Genetics = t.Shared("Logic.Genetics")
	local BattleSim = t.Shared("Logic.BattleSim")
	local Loot = t.Shared("Logic.Loot")
	local Arena = t.Shared("Logic.Arena")
	local Rng = t.Shared("Logic.Rng")

	local Rules = Config.Jobs
	local HOUR = 3600

	local function uniform(a, b)
		local g = {}
		for _, stat in Config.Genetics.Stats do
			g[stat] = { a, b }
		end
		return g
	end

	local function worker(fields)
		local m = {
			id = "m1",
			line = "cindlet",
			stage = 3,
			rarity = 2,
			lv = 20,
			stars = 2,
			traits = {},
			hidden = 0,
			muts = {},
			mood = 80,
			genes = uniform(0, 0),
		}
		for k, v in fields or {} do
			m[k] = v
		end
		return m
	end

	local function always()
		return true
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Jobs" }

	local function boot(level: number?)
		local h = TestKernel.new({ systems = SYSTEMS })
		local p = h:Join()
		levelTo(h, p, level or 6)
		return h, p, h:System("Monsters")
	end

	local function adult(M, p, fields)
		local spec = { line = "cindlet", rarity = 3, stage = 3, traits = { 7, 12 }, hidden = 9 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return M:Create(p, spec, "test", true)
	end

	describe("Job rules", function()
		it("rates a better worker higher, and genes raise the job's stat", function()
			local teen = worker({ rarity = 1, stage = 2, lv = 1, stars = 1 })
			local mid = worker()
			local top = worker({ rarity = 6, lv = 50, stars = 5 })
			for _, job in Rules.Ids do
				expect(JobsLogic.Power(mid, job)).toBeGreaterThan(JobsLogic.Power(teen, job))
				expect(JobsLogic.Power(top, job)).toBeGreaterThan(JobsLogic.Power(mid, job))
				local stat = Rules.ById[job].stat
				local gifted =
					worker({ genes = (function()
						local g = uniform(0, 0)
						g[stat] = { 10, 10 }
						return g
					end)() })
				expect(JobsLogic.Power(gifted, job)).toBeGreaterThan(JobsLogic.Power(mid, job))
			end
			-- The headline numbers from the proposal.
			expect(JobsLogic.FoodPerHour(teen)).toBeNear(1.1, 0.3)
			expect(JobsLogic.FoodPerHour(top)).toBeNear(8.8, 1.2)
			expect(JobsLogic.GuardMinutes(teen)).toBeNear(7, 2)
			expect(JobsLogic.GuardMinutes(top)).toBeNear(52, 6)
			expect(JobsLogic.EggChancePerHour(top) * Rules.MaxHours).toBeNear(1, 0.2)
		end)

		it("pays a miner 20-65% of its pen income, more for ATK-strong species and ATK genes", function()
			for _, line in Config.Species.Lines do
				local m = worker({ line = line.id })
				local share = JobsLogic.CoinsPerSecond(m) / Formulas.CoinRate(m)
				expect(share).toBeGreaterThan(0.2)
				expect(share).toBeLessThan(0.65)
			end
			local plain = worker()
			local strong = worker({ genes = (function()
				local g = uniform(0, 0)
				g.atk = { 10, 10 }
				return g
			end)() })
			expect(JobsLogic.CoinsPerSecond(strong)).toBeNear(JobsLogic.CoinsPerSecond(plain) * 1.2, 1e-6)
		end)

		it("caps guards at GuardMaxMinutes and herders at a full shield", function()
			local top = worker({ rarity = 6, lv = 50, stars = 5 })
			expect(JobsLogic.GuardSeconds({ top, top, top })).toBe(Rules.GuardMaxMinutes * 60)
			expect(JobsLogic.Shield({ top, top })).toBe(1)
			expect(JobsLogic.Shield({})).toBe(0)
			expect(JobsLogic.Shield({ worker({ rarity = 1, stage = 2, lv = 1, stars = 1 }) })).toBeLessThan(0.3)
		end)

		it("counts slots from the unlocks", function()
			expect(JobsLogic.SlotCount(function()
				return false
			end)).toBe(0)
			expect(JobsLogic.SlotCount(function(key)
				return key == Rules.Unlock
			end)).toBe(Rules.BaseSlots)
			expect(JobsLogic.SlotCount(always)).toBe(Rules.MaxSlots)
		end)

		it("stores at most MaxHours and keeps fractions for the next collect", function()
			local m = worker()
			local slot = { job = "miner", monster = "m1", since = 1000, carry = 0, rolled = 0, flavor = "sweet", seed = 5 }
			local capped = JobsLogic.Collect(slot, m, 1000 + Rules.MaxHours * HOUR, {})
			local over = JobsLogic.Collect(slot, m, 1000 + 20 * HOUR, {})
			expect(over[1].amount).toBe(capped[1].amount)
			expect(JobsLogic.IsFull(slot, 1000 + Rules.MaxHours * HOUR)).toBe(true)
			expect(JobsLogic.IsFull(slot, 1000 + HOUR)).toBe(false)
			expect(JobsLogic.IsFull(JobsLogic.EmptySlot(), 1000 + 20 * HOUR)).toBe(false)

			local food = { job = "forager", monster = "m1", since = 0, carry = 0, rolled = 0, flavor = "spicy", seed = 5 }
			local whole = JobsLogic.Collect(food, m, 6 * HOUR, {})
			local total, since, carry = 0, 0, 0
			for step = 1, 12 do
				local s = { job = "forager", monster = "m1", since = since, carry = carry, rolled = 0, flavor = "spicy", seed = 5 }
				local rewards
				rewards, since, carry = JobsLogic.Collect(s, m, step * HOUR / 2, {})
				for _, r in rewards do
					expect(r.id).toBe("spicy")
					total += r.amount
				end
			end
			expect(total).toBe(whole[1].amount)
		end)

		it("rolls scout eggs per whole hour from the seed, only from unlocked eggs", function()
			local m = worker({ rarity = 6, lv = 50, stars = 5 })
			local eggs = JobsLogic.ScoutEggs(function(key)
				return key == "egg_meadow" or key == "egg_grove"
			end)
			expect(#eggs).toBe(2)
			local found, seen = 0, {}
			for seed = 1, 200 do
				local slot = { job = "scout", monster = "m1", since = 0, carry = 0, rolled = 0, flavor = "sweet", seed = seed }
				local once, since, _, rolled = JobsLogic.Collect(slot, m, 8 * HOUR, eggs)
				expect(since).toBe(8 * HOUR)
				expect(rolled).toBe(8)
				-- The same 8 hours collected in two parts find the same eggs.
				local first, s1, _, r1 = JobsLogic.Collect(slot, m, 3 * HOUR + 1200, eggs)
				expect(s1).toBe(3 * HOUR) -- the 20 minutes into hour 4 carry over
				local slot2 = { job = "scout", monster = "m1", since = s1, carry = 0, rolled = r1, flavor = "sweet", seed = seed }
				local second = JobsLogic.Collect(slot2, m, 8 * HOUR, eggs)
				local a, b = 0, 0
				for _, r in once do
					a += r.amount
					seen[r.id] = true
				end
				for _, list in { first, second } do
					for _, r in list do
						b += r.amount
					end
				end
				expect(b).toBe(a)
				found += a
			end
			expect(seen.crystal).toBeNil()
			expect(seen.royal).toBeNil()
			-- About one egg per 8 hours for a maxed Mythic scout.
			expect(found / 200).toBeNear(8 * JobsLogic.EggChancePerHour(m), 0.25)
		end)
	end)

	describe("Job Board", function()
		it("opens at Ranch Level 6 with 2 slots and grows to 5", function()
			local h, p, M = boot(5)
			local m = adult(M, p)
			expect(h:Reject(p, "Jobs.Assign", { slot = 1, job = "miner", id = m.id })).toContain("Ranch Level 6")
			levelTo(h, p, 6)
			expect(h:Session(p, "Jobs").slotCount).toBe(2)
			expect(h:Reject(p, "Jobs.Assign", { slot = 3, job = "miner", id = m.id })).toContain("Ranch Level 20")
			levelTo(h, p, 50)
			expect(h:Session(p, "Jobs").slotCount).toBe(5)
		end)

		it("takes a free Teen or Adult from the barn and keeps it busy", function()
			local h, p, M = boot()
			local baby = adult(M, p, { stage = 1 })
			expect(h:Reject(p, "Jobs.Assign", { slot = 1, job = "miner", id = baby.id })).toContain("Teens and Adults")
			local penned = adult(M, p)
			h:Call(p, "Ranch.Assign", { id = penned.id, pen = 1 })
			h:Advance(1)
			expect(h:Reject(p, "Jobs.Assign", { slot = 1, job = "miner", id = penned.id })).toContain("barn")
			local m = adult(M, p)
			h:Call(p, "Jobs.Assign", { slot = 1, job = "miner", id = m.id })
			expect(m.busy).toBe("job")
			expect(h:Client(p).profile.Jobs.slots[1].job).toBe("miner")
			h:Advance(1)
			expect(h:Reject(p, "Jobs.Assign", { slot = 1, job = "scout", id = adult(M, p).id })).toContain("Recall")
			expect(h:Reject(p, "Jobs.Assign", { slot = 2, job = "scout", id = m.id })).toContain("busy")
			expect(h:Reject(p, "Ranch.Assign", { id = m.id, pen = 1 })).toContain("busy")
		end)

		it("pays a miner's coins, capped at 8 hours, and frees it on recall", function()
			local h, p, M = boot()
			local m = adult(M, p)
			h:Call(p, "Jobs.Assign", { slot = 1, job = "miner", id = m.id })
			h:Advance(20 * HOUR)
			-- Read at collect time: the miner's own Mood (part of its coin rate) drops online.
			local perSecond = JobsLogic.CoinsPerSecond(m)
			local coins = h:Section(p, "Currency").coins
			local res = h:Call(p, "Jobs.Collect")
			local got = h:Section(p, "Currency").coins - coins
			expect(got).toBeNear(perSecond * Rules.MaxHours * HOUR, 2)
			expect(res.rewards[1].kind).toBe("coins")
			h:Advance(HOUR)
			perSecond = JobsLogic.CoinsPerSecond(m)
			local back = h:Call(p, "Jobs.Recall", { slot = 1 })
			expect(back.rewards[1].amount).toBeNear(perSecond * HOUR, 2)
			expect(m.busy).toBe(false)
			expect(h:Section(p, "Jobs").slots[1].job).toBe(false)
		end)

		it("gathers the chosen flavour and pays the old flavour before a change", function()
			local h, p, M = boot()
			local m = adult(M, p)
			h:Call(p, "Jobs.Assign", { slot = 1, job = "forager", id = m.id, flavor = "sour" })
			h:Advance(4 * HOUR)
			local sour = h:Section(p, "Currency").food.sour or 0
			h:Call(p, "Jobs.SetFlavor", { slot = 1, flavor = "sweet" })
			expect((h:Section(p, "Currency").food.sour or 0) - sour).toBeNear(JobsLogic.FoodPerHour(m) * 4, 1)
			h:Advance(4 * HOUR)
			local sweet = h:Section(p, "Currency").food.sweet or 0
			h:Call(p, "Jobs.Collect")
			expect((h:Section(p, "Currency").food.sweet or 0) - sweet).toBeNear(JobsLogic.FoodPerHour(m) * 4, 1)
			expect(h:Reject(p, "Jobs.SetFlavor", { slot = 2, flavor = "sweet" })).toContain("foragers")
		end)

		it("puts a scout's eggs in the egg inventory", function()
			local h, p, M = boot(12)
			local scout = adult(M, p, { rarity = 6 })
			scout.lv, scout.stars = 50, 5
			h:Call(p, "Jobs.Assign", { slot = 1, job = "scout", id = scout.id })
			local before = h:System("Eggs"):Count(p)
			local found = 0
			for _ = 1, 6 do
				h:Advance(8 * HOUR)
				local res = h:Call(p, "Jobs.Collect")
				for _, r in res.rewards do
					expect(r.kind).toBe("egg")
					found += r.amount
				end
				h:Advance(1)
			end
			expect(found).toBeGreaterThan(0)
			expect(h:System("Eggs"):Count(p)).toBe(before + found)
		end)

		it("makes every coin jar hold longer while a guard is on duty", function()
			local h, p, M = boot()
			local base = h:Session(p, "Ranch").caps[1]
			local m = adult(M, p, { rarity = 6 })
			m.lv, m.stars = 50, 5
			h:Call(p, "Jobs.Assign", { slot = 1, job = "guard", id = m.id })
			local guarded = h:Session(p, "Ranch").caps[1]
			expect(guarded - base).toBe(JobsLogic.GuardSeconds({ m }))
			expect(guarded - base).toBeGreaterThan(40 * 60)
			h:Advance(1)
			h:Call(p, "Jobs.Recall", { slot = 1 })
			expect(h:Session(p, "Ranch").caps[1]).toBe(base)
		end)

		it("slows the Mood drop of pen monsters while a herder works", function()
			local h, p, M = boot()
			local penned = adult(M, p)
			h:Call(p, "Ranch.Assign", { id = penned.id, pen = 1 })
			local barn = adult(M, p)
			penned.mood, barn.mood = 80, 80
			local herder = adult(M, p, { rarity = 6 })
			herder.lv, herder.stars = 50, 5
			h:Advance(1)
			h:Call(p, "Jobs.Assign", { slot = 1, job = "herder", id = herder.id })
			h:Advance(Config.Economy.Mood.decayEvery * 3 + 1)
			expect(penned.mood).toBe(80) -- a maxed herder is a full shield
			expect(barn.mood).toBeLessThan(80) -- only pen monsters are herded
		end)

		it("frees the slot of a worker that leaves the ranch", function()
			local h, p, M = boot()
			local m = adult(M, p)
			h:Call(p, "Jobs.Assign", { slot = 1, job = "miner", id = m.id })
			h.kernel.Bus:Publish("MonsterRemoved", p, { id = m.id, reason = "rebirth" })
			expect(h:Section(p, "Jobs").slots[1].job).toBe(false)
		end)

		it("keeps working offline and says so on the way back", function()
			local h, p, M = boot()
			local m = adult(M, p)
			h:Call(p, "Jobs.Assign", { slot = 1, job = "forager", id = m.id })
			local welcome = {}
			h.kernel.Bus:Subscribe("WelcomeItem", function(_, detail)
				table.insert(welcome, detail)
			end)
			local p2 = h:Rejoin(p, 3 * HOUR)
			local slot = h:Section(p2, "Jobs").slots[1]
			expect(slot.job).toBe("forager")
			expect(h:System("Monsters"):Get(p2, m.id).busy).toBe("job")
			local said = false
			for _, item in welcome do
				if item.kind == "jobs" then
					said = true
					expect(item.text).toContain("Job Board")
				end
			end
			expect(said).toBe(true)
			local res = h:Call(p2, "Jobs.Collect")
			expect(res.rewards[1].amount).toBeNear(JobsLogic.FoodPerHour(h:System("Monsters"):Get(p2, m.id)) * 3, 1)
		end)
	end)

	describe("Luck that counts", function()
		it("adds crit chance from Luck, capped", function()
			expect(BattleSim.LuckCrit(0)).toBe(0)
			expect(BattleSim.LuckCrit(13)).toBeNear(0.008, 0.002)
			expect(BattleSim.LuckCrit(156)).toBeNear(0.056, 0.004)
			expect(BattleSim.LuckCrit(1e6)).toBe(BattleSim.LuckCritMax)
		end)

		it("gives arena fighters the same Luck whatever their genes", function()
			local a = worker({ genes = uniform(10, 10) })
			local b = worker({ genes = uniform(0, 0) })
			local na, nb = Arena.Normalize(a), Arena.Normalize(b)
			expect(Formulas.Stats(na).luck).toBe(Formulas.Stats(nb).luck)
		end)

		it("turns a squad's Luck into a loot bonus, capped at +15%", function()
			expect(Loot.LuckBonus({})).toBe(0)
			expect(Loot.LuckBonus({ 156 })).toBeNear(0.034, 0.003)
			expect(Loot.LuckBonus({ 156, 156, 156, 156, 156 })).toBe(Loot.LuckLootMax)
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions" } })
			local p = h:Join()
			local M = h:System("Monsters")
			local lucky = M:Create(p, { line = "cindlet", rarity = 6, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
			lucky.lv, lucky.stars = 50, 5
			local plain = M:Create(p, { line = "cindlet", rarity = 1, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
			local E = h:System("Expeditions")
			expect(E:LootBonus(p, { lucky.id }) - E:LootBonus(p, { plain.id })).toBeGreaterThan(0.02)
		end)

		it("gives Luck a gene that raises the Luck stat", function()
			expect(Config.Genetics.Stats[5]).toBe("luck")
			expect(Genetics.MaxTotal).toBe(100)
			local plain = worker({ genes = uniform(0, 0) })
			local lucky = worker({ genes = (function()
				local g = uniform(0, 0)
				g.luck = { 10, 10 }
				return g
			end)() })
			expect(Formulas.Stats(lucky).luck).toBeNear(Formulas.Stats(plain).luck * 1.2, 1)
		end)

		it("adds only a Luck pair to 3.6 genes and keeps the other four", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters" } })
			local userId = 6262
			local old = { hp = { 5, 0 }, atk = { 2, 4 }, def = { 4, 2 }, spd = { 0, 2 } }
			local function save()
				return {
					v = 1,
					data = {
						_meta = { created = 1690000000, lastSeen = 1700000500, joins = 9, playSeconds = 999, versions = { Monsters = 2 } },
						Monsters = {
							list = {
								m3 = {
									line = "coralbun",
									stage = 1,
									form = Config.Species.ById.coralbun.forms[1].id,
									rarity = 1,
									variant = 0,
									muts = {},
									traits = { 3, 4 },
									hidden = 5,
									weight = 2,
									lv = 1,
									stars = 1,
									mood = 70,
									meals = {},
									growEndsAt = 0,
									loc = "barn",
									pen = 0,
									busy = false,
									name = "",
									locked = false,
									born = 1790320887,
									gen = 0,
									genes = table.clone(old),
								},
							},
							codex = {},
							nextId = 4,
							grown = 0,
						},
					},
				}
			end
			h.adapters.store["player_" .. userId] = save()
			local p = h:Join(userId, "Veteran")
			local genes = h:Section(p, "Monsters").list.m3.genes
			expect(h.kernel.Data:Get(p)._meta.versions.Monsters).toBe(3)
			for stat, pair in old do
				expect(genes[stat]).toEqual(pair)
			end
			expect(Genetics.Valid(genes)).toBe(true)
			-- Not the HP pair again: the Luck pair has a seed of its own.
			local seed = Rng.seed("genes", "m3", 1790320887)
			expect(genes.luck).toEqual(Genetics.Fill(old, Rng.new(Rng.seed(seed, "fill"))).luck)
			-- A second server migrates the same save to the same genes.
			local h2 = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters" } })
			h2.adapters.store["player_" .. userId] = save()
			local p2 = h2:Join(userId, "Veteran")
			expect(h2:Section(p2, "Monsters").list.m3.genes).toEqual(genes)
		end)
	end)
end
