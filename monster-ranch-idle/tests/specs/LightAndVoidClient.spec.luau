--[[
	LightAndVoidClient (update 2.0): the Sky Islands (pads, crystals, gate), Riding and the
	Surf Shack, played through the real client (ClientHarness).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

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

	describe("Sky Islands client", function()
		it("flies up from the launch pad, collects a crystal and opens the Sky Gate", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 45)
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local sky = c.world.workspace.World.Sky
			expect(#sky.Islands:GetChildren()).toBe(#Config.World.Sky.islands)
			expect(#sky.Bridges:GetChildren()).toBe(#Config.World.Sky.bridges)

			c:Trigger(sky.LaunchPad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			local root = c.character.PrimaryPart
			expect(root.Position.Y > 150).toBe(true)

			local crystals = c.world.workspace.SkyCrystals
			expect(#crystals:GetChildren()).toBe(#Config.SkyIslands.Crystals)
			local spot = Config.SkyIslands.Crystals[1]
			p.Character = { HumanoidRootPart = { Position = { X = spot[1], Y = spot[2] + 2, Z = spot[3] } } }
			c:Trigger(crystals.Crystal1:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(1)
			expect(h:Section(p, "SkyIslands").total).toBe(1)
			expect(crystals:FindFirstChild("Crystal1")).toBeNil()

			c:Trigger(sky.Gate.Portal:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBe("Expeditions")
			expect(c:HasText("Sky Islands", c:Screen("Expeditions"))).toBe(true)
			c:Close("Expeditions")

			c:Trigger(sky.ReturnPad:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(root.Position.Y < 20).toBe(true)
			expectClean(c)
		end)
	end)

	describe("Riding client", function()
		it("rides from the monster screen and gets off from the HUD", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 16)
			local m = h:System("Monsters"):Create(p, { line = "zappip", rarity = 5, stage = 3 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local detail = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.5)
			c:Click(detail:FindFirstChild("Ride", true))
			c:Advance(1)
			expect(c.kernel.Router:Current()).toBeNil()
			local mount = c.character:FindFirstChild("Mount")
			expect(mount ~= nil).toBe(true)
			local humanoid = c.character:FindFirstChildOfClass("Humanoid")
			expect(humanoid.WalkSpeed).toBe(Config.Riding.SpeedFor(m))
			local button = c.kernel.UI.Hud:FindFirstChild("DismountButton", true)
			expect(c:IsShown(button)).toBe(true)
			c:Click(button)
			c:Advance(1)
			expect(c.character:FindFirstChild("Mount")).toBeNil()
			expect(humanoid.WalkSpeed).toBe(Config.Riding.WalkSpeed)
			expect(c:IsShown(button)).toBe(false)
			expectClean(c)
		end)
	end)

	describe("Surf Shack client", function()
		it("surfs a whole run and shows the server's score", function()
			local SPLASH = Config.Events.ById.summersplash
			local h = TestKernel.new({ systems = allSystems(), startTime = SPLASH.startsAt + 3600 })
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Surf")
			c:Advance(0.5)
			expect(c:HasText("Best score: 0", screen)).toBe(true)
			c:Click(screen:FindFirstChild("StartSurf", true))
			c:Advance(0.2)
			expect(screen:FindFirstChild("Waves", true) ~= nil).toBe(true)
			-- Weave between the lanes for the whole run.
			for i = 1, 60 do
				local side = if i % 3 == 0 then "Left" else "Right"
				local b = screen:FindFirstChild(side, true)
				if not b then
					break
				end
				c:Click(b)
				c:Advance(0.8, 0.1)
			end
			c:Advance(3, 0.1)
			expect(screen:FindFirstChild("SurfResult", true) ~= nil).toBe(true)
			expect(h:Section(p, "Surf").runs).toBe(1)
			expect(c:HasText("Score", screen)).toBe(true)
			c:Click(screen:FindFirstChild("SurfDone", true))
			c:Advance(0.5)
			expect(c:HasText("Runs: 1", screen)).toBe(true)
			c:Close("Surf")
			expectClean(c)
		end)
	end)
end
