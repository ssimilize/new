--[[
	Genetics (update 3.6): stat genes. The rules (Logic/Genetics), what genes do to stats and
	nothing else (Formulas), where genes come from (hatching, breeding, the save migration,
	trades and the Market), and that the rolls made before genes existed are unchanged.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Genetics = t.Shared("Logic.Genetics")
	local Formulas = t.Shared("Logic.Formulas")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local BreedingLogic = t.Shared("Logic.Breeding")
	local Rng = t.Shared("Logic.Rng")

	local Rules = Config.Genetics

	local function genes(hp, atk, def, spd)
		return { hp = hp, atk = atk, def = def, spd = spd }
	end

	local function uniform(a, b)
		return genes({ a, b }, { a, b }, { a, b }, { a, b })
	end

	local function adultRecord(fields)
		local m = { line = "cindlet", stage = 3, rarity = 3, lv = 12, stars = 2, traits = { 4, 6 }, hidden = 20, muts = {}, weight = 3 }
		for k, v in fields or {} do
			m[k] = v
		end
		return m
	end

	describe("Genetics rules", function()
		it("gives HP, ATK, DEF and SPD genes and none to Luck", function()
			expect(Rules.Stats).toEqual({ "hp", "atk", "def", "spd" })
			expect(Genetics.MaxTotal).toBe(80)
			expect(Genetics.Points(uniform(4, 5), "luck")).toBe(0)
		end)

		it("rolls hatch genes inside the hatch range and repeats them for a seed", function()
			local lo, hi = Rules.HatchRange[1], Rules.HatchRange[2]
			local seen = {}
			for seed = 1, 200 do
				local g = Genetics.Roll(Rng.new(seed))
				expect(Genetics.Valid(g)).toBe(true)
				for _, stat in Rules.Stats do
					for _, v in g[stat] do
						expect(v).toBeAtLeast(lo)
						expect(v).toBeAtMost(hi)
						seen[v] = true
					end
				end
			end
			for v = lo, hi do
				expect(seen[v]).toBe(true)
			end
			expect(Genetics.Seeded(77)).toEqual(Genetics.Seeded(77))
			expect(Genetics.Seeded(77)).toEqual(Genetics.Roll(Rng.new(77)))
		end)

		it("adds one percent per point and grades the pair", function()
			local g = genes({ 10, 10 }, { 7, 8 }, { 0, 3 }, { 5, 5 })
			expect(Genetics.Points(g, "hp")).toBe(20)
			expect(Genetics.Bonus(g, "hp")).toBeNear(0.20)
			expect(Genetics.Bonus(g, "atk")).toBeNear(0.15)
			expect(Genetics.Total(g)).toBe(48)
			local expected =
				{ [0] = "D", [4] = "D", [5] = "C", [9] = "C", [10] = "B", [13] = "B", [14] = "A", [17] = "A", [18] = "S", [20] = "S" }
			for points, grade in expected do
				expect(Genetics.Grade(points).grade).toBe(grade)
			end
		end)

		it("rejects broken genes and reads missing genes as zero", function()
			expect(Genetics.Valid(nil)).toBe(false)
			expect(Genetics.Valid(uniform(0, 10))).toBe(true)
			expect(Genetics.Valid(uniform(0, 11))).toBe(false)
			expect(Genetics.Valid(uniform(-1, 2))).toBe(false)
			expect(Genetics.Valid(uniform(2.5, 2))).toBe(false)
			expect(Genetics.Valid({ hp = { 1, 1 }, atk = { 1, 1 }, def = { 1, 1 } })).toBe(false)
			expect(Genetics.Total(nil)).toBe(0)
			expect(Genetics.Bonus(nil, "atk")).toBe(0)
			expect(Genetics.Copy(nil)).toEqual(uniform(0, 0))
		end)

		it("gives a baby one gene of each parent's pair", function()
			local a = genes({ 1, 9 }, { 2, 2 }, { 3, 4 }, { 0, 10 })
			local b = genes({ 5, 6 }, { 7, 7 }, { 8, 0 }, { 1, 2 })
			local counts = {}
			local N = 4000
			for seed = 1, N do
				local baby = Genetics.Inherit(Rng.new(seed), a, b)
				expect(Genetics.Valid(baby)).toBe(true)
				for _, stat in Rules.Stats do
					local fromA, fromB = baby[stat][1], baby[stat][2]
					local a1, a2 = a[stat][1], a[stat][2]
					local b1, b2 = b[stat][1], b[stat][2]
					-- Each gene is a parent's gene, or that gene after a +1 / +2 surge.
					local function fromPair(v, p1, p2)
						for _, base in { p1, p2 } do
							if v == base or v == math.min(Rules.MaxGene, base + 1) or v == math.min(Rules.MaxGene, base + 2) then
								return true
							end
						end
						return false
					end
					expect(fromPair(fromA, a1, a2)).toBe(true)
					expect(fromPair(fromB, b1, b2)).toBe(true)
				end
				counts[baby.hp[1]] = (counts[baby.hp[1]] or 0) + 1
			end
			-- HP from parent A is its 1 or its 9 about half the time each (surges move a few).
			local ones = (counts[1] or 0) / N
			local nines = (counts[9] or 0) / N
			expect(ones).toBeNear(0.5 * (1 - Rules.SurgeChance - Rules.BigSurgeChance), 0.04)
			expect(nines).toBeNear(0.5 * (1 - Rules.SurgeChance - Rules.BigSurgeChance), 0.04)
		end)

		it("surges about SurgeChance + BigSurgeChance of genes and never past the cap", function()
			local zero = uniform(0, 0)
			local surged, plusTwo, total, reported = 0, 0, 0, 0
			for seed = 1, 3000 do
				local baby, surges = Genetics.Inherit(Rng.new(seed), zero, zero)
				reported += surges
				for _, stat in Rules.Stats do
					for _, v in baby[stat] do
						total += 1
						if v > 0 then
							surged += 1
						end
						if v == 2 then
							plusTwo += 1
						end
					end
				end
			end
			expect(reported).toBe(surged)
			expect(surged / total).toBeNear(Rules.SurgeChance + Rules.BigSurgeChance, 0.01)
			expect(plusTwo / total).toBeNear(Rules.BigSurgeChance, 0.004)

			local top = uniform(Rules.MaxGene, Rules.MaxGene)
			for seed = 1, 300 do
				local baby, surges = Genetics.Inherit(Rng.new(seed), top, top)
				expect(baby).toEqual(top)
				expect(surges).toBe(0)
			end
		end)

		it("repeats a baby for a seed and previews its range before surges", function()
			local a = genes({ 1, 9 }, { 2, 2 }, { 3, 4 }, { 0, 10 })
			local b = genes({ 5, 6 }, { 7, 7 }, { 8, 0 }, { 1, 2 })
			expect(Genetics.Inherit(Rng.new(9), a, b)).toEqual(Genetics.Inherit(Rng.new(9), a, b))
			local lo, hi = Genetics.Range(a, b, "hp")
			expect(lo).toBe(6)
			expect(hi).toBe(15)
			local preview = Genetics.Preview(a, b)
			expect(#preview.stats).toBe(4)
			expect(preview.stats[4]).toEqual({ stat = "spd", lo = 1, hi = 12 })
			expect(preview.surgeChance).toBeNear(Rules.SurgeChance + Rules.BigSurgeChance)
		end)
	end)

	describe("Genes and stats", function()
		it("leaves a monster without genes, or with zero genes, exactly as it was", function()
			local plain = Formulas.Stats(adultRecord())
			expect(Formulas.Stats(adultRecord({ genes = uniform(0, 0) }))).toEqual(plain)
		end)

		it("multiplies HP, ATK, DEF and SPD by their gene bonus and leaves Luck alone", function()
			local plain = Formulas.Stats(adultRecord())
			local g = genes({ 10, 10 }, { 7, 8 }, { 0, 3 }, { 5, 0 })
			local boosted = Formulas.Stats(adultRecord({ genes = g }))
			for _, stat in Rules.Stats do
				expect(boosted[stat]).toBeNear(plain[stat] * (1 + Genetics.Bonus(g, stat)), 1)
				expect(boosted[stat]).toBeAtLeast(plain[stat])
			end
			expect(boosted.hp).toBeGreaterThan(plain.hp)
			expect(boosted.luck).toBe(plain.luck)
			expect(Formulas.MonsterPower(adultRecord({ genes = g }))).toBeGreaterThan(Formulas.MonsterPower(adultRecord()))
		end)

		it("never changes coins, value, price, the fee or how a monster looks", function()
			local Appearance = t.Shared("Logic.Appearance")
			local form = Config.Species.Form("cindlet", 3).id
			local plain = adultRecord({ id = "m1", form = form, variant = 0, genes = uniform(0, 0) })
			local perfect = adultRecord({ id = "m1", form = form, variant = 0, genes = uniform(10, 10) })
			expect(Formulas.CoinRate(perfect)).toBe(Formulas.CoinRate(plain))
			expect(Formulas.Value(perfect)).toBe(Formulas.Value(plain))
			expect(Formulas.SellPrice(perfect)).toBe(Formulas.SellPrice(plain))
			expect(BreedingLogic.Fee(perfect, perfect)).toBe(BreedingLogic.Fee(plain, plain))
			expect(Appearance.Of(perfect)).toEqual(Appearance.Of(plain))
		end)
	end)

	describe("Where genes come from", function()
		it("rolls genes for a new monster last, so every earlier roll is unchanged", function()
			local spec = { line = "cindlet", rarity = 2 }
			local rolled = MonsterGen.New(Rng.new(31), spec, 0)
			expect(Genetics.Valid(rolled.genes)).toBe(true)
			local given = uniform(3, 4)
			local copied = MonsterGen.New(Rng.new(31), { line = "cindlet", rarity = 2, genes = given }, 0)
			expect(copied.genes).toEqual(given)
			expect(copied.genes ~= given).toBe(true) -- a copy, not the spec's table
			for key, value in rolled do
				if key ~= "genes" then
					expect(copied[key]).toEqual(value)
				end
			end
		end)

		it("inherits genes in the breeding roll after every other roll", function()
			local a = adultRecord({ genes = uniform(1, 9) })
			local b = adultRecord({ line = "bubblin", genes = uniform(2, 8) })
			local a0 = adultRecord({ genes = uniform(0, 0) })
			local b0 = adultRecord({ line = "bubblin", genes = uniform(0, 0) })
			for seed = 1, 40 do
				local spec = BreedingLogic.Roll(Rng.new(seed), a, b)
				local same = BreedingLogic.Roll(Rng.new(seed), a0, b0)
				expect(Genetics.Valid(spec.genes)).toBe(true)
				expect(type(spec.surges)).toBe("number")
				for key, value in spec do
					if key ~= "genes" and key ~= "surges" then
						expect(same[key]).toEqual(value)
					end
				end
			end
			local o = BreedingLogic.Outcomes(a, b)
			expect(o.genes).toEqual(Genetics.Preview(a.genes, b.genes))
		end)

		it("hatches, rewards and breeds monsters with genes on the server", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Breeding" } })
			local p = h:Join()
			local P = h:System("Progression")
			while P:GetLevel(p) < 12 do
				P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
			end
			h:System("Currency"):Add(p, "coins", 1e9, "test")
			local M = h:System("Monsters")
			local a = M:Create(p, { line = "cindlet", rarity = 2, stage = 3, genes = uniform(9, 10) }, "test", true)
			local b = M:Create(p, { line = "bubblin", rarity = 2, stage = 3, genes = uniform(9, 10) }, "test", true)
			local hatched = M:Create(p, { line = "mossbun", rarity = 1 }, "test", true)
			expect(Genetics.Valid(hatched.genes)).toBe(true)
			expect(Genetics.Total(hatched.genes)).toBeAtMost(8 * Rules.HatchRange[2])
			expect(h:Client(p).profile.Monsters.list[hatched.id].genes).toEqual(hatched.genes)

			h:Call(p, "Breeding.Start", { pod = 1, a = a.id, b = b.id })
			h:Advance(Config.Breeding.Seconds[2])
			local claim = h:Call(p, "Breeding.Claim", { pod = 1 })
			local baby = M:Get(p, claim.monster.id)
			expect(Genetics.Valid(baby.genes)).toBe(true)
			for _, stat in Rules.Stats do
				for _, v in baby.genes[stat] do
					expect(v).toBeAtLeast(9)
				end
			end
			expect(type(claim.surges)).toBe("number")
			expect(claim.monster.genes).toEqual(baby.genes)
		end)

		it("gives a pre-genetics save fixed genes that only ever add power", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters" } })
			local userId = 5151
			local function oldMonster(fields)
				local m = {
					line = "cindlet",
					stage = 3,
					form = Config.Species.Form("cindlet", 3).id,
					rarity = 4,
					variant = 0,
					muts = {},
					traits = { 3, 4 },
					hidden = 5,
					weight = 3,
					lv = 20,
					stars = 3,
					mood = 80,
					meals = {},
					growEndsAt = 0,
					loc = "barn",
					pen = 0,
					busy = false,
					name = "",
					locked = false,
					born = 1700000000,
					gen = 2,
				}
				for k, v in fields or {} do
					m[k] = v
				end
				return m
			end
			local function oldSave()
				return {
					v = 1,
					data = {
						_meta = { created = 1690000000, lastSeen = 1700000500, joins = 9, playSeconds = 999, versions = { Monsters = 1 } },
						Monsters = {
							list = { m1 = oldMonster(), m2 = oldMonster({ line = "bubblin", form = Config.Species.Form("bubblin", 3).id }) },
							codex = {},
							nextId = 3,
							grown = 4,
						},
					},
				}
			end
			h.adapters.store["player_" .. userId] = oldSave()
			local before = Formulas.Stats(oldMonster())
			local p = h:Join(userId, "Veteran")
			local list = h:Section(p, "Monsters").list
			expect(h.kernel.Data:Get(p)._meta.versions.Monsters).toBe(2)
			for id, m in list do
				expect(Genetics.Valid(m.genes)).toBe(true)
				expect(m.genes).toEqual(Genetics.Seeded(Rng.seed("genes", id, m.born)))
			end
			expect(list.m1.genes ~= list.m2.genes).toBe(true)
			local after = Formulas.Stats(list.m1)
			for _, stat in Rules.Stats do
				expect(after[stat]).toBeAtLeast(before[stat])
			end
			expect(after.luck).toBe(before.luck)
			expect(h:Client(p).profile.Monsters.list.m1.genes).toEqual(list.m1.genes)

			-- The same save migrated again (another server) gets the same genes.
			local h2 = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters" } })
			h2.adapters.store["player_" .. userId] = oldSave()
			local p2 = h2:Join(userId, "Veteran")
			expect(h2:Section(p2, "Monsters").list.m1.genes).toEqual(list.m1.genes)
		end)

		it("keeps genes through a trade insert and gives an old escrowed record genes", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters" } })
			local p = h:Join()
			local M = h:System("Monsters")
			local source = MonsterGen.New(Rng.new(3), { line = "cindlet", rarity = 3, genes = uniform(6, 7) }, 0)
			local kept = M:Insert(p, source, "trade")
			expect(kept.genes).toEqual(uniform(6, 7))
			expect(kept.genes ~= source.genes).toBe(true)
			local old = table.clone(source)
			old.genes = nil
			local given = M:Insert(p, old, "market")
			expect(Genetics.Valid(given.genes)).toBe(true)
		end)

		it("shows genes in a Market listing's public view, and none for an egg", function()
			local Listing = t.Server("Systems.Market.Listing")
			local record = MonsterGen.New(Rng.new(4), { line = "cindlet", rarity = 3, genes = uniform(2, 9) }, 0)
			record.id = "m9"
			expect(Listing.ItemView("monster", record).genes).toEqual(uniform(2, 9))
			record.genes = nil
			expect(Listing.ItemView("monster", record).genes).toBe(false)
			expect(Listing.ItemView("egg", { type = "meadow", source = "test", t = 0 }).genes).toBe(false)
		end)
	end)
end
