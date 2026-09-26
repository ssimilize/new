--[[
	CompanionsClient (glow-up T): companions and animated mounts through the real client. "Walk with
	me" on MonsterDetail, the HUD badge, the follow states as the character moves (walk, idle, sit,
	hop, catching up after a teleport), photo mode's pose, hiding while riding, and the mount's
	gait (idle, walk at the measured speed, hop). Clean of problems throughout.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local CFrame = t.Roblox.CFrame
	local Vector3 = t.Roblox.Vector3
	local Config = t.Shared("Config")
	local Cfg = Config.Companions

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
		local problems = c:Problems({ "Infinite yield possible" })
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	-- Moves the character by (dx, dy) studs per frame for `frames` frames of 0.1 s.
	local function move(c, dx: number, dy: number, frames: number)
		local root = c.character.HumanoidRootPart
		for _ = 1, frames do
			root.CFrame = root.CFrame + Vector3.new(dx, dy, 0)
			c:Advance(0.1)
		end
	end

	local function flat(a, b): number
		return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
	end

	describe("Companions (client)", function()
		it("walks a companion beside the player, sits, hops, catches up and poses", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			local M = h:System("Monsters")
			local m = M:Create(p, { line = "zappip", rarity = 3, stage = 3 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local companions = c.kernel:GetController("Companions")

			local screen = c:Open("MonsterDetail", { id = m.id })
			c:Advance(0.3)
			c:Click(c:Button("Walk with me", screen))
			c:Advance(1)
			expect(c:Store("profile.Companions.ids")).toEqual({ m.id })
			expect(c:Button("Stop walking", screen) ~= nil).toBe(true)
			c:Close("MonsterDetail")
			c:Advance(0.5)

			local model = companions:ModelOf(p.UserId, 1)
			expect(model ~= nil).toBe(true)
			expect(model.Parent).toBe(c.world.workspace.Companions)
			expect(companions:Count()).toBe(1)
			expect(c:Button("🐾 1", c.kernel.UI.Hud) ~= nil).toBe(true)
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					expect(part.CanCollide).toBe(false)
				end
			end

			-- Walk away at 20 studs/s: it trots after us and keeps up.
			local root = c.character.HumanoidRootPart
			move(c, 2, 0, 5)
			expect(companions:StateOf(p.UserId, 1)).toBe("walk")
			move(c, 2, 0, 15)
			expect(flat(model:GetPivot().Position, root.Position) < 12).toBe(true)

			-- Stop: it arrives and idles, then sits after a still moment.
			c:Advance(1.5)
			expect(companions:StateOf(p.UserId, 1)).toBe("idle")
			c:Advance(Cfg.SitAfter)
			expect(companions:StateOf(p.UserId, 1)).toBe("sit")

			-- Jump: it hops too.
			move(c, 0, 1.5, 1)
			expect(companions:StateOf(p.UserId, 1)).toBe("hop")
			move(c, 0, -1.5, 1)
			c:Advance(1)

			-- A teleport: it appears beside us instead of running across the map.
			root.CFrame = CFrame.new(400, root.Position.Y + 6, 300)
			c:Advance(0.2)
			expect(flat(model:GetPivot().Position, root.Position) < 10).toBe(true)

			-- Photo mode's Pose reaches it through World:OwnMonstersNear.
			local found = c.kernel:GetController("World"):OwnMonstersNear(root.Position, 20)
			local subject = nil
			for _, entry in found do
				if entry.model == model then
					subject = entry
				end
			end
			expect(subject ~= nil).toBe(true)
			subject.animator:Play("happy")
			expect(subject.animator._state).toBe("happy")
			c:Advance(0.1)
			expect(companions:StateOf(p.UserId, 1)).toBe("happy")

			-- Send it home from the badge's screen.
			c:Click(c:Button("🐾 1", c.kernel.UI.Hud))
			c:Advance(0.3)
			c:Click(c:Button("Stop walking", c:Screen("MonsterDetail")))
			c:Advance(1)
			expect(c:Store("profile.Companions.ids")).toEqual({})
			expect(companions:ModelOf(p.UserId, 1)).toBeNil()
			expect(companions:Count()).toBe(0)
			expectClean(c)
		end)

		it("hides companions while riding and animates the mount with the rider", function()
			local h = TestKernel.new({ systems = allSystems() })
			local p = h:Join()
			h:System("Progression"):AddXP(p, 1e7, "test")
			local M = h:System("Monsters")
			local pet = M:Create(p, { line = "mossbun", rarity = 2, stage = 3 }, "test", true)
			local steed = M:Create(p, { line = "zappip", rarity = 5, stage = 3 }, "test", true)
			local c = ClientHarness.new(h, p)
			c:Advance(1)
			local companions = c.kernel:GetController("Companions")
			local mounts = c.kernel:GetController("Mounts")
			c:Request("Companions.Set", { ids = { pet.id } })
			c:Advance(1)
			expect(companions:Count()).toBe(1)

			c:Request("Riding.Mount", { id = steed.id })
			c:Advance(1)
			expect(c.character:FindFirstChild("Mount") ~= nil).toBe(true)
			expect(companions:Count()).toBe(0)
			expect(mounts:StateOf(p.UserId)).toBe("idle")

			move(c, 2.5, 0, 8)
			expect(mounts:StateOf(p.UserId)).toBe("walk")
			expect(mounts:SpeedOf(p.UserId) > 15).toBe(true)
			move(c, 0, 1.5, 1)
			expect(mounts:StateOf(p.UserId)).toBe("hop")
			move(c, 0, -1.5, 1)
			c:Advance(2)
			expect(mounts:StateOf(p.UserId)).toBe("idle")

			c:Request("Riding.Dismount")
			c:Advance(1)
			expect(mounts:StateOf(p.UserId)).toBeNil()
			expect(companions:Count()).toBe(1)
			expectClean(c)
		end)
	end)
end
