--[[
	LiveRaceClient (glow-up LR): a live race played through the real client (ClientHarness). One
	rider is under MinPlayers, so the ghosts from Monster Racing fill the field; joining, the
	countdown, the LiveRace controller's own rail-driven running (it moves the character, reports
	its position and finishes), and the session's cleanup back to idle.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Enum = t.Roblox.Enum
	local Config = t.Shared("Config")
	local LR = Config.LiveRace

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

	describe("Live race client", function()
		it("joins from the Racing screen, counts down, races a lap against ghosts and cleans up", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			levelTo(h, p, 16)
			local m = h:System("Monsters"):Create(p, { line = "zappip", rarity = 6, stage = 3 }, "test", true)
			h:Call(p, "Riding.Mount", { id = m.id })

			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local screen = c:Open("Racing")
			c:Advance(0.5)
			local join = c:Button("Join Live Race (up to 6 riders)", screen)
			expect(join ~= nil).toBe(true)
			c:Click(join)
			c:Advance(0.5)
			-- Joining closes the modal panel: the race plays out in the world, not in a screen.
			expect(c.kernel.Router:Current()).toBeNil()
			expect(type(c:Store("session.LiveRace").heat)).toBe("number")

			-- One human is under MinPlayers: the lobby waits the full LobbySeconds, then the
			-- ghosts join and the countdown runs.
			c:Advance(LR.LobbySeconds + 1)
			expect(c:Store("global.LiveRace").state).toBe("countdown")
			expect(#c:Store("global.LiveRace").ghosts > 0).toBe(true)
			c:Advance(LR.CountdownSeconds + 1)
			expect(c:Store("global.LiveRace").state).toBe("running")

			-- The controller takes the character over (driven along the track, a chase camera)
			-- and reports its own position; let it run itself to the finish line.
			local root = c.character.HumanoidRootPart
			local startPosition = root.Position
			local camera = c.world.workspace.CurrentCamera
			expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
			-- Solo (no other human): the heat settles the instant the local rider finishes, so
			-- `session.finished` (true only while the heat is still open) can flip back to its
			-- resting `false` again before the next poll. `result` is set once, at that same
			-- settle, and stays until the next Join — the reliable "I'm done" signal here.
			local result = nil
			for _ = 1, 400 do
				c:Advance(0.5, 0.1)
				local sess = c:Store("session.LiveRace")
				if type(sess.result) == "table" then
					result = sess.result
					break
				end
			end
			expect(type(result)).toBe("table")
			expect(result.finished).toBe(true)
			-- The rider's character actually moved along the track (not stuck at the grid).
			expect(root.Position ~= startPosition).toBe(true)

			-- Once the local rider is done, control (and the camera) is handed back at once, to
			-- whatever it was before (the mock's default, Fixed).
			expect(camera.CameraType).toBe(Enum.CameraType.Fixed)

			-- The heat itself settles to idle right along with it (solo: no one left to wait on).
			expect(c:Store("global.LiveRace").state).toBe("podium")
			expect(c:Store("session.LiveRace").heat).toBe(false)
			c:Advance(LR.PodiumSeconds + 1)
			expect(c:Store("global.LiveRace").state).toBe("idle")
			expectClean(c)
		end)
	end)
end
