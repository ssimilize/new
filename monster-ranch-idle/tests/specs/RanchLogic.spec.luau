-- S3 pure rules: Logic/EggRoll (odds, pity, lucky meter), Logic/Restock (global stock), Logic/Jar.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local Config = t.Shared("Config")
	local Rng = t.Shared("Logic.Rng")
	local EggRoll = t.Shared("Logic.EggRoll")
	local Restock = t.Shared("Logic.Restock")
	local Jar = t.Shared("Logic.Jar")
	local Eggs = Config.Eggs

	local function counts(n: number, fn)
		local out = { 0, 0, 0, 0, 0, 0 }
		for _ = 1, n do
			local r = fn()
			out[r] += 1
		end
		return out
	end

	describe("EggRoll", function()
		it("matches the published odds of a Meadow Egg", function()
			local rng = Rng.new(11)
			local n = 20000
			local c = counts(n, function()
				return (EggRoll.roll(rng, Eggs.ById.meadow)).rarity
			end)
			expect(c[1] / n).toBeNear(0.75, 0.015)
			expect(c[2] / n).toBeNear(0.22, 0.015)
			expect(c[3] / n).toBeNear(0.03, 0.006)
			expect(c[4] + c[5] + c[6]).toBe(0)
		end)

		it("never rolls a rarity with 0% odds", function()
			local rng = Rng.new(5)
			for _ = 1, 3000 do
				local spec = EggRoll.roll(rng, Eggs.ById.crystal)
				expect(spec.rarity >= 2 and spec.rarity <= 5).toBe(true)
			end
		end)

		it("draws lines uniformly from the egg's pool", function()
			local rng = Rng.new(8)
			local pool = Config.Species.Pools.common
			local seen = {}
			local n = 12000
			for _ = 1, n do
				local spec = EggRoll.roll(rng, Eggs.ById.meadow)
				seen[spec.line] = (seen[spec.line] or 0) + 1
			end
			for _, line in pool do
				expect(seen[line] or 0).toBeNear(n / #pool, n / #pool * 0.25)
			end
		end)

		it("guarantees a Legendary+ Starlit hatch within the pity count", function()
			local rng = Rng.new(99)
			local def = Eggs.ById.starlit
			local pity = { starlit = 0, royal = 0 }
			local sinceHit, longest, guarantees = 0, 0, 0
			for _ = 1, 6000 do
				local spec, result = EggRoll.roll(rng, def, { pity = pity })
				if result.guaranteed then
					guarantees += 1
					expect(pity.starlit).toBe(def.pity.count - 1)
				end
				pity = result.pity
				if spec.rarity >= def.pity.minRarity then
					sinceHit = 0
					expect(pity.starlit).toBe(0)
				else
					sinceHit += 1
					longest = math.max(longest, sinceHit)
				end
			end
			expect(longest).toBeLessThan(def.pity.count)
			expect(guarantees).toBeGreaterThan(0)
		end)

		it("pays the pity on exactly the 40th egg and resets the counter", function()
			local def = Eggs.ById.starlit
			for seed = 1, 50 do
				local spec, result = EggRoll.roll(Rng.new(seed), def, { pity = { starlit = def.pity.count - 1, royal = 3 } })
				expect(spec.rarity).toBeAtLeast(def.pity.minRarity)
				expect(result.guaranteed).toBe(true)
				expect(result.pity.starlit).toBe(0)
				expect(result.pity.royal).toBe(3) -- other counters untouched
			end
			expect(EggRoll.HatchesUntilGuarantee(def, { starlit = 12 })).toBe(28)
			expect(EggRoll.HatchesUntilGuarantee(Eggs.ById.meadow, {})).toBeNil()
		end)

		it("does not mutate the caller's pity table", function()
			local pity = { starlit = 5, royal = 0 }
			local _, result = EggRoll.roll(Rng.new(1), Eggs.ById.starlit, { pity = pity })
			expect(pity.starlit).toBe(5)
			expect(result.pity ~= pity).toBe(true)
		end)

		it("fills the Royal lucky meter: every 5th hatch is Epic or better", function()
			local rng = Rng.new(3)
			local def = Eggs.ById.royal
			local pity = { starlit = 0, royal = 0 }
			for i = 1, 500 do
				local spec, result = EggRoll.roll(rng, def, { pity = pity })
				pity = result.pity
				if i % def.luckyMeter.every == 0 then
					expect(spec.rarity).toBeAtLeast(def.luckyMeter.minRarity)
					expect(result.guaranteed).toBe(true)
					expect(pity.royal).toBe(0)
				else
					expect(result.guaranteed).toBe(false)
					expect(pity.royal).toBe(i % def.luckyMeter.every)
				end
			end
		end)

		it("rolls Stampede hybrids at the configured chance", function()
			local rng = Rng.new(21)
			local def = Eggs.ById.stampede
			local hybrids, n = 0, 20000
			local hybridSet = {}
			for _, line in Config.Species.Pools.hybrid do
				hybridSet[line] = true
			end
			for _ = 1, n do
				local spec, result = EggRoll.roll(rng, def)
				expect(result.hybrid == (hybridSet[spec.line] == true)).toBe(true)
				expect(spec.rarity).toBeAtLeast(4)
				if result.hybrid then
					hybrids += 1
				end
			end
			expect(hybrids / n).toBeNear(def.hybridChance, 0.008)
		end)

		it("forces the Frostfall mutation and draws from the event pool", function()
			local rng = Rng.new(4)
			local pool = {}
			for _, line in Config.Species.Pools.frostfall do
				pool[line] = true
			end
			for _ = 1, 200 do
				local spec = EggRoll.roll(rng, Eggs.ById.frostfall)
				expect(spec.muts).toEqual({ "frosted" })
				expect(pool[spec.line]).toBe(true)
			end
			expect((EggRoll.roll(rng, Eggs.ById.meadow)).muts).toBeNil()
		end)

		it("rolls variants with normal and Lucky Hatcher odds", function()
			local function golden(lucky: boolean)
				local rng = Rng.new(if lucky then 77 else 76)
				local n, hits, rainbows = 60000, 0, 0
				for _ = 1, n do
					local v = (EggRoll.roll(rng, Eggs.ById.meadow, { lucky = lucky })).variant
					if v == 1 then
						hits += 1
					elseif v == 2 then
						rainbows += 1
					end
				end
				return hits / n, rainbows / n
			end
			local g, r = golden(false)
			expect(g).toBeNear(Config.Rarities.VariantChance.golden, 0.004)
			expect(r).toBeNear(Config.Rarities.VariantChance.rainbow, 0.0015)
			local lg = golden(true)
			expect(lg).toBeNear(Config.Rarities.LuckyVariantChance.golden, 0.004)
		end)

		it("hatches the starter egg as an Uncommon starter line", function()
			local rng = Rng.new(2)
			local seen = {}
			for _ = 1, 300 do
				local spec = EggRoll.starter(rng)
				expect(spec.rarity).toBe(Eggs.Starter.rarity)
				expect(Eggs.Starter.lines).toContain(spec.line)
				seen[spec.line] = true
			end
			for _, line in Eggs.Starter.lines do
				expect(seen[line]).toBe(true)
			end
		end)

		it("falls back to the floor rarity when no odds reach it", function()
			expect(EggRoll.RollRarity(Rng.new(1), { 100, 0, 0, 0, 0, 0 }, 5)).toBe(5)
			for seed = 1, 30 do
				expect(EggRoll.RollRarity(Rng.new(seed), { 50, 30, 10, 5, 4, 1 }, 5)).toBeAtLeast(5)
			end
		end)
	end)

	describe("Restock", function()
		it("uses a global window clock", function()
			local s = Eggs.RestockSeconds
			expect(Restock.Window(10 * s)).toBe(10)
			expect(Restock.Window(10 * s + s - 1)).toBe(10)
			expect(Restock.EndsAt(10)).toBe(11 * s)
		end)

		it("is deterministic per window (every server shows the same stock)", function()
			for w = 5000000, 5000050 do
				expect(Restock.Roll(w)).toEqual(Restock.Roll(w))
			end
			local differs = false
			for w = 1, 40 do
				if not t.Shared("Logic.TableUtil").equal(Restock.Roll(w), Restock.Roll(w + 1)) then
					differs = true
				end
			end
			expect(differs).toBe(true)
		end)

		it("lists only eggs on sale, with -1 for unlimited", function()
			local stock = Restock.Roll(123)
			expect(stock.meadow).toBe(-1)
			expect(stock.starlit).toBe(-1)
			expect(stock.stampede).toBeNil() -- no price: boss-only
			expect(stock.frostfall).toBeNil() -- event not running
			expect(Restock.Roll(123, "frostfall").frostfall).toBe(-1)
			expect(Restock.OnSale(Eggs.ById.frostfall, "frostfall")).toBe(true)
			expect(Restock.OnSale(Eggs.ById.frostfall, "harvestmoon")).toBe(false)
		end)

		it("restocks limited eggs at their appear chance and within min..max", function()
			local n = 4000
			local seen = { grove = 0, crystal = 0, royal = 0 }
			for w = 1, n do
				local stock = Restock.Roll(w)
				for id in seen do
					local def = Eggs.ById[id]
					local v = stock[id]
					if v > 0 then
						seen[id] += 1
						expect(v >= def.stock.min and v <= def.stock.max).toBe(true)
					else
						expect(v).toBe(0)
					end
				end
			end
			expect(seen.grove).toBe(n)
			expect(seen.crystal / n).toBeNear(0.6, 0.03)
			expect(seen.royal / n).toBeNear(0.15, 0.02)
		end)
	end)

	describe("Jar", function()
		it("fills at the rate and stops at the cap", function()
			expect(Jar.Value(0, 2, 100, 110, 3600)).toBe(20)
			expect(Jar.Value(5, 2, 100, 110, 3600)).toBe(25)
			expect(Jar.Value(0, 2, 0, 1e6, 3600)).toBe(7200)
			expect(Jar.Value(0, 2, 100, 90, 3600)).toBe(0) -- clock skew never goes negative
		end)

		it("keeps settled coins when the rate drops", function()
			expect(Jar.Value(500, 0, 0, 1000, 3600)).toBe(500)
			expect(Jar.Value(500, 0.1, 0, 1000, 3600)).toBe(500) -- above the new cap: keep, stop filling
		end)

		it("settles into the pen without changing the live value", function()
			local pen = { jar = 3, jarAt = 100 }
			local before = Jar.Value(pen.jar, 1.5, pen.jarAt, 200, 60)
			Jar.Settle(pen, 1.5, 60, 150)
			expect(pen.jarAt).toBe(150)
			expect(Jar.Value(pen.jar, 1.5, pen.jarAt, 200, 60)).toBeNear(before, 1e-9)
		end)

		it("computes caps from tier, VIP, Hoarder and bonuses", function()
			local E = Config.Economy
			expect(Jar.CapSeconds(1)).toBe(E.JarTiers[1].seconds)
			expect(Jar.CapSeconds(99)).toBe(E.JarTiers[#E.JarTiers].seconds)
			expect(Jar.CapSeconds(2, { vip = true, hoarderMinutes = 30, bonusSeconds = 900 })).toBe(
				E.JarTiers[2].seconds + E.VipJarBonusSeconds + 1800 + 900
			)
		end)

		it("reports time to full and whole collectable coins", function()
			expect(Jar.SecondsToFull(0, 2, 100)).toBe(100)
			expect(Jar.SecondsToFull(500, 2, 100)).toBe(0)
			expect(Jar.SecondsToFull(0, 0, 100)).toBe(math.huge)
			expect(Jar.IsFull(200, 2, 100)).toBe(true)
			local whole, rest = Jar.Collectable(12.75)
			expect(whole).toBe(12)
			expect(rest).toBeNear(0.75)
			expect(Jar.MonsterRate(2, 0.5, 2)).toBe(6)
			expect(Jar.MonsterRate(2, -3)).toBe(0)
		end)
	end)
end
