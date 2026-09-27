--[[
	Observatory (update 3.12 · Honey & stars): the Observatory and its Star Charts. The night clock,
	the seeded sky, the tap check, the unlock, night-only sightings (three a night, fresh the next
	night), valid and failed submits (wrong order, too fast, too slow, a replayed id), finishing a
	chart (StarCharted and its perk), the seasonal gate, the perk caps, every wired perk consumer
	(and each unchanged at 0) and the weekly goal stars_5.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Observatory")
	local Seasons = t.Shared("Logic.Seasons")

	local Cfg = Config.Observatory
	local LENGTH = Config.Weather.DayLength
	local BASE = 1790000000 -- the harness's default start
	-- A clock time early in a night (the first minute after dusk).
	local NIGHT = BASE - BASE % LENGTH + math.floor(LENGTH * (1 - Config.Weather.NightFraction)) + 5
	local DAY = NIGHT - 300

	local CORE = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Decor", "Observatory", "Weekly" }

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function boot(opts)
		opts = opts or {}
		local h = TestKernel.new({ systems = opts.systems or CORE, startTime = opts.at or NIGHT })
		local sighted, charted = {}, {}
		h.kernel.Bus:Subscribe("StarSighted", function(_, detail)
			table.insert(sighted, detail)
		end)
		h.kernel.Bus:Subscribe("StarCharted", function(_, detail)
			table.insert(charted, detail)
		end)
		local p = h:Join()
		levelTo(h, p, opts.level or Config.Unlocks.Features.observatory)
		return h, p, sighted, charted
	end

	-- Taps that trace `order` with `gap` seconds between stars.
	local function trace(order, gap: number, first: number?)
		local taps = {}
		for i, star in order do
			table.insert(taps, { star = star, t = (first or 0.5) + (i - 1) * gap })
		end
		return taps
	end

	-- One full, correct sighting of `chart`; returns the Submit result.
	local function sight(h, p, chart: string)
		local res = h:Call(p, "Observatory.Start", { chart = chart })
		local taps = trace(res.order, 0.4)
		h:Advance(taps[#taps].t + 0.2)
		return h:Call(p, "Observatory.Submit", { id = res.id, taps = taps })
	end

	-- A chart that is (want = true) or is not (false) in season at `now`.
	local function seasonal(now: number, want: boolean)
		local id = Seasons.At(now).id
		for _, c in Cfg.Charts do
			if c.season and (c.season == id) == want then
				return c
			end
		end
		error("no seasonal chart")
	end

	describe("Logic", function()
		it("reads the night off the Weather cycle and deals the same sky from the same seed", function()
			local isNight, night, changesAt = Logic.Night(NIGHT)
			expect(isNight).toBe(true)
			expect(night).toBe(NIGHT // LENGTH)
			expect(changesAt).toBe(night * LENGTH + LENGTH)
			local day, dayNight, opensAt = Logic.Night(DAY)
			expect(day).toBe(false)
			expect(dayNight).toBe(night)
			expect(opensAt).toBe(NIGHT - 5)
			expect(Logic.Seed(1, 2, 3, 4)).toBe(Logic.Seed(1, 2, 3, 4))
			expect(Logic.Seed(1, 2, 3, 4) ~= Logic.Seed(1, 2, 4, 4)).toBe(true)
			for seed = 1, 200 do
				local count = 5 + seed % 3
				local a, b = Logic.Sky(seed, count), Logic.Sky(seed, count)
				expect(#a.stars).toBe(count)
				expect(a.order).toEqual(b.order)
				local seen = {}
				for i, s in a.stars do
					expect(s.x).toBe(b.stars[i].x)
					expect(s.x >= Cfg.Margin - 1e-6 and s.x <= 1 - Cfg.Margin + 1e-6).toBe(true)
					expect(s.y >= Cfg.Margin - 1e-6 and s.y <= 1 - Cfg.Margin + 1e-6).toBe(true)
					seen[a.order[i]] = true
				end
				for i = 1, count do
					expect(seen[i]).toBe(true)
				end
			end
		end)

		it("checks the order, the gaps and the time limit", function()
			local order = { 3, 1, 2 }
			expect(Logic.Check(order, trace(order, 0.3))).toBe(true)
			expect(select(2, Logic.Check(order, trace({ 1, 3, 2 }, 0.3)))).toBe("order")
			expect(select(2, Logic.Check(order, trace({ 3, 1 }, 0.3)))).toBe("order")
			expect(select(2, Logic.Check(order, trace(order, Cfg.MinGap / 2)))).toBe("fast")
			expect(select(2, Logic.Check(order, { { star = 3, t = 1 }, { star = 1, t = 0.5 }, { star = 2, t = 2 } }))).toBe("fast")
			expect(select(2, Logic.Check(order, trace(order, 0.3, Cfg.TimeLimit)))).toBe("slow")
			expect(Logic.PerkText("egg_speed", 0.02)).toBe("Eggs hatch 2% faster")
			expect(Logic.PerkText("appeal", 2)).toBe("Ranch appeal +2")
		end)

		it("lists 12 charts, 8 all year and one for each season, every perk key used", function()
			expect(#Cfg.Charts).toBe(12)
			local seasonsSeen, keys, allYear = {}, {}, 0
			for _, c in Cfg.Charts do
				if c.season then
					expect(Config.Seasons.ById[c.season] ~= nil).toBe(true)
					expect(seasonsSeen[c.season]).toBeNil()
					seasonsSeen[c.season] = true
				else
					allYear += 1
				end
				expect(c.stars >= 5 and c.stars <= Cfg.MaxStars).toBe(true)
				keys[c.perk.key] = true
			end
			expect(allYear).toBe(8)
			for _, key in Cfg.PerkKeys do
				expect(keys[key]).toBe(true)
			end
		end)
	end)

	describe("Sightings", function()
		it("opens at Ranch Level 19 and only at night", function()
			local h, p = boot({ level = 18 })
			expect(h:Reject(p, "Observatory.Start", { chart = "ladle" })).toContain("Ranch Level 19")
			local h2, p2 = boot({ at = DAY })
			expect(h2:Reject(p2, "Observatory.Start", { chart = "ladle" })).toBe("The stars come out at night. Come back after dark")
			expect(h2:Section(p2, "Observatory").used).toBe(0)
		end)

		it("counts a correct trace, publishes StarSighted and hides the secret", function()
			local h, p, sighted = boot()
			local res = h:Call(p, "Observatory.Start", { chart = "ladle" })
			expect(res.left).toBe(Cfg.Sightings - 1)
			expect(#res.stars).toBe(Cfg.ById.ladle.stars)
			local s = h:Section(p, "Observatory")
			local night = NIGHT // LENGTH
			local sky = Logic.Sky(Logic.Seed(p.UserId, night, 1, s.secret), Cfg.ById.ladle.stars)
			expect(res.order).toEqual(sky.order)
			local taps = trace(res.order, 0.4)
			h:Advance(3)
			local out = h:Call(p, "Observatory.Submit", { id = res.id, taps = taps })
			expect(out.success).toBe(true)
			expect(out.progress).toBe(1)
			expect(out.charted).toBe(false)
			expect(s.charts.ladle).toBe(1)
			expect(s.seen).toBe(1)
			expect(#sighted).toBe(1)
			expect(sighted[1].chart).toBe("ladle")
			expect(table.find(h:System("Observatory").Profile.Private, "secret") ~= nil).toBe(true)
			-- The id is one-shot.
			expect(h:Reject(p, "Observatory.Submit", { id = res.id, taps = taps })).toBe("That sighting is over. Start a new one!")
		end)

		it("fails a wrong order, a too-fast or too-slow trace and still uses the sighting", function()
			local h, p, sighted = boot()
			local s = h:Section(p, "Observatory")
			local function try(make, wait: number)
				local res = h:Call(p, "Observatory.Start", { chart = "lantern" })
				h:Advance(wait)
				return h:Call(p, "Observatory.Submit", { id = res.id, taps = make(res.order) })
			end
			local wrong = try(function(order)
				local swapped = table.clone(order)
				swapped[1], swapped[2] = swapped[2], swapped[1]
				return trace(swapped, 0.4)
			end, 3)
			expect(wrong.success).toBe(false)
			expect(wrong.why).toBe("order")
			-- Taps claiming more time than the server saw pass are too fast.
			local quick = try(function(order)
				return trace(order, 1.5)
			end, 1)
			expect(quick.why).toBe("fast")
			local slow = try(function(order)
				return trace(order, 0.4, Cfg.TimeLimit)
			end, Cfg.TimeLimit + 3)
			expect(slow.why).toBe("slow")
			expect(slow.left).toBe(0)
			expect(s.charts.lantern).toBeNil()
			expect(#sighted).toBe(0)
			expect(s.used).toBe(Cfg.Sightings)
		end)

		it("allows three sightings a night and three more the next night", function()
			local h, p = boot()
			for _ = 1, Cfg.Sightings do
				sight(h, p, "fish")
			end
			expect(h:Reject(p, "Observatory.Start", { chart = "compass" })).toBe("No sightings left tonight. Come back tomorrow night")
			h:Advance(LENGTH)
			local res = h:Call(p, "Observatory.Start", { chart = "compass" })
			expect(res.left).toBe(Cfg.Sightings - 1)
			expect(h:Section(p, "Observatory").night).toBe(NIGHT // LENGTH + 1)
		end)

		it("finishes a chart after three observations: StarCharted, the perk and Charted", function()
			local h, p, _, charted = boot()
			local O = h:System("Observatory")
			expect(O:Perk(p, "egg_speed")).toBe(0)
			expect(sight(h, p, "ladle").progress).toBe(1)
			expect(sight(h, p, "ladle").progress).toBe(2)
			local last = sight(h, p, "ladle")
			expect(last.progress).toBe(Cfg.Observations)
			expect(last.charted).toBe(true)
			expect(#charted).toBe(1)
			expect(charted[1].chart).toBe("ladle")
			expect(O:Perk(p, "egg_speed")).toBe(0.02)
			expect(O:Charted(p)).toEqual({ ladle = true })
			h:Advance(LENGTH)
			expect(h:Reject(p, "Observatory.Start", { chart = "ladle" })).toBe("You already charted those stars")
		end)

		it("only starts a seasonal chart in its season", function()
			local h, p = boot()
			local away = seasonal(NIGHT, false)
			expect(h:Reject(p, "Observatory.Start", { chart = away.id })).toBe("That chart's stars aren't in the sky this season")
			local here = seasonal(NIGHT, true)
			expect(sight(h, p, here.id).success).toBe(true)
		end)

		it("caps every perk key and gives nothing before the unlock", function()
			local h, p = boot()
			local s = h:Section(p, "Observatory")
			for _, c in Cfg.Charts do
				s.charts[c.id] = Cfg.Observations
			end
			local O = h:System("Observatory")
			for _, key in Cfg.PerkKeys do
				local sum = 0
				for _, c in Cfg.Charts do
					if c.perk.key == key then
						sum += c.perk.value
					end
				end
				expect(O:Perk(p, key)).toBe(math.min(sum, Cfg.PerkCaps[key]))
			end
			expect(O:Perk(p, "nope")).toBe(0)
			local q = h:Join()
			levelTo(h, q, 18)
			h:Section(q, "Observatory").charts.ladle = Cfg.Observations
			expect(O:Perk(q, "egg_speed")).toBe(0)
		end)

		it("keeps a stars_5 weekly goal on StarSighted and cleans a damaged save on join", function()
			local goal = Config.Weekly.ById.stars_5
			expect(goal.family).toBe("observatory")
			expect(goal.unlock).toBe("observatory")
			expect(goal.topic).toBe("StarSighted")
			expect(goal.target).toBe(5)
			expect(Config.Unlocks.Features.observatory).toBe(19)
			local h, p = boot()
			local s = h:Section(p, "Observatory")
			s.charts = { ladle = 9, nope = 2, lantern = "x" }
			h:System("Observatory").PlayerAdded(p)
			expect(s.charts).toEqual({ ladle = Cfg.Observations })
		end)
	end)

	describe("Perk consumers", function()
		local function finish(h, p, chart: string)
			h:Section(p, "Observatory").charts[chart] = Cfg.Observations
		end

		it("speeds eggs, raises income, loot and appeal by the perk and leaves them at 0", function()
			local h, p = boot({ systems = allSystems() })
			local Eggs, Ranch = h:System("Eggs"), h:System("Ranch")
			local Expeditions, Tourists = h:System("Expeditions"), h:System("Tourists")
			h:System("Monsters"):Create(p, { line = "cindlet", rarity = 1, traits = { 3, 4 }, hidden = 5, variant = 0 }, "hatch", true)
			local speed = Eggs:Speed(p)
			Ranch:Refresh(p)
			local income = Ranch:IncomePerSecond(p)
			expect(income > 0).toBe(true)
			local loot = Expeditions:LootBonus(p, {})
			local appeal = Tourists:Appeal(p)
			finish(h, p, "lantern")
			Ranch:Refresh(p)
			expect(Ranch:IncomePerSecond(p) > income).toBe(true)
			expect(Eggs:Speed(p)).toBe(speed)
			expect(Expeditions:LootBonus(p, {})).toBe(loot)
			expect(Tourists:Appeal(p).score).toBe(appeal.score)
			finish(h, p, "ladle")
			finish(h, p, "compass")
			finish(h, p, "crown")
			expect(math.abs(Eggs:Speed(p) - (speed + 0.02)) < 1e-9).toBe(true)
			expect(math.abs(Expeditions:LootBonus(p, {}) - (loot + 0.02)) < 1e-9).toBe(true)
			expect(Tourists:Appeal(p).bonus).toBe(appeal.bonus + 2)
		end)

		it("adds rare_fish to the Fishing bonus and takes dojo_time off training", function()
			local h, p = boot({ systems = allSystems(), level = 24 })
			local first = h:Call(p, "Fishing.Start")
			finish(h, p, "fish")
			h:Advance(Config.Fishing.Duration + 10)
			local second = h:Call(p, "Fishing.Start")
			expect(math.abs(second.bonus - (first.bonus + 0.03)) < 1e-9).toBe(true)

			h:System("Currency"):Add(p, "stardust", 1e5, "test")
			local M = h:System("Monsters")
			local a = M:Create(p, { line = "cindlet", rarity = 2, stage = 3, variant = 0 }, "test", true)
			local b = M:Create(p, { line = "cindlet", rarity = 2, stage = 3, variant = 0 }, "test", true)
			local plain = h:Call(p, "Dojo.Train", { id = a.id, tech = "cinder_fang" })
			local _, seconds = t.Shared("Logic.Dojo").Cost(1)
			expect(plain.readyAt - h.adapters.Clock.Now()).toBe(seconds)
			h:Section(p, "Dojo").training = false
			M:SetBusy(p, a.id, nil)
			finish(h, p, "kettle")
			local cut = h:Call(p, "Dojo.Train", { id = b.id, tech = "cinder_fang" })
			expect(cut.readyAt - h.adapters.Clock.Now()).toBe(math.floor(seconds * (1 - 0.05) + 0.5))
		end)
	end)
end
