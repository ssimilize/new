--[[
	R2-STREAMING: the five controllers the survey flagged (Interaction, Leaderboards, Showtime,
	Community, SkyIslands) played through the real client (ClientHarness) with the world part each
	depends on missing at Start, arriving late, and (once) streaming out and back in as a fresh
	Instance - the shape StreamingEnabled actually gives a client. Every one still works with no
	console problems and without wiring a second, duplicate handler onto the new instance.

	Also: a far teleport (SkyIslands, the Stampede Arena) asks the server to pre-stream the
	destination (World.StreamAround) before the client moves its own character there.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Config = t.Shared("Config")

	-- Unlike ShowtimeClient.spec, this file includes "World": World.StreamAround must be
	-- registered (Systems/World.Init does that before its Workspace check, so it works even
	-- though the server test kernel has no Workspace adapter).
	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			table.insert(list, name)
		end
		return list
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function countPrompts(root): number
		local n = 0
		for _, d in root:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				n += 1
			end
		end
		return n
	end

	local function countOfClass(root, className: string): number
		local n = 0
		for _, d in root:GetChildren() do
			if d:IsA(className) then
				n += 1
			end
		end
		return n
	end

	describe("Leaderboards: the board's Body", function()
		it("builds nothing until the Body streams in, and rebuilds once after it cycles out and back in", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p, { lateWorldParts = { "Hub.Buildings.leaderboard.Body" } })
			c:Advance(1)
			local building = c.world.workspace.World.Hub.Buildings.leaderboard
			expect(building:FindFirstChild("BoardGui", true)).toBeNil()

			c:StreamIn("Hub.Buildings.leaderboard.Body")
			c:Advance(1)
			local body1 = building.Body
			expect(body1:FindFirstChild("BoardGui") ~= nil).toBe(true)
			expect(countOfClass(body1, "SurfaceGui")).toBe(1)

			c:StreamOut("Hub.Buildings.leaderboard.Body")
			c:Advance(9) -- past one cycle: proves the old board's loop actually stopped, not two racing
			local body2 = building.Body
			expect(body2 ~= body1).toBe(true)
			expect(body2:FindFirstChild("BoardGui") ~= nil).toBe(true)
			expect(countOfClass(body2, "SurfaceGui")).toBe(1) -- exactly one board, no leftover from body1
			expectClean(c)
		end)
	end)

	describe("Showtime: the stage's Body", function()
		it("only shows the runway monster once the stage streams in, and again after it cycles", function()
			local C = Config.Contests
			local show = 2900001
			local h = TestKernel.new({ systems = allSystems(), startTime = show * C.CycleSeconds + 3 })
			local a = h:Join(8801, "Ava")
			local P = h:System("Progression")
			while P:GetLevel(a) < 8 do
				P:AddXP(a, Config.Unlocks.XPToNext(P:GetLevel(a)) - h:Section(a, "Progression").xp, "test")
			end
			local ma = h:System("Monsters"):Create(a, { line = "cindlet", rarity = 2, stage = 3 }, "test", true)
			local c = ClientHarness.new(h, a, { lateWorldParts = { "Hub.Buildings.showStage.Body" } })
			c:Advance(1)

			local screen = c:Open("Contests")
			c:Advance(1)
			c:Click(screen:FindFirstChild("EnterButton", true))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Monsters")
			local cell = c:Screen("Monsters"):FindFirstChild(ma.id, true)
			c:Click(cell:FindFirstChild("Tap"))
			c:Advance(1)

			c:Advance(C.EntrySeconds)
			expect(h:Client(a).global.Contests.state).toBe("runway")
			local stage = c.world.workspace.World.Hub.Buildings.showStage
			expect(stage:FindFirstChild("RunwayMonster", true)).toBeNil() -- the stage's Body has not streamed in

			c:StreamIn("Hub.Buildings.showStage.Body")
			c:Advance(0.5)
			expect(stage:FindFirstChild("RunwayMonster") ~= nil).toBe(true)

			c:StreamOut("Hub.Buildings.showStage.Body")
			c:Advance(0.5)
			-- global.Contests did not change, but the walker follows the new Body once it streams
			-- back in (the stale stageBody reference is dropped by AncestryChanged, not reused).
			expect(stage:FindFirstChild("RunwayMonster") ~= nil).toBe(true)
			c:Close("Contests")
			expectClean(c)
		end)
	end)

	describe("Community: the VIP balcony pad", function()
		it("only prompts once the pad streams in, and again (no duplicate) after it cycles", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p, { lateWorldParts = { "Hub.VipPad" } })
			c:Advance(1)
			local hub = c.world.workspace.World.Hub
			expect(hub:FindFirstChild("VipPad")).toBeNil()

			c:StreamIn("Hub.VipPad")
			c:Advance(1)
			local pad1 = hub.VipPad
			expect(countPrompts(pad1)).toBe(1)
			c:Trigger(pad1:FindFirstChildOfClass("ProximityPrompt"))
			expect(table.find(c.requests, "Community.Balcony") ~= nil).toBe(true)

			c:StreamOut("Hub.VipPad")
			c:Advance(1)
			local pad2 = hub.VipPad
			expect(pad2 ~= pad1).toBe(true)
			expect(countPrompts(pad2)).toBe(1) -- not 2: the rescan does not double-prompt
			expectClean(c)
		end)
	end)

	describe("SkyIslands: the Sky folder's pads", function()
		it("only prompts once ReturnPad streams in, pre-streams the destination, and survives a cycle", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p, { lateWorldParts = { "Sky.ReturnPad" } })
			c:Advance(1)
			local sky = c.world.workspace.World.Sky
			expect(sky:FindFirstChild("ReturnPad")).toBeNil()

			c:StreamIn("Sky.ReturnPad")
			c:Advance(1)
			local pad1 = sky.ReturnPad
			expect(countPrompts(pad1)).toBe(1)
			c:Trigger(pad1:FindFirstChildOfClass("ProximityPrompt"))
			expect(table.find(c.requests, "World.StreamAround") ~= nil).toBe(true)
			expect(#h.adapters.log.streamAround).toBe(1)
			local launch = Config.World.Sky.launchPad
			expect(h.adapters.log.streamAround[1].position.x).toBe(launch[1])

			c:StreamOut("Sky.ReturnPad")
			c:Advance(1)
			local pad2 = sky.ReturnPad
			expect(pad2 ~= pad1).toBe(true)
			expect(countPrompts(pad2)).toBe(1)
			c:Trigger(pad2:FindFirstChildOfClass("ProximityPrompt"))
			expect(#h.adapters.log.streamAround).toBe(2) -- one more request, not zero and not a double-fire
			expectClean(c)
		end)
	end)

	describe("Interaction: a hub building's prompt", function()
		it("only opens its screen once the building streams in, and again (no duplicate) after it cycles", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local c = ClientHarness.new(h, p, { lateWorldParts = { "Hub.Buildings.market" } })
			c:Advance(1)
			local buildings = c.world.workspace.World.Hub.Buildings
			expect(buildings:FindFirstChild("market")).toBeNil()

			c:StreamIn("Hub.Buildings.market")
			c:Advance(1)
			local model1 = buildings.market
			expect(countPrompts(model1)).toBe(1)
			c:Trigger(model1.Door:FindFirstChildOfClass("Attachment"):FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Market")
			c:Close("Market")

			c:StreamOut("Hub.Buildings.market")
			c:Advance(1)
			local model2 = buildings.market
			expect(model2 ~= model1).toBe(true)
			expect(countPrompts(model2)).toBe(1) -- rebuilt clean, not stacked onto the old count
			c:Trigger(model2.Door:FindFirstChildOfClass("Attachment"):FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Market")
			c:Close("Market")
			expectClean(c)
		end)
	end)
end
