--[[
	PhotoMode controller: the world side of photo mode ("your ranch is on display"). The toolbar,
	frames, stickers and the photo card are the PhotoMode screen (UI/Screens/PhotoMode), a
	non-modal Router screen: opening it starts a session here and closing it ends one, so every way
	out (✕, B, P, another screen opening) restores the game the same way.

	Entry: the HUD's 📷 button (Router:Toggle("PhotoMode")), P on a keyboard, D-pad up on a pad,
	each only while no screen or modal card is open.

	A session:
	  · closes the open menu, hides every ScreenGui the game owns (our layers except the photo
	    screen, the toast lane and the pad legend; any other ScreenGui in the PlayerGui, the touch
	    controls included), every BillboardGui (nameplates, jar labels), avatar name tags and the
	    Roblox core GUI, and restores exactly what it changed, unless someone else changed it since;
	  · takes the camera (Scriptable, BindToRenderStep after the camera scripts) and gives it back
	    with its old CameraType, CameraSubject, CFrame, Focus and FieldOfView;
	  · orbits, pans and zooms (Logic/PhotoRig) around the spot it began at, within
	    Config.Photo.Camera.radius; a ray from the focus to the eye keeps the camera out of the ground
	    and walls; reduced motion (Anim.enabled off, lowGraphics, or GuiService.ReducedMotionEnabled)
	    snaps instead of easing;
	  · adds a ColorCorrectionEffect, a BloomEffect and a DepthOfFieldEffect to Lighting (removed on
	    exit). Low graphics skips heavy filters, bloom and depth of field.

	Input (the screen's full-screen Surface button sinks touches and clicks, so World's monster
	taps and the character never see them):
	  touch      one finger drags to orbit, two fingers pan and pinch to zoom, a tap focuses (or places
	             the armed sticker, or brings the hidden toolbar back)
	  mouse      left-drag orbits, right-drag pans, the wheel zooms, a click focuses
	  keyboard   WASD pan, Q / E down / up, arrow keys orbit, R / F zoom, Space takes the photo,
	             H hides the toolbar, P leaves
	  gamepad    left stick pans, right stick orbits, RT / LT zoom, A takes the photo, X next filter,
	             Y pose, LB / RB frame, D-pad up hides the toolbar, D-pad down focuses the centre,
	             D-pad right / left adds / removes a sticker, B leaves (the screen's GamepadLegend
	             attribute keeps the Gamepad controller's cursor away)
	Movement keys and sticks are sunk with ContextActionService while a session runs, so the
	character stands still; nothing is bound outside a session.

	Public (the screen and tests use these):
	  PhotoMode:IsActive() -> boolean          PhotoMode:Toggle()
	  PhotoMode:Begin(api) / :End()            called by the screen's Open / Close;
	                                           api = { Surface, Tap(pos) -> boolean, Focused(pos),
	                                                   Command(name), Busy() -> boolean }
	  PhotoMode:Filter() -> def                PhotoMode:StepFilter(step) -> def
	  PhotoMode:DepthAvailable() / :DepthOn() / :SetDepth(on)
	  PhotoMode:FocusAt(screenPos: Vector2) -> boolean   raycast under a screen point (input space)
	  PhotoMode:Pose() -> number               own pen monsters near the focus play "trick" (or
	                                           "happy" where the animator has no trick clip)
	  PhotoMode:SetClean(on)                   hides the toast lane and pad legend for the shot
	  PhotoMode:Capabilities() -> { capture, save, share }   CaptureService members that exist
	  PhotoMode:Capture(done(contentId?)) / :Save(contentId, done(ok)) / :Share(contentId, done(ok))
	  PhotoMode:Rig() -> { yaw, pitch, distance, x, y, z }   copy, for tests
	  PhotoMode:LowGraphics() / :ReducedMotion() -> boolean
]]

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local PhotoConfig = require(Shared.Config.Photo)
local PhotoRig = require(Shared.Logic.PhotoRig)

local Client = script.Parent.Parent
local Anim = require(Client.UI.Anim)
local Quality = require(Client.Visuals.Quality)
local Focus = require(Client.UI.Focus)
local Voices = require(Client.Audio.Voices)

local PhotoMode = {
	Name = "PhotoMode",
	Dependencies = {},
}

local SCREEN = "PhotoMode"
local RENDER_NAME = "PhotoModeCamera"
local PRIORITY = Enum.ContextActionPriority.High.Value
local CAM = PhotoConfig.Camera
local DEPTH = PhotoConfig.Depth
local FILTERS = PhotoConfig.Filters
local CAPTURE_TIMEOUT = 6
local KEEP_OVERLAY = { Toasts = true, GamepadLegend = true }

local HELD_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Q,
	Enum.KeyCode.E,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.R,
	Enum.KeyCode.F,
}
local SUNK = { Enum.KeyCode.Thumbstick1, Enum.KeyCode.Thumbstick2, Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2 }
-- action name -> { keys, command } (commands go to the screen; "exit" and "focus" are ours)
local COMMANDS = {
	PhotoModeShoot = { { Enum.KeyCode.Space, Enum.KeyCode.ButtonA }, "capture" },
	PhotoModeFilter = { { Enum.KeyCode.ButtonX }, "filter" },
	PhotoModePose = { { Enum.KeyCode.ButtonY }, "pose" },
	PhotoModeFramePrev = { { Enum.KeyCode.ButtonL1 }, "framePrev" },
	PhotoModeFrameNext = { { Enum.KeyCode.ButtonR1 }, "frameNext" },
	PhotoModeHide = { { Enum.KeyCode.H, Enum.KeyCode.DPadUp }, "toggle" },
	PhotoModeFocus = { { Enum.KeyCode.DPadDown }, "focus" },
	PhotoModeSticker = { { Enum.KeyCode.DPadRight }, "sticker" },
	PhotoModeUnsticker = { { Enum.KeyCode.DPadLeft }, "unsticker" },
	PhotoModeExit = { { Enum.KeyCode.ButtonB, Enum.KeyCode.P }, "exit" },
}

