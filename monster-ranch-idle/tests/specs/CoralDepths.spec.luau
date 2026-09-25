-- Update 1.1 · Coral Depths: Coral Coast stages 21–30 (own unlock, enemies and bosses),
-- the Pearl Egg and its three new lines, the Pearl combo mutation and the beach decor set.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Regions = Config.Regions

	local function boot(extra)
		local eggs = {}
		local systems = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions" }
		for _, name in extra or {} do
			table.insert(systems, name)
		end
		local stubs = {}
		if not table.find(systems, "Eggs") then
			stubs.Eggs = {
				Add = function(_, player, eggType, source, amount)
					table.insert(eggs, { userId = player.UserId, egg = eggType, source = source, amount = amount or 1 })
					return {}
				end,
			}
		end
		return TestKernel.new({ systems = systems, stubs = stubs }), eggs
	end

	-- A squad strong enough for the Depths bosses.
	local function strongSquad(h, p)
		local M = h:System("Monsters")
		local ids = {}
		for i, line in { "blazefang", "bubblin", "zappip" } do
			local lineId = if line == "blazefang" then "cindlet" else line
			local m = M:Create(p, { line = lineId, rarity = 6, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
			m.lv = 60
			m.stars = 5
			ids[i] = m.id
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return ids
	end

	describe("Regions", function()
		it("gives Coral Coast 30 stages with the Depths as their own band", function()
			expect(Regions.Stages("coral")).toBe(30)
			expect(Regions.Stages("meadow")).toBe(20)
			expect(Regions.MaxStages).toBe(30)
			local coast = Regions.Band("coral", 20)
			expect(coast.first).toBe(1)
			expect(coast.last).toBe(20)
			expect(coast.depths).toBe(false)
			local depths = Regions.Band("coral", 21)
			expect(depths.first).toBe(21)
			expect(depths.last).toBe(30)
			expect(depths.depths).toBe(true)
			expect(depths.name).toBe("Coral Depths")
			expect(depths.unlock).toBe("coral_depths")
			expect(Config.Unlocks.Features.coral_depths).toBeGreaterThan(Config.Unlocks.Features.region_coral)
		end)

		it("scales the Depths between early and late Ember Peaks", function()
			expect(Regions.GlobalIndex("coral", 20)).toBe(40)
			expect(Regions.GlobalIndex("coral", 21)).toBe(42)
			expect(Regions.GlobalIndex("coral", 30)).toBe(60)
			expect(Regions.GlobalIndex("ember", 1)).toBe(41)
			local BattleSim = t.Shared("Logic.BattleSim")
			local last = 0
			for stage = 21, 30 do
				local power = BattleSim.RecommendedPower("coral", stage)
				if not Regions.ById.coral.bosses[stage] then
					expect(power).toBeAtLeast(last)
					last = power
				end
			end
			expect(BattleSim.RecommendedPower("coral", 22)).toBeGreaterThan(BattleSim.RecommendedPower("coral", 19))
		end)

		it("fills Depths waves with Depths enemies and has bosses at 25 and 30", function()
			local BattleSim = t.Shared("Logic.BattleSim")
			local allowed = {}
			for _, line in Regions.ById.coral.depths.enemyLines do
				expect(Config.Species.ById[line] ~= nil).toBe(true)
				allowed[line] = true
			end
			for seed = 1, 20 do
				for _, enemy in BattleSim.BuildEnemies("coral", 23, seed) do
					expect(allowed[enemy.line]).toBe(true)
				end
			end
			for _, stage in { 25, 30 } do
				local boss = BattleSim.BuildEnemies("coral", stage, 1)
				expect(#boss).toBe(1)
				expect(boss[1].boss).toBe(true)
				expect(boss[1].line).toBe(Regions.ById.coral.bosses[stage].line)
			end
		end)
	end)

	describe("Expeditions", function()
		it("locks the Depths until Ranch Level 22 and stage 20 is cleared", function()
			local h = boot()
			local p = h:Join()
			strongSquad(h, p)
			h:Section(p, "Progression").level = 12
			h:Section(p, "Expeditions").cleared.coral = 20
			expect(h:Reject(p, "Expeditions.Fight", { region = "coral", stage = 21 })).toContain("Coral Depths unlocks at Ranch Level 22")
			h:Section(p, "Progression").level = 22
			h:Section(p, "Expeditions").cleared.coral = 19
			h:Advance(1)
			expect(h:Reject(p, "Expeditions.Fight", { region = "coral", stage = 21 })).toContain("Clear stage 20 first")
			h:Section(p, "Expeditions").cleared.coral = 20
			h:Advance(1)
			local res = h:Call(p, "Expeditions.Fight", { region = "coral", stage = 21 })
			expect(res.win).toBe(true)
			expect(h:System("Expeditions"):Cleared(p, "coral")).toBe(21)
		end)

		it("gives Pearl Eggs for the first clear of each Depths boss only", function()
			local h, eggs = boot()
			local p = h:Join()
			strongSquad(h, p)
			h:Section(p, "Progression").level = 30
			h:Section(p, "Expeditions").cleared.coral = 24
			local res = h:Call(p, "Expeditions.Fight", { region = "coral", stage = 25 })
			expect(res.win).toBe(true)
			local pearls = 0
			for _, e in eggs do
				if e.egg == "pearl" then
					pearls += e.amount
				end
			end
			expect(pearls).toBe(1)
			h:Advance(1)
			h:Call(p, "Expeditions.Fight", { region = "coral", stage = 25 })
			local again = 0
			for _, e in eggs do
				if e.egg == "pearl" then
					again += e.amount
				end
			end
			expect(again).toBe(1)
		end)

		it("can drop Pearl Eggs from Depths expeditions but not from the coast", function()
			local Loot = t.Shared("Logic.Loot")
			local function pearlsFrom(stage)
				local n = 0
				for seed = 1, 60 do
					local loot = Loot.ExpeditionLoot("coral", stage, 28800, { seed = seed })
					for _, item in loot do
						if item.kind == "egg" and item.id == "pearl" then
							n += item.amount or 1
						end
					end
				end
				return n
			end
			expect(pearlsFrom(20)).toBe(0)
			expect(pearlsFrom(30)).toBeGreaterThan(0)
		end)
	end)

	describe("Pearl Egg", function()
		it("hatches only the three Depths lines", function()
			local EggRoll = t.Shared("Logic.EggRoll")
			local Rng = t.Shared("Logic.Rng")
			local egg = Config.Eggs.ById.pearl
			expect(egg ~= nil).toBe(true)
			local lines = {}
			local rng = Rng.new(11)
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, egg, {})
				lines[spec.line] = true
				expect(spec.rarity).toBeAtLeast(2)
			end
			local count = 0
			for line in lines do
				count += 1
				expect(Config.Species.ById[line].added).toBe("1.1")
			end
			expect(count).toBe(3)
		end)

		it("is never sold in the shop", function()
			expect(Config.Eggs.ById.pearl.price).toBeNil()
			expect(Config.Eggs.ById.pearl.stock).toBeNil()
		end)
	end)

	describe("Pearl mutation", function()
		it("combines Soaked and Starstruck into Pearl in either order", function()
			local Mutation = t.Shared("Logic.Mutation")
			local list, r = Mutation.Add({ "soaked" }, "starstruck")
			expect(r).toBe("combined")
			expect(list).toEqual({ "pearl" })
			list = Mutation.Add({ "starstruck" }, "soaked")
			expect(list).toEqual({ "pearl" })
			expect(Config.Mutations.ById.pearl.mult).toBeGreaterThan(Config.Mutations.ById.starstruck.mult)
		end)
	end)

	describe("Beach decor", function()
		it("sells the beach set and the boardwalk theme", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop" } })
			local p = h:Join()
			local currency = h:System("Currency")
			currency:Add(p, "coins", 1e6, "test")
			currency:Add(p, "gems", 1000, "test")
			currency:Add(p, "friendship", 500, "test")
			local beach = 0
			for _, d in Config.Decor.List do
				if d.set == "beach" then
					beach += 1
					h:Call(p, "Shop.BuyDecor", { decor = d.id })
					h:Advance(1)
				end
			end
			expect(beach).toBe(4)
			expect(h:Section(p, "Shop").decor.tide_pool).toBe(1)
			h:Call(p, "Shop.BuyTheme", { theme = "boardwalk" })
			expect(h:Section(p, "Shop").themes.boardwalk).toBe(true)
		end)
	end)

	describe("Leaderboards", function()
		it("ranks a Depths clear above the end of the coast", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions", "Leaderboards" } })
			local p = h:Join()
			h:Section(p, "Expeditions").cleared.coral = 30
			expect(h:System("Leaderboards"):Value(p, "stage")).toBe(60)
		end)
	end)

	describe("Launch code and achievements", function()
		it("redeems CORALDEPTHS for a Pearl Egg and tracks the Depths achievements", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests" } })
			local p = h:Join()
			local before = h:System("Eggs"):Count(p)
			h:Call(p, "Quests.Redeem", { code = "coraldepths" })
			expect(h:System("Eggs"):Count(p)).toBe(before + 1)
			h.kernel.Bus:Publish("StageCleared", p, { region = "coral", stage = 30, first = true })
			h.kernel.Bus:Publish("Mutated", p, { id = "m1", mutation = "pearl" })
			local achievements = h:Section(p, "Quests").achievements
			expect(achievements.clear_depths.progress).toBe(1)
			expect(achievements.pearl_mutation.progress).toBe(1)
			local rewards = h:Call(p, "Quests.ClaimAchievement", { id = "clear_depths" }).rewards
			local pearl = false
			for _, item in rewards do
				if item.kind == "egg" and item.id == "pearl" then
					pearl = true
				end
			end
			expect(pearl).toBe(true)
		end)
	end)
end
