--[[
	DeepReef controller (glow-up DR): the Dive Dock, the underwater Area and local swimming.
	Built entirely on this client (like Codex Museum / Fame Plaza), from Config.DeepReef and
	Visuals/ReefBuild + Visuals/ReefLife; nothing is built in the Trading Hub place.

	  DivePad ("Dive")        teleports into the Area (Ranch Level Config.DeepReef.Unlock) and
	                          takes the light: Weather.Hold(true), the Sky / Critters ambience
	                          layers switched off (Lighting "Ambience_<layer>" = false), a stacked
	                          ColorCorrectionEffect ("ReefColor") and the shared Atmosphere set from
	                          Config.DeepReef.Light, Lighting.Ambient / OutdoorAmbient saved and
	                          replaced.
	  ReturnPad ("Swim up")   the Surface Bell: reverses all of the above and returns to the Dock.
	  Gate Portal ("Enter")   opens the Expeditions screen on the "reef" region (its own opensAt
	                          gates the expedition itself, same as every region).
	  Swimming                while inside: the humanoid is PlatformStand (no walking, no gravity)
	                          and this steps Logic/Swim each Heartbeat from WASD / the left stick
	                          (flat) and Space / Ctrl / the triggers (ascend / descend), the
	                          camera's pitch nudging vertical speed while swimming forward, writing
	                          the character's CFrame directly (heading, tilt, idle bob). A mounted
	                          swimmer rides faster (Logic/Swim.Speed); Controllers/Mounts poses it.
	                          No drowning: there is no air meter.

	DeepReef.IsInside() -> boolean   the local character is in the Area (Soundscape, Mounts' own
	                                 riders read Logic/Swim.Inside directly, no call here needed).
]]

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Swim = require(Shared.Logic.Swim)

local Client = script.Parent.Parent
local ReefBuild = require(Client.Visuals.ReefBuild)
local ReefLife = require(Client.Visuals.ReefLife)
local Quality = require(Client.Visuals.Quality)
local StoreKit = require(Client.UI.Components.StoreKit)

local Cfg = Config.DeepReef
local hex = Color3.fromHex

local DeepReef = {
	Name = "DeepReef",
	Dependencies = { "Weather" },
}

local PRIORITY = Enum.ContextActionPriority.High.Value
local VERTICAL_KEYS = { Enum.KeyCode.Space, Enum.KeyCode.ButtonR2, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonL2 }

local ctx
local dock: Model? = nil
local area: Folder? = nil
local life = nil
local lowGraphics = false
local built = false

local swimming = false
local state = { x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0 }
local heading = 0
local held = { up = false, down = false }
local colorEffect: ColorCorrectionEffect? = nil
local trail: ParticleEmitter? = nil
local savedAmbient: Color3? = nil
local savedOutdoor: Color3? = nil

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function unlocked(): boolean
	return StoreKit.level(ctx.Store) >= (Config.Unlocks.Features[Cfg.Unlock] or math.huge)
end

