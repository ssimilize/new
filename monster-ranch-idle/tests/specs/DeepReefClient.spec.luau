--[[
	DeepReefClient (glow-up DR): the Dive Dock, swimming and a swimmer mount, played through the
	real client (ClientHarness), like LightAndVoidClient does for the Sky Islands.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local CFrame = t.Roblox.CFrame
	local Config = t.Shared("Config")
	local Enum = t.Roblox.Enum

	local Cfg = Config.DeepReef
	-- Ranch Level 64 is above the 60 cap until 3.2's Level 70 cap opens (11 Mar 2028).
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

	local function inArea(pos): boolean
		local c = Cfg.Area.center
		local dx, dz = pos.X - c[1], pos.Z - c[3]
		return dx * dx + dz * dz <= (Cfg.Area.radius + 1) ^ 2 and pos.Y >= Cfg.Area.floorY - 1 and pos.Y <= Cfg.Area.surfaceY + 1
	end

	describe("Deep Reef client", function()
		it("dives from the Dive Dock, swims (ascend included), mounts a swimmer, and swims home", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = AFTER_CAP })
			local p = h:Join()
			levelTo(h, p, 64)
			local m = h:System("Monsters"):Create(p, {
				line = "finnip",
				rarity = 5,
				stage = 3,
				form = Config.Species.ById.finnip.forms[3][1].id,
			}, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(2)

			local dock = c.world.workspace:FindFirstChild("DiveDock")
			local area = c.world.workspace:FindFirstChild("Area")
			expect(dock ~= nil).toBe(true)
			expect(area ~= nil).toBe(true)

			local reef = c.kernel:GetController("DeepReef")
			local weather = c.kernel:GetController("Weather")
			local lighting = c.world.game:GetService("Lighting")
			local baseAmbient = lighting.Ambient

			expect(reef.IsInside()).toBe(false)

			-- Dive: teleported into the Area, the humanoid stops walking, the light changes.
			c:Trigger(dock.DivePad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			local root = c.character.PrimaryPart
			local humanoid = c.character:FindFirstChildOfClass("Humanoid")
			expect(inArea(root.Position)).toBe(true)
			expect(humanoid.PlatformStand).toBe(true)
			expect(reef.IsInside()).toBe(true)
			expect(weather.IsHeld()).toBe(true)
			expect(lighting.Ambient == baseAmbient).toBe(false)

			-- Ascend with Space held: the swim maths lift the character (no drowning, no timer).
			local startY = root.Position.Y
			c:_input(Enum.KeyCode.Space, Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
			c:Advance(1.5)
			expect(root.Position.Y > startY).toBe(true)
			c:_input(Enum.KeyCode.Space, Enum.UserInputState.End, Enum.UserInputType.Keyboard)
			c:Advance(0.2)

			-- Ride the Finnip: swimming mounted is a swim pose, not a walk.
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			c:Click(detail:FindFirstChild("Ride", true))
			c:Advance(0.5)
			expect(c.character:FindFirstChild("Mount") ~= nil).toBe(true)
			expect(Cfg.Swims("finnip")).toBe(true)

			local mounts = c.kernel:GetController("Mounts")
			c:_input(Enum.KeyCode.Space, Enum.UserInputState.Begin, Enum.UserInputType.Keyboard)
			c:Advance(1)
			c:_input(Enum.KeyCode.Space, Enum.UserInputState.End, Enum.UserInputType.Keyboard)
			expect(mounts:SpeedOf(p.UserId) > 0).toBe(true)
			expect(mounts:StateOf(p.UserId)).toBe("walk")

			-- Swim home: the Surface Bell's Return pad, back at the Dock with every override undone.
			c:Click(c.kernel.UI.Hud:FindFirstChild("DismountButton", true))
			c:Advance(0.5)
			c:Trigger(area.SurfaceBell.ReturnPad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(reef.IsInside()).toBe(false)
			expect(humanoid.PlatformStand).toBe(false)
			expect(weather.IsHeld()).toBe(false)
			expect(lighting.Ambient).toBe(baseAmbient)
			expect(inArea(root.Position)).toBe(false)

			-- The Reef Gate opens Expeditions on the "reef" region.
			c:Trigger(dock.DivePad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			c:Trigger(area.Gate.Portal:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Expeditions")
			expect(c:HasText("Reef", c:Screen("Expeditions"))).toBe(true)
			c:Close("Expeditions")
			c:Trigger(area.SurfaceBell.ReturnPad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expectClean(c)
		end)

		it("gives the light back when the swimmer is lost mid-dive, and a second dive stacks nothing", function()
			-- Found in Studio 2026-09-26: a swimmer flung off the floor died, the swim loop dropped
			-- `swimming` without the light, and the reef tint, fog and ambient stayed for good.
			local h = TestKernel.new({ systems = allSystems(), startTime = AFTER_CAP })
			local p = h:Join()
			levelTo(h, p, 64)
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local reef = c.kernel:GetController("DeepReef")
			local lighting = c.world.game:GetService("Lighting")
			local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
			local baseAmbient, baseOutdoor = lighting.Ambient, lighting.OutdoorAmbient
			local baseDensity = atmosphere and atmosphere.Density
			local function reefColors(): number
				local n = 0
				for _, child in lighting:GetChildren() do
					if child.Name == "ReefColor" then
						n += 1
					end
				end
				return n
			end

			reef.Dive()
			c:Advance(0.5)
			expect(reef.IsInside()).toBe(true)
			expect(reefColors()).toBe(1)
			local root = c.character.PrimaryPart
			expect(root.AssemblyLinearVelocity.Magnitude < 50).toBe(true)

			c.character:Destroy()
			c:Advance(0.5)
			expect(reefColors()).toBe(0)
			expect(lighting.Ambient).toBe(baseAmbient)
			expect(lighting.OutdoorAmbient).toBe(baseOutdoor)
			if atmosphere then
				expect(atmosphere.Density).toBe(baseDensity)
			end

			c:_spawnCharacter()
			c:Advance(0.5)
			reef.Dive()
			c:Advance(0.5)
			reef.Dive() -- a second Dive while inside changes nothing
			c:Advance(0.2)
			expect(reefColors()).toBe(1)
			reef.Surface()
			c:Advance(0.5)
			expect(reefColors()).toBe(0)
			expect(lighting.Ambient).toBe(baseAmbient)
			expectClean(c)
		end)

		it("stays shut below Ranch Level 64 and tells you so", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local dock = c.world.workspace:FindFirstChild("DiveDock")
			c:Trigger(dock.DivePad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			local reef = c.kernel:GetController("DeepReef")
			expect(reef.IsInside()).toBe(false)
			expect(c:HasText(string.format("Ranch Level %d", Config.Unlocks.Features.region_reef), c.kernel.UI.Feedback)).toBe(true)
			expectClean(c)
		end)
		it("keeps its life still and its bubbles off while the camera is far away, and wakes near it", function()
			local h = TestKernel.new({})
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local area = c.world.workspace:FindFirstChild("Area")
			local fish = area.Fish:FindFirstChildWhichIsA("BasePart")
			local bubbles = area.Vents:FindFirstChild("Bubbles", true)
			local camera = c.world.workspace.CurrentCamera
			local home = camera.CFrame
			-- The harness camera starts by the plaza, hundreds of studs from the reef (Visuals/Wake).
			local before = fish.CFrame
			c:Advance(1)
			expect(fish.CFrame == before).toBe(true)
			expect(bubbles.Enabled).toBe(false)

			local center = Cfg.Area.center
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
