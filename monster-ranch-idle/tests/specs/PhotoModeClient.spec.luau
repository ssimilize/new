--[[
	PhotoModeClient: photo mode played through the real client (ClientHarness): the HUD camera
	button, hiding and restoring the game UI and camera, the free camera by touch, mouse wheel and
	pad, collision, tap-to-focus depth of field, filters (and low graphics), frames, stickers,
	posing monsters and the CaptureService flow (stubbed; the mock has no CaptureService members,
	which is also the "unsupported platform" case).
]]
return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local TestKernel, ClientHarness = t.TestKernel, t.ClientHarness
	local RobloxMock = require("../runtime/RobloxMock")
	local Enum = t.Roblox.Enum
	local Vector3 = t.Roblox.Vector3
	local Vector2 = t.Roblox.Vector2

	local function allSystems()
		local list = {}
		for _, name in t.Server("Manifest").Systems do
			if name ~= "World" then
				table.insert(list, name)
			end
		end
		return list
	end

	local function boot(options)
		local h = TestKernel.new({ systems = allSystems() })
		local p = h:Join()
		local c = ClientHarness.new(h, p, options)
		c:Advance(1)
		return h, p, c
	end

	local function expectClean(c)
		local problems = c:Problems()
		if #problems > 0 then
			error(table.concat(problems, "\n\n"), 2)
		end
	end

	local function controller(c)
		return c.kernel:GetController("PhotoMode")
	end

	local function openFromHud(c)
		local button = c:Button("📷", c.kernel.UI.Hud)
		expect(button ~= nil).toBe(true)
		c:Click(button)
		c:Advance(0.2)
		return c:Screen("PhotoMode")
	end

	local function effect(c, name: string)
		return c.world.game:GetService("Lighting"):FindFirstChild(name)
	end

	local function photoActions(c): { string }
		local list = {}
		for name in c.world.input.actions do
			if string.sub(name, 1, 9) == "PhotoMode" then
				table.insert(list, name)
			end
		end
		table.sort(list)
		return list
	end

	local function input(c, kind, position: Vector2, keyCode)
		return RobloxMock.newInput(c.world, {
			UserInputType = kind,
			KeyCode = keyCode or Enum.KeyCode.Unknown,
			UserInputState = Enum.UserInputState.Begin,
			Position = Vector3.new(position.X, position.Y, 0),
		})
	end

	local function uis(c)
		return c.world.game:GetService("UserInputService")
	end

	local function touchDown(c, root, position: Vector2)
		local touch = input(c, Enum.UserInputType.Touch, position)
		RobloxMock.fire(root:FindFirstChild("Surface"), "InputBegan", touch)
		c:Settle()
		return touch
	end

	local function touchMove(c, touch, position: Vector2)
		RobloxMock.rawSet(touch, "Position", Vector3.new(position.X, position.Y, 0))
		RobloxMock.rawSet(touch, "UserInputState", Enum.UserInputState.Change)
		RobloxMock.fire(uis(c), "InputChanged", touch, true)
		c:Settle()
	end

	local function touchUp(c, touch)
		RobloxMock.rawSet(touch, "UserInputState", Enum.UserInputState.End)
		RobloxMock.fire(uis(c), "InputEnded", touch, true)
		c:Settle()
	end

	local function tap(c, root, position: Vector2)
		touchUp(c, touchDown(c, root, position))
	end

	describe("Photo mode", function()
		it("hides every game UI from the HUD camera button and gives the game back exactly", function()
			local _, _, c = boot()
			local ui = c.kernel.UI
			local camera = c.world.workspace.CurrentCamera
			local other = c.Instance.new("ScreenGui")
			other.Name = "SomeoneElsesGui"
			other.Parent = c.playerGui
			local sign = c.Instance.new("BillboardGui")
			sign.Parent = c.character.HumanoidRootPart
			local humanoid = c.character:FindFirstChildOfClass("Humanoid")
			local before = {
				cframe = camera.CFrame,
				cameraType = camera.CameraType,
				fov = camera.FieldOfView,
				display = humanoid.DisplayDistanceType,
			}
			c:Open("Settings")
			c:Advance(0.3)
			local root = openFromHud(c)
			local photo = controller(c)
			expect(photo:IsActive()).toBe(true)
			expect(c:IsShown(root)).toBe(true)
			expect(c.kernel.Router:IsOpen("Settings")).toBe(false)
			expect(ui.Hud.Visible).toBe(false)
			expect(ui.Top.Visible).toBe(false)
			expect(other.Enabled).toBe(false)
			expect(sign.Enabled).toBe(false)
			expect(humanoid.DisplayDistanceType).toBe(Enum.HumanoidDisplayDistanceType.None)
			expect(camera.CameraType).toBe(Enum.CameraType.Scriptable)
			for _, name in { "PhotoModeColor", "PhotoModeBloom", "PhotoModeDepth" } do
				expect(effect(c, name) ~= nil).toBe(true)
			end
			expect(#photoActions(c) > 0).toBe(true)
			-- A nameplate that appears during the session is hidden too.
			local late = c.Instance.new("BillboardGui")
			late.Parent = c.character.HumanoidRootPart
			c:Advance(0.1)
			expect(late.Enabled).toBe(false)
			-- The only buttons left are photo mode's own.
			for _, b in c:Buttons() do
				expect(b:IsDescendantOf(root)).toBe(true)
			end
			c:Advance(1)
			expect(camera.CFrame ~= before.cframe).toBe(true)

			c:Click(c:Button("✕", root))
			c:Advance(0.2)
			expect(photo:IsActive()).toBe(false)
			expect(c:IsShown(root)).toBe(false)
			expect(ui.Hud.Visible).toBe(true)
			expect(ui.Top.Visible).toBe(true)
			expect(other.Enabled).toBe(true)
			expect(sign.Enabled).toBe(true)
			expect(late.Enabled).toBe(true)
			expect(humanoid.DisplayDistanceType).toBe(before.display)
			expect(camera.CameraType).toBe(before.cameraType)
			expect(camera.CFrame).toBe(before.cframe)
			expect(camera.FieldOfView).toBe(before.fov)
			for _, name in { "PhotoModeColor", "PhotoModeBloom", "PhotoModeDepth" } do
				expect(effect(c, name)).toBe(nil)
			end
			expect(photoActions(c)).toEqual({})
			expectClean(c)
		end)

		it("orbits, pinches and pans by touch, zooms with the wheel and keeps to its radius", function()
			local _, _, c = boot()
			local root = openFromHud(c)
			local photo = controller(c)
			local start = photo:Rig()

			local finger = touchDown(c, root, Vector2.new(300, 200))
			touchMove(c, finger, Vector2.new(340, 220))
			local rig = photo:Rig()
			expect(math.abs(rig.yaw - (start.yaw - 40 * 0.3)) < 1e-4).toBe(true)
			expect(rig.pitch > start.pitch).toBe(true)
			touchUp(c, finger)

			local a = touchDown(c, root, Vector2.new(200, 200))
			local b = touchDown(c, root, Vector2.new(300, 200))
			local distance = photo:Rig().distance
			touchMove(c, b, Vector2.new(400, 200)) -- fingers spread: zoom in
			expect(photo:Rig().distance < distance).toBe(true)
			local x = photo:Rig().x
			touchMove(c, a, Vector2.new(260, 200)) -- the pair's centre moves: the view pans
			expect(photo:Rig().x ~= x).toBe(true)
			touchUp(c, a)
			touchUp(c, b)
			expect(effect(c, "PhotoModeDepth").FocusDistance > 0).toBe(true)

			distance = photo:Rig().distance
			local wheel = input(c, Enum.UserInputType.MouseWheel, Vector2.new(300, 200))
			RobloxMock.rawSet(wheel, "Position", Vector3.new(300, 200, 1))
			RobloxMock.fire(root:FindFirstChild("Surface"), "InputChanged", wheel)
			c:Settle()
			expect(photo:Rig().distance < distance).toBe(true)

			c:Stick(0, 1) -- left stick forward for a long time
			c:Advance(8)
			c:Stick(0, 0)
			rig = photo:Rig()
			expect(math.sqrt(rig.x * rig.x + rig.z * rig.z) <= 60 + 1e-3).toBe(true)
			expectClean(c)
		end)

		it("keeps the camera on this side of the ground", function()
			local _, _, c = boot()
			openFromHud(c)
			c:Advance(1)
			local camera = c.world.workspace.CurrentCamera
			local focus = camera.Focus.Position
			local eye = camera.CFrame.Position
			local towards = (eye - focus).Unit
			c.world.raycastResult = { Position = focus + towards * 3, Distance = 3, Normal = Vector3.new(0, 1, 0) }
			c:Advance(1)
			local reach = (camera.CFrame.Position - focus).Magnitude
			expect(reach <= 3).toBe(true)
			expect(reach > 1).toBe(true)
			c.world.raycastResult = nil
			c:Advance(1)
			expect((camera.CFrame.Position - focus).Magnitude > 3).toBe(true)
			c:Close("PhotoMode")
			expectClean(c)
		end)

		it("focuses on a tap, cycles filters and frames, and drops heavy effects in low graphics", function()
			local _, _, c = boot()
			local root = openFromHud(c)
			local photo = controller(c)
			local depth = effect(c, "PhotoModeDepth")
			local bloom = effect(c, "PhotoModeBloom")
			expect(depth.Enabled).toBe(true)
			local camera = c.world.workspace.CurrentCamera
			c:Advance(1)
			local eye = camera.CFrame.Position
			c.world.raycastResult = { Position = eye + camera.CFrame.LookVector * 25, Distance = 25, Normal = Vector3.new(0, 1, 0) }
			tap(c, root, Vector2.new(320, 180))
			expect(math.abs(depth.FocusDistance - 25) < 0.5).toBe(true)
			expect(root:FindFirstChild("FocusRing").Visible).toBe(true)
			c.world.raycastResult = nil

			local filter = root.Toolbar.Filter
			expect(c:HasText("Natural", filter)).toBe(true)
			for _, name in { "Warm", "Cool", "Dreamy" } do
				c:Click(filter)
				expect(c:HasText(name, root)).toBe(true)
			end
			expect(photo:Filter().id).toBe("dreamy")
			expect(bloom.Enabled).toBe(true)

			local frame = root.Toolbar.Frame
			expect(c:HasText("No frame", frame)).toBe(true)
			c:Click(frame)
			expect(c:HasText("Polaroid", root)).toBe(true)
			expect(root.FrameArt.polaroid.Visible).toBe(true)
			expect(c:HasText(c.localPlayer.DisplayName .. "'s ranch", root)).toBe(true)
			c:Click(frame)
			c:Click(frame)
			expect(root.FrameArt.badge.Visible).toBe(true)
			expect(root.FrameArt.polaroid.Visible).toBe(false)

			local ok = c:Request("Settings.Set", { key = "lowGraphics", value = true })
			expect(ok).toBe(true)
			c:Advance(0.5)
			expect(photo:Filter().heavy).toBe(nil) -- moved off Dreamy
			expect(bloom.Enabled).toBe(false)
			expect(depth.Enabled).toBe(false)
			expect(c:IsShown(root.Toolbar.Blur)).toBe(false)
			expect(photo:ReducedMotion()).toBe(true)
			for _ = 1, #t.Shared("Config.Photo").Filters do
				c:Click(filter)
				expect(photo:Filter().heavy).toBe(nil)
				expect(bloom.Enabled).toBe(false)
			end
			c:Request("Settings.Set", { key = "lowGraphics", value = false })
			c:Advance(0.5)
			expect(c:HasText("Blur on", root.Toolbar.Blur)).toBe(true)
			c:Click(root.Toolbar.Blur)
			expect(depth.Enabled).toBe(false)
			expect(c:HasText("Blur off", root)).toBe(true)
			c:Close("PhotoMode")
			expectClean(c)
		end)

		it("places stickers by tapping, drags them, removes one and clears the rest", function()
			local _, _, c = boot()
			local root = openFromHud(c)
			local layer = root:FindFirstChild("Stickers")
			c:Click(c:Button("Stickers", root))
			local tray = root:FindFirstChild("Tray")
			expect(c:IsShown(tray)).toBe(true)
			c:Click(tray:FindFirstChild("heart"))
			expect(c:HasText("Tap where the sticker goes", root)).toBe(true)
			tap(c, root, Vector2.new(400, 250))
			tap(c, root, Vector2.new(200, 150))
			local placed = layer:GetChildren()
			expect(#placed).toBe(2)
			local sticker = placed[1]
			expect(sticker:GetAttribute("Sprite")).toBe("heart")

			-- Drag it with a finger.
			local from = sticker.Position
			local finger = input(c, Enum.UserInputType.Touch, Vector2.new(400, 250))
			RobloxMock.fire(sticker, "InputBegan", finger)
			c:Settle()
			touchMove(c, finger, Vector2.new(480, 250))
			touchUp(c, finger)
			expect(sticker.Position.X.Scale > from.X.Scale).toBe(true)
			expect(sticker:FindFirstChild("Remove").Visible).toBe(false)

			-- A plain press (pad A, or a click) shows its ✕, which removes it.
			c:Advance(2)
			c:Click(sticker)
			expect(sticker:FindFirstChild("Remove").Visible).toBe(true)
			c:Click(sticker:FindFirstChild("Remove"))
			expect(#layer:GetChildren()).toBe(1)

			c:Click(c:Button("Clear", tray))
			expect(#layer:GetChildren()).toBe(0)
			-- Stickers do not survive leaving photo mode.
			tap(c, root, Vector2.new(300, 300))
			expect(#layer:GetChildren()).toBe(1)
			c:Close("PhotoMode")
			expect(#layer:GetChildren()).toBe(0)
			expectClean(c)
		end)

		it("poses the player's monsters with trick, or happy where there is no trick", function()
			local _, _, c = boot()
			local root = openFromHud(c)
			local world = c.kernel:GetController("World")
			expect(type(world:OwnMonstersNear(Vector3.zero, 1000))).toBe("table")

			c:Click(root.Toolbar.Pose)
			c:Advance(0.5)
			expect(c:HasText("None of your monsters are close by")).toBe(true)

			local function animator(knowsTrick: boolean)
				return {
					calls = {},
					_state = "idle",
					Play = function(self, state)
						table.insert(self.calls, state)
						self._state = if state == "trick" and not knowsTrick then "idle" else state
					end,
				}
			end
			local old, withTrick = animator(false), animator(true)
			local real = world.OwnMonstersNear
			world.OwnMonstersNear = function()
				return { { animator = old }, { animator = withTrick } }
			end
			c:Click(root.Toolbar.Pose)
			c:Advance(0.5)
			world.OwnMonstersNear = real
			expect(old.calls).toEqual({ "trick", "happy" })
			expect(withTrick.calls).toEqual({ "trick" })
			c:Close("PhotoMode")
			expectClean(c)
		end)

		it("hides the photo button without CaptureService and runs capture, save and share when it exists", function()
			local _, _, c = boot()
			local root = openFromHud(c)
			local photo = controller(c)
			expect(photo:Capabilities().capture).toBe(false)
			expect(c:IsShown(root.Toolbar.TakePhoto)).toBe(false)
			expect(root:GetAttribute("GamepadLegend")).toBe("Ⓧ Filter · Ⓨ Pose · LB/RB Frame · Ⓑ Exit")
			local result = "unset"
			c.world:Run(function()
				photo:Capture(function(id)
					result = id
				end)
			end)
			c:Settle()
			expect(result).toBe(nil)
			c:Close("PhotoMode")

			-- A platform with CaptureService: stub the controller's CaptureService calls.
			local saved, shared = {}, {}
			local nextId: string? = "rbxtemp://photo-1"
			photo.Capabilities = function()
				return { capture = true, save = true, share = true }
			end
			photo.Capture = function(_, done)
				done(nextId) -- runs in the calling game thread (the spec's own task library is not the world's)
			end
			photo.Save = function(_, id, done)
				table.insert(saved, id)
				done(true)
			end
			photo.Share = function(_, id, done)
				table.insert(shared, id)
				done(true)
			end
			root = openFromHud(c)
			expect(root:GetAttribute("GamepadLegend")).toBe("Ⓐ Photo · Ⓧ Filter · Ⓨ Pose · LB/RB Frame · Ⓑ Exit")
			c:Click(root.Toolbar.TakePhoto)
			c:Advance(0.5)
			local card = root:FindFirstChild("PhotoCard")
			expect(c:IsShown(card)).toBe(true)
			expect(card.Photo.Image).toBe("rbxtemp://photo-1")
			expect(c:IsShown(root:FindFirstChild("Toolbar"))).toBe(true)
			c:Click(c:Button("Save", card))
			c:Click(c:Button("Share", card))
			c:Advance(0.2)
			expect(saved).toEqual({ "rbxtemp://photo-1" })
			expect(shared).toEqual({ "rbxtemp://photo-1" })
			expect(c:HasText("Saved to your gallery!")).toBe(true)
			c:Click(c:Button("Back", card))
			expect(c:IsShown(card)).toBe(false)

			nextId = nil
			c:Click(root.Toolbar.TakePhoto)
			c:Advance(0.5)
			expect(c:HasText("Couldn't take the photo. Try again.")).toBe(true)
			expect(c:IsShown(card)).toBe(false)
			c:Close("PhotoMode")
			expectClean(c)
		end)

		it("plays with a pad and a keyboard, and binds nothing outside a session", function()
			local _, _, c = boot()
			expect(photoActions(c)).toEqual({})
			c:UseGamepad(true)
			c:Press("DPadUp")
			c:Advance(0.2)
			local photo = controller(c)
			local root = c:Screen("PhotoMode")
			expect(photo:IsActive()).toBe(true)
			c:Press("ButtonX")
			expect(photo:Filter().id).toBe("warm")
			c:Press("ButtonR1")
			expect(root.FrameArt.polaroid.Visible).toBe(true)
			c:Press("ButtonL1")
			expect(root.FrameArt.polaroid.Visible).toBe(false)
			c:Press("DPadRight")
			expect(#root.Stickers:GetChildren()).toBe(1)
			c:Press("DPadLeft")
			expect(#root.Stickers:GetChildren()).toBe(0)
			c:Press("DPadUp")
			expect(c:IsShown(root:FindFirstChild("Toolbar"))).toBe(false)
			expect(c.kernel.UI.Overlay.Visible).toBe(false)
			c:Press("DPadUp")
			expect(c:IsShown(root:FindFirstChild("Toolbar"))).toBe(true)
			expect(c.kernel.UI.Overlay.Visible).toBe(true)
			c:Press("ButtonB")
			c:Advance(0.2)
			expect(photo:IsActive()).toBe(false)
			expect(photoActions(c)).toEqual({})

			c:Press("P")
			c:Advance(0.2)
			expect(photo:IsActive()).toBe(true)
			c:Press("H")
			expect(c:IsShown(root:FindFirstChild("Toolbar"))).toBe(false)
			-- A tap anywhere brings the toolbar back.
			c:Click(root:FindFirstChild("Surface"))
			expect(c:IsShown(root:FindFirstChild("Toolbar"))).toBe(true)
			c:Press("P")
			c:Advance(0.2)
			expect(photo:IsActive()).toBe(false)
			expect(photoActions(c)).toEqual({})
			-- Not while a menu is open.
			c:Open("Codex")
			c:Press("P")
			expect(photo:IsActive()).toBe(false)
			c:Close("Codex")
			expectClean(c)
		end)

		it("puts the HUD camera inside a small phone, clear of the gear and the level bar", function()
			local _, _, c = boot({ viewport = Vector2.new(568, 320) })
			local hud = c.kernel.UI.Hud
			local camera = c:Button("📷", hud)
			local function rect(gui)
				return gui.AbsolutePosition, gui.AbsolutePosition + gui.AbsoluteSize
			end
			local a0, a1 = rect(camera)
			expect(a0.X >= 0 and a0.Y >= 0 and a1.X <= 568 and a1.Y <= 320).toBe(true)
			for _, other in { c:Button("⚙", hud), hud:FindFirstChild("RanchLevel", true) } do
				local b0, b1 = rect(other)
				local overlaps = a0.X < b1.X and b0.X < a1.X and a0.Y < b1.Y and b0.Y < a1.Y
				expect(overlaps).toBe(false)
			end
			expectClean(c)
		end)
	end)
end
