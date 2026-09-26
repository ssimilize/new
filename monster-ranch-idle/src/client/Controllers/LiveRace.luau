--[[
	LiveRace controller (glow-up LR): live races round the track, drawn in the world.

	Joining happens from the Racing screen ("Join Live Race", while riding an Adult); everything
	after that is this controller, over whatever screen is open:

	  lobby      a small banner (riders in, seconds left, Leave)
	  countdown  "3 2 1 GO!" (global.LiveRace.goAt, shared by every racer)
	  running    takes over the local rider: Logic/LiveRace's rider prediction moves the character
	             (root part anchored and driven by script — a rail, not free physics; the server
	             is the one that matters, see Systems/LiveRace's header) along the track, a chase
	             camera follows (saved and restored exactly, like CameraDirector), and the rider's
	             position is reported every Config.LiveRace.ReportEvery seconds. Space/W/Up or pad
	             Ⓐ/D-pad up jumps (hurdles), Shift/B or pad RB/RT boosts (meter, refilled by
	             drafting or a hard turn through a curve — Logic.IsCurve + DriftSteer).
	  podium     the field in order for a few seconds (session.LiveRace.result)

	Racing gear (Systems/RaceGear) is drawn on every mount from global.RaceGear.here, not just
	while racing (see Riding's "Mount" model).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.LiveRace)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Button = require(UI.Components.Button)
local Widgets = require(UI.Components.Widgets)
local StoreKit = require(UI.Components.StoreKit)
local RaceTrack = require(script.Parent.Parent.Visuals.RaceTrack)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.LiveRace
local STICK_DEADZONE = 0.25

local LiveRace = {
	Name = "LiveRace",
	Dependencies = { "Riding" },
}

local ctx
local player = Players.LocalPlayer

-- Local rider prediction (see Logic/LiveRace header); nil when not taking over the character.
local rider = nil
local savedRoot = nil -- { anchored: boolean }
local savedCamera = nil -- { CameraType, CameraSubject, FieldOfView }
local reportAcc = 0
local held = { left = false, right = false }
local stickX = 0

-- HUD (built once; Stampede-style overlay on the Feedback layer).
local hud = {}
local podiumUntil = 0
local lastResultSeen = false

local function session()
	return StoreKit.tbl(ctx.Store, "session.LiveRace")
end

local function globalState()
	return StoreKit.tbl(ctx.Store, "global.LiveRace")
end

local function character(): Model?
	return player.Character
end

local function rootPart(): BasePart?
	local c = character()
	local p = c and c:FindFirstChild("HumanoidRootPart")
	return if p and p:IsA("BasePart") then p else nil
end

local function laneOf(g): number
	for _, r in g.racers or {} do
		if r.userId == player.UserId then
			return r.lane or 1
		end
	end
	return 1
end

-- Rider control ---------------------------------------------------------------------------------

local function takeCamera()
	if savedCamera then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	savedCamera = { CameraType = camera.CameraType, CameraSubject = camera.CameraSubject, FieldOfView = camera.FieldOfView }
	camera.CameraType = Enum.CameraType.Scriptable
end

local function releaseCamera()
	local camera = workspace.CurrentCamera
	if camera and savedCamera then
		camera.FieldOfView = savedCamera.FieldOfView
		camera.CameraSubject = savedCamera.CameraSubject
		camera.CameraType = savedCamera.CameraType
	end
	savedCamera = nil
end

local function takeControl(g)
	local speed = (StoreKit.tbl(ctx.Store, "session.Riding").speed or Cfg.ParSpeed) * Cfg.SpeedScale
	rider = Logic.NewRider(speed, Cfg.Lanes[laneOf(g)] or 0)
	local root = rootPart()
	if root then
		savedRoot = { anchored = root.Anchored }
		root.Anchored = true
	end
	reportAcc = 0
	takeCamera()
end

local function releaseControl()
	if not rider then
		return
	end
	rider = nil
	local root = rootPart()
	if root and savedRoot then
		root.Anchored = savedRoot.anchored
	end
	savedRoot = nil
	releaseCamera()
end

local function steerValue(): number
	local v = stickX
	if held.left then
		v -= 1
	end
	if held.right then
		v += 1
	end
	return math.clamp(v, -1, 1)
end

local function stepRider(dt: number, sess)
	local steer = steerValue()
	Logic.StepRider(rider, dt, steer)
	local x, z, dx, dz = Logic.Point(rider.progress, rider.lateral)
	local yaw = RaceTrack.Yaw(dx, dz)
	local y = Config.LiveRace.Track.center[2] + 3 + Logic.Hop(rider.air)
	local root = rootPart()
	if root then
		root.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
	end
	local camera = workspace.CurrentCamera
	if camera and savedCamera then
		local cam = Cfg.Camera
		local pos = Vector3.new(x, y, z) - Vector3.new(dx, 0, dz) * cam.back + Vector3.new(0, cam.up, 0)
		camera.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(cam.pitch, 0, 0)
		camera.FieldOfView = if rider.boost > 0 then cam.boostFov else cam.fov
	end
	reportAcc += dt
	if reportAcc >= Cfg.ReportEvery then
		reportAcc = 0
		local drift = math.abs(steer) >= Cfg.DriftSteer and Logic.IsCurve(rider.progress)
		local ok, res = ctx.Net:Request("LiveRace.Progress", { heat = sess.heat, x = x, z = z, drift = drift })
		if ok and type(res) == "table" and not res.accepted then
			rider.progress = tonumber(res.progress) or rider.progress
			local _, lateral = Logic.Project(tonumber(res.x) or x, tonumber(res.z) or z)
			rider.lateral = lateral
		end
	end
end

-- Input -------------------------------------------------------------------------------------

local function doJump()
	if not rider then
		return
	end
	local sess = session()
	if Logic.TryJump(rider) then
		ctx.Net:Request("LiveRace.Jump", { heat = sess.heat })
	end
end

local function doBoost()
	if not rider then
		return
	end
	local sess = session()
	if type(sess.heat) ~= "number" then
		return
	end
	local ok, res = ctx.Net:Request("LiveRace.Boost", { heat = sess.heat })
	if ok and type(res) == "table" then
		rider.boost = tonumber(res.seconds) or Cfg.BoostSeconds
	end
end

local function leaveHeat()
	StoreKit.request(ctx, "LiveRace.Leave")
end

-- HUD -----------------------------------------------------------------------------------------

local function buildHud()
	hud.root = New("Frame", {
		Name = "LiveRaceHud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 6,
		Parent = ctx.UI.Feedback,
	})
	hud.banner = New("Frame", {
		Name = "Lobby",
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(460, 64),
		Visible = false,
		Parent = hud.root,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(3, C.Gold, 0) })
	hud.bannerText = Create.Text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -140, 1, 0),
		Parent = hud.banner,
	})
	Button.new({
		Name = "LeaveRace",
		Text = "Leave",
		Color = C.Gray,
		Size = UDim2.fromOffset(100, 44),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Parent = hud.banner,
		OnClick = leaveHeat,
	})
	hud.countdown = Create.Text({
		Name = "Countdown",
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = 64,
		TextColor3 = C.White,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(300, 90),
		Visible = false,
		Parent = hud.root,
	})
	hud.race = New("Frame", {
		Name = "Race",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(300, 90),
		Visible = false,
		Parent = hud.root,
	})
	hud.raceText = Create.Text({
		Text = "",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Header,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = hud.race,
	})
	hud.meter = Widgets.Bar({
		Name = "Meter",
		Color = C.Purple,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = hud.race,
	})
	hud.podium = New("Frame", {
		Name = "Podium",
		BackgroundColor3 = C.Dark,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(360, 200),
		Visible = false,
		Parent = hud.root,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(3, C.Gold, 0) })
	hud.podiumText = Create.Text({
		Text = "",
		Font = Theme.Fonts.Body,
		TextSize = Theme.TextSize.Body,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 1, -24),
		Parent = hud.podium,
	})
