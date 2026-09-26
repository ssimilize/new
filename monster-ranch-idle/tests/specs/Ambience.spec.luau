--[[
	Ambience: Logic/Ambience (the pure rules), Config/Ambience and Config/Vfx.Scenery (data rules),
	and the four client controllers (Sky, Lamplight, SceneryMotion, Critters) plus the Weather
	controller's sprites, run for real in RobloxMock: caps near the camera, lowGraphics, day and
	night, the live layer switches, and no errors.
]]

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Ambience")
	local Presets = t.Shared("Config.Vfx")
	local SpriteIds = t.Shared("Config.VfxSprites")
	local Vector3 = t.Roblox.Vector3
	local CFrame = t.Roblox.CFrame

	local A = Config.Ambience

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

	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		return h, p, c
	end

	-- A scenery folder like World/Scenery's, round the mock camera (0, 20, 30).
	local function plantScenery(c, counts)
		local folder = c.Instance.new("Folder")
		folder.Name = "Scenery"
		local i = 0
		for kind, n in counts do
			for _ = 1, n do
				i += 1
				local part = c.Instance.new("Part")
				part.Name = kind
				part.Anchored = true
				part.Size = Vector3.new(4, 8, 4)
				part.CFrame = CFrame.new((i % 7) * 6 - 18, 4, 30 + math.floor(i / 7) * 6 - 12)
				part.Parent = folder
			end
		end
		folder.Parent = c.world.workspace:FindFirstChild("World")
		return folder
	end

	describe("Logic/Ambience", function()
		it("fades night in through dusk and out through dawn", function()
			local on, off = A.Lights.on, A.Lights.off
			expect(Logic.Night(14, on, off)).toBe(0)
			expect(Logic.Night(0.5, on, off)).toBe(1)
			expect(Logic.Night(23, on, off)).toBe(1)
			expect(Logic.Night((on[1] + on[2]) / 2, on, off)).toBeNear(0.5, 1e-6)
			expect(Logic.Night((off[1] + off[2]) / 2, on, off)).toBeNear(0.5, 1e-6)
			expect(Logic.Night(24.5, on, off)).toBe(1) -- the Weather controller's night clock, unwrapped
		end)

		it("peaks the golden hour at dusk and dawn and is off at noon and midnight", function()
			local G = A.GoldenHour
			expect(Logic.GoldenHour(G.dusk.peak, G)).toBeNear(1, 1e-6)
			expect(Logic.GoldenHour(G.dawn.peak, G)).toBeNear(1, 1e-6)
			expect(Logic.GoldenHour(12, G)).toBe(0)
			expect(Logic.GoldenHour(0.5, G)).toBe(0)
			local mid = Logic.GoldenHour((G.dusk.from + G.dusk.peak) / 2, G)
			expect(mid > 0 and mid < 1).toBe(true)
		end)

		it("has a cloud look for every weather, darker at night, and no sun rays at night", function()
			for _, w in Config.Weather.List do
				expect({ w.id, A.Clouds.byWeather[w.id] ~= nil }).toEqual({ w.id, true })
				local cover, density, r = Logic.Clouds(A.Clouds, w.id, 0)
				expect(cover >= 0 and cover <= 1 and density >= 0 and density <= 1).toBe(true)
				local _, _, rn = Logic.Clouds(A.Clouds, w.id, 1)
				expect(rn < r or r == 0).toBe(true)
				expect(Logic.SunRays(A.SunRays, w.id, 1)).toBe(0)
			end
			local stormCover = Logic.Clouds(A.Clouds, "thunderstorm", 0)
			local clearCover = Logic.Clouds(A.Clouds, "clear", 0)
			expect(stormCover > clearCover).toBe(true)
			expect(Logic.Clouds(A.Clouds, "nope", 0)).toBe(clearCover)
			expect(Logic.SunRays(A.SunRays, "rain", 0)).toBe(0)
			expect(Logic.SunRays(A.SunRays, "clear", 0)).toBe(A.SunRays.default)
		end)

		it("picks the nearest within a radius, caps counts, and reads switches", function()
			local pts = { { X = 10, Z = 0 }, { X = 1, Z = 0 }, { X = 50, Z = 0 }, { X = 3, Z = 4 } }
			expect(Logic.Nearest(pts, 0, 0, 20, 2)).toEqual({ 2, 4 })
			expect(Logic.Nearest(pts, 0, 0, 20, 10)).toEqual({ 2, 4, 1 })
			expect(Logic.Nearest(pts, 0, 0, 20, 0)).toEqual({})
			expect(Logic.Cap({ max = 8, maxLow = 2 }, false)).toBe(8)
			expect(Logic.Cap({ max = 8, maxLow = 2 }, true)).toBe(2)
			expect(Logic.Cap({ max = 8 }, true)).toBe(0)
			expect(Logic.Enabled({ clouds = true }, "clouds", nil)).toBe(true)
			expect(Logic.Enabled({ clouds = false }, "clouds", nil)).toBe(false)
			expect(Logic.Enabled({ clouds = false }, "clouds", true)).toBe(true)
			expect(Logic.Enabled({ clouds = true }, "clouds", false)).toBe(false)
			local B = A.Critters.birds
			expect(Logic.Scared({ X = 0, Z = 0 }, { X = 3, Z = 0 }, B.scareSpeed + 1, B)).toBe(true)
			expect(Logic.Scared({ X = 0, Z = 0 }, { X = 3, Z = 0 }, B.scareSpeed - 1, B)).toBe(false)
			expect(Logic.Scared({ X = 0, Z = 0 }, { X = B.scare + 1, Z = 0 }, 30, B)).toBe(false)
			local ax, az = Logic.Sway(3.7, 1.1, 1, 0.5)
			expect(math.abs(ax) <= math.rad(1) + 1e-9 and math.abs(az) <= math.rad(1) + 1e-9).toBe(true)
		end)
	end)

	describe("Ambience config", function()
		it("keeps every layer switchable and every count capped, lower in low graphics", function()
			for _, name in
				{
					"sky",
					"clouds",
					"sunRays",
					"depthOfField",
					"goldenHour",
					"weatherSprites",
					"lights",
					"campfires",
					"fountain",
					"windmills",
					"sway",
					"butterflies",
					"fireflies",
					"birds",
					"fish",
				}
			do
				expect({ name, type(A.Layers[name]) }).toEqual({ name, "boolean" })
			end
			for _, entry in { A.Lights, A.Scenery.campfire, A.Scenery.windmill, A.Scenery.sway } do
				expect(entry.max > 0 and entry.max <= 12 and entry.maxLow <= entry.max).toBe(true)
			end
			for _, key in { "butterflies", "fireflies", "birds", "fish" } do
				local e = A.Critters[key]
				expect({ key, e.max <= 16 and e.maxLow <= 5 }).toEqual({ key, true })
			end
			-- "none in low graphics except a handful of fireflies"
			expect(A.Critters.butterflies.maxLow + A.Critters.birds.maxLow + A.Critters.fish.maxLow).toBe(0)
			for _, sprite in { "droplet", "snowflake", "petal", "star", "flame", "ember", "puff", "leaf", "ring" } do
				expect({ sprite, Presets.Sprites[sprite] ~= nil }).toEqual({ sprite, true })
			end
		end)

		it("follows the Vfx rules in the scenery effects", function()
			local problems = {}
			for id, specs in Presets.Scenery do
				local live = 0
				for i, spec in specs do
					local label = id .. "[" .. i .. "]"
					if not Presets.Sprites[spec.sprite] then
						table.insert(problems, label .. ": unknown sprite " .. tostring(spec.sprite))
					elseif spec.grey and not Presets.Sprites[spec.sprite].tint then
						table.insert(problems, label .. ": grey on a sprite with no grey twin")
					end
					local le = spec.lightEmission or 0.2
					if le < 0.15 or le > 0.3 then
						table.insert(problems, label .. ": daylight LightEmission must be 0.15 - 0.3")
					end
					for _, key in { "size", "transparency" } do
						local v = spec[key]
						if type(v) == "table" and (v[1][1] ~= 0 or v[#v][1] ~= 1) then
							table.insert(problems, label .. ": " .. key .. " keys must run 0 .. 1")
						end
					end
					if type(spec.transparency) == "table" and spec.transparency[#spec.transparency][2] < 0.6 then
						table.insert(problems, label .. ": must fade out")
					end
					if spec.on and id ~= "fountain" then
						table.insert(problems, label .. ": `on` is for the fountain only")
					end
					live += spec.rate * spec.lifetime[2]
				end
				if live > Presets.Budget.scenery then
					table.insert(problems, string.format("%s: %.1f live particles > %d", id, live, Presets.Budget.scenery))
				end
			end
			expect(problems).toEqual({})
		end)
	end)

	describe("Ambience client", function()
		it("builds the sky layers, warms the golden hour and drops the costly ones in low graphics", function()
			local _, _, c = boot()
			local lighting = c.world.game:GetService("Lighting")
			local rays = lighting:FindFirstChild("AmbienceSunRays")
			local dof = lighting:FindFirstChild("AmbienceDepthOfField")
			local golden = lighting:FindFirstChild("AmbienceGoldenHour")
			expect(rays ~= nil and dof ~= nil and golden ~= nil).toBe(true)
			expect(lighting:FindFirstChildOfClass("Sky") ~= nil).toBe(true)

			lighting.ClockTime = 12
			c:Advance(0.5)
			expect(golden.Enabled).toBe(false)
			expect(rays.Enabled and dof.Enabled).toBe(true)

			lighting.ClockTime = A.GoldenHour.dusk.peak
			c:Advance(0.5)
			expect(golden.Enabled).toBe(true)
			expect(golden.TintColor.B < 0.9).toBe(true)
			expect(rays.Intensity < A.SunRays.default).toBe(true) -- the sun is going down

			expect(c:Request("Settings.Set", { key = "lowGraphics", value = true })).toBe(true)
			c:Advance(0.5)
			expect(rays.Enabled or dof.Enabled).toBe(false)

			lighting:SetAttribute("Ambience_goldenHour", false)
			c:Advance(0.5)
			expect(golden.Enabled).toBe(false)
			expectClean(c)
		end)

		it("gives the weather particles the Vfx sprites", function()
			local _, _, c = boot()
			local emitter = c.world.workspace:FindFirstChild("WeatherEmitter")
			expect(emitter ~= nil).toBe(true)
			for name, sprite in { Rain = "droplet", Snow = "snowflake", Pollen = "petal", Stars = "star" } do
				local e = emitter:FindFirstChild(name)
				local row = SpriteIds[sprite]
				if row then
					expect({ name, e.Texture }).toEqual({ name, row.grey or row.color })
				end
			end
			expectClean(c)
		end)

		it("moves the nearest scenery, lights up at night and scales down in low graphics", function()
			local _, _, c = boot()
			local lighting = c.world.game:GetService("Lighting")
			lighting.ClockTime = 14
			local folder = plantScenery(c, { campfire = 6, oak = 8, bush = 6, flowers = 20, birdhouse = 3, crystals = 2 })
			local oak = folder:FindFirstChild("oak")
			local placed = {}
			for _, part in folder:GetChildren() do
				placed[part] = part.CFrame
			end
			c:Advance(2)
			local Motion = c:require(c.clientFolder.Controllers.SceneryMotion)
			local Lamplight = c:require(c.clientFolder.Controllers.Lamplight)
			local Critters = c:require(c.clientFolder.Controllers.Critters)

			local stats = Motion.Stats()
			expect(stats.campfire).toBe(A.Scenery.campfire.max)
			expect(stats.sway).toBe(A.Scenery.sway.max)
			expect(stats.fountain).toBe(1)
			local moved = 0
			for part, cf in placed do
				if part.Name == "oak" or part.Name == "bush" then
					if (part.CFrame.Position - cf.Position).Magnitude > 1e-4 then
						moved += 1
					end
					-- a rock about the base: the bottom stays put
					local bottom = part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)
					local was = cf * CFrame.new(0, -part.Size.Y / 2, 0)
					expect((bottom.Position - was.Position).Magnitude < 1e-3).toBe(true)
				end
			end
			expect(moved > 0).toBe(true)

			-- day: lights off, butterflies and birds out
			local on = Lamplight.Stats()
			expect(on).toBe(0)
			local shown = Critters.Stats()
			expect(shown.butterflies).toBe(A.Critters.butterflies.max)
			expect(shown.fireflies).toBe(0)
			expect(shown.birds > 0 and shown.birds <= A.Critters.birds.max).toBe(true)
			expect(shown.fish).toBe(A.Critters.fish.max)

			-- night: lights on (capped), fireflies instead of butterflies
			lighting.ClockTime = 0.5
			c:Advance(4)
			local lit, sources = Lamplight.Stats()
			expect(lit > 0 and lit <= A.Lights.max and sources > lit).toBe(true)
			shown = Critters.Stats()
			expect(shown.butterflies).toBe(0)
			expect(shown.fireflies).toBe(A.Critters.fireflies.max)

			-- low graphics: fewer of everything, no sway, trees back where they were placed
			expect(c:Request("Settings.Set", { key = "lowGraphics", value = true })).toBe(true)
			c:Advance(4)
			stats = Motion.Stats()
			expect(stats.campfire).toBe(A.Scenery.campfire.maxLow)
			expect(stats.sway).toBe(0)
			expect(oak.CFrame).toEqual(placed[oak])
			lit = Lamplight.Stats()
			expect(lit <= A.Lights.maxLow).toBe(true)
			shown = Critters.Stats()
			expect(shown.fireflies).toBe(A.Critters.fireflies.maxLow)
			expect(shown.birds + shown.fish + shown.butterflies).toBe(0)

			-- a live layer switch
			lighting:SetAttribute("Ambience_campfires", false)
			lighting:SetAttribute("Ambience_fireflies", false)
			lighting:SetAttribute("Ambience_lights", false)
			c:Advance(2)
			expect(Motion.Stats().campfire).toBe(0)
			expect(Critters.Stats().fireflies).toBe(0)
			expect((Lamplight.Stats())).toBe(0)
			expectClean(c)
		end)
	end)
end