local ctx
local session = nil -- one photo session's state; nil while photo mode is off
local filterIndex = 1 -- kept between sessions
local depthOn = true
local capabilities = nil

-- Settings -----------------------------------------------------------------------------------

-- Effects follow the quality level (Visuals/Quality, glow-up P); reduced motion follows only the
-- player's explicit Low choice (Settings.lowGraphics), never Auto dropping to Low.
local function lowGraphics(): boolean
	return Quality.IsLow()
end

local function reducedMotion(): boolean
	local settings = ctx.Store:Get("profile.Settings")
	if not Anim.enabled or (type(settings) == "table" and settings.lowGraphics == true) then
		return true
	end
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

local function filterAllowed(index: number): boolean
	local def = FILTERS[index]
	return def ~= nil and not (def.heavy and lowGraphics())
end

-- Hiding and restoring ----------------------------------------------------------------------

-- Sets inst[prop] = value and remembers the old value (restored in reverse order on exit).
local function hide(inst: Instance, prop: string, value: any)
	if not session then
		return
	end
	local ok, current = pcall(function()
		return (inst :: any)[prop]
	end)
	if not ok or current == value then
		return
	end
	(inst :: any)[prop] = value
	table.insert(session.hidden, { inst = inst, prop = prop, value = current, set = value })
end

local function restoreHidden()
	for i = #session.hidden, 1, -1 do
		local entry = session.hidden[i]
		pcall(function()
			-- Leave it if someone else changed it meanwhile (their value is newer than ours).
			if (entry.inst :: any)[entry.prop] == entry.set then
				(entry.inst :: any)[entry.prop] = entry.value
			end
		end)
	end
	table.clear(session.hidden)
end

