--[[
	World/Build (C1): procedural placeholder geometry for the whole map, built from
	Config.World. Pure construction: returns an unparented Folder "World" so the caller can
	parent it in one step (clients receive the whole tree at once).

	Layout (all under Workspace.World):
	  Ground                         Part, grass, top at Config.World.GroundY
	  Paths/Path<i>                  dirt paths from the plaza to each plot gate
	  Hub/Plaza, Hub/Fountain        plaza disc and fountain model
	  Hub/Buildings/<id>             Model (attrs HubId, Screen, Name) with Body, Roof*, Sign, Door
	  Plots/Plot<i>                  Model (attr PlotId)
	    Floor                        Part (attr PlotId)
	    Pens/Pen<n>                  Model (attrs PlotId, PenIndex)
	      Floor                      Part (attrs PlotId, PenIndex) top = standing height
	      Rail*, Post*               low fence with collision
	    IncubatorPad                 Part (attrs PlotId, Incubator = true)
	    Barn                         Model (attr PlotId) with Body, Roof*, Door
	    Gate                         Model with PostL, PostR, Sign (client adds the owner name)
	  SpawnLocation
	  Sky/Islands/<id>               Model: Top (walkable grass disc), Rock* underside, Tree*
	  Sky/Bridges/Bridge<i>          cloud bridges between island edges
	  Sky/LaunchPad, Sky/ReturnPad   pads (attr SkyPad = "launch"|"return"); the client adds prompts
	  Sky/Gate                       arch (attr Screen = "Expeditions", Region = "sky")

	On the Trading Hub place (Build.world(Config, "hub"), update 3.0): Ground, Hub/Plaza and
	Hub/Buildings/<id> from Config.TradingHub.World (booths are booth1..n, screen "Trade"),
	empty Plots and Paths folders, and the SpawnLocation. No plots and no Sky.

	Plot frame: plot-local +X points at the hub (Config.World.Plots[i].facing is the compass
	heading of that direction, 0 = +Z, 90 = +X). Pen, incubator, barn and statue offsets are
	in this frame. Clients use the same maths (Controllers/World.luau).
]]

local Build = {}

local hex = Color3.fromHex

local COLORS = {
	grass = hex("#7CC456"),
	plot = hex("#8FD35F"),
	path = hex("#C9A26B"),
	plaza = hex("#E8DCC0"),
	plazaEdge = hex("#CDBF9E"),
	stone = hex("#B9B3A5"),
	water = hex("#5EC3F2"),
	penGround = hex("#A2D776"),
	fence = hex("#9C6130"),
	fenceDark = hex("#7A4A22"),
	barn = hex("#C8473C"),
	barnRoof = hex("#6B3A2A"),
	white = hex("#FFFFFF"),
	door = hex("#4A3526"),
	pad = hex("#EFE3C4"),
	padRim = hex("#F2A93B"),
	sign = hex("#FFF7E3"),
	ink = hex("#2A2419"),
}

local PEN_FLOOR_HEIGHT = 0.8 -- floor top sits at GroundY + 0.4
local FENCE_HEIGHT = 2.2
local FENCE_THICKNESS = 0.5

local count = 0

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function newPart(
	className: string,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	props: { [string]: any }?
)
	local p = Instance.new(className)
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if props then
		for key, value in props do
			(p :: any)[key] = value
		end
	end
	p.Parent = parent
	count += 1
	return p
end

local function block(name, size, cframe, color, parent, props)
	return newPart("Part", name, size, cframe, color, parent, props)
end