end

-- An estimate for the HUD only (ghosts finish on their own clock; the server decides the real
-- order in Order() at settle time).
local function placeText(g, sess): string
	local ahead = 1
	for _, r in g.racers or {} do
		if r.userId ~= player.UserId and (r.finished or (r.progress or 0) > (sess.progress or 0)) then
			ahead += 1
		end
	end
	return string.format("%d%s", ahead, if ahead == 1 then "st" elseif ahead == 2 then "nd" elseif ahead == 3 then "rd" else "th")
end

local function podiumLines(results): string
	local lines = {}
	for _, r in results or {} do
		table.insert(
			lines,
			string.format("%d. %s%s", r.place, tostring(r.name), if r.dq then " (DQ)" elseif not r.time then " (DNF)" else "")
		)
	end
	return table.concat(lines, "\n")
end

local function refreshHud()
	local sess = session()
	local g = globalState()
	local inHeat = type(sess.heat) == "number"
	hud.root.Visible = inHeat or (type(sess.result) == "table" and os.clock() < podiumUntil)
	hud.banner.Visible = inHeat and (g.state == "lobby")
	hud.countdown.Visible = inHeat and g.state == "countdown"
	hud.race.Visible = inHeat and g.state == "running" and not sess.dq
	hud.podium.Visible = not hud.race.Visible and type(sess.result) == "table" and os.clock() < podiumUntil

	if hud.banner.Visible then
		local left = math.max(0, math.ceil((g.lobbyEndsAt or 0) - ctx:Now()))
		local n = 0
		for _ in g.racers or {} do
			n += 1
		end
		hud.bannerText.Text = string.format("Live race: %d / %d riders · starts in %ds", n, Cfg.MaxRiders, left)
	end
	if hud.countdown.Visible then
		local left = math.ceil((g.goAt or 0) - ctx:Now())
		hud.countdown.Text = if left > 0 then tostring(left) else "GO!"
	end
	if hud.race.Visible then
		hud.raceText.Text = string.format("Lap %d / %d · %s", sess.lap or 1, g.laps or Cfg.Laps, placeText(g, sess))
		hud.meter:SetValue((tonumber(sess.meter) or 0) / Cfg.MeterMax)
	end
	if hud.podium.Visible then
		hud.podiumText.Text = podiumLines(g.results)
	end

	local hasResult = type(sess.result) == "table"
	if hasResult and not lastResultSeen then
		podiumUntil = os.clock() + Cfg.PodiumSeconds
		local kit = ctx:GetController("Celebrate")
		if kit and sess.result.finished then
			kit:Play(if sess.result.place == 1 then "huge" else "medium")
		end
	end
	lastResultSeen = hasResult