local function hideCollector(gui: Instance)
	if gui ~= ctx.UI.Gui and (gui:IsA("ScreenGui") or gui:IsA("BillboardGui")) then
		hide(gui, "Enabled", false)
	end
end

local function hideHumanoid(character: Model?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		hide(humanoid, "DisplayDistanceType", Enum.HumanoidDisplayDistanceType.None)
	end
end

local function hideGameUi(screenRoot: GuiObject?)
	local ui = ctx.UI
	hide(ui.Hud, "Visible", false)
	hide(ui.Top, "Visible", false)
	for _, child in ui.Overlay:GetChildren() do
		if child:IsA("GuiObject") and not KEEP_OVERLAY[child.Name] then
			hide(child, "Visible", false)
		end
	end
	for _, child in ui.Screens:GetChildren() do
		if child:IsA("GuiObject") and child ~= screenRoot then
			hide(child, "Visible", false)
		end
	end
	local playerGui = ui.Gui.Parent
	if playerGui then
		for _, gui in playerGui:GetChildren() do
			hideCollector(gui)
		end
		table.insert(
			session.conns,
			playerGui.ChildAdded:Connect(function(gui)
				task.defer(function()
					if session and gui.Parent == playerGui then
						hideCollector(gui)
					end
				end)
			end)
		)
	end
	for _, d in workspace:GetDescendants() do
		if d:IsA("BillboardGui") then
			hide(d, "Enabled", false)
		end
	end
	table.insert(
		session.conns,
		workspace.DescendantAdded:Connect(function(d)
			if d:IsA("BillboardGui") then
				task.defer(function()
					if session and d.Parent then
						hide(d, "Enabled", false)
					end
				end)
			end
		end)
	)
	for _, p in Players:GetPlayers() do
		hideHumanoid(p.Character)
	end
	-- Roblox's own menus (player list, chat, backpack, the capture button, ...).
	session.core = {}
	local ok, items = pcall(function()
		return Enum.CoreGuiType:GetEnumItems()
	end)
	if ok then
		for _, item in items do
			if item ~= Enum.CoreGuiType.All then
				local okGet, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, item)
				if okGet and on then
					table.insert(session.core, item)
				end
			end
		end
	end
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, false)
end

local function restoreCoreGui()
	for _, item in session.core or {} do
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, item, true)
	end
end

-- Effects -------------------------------------------------------------------------------------

