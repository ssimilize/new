-- S5 Weather: Logic/WeatherRoll, the server schedule, day/night, mutation rolls, totems and the
-- tutorial guarantee. Ranch, Eggs and Monetization are stubbed.
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel = t.TestKernel
	local Config = t.Shared("Config")
	local WeatherRoll = t.Shared("Logic.WeatherRoll")
	local Rng = t.Shared("Logic.Rng")

	local W = Config.Weather

	local function indexOf(id)
		for i, w in W.List do
			if w.id == id then
				return i
			end
		end
		return nil
	end

	-- Temporarily overrides a config value (restored even if the test fails).
	local function withValue(tbl, key, value, fn)
		local old = tbl[key]
		tbl[key] = value
		local ok, err = pcall(fn)
		tbl[key] = old
		if not ok then
			error(err, 0)
		end
	end

	describe("Logic/WeatherRoll", function()
		it("keeps Blood Moon to the night and applies event boosts", function()
			local day = WeatherRoll.Weights({ night = false })
			local night = WeatherRoll.Weights({ night = true })
			expect(day[indexOf("bloodmoon")]).toBe(0)
			expect(night[indexOf("bloodmoon")]).toBe(3)
			expect(day[indexOf("clear")]).toBe(55)
			local harvest = WeatherRoll.Weights({ night = true, event = "harvestmoon" })
			expect(harvest[indexOf("bloodmoon")]).toBe(9)
			local frost = WeatherRoll.Weights({ night = false, event = "frostfall" })
			expect(frost[indexOf("snow")]).toBe(18)

			local rng = Rng.new(3)
			local nightMoons, N = 0, 20000
			for _ = 1, N do
				expect(WeatherRoll.Roll(rng, { night = false }) ~= "bloodmoon").toBe(true)
				if WeatherRoll.Roll(rng, { night = true }) == "bloodmoon" then
					nightMoons += 1
				end
			end
			expect(nightMoons / N).toBeNear(0.03, 0.006)
		end)

		it("aligns day/night and the roll clock to the unix clock", function()
			local length = W.DayLength
			local base = 1790000000 - 1790000000 % length
			local nightStart = base + math.floor(length * (1 - W.NightFraction))
			local night, endsAt = WeatherRoll.Phase(base + 10)
			expect(night).toBe(false)
			expect(endsAt).toBe(nightStart)
			night, endsAt = WeatherRoll.Phase(nightStart)
			expect(night).toBe(true)
			expect(endsAt).toBe(base + length)
			expect(WeatherRoll.NextRollAt(base)).toBe(base + W.RollInterval)
			expect(WeatherRoll.NextRollAt(base + 1) % W.RollInterval).toBe(0)
		end)

		it("splits the event chance over ticks with Weather Magnet and Stargazer", function()
			local rain, starfall = W.ById.rain, W.ById.starfall
			expect(WeatherRoll.MutationChance(rain, { "tide" }, {})).toBeNear(0.12 / W.Ticks)
			expect(WeatherRoll.MutationChance(rain, { "ember" }, {})).toBeNear(0.04 / W.Ticks)
			expect(WeatherRoll.MutationChance(rain, { "tide" }, { 14 })).toBeNear(0.24 / W.Ticks) -- Weather Magnet
			expect(WeatherRoll.MutationChance(rain, { "tide" }, { 19 })).toBeNear(0.12 / W.Ticks) -- Stargazer: starry only
			expect(WeatherRoll.MutationChance(starfall, { "ember" }, { 19 })).toBeNear(0.05 * 1.5 / W.Ticks)
			expect(WeatherRoll.MutationChance(starfall, { "ember" }, { 14, 19 })).toBeNear(0.05 * 3 / W.Ticks)
			expect(WeatherRoll.MutationChance(W.ById.clear, { "ember" }, { 14 })).toBe(0)
		end)
	end)

	-- System ------------------------------------------------------------------------------

	local function boot()
		local pens = {} -- [userId] = { { id, pen } }
		local calls = { pens = 0 }
		local eggs = {} -- { { player, type, source } }
		local products, speed = {}, {}
		local stubs = {
			Ranch = {
				MonstersInPens = function(_, player)
					calls.pens += 1
					return pens[player.UserId] or {}
				end,
			},
			Eggs = {
				Add = function(_, player, eggType, source, amount)
					table.insert(eggs, { player = player, type = eggType, source = source, amount = amount })
					return { "e1" }
				end,
				RegisterSpeedProvider = function(_, key, fn)
					speed[key] = fn
				end,
			},
			Monetization = {
				RegisterProduct = function(_, key, fn)
					products[key] = fn
				end,
				HasPass = function()
					return false
				end,
			},
		}
		local h = TestKernel.new({ systems = { "Currency", "Progression", "Rewards", "Monsters", "Weather" }, stubs = stubs })
		local changes = {}
		h.kernel.Bus:Subscribe("WeatherChanged", function(_, detail)
			table.insert(changes, { id = detail.id, at = h.adapters.Clock.Now() })
		end)
		return h, { pens = pens, calls = calls, eggs = eggs, products = products, speed = speed, changes = changes }
	end

	local function inPen(env, M, p, fields)
		local spec = { line = "bubblin", rarity = 1, traits = { 3, 4 }, hidden = 5 }
		for k, v in fields or {} do
			spec[k] = v
		end
		local m = M:Create(p, spec, "test", true)
		env.pens[p.UserId] = env.pens[p.UserId] or {}
		table.insert(env.pens[p.UserId], { id = m.id, pen = 1 })
		return m
	end

	describe("Weather system", function()
		it("starts clear, rolls on the clock and runs each weather for its duration", function()
			local h, env = boot()
			local W0 = h:System("Weather")
			local g = h.kernel.State:GlobalRoot("Weather")
			local now = h.adapters.Clock.Now()
			expect(g.id).toBe("clear")
			expect(g.nextRollAt % W.RollInterval).toBe(0)
			expect(g.nextRollAt > now).toBe(true)
			local night = WeatherRoll.Phase(now)
			expect(g.night).toBe(night)
			expect(W0:IsNight()).toBe(night)

			h:Advance(g.nextRollAt - now)
			expect(g.nextRollAt).toBe(WeatherRoll.NextRollAt(h.adapters.Clock.Now()))

			-- Many roll windows: every non-clear weather lasts Duration, Blood Moon only at night.
			local nights = {}
			h.kernel.Bus:Subscribe("WeatherChanged", function(_, detail)
				nights[#nights + 1] = { id = detail.id, night = g.night }
			end)
			h:Advance(40 * W.RollInterval)
			local started = 0
			for i, c in env.changes do
				if c.id ~= "clear" then
					started += 1
					local nextChange = env.changes[i + 1]
					if nextChange then
						expect(nextChange.id).toBe("clear")
						expect(nextChange.at - c.at).toBe(W.Duration)
					end
				end
			end
			expect(started).toBeGreaterThan(5)
			for _, n in nights do
				if n.id == "bloodmoon" then
					expect(n.night).toBe(true)
				end
			end
			expect(h:Client(h:Join()).global.Weather.nextRollAt).toBe(g.nextRollAt)
		end)

		it("cycles day and night", function()
			local h = boot()
			local g = h.kernel.State:GlobalRoot("Weather")
			local seen = {}
			for _ = 1, 4 do
				local wait = g.phaseEndsAt - h.adapters.Clock.Now()
				h:Advance(wait)
				seen[#seen + 1] = g.night
				expect(g.phaseEndsAt > h.adapters.Clock.Now()).toBe(true)
			end
			expect(seen[1] ~= seen[2]).toBe(true)
			expect(seen[2] ~= seen[3]).toBe(true)
		end)

		it("mutates pen monsters over Ticks rolls, matching element first", function()
			local h, env = boot()
			local M = h:System("Monsters")
			local p = h:Join()
			local tide = inPen(env, M, p, { line = "bubblin" })
			local ember = inPen(env, M, p, { line = "cindlet" })
			local busy = inPen(env, M, p, { line = "coralbun" })
			M:SetBusy(p, busy.id, "expedition")
			local barn = M:Create(p, { line = "drizzlet", rarity = 1 }, "test", true)
			local mutated = {}
			h.kernel.Bus:Subscribe("Mutated", function(_, detail)
				table.insert(mutated, detail)
			end)
			local rain = W.ById.rain
			withValue(rain, "matchChance", W.Ticks, function() -- certain for Tide
				withValue(rain, "chance", 0, function()
					h:System("Weather"):Trigger("rain", "tutorial")
					env.calls.pens = 0
					h:Advance(W.Duration)
				end)
			end)
			expect(env.calls.pens).toBe(W.Ticks)
			expect(tide.muts).toEqual({ "soaked" })
			expect(#ember.muts).toBe(0)
			expect(#busy.muts).toBe(0)
			expect(#barn.muts).toBe(0)
			expect(#mutated).toBe(1)
			local ev = h:LastEvent(p, "Weather.Mutated")
			expect(ev.payload.id).toBe(tide.id)
			expect(ev.payload.mutation).toBe("soaked")
			expect(ev.payload.result).toBe("added")
			expect(h.kernel.State:GlobalRoot("Weather").id).toBe("clear")
		end)

		it("doubles the chance with Weather Magnet and reports combos", function()
			local h, env = boot()
			local M = h:System("Monsters")
			local p = h:Join()
			local magnet = inPen(env, M, p, { line = "cindlet", traits = { 14, 3 }, muts = { "soaked" } })
			local plain = inPen(env, M, p, { line = "cindlet" })
			local snow = W.ById.snow
			withValue(snow, "chance", W.Ticks / 2, function() -- 50% per tick, 100% with the magnet
				withValue(snow, "matchChance", W.Ticks / 2, function()
					h:System("Weather"):Trigger("snow", "tutorial", 16)
					h:Advance(1)
				end)
			end)
			expect(magnet.muts).toEqual({ "frozen" })
			expect(h:LastEvent(p, "Weather.Mutated").payload.result).toBe("combined")
			expect(h:LastEvent(p, "Weather.Mutated").payload.mutation).toBe("frozen")
			expect(#plain.muts <= 1).toBe(true)
		end)

		it("gives everyone online a free egg when Starfall starts", function()
			local h, env = boot()
			local a, b = h:Join(), h:Join()
			expect(h:System("Weather"):Trigger("starfall", "PixelPaws")).toBe(true)
			expect(#env.eggs).toBe(2)
			expect(env.eggs[1].type).toBe("grove")
			local g = h:Client(a).global.Weather
			expect(g.id).toBe("starfall")
			expect(g.summonedBy).toBe("PixelPaws")
			expect(g.endsAt).toBe(h.adapters.Clock.Now() + W.Duration)
			expect(h:Client(b).global.Weather.id).toBe("starfall")
			h:Advance(W.Duration)
			expect(#env.eggs).toBe(2)
		end)

		it("runs Robux totems now, or queues them behind running weather", function()
			local h, env = boot()
			local p = h:Join(nil, "Totemer")
			local handler = env.products["Weather.Totem"]
			expect(handler).toBeTruthy()
			local Products = Config.Monetization.ProductByKey
			expect(handler(p, Products.totemRain)).toBe(true)
			local g = h.kernel.State:GlobalRoot("Weather")
			expect(g.id).toBe("rain")
			expect(g.summonedBy).toBe("Totemer")
			expect(handler(p, Products.totemThunder)).toBe(true)
			expect(g.id).toBe("rain")
			expect(h:LastEvent(p, "Kernel.Notify").payload.text).toContain("after the current Rain")
			h:Advance(W.Duration)
			expect(g.id).toBe("thunderstorm")
			expect(g.summonedBy).toBe("Totemer")
			expect(handler(p, { key = "bad", args = { weather = "aurora" } })).toBe(false)
			expect(handler(p, { key = "bad" })).toBe(false)
		end)

		it("speeds up incubators during a Heatwave", function()
			local h, env = boot()
			local p = h:Join()
			local provider = env.speed.heatwave
			expect(provider(p)).toBe(0)
			h:System("Weather"):Trigger("heatwave", "admin")
			expect(provider(p)).toBeNear(0.2)
			expect(h:System("Weather"):Effects().hatchSpeed).toBe(1.25)
			h:Advance(W.Duration)
			expect(provider(p)).toBe(0)
		end)

		it("triggers, replaces and clears weather", function()
			local h, env = boot()
			local Weather = h:System("Weather")
			expect(Weather:Trigger("nope", "admin")).toBe(false)
			expect(Weather:Trigger("rain", "admin", 30)).toBe(true)
			expect(Weather:Current().endsAt).toBe(h.adapters.Clock.Now() + 30)
			expect(Weather:Trigger("snow", "admin")).toBe(true)
			expect(Weather:Current().id).toBe("snow")
			expect(Weather:Trigger("clear", "admin")).toBe(true)
			expect(Weather:Current().id).toBe("clear")
			expect(Weather:Current().endsAt).toBe(0)
			local ids = {}
			for _, c in env.changes do
				table.insert(ids, c.id)
			end
			expect(ids).toEqual({ "rain", "snow", "clear" })
		end)

		it("guarantees the tutorial mutation on one monster that lacks it", function()
			local h, env = boot()
			local M = h:System("Monsters")
			local p = h:Join()
			local Weather = h:System("Weather")
			local barnOnly = M:Create(p, { line = "cindlet", rarity = 1 }, "test", true)
			-- no pens yet: falls back to any free monster
			expect(Weather:GuaranteeMutation(p, "soaked")).toBe(true)
			expect(barnOnly.muts).toEqual({ "soaked" })
			local penned = inPen(env, M, p, { line = "mossbun" })
			expect(Weather:GuaranteeMutation(p, "soaked")).toBe(true)
			expect(penned.muts).toEqual({ "soaked" })
			expect(Weather:GuaranteeMutation(p, "soaked")).toBe(false)
			expect(Weather:GuaranteeMutation(p, "not_a_mutation")).toBe(false)
			expect(h:LastEvent(p, "Weather.Mutated").payload.id).toBe(penned.id)
		end)
	end)
end
