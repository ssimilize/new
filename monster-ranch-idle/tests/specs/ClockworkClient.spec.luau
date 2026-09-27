--[[
	ClockworkClient (R2-CLOCKWORK): the gear tower landmark and the walk-in canyon Area, built
	and turning through the real client (ClientHarness), like DeepReefClient does for the Deep
	Reef's Dock and Area.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local CFrame = t.Roblox.CFrame

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	describe("Clockwork Canyon client", function()
		it("builds the landmark and the area, turns its gears, and the Gate opens Expeditions on it", function()
			local h = TestKernel.new({})
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)

			local tower = c.world.workspace:FindFirstChild("ClockworkTower")
			local area = c.world.workspace:FindFirstChild("ClockworkArea")
			expect(tower ~= nil).toBe(true)
			expect(area ~= nil).toBe(true)
			expect(tower:FindFirstChild("Gear1") ~= nil).toBe(true)

			local canyon = c.kernel:GetController("ClockworkCanyon")
			expect(canyon.GearCount() > 0).toBe(true)

			-- The tower's landmark gears really turn (a pivot changes over time), cheaply.
			local gear1 = tower.Gear1 :: Model
			local before = gear1:GetPivot()
			c:Advance(1)
			expect(gear1:GetPivot() == before).toBe(false)

			-- The Clockwork Gate opens Expeditions on "clockwork" (walked to, no dive/teleport).
			c:Trigger(area.Gate.Portal:FindFirstChildOfClass("ProximityPrompt"))
			c:Advance(0.5)
			expect(c.kernel.Router:Current()).toBe("Expeditions")
			expect(c:HasText("Clockwork", c:Screen("Expeditions"))).toBe(true)
			c:Close("Expeditions")
			expectClean(c)
		end)

		it("drops a gear from the list instead of erroring once its model is gone", function()
			local h = TestKernel.new({})
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local canyon = c.kernel:GetController("ClockworkCanyon")
			local before = canyon.GearCount()
			expect(before > 0).toBe(true)
			local tower = c.world.workspace:FindFirstChild("ClockworkTower")
			tower.Gear1:Destroy()
			c:Advance(1)
			expect(canyon.GearCount()).toBe(before - 1)
			expectClean(c)
		end)
		it("turns the tower's gears only while the camera is near the tower", function()
			local h = TestKernel.new({})
			local p = h:Join()
			local c = ClientHarness.new(h, p)
			c:Advance(2)
			local gear1 = c.world.workspace.ClockworkTower.Gear1 :: Model
			local camera = c.world.workspace.CurrentCamera
			local home = camera.CFrame -- by the plaza, near the tower

			camera.CFrame = CFrame.new(3000, 20, 3000) -- far from the tower and the canyon (Visuals/Wake)
			c:Advance(1)
			local asleep = gear1:GetPivot()
			c:Advance(1)
			expect(gear1:GetPivot() == asleep).toBe(true)

			camera.CFrame = home
			c:Advance(1)
			expect(gear1:GetPivot() == asleep).toBe(false)
			expectClean(c)
		end)
	end)
end
