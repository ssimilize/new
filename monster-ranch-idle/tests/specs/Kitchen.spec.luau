--[[
	Kitchen (update 3.10): Kitchen & Pantry. The cooking rules (Logic/Kitchen), the Job Board's
	output boost (Logic/Jobs.BoostedSeconds), and the server: recipes charged all at once,
	refusals when short, slots (the 3rd at Level 30), cooking while away with its Welcome Back
	line, the Pantry cap, every dish effect, Golden seeds from the Feed Garden, and fish through a
	stubbed Fishing system (and without one).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Kitchen")
	local JobsLogic = t.Shared("Logic.Jobs")
	local Objectives = t.Shared("Logic.Objectives")

	local Rules = Config.Kitchen
	local HOUR = 3600

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Ranch", "Jobs", "Bond", "Expeditions", "Kitchen" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	-- A Fishing stand-in with the shared contract (FishCount / SpendFish).
	local function fakeFishing(start: number, refuse: boolean?)
		local pond = { fish = start, spent = 0 }
		pond.api = {
			FishCount = function(_, _player)
				return pond.fish
			end,
			SpendFish = function(_, _player, n)
				if refuse or pond.fish < n then
					return false
				end
				pond.fish -= n
				pond.spent += n
				return true
			end,
		}
		return pond
	end

	local function boot(level: number?, stubs)
		local h = TestKernel.new({ systems = SYSTEMS, stubs = stubs })
		local p = h:Join()
		levelTo(h, p, level or 9)
		return h, p
	end

	local function food(h, p, amounts)
		for flavor, n in amounts do
			h:System("Currency"):Add(p, "food." .. flavor, n, "test")
		end
	end

	local function balance(h, p, flavor: string): number
		return h:System("Currency"):Balance(p, "food." .. flavor)
	end

	local function create(h, p, fields)
		local spec = { line = "cindlet", rarity = 3, stage = 3, traits = {}, hidden = 0 }
		for k, v in fields or {} do
			spec[k] = v
		end
		return h:System("Monsters"):Create(p, spec, "test", true)
	end

	-- Cooks `recipe` (food added first), finishes it and collects it into the Pantry.
	local function cookOne(h, p, recipe: string)
		local r = Rules.ById[recipe]
		local cost = {}
		for key, n in r.cost do
			if Config.Food.ById[key] then
				cost[key] = n
			end
		end
		food(h, p, cost)
		h:Call(p, "Kitchen.Cook", { recipe = recipe })
		h:Advance(r.minutes * 60 + 1)
		return h:Call(p, "Kitchen.Collect")
	end

	local function topics(h, names)
		local seen = {}
		for _, name in names do
			seen[name] = {}
			h.kernel.Bus:Subscribe(name, function(player, detail)
				table.insert(seen[name], { player = player, detail = detail })
			end)
		end
		return seen
	end

	describe("Kitchen rules", function()
		it("has 8 recipes with one known effect each, cook times of 5-60 minutes and fish and golden recipes", function()
			expect(#Rules.Recipes).toBe(8)
			local fish, golden, effects = 0, 0, {}
			for _, r in Rules.Recipes do
				expect(Rules.Effects[r.effect] ~= nil).toBe(true)
				effects[r.effect] = true
				expect(r.minutes >= 5 and r.minutes <= 60).toBe(true)
				local _, f, g = Logic.Split(r)
				fish += if f > 0 then 1 else 0
				golden += if g > 0 then 1 else 0
				if r.effect == "meals" then
					expect(Config.Food.ById[r.flavor] ~= nil).toBe(true)
				end
			end
			expect(fish).toBe(2)
			expect(golden).toBe(2)
			for id in Rules.Effects do
				expect(effects[id]).toBe(true)
			end
		end)

		it("names what is missing and counts slots by unlock", function()
			local pie = Rules.ById.berry_pie
			expect(Logic.Missing(pie, { food = { sweet = 5, savory = 3 } })).toBe(nil)
			expect(Logic.Missing(pie, { food = { sweet = 5, savory = 2 } })).toBe("savory")
			expect(Logic.Missing(Rules.ById.sushi_roll, { food = { sour = 9 }, fish = 2 })).toBe("fish")
			expect(Logic.Missing(Rules.ById.golden_feast, { food = {}, fish = 0, golden = 0 })).toBe("golden")
			expect(Logic.SlotCount(function()
				return false
			end)).toBe(0)
			expect(Logic.SlotCount(function(key)
				return key == "kitchen"
			end)).toBe(2)
			expect(Logic.SlotCount(function()
				return true
			end)).toBe(3)
		end)

		it("boosts a job's output only inside the boost window", function()
			local boosts = { { from = 1000, to = 1000 + 2 * HOUR, pct = 0.2 } }
			expect(JobsLogic.BoostedSeconds(0, 1000, boosts)).toBe(0)
			expect(JobsLogic.BoostedSeconds(1000, 4 * HOUR, boosts)).toBeNear(0.2 * 2 * HOUR, 0.001)
			expect(JobsLogic.BoostedSeconds(1000 + HOUR, 4 * HOUR, boosts)).toBeNear(0.2 * HOUR, 0.001)
			-- A second serving while the boost runs extends it instead of stacking.
			local w = Logic.AddWindow({}, 100, 7200)
			w = Logic.AddWindow(w, 3600, 7200)
			expect(#w).toBe(1)
			expect(w[1].from).toBe(100)
			expect(w[1].to).toBe(3600 + 7200)
			w = Logic.AddWindow(w, 20000, 7200)
			expect(#w).toBe(2)
		end)
	end)

	describe("Cooking", function()
		it("charges every ingredient at once, cooks on the server clock and collects into the Pantry", function()
			local h, p = boot()
			local seen = topics(h, { "DishCooked" })
			food(h, p, { sweet = 5, savory = 3 })
			local res = h:Call(p, "Kitchen.Cook", { recipe = "berry_pie" })
			expect(res.slot).toBe(1)
			expect(balance(h, p, "sweet")).toBe(0)
			expect(balance(h, p, "savory")).toBe(0)
			expect(h:Reject(p, "Kitchen.Collect")).toBe("Nothing is ready yet")
			h:Advance(5 * 60 + 1)
			expect(h:Call(p, "Kitchen.Collect").dishes.berry_pie).toBe(1)
			expect(h:Section(p, "Kitchen").pantry.berry_pie).toBe(1)
			expect(h:Client(p).profile.Kitchen.pantry.berry_pie).toBe(1)
			expect(h:Section(p, "Kitchen").slots[1].recipe).toBe(false)
			expect(seen.DishCooked[1].detail.dish).toBe("berry_pie")
			expect(seen.DishCooked[1].detail.count).toBe(1)
			-- The weekly "Cook 10 dishes" counts dishes, not collects.
			expect(Objectives.Amount(Config.Quests.CountField, "DishCooked", { dish = "golden_feast", count = 2 })).toBe(2)
			expect(Config.Weekly.ById.cook_10.unlock).toBe("kitchen")
		end)

		it("refuses when short and charges nothing", function()
			local h, p = boot()
			food(h, p, { sweet = 5, savory = 2 })
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "berry_pie" })).toBe("Not enough Hearty Roots")
			expect(balance(h, p, "sweet")).toBe(5)
			food(h, p, { sweet = 10 })
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "golden_honeycake" })).toBe("Not enough Golden Honeyfruit")
			expect(balance(h, p, "sweet")).toBe(15)
			-- No Fishing system: fish recipes can't be cooked.
			food(h, p, { savory = 5 })
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "fish_supper" })).toBe("Needs fish from the Fishing Pond")
			expect(h:Client(p).session.Kitchen.fish).toBe(0)
			expect(h:Client(p).session.Kitchen.fishing).toBe(false)
			expect(balance(h, p, "savory")).toBe(7)
		end)

		it("is locked before Ranch Level 9", function()
			local h, p = boot(8)
			food(h, p, { sweet = 5, savory = 3 })
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "berry_pie" })).toContain("Level 9")
			expect(balance(h, p, "sweet")).toBe(5)
		end)

		it("has 2 slots, and a 3rd from Ranch Level 30", function()
			local h, p = boot()
			food(h, p, { sweet = 30, savory = 30 })
			h:Call(p, "Kitchen.Cook", { recipe = "berry_pie" })
			h:Call(p, "Kitchen.Cook", { recipe = "berry_pie" })
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "berry_pie" })).toBe("Every cooking slot is busy")
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "berry_pie", slot = 3 })).toBe("Cooking slot 3 opens at Ranch Level 30")
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "berry_pie", slot = 1 })).toBe("That cooking slot is busy")
			expect(balance(h, p, "sweet")).toBe(20)
			levelTo(h, p, 30)
			expect(h:Client(p).session.Kitchen.slotCount).toBe(3)
			expect(h:Call(p, "Kitchen.Cook", { recipe = "berry_pie" }).slot).toBe(3)
		end)

		it("finishes while the player is away and says so on the Welcome Back screen", function()
			local h, p = boot()
			food(h, p, { spicy = 5, savory = 3, sour = 5, sweet = 3 })
			h:Call(p, "Kitchen.Cook", { recipe = "pepper_stew" })
			h:Call(p, "Kitchen.Cook", { recipe = "lime_tart" })
			local items = {}
			h.kernel.Bus:Subscribe("WelcomeItem", function(_, detail)
				table.insert(items, detail)
			end)
			p = h:Rejoin(p, 2 * HOUR)
			local found = nil
			for _, item in items do
				if item.kind == "kitchen" then
					found = item.text
				end
			end
			expect(found).toBe("2 dishes finished cooking in your Kitchen")
			local got = h:Call(p, "Kitchen.Collect").dishes
			expect(got.pepper_stew).toBe(1)
			expect(got.lime_tart).toBe(1)
		end)

		it("keeps a dish in its slot when the Pantry is full", function()
			local h, p = boot()
			h:Section(p, "Kitchen").pantry.berry_pie = Rules.PantryCap
			food(h, p, { sweet = 5, savory = 3 })
			h:Call(p, "Kitchen.Cook", { recipe = "berry_pie" })
			h:Advance(5 * 60 + 1)
			expect(h:Reject(p, "Kitchen.Collect")).toBe("The Pantry has no room for more Berry Pie")
			expect(h:Section(p, "Kitchen").slots[1].recipe).toBe("berry_pie")
		end)

		it("cooks fish recipes with fish from the Fishing system, spending nothing when short", function()
			local pond = fakeFishing(4)
			local h, p = boot(9, { Fishing = pond.api })
			food(h, p, { sour = 10, savory = 10 })
			h:Advance(6) -- the session picks up the catch
			expect(h:Client(p).session.Kitchen.fish).toBe(4)
			pond.fish = 2
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "sushi_roll" })).toBe("Not enough fish")
			expect(balance(h, p, "sour")).toBe(10)
			pond.fish = 5
			h:Call(p, "Kitchen.Cook", { recipe = "sushi_roll" })
			expect(pond.fish).toBe(2)
			expect(balance(h, p, "sour")).toBe(8)
		end)

		it("cooks with fish from the real Fishing Pond, cheapest fish first", function()
			local systems = table.clone(SYSTEMS)
			table.insert(systems, "Fishing")
			local h = TestKernel.new({ systems = systems })
			local p = h:Join()
			levelTo(h, p, 13)
			food(h, p, { savory = 10 })
			local pond = h:Section(p, "Fishing")
			pond.fish = { minnow = 1, trout = 2 }
			h.kernel.Bus:Publish("FishCaught", p, { fish = "trout", rarity = "uncommon", weight = 1 })
			h:Step()
			expect(h:Client(p).session.Kitchen.fish).toBe(3)
			h:Call(p, "Kitchen.Cook", { recipe = "fish_supper" })
			-- The common minnow goes first, then one trout.
			expect(pond.fish.minnow).toBeNil()
			expect(pond.fish.trout).toBe(1)
			expect(balance(h, p, "savory")).toBe(7)
			h:Step()
			expect(h:Client(p).session.Kitchen.fish).toBe(1)
		end)

		it("charges no food when the Fishing system refuses the fish", function()
			local pond = fakeFishing(9, true)
			local h, p = boot(9, { Fishing = pond.api })
			food(h, p, { savory = 3 })
			expect(h:Reject(p, "Kitchen.Cook", { recipe = "fish_supper" })).toBe("Not enough fish")
			expect(balance(h, p, "savory")).toBe(3)
			expect(pond.spent).toBe(0)
		end)
	end)

	describe("Serving", function()
		it("counts a meal dish as 3 growth meals of its flavour", function()
			local h, p = boot()
			local seen = topics(h, { "MonsterFed" })
			local baby = create(h, p, { stage = 1, rarity = 1 })
			local adult = create(h, p)
			cookOne(h, p, "berry_pie")
			expect(h:Reject(p, "Kitchen.Serve", { id = adult.id, dish = "berry_pie" })).toBe("Only Babies and Teens eat growth meals")
			expect(h:Call(p, "Kitchen.Serve", { id = baby.id, dish = "berry_pie" }).effect).toBe("meals")
			expect(h:System("Monsters"):Get(p, baby.id).meals.sweet).toBe(Rules.MealsPerDish)
			expect(#seen.MonsterFed).toBe(Rules.MealsPerDish)
			expect(h:Section(p, "Kitchen").pantry.berry_pie).toBe(nil)
			expect(h:Reject(p, "Kitchen.Serve", { id = baby.id, dish = "berry_pie" })).toBe("You have no Berry Pie in the Pantry")
		end)

		it("fills Mood to the max", function()
			local h, p = boot()
			local m = create(h, p)
			h:System("Monsters"):Get(p, m.id).mood = 10
			cookOne(h, p, "lime_tart")
			cookOne(h, p, "lime_tart")
			h:Call(p, "Kitchen.Serve", { id = m.id, dish = "lime_tart" })
			expect(h:System("Monsters"):Get(p, m.id).mood).toBe(Config.Economy.Mood.max)
			expect(h:Reject(p, "Kitchen.Serve", { id = m.id, dish = "lime_tart" })).toContain("already as happy")
			expect(h:Section(p, "Kitchen").pantry.lime_tart).toBe(1)
		end)

		it("adds a Bond heart, up to the last one", function()
			local h, p = boot()
			local m = create(h, p)
			h:Section(p, "Kitchen").golden = 2
			cookOne(h, p, "golden_honeycake")
			expect(h:Section(p, "Kitchen").golden).toBe(0)
			h:Call(p, "Kitchen.Serve", { id = m.id, dish = "golden_honeycake" })
			expect(h:System("Bond"):Hearts(p, m.id)).toBe(1)
			-- A Golden Feast makes two dishes; at the last heart they are refused.
			h:Section(p, "Kitchen").golden = 3
			local got = cookOne(h, p, "golden_feast")
			expect(got.dishes.golden_feast).toBe(2)
			h:Section(p, "Bond").list[m.id].pts = Config.Bond.HeartAt[Config.Bond.MaxHearts]
			expect(h:Reject(p, "Kitchen.Serve", { id = m.id, dish = "golden_feast" })).toContain("every Bond heart")
			expect(h:Section(p, "Kitchen").pantry.golden_feast).toBe(2)
		end)

		it("makes a miner earn 20% more for 2 hours", function()
			local h, p = boot()
			local m = create(h, p)
			h:Call(p, "Jobs.Assign", { slot = 1, job = "miner", id = m.id })
			cookOne(h, p, "pepper_stew")
			local slot = h:Section(p, "Jobs").slots[1]
			slot.since = h.adapters.Clock.Now()
			slot.carry = 0
			local baby = create(h, p, { stage = 1 })
			expect(h:Reject(p, "Kitchen.Serve", { id = baby.id, dish = "pepper_stew" })).toBe("Only Teens and Adults can work")
			h:Call(p, "Kitchen.Serve", { id = m.id, dish = "pepper_stew" })
			h:Advance(3 * HOUR)
			local record = h:System("Monsters"):Get(p, m.id)
			local plain = JobsLogic.Pending(slot, record, h.adapters.Clock.Now(), {})[1].amount
			local coins = h:Call(p, "Jobs.Recall", { slot = 1 }).rewards[1].amount
			expect(coins / plain).toBeNear((3 + Rules.JobBoost.pct * Rules.JobBoost.hours) / 3, 0.01)
		end)

		it("adds 5% loot to the monster's next expedition only", function()
			local h, p = boot()
			local E = h:System("Expeditions")
			local m = create(h, p)
			local before = E:LootBonus(p, { m.id })
			h:Section(p, "Kitchen").pantry.fish_supper = 2
			h:Call(p, "Kitchen.Serve", { id = m.id, dish = "fish_supper" })
			expect(E:LootBonus(p, { m.id }) - before).toBeNear(Rules.LootPct, 1e-9)
			expect(h:Reject(p, "Kitchen.Serve", { id = m.id, dish = "fish_supper" })).toContain("already has a snack")
			h:Call(p, "Expeditions.Start", { slot = 1, region = "meadow", stage = 1, duration = "900", squad = { m.id } })
			h:Advance(901)
			h:Call(p, "Expeditions.Claim", { slot = 1 })
			expect(h:Section(p, "Kitchen").boosts[m.id].loot).toBe(false)
			expect(E:LootBonus(p, { m.id })).toBeNear(before, 1e-9)
		end)
	end)

	describe("Golden seeds", function()
		local function harvestOne(h, p)
			h:Call(p, "Ranch.Plant", { plot = 1, flavor = "sweet" })
			h:Section(p, "Ranch").garden.plots[1].readyAt = 0
			return h:Call(p, "Ranch.Harvest", { plot = 1 })
		end

		it("drop from the Feed Garden on the seeded harvests only", function()
			local h, p = boot()
			local hit, miss = nil, nil
			for n = 1, 500 do
				if Logic.GoldenSeed(p.UserId, n) then
					hit = hit or n
				else
					miss = miss or n
				end
			end
			expect(hit ~= nil and miss ~= nil).toBe(true)
			local s = h:Section(p, "Kitchen")
			s.harvests = (miss :: number) - 1
			expect(harvestOne(h, p).food.sweet).toBe(Config.Economy.Garden.yield)
			expect(s.seeds).toBe(0)
			s.harvests = (hit :: number) - 1
			harvestOne(h, p)
			expect(s.seeds).toBe(1)
			expect(s.harvests).toBe(hit)
		end)

		it("don't drop before the Kitchen unlocks", function()
			local h, p = boot(8)
			harvestOne(h, p)
			expect(h:Section(p, "Kitchen").harvests).toBe(0)
		end)

		it("grow golden produce for the Kitchen", function()
			local h, p = boot()
			local s = h:Section(p, "Kitchen")
			expect(h:Reject(p, "Kitchen.PlantGolden", { plot = 1 })).toBe("You have no Golden seeds")
			s.seeds = 2
			h:Call(p, "Ranch.Plant", { plot = 2, flavor = "sour" })
			expect(h:Reject(p, "Kitchen.PlantGolden", { plot = 2 })).toBe("Something is already growing there")
			local res = h:Call(p, "Kitchen.PlantGolden", { plot = 1 })
			expect(res.readyAt).toBe(h.adapters.Clock.Now() + Rules.GoldenGrowMinutes * 60)
			expect(s.seeds).toBe(1)
			expect(h:Section(p, "Ranch").garden.plots[1].flavor).toBe("golden")
			expect(h:Reject(p, "Ranch.Harvest", { plot = 1 })).toBe("That crop isn't ready yet")
			h:Advance(Rules.GoldenGrowMinutes * 60 + 1)
			local sweet = balance(h, p, "sweet")
			h:Call(p, "Ranch.Harvest", {})
			expect(s.golden).toBe(Rules.GoldenYield)
			expect(balance(h, p, "sweet")).toBe(sweet)
			expect(h:Section(p, "Ranch").garden.plots[1].flavor).toBe(false)
		end)
	end)
end
