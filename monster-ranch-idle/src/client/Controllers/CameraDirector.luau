--[[
	CameraDirector (glow-up N): borrows the camera for a short shot, then hands it back exactly as
	it was (CameraType, CameraSubject, CFrame, Focus, FieldOfView; CameraType last, like PhotoMode).

		CameraDirector:Play(shot) -> ()          queue a shot; one plays at a time
		    shot.position   Vector3: the subject's base (feet) point
		    shot.height     studs tall (framing: Cinema's rig language, Logic/Cinematic.Frame without it)
		    shot.run        fn(handle) run in the shot's own thread once the glide in has started;
		                    the shot ends when it returns (default: hold `shot.hold` seconds)
		    shot.onDone     fn(ran: boolean) always called once: ran = false when the shot could not
		                    start (see CanStart) and nothing was shown
		    shot.stage      glow-up V (a fight on the 3D battle stage): cuts in and out instead of
		                    gliding, no letterbox / tap catcher (the caller draws its own), and a
		                    Router screen being open neither stops it starting nor cuts it short
		handle:Wait(seconds) -> skipped           yields; returns at once (true) after a skip
		handle:Skipped() -> boolean
		handle:Frame(position, height, seconds?)  glide to frame another subject
		handle:Look(eye, at, seconds?)            glide to an explicit eye and look point (0 = cut)
		handle:Aborted() -> boolean               the camera was taken back (PhotoMode, a mount...)
		handle.reduced                            reduced motion (cuts, no shake); handle.low = lowGraphics
		CameraDirector:Skip()                     the playing shot hurries to its end (any tap does it)
		CameraDirector:Stop()                     ends every shot now and cuts back (PhotoMode:Begin)
		CameraDirector:IsBusy() -> boolean        a shot is playing or the camera is not handed back yet
		CameraDirector:CanStart(stage?) -> boolean   the world is the player's to look at: no PhotoMode,
		                                          no Router screen (unless stage), no UI/Focus modal,
		                                          not riding

	While a shot plays: letterbox bars and a full-screen tap catcher with "Tap to skip" in UI.Top
	(taps do not reach the world), the HUD layer hidden. A Router screen opening, PhotoMode or
	mounting a monster mid-shot cuts straight back. Reduced motion (Settings.lowGraphics,
	Settings.reducedMotion (R2-A11Y), UI/Anim.enabled == false, GuiService.ReducedMotionEnabled)
	cuts instead of gliding.

	Foundry (wave 1g): the framing comes from the Cinema package through ctx.Foundry: the numbers
	are Cinema.profile("monster-ranch").rig (fov, the 0.42 fill band, pitch, distances, lookUp,
	glideIn / glideOut), the eye and look point are Cinema.Language's rig frame, and the glide's
	curve is Cinema.Ease ("smoother"). The glide's timing, the chrome and the hand-back stay here
	(NotAdopted). Without the package it warns once and frames with Config.Cinematics.Camera and
	Logic/Cinematic, as before. tests/specs/CameraCompat.spec proves both paths equal the old
	controller (tests/runtime/OldCameraDirector.luau) bit for bit, frame by frame.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Cinematic = require(Shared.Logic.Cinematic)
local Tuning = require(Shared.Config.Cinematics)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local Focus = require(UI.Focus)

local New = Create.New
local CAM = Tuning.Camera -- the fallback's numbers (no Cinema package)
local RENDER_NAME = "CameraDirector"
local BAR = 0.09 -- letterbox bar height, fraction of the screen

local CameraDirector = {
	Name = "CameraDirector",
	Dependencies = {},
	-- What stays this controller's own, and why (CameraCompat.spec checks the reasons).
	NotAdopted = {
		glide = "the glide's clock (os.clock, a render step, Heartbeat waits), skip, abort and the hand-back: the package solves poses and has no scheduler",
		fieldOfView = "the director never sets FieldOfView, it keeps the player's and restores it; rig.fov only sizes the framing distance",
		look = "Handle:Look aims at an explicit eye and look point (BattleStage), so there is no framing maths to move",
		chrome = "letterbox bars, the tap-to-skip catcher, the HUD hiding, the whoosh and skip input are Ranch UI the package does not know",
		nonFinite = "a NaN or infinite subject, height or camera point keeps Logic/Cinematic.Frame: the package swaps such input for defaults, the old maths does not",
		photoMode = "Cinema.PhotoMode is not wired: Controllers/PhotoMode stays the Ranch's own, its ideas are proposals only",
		rails = "Cinema.Rails and its moment director are not wired: Cinematics, Celebrate and BattleStage script their own shots",
		focus = "Cinema.Focus depth of field is not wired: a shot draws no DepthOfFieldEffect today, so adding one would change the look",
		recorder = "Cinema.Recorder is not wired: it is a capture tool, and the shots record nothing today",
	},
}

local ctx
local lensState: any = nil -- { lang, rig, ease } with the Cinema package, false without
local queue = {}
local working = false
local saved = nil -- the player's camera while we hold it
local current = nil -- the playing shot's state
local rig = nil -- { fromCF, toCF, t0, glide, fov }
local chrome = {}
local hudWasVisible: boolean? = nil
local inputConn: RBXScriptConnection? = nil
local bound = false

local function lowGraphics(): boolean
	local settings = ctx.Store:Get("profile.Settings")
	return type(settings) == "table" and settings.lowGraphics == true
end

-- R2-A11Y: Settings.reducedMotion (independent of Low graphics).
local function reducedMotionSetting(): boolean
	local settings = ctx.Store:Get("profile.Settings")
	return type(settings) == "table" and settings.reducedMotion == true
end

local function reducedMotion(): boolean
	if not Anim.enabled or lowGraphics() or reducedMotionSetting() then
		return true
	end
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

local function riding(): boolean
	local character = ctx.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:FindFirstChild("Mount") ~= nil
end

local function photoActive(): boolean
	local photo = ctx:GetController("PhotoMode")
	return photo ~= nil and photo:IsActive()
end

local function mayContinue(stage: boolean?): boolean
	return not photoActive() and (stage == true or ctx.Router:Current() == nil) and not riding()
end

-- The Cinema package's Ranch camera language, or nil (warned once) when it is not vendored: the
-- built-in Config.Cinematics.Camera and Logic/Cinematic run instead.
local function lens(): any
	if lensState == nil then
		local f = ctx and ctx.Foundry
		local lib = f and f.packages and f.packages.Cinema
		if lib then
			local profile = lib.profile("monster-ranch")
			lensState = { lang = lib.Language.new(profile), rig = profile.rig, ease = lib.Ease }
		else
			lensState = false
			warn("[CameraDirector] the Foundry Cinema package is not vendored; the built-in Config.Cinematics.Camera framing runs")
		end
	end
	return lensState or nil
end

-- The camera numbers (lookUp, glideIn, glideOut): the package's rig or Config.Cinematics.Camera.
local function cam(): any
	local L = lens()
	return if L then L.rig else CAM
end

local function ease(a: number): number
	local L = lens()
	if L then
		return L.ease.apply(L.rig.ease, a)
	end
	return Cinematic.Ease(a)
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function framing(position: Vector3, height: number, from: Vector3): CFrame
	local L = lens()
	if
		L
		and finite(height)
		and finite(position.X)
		and finite(position.Y)
		and finite(position.Z)
		and finite(from.X)
		and finite(from.Y)
		and finite(from.Z)
	then
		local pose = L.lang.frame({
			position = { x = position.X, y = position.Y, z = position.Z },
			height = height,
			from = { x = from.X, y = from.Y, z = from.Z },
		})
		local eye, at = pose.position, pose.lookAt
		return CFrame.lookAt(Vector3.new(eye.x, eye.y, eye.z), Vector3.new(at.x, at.y, at.z))
	end
	local ex, ey, ez, lx, ly, lz = Cinematic.Frame(CAM, position.X, position.Y, position.Z, height, from.X, from.Y, from.Z)
	return CFrame.lookAt(Vector3.new(ex, ey, ez), Vector3.new(lx, ly, lz))
end

-- Chrome ------------------------------------------------------------------------------------

local function buildChrome()
	if chrome.root then
		return
	end
	local root = New("Frame", {
		Name = "Cinematic",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 40,
		Parent = ctx.UI.Top,
	})
	chrome.root = root
	chrome.top = New("Frame", {
		Name = "BarTop",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, BAR),
		ZIndex = 41,
		Parent = root,
	})
	chrome.bottom = New("Frame", {
		Name = "BarBottom",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, BAR),
		ZIndex = 41,
		Parent = root,
	})
	chrome.catcher = New("TextButton", {
		Name = "TapToSkip",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 42,
		Selectable = false, -- a tap target only; a pad skips with A or B
		Parent = root,
		Activated = function()
			CameraDirector:Skip()
		end,
	})
	chrome.hint = Create.Text({
		Text = "Tap to skip",
		TextSize = Theme.TextSize.Body,
		TextColor3 = Theme.Colors.White,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.fromOffset(300, 28),
		ZIndex = 43,
		Parent = root,
	})
end

local function showChrome(bare: boolean?)
	if bare then
		-- A stage shot draws its own chrome; only the HUD steps aside.
		local hud = ctx.UI.Hud
		if hud and hudWasVisible == nil then
			hudWasVisible = hud.Visible
			hud.Visible = false
		end
		return
	end
	buildChrome()
	chrome.root.Visible = true
	chrome.hint.Visible = true
	if not reducedMotion() then
		chrome.top.Position = UDim2.fromScale(0, -BAR)
		chrome.bottom.Position = UDim2.fromScale(0, 1 + BAR)
		Anim.tween(chrome.top, { Position = UDim2.fromScale(0, 0) }, 0.35)
		Anim.tween(chrome.bottom, { Position = UDim2.fromScale(0, 1) }, 0.35)
	else
		chrome.top.Position = UDim2.fromScale(0, 0)
		chrome.bottom.Position = UDim2.fromScale(0, 1)
	end
	local hud = ctx.UI.Hud
	if hud and hudWasVisible == nil then
		hudWasVisible = hud.Visible
		hud.Visible = false
	end
	if not inputConn then
		inputConn = UserInputService.InputBegan:Connect(function(input: InputObject)
			local kind, key = input.UserInputType, input.KeyCode
			if
				kind == Enum.UserInputType.Touch
				or kind == Enum.UserInputType.MouseButton1
				or key == Enum.KeyCode.ButtonA
				or key == Enum.KeyCode.ButtonB
				or key == Enum.KeyCode.Space
				or key == Enum.KeyCode.Return
			then
				CameraDirector:Skip()
			end
		end)
	end
end

local function hideChrome()
	if chrome.root then
		chrome.root.Visible = false
	end
	local hud = ctx.UI.Hud
	if hud and hudWasVisible ~= nil then
		hud.Visible = hudWasVisible
	end
	hudWasVisible = nil
	if inputConn then
		inputConn:Disconnect()
		inputConn = nil
	end
end

-- The camera --------------------------------------------------------------------------------

local function step()
	local camera = workspace.CurrentCamera
	if not (saved and camera and rig) then
		return
	end
	if current and not current.aborted and not mayContinue(current.stage) then
		CameraDirector:Stop()
		return
	end
	local a = if rig.glide <= 0 then 1 else (os.clock() - rig.t0) / rig.glide
	local cf = rig.fromCF:Lerp(rig.toCF, ease(a))
	camera.CFrame = cf
	camera.Focus = CFrame.new(rig.focus)
end

local function bind()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, step)
end

