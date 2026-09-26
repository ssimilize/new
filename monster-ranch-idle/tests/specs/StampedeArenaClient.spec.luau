--[[
	StampedeArenaClient (glow-up U): the Stampede live in the world, driven through the real client
	(ClientHarness): lobby (storm, "To the arena" joins and moves you there, your squad in its ring)
	→ fight (the giant, the Cheer button, bolts capped per second) → defeat (the fall, the loot
	fountain before the result popup) → everything cleaned up and Lighting left as it was.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	local Cfg = Config.Boss
	local A = Cfg.Arena
	local START = 1000000 * Cfg.Period

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

	local function fighter(h)
		local p = h:Join()
		h:Section(p, "Progression").level = 4
		local M = h:System("Monsters")
		local ids = {}
		for i = 1, 3 do
			local m = M:Create(p, { line = "cindlet", rarity = 2, stage = 3, traits = { 3, 4 }, hidden = 5 }, "test", true)
			m.lv = 20
			ids[i] = m.id
		end
		h:Call(p, "Expeditions.SetSquad", { ids = ids })
		return h:Rejoin(p) -- the next session loads the level, so the client sees the unlock
	end

	local function models(folder): number
		local n = 0
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				n += 1
			end
		end
		return n
	end

	describe("Stampede arena client", function()
		it("plays a lobby → fight → defeat cycle in the world and cleans up after it", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = START - 6 })
			local p = fighter(h)
			local c = ClientHarness.new(h, p)
			local Arena = c:require(c.clientFolder.Controllers.StampedeArena)
			local game = c.world.game
			local Workspace = game:GetService("Workspace")
			local Lighting = game:GetService("Lighting")
			local B = h:System("Boss")

			c:Advance(2)
			expect(B:State().state).toBe("lobby")
			local folder = Workspace:FindFirstChild("StampedeArena")
			expect(folder ~= nil).toBe(true)
			local live = folder:FindFirstChild("Live")
			-- The call: the storm rolls in over the whole server.
			expect(Lighting:FindFirstChild("StampedeStorm") ~= nil).toBe(true)
			expect(Arena.Stats().storm > 0).toBe(true)

			-- Far from the arena: "To the arena" joins and moves the character to its edge.
			local hud = c.kernel.UI.Hud
			c:Click(c:Button("To the arena", hud))
			c:Advance(1)
			expect(c:Store("session.Boss").joined).toBe(true)
			local root = c.character:FindFirstChild("HumanoidRootPart")
			local centre = Config.World.StampedeArena.center
			local dx, dz = root.Position.X - centre[1], root.Position.Z - centre[2]
			expect(math.sqrt(dx * dx + dz * dz) <= A.nearRange).toBe(true)
			expect(Arena.Stats().phase).toBe("gather")
			expect(Arena.Stats().squad).toBe(3)
			expect(models(live)).toBe(3)

			-- The fight goes live: the giant charges in, the Cheer button shows.
			c:Advance(4)
			expect(B:State().state).toBe("active")
			local stats = Arena.Stats()
			expect(stats.phase).toBe("fight")
			expect(stats.boss).toBe(true)
			expect(models(live)).toBe(4)
			expect(Arena:Live()).toBe(true)

			-- Taps count on the server; bolts are capped per second.
			local cheer = c:Button("Cheer!", hud)
			for _ = 1, 20 do
				c:Click(cheer)
			end
			expect(Arena.Stats().bolts).toBe(A.boltsPerSecond)
			c:Advance(1)
			expect(c:Store("session.Boss").cheer > 0).toBe(true)
			expect(Arena.Stats().bolts).toBe(0) -- landed and back in the pool

			-- Defeat: the fall, the loot fountain, then the result popup.
			B:State().hp = 1
			c:Advance(1.5)
			expect(B:State().state).toBe("idle")
			expect(Arena.Stats().phase).toBe("fall")
			expect(c:HasText("Stampede over!", c.kernel.UI.Top)).toBe(false) -- waits for the fountain
			c:Advance(A.fallSeconds + A.fountainSeconds + 0.5)
			expect(c:HasText("Stampede over!", c.kernel.UI.Top)).toBe(true)
			c:Click(c:Button("Nice!", c.kernel.UI.Top))

			-- Everything leaves; the storm fades out and its effect is removed.
			c:Advance(A.leaveSeconds + A.storm.fade + 1)
			stats = Arena.Stats()
			expect(stats.phase).toBe("off")
			expect(stats.boss).toBe(false)
			expect(stats.squad).toBe(0)
			expect(models(live)).toBe(0)
			expect(Lighting:FindFirstChild("StampedeStorm")).toBeNil()
			expect(Arena:Live()).toBe(false)
			expectClean(c)
		end)

		it("shows the result popup straight away for a player away from the arena", function()
			local h = TestKernel.new({ systems = allSystems(), startTime = START - 6 })
			local p = fighter(h)
			local c = ClientHarness.new(h, p)
			local Arena = c:require(c.clientFolder.Controllers.StampedeArena)
			local B = h:System("Boss")
			c:Advance(2)
			c:Request("Boss.Join")
			-- Far away (past viewRange): nothing is built and nobody is dragged in.
			c.character:PivotTo(c.character:GetPivot() + t.Roblox.Vector3.new(-(A.viewRange + 200), 0, 0))
			c:Advance(5)
			expect(B:State().state).toBe("active")
			expect(Arena.Stats().boss).toBe(false)
			expect(Arena.Stats().squad).toBe(0)
			B:State().hp = 1
			c:Advance(1.5)
			expect(c:HasText("Stampede over!", c.kernel.UI.Top)).toBe(true)
			expectClean(c)
		end)
	end)
end
