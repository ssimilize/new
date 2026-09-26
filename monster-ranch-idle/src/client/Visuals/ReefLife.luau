--[[
	ReefLife (glow-up DR): the Deep Reef's ambient life, layered onto Visuals/ReefBuild's Area by
	Controllers/DeepReef. Budgeted like Controllers/SceneryMotion: `max` in normal graphics,
	`maxLow` with lowGraphics (Visuals/Quality), rebuilt only when that flag flips.

	  ReefLife.Build(area: Folder, low: boolean) -> state    kelp sway records, vent bubble emitters,
	                                                         fish schools and light shafts from
	                                                         Config.DeepReef.Life / .Area
	  ReefLife.Step(state, dt)                               swims the fish, sways the kelp (kelp at
	                                                         Config.DeepReef.Life.rate updates a second)
	  ReefLife.SetLow(state, low)                            rebuilds fish and shafts to the new cap
	  ReefLife.Destroy(state)
	  ReefLife.Stats(state) -> { kelp, fish, shafts, vents }  tests: live counts

	Positions are studs; the Area's own parts (Floor, Surface, Rocks, Coral, Ruins, ...) are left as
	ReefBuild made them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ambience = require(Shared.Logic.Ambience)
local Rng = require(Shared.Logic.Rng)

local ReefLife = {}

local hex = Color3.fromHex

-- Kelp sway (Controllers/SceneryMotion's tree sway, one seed per plant shared by its stalks) ------

local function buildKelp(area: Folder, cfg)
	local stalks = {}
	local kelp = area:FindFirstChild("Kelp")
	if kelp then
		for _, model in kelp:GetChildren() do
			local seed = tonumber(model:GetAttribute("Seed")) or 0
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					local offset = CFrame.new(0, part.Size.Y / 2, 0)
					stalks[part] = {
						pivot = part.CFrame * offset:Inverse(),
						offset = offset,
						seed = seed,
						angle = cfg.angle,
						speed = cfg.speed,
					}
				end
			end
		end
	end
	return stalks
end

local function swayKelp(stalks, clock: number)
	for part, rec in stalks do
		local ax, az = Ambience.Sway(clock, rec.seed, rec.angle, rec.speed)
		part.CFrame = rec.pivot * CFrame.Angles(ax, 0, az) * rec.offset
	end
end

-- Vent bubbles (one small emitter per bubble vent, rate only, never re-created) -------------------

local function buildVents(area: Folder, cfg, low: boolean)
	local emitters = {}
	local vents = area:FindFirstChild("Vents")
	if not vents then
		return emitters
	end
	local rate = if low then cfg.rateLow else cfg.rate
	for _, part in vents:GetChildren() do
		if part:IsA("BasePart") then
			local attach = Instance.new("Attachment")
			attach.Name = "BubbleSource"
			attach.Parent = part
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Bubbles"
			emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
			emitter.Color = ColorSequence.new(hex("#DFFBFF"))
			emitter.Transparency = NumberSequence.new(0.35, 1)
			emitter.Size = NumberSequence.new(0.25, 0.05)
			emitter.Lifetime = NumberRange.new(cfg.lifetime[1], cfg.lifetime[2])
			emitter.Speed = NumberRange.new(3, 5)
			emitter.SpreadAngle = Vector2.new(6, 6)
			emitter.Acceleration = Vector3.new(0, 6, 0)
			emitter.Rate = rate
			emitter.LightEmission = 0.4
			emitter.Parent = attach
			table.insert(emitters, emitter)
		end
	end
	return emitters
end

-- Fish schools (a slow orbit per fish, no physics: cheap and deterministic) -----------------------

local function buildFish(area: Folder, areaCfg, cfg, low: boolean, rng)
	local schools = if low then cfg.schoolsLow else cfg.schools
	local perSchool = if low then cfg.perSchoolLow else cfg.perSchool
	local folder = area:FindFirstChild("Fish")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Fish"
	folder.Parent = area
	local c = Vector3.new(areaCfg.center[1], areaCfg.center[2], areaCfg.center[3])
	local fish = {}
	for s = 1, schools do
		local angle = rng:Next() * math.pi * 2
		local dist = areaCfg.radius * rng:Float(0.25, 0.75)
		local center = c
			+ Vector3.new(math.cos(angle) * dist, rng:Float(10, areaCfg.surfaceY - areaCfg.center[2] - 14), math.sin(angle) * dist)
		local color = hex(cfg.colors[(s - 1) % #cfg.colors + 1])
		for _ = 1, perSchool do
			local part = Instance.new("Part")
			part.Name = "Fish"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Size = Vector3.new(0.8, 0.4, 0.3)
			part.Color = color
			part.Material = Enum.Material.SmoothPlastic
			part.Parent = folder
			table.insert(fish, {
				part = part,
				center = center,
				radius = rng:Float(2, 5),
				height = rng:Float(0.6, 1.6),
				speed = rng:Float(0.25, 0.45),
				phase = rng:Float(0, math.pi * 2),
			})
		end
	end
	return fish, folder
end

local function stepFish(fish, clock: number)
	for _, f in fish do
		local a = clock * f.speed + f.phase
		local pos = f.center + Vector3.new(math.cos(a) * f.radius, math.sin(a * 1.7) * f.height, math.sin(a) * f.radius)
		local ahead = f.center
			+ Vector3.new(math.cos(a + 0.15) * f.radius, math.sin((a + 0.15) * 1.7) * f.height, math.sin(a + 0.15) * f.radius)
		f.part.CFrame = CFrame.lookAt(pos, ahead)
	end
end

-- Light shafts (static: placed once per rebuild, no per-frame cost) -------------------------------

local function buildShafts(area: Folder, areaCfg, cfg, low: boolean, rng)
	local max = if low then cfg.maxLow else cfg.max
	local folder = area:FindFirstChild("Shafts")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Shafts"
	folder.Parent = area
	local c = Vector3.new(areaCfg.center[1], areaCfg.center[2], areaCfg.center[3])
	local color = hex(cfg.color)
	for i = 1, max do
		local angle = rng:Next() * math.pi * 2
		local dist = areaCfg.radius * rng:Float(0.1, 0.8)
		local top = areaCfg.surfaceY - 1
		local bottom = top - rng:Float(30, 70)
		local height = top - bottom
		local at = c + Vector3.new(math.cos(angle) * dist, (top + bottom) / 2, math.sin(angle) * dist)
		local shaft = Instance.new("Part")
		shaft.Name = "Shaft" .. i
		shaft.Anchored = true
		shaft.CanCollide = false
		shaft.CanQuery = false
		shaft.CanTouch = false
		shaft.CastShadow = false
		shaft.Material = Enum.Material.Neon
		shaft.Color = color
		shaft.Transparency = 0.88
		shaft.Size = Vector3.new(3 + rng:Float(0, 2), height, 3 + rng:Float(0, 2))
		shaft.CFrame = CFrame.new(at)
		shaft.Parent = folder
	end
	return folder
end

-- Public -------------------------------------------------------------------------------------

function ReefLife.Build(area: Folder, low: boolean)
	local Cfg = Config.DeepReef
	local L = Cfg.Life
	local rng = Rng.new(Cfg.Area.seed + 1)
	local fish, fishFolder = buildFish(area, Cfg.Area, L.fish, low, rng)
	return {
		area = area,
		low = low,
		clock = 0,
		acc = 0,
		stalks = buildKelp(area, L.kelp),
		vents = buildVents(area, L.bubbles, low),
		fish = fish,
		fishFolder = fishFolder,
		shafts = buildShafts(area, Cfg.Area, L.shafts, low, rng),
		rate = L.rate,
	}
end

function ReefLife.SetLow(state, low: boolean)
	if state.low == low then
		return
	end
	state.low = low
	local Cfg = Config.DeepReef
	local L = Cfg.Life
	local rng = Rng.new(Cfg.Area.seed + 1)
	state.fish, state.fishFolder = buildFish(state.area, Cfg.Area, L.fish, low, rng)
	state.shafts = buildShafts(state.area, Cfg.Area, L.shafts, low, rng)
end

function ReefLife.Step(state, dt: number)
	state.clock += dt
	state.acc += dt
	local every = if state.rate > 0 then 1 / state.rate else 0
	if state.acc < every then
		return
	end
	state.acc = 0
	swayKelp(state.stalks, state.clock)
	stepFish(state.fish, state.clock)
end

function ReefLife.Destroy(state)
	if state.fishFolder then
		state.fishFolder:Destroy()
	end
	if state.shafts then
		state.shafts:Destroy()
	end
	for _, emitter in state.vents do
		local attach = emitter.Parent
		emitter:Destroy()
		if attach then
			attach:Destroy()
		end
	end
end

-- Tests: live counts.
function ReefLife.Stats(state): { [string]: number }
	local kelp = 0
	for _ in state.stalks do
		kelp += 1
	end
	return { kelp = kelp, fish = #state.fish, shafts = #state.shafts:GetChildren(), vents = #state.vents }
end

return ReefLife
