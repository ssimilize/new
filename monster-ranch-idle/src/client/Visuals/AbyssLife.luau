--[[
	AbyssLife (R2-ABYSS): the Sunken Abyss's ambient life, layered onto Visuals/AbyssBuild's
	AbyssArea by Controllers/Abyss. Same shape as Visuals/ReefLife (budgeted: `max` in normal
	graphics, `maxLow` with lowGraphics), minus light shafts — there is no sunlight this deep to
	shaft, so glow motes take their place: small, static, drifting points of colour instead.

	  AbyssLife.Build(area: Folder, low: boolean) -> state
	  AbyssLife.Step(state, dt)          drifts the motes, swims the fish (Config.Abyss.Life.rate
	                                     updates a second)
	  AbyssLife.SetLow(state, low)       rebuilds fish and motes to the new cap
	  AbyssLife.Destroy(state)
	  AbyssLife.Stats(state) -> { fish, motes, vents }   tests: live counts

	A part whose Parent has gone (streamed out, destroyed) is dropped instead of erroring, like
	Visuals/ClockworkGears.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Rng = require(Shared.Logic.Rng)

local AbyssLife = {}

local hex = Color3.fromHex

-- Vent bubbles ------------------------------------------------------------------------------

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
			emitter.Color = ColorSequence.new(hex("#7CFFB2"))
			emitter.Transparency = NumberSequence.new(0.4, 1)
			emitter.Size = NumberSequence.new(0.22, 0.05)
			emitter.Lifetime = NumberRange.new(cfg.lifetime[1], cfg.lifetime[2])
			emitter.Speed = NumberRange.new(2.5, 4)
			emitter.SpreadAngle = Vector2.new(6, 6)
			emitter.Acceleration = Vector3.new(0, 5, 0)
			emitter.Rate = rate
			emitter.LightEmission = 0.5
			emitter.Parent = attach
			table.insert(emitters, emitter)
		end
	end
	return emitters
end

-- Fish schools (same orbit maths as ReefLife: cheap and deterministic) ---------------------------

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
		local center = c + Vector3.new(math.cos(angle) * dist, rng:Float(10, 40), math.sin(angle) * dist)
		local color = hex(cfg.colors[(s - 1) % #cfg.colors + 1])
		for _ = 1, perSchool do
			local part = Instance.new("Part")
			part.Name = "Fish"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Size = Vector3.new(0.7, 0.35, 0.3)
			part.Color = color
			part.Material = Enum.Material.Neon
			part.Parent = folder
			table.insert(fish, {
				part = part,
				center = center,
				radius = rng:Float(2, 5),
				height = rng:Float(0.6, 1.6),
				speed = rng:Float(0.2, 0.4),
				phase = rng:Float(0, math.pi * 2),
			})
		end
	end
	return fish, folder
end

local function stepFish(fish, clock: number)
	local i = 1
	while i <= #fish do
		local f = fish[i]
		if not f.part.Parent then
			table.remove(fish, i)
		else
			local a = clock * f.speed + f.phase
			local pos = f.center + Vector3.new(math.cos(a) * f.radius, math.sin(a * 1.7) * f.height, math.sin(a) * f.radius)
			local ahead = f.center
				+ Vector3.new(math.cos(a + 0.15) * f.radius, math.sin((a + 0.15) * 1.7) * f.height, math.sin(a + 0.15) * f.radius)
			f.part.CFrame = CFrame.lookAt(pos, ahead)
			i += 1
		end
	end
end

-- Glow motes (drifting points of light: ReefLife's shafts, but small and mobile, no sunlight to shaft) --

local function buildMotes(area: Folder, areaCfg, cfg, low: boolean, rng)
	local max = if low then cfg.maxLow else cfg.max
	local folder = area:FindFirstChild("Motes")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Motes"
	folder.Parent = area
	local c = Vector3.new(areaCfg.center[1], areaCfg.center[2], areaCfg.center[3])
	local color = hex(cfg.color)
	local motes = {}
	for i = 1, max do
		local angle = rng:Next() * math.pi * 2
		local dist = areaCfg.radius * rng:Float(0.1, 0.85)
		local center = c + Vector3.new(math.cos(angle) * dist, rng:Float(6, 50), math.sin(angle) * dist)
		local mote = Instance.new("Part")
		mote.Name = "Mote" .. i
		mote.Anchored = true
		mote.CanCollide = false
		mote.CanQuery = false
		mote.CanTouch = false
		mote.CastShadow = false
		mote.Shape = Enum.PartType.Ball
		mote.Material = Enum.Material.Neon
		mote.Color = color
		mote.Size = Vector3.new(0.5, 0.5, 0.5) * rng:Float(0.6, 1.4)
		mote.CFrame = CFrame.new(center)
		mote.Parent = folder
		table.insert(
			motes,
			{ part = mote, center = center, radius = rng:Float(3, 8), speed = rng:Float(0.08, 0.18), phase = rng:Float(0, math.pi * 2) }
		)
	end
	return motes, folder
end

local function stepMotes(motes, clock: number)
	local i = 1
	while i <= #motes do
		local m = motes[i]
		if not m.part.Parent then
			table.remove(motes, i)
		else
			local a = clock * m.speed + m.phase
			m.part.Position = m.center + Vector3.new(math.cos(a) * m.radius, math.sin(a * 0.6) * 2, math.sin(a) * m.radius)
			i += 1
		end
	end
end

-- Public -------------------------------------------------------------------------------------

function AbyssLife.Build(area: Folder, low: boolean)
	local Cfg = Config.Abyss
	local L = Cfg.Life
	local rng = Rng.new(Cfg.Area.seed + 1)
	local fish, fishFolder = buildFish(area, Cfg.Area, L.fish, low, rng)
	local motes, moteFolder = buildMotes(area, Cfg.Area, L.motes, low, rng)
	return {
		area = area,
		low = low,
		clock = 0,
		acc = 0,
		vents = buildVents(area, L.bubbles, low),
		fish = fish,
		fishFolder = fishFolder,
		motes = motes,
		moteFolder = moteFolder,
		rate = L.rate,
	}
end

function AbyssLife.SetLow(state, low: boolean)
	if state.low == low then
		return
	end
	state.low = low
	local Cfg = Config.Abyss
	local L = Cfg.Life
	local rng = Rng.new(Cfg.Area.seed + 1)
	state.fish, state.fishFolder = buildFish(state.area, Cfg.Area, L.fish, low, rng)
	state.motes, state.moteFolder = buildMotes(state.area, Cfg.Area, L.motes, low, rng)
end

function AbyssLife.Step(state, dt: number)
	state.clock += dt
	state.acc += dt
	local every = if state.rate > 0 then 1 / state.rate else 0
	if state.acc < every then
		return
	end
	state.acc = 0
	stepFish(state.fish, state.clock)
	stepMotes(state.motes, state.clock)
end

function AbyssLife.Destroy(state)
	if state.fishFolder then
		state.fishFolder:Destroy()
	end
	if state.moteFolder then
		state.moteFolder:Destroy()
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
function AbyssLife.Stats(state): { [string]: number }
	return { fish = #state.fish, motes = #state.motes, vents = #state.vents }
end

return AbyssLife