local function prompt(parent: Instance, action: string, object: string, distance: number, onTrigger: () -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = parent
	p.Triggered:Connect(onTrigger)
	return p
end

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local character = ctx.Player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	return humanoid, if root and root:IsA("BasePart") then root else nil
end

-- Light -------------------------------------------------------------------------------------

local function applyAtmosphere()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		return
	end
	local A = Cfg.Light.atmosphere
	atmosphere.Density = A.density
	atmosphere.Offset = A.offset
	atmosphere.Haze = A.haze
	atmosphere.Glare = A.glare
	atmosphere.Color = hex(A.color)
	atmosphere.Decay = hex(A.decay)
end

local function buildColorEffect()
	local L = Cfg.Light
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "ReefColor"
	effect.TintColor = hex(L.tint)
	effect.Brightness = L.brightness
	effect.Contrast = L.contrast
	effect.Saturation = L.saturation
	effect.Parent = Lighting
	colorEffect = effect
end

local function takeLight()
	savedAmbient, savedOutdoor = Lighting.Ambient, Lighting.OutdoorAmbient
	local weather = ctx:GetController("Weather")
	if weather and weather.Hold then
		weather.Hold(true)
	end
	for _, name in Cfg.Light.layers do
		Lighting:SetAttribute("Ambience_" .. name, false)
	end
	Lighting.Ambient = hex(Cfg.Light.ambient)
	Lighting.OutdoorAmbient = hex(Cfg.Light.outdoorAmbient)
	applyAtmosphere()
	buildColorEffect()
end

local function giveLightBack()
	local weather = ctx:GetController("Weather")
	if weather and weather.Hold then
		weather.Hold(false)
	end
	for _, name in Cfg.Light.layers do
		Lighting:SetAttribute("Ambience_" .. name, nil)
	end
	if savedAmbient then
		Lighting.Ambient = savedAmbient
	end
	if savedOutdoor then
		Lighting.OutdoorAmbient = savedOutdoor
	end
	if colorEffect then
		colorEffect:Destroy()
		colorEffect = nil
	end
end

-- Trail bubbles off the local swimmer ---------------------------------------------------------

local function buildTrail(root: BasePart)
	local attach = Instance.new("Attachment")
	attach.Name = "ReefTrail"
	attach.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Trail"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
	emitter.Transparency = NumberSequence.new(0.5, 1)
	emitter.Size = NumberSequence.new(0.2, 0.05)
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(0.5, 1)
	emitter.Rate = 0
	emitter.LightEmission = 0.3
	emitter.Parent = attach
	trail = emitter
end

local function destroyTrail()
	if trail then
		local attach = trail.Parent
		trail:Destroy()
		if attach then
			attach:Destroy()
		end
		trail = nil
	end
end

-- Swimming -------------------------------------------------------------------------------------

local function localRider()
	local riders = StoreKit.tbl(ctx.Store, "global.Riding.riders")
	return riders["u" .. tostring(ctx.Player.UserId)]
end

local function swimSpeed(): number
	local sess = StoreKit.tbl(ctx.Store, "session.Riding")
	local riding = type(sess.mount) == "string"
	local swims = false
	if riding then
		local rider = localRider()
		if type(rider) == "table" and type(rider.appearance) == "table" then
			swims = Cfg.Swims(rider.appearance.line)
		end
	end
	return Swim.Speed(riding, swims, tonumber(sess.speed), Cfg.Swim)
end

-- The left stick's Y (-1..1), kept live by onStickChanged (never polled: GetGamepadState is not
-- for a per-frame read).
local stickY = 0

local function vertical(): number
	local v = (if held.up then 1 else 0) - (if held.down then 1 else 0)
	if math.abs(stickY) > 0.2 then
		v += stickY
	end
	return math.clamp(v, -1, 1)
end

-- Input ---------------------------------------------------------------------------------------

local function onVertical(_, inputState: Enum.UserInputState, input: InputObject)
	local down = inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.Change
	if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonR2 then
		held.up = down
	else
		held.down = down
	end
	return if swimming then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
end

local function dive()
	if not unlocked() then
		ctx:Toast(string.format("The Deep Reef opens at Ranch Level %d", Config.Unlocks.Features[Cfg.Unlock]), "info")
		return
	end
	if swimming then
		return
	end
	local humanoid, root = humanoidAndRoot()
	if not humanoid or not root then
		return
	end
	swimming = true
	takeLight()
	humanoid.PlatformStand = true
	humanoid.AutoRotate = false
	local at = v3(Cfg.Area.center) + v3(Cfg.Area.arrive)
	root.CFrame = CFrame.new(at)
	state.x, state.y, state.z, state.vx, state.vy, state.vz = at.X, at.Y, at.Z, 0, 0, 0
	heading = 0
	held.up, held.down = false, false
	ContextActionService:BindActionAtPriority("DeepReefVertical", onVertical, false, PRIORITY, table.unpack(VERTICAL_KEYS))
	buildTrail(root)
	ctx:Sound("ReefDive", { at = at })
end

local function surface()
	if not swimming then
		return
	end
	swimming = false
	ContextActionService:UnbindAction("DeepReefVertical")
	held.up, held.down = false, false
	local humanoid, root = humanoidAndRoot()
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end
	giveLightBack()
	destroyTrail()
	local at = v3(Cfg.Dock.position)
	if root then
		root.CFrame = CFrame.new(at.X, at.Y + 3, at.Z + 6)
		ctx:Sound("ReefDive", { at = root.Position })
	end
