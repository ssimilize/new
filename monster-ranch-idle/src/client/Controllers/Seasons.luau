--[[
	Seasons controller (update 3.11 · Ranch Seasons): the look of the season on the ranch. The
	season is Logic/Seasons.At(server time), so every client agrees with the server and nothing is
	sent over the network.

	  ground     workspace.World.Ground takes the season's grass tint (Config.Seasons ground)
	  particles  one invisible anchored part follows the camera (like the Weather controller) with
	             one emitter per ambient kind: spring petals, summer fireflies by night and pollen
	             by day, autumn falling leaves, winter snow. Only the season's emitter has a Rate.
	             Visuals/Quality: Low runs at LOW_SHARE of the rate; Reduced motion (Settings) and
	             a held Weather (the Deep Reef) run none.

	The winter swap of the weather's rain for snow lives in the Weather controller.
	Seasons.Current() -> seasonId (the season this controller shows; tests read it).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SeasonsLogic = require(Shared.Logic.Seasons)
local Quality = require(script.Parent.Parent.Visuals.Quality)

local Seasons = {
	Name = "Seasons",
	Dependencies = {},
}

local CHECK_EVERY = 2 -- seconds between season / night / quality checks
local LOW_SHARE = 0.35
local HEIGHT = 26

local hex = Color3.fromHex

-- One look per ambient kind (Config.Seasons particle; summer's night look is "fireflies").
local LOOKS = {
	petals = {
		rate = 9,
		props = {
			Color = ColorSequence.new(hex("#FFD1E6"), hex("#FF8FC0")),
			Transparency = NumberSequence.new(0.1, 0.7),
			Size = NumberSequence.new(0.35),
			Speed = NumberRange.new(2, 4),
			Lifetime = NumberRange.new(7, 10),
			SpreadAngle = Vector2.new(45, 45),
			Acceleration = Vector3.new(2, -0.8, 1.2),
			RotSpeed = NumberRange.new(-120, 120),
			Rotation = NumberRange.new(0, 360),
			LightEmission = 0.2,
		},
	},
	fireflies = {
		rate = 6,
		props = {
			Color = ColorSequence.new(hex("#F7FF9E"), hex("#C8FF6E")),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.1),
				NumberSequenceKeypoint.new(0.7, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Size = NumberSequence.new(0.22),
			Speed = NumberRange.new(0.5, 1.5),
			Lifetime = NumberRange.new(4, 7),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -0.6, 0),
			LightEmission = 1,
		},
	},
	pollen = {
		rate = 5,
		props = {
			Color = ColorSequence.new(hex("#FFE38A"), hex("#FFF4C2")),
			Transparency = NumberSequence.new(0.3, 0.9),
			Size = NumberSequence.new(0.16),
			Speed = NumberRange.new(1, 2.5),
			Lifetime = NumberRange.new(6, 9),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(1.5, -0.3, 0.8),
			LightEmission = 0.4,
		},
	},
	leaves = {
		rate = 8,
		props = {
			Color = ColorSequence.new(hex("#E8702A"), hex("#C8452A")),
			Transparency = NumberSequence.new(0, 0.6),
			Size = NumberSequence.new(0.45),
			Speed = NumberRange.new(2, 4),
			Lifetime = NumberRange.new(6, 9),
			SpreadAngle = Vector2.new(35, 35),
			Acceleration = Vector3.new(2.5, -1.4, 1.5),
			RotSpeed = NumberRange.new(-160, 160),
			Rotation = NumberRange.new(0, 360),
			LightEmission = 0,
		},
	},
	snow = {
		rate = 40,
		props = {
			Color = ColorSequence.new(hex("#FFFFFF")),
			Transparency = NumberSequence.new(0.15),
			Size = NumberSequence.new(0.3),
			Speed = NumberRange.new(4, 7),
			Lifetime = NumberRange.new(5, 7),
			SpreadAngle = Vector2.new(25, 25),
			Acceleration = Vector3.new(1.2, 0, 0.6),
			RotSpeed = NumberRange.new(-60, 60),
			LightEmission = 0.3,
		},
	},
}
local KINDS = { "petals", "fireflies", "pollen", "leaves", "snow" }

local ctx
local part: Part
local emitters = {} -- [kind] = ParticleEmitter
local connections = {}
local season = ""
local kind = ""
local ground: BasePart? = nil
local checkIn = 0

local function isNight(): boolean
	local w = ctx.Store:Get("global.Weather")
	return type(w) == "table" and w.night == true
end

local function reducedMotion(): boolean
	local settings = ctx.Store:Get("profile.Settings")
	return type(settings) == "table" and settings.reducedMotion == true
end

local function weatherHeld(): boolean
	local ok, weather = pcall(ctx.GetController, ctx, "Weather")
	return ok and type(weather) == "table" and type(weather.IsHeld) == "function" and weather.IsHeld() == true
end

local function findGround(): BasePart?
	if ground and ground.Parent then
		return ground
	end
	local world = workspace:FindFirstChild("World")
	local g = world and world:FindFirstChild("Ground")
	ground = if g and g:IsA("BasePart") then g else nil
	return ground
end

-- Which emitter runs, and how hard (particles per second).
local function wanted(): (string, number)
	local def = Config.Seasons.ById[season]
	if not def then
		return "", 0
	end
	local k = def.particle
	if k == "fireflies" and not isNight() then
		k = "pollen"
	end
	if reducedMotion() or weatherHeld() then
		return k, 0
	end
	local share = if Quality.IsLow() then LOW_SHARE else 1
	return k, math.floor(LOOKS[k].rate * share + 0.5)
end

local function refresh()
	season = SeasonsLogic.At(ctx:Now()).id
	local def = Config.Seasons.ById[season]
	local g = findGround()
	if g and def then
		local tint = hex(def.ground)
		if g.Color ~= tint then
			g.Color = tint
		end
	end
	local k, rate = wanted()
	kind = k
	for id, e in emitters do
		local r = if id == k then rate else 0
		if e.Rate ~= r then
			e.Rate = r
		end
	end
end

local function step(dt: number)
	checkIn -= dt
	if checkIn <= 0 then
		checkIn = CHECK_EVERY
		refresh()
	end
	local e = emitters[kind]
	if e and e.Rate > 0 then
		local camera = workspace.CurrentCamera
		if camera then
			local p = camera.CFrame.Position
			part.CFrame = CFrame.new(p.X, p.Y + HEIGHT, p.Z)
		end
	end
end

local function build()
	part = Instance.new("Part")
	part.Name = "SeasonEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(120, 1, 120)
	part.CFrame = CFrame.new(0, -500, 0)
	part.Parent = workspace
	for _, k in KINDS do
		local e = Instance.new("ParticleEmitter")
		e.Name = "Season_" .. k
		e.Rate = 0
		e.EmissionDirection = Enum.NormalId.Bottom
		for prop, value in LOOKS[k].props do
			(e :: any)[prop] = value
		end
		e.Parent = part
		emitters[k] = e
	end
end

function Seasons.Current(): string
	return season
end

function Seasons.Init(context)
	ctx = context
	build()
end

function Seasons.Start()
	refresh()
	table.insert(connections, RunService.RenderStepped:Connect(step))
	table.insert(
		connections,
		Quality.Changed:Connect(function()
			checkIn = 0
		end)
	)
end

-- Tears everything down (not called by the kernel today; kept so the controller can be unplugged).
function Seasons.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	part:Destroy()
end

return Seasons
