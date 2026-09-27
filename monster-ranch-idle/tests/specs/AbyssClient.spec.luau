--[[
	AbyssClient (R2-ABYSS): the Chasm descent inside the Deep Reef's own Area, the darker
	AbyssArea, the Ascent Bell home and the Abyss Gate, played through the real client
	(ClientHarness), like DeepReefClient does for the Deep Reef itself.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local CFrame = t.Roblox.CFrame
	local Config = t.Shared("Config")

	local Reef = Config.DeepReef
	local Abyss = Config.Abyss
	-- Ranch Level 70 is above the 60 cap until 3.2's Level 70 cap opens (11 Mar 2028).
	local AFTER_CAP = Config.Unlocks.LevelCaps[2].from + 3600

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

	local function inAbyssArea(pos): boolean
		local c = Abyss.Area.center
		local dx, dz = pos.X - c[1], pos.Z - c[3]
		return dx * dx + dz * dz <= (Abyss.Area.radius + 1) ^ 2 and pos.Y >= Abyss.Area.floorY - 1 and pos.Y <= Abyss.Area.surfaceY + 1
	end

	local function inReefArea(pos): boolean
		local c = Reef.Area.center
		local dx, dz = pos.X - c[1], pos.Z - c[3]
		return dx * dx + dz * dz <= (Reef.Area.radius + 1) ^ 2 and pos.Y >= Reef.Area.floorY - 1 and pos.Y <= Reef.Area.surfaceY + 1
	end

	describe("Sunken Abyss client", function()
		it("dives deeper from inside the Deep Reef, stacks a darker light, and swims safely home", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = AFTER_CAP })
			local p = h:Join()
			levelTo(h, p, 70)
			local c = ClientHarness.new(h, p)
			c:Advance(2)

			local dock = c.world.workspace:FindFirstChild("DiveDock")
			local reefArea = c.world.workspace:FindFirstChild("Area")
			local abyssArea = c.world.workspace:FindFirstChild("AbyssArea")
			expect(dock ~= nil).toBe(true)
			expect(reefArea ~= nil).toBe(true)
			expect(abyssArea ~= nil).toBe(true) -- built once the Deep Reef's own Area exists, unlock or not

			local reef = c.kernel:GetController("DeepReef")
			local abyss = c.kernel:GetController("Abyss")
			local lighting = c.world.game:GetService("Lighting")
			local baseAmbient = lighting.Ambient

			-- Dive into the Deep Reef first: the Chasm only works while already swimming there.
			c:Trigger(dock.DivePad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(reef.IsInside()).toBe(true)
			expect(abyss.IsDescended()).toBe(false)

			local chasm = reefArea:FindFirstChild("Chasm")
			expect(chasm ~= nil).toBe(true)
			-- On the reef's sand, under its surface, where a swimmer can reach it (Studio 2026-09-27:
			-- it sat 158 studs up, above the water, measured off the Floor cylinder's diameter).
			local R = Config.DeepReef.Area
			local padY = chasm.DivePad.Position.Y
			expect(padY >= R.floorY - 2 and padY < R.surfaceY).toBe(true)
			c:Trigger(chasm.DivePad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)

			local root = c.character.PrimaryPart
			expect(abyss.IsDescended()).toBe(true)
			expect(inAbyssArea(root.Position)).toBe(true)
			expect(lighting:FindFirstChild("ReefColor") ~= nil).toBe(true) -- the Reef's own light kept running underneath
			expect(lighting:FindFirstChild("AbyssColor") ~= nil).toBe(true) -- stacked on top: darker still

			-- The Abyss Gate opens Expeditions on the "abyss" region.
			c:Trigger(abyssArea.Gate.Portal:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Expeditions")
			expect(c:HasText("Abyss", c:Screen("Expeditions"))).toBe(true)
			c:Close("Expeditions")

			-- The safe way back up: the Ascent Bell hands the swim back to the Deep Reef.
			c:Trigger(abyssArea.AscentBell.ReturnPad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(abyss.IsDescended()).toBe(false)
			expect(reef.IsInside()).toBe(true)
			expect(inReefArea(root.Position)).toBe(true)
			expect(lighting:FindFirstChild("AbyssColor") ~= nil).toBe(false)
			expect(lighting:FindFirstChild("ReefColor") ~= nil).toBe(true)

			-- Swim all the way home: the Surface Bell, every override undone.
			c:Trigger(reefArea.SurfaceBell.ReturnPad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(reef.IsInside()).toBe(false)
			expect(lighting.Ambient).toBe(baseAmbient)
			expectClean(c)
		end)

		it("only opens the Chasm once Ranch Level Config.Abyss.Unlock is reached", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = AFTER_CAP })
			local p = h:Join()
			levelTo(h, p, 64) -- the Deep Reef, but not the Sunken Abyss (70)
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local dock = c.world.workspace:FindFirstChild("DiveDock")
			local reefArea = c.world.workspace:FindFirstChild("Area")
			c:Trigger(dock.DivePad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			local abyss = c.kernel:GetController("Abyss")
			c:Trigger(reefArea.Chasm.DivePad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.2)
			expect(abyss.IsDescended()).toBe(false)
			c:Trigger(reefArea.SurfaceBell.ReturnPad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.2)
			expectClean(c)
		end)
		it("keeps its life still and its bubbles off while the camera is far away, and wakes near it", function()
			local h = TestKernel.new({})
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local area = c.world.workspace:FindFirstChild("AbyssArea")
			local fish = area.Fish:FindFirstChildWhichIsA("BasePart")
			local bubbles = area.Vents:FindFirstChild("Bubbles", true)
			local camera = c.world.workspace.CurrentCamera
			local home = camera.CFrame
			-- The harness camera starts by the plaza, hundreds of studs from the abyss (Visuals/Wake).
			local before = fish.CFrame
			c:Advance(1)
			expect(fish.CFrame == before).toBe(true)
			expect(bubbles.Enabled).toBe(false)

			local center = Abyss.Area.center
			camera.CFrame = CFrame.new(center[1], center[2] + 20, center[3])
			c:Advance(1)
			expect(fish.CFrame == before).toBe(false)
			expect(bubbles.Enabled).toBe(true)

			camera.CFrame = home
			c:Advance(1)
			local asleep = fish.CFrame
			c:Advance(1)
			expect(fish.CFrame == asleep).toBe(true)
			expect(bubbles.Enabled).toBe(false)
			expectClean(c)
		end)
	end)
end