local function applyFilter()
	if not session then
		return
	end
	if not filterAllowed(filterIndex) then
		filterIndex = PhotoRig.Cycle(#FILTERS, filterIndex, 1, filterAllowed)
	end
	local def = FILTERS[filterIndex] or FILTERS[1]
	local color, bloom = session.color, session.bloom
	color.Brightness = def.brightness or 0
	color.Contrast = def.contrast or 0
	color.Saturation = def.saturation or 0
	color.TintColor = if def.tint then Color3.fromHex(def.tint) else Color3.new(1, 1, 1)
	local b = def.bloom
	bloom.Enabled = b ~= nil and not lowGraphics()
	if b then
		bloom.Intensity = b.intensity
		bloom.Size = b.size
		bloom.Threshold = b.threshold
	end
end

local function applyDepth()
	if not session then
		return
	end
	local depth = session.depth
	local distance = math.clamp(session.focusDistance or session.rig.distance, 0, DEPTH.maxFocus)
	depth.Enabled = depthOn and not lowGraphics()
	depth.FocusDistance = distance
	depth.InFocusRadius = PhotoRig.FocusRadius(DEPTH, distance)
end

local function makeEffects()
	session.color = Instance.new("ColorCorrectionEffect")
	session.color.Name = "PhotoModeColor"
	session.color.Parent = Lighting
	session.bloom = Instance.new("BloomEffect")
	session.bloom.Name = "PhotoModeBloom"
	session.bloom.Enabled = false
	session.bloom.Parent = Lighting
	session.depth = Instance.new("DepthOfFieldEffect")
	session.depth.Name = "PhotoModeDepth"
	session.depth.FarIntensity = DEPTH.farIntensity
	session.depth.NearIntensity = DEPTH.nearIntensity
	session.depth.Enabled = false
	session.depth.Parent = Lighting
	applyFilter()
	applyDepth()
end

-- Camera --------------------------------------------------------------------------------------

local function characterRoot(): BasePart?
	local character = ctx.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function focusPoint(): Vector3
	local rig = session.rig
	return session.anchor + Vector3.new(rig.x, rig.y, rig.z)
end

local function collide(focus: Vector3, eye: Vector3): Vector3
	local offset = eye - focus
	local length = offset.Magnitude
	if length < 1e-3 then
		return eye
	end
	local hit = workspace:Raycast(focus, offset, session.rayParams)
	if hit then
		local reach = math.max(0.5, (hit.Position - focus).Magnitude - CAM.collisionMargin)
		if reach < length then
			return focus + offset.Unit * reach
		end
	end
	return eye
end

local function held(key: Enum.KeyCode): number
	return if session.keys[key] then 1 else 0
end

local function applyHeld(dt: number)
	local rig, sticks = session.rig, session.sticks
	local right = held(Enum.KeyCode.D) - held(Enum.KeyCode.A) + sticks.moveX
	local forward = held(Enum.KeyCode.W) - held(Enum.KeyCode.S) + sticks.moveY
	local up = held(Enum.KeyCode.E) - held(Enum.KeyCode.Q)
	if right ~= 0 or forward ~= 0 or up ~= 0 then
		local step = CAM.panSpeed * dt
		PhotoRig.Pan(rig, CAM, right * step, up * step, forward * step)
	end
	local lookX = held(Enum.KeyCode.Right) - held(Enum.KeyCode.Left) + sticks.lookX
	local lookY = held(Enum.KeyCode.Up) - held(Enum.KeyCode.Down) + sticks.lookY
	if lookX ~= 0 or lookY ~= 0 then
		local step = CAM.orbitSpeed * dt
		PhotoRig.Orbit(rig, CAM, -lookX * step, -lookY * step)
	end
	local zoom = held(Enum.KeyCode.F) - held(Enum.KeyCode.R) + sticks.zoomOut - sticks.zoomIn
	if zoom ~= 0 then
		PhotoRig.Zoom(rig, CAM, math.exp(zoom * CAM.zoomSpeed * dt * math.log(2)))
	end
end

local function renderStep(dt: number)
	if not session then
		return
	end
	applyHeld(dt)
	local focus = focusPoint()
	local ex, ey, ez = PhotoRig.Eye(session.rig)
	local eye = collide(focus, focus + Vector3.new(ex, ey, ez))
	local target = CFrame.lookAt(eye, focus)
	local shown = session.shown
	if shown and CAM.smoothing > 0 and not reducedMotion() then
		shown = shown:Lerp(target, 1 - math.exp(-CAM.smoothing * dt))
	else
		shown = target
	end
	session.shown = shown
	local camera = session.camera.inst
	camera.CFrame = shown
	camera.Focus = CFrame.new(focus)
	if not session.focusDistance then
		applyDepth() -- follows the focus point until the first tap
	end
end

local function takeCamera()
	local camera = workspace.CurrentCamera
	session.camera = {
		inst = camera,
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		Focus = camera.Focus,
		FieldOfView = camera.FieldOfView,
	}
	local root = characterRoot()
	local anchor = camera.CFrame.Position + camera.CFrame.LookVector * CAM.startDistance
	if root then
		anchor = root.Position + Vector3.new(0, 1.5, 0) -- about chest height
	end
	session.anchor = anchor
	local offset = camera.CFrame.Position - anchor
	session.rig = PhotoRig.FromOffset(CAM, offset.X, offset.Y, offset.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if ctx.Player.Character then { ctx.Player.Character } else {}
	params.IgnoreWater = true
	params.RespectCanCollide = true
	session.rayParams = params
	session.shown = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, renderStep)
end

local function giveCameraBack()
	RunService:UnbindFromRenderStep(RENDER_NAME)
	local saved = session.camera
	if not saved then
		return
	end
	local camera = saved.inst
	-- One property at a time, CameraType last, so the camera scripts resume from the old view.
	for _, prop in { "FieldOfView", "CameraSubject", "CFrame", "Focus", "CameraType" } do
		local value = saved[prop]
		if value ~= nil then
			pcall(function()
				(camera :: any)[prop] = value
			end)
		end
	end
end

-- Input ---------------------------------------------------------------------------------------

local function command(name: string)
	if not session then
		return
	end
	if name == "exit" then
		ctx.Router:Close(SCREEN)
	elseif name == "focus" then
		-- The viewport centre in input space (below the top bar inset), as a tap there would report.
		local centre = session.camera.inst.ViewportSize / 2 - GuiService:GetGuiInset()
		if PhotoMode:FocusAt(centre) and session.api and session.api.Focused then
			session.api.Focused(centre)
		end
	elseif session.api and session.api.Command then
		session.api.Command(name)
	end
end

local function busy(): boolean
	return session ~= nil and session.api ~= nil and session.api.Busy ~= nil and session.api.Busy() == true
end

local function onHeldKey(_, state: Enum.UserInputState, input: InputObject)
	if not session then
		return Enum.ContextActionResult.Pass
	end
	session.keys[input.KeyCode] = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	return Enum.ContextActionResult.Sink
end

local function onSunk()
	return if session then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

local function commandAction(name: string)
	return function(_, state: Enum.UserInputState)
		if not session or busy() then
			return Enum.ContextActionResult.Pass -- a photo card is up: its buttons get A, the D-pad and B
		end
		if state == Enum.UserInputState.Begin then
			task.spawn(command, name)
		end
		return Enum.ContextActionResult.Sink
	end
end

local function bindActions()
	ContextActionService:BindActionAtPriority("PhotoModeHeld", onHeldKey, false, PRIORITY, table.unpack(HELD_KEYS))
	ContextActionService:BindActionAtPriority("PhotoModeSink", onSunk, false, PRIORITY, table.unpack(SUNK))
	for action, spec in COMMANDS do
		ContextActionService:BindActionAtPriority(action, commandAction(spec[2]), false, PRIORITY, table.unpack(spec[1]))
	end
end

local function unbindActions()
	ContextActionService:UnbindAction("PhotoModeHeld")
	ContextActionService:UnbindAction("PhotoModeSink")
	for action in COMMANDS do
		ContextActionService:UnbindAction(action)
	end
end

local function xy(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function tap(position: Vector2)
	if not session then
		return
	end
	local api = session.api
	if api and api.Tap and api.Tap(position) then
		return -- the screen used it (sticker placed, toolbar shown)
	end
	if PhotoMode:FocusAt(position) and api and api.Focused then
		api.Focused(position)
	end
end

local function orbitBy(delta: Vector2)
	PhotoRig.Orbit(session.rig, CAM, -delta.X * CAM.orbitPerPixel, delta.Y * CAM.orbitPerPixel)
end

local function panBy(delta: Vector2)
	local scale = CAM.panPerPixel * session.rig.distance
	PhotoRig.Pan(session.rig, CAM, -delta.X * scale, 0, delta.Y * scale)
end

local function touchCount(): number
	local n = 0
	for _ in session.touches do
		n += 1
	end
	return n
end

local function onTouchMoved(input: InputObject)
	local touches = session.touches
	local entry = touches[input]
	local position = xy(input)
	local delta = position - entry.pos
	entry.moved += delta.Magnitude
	local count = touchCount()
	if count == 1 then
		orbitBy(delta)
	elseif count >= 2 then
		local other
		for key, value in touches do
			if key ~= input then
				other = value
				break
			end
		end
		local before, after = (entry.pos + other.pos) / 2, (position + other.pos) / 2
		panBy(after - before)
		local oldSpan, newSpan = (entry.pos - other.pos).Magnitude, (position - other.pos).Magnitude
		if oldSpan > 1 and newSpan > 1 then
			PhotoRig.Zoom(session.rig, CAM, oldSpan / newSpan)
		end
	end
	entry.pos = position
end

local function onSurfaceBegan(input: InputObject)
	if not session then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		session.touches[input] = { pos = xy(input), t0 = os.clock(), moved = 0 }
		if touchCount() > 1 then
			session.multi = true
		end
	elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
		session.mouse = { button = kind, last = xy(input), t0 = os.clock(), moved = 0 }
	end
end

local function onSurfaceChanged(input: InputObject)
	if session and input.UserInputType == Enum.UserInputType.MouseWheel then
		PhotoRig.Zoom(session.rig, CAM, 1 - math.clamp(input.Position.Z, -1, 1) * CAM.wheelStep)
	end
end

local function onInputChanged(input: InputObject)
	if not session then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		if session.touches[input] then
			onTouchMoved(input)
		end
	elseif kind == Enum.UserInputType.MouseMovement then
		local mouse = session.mouse
		if mouse then
			local position = xy(input)
			local delta = position - mouse.last
			mouse.last = position
			mouse.moved += delta.Magnitude
			if mouse.button == Enum.UserInputType.MouseButton1 then
				orbitBy(delta)
			else
				panBy(delta)
			end
		end
	elseif string.match(kind.Name, "^Gamepad%d$") then
		local sticks = session.sticks
		local key = input.KeyCode
		if key == Enum.KeyCode.Thumbstick1 then
			sticks.moveX = PhotoRig.Deadzone(input.Position.X, CAM.deadzone)
			sticks.moveY = PhotoRig.Deadzone(input.Position.Y, CAM.deadzone)
		elseif key == Enum.KeyCode.Thumbstick2 then
			sticks.lookX = PhotoRig.Deadzone(input.Position.X, CAM.deadzone)
			sticks.lookY = PhotoRig.Deadzone(input.Position.Y, CAM.deadzone)
		elseif key == Enum.KeyCode.ButtonR2 then
			sticks.zoomIn = PhotoRig.Deadzone(input.Position.Z, CAM.deadzone)
		elseif key == Enum.KeyCode.ButtonL2 then
			sticks.zoomOut = PhotoRig.Deadzone(input.Position.Z, CAM.deadzone)
		end
	end
end

local function onInputEnded(input: InputObject)
	if not session then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch then
		local entry = session.touches[input]
		if entry then
			session.touches[input] = nil
			local single = not session.multi
			if touchCount() == 0 then
				session.multi = false
			end
			if single and PhotoRig.IsTap(entry.moved, os.clock() - entry.t0) then
				tap(entry.pos)
			end
		end
	elseif kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.MouseButton2 then
		local mouse = session.mouse
		if mouse and mouse.button == kind then
			session.mouse = nil
			if kind == Enum.UserInputType.MouseButton1 and PhotoRig.IsTap(mouse.moved, os.clock() - mouse.t0) then
				tap(xy(input))
			end
		end
	elseif string.match(kind.Name, "^Gamepad%d$") then
		local sticks, key = session.sticks, input.KeyCode
		if key == Enum.KeyCode.Thumbstick1 then
			sticks.moveX, sticks.moveY = 0, 0
		elseif key == Enum.KeyCode.Thumbstick2 then
			sticks.lookX, sticks.lookY = 0, 0
		elseif key == Enum.KeyCode.ButtonR2 then
			sticks.zoomIn = 0
		elseif key == Enum.KeyCode.ButtonL2 then
			sticks.zoomOut = 0
		end
	end
end

-- Entry keys: P and D-pad up when nothing is open (UserInputService, so nothing is bound while off).
local function onEntryInput(input: InputObject, processed: boolean)
	if processed or session then
		return
	end
	local key = input.KeyCode
	if key ~= Enum.KeyCode.P and key ~= Enum.KeyCode.DPadUp then
		return
	end
	if ctx.Router:Current() ~= nil or Focus.top() ~= nil or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if ctx.Router:Has(SCREEN) then
		ctx.Router:Open(SCREEN)
	end
end

-- Capture -------------------------------------------------------------------------------------

local function captureService(): Instance?
	local ok, service = pcall(function()
		return game:GetService("CaptureService")
	end)
	return if ok then service else nil
end

local function hasMethod(service: Instance?, name: string): boolean
	if not service then
		return false
	end
	local ok, member = pcall(function()
		return (service :: any)[name]
	end)
	return ok and type(member) == "function"
end

-- Public --------------------------------------------------------------------------------------

function PhotoMode:IsActive(): boolean
	return session ~= nil
end

function PhotoMode:Toggle()
	ctx.Router:Toggle(SCREEN)
end

function PhotoMode:LowGraphics(): boolean
	return lowGraphics()
end

function PhotoMode:ReducedMotion(): boolean
	return reducedMotion()
end

function PhotoMode:Begin(api)
	if session then
		self:End()
	end
	local director = ctx:GetController("CameraDirector") -- glow-up N: never start mid-shot; end it first
	if director then
		director:Stop()
	end
	local current = ctx.Router:Current()
	if current and current ~= SCREEN then
		ctx.Router:Close(current)
	end
	session = {
		api = api,
		hidden = {},
		conns = {},
		keys = {},
		touches = {},
		multi = false,
		mouse = nil,
		sticks = { moveX = 0, moveY = 0, lookX = 0, lookY = 0, zoomIn = 0, zoomOut = 0 },
		focusDistance = nil,
		overlay = ctx.UI.Overlay.Visible,
	}
	hideGameUi(api and api.Root)
	takeCamera()
	makeEffects()
	bindActions()
	local surface = api and api.Surface
	if surface then
		table.insert(session.conns, surface.InputBegan:Connect(onSurfaceBegan))
		table.insert(session.conns, surface.InputChanged:Connect(onSurfaceChanged))
	end
	table.insert(session.conns, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(session.conns, UserInputService.InputEnded:Connect(onInputEnded))
	table.insert(
		session.conns,
		ctx.Router.Opened:Connect(function(name: string)
			if name ~= SCREEN and session then
				ctx.Router:Close(SCREEN) -- a menu or prompt opened: give the game back first
			end
		end)
	)
	table.insert(
		session.conns,
		ctx.Store:Observe("profile.Settings", function()
			applyFilter()
			applyDepth()
		end)
	)
end

function PhotoMode:End()
	if not session then
		return
	end
	local ending = session
	for _, conn in ending.conns do
		conn:Disconnect()
	end
	unbindActions()
	giveCameraBack()
	for _, effect in { ending.color, ending.bloom, ending.depth } do
		if effect then
			effect:Destroy()
		end
	end
	ctx.UI.Overlay.Visible = ending.overlay
	restoreHidden()
	restoreCoreGui()
	session = nil
end

function PhotoMode:SetClean(on: boolean)
	if session then
		ctx.UI.Overlay.Visible = if on then false else session.overlay
	end
end

function PhotoMode:Filter()
	return FILTERS[filterIndex] or FILTERS[1]
end

function PhotoMode:StepFilter(step: number)
	filterIndex = PhotoRig.Cycle(#FILTERS, filterIndex, step, filterAllowed)
	applyFilter()
	return self:Filter()
end

function PhotoMode:DepthAvailable(): boolean
	return not lowGraphics()
end

function PhotoMode:DepthOn(): boolean
	return depthOn and not lowGraphics()
end

function PhotoMode:SetDepth(on: boolean)
	depthOn = on == true
	applyDepth()
end

function PhotoMode:FocusAt(position: Vector2): boolean
	if not session then
		return false
	end
	local camera = session.camera.inst
	local ray = camera:ScreenPointToRay(position.X, position.Y)
	local hit = workspace:Raycast(ray.Origin, ray.Direction.Unit * DEPTH.maxFocus, session.rayParams)
	if not hit then
		return false
	end
	session.focusDistance = (hit.Position - camera.CFrame.Position).Magnitude
	applyDepth()
	return true
end

-- The animator gets "trick" when it knows that state, else "happy" (Play falls back to idle on
-- a state it does not know, which is how an animator without the trick clip is recognised).
local function strikePose(animator)
	local ok = pcall(animator.Play, animator, "trick")
	if not ok or (animator :: any)._state ~= "trick" then
		animator:Play("happy")
	end
end

function PhotoMode:Pose(): number
	if not session then
		return 0
	end
	local world = ctx:GetController("World")
	local list = {}
	if world and world.OwnMonstersNear then
		list = world:OwnMonstersNear(focusPoint(), PhotoConfig.PoseRadius)
	end
	for i, monster in list do
		task.delay((i - 1) * 0.06, function()
			if monster.animator then
				strikePose(monster.animator)
			end
			if i <= 3 and monster.model then
				Voices.Cry(monster.model, "happy")
			end
		end)
	end
	return #list
end

function PhotoMode:Capabilities()
	if not capabilities then
		local service = captureService()
		capabilities = {
			capture = hasMethod(service, "CaptureScreenshot"),
			save = hasMethod(service, "PromptSaveCapturesToGallery"),
			share = hasMethod(service, "PromptShareCapture"),
		}
	end
	return capabilities
end

function PhotoMode:Capture(done: (string?) -> ())
	local service = captureService()
	if not self:Capabilities().capture or not service then
		task.spawn(done, nil)
		return
	end
	local finished = false
	local function finish(contentId: any)
		if finished then
			return
		end
		finished = true
		done(if type(contentId) == "string" and contentId ~= "" then contentId else nil)
	end
	local ok = pcall(function()
		(service :: any):CaptureScreenshot(function(contentId)
			task.spawn(finish, contentId)
		end)
	end)
	if not ok then
		finish(nil)
		return
	end
	task.delay(CAPTURE_TIMEOUT, finish, nil)
end

function PhotoMode:Save(contentId: string, done: (boolean) -> ())
	local service = captureService()
	if not self:Capabilities().save or not service then
		task.spawn(done, false)
		return
	end
	local ok = pcall(function()
		(service :: any):PromptSaveCapturesToGallery({ contentId }, function(results)
			task.spawn(done, type(results) == "table" and results[contentId] == true)
		end)
	end)
	if not ok then
		task.spawn(done, false)
	end
end

function PhotoMode:Share(contentId: string, done: (boolean) -> ())
	local service = captureService()
	if not self:Capabilities().share or not service then
		task.spawn(done, false)
		return
	end
	local ok = pcall(function()
		(service :: any):PromptShareCapture(contentId, "", function()
			task.spawn(done, true)
		end, function()
			task.spawn(done, false)
		end)
	end)
	if not ok then
		task.spawn(done, false)
	end
end

function PhotoMode:Rig()
	if not session then
		return nil
	end
	local rig = session.rig
	return { yaw = rig.yaw, pitch = rig.pitch, distance = rig.distance, x = rig.x, y = rig.y, z = rig.z }
end

-- Lifecycle -----------------------------------------------------------------------------------

function PhotoMode.Init(context)
	ctx = context
	UserInputService.InputBegan:Connect(onEntryInput)
end

function PhotoMode.Start() end

return PhotoMode
