-- Update 2.0 · Light & Void: the Light/Void element pair, Sky Islands (region, Sky Egg,
-- floating islands, wind crystals), Riding, Summer Splash (Beach Day, Sunkissed, Splash
-- Egg) and the Surf Shack minigame, Season 4.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local SurfLogic = t.Shared("Logic.Surf")

	local SPLASH = Config.Events.ById.summersplash
	local DURING = SPLASH.startsAt + 3600

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function standAt(p, pos)
		p.Character = { HumanoidRootPart = { Position = { X = pos[1], Y = pos[2] + 2, Z = pos[3] } } }
	end

	-- A perfect run: dodge every rock, catch every shell that is safe to catch.
	local function plan(seed: number)
		local course = SurfLogic.Course(seed)
		local byTime, times = {}, {}
		for _, item in course do
			if not byTime[item.t] then
				byTime[item.t] = {}
				table.insert(times, item.t)
			end
			table.insert(byTime[item.t], item)
		end
		table.sort(times)
		local inputs, lane = {}, Config.Surf.StartLane
		for _, time in times do
			local rock, shell = {}, nil
			for _, item in byTime[time] do
				if item.kind == "rock" then
					rock[item.lane] = true
				else
					shell = item.lane
				end
			end
			local want = lane
			if shell and not rock[shell] then
				want = shell
			elseif rock[lane] then
				for l = 1, Config.Surf.Lanes do
					if not rock[l] then
						want = l
						break
					end
				end
			end
			if want ~= lane then
				lane = want
				table.insert(inputs, { t = math.max(0, time - 0.1), lane = lane })
			end
		end
		return inputs
	end

	describe("Light & Void", function()
		it("forms a pair that beats each other and is neutral to the rest", function()
			local E = Config.Elements
			expect(E.Multiplier("light", "void")).toBe(E.Advantage)
			expect(E.Multiplier("void", "light")).toBe(E.Advantage)
			for _, other in { "ember", "tide", "sprout", "spark", "gloom", "stone" } do
				expect(E.Multiplier("light", other)).toBe(1)
				expect(E.Multiplier(other, "void")).toBe(1)
			end
			expect(#E.List).toBe(8)
		end)

		it("hatches Light and Void lines from the Sky Egg and fights them in the Sky Islands", function()
			local EggRoll = t.Shared("Logic.EggRoll")
			local rng = t.Shared("Logic.Rng").new(3)
			local seen = { light = false, void = false }
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.sky, {})
				for _, el in Config.Species.ById[spec.line].elements do
					seen[el] = true
				end
				expect(Config.Species.ById[spec.line].added).toBe("2.0")
			end
			expect(seen.light and seen.void).toBe(true)
			local R = Config.Regions
			local sky = R.ById.sky
			expect(R.GlobalIndex("sky", 20)).toBe(100)
			for _, line in sky.enemyLines do
				expect(Config.Species.ById[line] ~= nil).toBe(true)
			end
			for _, boss in sky.bosses do
				expect(Config.Species.Form(boss.line, 3, boss.form).id).toBe(boss.form)
			end
			-- Stage fights need the region unlock.
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Expeditions" } })
			local p = h:Join()
			local m = h:System("Monsters"):Create(p, { line = "lumipup", rarity = 6, stage = 3 }, "test", true)
			h:Call(p, "Expeditions.SetSquad", { ids = { m.id } })
			expect(h:Reject(p, "Expeditions.Fight", { region = "sky", stage = 1 })).toBe("Sky Islands unlocks at Ranch Level 45")
		end)
	end)

	describe("Sky Islands", function()
		it("lays out floating islands joined by bridges, with crystals on them", function()
			-- The parts themselves are built (and checked against Roblox) in LightAndVoidClient.spec.
			local Sky = Config.World.Sky
			for _, island in Sky.islands do
				expect(island.center[2] >= 150).toBe(true)
			end
			for _, pair in Sky.bridges do
				local found = 0
				for _, island in Sky.islands do
					if island.id == pair[1] or island.id == pair[2] then
						found += 1
					end
				end
				expect(found).toBe(2)
			end
			-- Every crystal stands on an island, just above its grass.
			for _, pos in Config.SkyIslands.Crystals do
				local on = false
				for _, island in Sky.islands do
					local c = island.center
					local d = math.sqrt((pos[1] - c[1]) ^ 2 + (pos[3] - c[3]) ^ 2)
					on = on or (d < island.radius - 2 and math.abs(pos[2] - c[2] - 1.5) < 0.01)
				end
				expect(on).toBe(true)
			end
		end)

		it("pays wind crystals nearby, once an hour each, up to a daily cap", function()
			local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Quests", "SkyIslands" } })
			local p = h:Join()
			local spot = Config.SkyIslands.Crystals[1]
			standAt(p, spot)
			expect(h:Reject(p, "SkyIslands.Collect", { crystal = 1 })).toBe("Unlocks at Ranch Level 45")
			levelTo(h, p, 45)
			p.Character = nil
			expect(h:Reject(p, "SkyIslands.Collect", { crystal = 1 })).toBe("Get closer to the crystal")
			standAt(p, Config.SkyIslands.Crystals[5])
			expect(h:Reject(p, "SkyIslands.Collect", { crystal = 1 })).toBe("Get closer to the crystal")
			standAt(p, spot)
			local res = h:Call(p, "SkyIslands.Collect", { crystal = 1 })
			expect(#res.rewards).toBe(1)
			expect(res.nextAt).toBe(h.adapters.Clock.Now() + Config.SkyIslands.RespawnSeconds)
			h:Advance(1)
			expect(h:Reject(p, "SkyIslands.Collect", { crystal = 1 })).toBe("That crystal is still recharging")
			expect(h:Section(p, "Quests").achievements.sky_first.progress).toBe(1)
			h:Advance(Config.SkyIslands.RespawnSeconds)
			h:Call(p, "SkyIslands.Collect", { crystal = 1 })
			expect(h:Section(p, "SkyIslands").total).toBe(2)
			h:Section(p, "SkyIslands").count = Config.SkyIslands.DailyCap
			standAt(p, Config.SkyIslands.Crystals[2])
			h:Advance(1)
			expect(h:Reject(p, "SkyIslands.Collect", { crystal = 2 })).toBe("The winds are calm. Come back tomorrow for more crystals!")
			-- Long-expired timers are dropped on join.
			p = h:Rejoin(p, Config.SkyIslands.RespawnSeconds + 10)
			expect(next(h:Section(p, "SkyIslands").taken)).toBeNil()
		end)
	end)

	describe("Riding", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Monsters", "Riding", "Quests" }

		it("mounts an Adult, publishes the rider and sets its speed", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local M = h:System("Monsters")
			local baby = M:Create(p, { line = "zappip", rarity = 2 }, "test", true)
			local adult = M:Create(p, { line = "zappip", rarity = 5, stage = 3 }, "test", true)
			M:Create(p, { line = "mossbun", rarity = 1 }, "test", true)
			expect(h:Reject(p, "Riding.Mount", { id = adult.id })).toBe("Unlocks at Ranch Level 16")
			levelTo(h, p, 16)
			expect(h:Reject(p, "Riding.Mount", { id = baby.id })).toBe("Only Adults are big enough to ride")
			local speed = h:Call(p, "Riding.Mount", { id = adult.id }).speed
			-- zappip base SPD 20, Legendary: 20 + 10 + 6 = 36
			expect(speed).toBe(36)
			-- gravitoad base SPD 10, Common: 20 + 5 = 25; nothing goes past Max.
			expect(Config.Riding.SpeedFor({ line = "gravitoad", rarity = 1 })).toBe(25)
			expect(Config.Riding.SpeedFor({ line = "surfotter", rarity = 6 }) <= Config.Riding.Max).toBe(true)
			local rider = h:Client(p).global.Riding.riders["u" .. p.UserId]
			expect(rider.speed).toBe(36)
			expect(rider.appearance.line).toBe("zappip")
			expect(h:Session(p, "Riding").mount).toBe(adult.id)
			expect(h:Section(p, "Quests").achievements.ride_1.progress).toBe(1)

			-- Busy (expedition) or gone: off the mount.
			M:SetBusy(p, adult.id, "expedition")
			expect(h:Session(p, "Riding").mount).toBe(false)
			expect(h:Client(p).global.Riding.riders["u" .. p.UserId]).toBeNil()
			M:SetBusy(p, adult.id, false)
			h:Advance(1)
			h:Call(p, "Riding.Mount", { id = adult.id })
			M:Remove(p, adult.id, "sell")
			expect(h:Session(p, "Riding").speed).toBe(Config.Riding.WalkSpeed)
			expect(h:Reject(p, "Riding.Dismount")).toBe("You aren't riding")
		end)

		it("drops the rider when they leave", function()
			local h = TestKernel.new({ systems = SYSTEMS })
			local p = h:Join()
			local watcher = h:Join()
			levelTo(h, p, 16)
			local adult = h:System("Monsters"):Create(p, { line = "cindlet", rarity = 3, stage = 3 }, "test", true)
			h:Call(p, "Riding.Mount", { id = adult.id })
			expect(h:Client(watcher).global.Riding.riders["u" .. p.UserId] ~= nil).toBe(true)
			h:Leave(p)
			h:Step()
			expect(h:Client(watcher).global.Riding.riders["u" .. p.UserId]).toBeNil()
		end)
	end)

	describe("Summer Splash", function()
		it("runs in July with boosted Heatwave, Beach Day and the Tropical combo", function()
			local Events = Config.Events
			expect(Events.ActiveId(SPLASH.startsAt)).toBe("summersplash")
			expect(os.date("!%d %b %Y", SPLASH.startsAt)).toBe("03 Jul 2027")
			for i, a in Events.List do
				for j, b in Events.List do
					if i ~= j then
						expect(a.endsAt <= b.startsAt or b.endsAt <= a.startsAt).toBe(true)
					end
				end
			end
			local WeatherRoll = t.Shared("Logic.WeatherRoll")
			local indexOf = {}
			for i, w in Config.Weather.List do
				indexOf[w.id] = i
			end
			local off = WeatherRoll.Weights({ night = false })
			local on = WeatherRoll.Weights({ night = false, event = "summersplash" })
			expect(on[indexOf.heatwave]).toBe(3 * off[indexOf.heatwave])
			expect(off[indexOf.beachday]).toBe(0)
			expect(on[indexOf.beachday]).toBeGreaterThan(0)
			expect(WeatherRoll.Weights({ night = true, event = "summersplash" })[indexOf.beachday]).toBe(0)
			local Mutation = t.Shared("Logic.Mutation")
			local list, result = Mutation.Add({ "soaked" }, "sunkissed")
			expect(result).toBe("combined")
			expect(list).toEqual({ "tropical" })
		end)

		it("hatches the Splash lines with Sunkissed", function()
			local EggRoll = t.Shared("Logic.EggRoll")
			local rng = t.Shared("Logic.Rng").new(11)
			local lines = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.splash, {})
				lines[spec.line] = true
				expect(spec.muts).toEqual({ "sunkissed" })
			end
			expect(lines.surfotter and lines.coconutty and lines.sunnyray).toBe(true)
		end)
	end)

	describe("Surf Shack", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Events", "Surf", "Quests" }

		it("builds the same course from a seed and scores moves by replaying them", function()
			local a, b = SurfLogic.Course(42), SurfLogic.Course(42)
			expect(#a).toBe(#b)
			expect(a[#a].t).toBe(b[#b].t)
			expect(a[#a].t < Config.Surf.Duration).toBe(true)
			local perfect = SurfLogic.Simulate(42, plan(42))
			expect(perfect.hits).toBe(0)
			expect(perfect.survived).toBe(Config.Surf.Duration)
			expect(perfect.score).toBe(perfect.shells * Config.Surf.ShellPoints + Config.Surf.Duration * Config.Surf.SecondPoints)
			-- Sitting still eventually wipes out.
			local lazy = SurfLogic.Simulate(42, {})
			expect(lazy.wiped).toBe(true)
			expect(lazy.score < perfect.score).toBe(true)
			expect(SurfLogic.Valid({ { t = 5, lane = 1 }, { t = 4, lane = 2 } })).toBe(false)
			expect(SurfLogic.Valid({ { t = 5, lane = 4 } })).toBe(false)
		end)

		it("pays Seashells for a real run and rejects runs that are too fast or stale", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = DURING })
			local p = h:Join()
			local before = h:System("Currency"):Balance(p, "token.summersplash")
			local run = h:Call(p, "Surf.Start")
			expect(run.duration).toBe(Config.Surf.Duration)
			local inputs = plan(run.seed)
			-- Too quick: a full run submitted after 5 seconds.
			h:Advance(5)
			expect(h:Reject(p, "Surf.Finish", { run = run.run, inputs = inputs })).toBe("That run finished too quickly")
			expect(h:Reject(p, "Surf.Finish", { run = run.run, inputs = inputs })).toBe("That surf run has ended. Start a new one!")

			h:Advance(5)
			run = h:Call(p, "Surf.Start")
			inputs = plan(run.seed)
			h:Advance(Config.Surf.Duration)
			local res = h:Call(p, "Surf.Finish", { run = run.run, inputs = inputs })
			local expected = SurfLogic.Simulate(run.seed, inputs)
			expect(res.score).toBe(expected.score)
			expect(res.tokens).toBe(math.min(Config.Surf.MaxTokensPerRun, math.floor(expected.score / Config.Surf.PointsPerToken)))
			expect(h:System("Currency"):Balance(p, "token.summersplash")).toBe(before + res.tokens)
			expect(h:Section(p, "Surf").best).toBe(expected.score)
			expect(h:Section(p, "Quests").achievements.surf_10.progress).toBe(1)

			local later = TestKernel.new({ systems = SYSTEMS, startTime = SPLASH.endsAt + 60 })
			local q = later:Join()
			expect(later:Reject(q, "Surf.Start")).toBe("The Surf Shack opens during Summer Splash")
		end)
	end)

	describe("Season 4 and the 2.0 code", function()
		it("chains Season 4 after Season 3 with rewards that exist", function()
			local Q = Config.Quests
			expect(Q.Seasons[4].startsAt).toBe(Q.Seasons[3].endsAt)
			expect(Q.PassAt(Q.Seasons[4].startsAt + 10).season).toBe(4)
			for _, tier in Q.Seasons[4].tiers do
				for _, track in { tier.free, tier.premium } do
					for _, reward in track do
						if reward.kind == "egg" then
							expect(Config.Eggs.ById[reward.id] ~= nil).toBe(true)
						elseif reward.kind == "accessory" then
							expect(Config.Accessories.ById[reward.id] ~= nil).toBe(true)
						elseif reward.kind == "monster" then
							expect(Config.Species.ById[reward.id] ~= nil).toBe(true)
						end
					end
				end
			end
			expect(Q.Codes.LIGHTANDVOID.reward[1].id).toBe("sky")
		end)
	end)
end