local function unbind()
	if bound then
		bound = false
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end
end

local function glideTo(toCF: CFrame, focus: Vector3, seconds: number)
	local camera = workspace.CurrentCamera
	rig = {
		fromCF = if camera then camera.CFrame else toCF,
		toCF = toCF,
		focus = focus,
		t0 = os.clock(),
		glide = if reducedMotion() then 0 else seconds,
	}
	step()
end

local function takeCamera(bare: boolean?): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	saved = {
		inst = camera,
		CameraType = camera.CameraType,
		CameraSubject = camera.CameraSubject,
		CFrame = camera.CFrame,
		Focus = camera.Focus,
		FieldOfView = camera.FieldOfView,
	}
	camera.CameraType = Enum.CameraType.Scriptable
	bind()
	showChrome(bare)
	return true
end

local function giveCameraBack()
	unbind()
	rig = nil
	hideChrome()
	local keep = saved
	saved = nil
	if not keep then
		return
	end
	-- One property at a time, CameraType last, so the camera scripts resume from the old view.
	for _, prop in { "FieldOfView", "CameraSubject", "CFrame", "Focus", "CameraType" } do
		local value = keep[prop]
		if value ~= nil then
			pcall(function()
				(keep.inst :: any)[prop] = value
			end)
		end
	end