-- Vertical cylinder: `diameter` wide, `height` tall, centred at `center`.
local function disc(name: string, diameter: number, height: number, center: Vector3, color: Color3, parent: Instance, props)
	local p = newPart(
		"Part",
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		parent,
		props
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Gable roof (two wedges) on top of a box of `size` whose centre is `cframe`.
local function gableRoof(parent: Instance, cframe: CFrame, size: Vector3, color: Color3, pitch: number)
	local roofH = size.Y * pitch
	local depth = size.Z / 2 + 0.6
	local y = size.Y / 2 + roofH / 2
	local roofSize = Vector3.new(size.X + 1.2, roofH, depth)
	newPart("WedgePart", "RoofFront", roofSize, cframe * CFrame.new(0, y, -depth / 2), color, parent)
	newPart("WedgePart", "RoofBack", roofSize, cframe * CFrame.new(0, y, depth / 2) * CFrame.Angles(0, math.pi, 0), color, parent)
end

local function surfaceSign(part: BasePart, text: string, background: Color3, textColor: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = background
	label.BorderSizePixel = 0
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = textColor
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = part
	return gui
end

local function billboardSign(part: BasePart, text: string, color: Color3, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameGui"
	gui.Size = UDim2.fromScale(18, 4)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = COLORS.white
	local stroke = Instance.new("UIStroke")
	stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.55)
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
	return gui
end

-- The CFrame of a plot at ground level; plot-local +X faces the hub.
function Build.plotFrame(World, plot): CFrame
	local c = plot.center
	return CFrame.new(c[1], World.GroundY, c[3]) * CFrame.Angles(0, math.rad((plot.facing or 0) - 90), 0)
end

local function buildGround(World, root: Instance)
	local size = World.GroundSize
	block(
		"Ground",
		Vector3.new(size[1], 4, size[2]),
		CFrame.new(0, World.GroundY - 2, 0),
		COLORS.grass,
		root,
		{ Material = Enum.Material.Grass, CastShadow = false }
	)
end

-- Hub buildings: a box with a gable roof, sign and door, facing the fountain at the origin.
local function buildBuildings(defs, buildings: Instance, y: number)
	for _, def in defs do
		local model = Instance.new("Model")
		model.Name = def.id
		local size = v3(def.size)
		local color = hex(def.color)
		local pos = v3(def.position)
		local center = Vector3.new(pos.X, y + 0.3 + size.Y / 2, pos.Z)
		local toHub = Vector3.new(0, center.Y, 0)
		-- Face the fountain; a building exactly at the origin keeps the default facing.
		local cf = if (toHub - center).Magnitude > 0.1 then CFrame.lookAt(center, toHub) else CFrame.new(center)

		local body = block("Body", size, cf, color, model)
		gableRoof(model, cf, size, color:Lerp(Color3.new(0, 0, 0), 0.35), 0.4)
		local sign = block(
			"Sign",
			Vector3.new(size.X * 0.75, math.min(3.4, size.Y * 0.22), 0.4),
			cf * CFrame.new(0, size.Y / 2 - math.min(3.4, size.Y * 0.22) / 2 - 1, -size.Z / 2 - 0.25),
			COLORS.sign,
			model
		)
		surfaceSign(sign, def.name, COLORS.sign, COLORS.ink)
		local doorH = math.min(8, size.Y * 0.45)
		block(
			"Door",
			Vector3.new(math.min(7, size.X * 0.3), doorH, 0.4),
			cf * CFrame.new(0, -size.Y / 2 + doorH / 2, -size.Z / 2 - 0.2),
			COLORS.door,
			model
		)
		billboardSign(body, def.name, color, size.Y * 0.5 + size.Y * 0.4 + 3)

		model.PrimaryPart = body
		model:SetAttribute("HubId", def.id)
		model:SetAttribute("Screen", def.screen)
		model:SetAttribute("DisplayName", def.name)
		body:SetAttribute("HubId", def.id)
		body:SetAttribute("Screen", def.screen)
		model.Parent = buildings
	end
end

local function buildHub(World, root: Instance)
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = root
	local y = World.GroundY

	disc("Plaza", World.HubRadius * 2, 0.6, Vector3.new(0, y, 0), COLORS.plaza, hub, { CastShadow = false })
	disc("PlazaEdge", World.HubRadius * 2 + 4, 0.5, Vector3.new(0, y - 0.05, 0), COLORS.plazaEdge, hub, { CastShadow = false })

	-- Fountain
	local fountain = Instance.new("Model")
	fountain.Name = "Fountain"
	local fp = v3(World.Fountain.position)
	local r = World.Fountain.radius
	local basin = disc("Basin", r * 2, 1.6, fp + Vector3.new(0, y + 0.8, 0), COLORS.stone, fountain)
	disc("Water", r * 2 - 2.5, 0.2, fp + Vector3.new(0, y + 1.45, 0), COLORS.water, fountain, {
		CanCollide = false,
		Transparency = 0.15,
		Material = Enum.Material.Glass,
		CastShadow = false,
	})
	disc("Pillar", 3, 5, fp + Vector3.new(0, y + 4.1, 0), COLORS.stone, fountain)
	disc("Bowl", 8, 0.8, fp + Vector3.new(0, y + 6.6, 0), COLORS.stone, fountain)
	disc("BowlWater", 6.6, 0.2, fp + Vector3.new(0, y + 7.05, 0), COLORS.water, fountain, {
		CanCollide = false,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CastShadow = false,
	})
	fountain.PrimaryPart = basin
	fountain.Parent = hub

	-- Buildings
	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = hub
	buildBuildings(World.Hub, buildings, y)

	-- Leaderboard: a framed board on two posts. Clients draw the rows onto Body's front face
	-- (Controllers/Leaderboards); the prompt comes from the Screen attribute like the buildings.
	if World.Board then
		local def = World.Board
		local model = Instance.new("Model")
		model.Name = "leaderboard"
		local size = v3(def.size)
		local pos = v3(def.position)
		local lift = 2.5
		local center = Vector3.new(pos.X, y + 0.3 + lift + size.Y / 2, pos.Z)
		local toHub = Vector3.new(0, center.Y, 0)
		local cf = if (toHub - center).Magnitude > 0.1 then CFrame.lookAt(center, toHub) else CFrame.new(center)
		local frameColor = hex(def.color)
		local body = block("Body", size, cf, COLORS.sign, model)
		block("Frame", size + Vector3.new(1.2, 1.2, -0.4), cf * CFrame.new(0, 0, 0.5), frameColor, model)
		for _, side in { -1, 1 } do
			block(
				"Post",
				Vector3.new(1, size.Y + lift, 1),
				cf * CFrame.new(side * (size.X / 2 + 0.2), -lift / 2, 0.9),
				frameColor:Lerp(Color3.new(0, 0, 0), 0.3),
				model
			)
		end
		billboardSign(body, "Leaderboards", frameColor, size.Y / 2 + 3)
		model.PrimaryPart = body
		model:SetAttribute("HubId", "leaderboard")
		model:SetAttribute("Screen", "Leaderboards")
		model:SetAttribute("DisplayName", "Leaderboards")
		body:SetAttribute("HubId", "leaderboard")
		body:SetAttribute("Screen", "Leaderboards")
		model.Parent = buildings
	end
end

local function buildPen(plotId: number, penIndex: number, plotCf: CFrame, World, parent: Instance)
	local offset = World.PenOffsets[penIndex]
	local w, d = World.PenSize[1], World.PenSize[2]
	local model = Instance.new("Model")
	model.Name = "Pen" .. penIndex
	local base = plotCf * CFrame.new(offset[1], offset[2], offset[3])

	local floor = block("Floor", Vector3.new(w, PEN_FLOOR_HEIGHT, d), base, COLORS.penGround, model, { CastShadow = false })
	floor:SetAttribute("PlotId", plotId)
	floor:SetAttribute("PenIndex", penIndex)

	local top = PEN_FLOOR_HEIGHT / 2
	local railY = top + FENCE_HEIGHT / 2
	local t = FENCE_THICKNESS
	block("RailN", Vector3.new(w, FENCE_HEIGHT, t), base * CFrame.new(0, railY, -d / 2 + t / 2), COLORS.fence, model)
	block("RailS", Vector3.new(w, FENCE_HEIGHT, t), base * CFrame.new(0, railY, d / 2 - t / 2), COLORS.fence, model)
	block("RailW", Vector3.new(t, FENCE_HEIGHT, d - t * 2), base * CFrame.new(-w / 2 + t / 2, railY, 0), COLORS.fence, model)
	block("RailE", Vector3.new(t, FENCE_HEIGHT, d - t * 2), base * CFrame.new(w / 2 - t / 2, railY, 0), COLORS.fence, model)
	local postH = FENCE_HEIGHT + 0.7
	for i, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		block(
			"Post" .. i,
			Vector3.new(0.9, postH, 0.9),
			base * CFrame.new(corner[1] * (w / 2 - t / 2), top + postH / 2, corner[2] * (d / 2 - t / 2)),
			COLORS.fenceDark,
			model
		)
	end

	model.PrimaryPart = floor
	model:SetAttribute("PlotId", plotId)
	model:SetAttribute("PenIndex", penIndex)
	model.Parent = parent
end

local function buildPlot(World, plot, parent: Instance)
	local plotCf = Build.plotFrame(World, plot)
	local model = Instance.new("Model")
	model.Name = "Plot" .. plot.id
	model:SetAttribute("PlotId", plot.id)

	local sx, sz = World.PlotSize[1], World.PlotSize[2]
	local floor = block("Floor", Vector3.new(sx, 0.6, sz), plotCf, COLORS.plot, model, { CastShadow = false })
	floor:SetAttribute("PlotId", plot.id)
	model.PrimaryPart = floor

	local pens = Instance.new("Folder")
	pens.Name = "Pens"
	pens.Parent = model
	for penIndex = 1, math.min(5, #World.PenOffsets) do
		buildPen(plot.id, penIndex, plotCf, World, pens)
	end

	-- Incubator pad
	local io = World.IncubatorOffset
	local padCenter = (plotCf * CFrame.new(io[1], 0.4, io[3])).Position
	disc("IncubatorRim", 15, 0.6, padCenter - Vector3.new(0, 0.1, 0), COLORS.padRim, model, { CastShadow = false })
	local pad = disc("IncubatorPad", 13, 0.8, padCenter, COLORS.pad, model, { CastShadow = false })
	pad:SetAttribute("PlotId", plot.id)
	pad:SetAttribute("Incubator", true)

	-- Barn (door faces the plot centre, plot-local -Z)
	local bo = World.BarnOffset
	local barn = Instance.new("Model")
	barn.Name = "Barn"
	local barnSize = Vector3.new(14, 10, 12)
	local barnCf = plotCf * CFrame.new(bo[1], 0.3 + barnSize.Y / 2, bo[3])
	local barnBody = block("Body", barnSize, barnCf, COLORS.barn, barn)
	gableRoof(barn, barnCf * CFrame.Angles(0, math.rad(90), 0), Vector3.new(barnSize.Z, barnSize.Y, barnSize.X), COLORS.barnRoof, 0.45)
	block("Door", Vector3.new(5, 6.5, 0.4), barnCf * CFrame.new(0, -barnSize.Y / 2 + 3.25, -barnSize.Z / 2 - 0.2), COLORS.door, barn)
	block("DoorTrim", Vector3.new(5.8, 0.6, 0.5), barnCf * CFrame.new(0, -barnSize.Y / 2 + 6.8, -barnSize.Z / 2 - 0.2), COLORS.white, barn)
	barn.PrimaryPart = barnBody
	barn:SetAttribute("PlotId", plot.id)
	barn.Parent = model

	-- Gate at the front edge (facing the hub); the client writes the owner's name above it.
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local gx = sx / 2 - 2
	local postH = 9
	local postL = block("PostL", Vector3.new(1.2, postH, 1.2), plotCf * CFrame.new(gx, 0.3 + postH / 2, -8), COLORS.fence, gate)
	block("PostR", Vector3.new(1.2, postH, 1.2), plotCf * CFrame.new(gx, 0.3 + postH / 2, 8), COLORS.fence, gate)
	local sign =
		block("Sign", Vector3.new(0.6, 2.4, 18), plotCf * CFrame.new(gx, 0.3 + postH - 0.6, 0), COLORS.sign, gate, { CanCollide = false })
	sign:SetAttribute("PlotId", plot.id)
	gate.PrimaryPart = postL
	gate.Parent = model

	model.Parent = parent
	return plotCf
end

local function buildPath(World, plotCf: CFrame, index: number, parent: Instance)
	local front = (plotCf * CFrame.new(World.PlotSize[1] / 2, 0, 0)).Position
	local flat = Vector3.new(front.X, 0, front.Z)
	if flat.Magnitude < World.HubRadius then
		return
	end
	local start = flat.Unit * (World.HubRadius - 2)
	local finish = flat + flat.Unit * 3
	local mid = (start + finish) / 2
	local length = (finish - start).Magnitude
	block(
		"Path" .. index,
		Vector3.new(12, 0.4, length),
		CFrame.lookAt(Vector3.new(mid.X, World.GroundY, mid.Z), Vector3.new(finish.X, World.GroundY, finish.Z)),
		COLORS.path,
		parent,
		{ Material = Enum.Material.Ground, CastShadow = false }
	)
end

local function buildSpawn(World, root: Instance)
	local s = World.Spawn
	-- Config.World.Spawn's Y is where characters appear; the pad itself sits on the plaza.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(s[1], World.GroundY + 0.3, s[3])
	spawn.Color = COLORS.padRim
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.CanTouch = true
	spawn.Parent = root
	count += 1
end

-- Update 2.0 · Sky Islands --------------------------------------------------------------

local SKY = {
	rock = hex("#B7A993"),
	rockDark = hex("#8E7F6A"),
	cloud = hex("#F4FAFF"),
	pad = hex("#8EC9FF"),
	padRim = hex("#FFFFFF"),
	gate = hex("#F2C94C"),
	trunk = hex("#9C6130"),
	leaves = hex("#7FD18B"),
}

local function buildSky(World, root: Instance)
	local Sky = World.Sky
	if not Sky then
		return
	end
	local sky = Instance.new("Folder")
	sky.Name = "Sky"
	sky.Parent = root
	local islands = Instance.new("Folder")
	islands.Name = "Islands"
	islands.Parent = sky
	local byId = {}
	for _, def in Sky.islands do
		byId[def.id] = def
		local model = Instance.new("Model")
		model.Name = def.id
		model:SetAttribute("Island", def.name)
		model.Parent = islands
		local c = v3(def.center)
		local r = def.radius
		-- Grass top (its top face is `center`), then a rocky underside that narrows.
		disc("Top", r * 2, 2, c - Vector3.new(0, 1, 0), hex(def.grass), model, { Material = Enum.Material.Grass })
		disc("Rock1", r * 1.9, 6, c - Vector3.new(0, 5, 0), SKY.rock, model, { Material = Enum.Material.Slate, CanCollide = false })
		disc("Rock2", r * 1.35, 8, c - Vector3.new(0, 12, 0), SKY.rockDark, model, { Material = Enum.Material.Slate, CanCollide = false })
		disc("Rock3", r * 0.7, 10, c - Vector3.new(0, 20, 0), SKY.rockDark, model, { Material = Enum.Material.Slate, CanCollide = false })
		-- Two trees at fixed spots on each island.
		for i, angle in { 40, 220 } do
			local a = math.rad(angle + #def.id * 17)
			local at = c + Vector3.new(math.cos(a) * r * 0.6, 0, math.sin(a) * r * 0.6)
			block("Trunk" .. i, Vector3.new(1.6, 7, 1.6), CFrame.new(at + Vector3.new(0, 3.5, 0)), SKY.trunk, model)
			local leaves =
				block("Tree" .. i, Vector3.new(8, 7, 8), CFrame.new(at + Vector3.new(0, 9, 0)), SKY.leaves, model, { CanCollide = false })
			leaves.Shape = Enum.PartType.Ball
		end
	end

	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	bridges.Parent = sky
	for i, pair in Sky.bridges do
		local a, b = byId[pair[1]], byId[pair[2]]
		if a and b then
			local ca, cb = v3(a.center), v3(b.center)
			local flat = Vector3.new(cb.X - ca.X, 0, cb.Z - ca.Z).Unit
			local from = ca + flat * (a.radius - 2) - Vector3.new(0, 0.5, 0)
			local to = cb - flat * (b.radius - 2) - Vector3.new(0, 0.5, 0)
			local mid = (from + to) / 2
			block(
				"Bridge" .. i,
				Vector3.new(8, 1, (to - from).Magnitude),
				CFrame.lookAt(mid, to),
				SKY.cloud,
				bridges,
				{ Material = Enum.Material.SmoothPlastic }
			)
		end
	end

	local launch = disc("LaunchPad", 12, 1, v3(Sky.launchPad) + Vector3.new(0, 0.5, 0), SKY.pad, sky, { Material = Enum.Material.Neon })
	launch:SetAttribute("SkyPad", "launch")
	disc("LaunchPadRim", 14, 0.8, v3(Sky.launchPad) + Vector3.new(0, 0.3, 0), SKY.padRim, sky)
	local back = disc("ReturnPad", 10, 1, v3(Sky.returnPad) + Vector3.new(0, 0.5, 0), SKY.pad, sky, { Material = Enum.Material.Neon })
	back:SetAttribute("SkyPad", "return")

	local gate = Instance.new("Model")
	gate.Name = "Gate"
	gate:SetAttribute("Screen", "Expeditions")
	gate:SetAttribute("Region", "sky")
	gate.Parent = sky
	local g = v3(Sky.gate)
	block("PostL", Vector3.new(2, 14, 2), CFrame.new(g + Vector3.new(-7, 7, 0)), SKY.gate, gate)
	block("PostR", Vector3.new(2, 14, 2), CFrame.new(g + Vector3.new(7, 7, 0)), SKY.gate, gate)
	block("Lintel", Vector3.new(18, 2, 2.4), CFrame.new(g + Vector3.new(0, 15, 0)), SKY.gate, gate)
	local portal = block("Portal", Vector3.new(12, 13, 0.4), CFrame.new(g + Vector3.new(0, 7, 0)), hex("#BFE3FF"), gate, {
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
	})
	portal:SetAttribute("SkyGate", true)
end

-- Builds the world and returns (folder, partCount). The folder is not parented yet.
-- Update 3.0 · the Trading Hub place ---------------------------------------------------

-- The hub place: a big plaza with the Trade Board, Trading Plaza, Market, trade booths in a
-- ring and the portal back to the ranch. Empty Plots/Paths folders keep clients happy.
local function buildTradingHub(Config, root: Instance)
	local World = Config.World
	local Hub = Config.TradingHub.World
	local y = World.GroundY
	buildGround(World, root)
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = root
	disc("Plaza", Hub.plazaRadius * 2, 0.6, Vector3.new(0, y, 0), COLORS.plaza, hub, { CastShadow = false })
	disc("PlazaEdge", Hub.plazaRadius * 2 + 4, 0.5, Vector3.new(0, y - 0.05, 0), COLORS.plazaEdge, hub, { CastShadow = false })
	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = hub
	local defs = table.clone(Hub.buildings)
	local b = Hub.booths
	for i = 1, b.count do
		local angle = (i - 0.5) / b.count * math.pi * 2
		table.insert(defs, {
			id = "booth" .. i,
			name = "Trade Booth",
			position = { math.cos(angle) * b.radius, 0, math.sin(angle) * b.radius },
			size = b.size,
			color = b.colors[(i - 1) % #b.colors + 1],
			screen = "Trade",
		})
	end
	buildBuildings(defs, buildings, y)
	for _, name in { "Plots", "Paths" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = root
	end
	buildSpawn({ GroundY = y, Spawn = Hub.spawn }, root)
end

function Build.world(Config, mode: string?): (Folder, number)
	count = 0
	local World = Config.World
	local root = Instance.new("Folder")
	root.Name = "World"
	if mode == "hub" then
		root:SetAttribute("PlaceMode", "hub")
		buildTradingHub(Config, root)
		root:SetAttribute("PartCount", count)
		return root, count
	end

	buildGround(World, root)
	buildHub(World, root)

	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = root
	local paths = Instance.new("Folder")
	paths.Name = "Paths"
	paths.Parent = root
	for index, plot in World.Plots do
		local plotCf = buildPlot(World, plot, plots)
		buildPath(World, plotCf, index, paths)
	end

	buildSpawn(World, root)
	buildSky(World, root)
	root:SetAttribute("PartCount", count)
	return root, count
end

return Build
