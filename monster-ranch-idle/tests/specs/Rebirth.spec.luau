-- Update 1.4 · Ranch Rebirth (prestige layer 2), the Stardust skill tree, Rebirth Stars,
-- biome themes and the 3rd trait slot.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local R = Config.Rebirth

	local SYSTEMS = {
		"Currency",
		"Progression",
		"Rewards",
		"Monsters",
		"Eggs",
		"Shop",
		"Ranch",
		"Expeditions",
		"Breeding",
		"Rebirth",
	}

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function monster(h, p, line: string, rarity: number, stars: number?)
		local m = h:System("Monsters"):Create(p, { line = line, rarity = rarity, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
		m.stars = stars or 1
		return m
	end

	-- A Level 40 ranch with enough coins for its next star and a few monsters.
	local function ready()
		local h = TestKernel.new({ systems = SYSTEMS })
		local p = h:Join()
		levelTo(h, p, 40)
		h:System("Currency"):Add(p, "coins", R.CoinsNeeded(0), "test")
		return h, p
	end

	local function topicLog(h, topic: string)
		local seen = {}
		h.kernel.Bus:Subscribe(topic, function(_player, detail)
			table.insert(seen, detail)
		end)
		return seen
	end

	describe("Rebirth rules", function()
		it("needs Ranch Level 40 and the coins for the next star", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local m = monster(h, p, "cindlet", 2)
			expect(h:Reject(p, "Rebirth.Rebirth", { keep = { m.id } })).toBe("Unlocks at Ranch Level 40")
			levelTo(h, p, 40)
			expect(h:Reject(p, "Rebirth.Rebirth", { keep = { m.id } })).toBe(string.format("Save up %d coins to rebirth", R.CoinsNeeded(0)))
			expect(R.CoinsNeeded(1)).toBe(3 * R.CoinsNeeded(0))
		end)

		it("keeps 1 to Heirlooms monsters, all of them home", function()
			local h, p = ready()
			local ids = {}
			for i = 1, 5 do
				ids[i] = monster(h, p, "cindlet", 1).id
			end
			expect(h:System("Rebirth"):Heirlooms(p)).toBe(3)
			expect(h:Reject(p, "Rebirth.Rebirth", { keep = { ids[1], ids[2], ids[3], ids[4] } })).toBe(
				"You can keep up to 3 Heirloom monsters"
			)
			expect(h:Reject(p, "Rebirth.Rebirth", { keep = { "m999" } })).toBe("That monster doesn't exist")
			expect(h:Reject(p, "Rebirth.Rebirth", { keep = {} })).toBeTruthy()
			h:System("Monsters"):SetBusy(p, ids[5], "expedition")
			h:Advance(5)
			expect(h:Reject(p, "Rebirth.Rebirth", { keep = { ids[1] } })).toBe(
				"Bring every monster home first (expeditions, breeding and trades)"
			)
			-- Duplicates count once.
			h:System("Monsters"):SetBusy(p, ids[5], false)
			h:Advance(5)
			local data = h:Call(p, "Rebirth.Rebirth", { keep = { ids[1], ids[1], ids[2], ids[3] } })
			expect(data.kept).toBe(3)
		end)
	end)

	describe("What a rebirth resets and keeps", function()
		it("resets coins, buildings and region progress; unkept monsters become Stardust", function()
			local h, p = ready()
			local Currency = h:System("Currency")
			local keep = monster(h, p, "cindlet", 4, 2)
			local gone1 = monster(h, p, "bubblin", 3, 1)
			local gone2 = monster(h, p, "mossbun", 1, 3)
			local expectDust = R.DustFor(gone1) + R.DustFor(gone2)
			expect(R.DustFor(gone1)).toBe(math.floor(Config.Rarities.List[3].stardust * 0.5))

			-- Build up the ranch first.
			Currency:Add(p, "gems", 77, "test")
			Currency:Add(p, "coins", 10000000, "test")
			h:Call(p, "Ranch.BuyPen")
			h:Call(p, "Ranch.Upgrade", { target = "barn" })
			h:Call(p, "Ranch.Upgrade", { target = "incubatorSpeed" })
			h:Call(p, "Ranch.Upgrade", { target = "jar", pen = 1 })
			h:System("Shop"):AddDecor(p, "flower_bed", 1)
			h:Call(p, "Ranch.PlaceDecor", { decor = "flower_bed", pen = 2 })
			local exp = h:Section(p, "Expeditions")
			exp.cleared.meadow = 12
			exp.cleared.coral = 3
			local codexBefore = h:System("Monsters"):CodexCount(p)
			local removed = topicLog(h, "MonsterRemoved")
			local reborn = topicLog(h, "Rebirthed")

			local data = h:Call(p, "Rebirth.Rebirth", { keep = { keep.id } })
			expect(data.stars).toBe(1)
			expect(data.stardust).toBe(expectDust)
			expect(data.theme).toBe("starfield")
			expect(reborn[1].stars).toBe(1)
			expect(#removed).toBe(2)
			expect(removed[1].reason).toBe("rebirth")

			expect(Currency:Balance(p, "coins")).toBe(0)
			expect(Currency:Balance(p, "gems")).toBe(77)
			expect(Currency:Balance(p, "stardust")).toBe(expectDust)
			local ranch = h:Section(p, "Ranch")
			expect(#ranch.pens).toBe(1)
			expect(ranch.pens[1].jarTier).toBe(1)
			expect(ranch.pens[1].theme).toBe("starfield")
			expect(ranch.pens[1].monsters).toEqual({ keep.id })
			expect(ranch.barnTier).toBe(1)
			expect(ranch.incubatorTier).toBe(1)
			expect(h:Section(p, "Shop").decor.flower_bed).toBe(1)
			expect(h:System("Shop"):OwnsTheme(p, "starfield")).toBe(true)
			expect(h:System("Shop"):OwnsTheme(p, "crystal_tundra")).toBe(false)
			expect(next(h:Section(p, "Expeditions").cleared)).toBeNil()
			expect(h:System("Monsters"):Count(p)).toBe(1)
			expect(h:System("Monsters"):Get(p, keep.id).stars).toBe(2)
			expect(h:System("Monsters"):CodexCount(p)).toBe(codexBefore)
			expect(h:System("Progression"):GetLevel(p)).toBe(40)
			expect(h:Section(p, "Rebirth").stars).toBe(1)
			expect(h:Section(p, "Rebirth").dust).toBe(expectDust)
			expect(h:Client(p).profile.Rebirth.stars).toBe(1)

			-- Saved: a rejoin keeps the star.
			p = h:Rejoin(p, 60)
			expect(h:Section(p, "Rebirth").stars).toBe(1)
			expect(h:Section(p, "Ranch").pens[1].theme).toBe("starfield")
		end)

		it("multiplies coin income by the Rebirth Stars", function()
			local h, p = ready()
			local keep = monster(h, p, "cindlet", 3)
			h:Call(p, "Ranch.Assign", { id = keep.id, pen = 1 })
			local before = h:Session(p, "Ranch").income
			expect(before).toBeGreaterThan(0)
			h:Call(p, "Rebirth.Rebirth", { keep = { keep.id } })
			expect(h:Session(p, "Ranch").income).toBeNear(before * R.CoinMult(1))
			expect(R.CoinMult(1)).toBe(1.5)
			expect(R.CoinMult(2)).toBe(2)
		end)

		it("grants a new biome and one more Heirloom with each star", function()
			local h, p = ready()
			local a = monster(h, p, "cindlet", 1)
			h:Call(p, "Rebirth.Rebirth", { keep = { a.id } })
			expect(h:System("Rebirth"):Heirlooms(p)).toBe(4)
			h:System("Currency"):Add(p, "coins", R.CoinsNeeded(1) - 1, "test")
			expect(h:Reject(p, "Rebirth.Rebirth", { keep = { a.id } })).toBe(string.format("Save up %d coins to rebirth", R.CoinsNeeded(1)))
			h:System("Currency"):Add(p, "coins", 1, "test")
			h:Advance(5)
			local data = h:Call(p, "Rebirth.Rebirth", { keep = { a.id } })
			expect(data.stars).toBe(2)
			expect(data.theme).toBe("crystal_tundra")
			expect(h:System("Shop"):OwnsTheme(p, "starfield")).toBe(true)
			expect(h:System("Shop"):OwnsTheme(p, "crystal_tundra")).toBe(true)
			expect(h:Reject(p, "Shop.BuyTheme", { theme = "nebula" })).toBe("That theme isn't for sale")
		end)
	end)

	describe("Stardust skill tree", function()
		it("follows the branch order and the star gates, and charges Stardust", function()
			local h, p = ready()
			local Currency = h:System("Currency")
			Currency:Add(p, "stardust", 5000, "test")
			expect(h:Reject(p, "Rebirth.BuySkill", { skill = "deep_pockets" })).toBe("Learn Golden Touch first")
			expect(h:Call(p, "Rebirth.BuySkill", { skill = "golden_touch" }).level).toBe(1)
			expect(Currency:Balance(p, "stardust")).toBe(5000 - R.SkillById.golden_touch.cost[1])
			h:Call(p, "Rebirth.BuySkill", { skill = "deep_pockets" })
			h:Advance(5)
			expect(h:Reject(p, "Rebirth.BuySkill", { skill = "head_start" })).toBe("Needs 1 Rebirth Star")
			h:Call(p, "Rebirth.BuySkill", { skill = "warm_hands" })
			h:Call(p, "Rebirth.BuySkill", { skill = "twin_nests" })
			expect(h:Reject(p, "Rebirth.BuySkill", { skill = "twin_nests" })).toBe("Twin Nests is already maxed")
			expect(h:System("Breeding"):BreedsPerDay(p)).toBe(Config.Breeding.BreedsPerDay + 1)
			Currency:Spend(p, { stardust = Currency:Balance(p, "stardust") }, "test")
			expect(h:Reject(p, "Rebirth.BuySkill", { skill = "golden_touch" })).toBeTruthy()
		end)

		it("feeds its effects into income, head start coins, Stardust and Heirlooms", function()
			local h, p = ready()
			local Currency = h:System("Currency")
			local keep = monster(h, p, "cindlet", 3)
			local gone = monster(h, p, "bubblin", 5, 3)
			h:Call(p, "Ranch.Assign", { id = keep.id, pen = 1 })
			local s = h:Section(p, "Rebirth")
			s.stars = 2 -- as if two rebirths were done already
			for id, level in
				{
					golden_touch = 1,
					deep_pockets = 1,
					head_start = 2,
					warm_hands = 1,
					twin_nests = 1,
					star_sifter = 1,
					trailblazer = 1,
					war_paint = 1,
				}
			do
				s.skills[id] = level
			end
			h.kernel.Bus:Publish("RateModifiersChanged", p, {})
			Currency:Add(p, "coins", R.CoinsNeeded(2), "test")
			expect(h:System("Rebirth"):Heirlooms(p)).toBe(5)
			s.skills.family_vault = 2
			expect(h:System("Rebirth"):Heirlooms(p)).toBe(7)

			local data = h:Call(p, "Rebirth.Rebirth", { keep = { keep.id } })
			expect(data.stars).toBe(3)
			expect(data.stardust).toBe(math.floor(R.DustFor(gone) * 1.15))
			expect(Currency:Balance(p, "coins")).toBe(2 * 250000)
			-- Income: ×(1 + 0.08 golden touch) × 2.5 (three stars) on the same monster.
			local base = h:System("Monsters"):CoinRate(p, keep.id)
			local Jar = t.Shared("Logic.Jar")
			expect(h:Session(p, "Ranch").income).toBeNear(Jar.MonsterRate(base, 0.08, R.CoinMult(3)))
			expect(h:Session(p, "Ranch").caps[1]).toBe(Config.Economy.JarTiers[1].seconds + 1800)
		end)
	end)

	describe("Third trait slot", function()
		it("gives every monster a 3rd visible trait from 3 Rebirth Stars", function()
			local h, p = ready()
			local keep = monster(h, p, "cindlet", 2)
			local other = monster(h, p, "mossbun", 2)
			local s = h:Section(p, "Rebirth")
			s.stars = 2
			h:System("Currency"):Add(p, "coins", R.CoinsNeeded(2), "test")
			h:Call(p, "Rebirth.Rebirth", { keep = { keep.id, other.id } })
			for _, m in h:System("Monsters"):All(p) do
				expect(#m.traits).toBe(3)
				expect(m.traits[3] ~= m.traits[1] and m.traits[3] ~= m.traits[2] and m.traits[3] ~= m.hidden).toBe(true)
				expect(Config.Traits.ById[m.traits[3]].hiddenOnly).toBeFalsy()
			end
			-- Monsters that arrive later get it too; nobody gets a 4th.
			local baby = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1 }, "hatch", true)
			expect(#baby.traits).toBe(3)
			p = h:Rejoin(p, 10)
			for _, m in h:System("Monsters"):All(p) do
				expect(#m.traits).toBe(3)
			end
		end)

		it("does nothing below 3 stars", function()
			local h, p = ready()
			local keep = monster(h, p, "cindlet", 2)
			h:Call(p, "Rebirth.Rebirth", { keep = { keep.id } })
			expect(#h:System("Monsters"):Get(p, keep.id).traits).toBe(2)
		end)
	end)
end