end

-- Shots -------------------------------------------------------------------------------------

local Handle = {}
Handle.__index = Handle

function Handle:Skipped(): boolean
	return self.state.skipped
end

function Handle:Wait(seconds: number): boolean
	local deadline = os.clock() + seconds
	while not self.state.skipped and os.clock() < deadline do
		RunService.Heartbeat:Wait() -- a frame (task.wait() would not advance the clock in the Lune mock)
	end
	return self.state.skipped
end

function Handle:Frame(position: Vector3, height: number, seconds: number?)
	if self.state.aborted or not saved then
		return
	end
	local camera = workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else position + Vector3.new(0, 10, 20)
	local cf = framing(position, height, from)
	glideTo(cf, position + Vector3.new(0, height * cam().lookUp, 0), seconds or cam().glideIn)
end

function Handle:Look(eye: Vector3, at: Vector3, seconds: number?)
	if self.state.aborted or not saved then
		return
	end
	glideTo(CFrame.lookAt(eye, at), at, seconds or cam().glideIn)
end

function Handle:Aborted(): boolean
	return self.state.aborted
end

local function playOne(shot)
	local stage = shot.stage == true
	local state = { skipped = false, aborted = false, stage = stage }
	current = state
	local handle = setmetatable({ state = state, reduced = reducedMotion(), low = lowGraphics() }, Handle)
	if not saved then
		takeCamera(stage)
		if not reducedMotion() and not stage then
			ctx:Sound("Whoosh")
		end
	end
	handle:Frame(shot.position, shot.height or 4, if stage then 0 else nil)
	local ok, err = xpcall(function()
		if shot.run then
			shot.run(handle)
		else
			handle:Wait(shot.hold or 1.5)
		end
	end, debug.traceback)
	if not ok then
		warn("[CameraDirector] shot failed: " .. tostring(err))
	end
	current = nil
	return state
