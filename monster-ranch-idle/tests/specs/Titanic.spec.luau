--[[
	Titanic (glow-up W): the size tier above Huge. Odds and size maths as units, the split of the
	old Huge draw (no seeded roll moved), a seeded Titanic roll on the server, looks-only (no stat
	or income change), the aura budget and old saves without the new fields.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Cfg = Config.Titanic
	local Titanic = t.Shared("Logic.Titanic")
	local MonsterGen = t.Shared("Logic.MonsterGen")
	local Formulas = t.Shared("Logic.Formulas")
	local Appearance = t.Shared("Logic.Appearance")
	local AudioRules = t.Shared("Logic.Audio")
	local Rng = t.Shared("Logic.Rng")
	local Presets = t.Shared("Config.Vfx")

	local SPEC = { line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5 }

	-- The weight roll exactly as it was before glow-up W (1% Huge, else the bell curve).
	local function oldRollWeight(rng, lineId)
		local avg = Config.Species.ById[lineId].weight
		local mult
		if rng:Chance(0.01) then
			mult = rng:Float(1.8, 2.0)
		else
			local sum = 0
			for _ = 1, 4 do
				sum += rng:Next()
			end
			mult = math.clamp(1 + (sum - 2) * 0.31, 0.5, 1.79)
		end
		return math.floor(avg * mult * 100 + 0.5) / 100
	end

	-- The first seed whose MonsterGen.New(SPEC) rolls a Titanic.
	local function titanicSeed(): number
		for seed = 1, 200000 do
			if MonsterGen.New(Rng.new(seed), SPEC, 0).titanic then
				return seed
			end
		end
		error("no Titanic seed found")
	end

	local function live(specs): number
		local n = 0
		for _, spec in specs do
			local life = if type(spec.lifetime) == "table" then spec.lifetime[2] or spec.lifetime[1] else spec.lifetime
			n += (spec.rate or 0) * (life or 0)
		end
		return n
	end

	describe("Logic/Titanic", function()
		it("splits the Huge draw: Titanic below Chance, Huge below HugeChance", function()
			expect(Cfg.Chance < Cfg.HugeChance / 10).toBe(true) -- well below Huge
			expect(Titanic.Classify(0)).toBe("titanic")
			expect(Titanic.Classify(Cfg.Chance - 1e-9)).toBe("titanic")
			expect(Titanic.Classify(Cfg.Chance)).toBe("huge")
			expect(Titanic.Classify(Cfg.HugeChance - 1e-9)).toBe("huge")
			expect(Titanic.Classify(Cfg.HugeChance)).toBeNil()
			local odds = Titanic.Odds()
			expect(math.abs(odds.huge + odds.titanic - Cfg.HugeChance) < 1e-12).toBe(true)
			expect(odds.titanic).toBe(Cfg.Chance)
			expect(Titanic.WeightMult("titanic", 0)).toBe(Cfg.WeightMult[1])
			expect(Titanic.WeightMult("titanic", 1)).toBe(Cfg.WeightMult[2])
			expect(math.abs(Titanic.WeightMult("huge", 0.5) - 1.9) < 1e-9).toBe(true)
			expect(Titanic.WeightMult(nil, 0.5)).toBeNil()
		end)

		it("sizes a Titanic at Scale, capped at PenScale in a pen; others by weight", function()
			local avg = Config.Species.ById.cindlet.weight
			local big = { line = "cindlet", weight = avg * 2.3, titanic = true }
			expect(Titanic.SizeMult(big)).toBe(Cfg.Scale)
			expect(Titanic.SizeMult(big, true)).toBe(Cfg.PenScale)
			expect(Cfg.PenScale < Cfg.Scale).toBe(true)
			expect(math.abs(Cfg.Scale - 3) < 0.25).toBe(true) -- "about 3× size"
			local huge = { line = "cindlet", weight = avg * 2 }
			expect(Titanic.SizeMult(huge)).toBe(math.clamp(2 ^ (1 / 3), 0.8, 1.3))
			expect(Titanic.SizeMult(huge, true)).toBe(Titanic.SizeMult(huge)) -- the cap is Titanic only
			expect(Titanic.SizeMult({ line = "cindlet", weight = avg })).toBe(1)
			expect(Titanic.SizeMult({ line = "cindlet", weight = avg * 0.1 })).toBe(0.8)
		end)

		it("gives a Titanic a deeper cry", function()
			local base = AudioRules.VoicePitch({ line = "cindlet", stage = 3, height = 3 })
			local deep = AudioRules.VoicePitch({ line = "cindlet", stage = 3, height = 3, titanic = true })
			expect(math.abs(deep - base * Cfg.CryPitch) < 1e-9).toBe(true)
			expect(deep < base).toBe(true)
		end)

		it("keeps the Titanic aura inside its particle budget", function()
			expect(type(Presets.Titanic) == "table" and #Presets.Titanic > 0).toBe(true)
			expect(live(Presets.Titanic) <= Presets.Budget.titanic).toBe(true)
			for _, spec in Presets.Titanic do
				expect(Presets.Sprites[spec.sprite] ~= nil).toBe(true)
			end
		end)
	end)

	describe("MonsterGen.RollSize", function()
		it("moves no seeded roll: same draws and same weights as the old Huge roll", function()
			local titanics = 0
			for seed = 1, 3000 do
				local a, b = Rng.new(seed), Rng.new(seed)
				local old = oldRollWeight(a, "cindlet")
				local weight, titanic = MonsterGen.RollSize(b, "cindlet")
				expect(a:State()).toBe(b:State())
				if titanic then
					titanics += 1
				else
					expect(weight).toBe(old)
				end
			end
			expect(titanics < 10).toBe(true)
		end)

		it("rolls Titanic about Chance of the time with a Titanic weight", function()
			local rng = Rng.new(Rng.seed("titanic-odds"))
			local avg = Config.Species.ById.cindlet.weight
			local n, titanic, huge = 200000, 0, 0
			for _ = 1, n do
				local weight, isTitanic = MonsterGen.RollSize(rng, "cindlet")
				if isTitanic then
					titanic += 1
					expect(weight >= avg * Cfg.WeightMult[1] - 0.01 and weight <= avg * Cfg.WeightMult[2] + 0.01).toBe(true)
				elseif weight >= avg * Config.Social.HugeWeightMult then
					huge += 1
				end
			end
			local expected = n * Cfg.Chance
			expect(titanic > expected * 0.5 and titanic < expected * 1.5).toBe(true)
			expect(huge > titanic * 10).toBe(true)
		end)

		it("sets titanic only on Titanic records and honours a forced spec", function()
			local seed = titanicSeed()
			local m = MonsterGen.New(Rng.new(seed), SPEC, 0)
			expect(m.titanic).toBe(true)
			expect(Formulas.IsHuge(m)).toBe(true) -- a Titanic is heavy too
			expect(MonsterGen.New(Rng.new(seed - 1), SPEC, 0).titanic).toBeNil() -- the first such seed
			local forced = MonsterGen.New(Rng.new(1), { line = "cindlet", rarity = 1, titanic = true }, 0)
			expect(forced.titanic).toBe(true)
			local bred = MonsterGen.New(Rng.new(seed), { line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5, weight = 3 }, 0)
			expect(bred.titanic).toBeNil() -- a given weight (breeding) never rolls the tier
		end)
	end)

	describe("Titanic on the server", function()
		it("rolls a seeded Titanic through Monsters:Create; looks only, no stat change", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Monsters" } })
			local p = h:Join()
			local M = h:System("Monsters")
			h.kernel.Rng._state = Rng.new(titanicSeed()):State()
			local m = M:Create(p, table.clone(SPEC), "hatch", true)
			expect(m.titanic).toBe(true)
			local avg = Config.Species.ById.cindlet.weight
			expect(m.weight >= avg * Cfg.WeightMult[1] - 0.01).toBe(true)
			local ap = M:Appearance(p, m.id)
			expect(ap.titanic).toBe(true)
			expect(h:Client(p).profile.Monsters.list[m.id].titanic).toBe(true)
			-- No pay-to-win: stats, power and income ignore the tier.
			local plain = table.clone(m)
			plain.titanic = nil
			expect(Formulas.Stats(m)).toEqual(Formulas.Stats(plain))
			expect(Formulas.CoinRate(m)).toBe(Formulas.CoinRate(plain))
			expect(Formulas.SellPrice(m)).toBe(Formulas.SellPrice(plain))
		end)

		it("loads an old save (no Titanic or edition fields) as ordinary monsters", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Monsters", "Editions" } })
			local p = h:Join()
			local M = h:System("Monsters")
			local m = M:Create(p, { line = "lanternling", rarity = 2 }, "test", true)
			-- A record as saved before glow-up W: no titanic / ltd / ltdNo / ltdOf.
			m.titanic, m.ltd, m.ltdNo, m.ltdOf = nil, nil, nil, nil
			local p2 = h:Rejoin(p)
			local again = M:Get(p2, m.id)
			expect(again ~= nil).toBe(true)
			expect(again.ltd).toBeNil() -- an event monster from before the update is never numbered later
			expect(again.ltdNo).toBeNil()
			local ap = M:Appearance(p2, m.id)
			expect(ap.titanic).toBeNil()
			expect(ap.ltdNo).toBeNil()
			expect(Titanic.SizeMult(ap)).toBe(Titanic.SizeMult(Appearance.Of(again)))
			expect(h:System("Editions"):Pending(p2)).toBe(0)
		end)
	end)
end
