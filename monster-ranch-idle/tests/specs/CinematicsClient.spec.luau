--[[
	CinematicsClient (glow-up N): the hatch in the world, Hatch All's montage, evolution you watch
	and the star-up look, played through the real client (ClientHarness): the camera shot and its
	hand-back, the 2D fallback, tap to skip, PhotoMode cutting a shot short, and nothing left behind.
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local Enum = t.Roblox.Enum
	local Vector3 = t.Roblox.Vector3
	local CFrame = t.Roblox.CFrame
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

	-- A new player with the starter egg ready in incubator 1.
	local function boot(options)
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		local c = ClientHarness.new(h, p, options)
		c:Advance(Config.Eggs.Starter.hatchSeconds + 1)
		return h, p, c
	end

	local function camera(c)
		return c.world.workspace.CurrentCamera
	end

	-- Lune's CFrame.lookAt faces away from its target (Roblox's faces it), so aim through a point
	-- mirrored behind the eye to get a camera that looks at `position` in the mock.
	local function lookAt(c, position)
		local eye = position + Vector3.new(0, 12, 24)
		camera(c).CFrame = CFrame.lookAt(eye, eye + (eye - position))
		local _, onScreen = camera(c):WorldToViewportPoint(position)
		expect(onScreen).toBe(true)
	end

	local function incubator(c)
		local spot = c.kernel:GetController("World"):IncubatorEgg("starter", 1)
		expect(spot ~= nil).toBe(true)
		return spot.Position
	end

	local function played(c)
		return c.kernel:GetController("Cinematics"):Played()
	end

	local function reveal(c)
		return c.kernel.UI.Top:FindFirstChild("HatchReveal")
	end

	local function stageCount(c): number
		local stage = c.world.workspace:FindFirstChild("Cinematic")
		return if stage then #stage:GetChildren() else 0
	end

	local function expectHandedBack(c, before)
		local cam = camera(c)
		expect(cam.CameraType).toBe(before.CameraType)
		expect(cam.CFrame == before.CFrame).toBe(true)
		expect(cam.FieldOfView).toBe(before.FieldOfView)
		expect(c.kernel:GetController("CameraDirector"):IsBusy()).toBe(false)
		expect(stageCount(c)).toBe(0)
		expect(c.world.game:GetService("Lighting"):FindFirstChild("CinematicPulse")).toBe(nil)
		expect(c.kernel.UI.Hud.Visible).toBe(true)
	end

	local function snapshot(c)
		local cam = camera(c)
		return { CameraType = cam.CameraType, CFrame = cam.CFrame, FieldOfView = cam.FieldOfView }
	end

	local function hatchStarter(c)
		local ok = c:Request("Eggs.Hatch", { slot = 1, starter = "cindlet" })
		expect(ok ~= false).toBe(true)
	end

	-- Taps through every reveal card (a 2D reveal shows its buttons once its animation ends).
	local function niceAll(c)
		for _ = 1, 60 do
			local root = reveal(c)
			if not (root and root.Visible) then
				return
			end
			local button = c:Button("Nice!", root)
			if button then
				c:Click(button)
			end
			c:Advance(0.25)
		end
		error("the reveal never closed")
	end

	describe("Cinematics: the hatch in the world", function()
		it("plays the hatch at the incubator on screen, then the reveal card as its summary", function()
			local _, _, c = boot()
			lookAt(c, incubator(c))
			local before = snapshot(c)
			hatchStarter(c)
			c:Advance(0.3)
			expect(played(c).hatch).toBe(1)
			expect(camera(c).CameraType).toBe(Enum.CameraType.Scriptable)
			expect(stageCount(c) > 0).toBe(true)
			expect(reveal(c).Visible).toBe(false)
			expect(c.kernel:GetController("Hatchery"):IsShowing()).toBe(true)
			expect(c.kernel.UI.Hud.Visible).toBe(false)
			c:Advance(6)
			expect(reveal(c).Visible).toBe(true)
			expect(c:HasText("NEW!", reveal(c))).toBe(true)
			expect(c:Button("Name it", reveal(c)) ~= nil).toBe(true) -- the starter's naming flow stays
			expectHandedBack(c, before)
			niceAll(c)
			expect(reveal(c).Visible).toBe(false)
			expectClean(c)
		end)

		it("falls back to the 2D reveal when the incubator is far away or a screen is open", function()
			local _, _, c = boot()
			camera(c).CFrame = CFrame.new(incubator(c) + Vector3.new(0, 20, 600))
			hatchStarter(c)
			c:Advance(0.3)
			expect(played(c).hatch).toBe(0)
			expect(reveal(c).Visible).toBe(true)
			niceAll(c)

			local _, _, c2 = boot()
			lookAt(c2, incubator(c2))
			c2:Open("Monsters")
			c2:Advance(0.2)
			hatchStarter(c2)
			c2:Advance(0.3)
			expect(played(c2).hatch).toBe(0)
			expect(reveal(c2).Visible).toBe(true)
			expectClean(c)
			expectClean(c2)
		end)

		it("closes the Incubators screen for the shot and opens it again after the card", function()
			local _, _, c = boot()
			lookAt(c, incubator(c))
			c:Open("Incubators")
			c:Advance(0.2)
			hatchStarter(c)
			c:Advance(0.3)
			expect(played(c).hatch).toBe(1)
			expect(c.kernel.Router:Current()).toBe(nil)
			c:Advance(6)
			niceAll(c)
			expect(c.kernel.Router:Current()).toBe("Incubators")
			expectClean(c)
		end)

		it("skips to the summary card on a tap and hands the camera back", function()
			local _, _, c = boot()
			lookAt(c, incubator(c))
			local before = snapshot(c)
			hatchStarter(c)
			c:Advance(0.4)
			local catcher = c.kernel.UI.Top:FindFirstChild("Cinematic"):FindFirstChild("TapToSkip")
			c:Click(catcher)
			c:Advance(1)
			expect(reveal(c).Visible).toBe(true)
			expectHandedBack(c, before)
			niceAll(c)
			expectClean(c)
		end)

		it("plays Hatch All as one quick montage, rarest last, then the cards", function()
			local h, p, c = boot()
			lookAt(c, incubator(c))
			hatchStarter(c)
			c:Advance(0.2)
			c.kernel:GetController("CameraDirector"):Skip()
			c:Advance(1)
			niceAll(c)
			local before = snapshot(c)
			local s = h:Section(p, "Eggs")
			local now = h.adapters.Clock.Now()
			for i = 1, 3 do
				s.slots[i] = { egg = "t" .. i, type = "meadow", startedAt = now - 60, endsAt = now - 1 }
			end
			local ok = c:Request("Eggs.HatchAll")
			expect(ok ~= false).toBe(true)
			c:Advance(0.3)
			expect(played(c).hatch).toBe(2)
			expect(stageCount(c) >= 3).toBe(true) -- every egg of the montage sits on the pad
			c:Advance(9)
			local root = reveal(c)
			expect(root.Visible).toBe(true)
			expect(c:Button("Skip all (2)", root) ~= nil).toBe(true)
			expectHandedBack(c, before)
			niceAll(c)
			expectClean(c)
		end)

		it("cuts instead of gliding with low graphics (reduced motion) and still cleans up", function()
			local _, _, c = boot()
			c:Request("Settings.Set", { key = "lowGraphics", value = true })
			c:Advance(0.2)
			lookAt(c, incubator(c))
			local before = snapshot(c)
			hatchStarter(c)
			c:Advance(0.2)
			expect(played(c).hatch).toBe(1)
			local framed = camera(c).CFrame
			expect(framed ~= before.CFrame).toBe(true)
			c:Advance(0.2)
			expect(camera(c).CFrame == framed).toBe(true) -- already there: no glide
			c:Advance(6)
			expectHandedBack(c, before)
			niceAll(c)
			expectClean(c)
		end)

		it("never runs with PhotoMode: opening it mid-shot cuts back first", function()
			local _, _, c = boot()
			lookAt(c, incubator(c))
			local before = snapshot(c)
			hatchStarter(c)
			c:Advance(0.4)
			c:Open("PhotoMode")
			c:Advance(0.3)
			expect(c.kernel:GetController("PhotoMode"):IsActive()).toBe(true)
			c:Close("PhotoMode")
			c:Advance(1)
			expectHandedBack(c, before)
			niceAll(c)
			expectClean(c)
		end)
	end)

	describe("Cinematics: evolution and star-ups", function()
		local function withPenMonster()
			local h, p, c = boot()
			camera(c).CFrame = CFrame.new(incubator(c) + Vector3.new(0, 20, 600)) -- a 2D hatch
			hatchStarter(c)
			c:Advance(0.3)
			niceAll(c)
			c:Advance(3)
			local id = nil
			for key in c:Store("profile.Monsters.list") do
				id = key
			end
			local own = c.kernel:GetController("World"):OwnMonster(id)
			expect(own ~= nil).toBe(true)
			lookAt(c, own.animator:GetPosition())
			return h, p, c, id, own
		end

		it("frames the evolving monster in its pen, then shows the evolution card", function()
			local h, p, c, id, own = withPenMonster()
			local before = snapshot(c)
			h.kernel.Net:Fire(p, "Monsters.Evolved", { id = id, fromForm = "cindlet", toForm = "kindlefox", stage = 2 })
			c:Advance(0.3)
			expect(played(c).evolve).toBe(1)
			expect(c.kernel.UI.Top:FindFirstChild("Evolved")).toBe(nil)
			c:Advance(6)
			expect(c.kernel.UI.Top:FindFirstChild("Evolved") ~= nil).toBe(true)
			expectHandedBack(c, before)
			for _, d in own.model:GetDescendants() do
				if d:IsA("BasePart") then
					expect(d.LocalTransparencyModifier).toBe(0)
				end
			end
			c:Click(c:Button("Yay!", c.kernel.UI.Top))
			c:Advance(1)
			expectClean(c)
		end)

		it("shows a star-up at the monster once the view is clear", function()
			local _, _, c, id = withPenMonster()
			local before = snapshot(c)
			c.kernel.Bus:Publish("Vfx.Burst", "monsterStarUp", { id = id })
			c:Advance(1.5)
			expect(played(c).spotlight).toBe(1)
			c:Advance(4)
			expectHandedBack(c, before)
			expectClean(c)
		end)
	end)
end
