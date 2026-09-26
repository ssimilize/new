--[[
	ReefBuild (glow-up DR): the Deep Reef's placeholder geometry, built on the client from
	Config.DeepReef (like the Codex Museum). Deterministic: the same seed scatters the same rocks,
	coral, kelp and vents on every client, so everyone swims round the same reef.

	  ReefBuild.Dock(parent) -> Model        "DiveDock" at the Market Square's edge (main place only)
	    Pool, Rim, Plank*, Post*, Sign       the pool, its pier and the name board
	    DivePad                              Neon disc (attr ReefPad = "dive"); the controller's prompt
	    Body                                 invisible box for the dock's mesh (attr Mesh when filled)
	  ReefBuild.Area(parent) -> Folder       "Area" deep under the ranch
	    Floor, Surface                       sand and the shimmering surface seen from below
	    Rocks/Rock*                          the ring of rocks round the edge
	    Coral/Coral*                         Model: Base + Branch* (one Neon accent, Glass fans)
	    Kelp/Kelp*                           Model: Stalk1..3 (attr Seed); Visuals/ReefLife sways them
	    Vents/Vent*                          bubble vents (attr ReefVent)
	    Ruins                                Model: platform, columns (some broken), arch, head, Body
	    GiantClam                            Model: halves and a pearl, Body
	    SurfaceBell                          Model: bell, rope to the surface, ReturnPad (attr ReefPad = "return")
	    Gate                                 Model (attrs Screen = "Expeditions", Region = "reef"): posts,
	                                         lintel, Portal (attr ReefGate), Body
	Hero props keep an invisible `Body` sized from Config.DeepReef.Props[id].size; a filled `mesh`
	id is put on it as the `Mesh` attribute for the art pipeline to dress.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rng = require(ReplicatedStorage.Shared.Logic.Rng)

local Cfg = Config.DeepReef
local hex = Color3.fromHex

local ReefBuild = {}

local CORAL = { "#FF6FAE", "#4FF0E0", "#B388FF", "#FF9F5A", "#7CFFB2" }
local STONE = hex("#B8C4B0")
local MOSS = hex("#4E7F4A")

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

-- An upright column: a cylinder turned to run along Y.
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
	local b = part("Body", Vector3.new(size[1], size[2], size[3]), cframe, STONE, parent, {
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

-- The Dive Dock ------------------------------------------------------------------------------

function ReefBuild.Dock(parent: Instance): Model
	local D = Cfg.Dock
	local at = v3(D.position)
	local dock = model("DiveDock", parent)
	dock:SetAttribute("DisplayName", "Dive Dock")
	disc("Rim", D.pool + 3, 0.6, at + Vector3.new(0, 0.2, 0), hex("#CDBF9E"), dock, { Material = Enum.Material.Cobblestone })
	disc("Pool", D.pool, 0.4, at + Vector3.new(0, 0.35, 0), hex("#2FA8C9"), dock, {
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		CanCollide = false,
	})
	local pad = disc("DivePad", 7, 0.3, at + Vector3.new(0, 0.6, 0), hex("#5CE1E6"), dock, { Material = Enum.Material.Neon })
	pad:SetAttribute("ReefPad", "dive")
	-- The pier runs out from the rim along `facing`.
	local yaw = math.rad(D.facing)
	local out = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	local start = D.pool / 2 + 1
	for i = 1, 3 do
		local x = (i - 2) * 2
		part(
			"Plank" .. i,
			Vector3.new(1.8, 0.4, 12),
			out * CFrame.new(x, 0.9, start + 6),
			hex("#9C6130"),
			dock,
			{ Material = Enum.Material.Wood }
		)
	end
	for i, corner in { { -3, 1 }, { 3, 1 }, { -3, 11 }, { 3, 11 } } do
		part("Post" .. i, Vector3.new(0.7, 3, 0.7), out * CFrame.new(corner[1], 1.5, start + corner[2]), hex("#7A4A22"), dock, {
			Material = Enum.Material.Wood,
		})
	end
	local sign = part("Sign", Vector3.new(7, 2.4, 0.4), out * CFrame.new(0, 4, start + 12), hex("#FFF7E3"), dock)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = hex("#1D5F7A")
	label.Text = "Deep Reef"
	label.Parent = gui
	gui.Parent = sign
	body("dock", out * CFrame.new(0, 0.5, start + 6), dock)
	return dock
end

-- The reef -----------------------------------------------------------------------------------

local function clearOf(x: number, z: number, keep: { Vector3 }, radius: number): boolean
	for _, k in keep do
		local dx, dz = x - k.X, z - k.Z
		if dx * dx + dz * dz < radius * radius then
			return false
		end
	end
	return true
end

-- A random spot on the sand between `from` and `to` studs from the centre, clear of the landmarks.
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

local function buildRuins(at: Vector3, parent: Instance)
	local ruins = model("Ruins", parent)
	part("Platform", Vector3.new(30, 2, 22), CFrame.new(at + Vector3.new(0, 0.6, 0)), hex("#8FA39A"), ruins, {
		Material = Enum.Material.Cobblestone,
	})
	local heights = { 16, 9, 14, 5, 12, 7 }
	for i, h in heights do
		local x = -12 + ((i - 1) % 3) * 12
		local z = if i <= 3 then -8 else 8
		column("Column" .. i, 2.6, h, at + Vector3.new(x, 1.6, z), STONE, ruins, { Material = Enum.Material.Marble })
		if h >= 12 then
			part(
				"Moss" .. i,
				Vector3.new(3, 0.5, 3),
				CFrame.new(at + Vector3.new(x, 1.6 + h, z)),
				MOSS,
				ruins,
				{ Material = Enum.Material.Grass }
			)
		end
	end
	-- A fallen column and the arch that still stands.
	local fallen =
		part("Fallen", Vector3.new(14, 2.4, 2.4), CFrame.new(at + Vector3.new(4, 2.8, 16)) * CFrame.Angles(0, 0.5, 0.08), STONE, ruins, {
			Material = Enum.Material.Marble,
			Shape = Enum.PartType.Cylinder,
		})
	fallen.Shape = Enum.PartType.Cylinder
	part("ArchL", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(-18, 10, 0)), STONE, ruins, { Material = Enum.Material.Marble })
	part("ArchR", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(-18, 10, 12)), STONE, ruins, { Material = Enum.Material.Marble })
	part("ArchTop", Vector3.new(4, 3, 17), CFrame.new(at + Vector3.new(-18, 20, 6)), STONE, ruins, { Material = Enum.Material.Marble })
	-- A great stone head half in the sand, glowing eyes.
	local head = part("Head", Vector3.new(8, 8, 8), CFrame.new(at + Vector3.new(10, 3, -16)) * CFrame.Angles(0.2, -0.6, 0), STONE, ruins, {
		Material = Enum.Material.Slate,
	})
	for i, x in { -1.6, 1.6 } do
		part(
			"Eye" .. i,
			Vector3.new(1, 0.8, 0.4),
			head.CFrame * CFrame.new(x, 1, -4),
			hex("#4FF0E0"),
			ruins,
			{ Material = Enum.Material.Neon }
		)
	end
	body("ruins", CFrame.new(at + Vector3.new(0, 9, 0)), ruins)
end

local function buildBell(at: Vector3, surfaceY: number, parent: Instance)
	local bell = model("SurfaceBell", parent)
	disc("Base", 12, 1.2, at + Vector3.new(0, 0.6, 0), hex("#8FA39A"), bell, { Material = Enum.Material.Cobblestone })
	local pad = disc("ReturnPad", 8, 0.4, at + Vector3.new(0, 1.4, 0), hex("#FFE38A"), bell, { Material = Enum.Material.Neon })
	pad:SetAttribute("ReefPad", "return")
	part("Bell", Vector3.new(6, 7, 6), CFrame.new(at + Vector3.new(0, 7, 0)), hex("#C9A45C"), bell, {
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
	})
	-- The rope up to the surface: the way home is always in sight.
	local top = at.Y + 10
	local rope = math.max(1, surfaceY - top)
	column("Rope", 0.6, rope, at + Vector3.new(0, 10, 0), hex("#E8DCC0"), bell, { CanCollide = false })
	disc("Buoy", 4, 2, Vector3.new(at.X, surfaceY, at.Z), hex("#E5484D"), bell, { CanCollide = false })
	body("bell", CFrame.new(at + Vector3.new(0, 5, 0)), bell)
end

local function buildGate(at: Vector3, parent: Instance)
	local gate = model("Gate", parent)
	gate:SetAttribute("Screen", "Expeditions")
	gate:SetAttribute("Region", Cfg.Region)
	local rock = hex("#4C6F6B")
	part("PostL", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(-8, 9, 0)), rock, gate, { Material = Enum.Material.Slate })
	part("PostR", Vector3.new(3, 18, 3), CFrame.new(at + Vector3.new(8, 9, 0)), rock, gate, { Material = Enum.Material.Slate })
	part("Lintel", Vector3.new(20, 3, 4), CFrame.new(at + Vector3.new(0, 19, 0)), rock, gate, { Material = Enum.Material.Slate })
	for i, x in { -8, 0, 8 } do
		part("Crust" .. i, Vector3.new(2, 2, 2), CFrame.new(at + Vector3.new(x, 20.5, 0)), hex(CORAL[i]), gate, {
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
		})
	end
	local portal = part("Portal", Vector3.new(13, 16, 0.4), CFrame.new(at + Vector3.new(0, 9, 0)), hex("#5CE1E6"), gate, {
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
	})
	portal:SetAttribute("ReefGate", true)
	body("gate", CFrame.new(at + Vector3.new(0, 11, 0)), gate)
end

local function buildClam(at: Vector3, parent: Instance)
	local clam = model("GiantClam", parent)
	local shell = hex("#9FD8E0")
	part("Lower", Vector3.new(8, 2, 6), CFrame.new(at + Vector3.new(0, 1, 0)), shell, clam, { Material = Enum.Material.Marble })
	part("Upper", Vector3.new(8, 1.6, 6), CFrame.new(at + Vector3.new(0, 3.4, 2)) * CFrame.Angles(0.7, 0, 0), shell, clam, {
		Material = Enum.Material.Marble,
	})
	local pearl = part("Pearl", Vector3.new(2, 2, 2), CFrame.new(at + Vector3.new(0, 2.8, -0.5)), hex("#FFF6F0"), clam, {
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
	})
	local light = Instance.new("PointLight")
	light.Color = hex("#FFE9F4")
	light.Range = 14
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = pearl
	body("giantClam", CFrame.new(at + Vector3.new(0, 2.5, 0)), clam)
end

function ReefBuild.Area(parent: Instance, low: boolean?): Folder
	local A = Cfg.Area
	local C = Cfg.Counts
	local c = v3(A.center)
	local r = A.radius
	local area = Instance.new("Folder")
	area.Name = "Area"
	local rng = Rng.new(A.seed)

	local floor = disc("Floor", r * 2 + 40, 4, c - Vector3.new(0, 2, 0), hex("#D9C89A"), area, { Material = Enum.Material.Sand })
	floor.CanQuery = true
	part("Surface", Vector3.new(r * 2 + 60, 1, r * 2 + 60), CFrame.new(c.X, A.surfaceY + 0.5, c.Z), hex("#7FE3E8"), area, {
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
	})

	local bellAt, gateAt, ruinsAt = c + v3(A.bell), c + v3(A.gate), c + v3(A.ruins)
	local keep = { bellAt, gateAt, ruinsAt, c + Vector3.new(A.arrive[1], 0, A.arrive[3]) }

	local rocks = Instance.new("Folder")
	rocks.Name = "Rocks"
	rocks.Parent = area
	for i = 1, C.rocks do
		local a = (i / C.rocks) * math.pi * 2 + rng:Float(-0.1, 0.1)
		local d = r + rng:Float(-6, 8)
		local size = Vector3.new(rng:Float(14, 26), rng:Float(18, 44), rng:Float(14, 26))
		local at = Vector3.new(c.X + math.cos(a) * d, c.Y + size.Y * 0.35, c.Z + math.sin(a) * d)
		part(
			"Rock" .. i,
			size,
			CFrame.new(at) * CFrame.Angles(rng:Float(-0.2, 0.2), a, rng:Float(-0.2, 0.2)),
			hex(if i % 2 == 0 then "#3E5F66" else "#4C6F6B"),
			rocks,
			{
				Material = Enum.Material.Slate,
			}
		)
	end

	local coral = Instance.new("Folder")
	coral.Name = "Coral"
	coral.Parent = area
	for i = 1, C.coral do
		local at = spot(rng, c, 14, r - 18, keep, A.clear)
		local m = model("Coral" .. i, coral)
		part("Base", Vector3.new(5, 3, 5), CFrame.new(at + Vector3.new(0, 1, 0)), hex("#6D5A6E"), m, {
			Material = Enum.Material.Rock,
			Shape = Enum.PartType.Ball,
		})
		local glow = hex(CORAL[(i - 1) % #CORAL + 1])
		for b = 1, 3 do
			local h = rng:Float(3, 7)
			local lean = CFrame.Angles(rng:Float(-0.5, 0.5), rng:Float(0, math.pi * 2), rng:Float(-0.5, 0.5))
			local neon = b == 1
			local cf = CFrame.new(at + Vector3.new(0, 2, 0)) * lean * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			local branch = part("Branch" .. b, Vector3.new(h, if neon then 1 else 2.6, if neon then 1 else 0.5), cf, glow, m, {
				Material = if neon then Enum.Material.Neon else Enum.Material.Glass,
				Transparency = if neon then 0 else 0.25,
			})
			if neon then
				branch.Shape = Enum.PartType.Cylinder
			end
		end
		if not low and i % 3 == 0 then
			local light = Instance.new("PointLight")
			light.Color = glow
			light.Range = 12
			light.Brightness = 1.1
			light.Shadows = false
			light.Parent = m:FindFirstChild("Branch1")
		end
	end

	local kelp = Instance.new("Folder")
	kelp.Name = "Kelp"
	kelp.Parent = area
	for i = 1, C.kelp do
		local at = spot(rng, c, r * 0.35, r - 10, keep, A.clear - 6)
		local m = model("Kelp" .. i, kelp)
		m:SetAttribute("Seed", rng:Float(0, 100))
		local h = rng:Float(6, 11)
		local yaw = CFrame.Angles(0, rng:Float(0, math.pi * 2), 0)
		for s = 1, 3 do
			part(
				"Stalk" .. s,
				Vector3.new(0.5, h, 1.8 - s * 0.3),
				CFrame.new(at + Vector3.new(0, h * (s - 0.5), 0)) * yaw,
				hex(if s == 3 then "#4FBF6A" else "#2F8F4E"),
				m,
				{
					CanCollide = false,
				}
			)
		end
	end

	local vents = Instance.new("Folder")
	vents.Name = "Vents"
	vents.Parent = area
	for i = 1, C.vents do
		local at = spot(rng, c, 10, r - 20, keep, A.clear)
		local v = part("Vent" .. i, Vector3.new(3, 2, 3), CFrame.new(at + Vector3.new(0, 0.6, 0)), hex("#5A4A4A"), vents, {
			Material = Enum.Material.Basalt,
			Shape = Enum.PartType.Ball,
		})
		v:SetAttribute("ReefVent", true)
	end

	buildRuins(ruinsAt, area)
	buildBell(bellAt, A.surfaceY, area)
	buildGate(gateAt, area)
	buildClam(gateAt + Vector3.new(18, 0, -6), area)
	area.Parent = parent
	return area
end

return ReefBuild