end

local function finish(shot, ran: boolean)
	if shot.onDone then
		local ok, err = xpcall(shot.onDone, debug.traceback, ran)
		if not ok then
			warn("[CameraDirector] onDone failed: " .. tostring(err))
		end
	end
end

local function work()
	working = true
	local cutHome = false
	while #queue > 0 do
		local shot = table.remove(queue, 1)
		cutHome = shot.stage == true
		if saved or CameraDirector:CanStart(shot.stage) then
			local state = playOne(shot)
			finish(shot, true)
			if state.aborted then
				giveCameraBack()
			end
		else
			finish(shot, false)
		end
	end
	if saved then
		-- Glide home, then hand the camera back.
		local keep = saved
		glideTo(keep.CFrame, keep.Focus.Position, if cutHome then 0 else cam().glideOut)
		local deadline = os.clock() + (if rig then rig.glide else 0)
		while saved == keep and os.clock() < deadline do
			RunService.Heartbeat:Wait() -- a frame (task.wait() would not advance the clock in the Lune mock)
		end
		if saved == keep then
			giveCameraBack()
		end
	end
	working = false
	if #queue > 0 then
		task.spawn(work)
	end
end

function CameraDirector:Play(shot)
	table.insert(queue, shot)
	if not working then
		task.spawn(work)
	end
end

function CameraDirector:Skip()
	if current then
		current.skipped = true
	end
end

function CameraDirector:Stop()
	if current then
		current.skipped = true
		current.aborted = true
	end
	local dropped = table.clone(queue)
	table.clear(queue)
	giveCameraBack()
	for _, shot in dropped do
		finish(shot, false)
	end
end

function CameraDirector:IsBusy(): boolean
	return working or saved ~= nil
end

function CameraDirector:CanStart(stage: boolean?): boolean
	return workspace.CurrentCamera ~= nil and mayContinue(stage) and Focus.top() == nil
end

function CameraDirector:ReducedMotion(): boolean
	return reducedMotion()
end

function CameraDirector.Init(context)
	ctx = context
end

function CameraDirector.Start() end

return CameraDirector