end

-- Racing gear on mounts -----------------------------------------------------------------------

local function gearKey(equipped): string
	return table.concat({ tostring(equipped.saddle), tostring(equipped.trail), tostring(equipped.banner) }, "|")
end

local function dressMount(mount: Model, equipped)
	local old = mount:FindFirstChild("RaceGear")
	if old then
		old:Destroy()
	end
	local root = mount.PrimaryPart
	if not root then
		return
	end
	local holder = Instance.new("Model")
	holder.Name = "RaceGear"
	for _, kind in Cfg.GearKinds do
		local id = equipped[kind]
		local item = type(id) == "string" and Cfg.GearById[id]
		if item then
			local part = Instance.new("Part")
			part.Name = kind
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			part.Massless = true
			part.Material = if item.material == "Neon"
				then Enum.Material.Neon
				elseif item.material == "Foil" then Enum.Material.Foil
				else Enum.Material.Fabric
			part.Color = Color3.fromHex(item.color)
			if kind == "saddle" then
				part.Size = Vector3.new(1.4, 0.4, 1.6)
				part.CFrame = root.CFrame * CFrame.new(0, 0.6, 0.2)
			elseif kind == "trail" then
				part.Size = Vector3.new(0.3, 0.3, 1.8)
				part.Transparency = 0.2
				part.CFrame = root.CFrame * CFrame.new(0, 0.1, 1.4)
			else
				part.Size = Vector3.new(0.1, 1, 0.8)
				part.CFrame = root.CFrame * CFrame.new(0.7, 0.6, 0.6)
			end
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
			part.Parent = holder
		end
	end
	holder.Parent = mount
	mount:SetAttribute("RaceGearKey", gearKey(equipped))
end

local function refreshGear()
	local here = StoreKit.tbl(ctx.Store, "global.RaceGear.here")
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local mount = char and char:FindFirstChild("Mount")
		if mount then
			local equipped = here["u" .. tostring(p.UserId)]
			local key = if type(equipped) == "table" then gearKey(equipped) else ""
			if mount:GetAttribute("RaceGearKey") ~= key then
				if type(equipped) == "table" then
					dressMount(mount :: Model, equipped)
				else
					local old = mount:FindFirstChild("RaceGear")
					if old then
						old:Destroy()
					end
					mount:SetAttribute("RaceGearKey", "")
				end
			end
		end
	end
end

-- Lifecycle -------------------------------------------------------------------------------------

local function heartbeat(dt: number)
	local sess = session()
	local g = globalState()
	local wantControl = g.state == "running" and type(sess.heat) == "number" and not sess.finished and not sess.dq
	if wantControl and not rider then
		takeControl(g)
	elseif not wantControl and rider then
		releaseControl()
	end
	if rider then
		stepRider(dt, sess)
	end
	refreshHud()
end

function LiveRace.Init(context)
	ctx = context
end

function LiveRace.Start()
	buildHud()
	RaceTrack.Build()
	ctx.Store:Observe("global.Riding.riders", refreshGear)
	ctx.Store:Observe("global.RaceGear.here", refreshGear)
	RunService.Heartbeat:Connect(heartbeat)
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.DPadUp then
			doJump()
			return
		elseif key == Enum.KeyCode.ButtonR2 or key == Enum.KeyCode.ButtonR1 then
			doBoost()
			return
		end
		if processed then
			return
		end
		if key == Enum.KeyCode.Space or key == Enum.KeyCode.W or key == Enum.KeyCode.Up then
			doJump()
		elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.B then
			doBoost()
		elseif key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
			held.left = true
		elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
			held.right = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		if key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
			held.left = false
		elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
			held.right = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = input.Position.X
			stickX = if math.abs(x) >= STICK_DEADZONE then x else 0
		end
	end)
end

return LiveRace
