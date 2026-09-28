--[[
	WeatherCompat (Foundry wave 1c): the Weather controller on the Foundry's SkyWeather package
	looks exactly as it did. The old controller survives only here, verbatim, as
	tests/runtime/OldWeather.luau.

	  - The package's Ranch rules: SkyWeather.kindRate / qualityScale equal the old PROFILES
	    particle rates and LOW_PARTICLES bit for bit, for every Config.Weather id.
	  - Dense samples: the old controller, the new one on the package and the new one without it
	    (the fallback) are each loaded with the same test probe appended (it sets the weather, the
	    winter flag and the quality level, blends one frame of dt from another settled weather and
	    reads what step() wrote). Every weather x every from-weather x winter x 3 quality levels x
	    15 blend steps: the blended particle values and all four emitter Rates, equal at 17
	    significant digits.
	  - Frame by frame: one booted client runs the old controller (Substitute), one the new one on
	    the package, one the new one with the package removed. Every weather change (all 11 x 11,
	    switched mid-blend) at high, medium and low quality, with the camera moving: every frame
	    records the emitter Rates and part, ColorCorrection, Bloom, Atmosphere and Lighting; the
	    three recordings are equal string for string.
]]

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local SkyWeather = t.Shared("Foundry.SkyWeather.SkyWeather")
	local SkyRules = t.Shared("Foundry.SkyWeather.rules.monster-ranch")
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local CFrame = t.Roblox.CFrame

	local DT = 1 / 30
	local IDS = {}
	for _, w in Config.Weather.List do
		table.insert(IDS, w.id)
	end
	local TO_IDS = table.clone(IDS)
	table.insert(TO_IDS, "no-such-weather")
	local EMITTERS = { "rain", "snow", "stars", "pollen" }
	local STEPS = { 0, 1 / 240, 1 / 60, 1 / 30, 0.05, 0.1, 0.2, 0.4, 0.8, 1.6, 3, 5, 8, 12, 60 }

	local function fmt(v: number): string
		return string.format("%.17g", v)
	end

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	-- ─── Dense samples ───────────────────────────────────────────────────────────────

	-- Appended to both controllers before their final `return Weather` (test-only, never shipped).
	local PROBE = [[
function Weather.__Probe(id, from, winterOn, level, dt)
	seasonCheckIn = math.huge
	held = false
	lowGraphics = level == 1
	qualityLevel = level
	winter = winterOn
	weatherId = from
	computeTarget()
	for _, key in FIELDS do
		current[key] = target[key]
	end
	weatherId = id
	computeTarget()
	table.clear(written)
	step(dt)
	return string.format("%.17g %.17g %.17g %.17g | %s %s %s %s", current.rain, current.snow, current.stars,
		current.pollen, tostring(emitters.rain.Rate), tostring(emitters.snow.Rate), tostring(emitters.stars.Rate),
		tostring(emitters.pollen.Rate))
end
]]

	local function probed(c, file: string, ctx)
		local source = fs.readFile(t.Root .. "/" .. file)
		local at = string.find(source, "\nreturn Weather%s*$")
		assert(at, file .. " does not end in `return Weather`")
		source = string.sub(source, 1, at) .. PROBE .. string.sub(source, at + 1)
		local env = c:_env(c.clientFolder.Controllers.Weather)
		local module = luau.load(source, { debugName = file, environment = env })()
		module.Init(ctx)
		return module
	end

	local function samples(module): ({ string }, number)
		math.randomseed(1)
		local out, rates = {}, 0
		for _, id in TO_IDS do
			for _, from in IDS do
				for _, winterOn in { false, true } do
					for level = 1, 3 do
						for _, dt in STEPS do
							table.insert(out, `{id} {from} {winterOn} {level} {dt}: {module.__Probe(id, from, winterOn, level, dt)}`)
							rates += #EMITTERS
						end
					end
				end
			end
		end
		return out, rates
	end

	describe("the package's Ranch rules", function()
		it("kindRate and qualityScale equal the old PROFILES rates and LOW_PARTICLES bit for bit", function()
			-- the old controller's numbers (tests/runtime/OldWeather.luau PROFILES, LOW_PARTICLES)
			local old = { rain = { "rain", 450 }, thunderstorm = { "rain", 650 }, snow = { "snow", 160 } }
			old.starfall, old.lanternnight, old.pollenstorm = { "stars", 14 }, { "stars", 8 }, { "pollen", 120 }
			for _, id in IDS do
				local precip, rate = SkyWeather.kindRate(SkyRules, id)
				local want = old[id] or { "none", 0 }
				expect({ id, precip, rate }).toEqual({ id, want[1], want[2] })
			end
			expect({ SkyWeather.qualityScale(SkyRules, 1), SkyWeather.qualityScale(SkyRules, 2), SkyWeather.qualityScale(SkyRules, 3) }).toEqual({
				0.35,
				1,
				1,
			})
			expect(SkyRules.emitters.height).toBe(32)
			local source = fs.readFile(t.Root .. "/tests/runtime/OldWeather.luau")
			for _, line in
				{
					"rain = 450,",
					"rain = 650,",
					"snow = 160,",
					"stars = 14,",
					"stars = 8,",
					"pollen = 120,",
					"LOW_PARTICLES = 0.35",
					"EMITTER_HEIGHT = 32",
				}
			do
				expect({ line, string.find(source, line, 1, true) ~= nil }).toEqual({ line, true })
			end
		end)

		it("dense samples: old, package and fallback blend to the same particle values and Rates", function()
			local h = TestKernel.new({ systems = allSystems() })
			local c = ClientHarness.new(h, h:Join())
			local ctx = c.kernel:ScreenContext("WeatherCompat")
			expect(ctx.Foundry.packages.SkyWeather ~= nil).toBe(true)
			local noFoundry = setmetatable({ Foundry = false }, { __index = ctx })

			local old, rates = samples(probed(c, "tests/runtime/OldWeather.luau", ctx))
			local new = samples(probed(c, "src/client/Controllers/Weather.luau", ctx))
			local warnsBefore = #c.world.warnings
			local fallback = samples(probed(c, "src/client/Controllers/Weather.luau", noFoundry))
			local warned = 0
			for i = warnsBefore + 1, #c.world.warnings do
				if string.find(c.world.warnings[i], "SkyWeather package is not vendored", 1, true) then
					warned += 1
				end
			end
			expect(warned).toBe(1)

			expect(#old).toBe(12 * 11 * 2 * 3 * #STEPS)
			local moving, nonzero = 0, 0
			for i = 1, #old do
				if old[i] ~= new[i] or old[i] ~= fallback[i] then
					error(`sample {i} differs\n  old      {old[i]}\n  package  {new[i]}\n  fallback {fallback[i]}`)
				end
				if not string.find(old[i], "| 0 0 0 0$") then
					nonzero += 1
				end
				local a, b = string.match(old[i], "^(%S+) (%S+)")
				if a ~= b then
					moving += 1
				end
			end
			-- the grid really blends: most samples change weather, and plenty emit particles
			expect(moving > #old * 0.8 and nonzero > #old * 0.3).toBe(true)
			print(`WeatherCompat: {#old} probes x 3 controllers equal ({rates} emitter Rates, {rates} blended values each)`)
		end)
	end)

	-- ─── Frame by frame ──────────────────────────────────────────────────────────────

	local function colour(c): string
		return fmt(c.R) .. "," .. fmt(c.G) .. "," .. fmt(c.B)
	end

	local function snapshot(c, level: number): string
		local lighting = c.world.game:GetService("Lighting")
		local part = c.world.workspace:FindFirstChild("WeatherEmitter")
		local out = { `q{level}` }
		for _, name in { "Rain", "Snow", "Stars", "Pollen" } do
			table.insert(out, fmt(part:FindFirstChild(name).Rate))
		end
		local p = part.Position
		table.insert(out, `{fmt(p.X)},{fmt(p.Y)},{fmt(p.Z)}`)
		local cc = lighting:FindFirstChild("WeatherColor")
		local bloom = lighting:FindFirstChild("WeatherBloom")
		local atm = lighting:FindFirstChildOfClass("Atmosphere")
		table.insert(out, `cc {colour(cc.TintColor)} {fmt(cc.Brightness)} {fmt(cc.Contrast)} {fmt(cc.Saturation)}`)
		table.insert(out, `bloom {fmt(bloom.Intensity)} {fmt(bloom.Size)}`)
		table.insert(out, `atm {colour(atm.Color)} {fmt(atm.Density)} {fmt(atm.Haze)}`)
		table.insert(out, `light {fmt(lighting.Brightness)} {fmt(lighting.ClockTime)}`)
		return table.concat(out, " ")
	end

	-- mode: "old" (verbatim old controller), "new" (on the package), "fallback" (package removed)
	local function record(mode: string): ({ string }, any, any)
		math.randomseed(20260927)
		local h = TestKernel.new({ systems = allSystems() })
		local c = ClientHarness.new(h, h:Join(), { noBoot = true })
		if mode == "old" then
			c:Substitute(c.clientFolder.Controllers.Weather, "tests/runtime/OldWeather.luau")
		elseif mode == "fallback" then
			c.world.game:GetService("ReplicatedStorage").Shared.Foundry.SkyWeather:Destroy()
		end
		c:Boot()
		c:Advance(1)
		local Quality = c:require(c.clientFolder.Visuals.Quality)
		local weather = h:System("Weather")
		local camera = c.world.workspace.CurrentCamera
		local frames = {}
		local stats = { levels = {}, rainy = 0, snowy = 0, starry = 0, pollen = 0 }
		local f = 0
		local function frames_(n: number)
			for _ = 1, n do
				f += 1
				camera.CFrame = CFrame.new((f % 97) - 48, 20 + (f % 13), 30 - (f % 41))
				c:Advance(DT, DT)
				local level = Quality.Level()
				stats.levels[level] = true
				local snap = snapshot(c, level)
				table.insert(frames, snap)
				local part = c.world.workspace:FindFirstChild("WeatherEmitter")
				stats.rainy += if part:FindFirstChild("Rain").Rate > 0 then 1 else 0
				stats.snowy += if part:FindFirstChild("Snow").Rate > 0 then 1 else 0
				stats.starry += if part:FindFirstChild("Stars").Rate > 0 then 1 else 0
				stats.pollen += if part:FindFirstChild("Pollen").Rate > 0 then 1 else 0
			end
		end
		for _, q in { "high", "medium", "low" } do
			if q == "medium" then
				Quality.SetChoice("auto")
				Quality.SetAuto(2)
			else
				Quality.SetChoice(q)
			end
			for _, a in IDS do
				for _, b in IDS do
					expect(weather:Trigger(a, "WeatherCompat", 100000)).toBe(true)
					frames_(4)
					expect(weather:Trigger(b, "WeatherCompat", 100000)).toBe(true)
					frames_(8)
				end
			end
		end
		return frames, stats, c
	end

	local function compare(a: { string }, b: { string }, what: string)
		expect(#b).toBe(#a)
		for i = 1, #a do
			if a[i] ~= b[i] then
				error(`{what}: frame {i} differs\n--- old\n{a[i]}\n--- new\n{b[i]}`, 2)
			end
		end
	end

	describe("frame by frame against the old controller", function()
		it("the package path and the fallback draw exactly what the old controller drew", function()
			local old, oldStats = record("old")
			-- the run covers every particle kind and more than one quality level
			expect(oldStats.rainy > 100 and oldStats.snowy > 100 and oldStats.starry > 100 and oldStats.pollen > 100).toBe(true)
			expect(oldStats.levels[1] and oldStats.levels[3]).toBe(true)

			local new, newStats, c = record("new")
			compare(old, new, "package path")
			expect(newStats).toEqual(oldStats)
			local Weather = c:require(c.clientFolder.Controllers.Weather)
			for key, why in Weather.NotAdopted do
				expect({ key, #why >= 20 }).toEqual({ key, true })
			end
			expect(#c:Problems()).toBe(0)
			new, c = nil, nil

			local fb, fbStats, fc = record("fallback")
			compare(old, fb, "fallback")
			expect(fbStats).toEqual(oldStats)
			local warned = 0
			for _, w in fc.world.warnings do
				if string.find(w, "SkyWeather package is not vendored", 1, true) then
					warned += 1
				end
			end
			expect(warned).toBe(1)
			expect(#fc:Problems({ "not vendored" })).toBe(0)
			local levels = {}
			for level in oldStats.levels do
				table.insert(levels, level)
			end
			table.sort(levels)
			print(
				`WeatherCompat: {#old} frames x 3 runs equal ({#old * 4} emitter Rates each); quality levels {table.concat(levels, ",")}; frames with rain {oldStats.rainy}, snow {oldStats.snowy}, stars {oldStats.starry}, pollen {oldStats.pollen}`
			)
		end)
	end)
end
