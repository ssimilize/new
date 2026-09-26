--[[
	PenLifeClient (glow-up S, living pens): the real client (ClientHarness) with a ranch of monsters
	whose traits differ. World drives Visuals/PenBrain; the checks read the animator states the
	monsters end up in and PenBrain.Describe / Stats: greeting the owner at the fence, the night pile
	(night owls stay up), weather reactions (shake, shiver, shelter at a PenSpot), a gather after an
	evolve, low graphics (no chase, essential bubbles only), pen bounds and separation, no leaks.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")
	local WeatherRoll = t.Shared("Logic.WeatherRoll")
	local Vector3 = t.Roblox.Vector3
	local CFrame = t.Roblox.CFrame

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

	local TRAITS = {
		owl = { "night_owl", "tough_hide" },
		glutton = { "glutton", "hearty" },
		cheerful = { "cheerful", "swift" },
		show = { "show_off", "brawny" },
	}

	local function ownPlot(c, p): number
		for i, data in c:Store("global.Plots") or {} do
			if type(data) == "table" and data.userId == p.UserId then
				return i
			end
		end
		error("no own plot")
	end

	-- Pen 1's centre and half extents in world space (the Config fallback World uses in tests).
	local function penArea(index: number)
		local plot = Config.World.Plots[index]
		local frame = CFrame.new(plot.center[1], Config.World.GroundY, plot.center[3])
			* CFrame.Angles(0, math.rad((plot.facing or 0) - 90), 0)
		local o = Config.World.PenOffsets[1]
		return frame * CFrame.new(o[1], 0.4, o[3]), Config.World.PenSize[1] / 2, Config.World.PenSize[2] / 2
	end

	-- Boots a ranch with four monsters in pen 1 and the camera looking at the plot.
	local function boot()
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		local c = ClientHarness.new(h, p)
		c:Advance(1)
		local night, endsAt = WeatherRoll.Phase(h.adapters.Clock.Unix())
		if night then
			h.adapters.setTime(endsAt + 1) -- start in daylight
		end
		h:System("Weather"):Trigger("clear", "test") -- and in clear weather, whatever the roll was
		c:Advance(1.2)
		-- Hold every pen still (the perf knob) until all four are in, so they arrive together.
		local brain = c:require(c.clientFolder.Visuals.PenBrain)
		local rng = t.Shared("Logic.Rng").new(20260926) -- the same pen life on every run
		brain.SetRandom(function()
			return rng:Next()
		end)
		brain.SetThinkRate(nil, 0)
		local Monsters = h:System("Monsters")
		local ids = {}
		for name, keys in TRAITS do
			local traitIds = {}
			for _, key in keys do
				table.insert(traitIds, Config.Traits.ByKey[key].id)
			end
			local m = Monsters:Create(p, { line = "cindlet", rarity = 1, traits = traitIds, hidden = 5, variant = 0 }, "hatch", true)
			-- Through the client: a server-side h:Call would take the profile patches with its response.
			c:Advance(0.1)
			local ok = c:Request("Ranch.Assign", { id = m.id, pen = 1 })
			expect(ok).toBe(true)
			c:Advance(1)
			ids[name] = m.id
		end
		local index = ownPlot(c, p)
		local target = penArea(index).Position
		c.world.workspace.CurrentCamera.CFrame = CFrame.lookAt(target + Vector3.new(0, 26, 30), target)
		c:Advance(2)
		brain.SetThinkRate(nil, 1)
		c:Advance(0.4)
		local world = c.kernel:GetController("World")
		return h, p, c, { ids = ids, brain = brain, world = world, target = target, index = index }
	end

	-- { name = { model, animator } } for the four test monsters, by their traits.
	local function monsters(env)
		local found = {}
		for _, item in env.world:OwnMonstersNear(env.target, 400) do
			local info = env.brain.Describe(item.model)
			if info then
				for name, keys in TRAITS do
					if table.find(info.traits, keys[1]) then
						found[name] = item
					end
				end
			end
		end
		return found
	end

	-- Advances `seconds` in 0.2 s steps, collecting every animator state each monster shows.
	local function watch(c, env, seconds: number)
		local seen = {}
		local list = monsters(env)
		for name in list do
			seen[name] = {}
		end
		local steps = math.floor(seconds / 0.2 + 0.5)
		for _ = 1, steps do
			c:Advance(0.2)
			for name, item in list do
				seen[name][item.animator:GetState()] = true
			end
		end
		return seen, list
	end

	local function stat(env, key: string): number
		return env.brain.Stats()[key] or 0
	end

	local function setNight(h, c, on: boolean)
		local now = h.adapters.Clock.Unix()
		local night, endsAt = WeatherRoll.Phase(now)
		if night ~= on then
			h.adapters.setTime(endsAt + 1)
		end
		c:Advance(1.2)
		expect(c:Store("global.Weather").night).toBe(on)
	end

	describe("Living pens", function()
		it("gives own monsters their traits, greets the owner at the fence and keeps them apart inside the pen", function()
			local _, _, c, env = boot()
			local list = monsters(env)
			for name, keys in TRAITS do
				expect(list[name] ~= nil).toBe(true)
				local info = env.brain.Describe(list[name].model)
				for _, key in keys do
					expect(table.find(info.traits, key) ~= nil).toBe(true)
				end
			end
			-- The owner arrived with the monsters in the pen: every one of them runs to the fence.
			expect(stat(env, "greet") >= 4).toBe(true)
			local seen = watch(c, env, 8)
			for name in TRAITS do
				expect(seen[name].happy == true).toBe(true)
			end
			expect(stat(env, "bubble") >= 1).toBe(true)
			-- Some daytime life after that, inside the floor and not on top of each other.
			c:Advance(10)
			local area, hx, hz = penArea(env.index)
			local positions = {}
			for _, item in monsters(env) do
				local p = area:PointToObjectSpace(item.animator:GetPosition())
				expect(math.abs(p.X) <= hx and math.abs(p.Z) <= hz).toBe(true)
				table.insert(positions, item.animator:GetPosition())
			end
			local overlaps = 0
			for i = 1, #positions do
				for j = i + 1, #positions do
					if (positions[i] - positions[j]).Magnitude < 0.5 then
						overlaps += 1
					end
				end
			end
			expect(overlaps).toBe(0)
			-- A monster sent to the barn leaves the pen and the brain lets go of it.
			local held = env.brain.Count()
			expect(held >= 4).toBe(true)
			expect(c:Request("Ranch.Assign", { id = env.ids.owl, pen = 0 })).toBe(true)
			c:Advance(7)
			expect(monsters(env).owl).toBe(nil)
			expect(env.brain.Count()).toBe(held - 1)
			expectClean(c)
		end)

		it("naps in a pile at night while the night owl stays up, and wakes at dawn", function()
			local h, _, c, env = boot()
			c:Advance(6)
			setNight(h, c, true)
			c:Advance(22)
			local list = monsters(env)
			local sleepers = {}
			for name, item in list do
				local info = env.brain.Describe(item.model)
				if name == "owl" then
					expect(info.action ~= "sleep").toBe(true)
					expect(item.animator:GetState() ~= "sleep").toBe(true)
				else
					expect(info.action).toBe("sleep")
					expect(item.animator:GetState()).toBe("sleep")
					table.insert(sleepers, item.animator:GetPosition())
				end
			end
			-- A pile: the sleepers lie close together.
			for i = 1, #sleepers do
				for j = i + 1, #sleepers do
					local d = (sleepers[i] - sleepers[j]).Magnitude
					expect(d > 0.5 and d < 10).toBe(true)
				end
			end
			setNight(h, c, false)
			c:Advance(8)
			for _, item in monsters(env) do
				expect(env.brain.Describe(item.model).action ~= "sleep").toBe(true)
			end
			expectClean(c)
		end)

		it("shakes off the rain, shivers in the snow and shelters from a storm", function()
			local h, _, c, env = boot()
			c:Advance(6)
			local Weather = h:System("Weather")
			Weather:Trigger("clear", "test")
			c:Advance(1.2)
			expect(c:Store("global.Weather").id).toBe("clear")
			local shakes = stat(env, "shake")
			Weather:Trigger("rain", "test", 120)
			local seen = watch(c, env, 5)
			expect(stat(env, "shake") >= shakes + 3).toBe(true)
			expect(seen.glutton.shake == true).toBe(true)
			expect(seen.owl.shake == nil).toBe(true) -- tough hide

			Weather:Trigger("snow", "test", 120)
			seen = watch(c, env, 16)
			local shivered = 0
			for name, states in seen do
				if states.shiver then
					shivered += 1
					expect(name ~= "owl").toBe(true)
				end
			end
			expect(shivered >= 1).toBe(true)

			-- A shelter spot another packet's pen props would carry.
			local area = penArea(env.index)
			local hut = c.Instance.new("Part")
			hut.Name = "Hut"
			hut.Anchored = true
			hut.Size = Vector3.new(4, 4, 4)
			hut.CFrame = area * CFrame.new(-8, 2, 6)
			hut:SetAttribute("PenSpot", "shelter")
			hut.Parent = c.world.workspace.WorldClient:FindFirstChild("Plot" .. env.index)
			c:Advance(7) -- the next spot rescan
			Weather:Trigger("thunderstorm", "test", 120)
			-- Everyone but the tough one heads for the hut at some point; nobody ends up inside it.
			local list = monsters(env)
			local closest = {}
			for _ = 1, 90 do
				c:Advance(0.2)
				for name, item in list do
					local d = ((item.animator:GetPosition() - hut.Position) * Vector3.new(1, 0, 1)).Magnitude
					closest[name] = math.min(closest[name] or math.huge, d)
				end
			end
			local near = 0
			for name, d in closest do
				if name ~= "owl" and d < 8 then
					near += 1
				end
			end
			for _, item in list do
				local d = ((item.animator:GetPosition() - hut.Position) * Vector3.new(1, 0, 1)).Magnitude
				expect(d > 2).toBe(true)
			end
			expect(near >= 2).toBe(true)
			expect(stat(env, "shelter") >= 2).toBe(true)
			expectClean(c)
		end)

		it("gathers the pen round a monster that evolved", function()
			local h, p, c, env = boot()
			c:Advance(6)
			local before = stat(env, "gather")
			h.kernel.Net:Fire(p, "Monsters.Evolved", { id = env.ids.show, toForm = "x" })
			c:Advance(1)
			-- The gather is a Celebrate moment: it waits under the evolution popup.
			expect(stat(env, "gather")).toBe(before)
			local yay = c:Button("Yay!", c.kernel.UI.Top)
			expect(yay ~= nil).toBe(true)
			c:Click(yay)
			c:Advance(3.5)
			expect(stat(env, "gather") >= before + 3).toBe(true)
			-- They come over: the closest each one gets to the evolved monster in the next seconds.
			local list = monsters(env)
			local closest = {}
			for _ = 1, 40 do
				c:Advance(0.2)
				local focal = list.show.animator:GetPosition()
				for name, item in list do
					local d = (item.animator:GetPosition() - focal).Magnitude
					closest[name] = math.min(closest[name] or math.huge, d)
				end
			end
			local close = 0
			for name, d in closest do
				if name ~= "show" and d < 9 then
					close += 1
				end
			end
			expect(close >= 2).toBe(true)
			expectClean(c)
		end)

		it("plays no chase and only essential bubbles on low graphics, and thinks less when told", function()
			local _, _, c, env = boot()
			c:Advance(8)
			local ok = c:Request("Settings.Set", { key = "lowGraphics", value = true })
			expect(ok).toBe(true)
			local chases = stat(env, "chase")
			local maxBubbles = 0
			local Bubbles = c:require(c.clientFolder.Visuals.MoodBubbles)
			for _ = 1, 60 do
				c:Advance(0.5)
				maxBubbles = math.max(maxBubbles, Bubbles.Count())
			end
			expect(stat(env, "chase")).toBe(chases)
			expect(maxBubbles <= t.Shared("Config.PenLife").Bubbles.maxLow).toBe(true)
			-- The perf knob: a frozen plot starts nothing new.
			env.brain.SetThinkRate(env.index, 0)
			c:Advance(1)
			local stats = env.brain.Stats()
			c:Advance(12)
			local after = env.brain.Stats()
			for key, value in after do
				expect(value).toBe(stats[key] or 0)
			end
			env.brain.SetThinkRate(nil, 1)
			env.brain.SetThinkRate(env.index, 1)
			c:Advance(8)
			local moved = 0
			for key, value in env.brain.Stats() do
				if value ~= (after[key] or 0) then
					moved += 1
				end
			end
			expect(moved >= 1).toBe(true)
			expectClean(c)
		end)
	end)
end