end

local function stepSwim(dt: number)
	local humanoid, root = humanoidAndRoot()
	if not humanoid or not root then
		swimming = false
		ContextActionService:UnbindAction("DeepReefVertical")
		held.up, held.down = false, false
		return
	end
	local camera = workspace.CurrentCamera
	local move = humanoid.MoveDirection
	local lookY = if camera then camera.CFrame.LookVector.Y else 0
	local speed = swimSpeed()
	local tx, ty, tz = Swim.Target(move.X, move.Z, vertical(), lookY, speed, Cfg.Swim)
	Swim.Step(state, tx, ty, tz, dt, Cfg.Swim, Cfg.Area)
	heading = Swim.Heading(state.vx, state.vz, heading)
	local speedNow = math.sqrt(state.vx ^ 2 + state.vy ^ 2 + state.vz ^ 2)
	local tilt = Swim.Tilt(state.vx, state.vy, state.vz, speed, Cfg.Swim.tilt)
	local bob = if speedNow < 1 then Swim.Bob(os.clock(), Cfg.Swim.bob) else 0
	root.CFrame = CFrame.new(state.x, state.y + bob, state.z) * CFrame.Angles(0, heading, 0) * CFrame.Angles(tilt, 0, 0)
	if trail then
		trail.Rate = if speedNow > 2 then Cfg.Life.trail.rate else Cfg.Life.trail.rateLow
	end
end

-- World wiring ----------------------------------------------------------------------------------

local function wireDock(model: Model)
	local pad = model:FindFirstChild("DivePad", true)
	if pad then
		prompt(pad, "Dive", "Deep Reef", 10, dive)
	end
end

local function wireArea(folder: Folder)
	local bell = folder:FindFirstChild("SurfaceBell")
	local returnPad = bell and bell:FindFirstChild("ReturnPad")
	if returnPad then
		prompt(returnPad, "Swim up", "Surface", 12, surface)
	end
	local gate = folder:FindFirstChild("Gate")
	local portal = gate and gate:FindFirstChild("Portal")
	if portal then
		prompt(portal, "Enter", "Reef Gate", 14, function()
			if ctx.Router:Has("Expeditions") then
				ctx.Router:Open("Expeditions", { region = "reef" })
			end
		end)
	end
end

local function build()
	if built then
		return
	end
	built = true
	dock = ReefBuild.Dock(workspace)
	area = ReefBuild.Area(workspace, lowGraphics)
	life = ReefLife.Build(area :: Folder, lowGraphics)
	wireDock(dock :: Model)
	wireArea(area :: Folder)
end

-- Public ----------------------------------------------------------------------------------------

function DeepReef.IsInside(): boolean
	if not swimming then
		return false
	end
	local _, root = humanoidAndRoot()
	return root ~= nil and Swim.Inside(root.Position.X, root.Position.Y, root.Position.Z, Cfg.Area, 2)
end

-- Tests: the dock and area models, and whether the local swim loop is running.
function DeepReef.Stats(): (Model?, Folder?, boolean)
	return dock, area, swimming
end

function DeepReef.Init(context)
	ctx = context
	lowGraphics = Quality.IsLow()
end

function DeepReef.Start()
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stickY = input.Position.Y
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stickY = 0
		end
	end)
	Quality.Changed:Connect(function()
		local low = Quality.IsLow()
		if low ~= lowGraphics then
			lowGraphics = low
			if life then
				ReefLife.SetLow(life, low)
			end
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if swimming then
			swimming = false
			ContextActionService:UnbindAction("DeepReefVertical")
			held.up, held.down = false, false
			giveLightBack()
			destroyTrail()
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		if not built then
			acc += dt
			if acc < 0.5 then
				return
			end
			acc = 0
			if ctx.Store.Ready and ctx.Store:Get("global.TradingHub.mode") ~= "hub" then
				build()
			end
			return
		end
		if life then
			ReefLife.Step(life, dt)
		end
		if swimming and dt > 0 then
			stepSwim(dt)
		end
	end)
end

return DeepReef
