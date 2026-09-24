-- Shared logic: RNG determinism, formulas, formatting, mutation rules, config integrity.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect

	describe("Rng", function()
		local Rng = t.Shared("Logic.Rng")
		it("is deterministic for a seed", function()
			local a, b = Rng.new(42), Rng.new(42)
			for _ = 1, 50 do
				expect(a:Next()).toBe(b:Next())
			end
		end)
		it("stays in range and is roughly uniform", function()
			local r = Rng.new(7)
			local buckets = { 0, 0, 0, 0 }
			for _ = 1, 8000 do
				local v = r:Next()
				expect(v >= 0 and v < 1).toBe(true)
				local i = r:Int(1, 4)
				buckets[i] += 1
			end
			for _, n in buckets do
				expect(n).toBeGreaterThan(1800)
				expect(n).toBeLessThan(2200)
			end
		end)
		it("respects weights", function()
			local r = Rng.new(99)
			local hits = { 0, 0, 0 }
			for _ = 1, 10000 do
				local i = r:Weighted({ 75, 22, 3 })
				hits[i] += 1
			end
			expect(hits[1]).toBeGreaterThan(7200)
			expect(hits[3]).toBeGreaterThan(200)
			expect(hits[3]).toBeLessThan(420)
		end)
		it("hashes strings stably", function()
			expect(Rng.hash("meadow|1")).toBe(Rng.hash("meadow|1"))
			expect(Rng.hash("a") ~= Rng.hash("b")).toBe(true)
		end)
	end)

	describe("Formulas", function()
		local Formulas = t.Shared("Logic.Formulas")
		local MonsterGen = t.Shared("Logic.MonsterGen")
		local Rng = t.Shared("Logic.Rng")
		local function make(spec)
			return MonsterGen.New(Rng.new(1), spec, 0)
		end
		it("gives a common baby 0.4 coins/s at mood 70 without traits", function()
			local m = make({ line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5, variant = 0 })
			expect(Formulas.CoinRate(m)).toBeNear(0.4 * (0.9 + 70 / 500), 1e-9)
		end)
		it("scales with level, stars, variant and mutations", function()
			local m = make({ line = "cindlet", rarity = 4, stage = 3, traits = { 3, 4 }, hidden = 5, variant = 1, muts = { "soaked" } })
			m.lv, m.stars, m.mood = 11, 2, 100
			local expected = 25 * 1.0 * 1.07 ^ 10 * 1.25 * 3 * 1.5 * 1.1
			expect(Formulas.CoinRate(m)).toBeNear(expected, 1e-6)
		end)
		it("caps levels by stage and stars", function()
			local m = make({ line = "cindlet", rarity = 1 })
			expect(Formulas.LevelCap(m)).toBe(10)
			m.stage = 3
			m.stars = 5
			expect(Formulas.LevelCap(m)).toBe(50)
		end)
		it("requires level and meals before growing", function()
			local m = make({ line = "cindlet", rarity = 1 })
			expect((Formulas.CanGrow(m))).toBe(false)
			m.lv = 10
			m.meals = { sweet = 3 }
			expect((Formulas.CanGrow(m))).toBe(true)
		end)
		it("rolls two distinct visible traits and a distinct hidden trait", function()
			local r = Rng.new(5)
			for _ = 1, 200 do
				local visible, hidden = MonsterGen.RollTraits(r)
				expect(#visible).toBe(2)
				expect(visible[1] ~= visible[2]).toBe(true)
				expect(hidden ~= visible[1] and hidden ~= visible[2]).toBe(true)
			end
		end)
		it("rolls huge weights about 1% of the time", function()
			local r = Rng.new(11)
			local huge = 0
			for _ = 1, 20000 do
				local w = MonsterGen.RollWeight(r, "pebblet")
				if w >= 12 * 1.8 then
					huge += 1
				end
			end
			expect(huge).toBeGreaterThan(120)
			expect(huge).toBeLessThan(290)
		end)
	end)

	describe("Mutation", function()
		local Mutation = t.Shared("Logic.Mutation")
		it("adds, combines, caps and ignores duplicates", function()
			local list, r = Mutation.Add({}, "soaked")
			expect(r).toBe("added")
			list, r = Mutation.Add(list, "frosted")
			expect(r).toBe("combined")
			expect(list).toEqual({ "frozen" })
			list, r = Mutation.Add(list, "soaked")
			expect(r).toBe("duplicate")
			list, r = Mutation.Add(list, "shadow")
			expect(r).toBe("added")
			list, r = Mutation.Add(list, "prismatic")
			expect(r).toBe("full")
			expect(#list).toBe(2)
		end)
	end)

	describe("Format", function()
		local Format = t.Shared("Logic.Format")
		it("shortens numbers", function()
			expect(Format.short(950)).toBe("950")
			expect(Format.short(1280)).toBe("1.28K")
			expect(Format.short(48200)).toBe("48.2K")
			expect(Format.short(1280000)).toBe("1.28M")
			expect(Format.short(2500000)).toBe("2.5M")
			expect(Format.short(312480)).toBe("312K")
		end)
		it("formats durations and clocks", function()
			expect(Format.duration(9000)).toBe("2h 30m")
			expect(Format.duration(75)).toBe("1m 15s")
			expect(Format.clock(161)).toBe("2:41")
			expect(Format.commas(1234567)).toBe("1,234,567")
		end)
	end)

	describe("Config", function()
		local Config = t.Shared("Config")
		it("has consistent species forms, pools and hybrids", function()
			for _, def in Config.Species.Lines do
				expect(#def.forms).toBe(3)
				expect(#def.forms[3]).toBeAtLeast(1)
				expect(Config.Species.Skills[def.special] ~= nil).toBe(true)
				expect(Config.Species.Passives[def.passive] ~= nil).toBe(true)
			end
			for _, line in Config.Breeding.Hybrids do
				expect(Config.Species.ById[line].hybrid).toBe(true)
			end
			for _, egg in Config.Eggs.List do
				expect(Config.Species.Pools[egg.pool] ~= nil).toBe(true)
			end
		end)
		it("uses only declared unlock keys", function()
			for _, egg in Config.Eggs.List do
				expect(Config.Unlocks.Features[egg.unlock] ~= nil).toBe(true)
			end
			for _, r in Config.Regions.List do
				expect(Config.Unlocks.Features[r.unlock] ~= nil).toBe(true)
			end
		end)
		it("picks the adult branch from the majority diet", function()
			expect(Config.Species.AdultForDiet("cindlet", { spicy = 3, sweet = 1 }).id).toBe("blazefang")
			expect(Config.Species.AdultForDiet("cindlet", { sweet = 4 }).id).toBe("hearthtail")
			expect(Config.Species.AdultForDiet("cindlet", { sweet = 2, spicy = 2 }).id).toBe("blazefang")
		end)
		it("computes element multipliers including hybrids", function()
			expect(Config.Elements.Multiplier("ember", "sprout")).toBe(1.5)
			expect(Config.Elements.Multiplier("sprout", "ember")).toBe(0.7)
			expect(Config.Elements.Multiplier("ember", "spark")).toBe(1)
			expect(Config.Elements.MultiplierMulti({ "ember", "tide" }, { "sprout" })).toBe(1.5)
			expect(Config.Elements.MultiplierMulti({ "tide" }, { "ember", "stone" })).toBe(1.5)
		end)
	end)
end
