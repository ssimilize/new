--[[
	ObservatoryClient (update 3.12 · Honey & stars): the Observatory through the real client
	(ClientHarness): the "Stargaze" prompt on the telescope opens the screen; by day it shows when
	night falls; at night Observe starts a sighting, clicking the stars in the traced order logs an
	observation and the chart's progress shows; a wrong star fails the sighting; the locked screen
	before Level 19 and Spanish text.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Observatory")

	local Cfg = Config.Observatory
	local LENGTH = Config.Weather.DayLength
	local BASE = 1790000000
	local NIGHT = BASE - BASE % LENGTH + math.floor(LENGTH * (1 - Config.Weather.NightFraction)) + 5
	local DAY = NIGHT - 300

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function levelTo(h, p, level: number)
		local P = h:System("Progression")
		while P:GetLevel(p) < level do
			P:AddXP(p, Config.Unlocks.XPToNext(P:GetLevel(p)) - h:Section(p, "Progression").xp, "test")
		end
	end

	local function stargazePrompt(c)
		for _, d in c.world.workspace:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.ActionText == "Stargaze" then
				return d
			end
		end
		return nil
	end

	local function boot(at: number, level: number?, opts)
		local h = TestKernel.new({ systems = allSystems(), startTime = at })
		local p = h:Join()
		levelTo(h, p, level or Config.Unlocks.Features.observatory)
		local c = ClientHarness.new(h, p, opts)
		c:Advance(1)
		return h, p, c
	end

	-- The order the server dealt for the player's next sighting (sighting `n` tonight).
	local function orderOf(h, p, chart: string, n: number)
		local s = h:Section(p, "Observatory")
		return Logic.Sky(Logic.Seed(p.UserId, NIGHT // LENGTH, n, s.secret), Cfg.ById[chart].stars).order
	end

	describe("Observatory", function()
		it("opens from the prompt at night, traces a sighting and shows the chart's progress", function()
			local h, p, c = boot(NIGHT)
			h:Section(p, "Observatory").secret = 777
			local prompt = stargazePrompt(c)
			expect(prompt ~= nil).toBe(true)
			expect(prompt:FindFirstAncestor("Observatory") ~= nil).toBe(true)
			c:Trigger(prompt)
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Observatory")
			local screen = c:Screen("Observatory")
			expect(c:HasText(string.format("Sightings left tonight: %d / %d", Cfg.Sightings, Cfg.Sightings), screen)).toBe(true)
			expect(c:HasText("Star perks", screen)).toBe(true)

			local row = screen:FindFirstChild("Chart_ladle", true)
			c:Click(row:FindFirstChild("Observe", true))
			c:Advance(0.5)
			local order = orderOf(h, p, "ladle", 1)
			expect(screen:FindFirstChild("Star_" .. Cfg.ById.ladle.stars, true) ~= nil).toBe(true)
			for _, star in order do
				c:Click(screen:FindFirstChild("Star_" .. star, true))
				c:Advance(0.3)
			end
			c:Advance(0.5)
			expect(h:Section(p, "Observatory").charts.ladle).toBe(1)
			expect(c:HasText(string.format("Sighting logged! %s · 1 / %d", Cfg.ById.ladle.name, Cfg.Observations), screen)).toBe(true)
			row = screen:FindFirstChild("Chart_ladle", true)
			expect(row:GetAttribute("Progress")).toBe(1)
			expect(c:HasText(string.format("Progress 1 / %d · %s", Cfg.Observations, Logic.PerkText("egg_speed", 0.02)), row)).toBe(true)
			expect(c:HasText(string.format("Sightings left tonight: %d / %d", Cfg.Sightings - 1, Cfg.Sightings), screen)).toBe(true)

			-- A wrong first star fails the sighting (and uses it).
			c:Click(screen:FindFirstChild("Chart_lantern", true):FindFirstChild("Observe", true))
			c:Advance(0.5)
			local wrong = orderOf(h, p, "lantern", 2)[2]
			c:Click(screen:FindFirstChild("Star_" .. wrong, true))
			c:Advance(0.5)
			expect(c:HasText("Wrong order · the pattern slipped away", screen)).toBe(true)
			expect(h:Section(p, "Observatory").charts.lantern).toBeNil()
			expect(h:Section(p, "Observatory").used).toBe(2)
			expectClean(c)
		end)

		it("shows when night falls by day", function()
			local _, _, c = boot(DAY)
			local screen = c:Open("Observatory")
			c:Advance(0.5)
			local clock = screen:FindFirstChild("SkyClock", true)
			expect(string.find(clock.Text, "Opens at night · in ", 1, true) == 1).toBe(true)
			expect(c:HasText("Come back at night to observe the stars", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the observatory locked before Level 19", function()
			local _, _, c = boot(NIGHT, 1)
			local screen = c:Open("Observatory")
			c:Advance(0.5)
			expect(c:HasText("Unlocks at Ranch Level 19", screen)).toBe(true)
			expectClean(c)
		end)

		it("shows the observatory in Spanish", function()
			local _, _, c = boot(NIGHT, nil, { localeId = "es-mx" })
			c:Open("Observatory")
			c:Advance(0.5)
			expect(c:HasText("Observatorio")).toBe(true)
			expect(c:HasText("Cartas estelares")).toBe(true)
			expectClean(c)
		end)
	end)
end
