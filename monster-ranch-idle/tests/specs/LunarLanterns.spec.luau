-- Update 1.2 · Lunar Lanterns: the event calendar (Config.Events), event tokens earned by
-- playing (Events system), Lantern Night weather with the Glow mutation, the Lantern Egg
-- and its three lines, and the event decor.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local Events = Config.Events

	local LANTERNS = Events.ById.lunarlanterns
	local DURING = LANTERNS.startsAt + 3600 -- a Saturday afternoon (UTC), during the event

	local function withFlag(value, fn)
		local before = Config.Flags.ActiveEvent
		Config.Flags.ActiveEvent = value
		local ok, err = pcall(fn)
		Config.Flags.ActiveEvent = before
		assert(ok, err)
	end

	local function tokens(h, p)
		return h:System("Currency"):Balance(p, "token.lunarlanterns")
	end

	describe("Calendar", function()
		it("runs each event in its window and never overlaps", function()
			expect(Events.ActiveId(LANTERNS.startsAt - 1)).toBeNil()
			expect(Events.ActiveId(LANTERNS.startsAt)).toBe("lunarlanterns")
			expect(Events.ActiveId(LANTERNS.endsAt - 1)).toBe("lunarlanterns")
			expect(Events.ActiveId(LANTERNS.endsAt)).toBeNil()
			expect(Events.ActiveId(Events.ById.frostfall.startsAt)).toBe("frostfall")
			for i, a in Events.List do
				expect(a.endsAt).toBeGreaterThan(a.startsAt)
				for j, b in Events.List do
					if i ~= j then
						expect(a.endsAt <= b.startsAt or b.endsAt <= a.startsAt).toBe(true)
					end
				end
			end
			expect(Events.Next(LANTERNS.startsAt - 10).id).toBe("lunarlanterns")
		end)

		it("lets Flags.ActiveEvent force an event or turn events off", function()
			withFlag("frostfall", function()
				expect(Events.ActiveId(DURING)).toBe("frostfall")
			end)
			withFlag(false, function()
				expect(Events.ActiveId(DURING)).toBeNil()
			end)
		end)
	end)

	describe("Lantern Night", function()
		it("only rolls at night while Lunar Lanterns runs", function()
			local WeatherRoll = t.Shared("Logic.WeatherRoll")
			local index
			for i, w in Config.Weather.List do
				if w.id == "lanternnight" then
					index = i
				end
			end
			expect(index ~= nil).toBe(true)
			expect(WeatherRoll.Weights({ night = true })[index]).toBe(0)
			expect(WeatherRoll.Weights({ night = false, event = "lunarlanterns" })[index]).toBe(0)
			expect(WeatherRoll.Weights({ night = true, event = "frostfall" })[index]).toBe(0)
			expect(WeatherRoll.Weights({ night = true, event = "lunarlanterns" })[index]).toBeGreaterThan(0)
			expect(Config.Weather.ById.lanternnight.mutation).toBe("glow")
			expect(Config.Mutations.ById.glow ~= nil).toBe(true)
		end)
	end)

	describe("Event tokens", function()
		local SYSTEMS = { "Currency", "Progression", "Rewards", "Events" }

		it("pays a daily login bonus once per day while the event runs", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = DURING })
			local p = h:Join()
			expect(tokens(h, p)).toBe(Events.Earn.dailyLogin)
			p = h:Rejoin(p, 60)
			expect(tokens(h, p)).toBe(Events.Earn.dailyLogin)
			p = h:Rejoin(p, 86400)
			expect(tokens(h, p)).toBe(2 * Events.Earn.dailyLogin)
			expect(h:Client(p).global.Events.id).toBe("lunarlanterns")
			expect(h:Client(p).global.Events.token.name).toBe("Lantern Coins")
		end)

		it("earns tokens from play up to the daily cap", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = DURING })
			local p = h:Join()
			local start = tokens(h, p)
			h.kernel.Bus:Publish("BossJoined", p, {})
			h.kernel.Bus:Publish("ExpeditionClaimed", p, { slot = 1, duration = 14400 })
			h.kernel.Bus:Publish("StageCleared", p, { region = "meadow", stage = 3, first = true })
			h.kernel.Bus:Publish("StageCleared", p, { region = "meadow", stage = 3, first = false })
			h.kernel.Bus:Publish("EggHatched", p, { id = "m1", egg = "meadow", rarity = 1, variant = 0 })
			local earned = tokens(h, p) - start
			expect(earned).toBe(Events.Earn.bossJoined + 4 * Events.Earn.expeditionPerHour + Events.Earn.stageFirstClear + Events.Earn.hatch)
			for _ = 1, 100 do
				h.kernel.Bus:Publish("BossJoined", p, {})
			end
			expect(tokens(h, p)).toBe(Events.Earn.dailyCap)
			expect(h:Section(p, "Events").earned).toBe(Events.Earn.dailyCap)
		end)

		it("pays nothing outside the event and closes the event on time", function()
			local h = TestKernel.new({ systems = SYSTEMS, startTime = LANTERNS.endsAt - 40 })
			local p = h:Join()
			expect(h:Client(p).global.Events.id).toBe("lunarlanterns")
			h:Advance(60)
			expect(h:Client(p).global.Events.id).toBe(false)
			local before = tokens(h, p)
			h.kernel.Bus:Publish("BossJoined", p, {})
			expect(tokens(h, p)).toBe(before)
		end)
	end)

	describe("Lantern Egg", function()
		it("sells for Lantern Coins only during the event", function()
			local systems = { "Currency", "Progression", "Rewards", "Monsters", "Eggs", "Shop", "Events" }
			local h = TestKernel.new({ systems = systems, startTime = DURING })
			local p = h:Join()
			h:System("Currency"):Add(p, "token.lunarlanterns", 1000, "test")
			local bought = h:Call(p, "Shop.BuyEgg", { egg = "lantern", amount = 1 })
			expect(#bought.eggs).toBe(1)
			expect(tokens(h, p)).toBe(1000 + Events.Earn.dailyLogin - 400)
			h:Call(p, "Shop.BuyDecor", { decor = "paper_lantern" })
			local later = TestKernel.new({ systems = systems, startTime = LANTERNS.endsAt + 3600 })
			local q = later:Join()
			later:System("Currency"):Add(q, "token.lunarlanterns", 1000, "test")
			expect(later:Reject(q, "Shop.BuyEgg", { egg = "lantern", amount = 1 })).toBeTruthy()
		end)

		it("hatches the three Lunar Lanterns lines with the Glow mutation", function()
			local EggRoll = t.Shared("Logic.EggRoll")
			local Rng = t.Shared("Logic.Rng")
			local rng = Rng.new(5)
			local lines = {}
			for _ = 1, 300 do
				local spec = EggRoll.roll(rng, Config.Eggs.ById.lantern, {})
				lines[spec.line] = true
				expect(spec.muts).toEqual({ "glow" })
				expect(Config.Species.ById[spec.line].event).toBe("lunarlanterns")
			end
			local count = 0
			for _ in lines do
				count += 1
			end
			expect(count).toBe(3)
			expect(lines.lanternling).toBe(true)
		end)
	end)
end
