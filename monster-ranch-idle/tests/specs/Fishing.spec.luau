--[[
	Fishing (update 3.10 · Ranch life): the Fishing Pond. Course determinism, the replayed
	minigame (catch and escape), the anti-cheat checks (too fast, too late, bad moves, a reused
	run, no casts), daily casts and bait, rarity and Luck odds, selling, the Kitchen contract
	(FishCount / SpendFish), the Fish Log milestones, the Biggest Catch board and the weekly goal.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Fishing")
	local Loot = t.Shared("Logic.Loot")

	local Cfg = Config.Fishing
	local DAY = 86400
	local WEEK = Config.Leaderboards.WeekSeconds

	local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Fishing", "Codex", "Leaderboards", "Weekly" }

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot()
		local h = TestKernel.new({ systems = SYSTEMS })
		local caught = {}
		h.kernel.Bus:Subscribe("FishCaught", function(player, detail)
			table.insert(caught, { player = player, detail = detail })
		end)
		return h, caught
	end

	local function angler(h)
		local p = h:Join()
		levelTo(h, p, 13)
		return p
	end

	-- A player who watches the fish and holds while the zone is below it.
	local function bot(seed: number, bonus: number?)
		local course = Logic.Course(seed, bonus)
		local state = Logic.NewState()
		local inputs = {}
		local down = false
		while not state.done do
			local t0 = state.i * Cfg.Step
			local fy = Logic.FishAt(course, t0 + 0.2)
			local want = state.zone + state.vel * 0.3 < fy
			if want ~= down then
				down = want
				table.insert(inputs, { t = math.floor(t0 * 1000 + 0.5) / 1000, down = want })
			end
			Logic.Advance(state, course, inputs)
		end
		return inputs, state
	end

	-- The first seed from `from` whose fish the bot lands (commons are easy).
	local function catchable(from: number, bonus: number?)
		for seed = from, from + 400 do
			local inputs, state = bot(seed, bonus)
			if state.caught then
				return seed, inputs, state
			end
		end
		error("no catchable seed")
	end

	-- Starts a cast, then plays the bot's moves for its own seed in real (test) time.
	local function castAndCatch(h, p)
		local start = h:Call(p, "Fishing.Start")
		local inputs, state = bot(start.seed, start.bonus)
		h:Advance(state.time + 0.1)
		local res = h:Call(p, "Fishing.Finish", { run = start.run, inputs = inputs })
		return res, state, start
	end

	describe("Logic", function()
		it("builds the same course from the same seed and keeps the fish on the bar", function()
			local a, b = Logic.Course(12345), Logic.Course(12345)
			expect(a.fish).toBe(b.fish)
			expect(a.weight).toBe(b.weight)
			expect(#a.points).toBe(#b.points)
			for i, point in a.points do
				expect(point.t).toBe(b.points[i].t)
				expect(point.y).toBe(b.points[i].y)
			end
			expect(a.points[#a.points].t >= Cfg.Duration).toBe(true)
			local differs = false
			for seed = 1, 10 do
				if Logic.Course(seed).points[2].y ~= a.points[2].y then
					differs = true
				end
			end
			expect(differs).toBe(true)
			for step = 0, Cfg.Duration / Cfg.Step do
				local y = Logic.FishAt(a, step * Cfg.Step)
				expect(y >= 0 and y <= 1).toBe(true)
			end
			local def = Cfg.ById[a.fish]
			expect(a.weight >= def.weight[1] and a.weight <= def.weight[2]).toBe(true)
		end)

		it("catches a fish the zone follows and lets one go when nobody reels", function()
			local seed, inputs, state = catchable(1)
			local res = Logic.Simulate(seed, inputs)
			expect(res.caught).toBe(true)
			expect(res.time).toBe(state.time)
			expect(res.time < Cfg.Duration).toBe(true)
			for s = 1, 20 do
				local idle = Logic.Simulate(s, {})
				expect(idle.caught).toBe(false)
				expect(idle.meter).toBe(0)
			end
			-- Holding the whole time pins the zone to the top; it still has to cover the fish.
			local held = Logic.Simulate(seed, { { t = 0, down = true } })
			expect(held.time <= Cfg.Duration).toBe(true)
		end)

		it("validates moves", function()
			expect((Logic.Valid({ { t = 1, down = true }, { t = 2, down = false } }))).toBe(true)
			expect((Logic.Valid({ { t = 2, down = true }, { t = 1, down = false } }))).toBe(false)
			expect((Logic.Valid({ { t = 1, down = "yes" } }))).toBe(false)
			expect((Logic.Valid({ { t = Cfg.Duration + 1, down = true } }))).toBe(false)
			local many = {}
			for i = 1, Cfg.MaxInputs + 1 do
				many[i] = { t = i * 0.01, down = i % 2 == 0 }
			end
			expect((Logic.Valid(many))).toBe(false)
			expect(Logic.DownAt({ { t = 1, down = true }, { t = 2, down = false } }, 1)).toBe(true)
			expect(Logic.DownAt({ { t = 1, down = true }, { t = 2, down = false } }, 0.99)).toBe(false)
		end)

		it("rolls rarities by weight and lets Luck raise the rare ones like Bounties do", function()
			local base = Logic.RarityChances(0)
			local total = 0
			for _, r in Cfg.Rarities do
				total += r.weight
			end
			expect(math.abs(base.common - 60 / total) < 1e-9).toBe(true)
			local lucky = Logic.RarityChances(0.15)
			expect(lucky.legendary > base.legendary).toBe(true)
			expect(lucky.common < base.common).toBe(true)

			expect(Logic.BuddyBonus(0)).toBe(0)
			expect(Logic.BuddyBonus(nil)).toBe(0)
			local luck = 60
			expect(math.abs(Logic.BuddyBonus(luck) - Loot.LuckBonus({ luck, luck, luck, luck, luck })) < 1e-4).toBe(true)
			expect(Logic.BuddyBonus(10000) <= Loot.LuckLootMax).toBe(true)
			expect(math.abs(Logic.ExtraChance(0.05, 0.1, 0.5) - 0.075) < 1e-9).toBe(true)
			expect(Logic.ExtraChance(0.05, 0.1, 5)).toBe(0.1)

			local n, counts = 4000, {}
			for seed = 1, n do
				local def = Logic.Roll(seed, 0)
				counts[def.rarity] = (counts[def.rarity] or 0) + 1
			end
			expect(math.abs(counts.common / n - base.common) < 0.03).toBe(true)
			expect(math.abs((counts.rare or 0) / n - base.rare) < 0.02).toBe(true)
			local extras = Logic.Extras(99, 0)
			local again = Logic.Extras(99, 0)
			expect(#extras).toBe(#again)
			expect(Logic.Egg() ~= nil).toBe(true)
			local eggs = 0
			for seed = 1, n do
				for _, item in Logic.Extras(seed, 0) do
					if item.kind == "egg" then
						eggs += 1
					end
				end
			end
			expect(math.abs(eggs / n - Cfg.EggChance) < 0.015).toBe(true)
		end)
	end)

	describe("Casting", function()
		it("lands a fish in the bucket and the Fish Log and publishes FishCaught", function()
			local h, caught = boot()
			local p = angler(h)
			local res
			for _ = 1, Cfg.FreeCasts do
				res = castAndCatch(h, p)
				if res.caught then
					break
				end
			end
			expect(res.caught).toBe(true)
			local s = h:Section(p, "Fishing")
			expect(s.fish[res.fish]).toBe(1)
			expect(s.log[res.fish].n).toBe(1)
			expect(s.log[res.fish].best).toBe(res.weight)
			expect(res.first).toBe(true)
			expect(s.total).toBe(1)
			expect(#caught).toBe(1)
			expect(caught[1].detail.fish).toBe(res.fish)
			expect(caught[1].detail.rarity).toBe(Cfg.ById[res.fish].rarity)
			expect(caught[1].detail.weight).toBe(res.weight)
			-- The weekly goal counts it.
			expect(Config.Weekly.ById.fish_20.topic).toBe("FishCaught")
			expect(Config.Weekly.ById.fish_20.unlock).toBe("fishing")
		end)

		it("rejects too fast, too late, bad moves, a reused run and a locked pond", function()
			local h = boot()
			local locked = h:Join()
			expect(h:Reject(locked, "Fishing.Start")).toBe("Unlocks at Ranch Level 13")
			local p = angler(h)

			local start = h:Call(p, "Fishing.Start")
			local inputs, state = bot(start.seed, start.bonus)
			expect(state.time > Cfg.GraceSeconds + 0.5).toBe(true)
			expect(h:Reject(p, "Fishing.Finish", { run = start.run, inputs = inputs })).toBe("That catch was too quick")
			-- The run is spent even though it failed.
			expect(h:Reject(p, "Fishing.Finish", { run = start.run, inputs = inputs })).toBe("That cast has ended. Cast again!")

			start = h:Call(p, "Fishing.Start")
			h:Advance(Cfg.Duration + Cfg.LateSeconds + 2)
			expect(h:Reject(p, "Fishing.Finish", { run = start.run, inputs = {} })).toBe("That cast has ended. Cast again!")

			start = h:Call(p, "Fishing.Start")
			h:Advance(5)
			local backwards = { { t = 2, down = true }, { t = 1, down = false } }
			expect(h:Reject(p, "Fishing.Finish", { run = start.run, inputs = backwards })).toBe(
				"That catch didn't add up (moves out of order)"
			)
			start = h:Call(p, "Fishing.Start")
			expect(type(h:Reject(p, "Fishing.Finish", { run = start.run, inputs = { { t = 1, down = "yes" } } }))).toBe("string")
			expect(h:Reject(p, "Fishing.Finish", { run = start.run + 50, inputs = {} })).toBe("That cast has ended. Cast again!")
			expect(h:Section(p, "Fishing").total).toBe(0)
		end)

		it("gives FreeCasts a day, then spends bait, and resets at the UTC day", function()
			local h = boot()
			local p = angler(h)
			for i = 1, Cfg.FreeCasts do
				h:Advance(1.1) -- Fishing.Start's rate limit
				local res = h:Call(p, "Fishing.Start")
				expect(res.casts).toBe(Cfg.FreeCasts - i)
			end
			expect(h:Reject(p, "Fishing.Start")).toBe("No casts left today. Use bait or come back tomorrow")
			expect(h:System("Fishing"):AddBait(p, 2)).toBe(2)
			h:System("Rewards"):Grant(p, { { kind = "bait", amount = 1 } }, "test")
			expect(h:Section(p, "Fishing").bait).toBe(3)
			for left = 2, 0, -1 do
				h:Advance(1.1)
				expect(h:Call(p, "Fishing.Start").bait).toBe(left)
			end
			h:Advance(1.1)
			expect(h:Reject(p, "Fishing.Start")).toBe("No casts left today. Use bait or come back tomorrow")
			h:Advance(DAY)
			expect(h:Call(p, "Fishing.Start").casts).toBe(Cfg.FreeCasts - 1)
		end)

		it("takes an Adult buddy whose Luck sets the run's bonus", function()
			local h = boot()
			local p = angler(h)
			local baby = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1, stage = 1 }, "test", true)
			expect(h:Reject(p, "Fishing.SetBuddy", { id = baby.id })).toBe("Only Adults can be a fishing buddy")
			local adult = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 5, stage = 3 }, "test", true)
			h:Call(p, "Fishing.SetBuddy", { id = adult.id })
			expect(h:Section(p, "Fishing").buddy).toBe(adult.id)
			local start = h:Call(p, "Fishing.Start")
			expect(start.bonus > 0).toBe(true)
			expect(start.bonus).toBe(h:System("Fishing"):Bonus(p))
		end)
	end)

	describe("Bucket", function()
		it("sells fish for coins and never more than you have", function()
			local h = boot()
			local p = angler(h)
			local s = h:Section(p, "Fishing")
			s.fish = { perch = 3 }
			local before = h:Section(p, "Currency").coins
			local res = h:Call(p, "Fishing.Sell", { fish = "perch", amount = 2 })
			expect(res.coins).toBeGreaterThan(0)
			expect(h:Section(p, "Currency").coins).toBe(before + res.coins)
			expect(s.fish.perch).toBe(1)
			expect(h:Reject(p, "Fishing.Sell", { fish = "perch", amount = 2 })).toBe("You don't have that many fish")
			expect(h:Reject(p, "Fishing.Sell", { fish = "koi", amount = 1 })).toBe("You don't have that many fish")
		end)

		it("counts and spends fish for the Kitchen, cheapest first", function()
			local h = boot()
			local p = angler(h)
			local F = h:System("Fishing")
			local s = h:Section(p, "Fishing")
			s.fish = { pond_king = 1, trout = 2, minnow = 1, koi = 1 }
			expect(F:FishCount(p)).toBe(5)
			expect(F:SpendFish(p, 6)).toBe(false)
			expect(F:FishCount(p)).toBe(5)
			expect(F:SpendFish(p, 2)).toBe(true)
			expect(s.fish.minnow).toBeNil()
			expect(s.fish.trout).toBe(1)
			expect(s.fish.pond_king).toBe(1)
			expect(F:SpendFish(p, 2)).toBe(true)
			expect(s.fish.trout).toBeNil()
			expect(s.fish.koi).toBeNil()
			expect(F:FishCount(p)).toBe(1)
			expect(F:SpendFish(p, 0)).toBe(true)
			expect(F:SpendFish(p, -1)).toBe(false)
		end)
	end)

	describe("Fish Log and board", function()
		it("pays the Fish Log milestones through Codex.Claim", function()
			local h = boot()
			local p = angler(h)
			local s = h:Section(p, "Fishing")
			-- 3.11: steps 5 / 10 / 20 (20 kinds with the four seasonal fish).
			s.log = {
				minnow = { n = 2, best = 0.1 },
				perch = { n = 1, best = 0.5 },
				trout = { n = 1, best = 1 },
				frost_char = { n = 1, best = 1 },
			}
			expect(h:Reject(p, "Codex.Claim", { milestone = "fish_5" })).toBe("Catch 1 more kinds of fish first")
			s.log.koi = { n = 1, best = 3 }
			local gems = h:Section(p, "Currency").gems
			local res = h:Call(p, "Codex.Claim", { milestone = "fish_5" })
			expect(res.gems).toBe(Config.Codex.Gems.fish[1])
			expect(h:Section(p, "Currency").gems).toBe(gems + res.gems)
			expect(h:Reject(p, "Codex.Claim", { milestone = "fish_5" })).toBe("Already claimed")
			expect(h:Reject(p, "Codex.Claim", { milestone = "fish_10" })).toBe("Catch 5 more kinds of fish first")
		end)

		it("puts the week's biggest catch on the Biggest Catch board and clears it next week", function()
			local board = Config.Leaderboards.ById.fishing
			expect(board ~= nil and board.period == "week" and board.format == "weight").toBe(true)
			local h = boot()
			local p = angler(h)
			local res
			for _ = 1, Cfg.FreeCasts do
				res = castAndCatch(h, p)
				if res.caught then
					break
				end
			end
			expect(res.caught).toBe(true)
			local value, label = h:System("Leaderboards"):Value(p, "fishing")
			expect(value).toBe(math.floor(res.weight * Config.Leaderboards.WeightScale + 0.5))
			expect(label).toBe(Cfg.ById[res.fish].name)
			h:Advance(WEEK)
			expect((h:System("Leaderboards"):Value(p, "fishing"))).toBe(0)
		end)
	end)
end
