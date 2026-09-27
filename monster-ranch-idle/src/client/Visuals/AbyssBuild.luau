--[[
	AbyssBuild (R2-ABYSS): the Sunken Abyss's placeholder geometry, built on the client from
	Config.Abyss (like Visuals/ReefBuild built the Deep Reef, Visuals/ClockworkBuild built
	Clockwork Canyon). Deterministic: the same seed scatters the same rocks and spires on every
	client, so everyone swims round the same abyss.

	  AbyssBuild.Descent(reefArea: Folder) -> Model   "Chasm" dropped into the Deep Reef's own Area
	    at Config.Abyss.Descent.offset from its centre: a dark crack in the sand, DivePad (attr
	    AbyssPad = "descend"); the controller's "Dive Deeper" prompt.
	  AbyssBuild.Area(parent) -> Folder   "AbyssArea" (never "Area": that name is the Deep Reef's
	    own folder, and both live under workspace at once once a player has descended)
	    Floor, Rocks/Rock*, Spires/Spire*   the sand and its glowing broken spires
	    Vents/Vent*                          bubble vents (attr AbyssVent)
	    AscentBell                           Model: bell, ReturnPad (attr AbyssPad = "ascend")
	    Gate                                 Model (attrs Screen = "Expeditions", Region = "abyss"):
	                                          posts, lintel, Portal (attr AbyssGate), Body
	Hero props keep an invisible `Body` sized from Config.Abyss.Props[id].size; a filled `mesh` id
	is put on it as the `Mesh` attribute for the art pipeline to dress, same as every other region.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Logic.Rng)

local Cfg = Config.Abyss
local hex = Color3.fromHex

local AbyssBuild = {}

local GLOW = { "#5CE1E6", "#7CFFB2", "#B388FF", "#FF7AC8" }
local ROCK = hex("#151A33")

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
	local b = part("Body", Vector3.new(size[1], size[2], size[3]), cframe, ROCK, parent, {
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

-- The Descent: a dark crack in the Deep Reef's own sand ------------------------------------------

function AbyssBuild.Descent(reefArea: Folder): Model
	-- On the reef's sand (Config.DeepReef.Area.floorY). Not measured off the reef's Floor part: it
	-- is a cylinder lying on its side, so its Size.Y is the 320-stud diameter, and half of that
	-- put the chasm 158 studs up, above the water where no swimmer could reach it (Studio,
	-- 2026-09-27).
	local R = Config.DeepReef.Area
	local at = Vector3.new(R.center[1], R.floorY, R.center[3]) + v3(Cfg.Descent.offset)
	local chasm = model("Chasm", reefArea)
	disc("Rim", 16, 0.8, at + Vector3.new(0, 0.3, 0), hex("#101425"), chasm, { Material = Enum.Material.Basalt })
	local pad = disc("DivePad", 11, 0.4, at + Vector3.new(0, 0.1, 0), hex("#2A1E4A"), chasm, {
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	pad:SetAttribute("AbyssPad", "descend")
	for i, x in { -3, 0, 3 } do
		part("Glow" .. i, Vector3.new(1, 0.4, 1), CFrame.new(at + Vector3.new(x, 0.4, 0)), hex(GLOW[(i % #GLOW) + 1]), chasm, {
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
			CanCollide = false,
		})
	end
	body("chasm", CFrame.new(at + Vector3.new(0, 1, 0)), chasm)
	return chasm
end

-- The Abyss floor ----------------------------------------------------------------------------

local function buildSpire(at: Vector3, height: number, glow: Color3, parent: Instance)
	local spire = model("Spire", parent)
	column("Stalk", 3, height, at, ROCK, spire, { Material = Enum.Material.Basalt })
	local tip = part("Tip", Vector3.new(2, 2, 2), CFrame.new(at + Vector3.new(0, height, 0)), glow, spire, {
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Range = 16
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = tip
	return spire
end

local function buildAscentBell(at: Vector3, parent: Instance)
	local bell = model("AscentBell", parent)
	disc("Base", 12, 1.2, at + Vector3.new(0, 0.6, 0), hex("#101425"), bell, { Material = Enum.Material.Basalt })
	local pad = disc("ReturnPad", 8, 0.4, at + Vector3.new(0, 1.4, 0), hex("#5CE1E6"), bell, { Material = Enum.Material.Neon })
	pad:SetAttribute("AbyssPad", "ascend")
	part("Bell", Vector3.new(6, 7, 6), CFrame.new(at + Vector3.new(0, 7, 0)), hex("#2A1E4A"), bell, {
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
	})
	body("bell", CFrame.new(at + Vector3.new(0, 5, 0)), bell)
end

local function buildGate(at: Vector3, parent: Instance)
	local gate = model("Gate", parent)
	gate:SetAttribute("Screen", "Expeditions")
	gate:SetAttribute("Region", Cfg.Region)
	local rock = hex("#101425")
	part("PostL", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(-8, 9, 0)), rock, gate, { Material = Enum.Material.Basalt })
	part("PostR", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(8, 9, 0)), rock, gate, { Material = Enum.Material.Basalt })
	part("Lintel", Vector3.new(20, 3, 4), CFrame.new(at + Vector3.new(0, 19, 0)), rock, gate, { Material = Enum.Material.Basalt })
	for i, x in { -8, 0, 8 } do
		part("Crust" .. i, Vector3.new(2, 2, 2), CFrame.new(at + Vector3.new(x, 20.5, 0)), hex(GLOW[(i % #GLOW) + 1]), gate, {
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
		})
	end
	local portal = part("Portal", Vector3.new(13, 16, 0.4), CFrame.new(at + Vector3.new(0, 9, 0)), hex("#2A1E4A"), gate, {
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	})
	portal:SetAttribute("AbyssGate", true)
	body("gate", CFrame.new(at + Vector3.new(0, 11, 0)), gate)
end

function AbyssBuild.Area(parent: Instance): Folder
	local A = Cfg.Area
	local C = Cfg.Counts
	local c = v3(A.center)
	local r = A.radius
	local area = Instance.new("Folder")
	area.Name = "AbyssArea"
	local rng = Rng.new(A.seed)

	local floor = disc("Floor", r * 2 + 40, 4, c - Vector3.new(0, 2, 0), hex("#0C0F1F"), area, { Material = Enum.Material.Basalt })
	floor.CanQuery = true

	local bellAt, gateAt, spireAt = c + v3(A.ascend), c + v3(A.gate), c + v3(A.spire)
	local keep = { bellAt, gateAt, spireAt, c + Vector3.new(A.arrive[1], 0, A.arrive[3]) }

	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	rocks.Parent = area
	for i = 1, C.rocks do
		local a = (i / C.rocks) * math.pi * 2 + rng:Float(-0.1, 0.1)
		local d = r + rng:Float(-6, 8)
		local size = Vector3.new(rng:Float(12, 24), rng:Float(16, 40), rng:Float(12, 24))
		local at = Vector3.new(c.X + math.cos(a) * d, c.Y + size.Y * 0.35, c.Z + math.sin(a) * d)
		part("Rock" .. i, size, CFrame.new(at) * CFrame.Angles(rng:Float(-0.2, 0.2), a, rng:Float(-0.2, 0.2)), ROCK, rocks, {
			Material = Enum.Material.Basalt,
		})
	end

	local spires = Instance.new("Folder")
	spires.Name = "Spires"
	spires.Parent = area
	for i = 1, C.spires do
		local at = spot(rng, c, 14, r - 18, keep, A.clear)
		local glow = hex(GLOW[(i - 1) % #GLOW + 1])
		buildSpire(at, rng:Float(8, 20), glow, spires)
	end

	local vents = Instance.new("Folder")
	vents.Name = "Vents"
	vents.Parent = area
	for i = 1, C.vents do
		local at = spot(rng, c, 10, r - 20, keep, A.clear)
		local v = part("Vent" .. i, Vector3.new(3, 2, 3), CFrame.new(at + Vector3.new(0, 0.6, 0)), hex("#0C0F1F"), vents, {
			Material = Enum.Material.Basalt,
			Shape = Enum.PartType.Ball,
		})
		v:SetAttribute("AbyssVent", true)
	end

	buildAscentBell(bellAt, area)
	buildGate(gateAt, area)
	buildSpire(spireAt, 30, hex(GLOW[1]), area) -- the landmark spire, always the biggest
	area.Parent = parent
	return area
end

return AbyssBuild
