--[[
	ClockworkBuild (R2-CLOCKWORK): Clockwork Canyon's placeholder geometry, built on the client
	from Config.Clockwork (like Visuals/ReefBuild did for the Deep Reef). Deterministic: the same
	seed scatters the same girders, gears and vents on every client.

	  ClockworkBuild.Landmark(parent) -> Model      "ClockworkTower" at the Market Square's edge
	    Base, Ring, Gear1..3               a stone base and three meshed gears (attr Gear = degrees
	                                        a second; Visuals/ClockworkGears turns them)
	    Body                                invisible box for the tower's mesh (attr Mesh when filled)
	  ClockworkBuild.Area(parent) -> Folder         "ClockworkArea" elsewhere in the world
	    Floor                               rusted plate floor
	    Girders/Girder*                     the ring of girders round the edge
	    Gears/Gear*                         Model: Hub + Cog (attr Gear); some spin, some don't
	    Vents/Vent*                         spark vents (attr SparkVent)
	    Gate                                Model (attrs Screen = "Expeditions", Region =
	                                        "clockwork"): posts, lintel, Portal (attr ClockworkGate), Body

	Hero props keep an invisible `Body` sized from Config.Clockwork.Props[id].size; a filled `mesh`
	id is put on it as the `Mesh` attribute for the art pipeline to dress.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Logic.Rng)

local Cfg = Config.Clockwork
local hex = Color3.fromHex

local ClockworkBuild = {}

local BRASS = hex("#B8860B")
local IRON = hex("#4C4438")
local RUST = hex("#7A4A22")
local SPARK = hex("#FFE066")

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance, props: { [string]: any }?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CastShadow = false
	for key, value in props or {} do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- A flat disc: a cylinder stood on end (Roblox cylinders run along X).
local function disc(name: string, diameter: number, height: number, center: Vector3, color: Color3, parent: Instance, props)
	local p =
		part(name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, parent, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function column(name: string, diameter: number, height: number, base: Vector3, color: Color3, parent: Instance, props)
	local cf = CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local p = part(name, Vector3.new(height, diameter, diameter), cf, color, parent, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function body(prop: string, cframe: CFrame, parent: Model)
	local def = Cfg.Props[prop]
	local size = def.size
	local b = part("Body", Vector3.new(size[1], size[2], size[3]), cframe, IRON, parent, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	if def.mesh ~= "" then
		b:SetAttribute("Mesh", def.mesh)
	end
	parent.PrimaryPart = b
	return b
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- A cogged gear: a hub disc with `teeth` small blocks round the rim. `speed` (degrees/second,
-- signed for spin direction) is stored as the `Gear` attribute; Visuals/ClockworkGears reads it.
local function gear(name: string, diameter: number, thickness: number, at: Vector3, speed: number, color: Color3, parent: Instance): Model
	local m = model(name, parent)
	local hub = disc("Hub", diameter, thickness, at, color, m, { Material = Enum.Material.Metal })
	local teeth = math.max(6, math.floor(diameter))
	for i = 1, teeth do
		local a = (i / teeth) * math.pi * 2
		local toothAt = at + Vector3.new(math.cos(a) * diameter / 2, 0, math.sin(a) * diameter / 2)
		part(
			"Tooth" .. i,
			Vector3.new(thickness, diameter * 0.14, diameter * 0.14),
			CFrame.new(toothAt) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(a, 0, 0),
			color,
			m,
			{ Material = Enum.Material.Metal }
		)
	end
	m:SetAttribute("Gear", speed)
	m.PrimaryPart = hub
	return m
end

-- The landmark tower ---------------------------------------------------------------------------

function ClockworkBuild.Landmark(parent: Instance): Model
	local L = Cfg.Landmark
	local at = v3(L.position)
	local tower = model("ClockworkTower", parent)
	tower:SetAttribute("DisplayName", "Clockwork Tower")
	part("Base", Vector3.new(10, 2, 10), CFrame.new(at + Vector3.new(0, 1, 0)), IRON, tower, { Material = Enum.Material.Cobblestone })
	column("Post", 3, 20, at + Vector3.new(0, 2, 0), BRASS, tower, { Material = Enum.Material.Metal })
	local yaw = math.rad(L.facing)
	local face = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	local speed = Cfg.Gears.towerSpeed
	gear("Gear1", 7, 1, (face * CFrame.new(0, 20, 3)).Position, speed, BRASS, tower)
	gear("Gear2", 4.5, 1, (face * CFrame.new(3.2, 17, 3.4)).Position, -speed * 1.4, IRON, tower)
	gear("Gear3", 4.5, 1, (face * CFrame.new(-3.2, 17, 3.4)).Position, -speed * 1.4, IRON, tower)
	local sign = part("Sign", Vector3.new(6, 2, 0.4), face * CFrame.new(0, 24, 3), hex("#2A2118"), tower)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = SPARK
	label.Text = "Clockwork Canyon"
	label.Parent = gui
	gui.Parent = sign
	body("tower", face * CFrame.new(0, 14, 0), tower)
	return tower
end

-- The canyon area --------------------------------------------------------------------------------

local function clearOf(x: number, z: number, keep: { Vector3 }, radius: number): boolean
	for _, k in keep do
		local dx, dz = x - k.X, z - k.Z
		if dx * dx + dz * dz < radius * radius then
			return false
		end
	end
	return true
end

local function spot(rng, c: Vector3, from: number, to: number, keep: { Vector3 }, clear: number): Vector3
	local x, z = c.X, c.Z
	for _ = 1, 24 do
		local a = rng:Next() * math.pi * 2
		local d = from + (to - from) * math.sqrt(rng:Next())
		x, z = c.X + math.cos(a) * d, c.Z + math.sin(a) * d
		if clearOf(x, z, keep, clear) then
			break
		end
	end
	return Vector3.new(x, c.Y, z)
end

local function buildGate(at: Vector3, parent: Instance)
	local gt = model("Gate", parent)
	gt:SetAttribute("Screen", "Expeditions")
	gt:SetAttribute("Region", Cfg.Region)
	part("PostL", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(-8, 9, 0)), IRON, gt, { Material = Enum.Material.Metal })
	part("PostR", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(8, 9, 0)), IRON, gt, { Material = Enum.Material.Metal })
	part("Lintel", Vector3.new(20, 3, 4), CFrame.new(at + Vector3.new(0, 19, 0)), IRON, gt, { Material = Enum.Material.Metal })
	gear("LintelGear", 5, 1.2, at + Vector3.new(0, 20.5, 0), Cfg.Gears.towerSpeed, BRASS, gt)
	local portal = part("Portal", Vector3.new(13, 16, 0.4), CFrame.new(at + Vector3.new(0, 9, 0)), hex("#FFC94D"), gt, {
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
	})
	portal:SetAttribute("ClockworkGate", true)
	body("gate", CFrame.new(at + Vector3.new(0, 11, 0)), gt)
end

function ClockworkBuild.Area(parent: Instance, _low: boolean?): Folder
	local A = Cfg.Area
	local C = Cfg.Counts
	local c = v3(A.center)
	local r = A.radius
	local area = Instance.new("Folder")
	area.Name = "ClockworkArea"
	local rng = Rng.new(A.seed)

	local floor = disc("Floor", r * 2 + 40, 4, c - Vector3.new(0, 2, 0), hex("#6E5A46"), area, { Material = Enum.Material.CorrodedMetal })
	floor.CanQuery = true

	local gateAt = c + v3(A.gate)
	local keep = { gateAt }

	local girders = Instance.new("Folder")
	girders.Name = "Girders"
	girders.Parent = area
	for i = 1, C.girders do
		local a = (i / C.girders) * math.pi * 2 + rng:Float(-0.1, 0.1)
		local d = r + rng:Float(-6, 8)
		local h = rng:Float(14, 30)
		local at = Vector3.new(c.X + math.cos(a) * d, c.Y + h * 0.5, c.Z + math.sin(a) * d)
		column("Girder" .. i, rng:Float(2, 3.5), h, at - Vector3.new(0, h * 0.5, 0), RUST, girders, { Material = Enum.Material.Metal })
	end

	local gears = Instance.new("Folder")
	gears.Name = "Gears"
	gears.Parent = area
	for i = 1, C.gears do
		local at = spot(rng, c, 12, r - 14, keep, A.clear)
		local diameter = rng:Float(4, 9)
		local spinning = i % 2 == 0 -- half the ground gears turn, half are seized still props
		local speed = if spinning then rng:Float(Cfg.Gears.groundSpeedMin, Cfg.Gears.groundSpeedMax) * (if i % 4 == 0 then -1 else 1) else 0
		gear(
			"Gear" .. i,
			diameter,
			rng:Float(0.8, 1.6),
			at + Vector3.new(0, diameter * 0.4, 0),
			speed,
			if i % 3 == 0 then IRON else BRASS,
			gears
		)
	end

	local vents = Instance.new("Folder")
	vents.Name = "Vents"
	vents.Parent = area
	for i = 1, C.vents do
		local at = spot(rng, c, 10, r - 18, keep, A.clear)
		local v = part("Vent" .. i, Vector3.new(3, 2.4, 3), CFrame.new(at + Vector3.new(0, 0.8, 0)), hex("#3A322A"), vents, {
			Material = Enum.Material.Metal,
		})
		v:SetAttribute("SparkVent", true)
	end

	buildGate(gateAt, area)
	area.Parent = parent
	return area
end

return ClockworkBuild
