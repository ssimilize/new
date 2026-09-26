--[[
	Quality (glow-up P): Logic/Quality (the Graphics choice, the Auto stepper's hysteresis, the
	distance LOD rules), Logic/ParticleBudget (the budget plan and the burst allowance) as pure
	units, and the real client: the Settings screen's Graphics choice, the Auto stepper on the
	harness's 10 fps frames, Vfx's budget pass, and switching levels without leaks.
]]

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local Logic = t.Shared("Logic.Quality")
	local Budget = t.Shared("Logic.ParticleBudget")
	local Presets = t.Shared("Config.Vfx")
	local Vector3 = t.Roblox.Vector3
	local CFrame = t.Roblox.CFrame

	local Q = Config.Quality

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
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

	-- Feeds `seconds` of frames of `ms` each, evaluating once a second like the controller.
	local function run(s, now: number, seconds: number, ms: number): (number, { number })
		local levels = {}
		local fps = math.max(1, math.floor(1000 / ms))
		for _ = 1, seconds do
			for i = 1, fps do
				Logic.Sample(s, ms / 1000, now + i / fps)
			end
			now += 1
			local level = Logic.Evaluate(s, now)
			table.insert(levels, level)
		end
		return now, levels
	end

	local function changes(levels: { number }): number
		local n = 0
		for i = 2, #levels do
			if levels[i] ~= levels[i - 1] then
				n += 1
			end
		end
		return n
	end

	describe("Logic/Quality: the Graphics choice", function()
		it("reads an old lowGraphics save as Low and defaults to Auto", function()
			expect(Logic.Choice(nil)).toBe("auto")
			expect(Logic.Choice({})).toBe("auto")
			expect(Logic.Choice({ lowGraphics = true })).toBe("low")
			expect(Logic.Choice({ lowGraphics = true, graphics = "high" })).toBe("low")
			expect(Logic.Choice({ lowGraphics = false, graphics = "high" })).toBe("high")
			expect(Logic.Choice({ lowGraphics = false, graphics = "low" })).toBe("auto") -- the old toggle switched it off
			expect(Logic.Choice({ graphics = "ultra" })).toBe("auto")
		end)

		it("resolves pinned choices over the measured level", function()
			expect(Logic.Resolve("high", 1)).toBe(3)
			expect(Logic.Resolve("low", 3)).toBe(1)
			expect(Logic.Resolve("auto", 2)).toBe(2)
			expect(Logic.Resolve("auto", 9)).toBe(3)
			expect(Logic.Median({ 5, 1, 3 })).toBe(3)
			expect(Logic.Median({ 4, 1, 3, 2 })).toBe(2.5)
		end)

		it("has a gap between each level's step-down and the next level's step-up", function()
			for level = 1, 2 do
				expect(Q.Auto.up[level] < Q.Auto.down[level + 1]).toBe(true)
			end
			expect(Q.Auto.up[2] < Q.Auto.up[1]).toBe(true)
			expect(Q.Auto.downAfter < Q.Auto.upAfter).toBe(true)
		end)
	end)

	describe("Logic/Quality: the Auto stepper", function()
		it("ignores the warm-up, then steps down one level at a time on slow frames", function()
			local s = Logic.NewStepper(Q.Auto, 0)
			local now, levels = run(s, 0, Q.Auto.warmup, 50)
			expect(levels[#levels]).toBe(3) -- nothing counted during the warm-up
			now, levels = run(s, now, 6, 50)
			expect(levels[#levels]).toBe(2)
			expect(changes(levels)).toBe(1)
			-- The cooldown keeps it at Medium for a while even though frames stay slow.
			local _, next = run(s, now, Q.Auto.cooldown - 2, 50)
			expect(next[1]).toBe(2)
			now, levels = run(s, now + Q.Auto.cooldown, 8, 50)
			expect(levels[#levels]).toBe(1)
			expect(Logic.NewStepper(Q.Auto, 0).level).toBe(Q.Auto.start)
		end)

		it("drops hitches and held frames", function()
			local s = Logic.NewStepper(Q.Auto, 0)
			local now = Q.Auto.warmup + 1
			for i = 1, 200 do
				Logic.Sample(s, 0.5, now + i / 100) -- a loading hitch: 500 ms frames
			end
			expect(#s.ms).toBe(0)
			Logic.Hold(s, now, 3)
			Logic.Sample(s, 0.05, now + 1)
			expect(#s.ms).toBe(0)
			Logic.Sample(s, 0.05, now + 3.5)
			expect(#s.ms).toBe(1)
		end)

		it("never flaps on frames between the thresholds", function()
			local s = Logic.NewStepper(Q.Auto, 0)
			local now = run(s, 0, Q.Auto.warmup, 16)
			now = run(s, now, 30, 50) -- down to Low
			expect(s.level).toBe(1)
			local mid = (Q.Auto.up[1] + Q.Auto.down[2]) / 2 -- too slow to climb, too fast to drop
			local _, levels = run(s, now, 120, mid)
			expect(changes(levels)).toBe(0)
		end)

		it("climbs back only after a long good run, and waits longer after a relapse", function()
			local s = Logic.NewStepper(Q.Auto, 0)
			local now = run(s, 0, Q.Auto.warmup, 16)
			now = run(s, now, 8, 28) -- 28 ms: High -> Medium only
			expect(s.level).toBe(2)
			local levels
			now, levels = run(s, now, Q.Auto.upAfter - 5, 14)
			expect(levels[#levels]).toBe(2) -- not yet
			now = run(s, now, 10, 14)
			expect(s.level).toBe(3)
			now = run(s, now, 6, 28) -- it could not hold High
			expect(s.level).toBe(2)
			expect(s.upAfter[2]).toBe(Q.Auto.upAfter * 2)
			now, levels = run(s, now, Q.Auto.upAfter + 5, 14)
			expect(levels[#levels]).toBe(2) -- the doubled wait
			run(s, now, Q.Auto.upAfter + 5, 14)
			expect(s.level).toBe(3)
		end)
	end)

	describe("Logic/Quality: distance LOD", function()
		local lod = Q.Lod
		it("keeps the own plot whole and thins other plots by distance and level", function()
			expect(Logic.PenCap(lod, 1, true, 900, 10)).toBe(10)
			expect(Logic.PenCap(lod, 3, false, 10, 10)).toBe(lod.penCap[3][1])
			expect(Logic.PenCap(lod, 3, false, lod.bands[3][1] + 1, 10)).toBe(lod.penCap[3][2])
			expect(Logic.PenCap(lod, 3, false, lod.bands[3][2] + 1, 10)).toBe(lod.penCap[3][3])
			expect(Logic.PenCap(lod, 1, false, 10, 10) <= Logic.PenCap(lod, 3, false, 10, 10)).toBe(true)
			expect(Logic.PenCap(lod, 3, false, 10, 4)).toBe(4) -- never above the own cap
		end)

		it("turns other plots' effects off with distance and animates far and hidden models less", function()
			expect(Logic.EffectsOn(lod, 1, true, 999)).toBe(true)
			expect(Logic.EffectsOn(lod, 3, false, lod.effectsDistance[3] - 1)).toBe(true)
			expect(Logic.EffectsOn(lod, 3, false, lod.effectsDistance[3] + 1)).toBe(false)
			expect(Logic.EffectsOn(lod, 1, false, 5)).toBe(false)
			expect(Logic.AnimInterval(lod, 3, true, 10, true)).toBe(0)
			expect(Logic.AnimInterval(lod, 3, true, lod.animPause + 1, true)).toBe(nil)
			expect(Logic.AnimInterval(lod, 3, true, 10, false)).toBe(lod.animInterval.offScreen)
			local far = Logic.AnimInterval(lod, 3, false, lod.animFar + 1, true)
			local ownSame = Logic.AnimInterval(lod, 3, true, lod.animFar + 1, true)
			expect(far > ownSame).toBe(true)
			expect(Logic.AnimInterval(lod, 1, true, 10, true) > 0).toBe(true)
		end)
	end)

	describe("Logic/ParticleBudget", function()
		local cfg = { minScale = 0.5, dropOrder = { "rarity", "mutation", "aura" } }

		it("leaves everything at full rate under budget", function()
			local plan = Budget.Plan({ aura = 50, rarity = 30 }, 20, 200, cfg)
			expect(plan.aura).toBe(1)
			expect(plan.rarity).toBe(1)
			expect(Budget.Live(10, 1, 3)).toBe(20)
		end)

		it("scales every kind together, then drops the lowest-priority kinds first", function()
			local plan = Budget.Plan({ aura = 100, rarity = 100 }, 0, 150, cfg)
			expect(plan.aura).toBe(0.75)
			expect(plan.rarity).toBe(0.75)
			plan = Budget.Plan({ aura = 100, rarity = 100, mutation = 100 }, 0, 100, cfg)
			expect(plan.rarity).toBe(0)
			expect(plan.mutation).toBe(0.5)
			expect(plan.aura).toBe(0.5)
			plan = Budget.Plan({ aura = 100, rarity = 100, mutation = 100, landmark = 100 }, 0, 60, cfg)
			expect(plan.rarity).toBe(0)
			expect(plan.mutation).toBe(0)
			expect(plan.aura).toBe(0)
			expect(plan.landmark).toBe(0.6) -- kinds outside dropOrder go last
		end)

		it("never cuts protected particles and restores kinds when demand falls", function()
			local plan = Budget.Plan({ aura = 100 }, 500, 400, cfg)
			expect(plan.aura).toBe(0)
			plan = Budget.Plan({ aura = 100 }, 100, 400, cfg)
			expect(plan.aura).toBe(1)
		end)

		it("caps bursts per second", function()
			local window = { start = -math.huge, used = 0 }
			expect(Budget.Allow(window, 0, 40, 60)).toBe(40)
			expect(Budget.Allow(window, 0.5, 40, 60)).toBe(20)
			expect(Budget.Allow(window, 0.9, 5, 60)).toBe(0)
			expect(Budget.Allow(window, 1.2, 5, 60)).toBe(5)
		end)
	end)

	describe("the client", function()
		local function boot()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local Quality = c:require(c.clientFolder.Visuals.Quality)
			return h, p, c, Quality
		end

		it("cycles the Graphics choice Auto -> High -> Low -> Auto on the Settings screen", function()
			local _, _, c, Quality = boot()
			expect(Quality.Choice()).toBe("auto")
			c:Open("Settings")
			c:Click(c:Button("Auto · High"))
			c:Advance(0.5)
			expect(c:Store("profile.Settings").graphics).toBe("high")
			expect(Quality.Choice()).toBe("high")
			c:Click(c:Button("High"))
			c:Advance(0.5)
			expect(c:Store("profile.Settings").lowGraphics).toBe(true)
			expect(Quality.IsLow()).toBe(true)
			local Anim = c:require(c.clientFolder.UI.Anim)
			expect(Anim.enabled).toBe(false) -- an explicit Low is also reduced motion
			c:Click(c:Button("Low"))
			c:Advance(0.5)
			expect(c:Store("profile.Settings").lowGraphics).toBe(false)
			expect(Quality.Choice()).toBe("auto")
			expect(Anim.enabled).toBe(true)
			expect(c:Button("Auto · High") ~= nil).toBe(true)
			expectClean(c)
		end)

		it("keeps a player who saved low graphics on Low", function()
			local _, _, c, Quality = boot()
			expect(c:Request("Settings.Set", { key = "lowGraphics", value = true })).toBe(true)
			c:Advance(0.5)
			expect(Quality.Choice()).toBe("low")
			expect(Quality.Level()).toBe(1)
			c:Open("Settings")
			expect(c:Button("Low") ~= nil).toBe(true)
			expectClean(c)
		end)

		it("steps Auto down on the harness's 10 fps frames but never touches reduced motion", function()
			local _, _, c, Quality = boot()
			local Anim = c:require(c.clientFolder.UI.Anim)
			c:Advance(Q.Auto.warmup - 2)
			expect(Quality.Level()).toBe(3)
			c:Advance(24)
			expect(Quality.AutoLevel()).toBe(1)
			expect(Quality.IsLow()).toBe(true)
			expect(Anim.enabled).toBe(true)
			c:Open("Settings")
			expect(c:Button("Auto · Low") ~= nil).toBe(true)
			expect(c:Request("Settings.SetGraphics", { graphics = "high" })).toBe(true)
			c:Advance(0.5)
			expect(Quality.Level()).toBe(3)
			expectClean(c)
		end)

		it("switches visuals with the level and leaks nothing", function()
			local _, _, c, Quality = boot()
			local lighting = c.world.game:GetService("Lighting")
			lighting.ClockTime = 12
			local rays = lighting:FindFirstChild("AmbienceSunRays")
			local dof = lighting:FindFirstChild("AmbienceDepthOfField")
			c:Advance(0.5)
			expect(rays.Enabled and dof.Enabled).toBe(true)
			local function count(): number
				return #c.world.workspace:GetDescendants() + #lighting:GetDescendants() + #c:Descendants()
			end
			local sizes = {}
			for round = 1, 3 do
				Quality.SetAuto(2)
				c:Advance(0.5)
				expect(dof.Enabled).toBe(false) -- depth of field is High only
				expect(rays.Enabled).toBe(true)
				Quality.SetAuto(1)
				c:Advance(0.5)
				expect(rays.Enabled or dof.Enabled).toBe(false)
				Quality.SetAuto(3)
				c:Advance(0.5)
				expect(rays.Enabled and dof.Enabled).toBe(true)
				sizes[round] = count()
			end
			expect(sizes[3]).toBe(sizes[2])
			expect(#Quality.Changed._handlers < 40).toBe(true)
			expectClean(c)
		end)

		it("holds live particles to the level's budget and restores them when under", function()
			local _, _, c, Quality = boot()
			local Vfx = c:require(c.clientFolder.Visuals.Vfx)
			Vfx.StopBudget() -- passes are run by hand below
			Quality.SetAuto(3)
			local budget = Q.Particles.budget[3]
			local models = {}
			local demand = 0
			local function liveOf(model): number
				local n = 0
				for _, e in model:GetDescendants() do
					if e:IsA("ParticleEmitter") and e.Enabled then
						n += e.Rate * (e.Lifetime.Min + e.Lifetime.Max) / 2
					end
				end
				return n
			end
			while demand <= budget * 2 and #models < 300 do
				local model = c.Instance.new("Model")
				local root = c.Instance.new("Part")
				root.Name = "Root"
				root.Size = Vector3.new(2, 3, 2)
				root.Anchored = true
				root.CFrame = CFrame.new((#models % 10) * 4, 2, 10 + math.floor(#models / 10) * 4)
				root.Parent = model
				model.PrimaryPart = root
				model:SetAttribute("Height", 3)
				model.Parent = c.world.workspace
				Vfx.AttachMonster(model, { elements = { "ember" }, muts = { "soaked" }, rarity = 1, archetype = "biped" })
				Vfx.SetOwned(model, false)
				table.insert(models, model)
				local live = liveOf(model)
				expect(live > 0).toBe(true)
				demand += live
			end
			local live = Vfx.BudgetPass()
			expect(live <= budget + 1).toBe(true)
			local after = 0
			for _, model in models do
				after += liveOf(model)
			end
			expect(after <= live + 0.5).toBe(true) -- live also counts the world's own effects
			expect(after < demand * 0.75).toBe(true)
			-- Remove all but one: that one is back at full rate.
			local keep = models[1]
			local full = demand / #models
			for i = 2, #models do
				models[i]:Destroy()
			end
			Vfx.BudgetPass()
			expect(math.abs(liveOf(keep) - full) < 0.01).toBe(true)
			-- Bursts: the per-second allowance.
			local burst = "hatch"
			expect(Presets.Bursts[burst] ~= nil).toBe(true)
			expect(Vfx.Burst(burst, Vector3.new(0, 5, 0)) > 0).toBe(true)
			for _ = 1, 60 do
				Vfx.Burst(burst, Vector3.new(0, 5, 0)) -- same frame: the allowance runs out
			end
			expect(Vfx.Burst(burst, Vector3.new(0, 5, 0))).toBe(0)
			c:Advance(1.1)
			expect(Vfx.Burst(burst, Vector3.new(0, 5, 0)) > 0).toBe(true)
			expectClean(c)
		end)
	end)
end
