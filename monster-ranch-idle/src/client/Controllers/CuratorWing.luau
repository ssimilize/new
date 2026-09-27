--[[
	CuratorWing controller (update 3.12 · Museum Exhibits): the Curator wing east of the walk-in
	Codex Museum (Config.World.CuratorWing), built on this client from Parts for the local player's
	own exhibits (profile.Exhibits.filled). Pedestals per set in rows (Logic/Exhibits.Layout), a
	name board over each set, and the Curator desk at the open north side with an "Exhibits"
	prompt -> Router:Open("Exhibits").

	LOD like the Codex Museum (Logic/Museum.Plan): every pedestal keeps its plate (the exhibit's
	name, dimmed while empty); the nearest Wing.maxModels filled ones (lowModels in low graphics)
	build a small Part display (a skeleton, a fish in a tank, a relic block, a honey jar, a star
	globe) and drop it again when the camera moves away. Nothing is built in the hub place.

	Public (for specs):
	  CuratorWing.Prompt() -> ProximityPrompt?
	  CuratorWing.Stats() -> (displays, pedestals)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Exhibits)
local Museum = require(Shared.Logic.Museum)

local Client = script.Parent.Parent
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)

local New = Create.New
local W = Config.Exhibits.Wing

local CuratorWing = {
	Name = "CuratorWing",
	Dependencies = {},
}

local ctx
local folder: Folder? = nil
local prompt: ProximityPrompt? = nil
local layout
local pedestals = {} -- [i] = { part, label, set, item, def, display?, state }
local known = {} -- [line] = filled
local plan, scratch, previous = {}, {}, {}
local opts = { max = W.maxModels, modelRange = W.modelRange, signRange = W.signRange, previous = previous }
local lowGraphics = false
local connections = {}

local STONE = Color3.fromHex("#EDE3D3")
local WOOD = Color3.fromHex("#8A5A2B")
local EMPTY = Color3.fromHex("#B9B3A8")

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function deco(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, shape: Enum.PartType?): Part
	local p = part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = parent,
	})
	if shape then
		p.Shape = shape
	end
	return p
end

local function textSign(parent: BasePart, face: Enum.NormalId, text: string, size: Vector2): TextLabel
	local gui = New("SurfaceGui", {
		Face = face,
		CanvasSize = size,
		LightInfluence = 0,
		Parent = parent,
	})
	return Create.Text({
		Text = text,
		TextSize = Theme.TextSize.Title,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
end

local function hex(s: string?, fallback: string): Color3
	local ok, c = pcall(Color3.fromHex, s or fallback)
	return if ok then c else Color3.fromHex(fallback)
end

local function openScreen()
	if ctx.Router:Has("Exhibits") then
		ctx.Router:Open("Exhibits")
	end
end

local function buildWing()
	local f = Instance.new("Folder")
	f.Name = "CuratorWing"
	local b = layout.bounds
	local cx, cz = (b.minX + b.maxX) / 2, (b.minZ + b.maxZ) / 2
	local w, d = b.maxX - b.minX, b.maxZ - b.minZ
	local y = Config.World.GroundY or 0
	part({
		Name = "Floor",
		Size = Vector3.new(w, 0.6, d),
		CFrame = CFrame.new(cx, y + 0.3, cz),
		Color = STONE,
		Material = Enum.Material.Marble,
		Parent = f,
	})
	-- Low walls on three sides; the north side (+z) stays open, like the museum's entrance.
	local h = W.wallHeight
	for _, wall in
		{
			{ Vector3.new(w, h, 1), Vector3.new(cx, y + h / 2, b.minZ) },
			{ Vector3.new(1, h, d), Vector3.new(b.minX, y + h / 2, cz) },
			{ Vector3.new(1, h, d), Vector3.new(b.maxX, y + h / 2, cz) },
		}
	do
		part({ Name = "Wall", Size = wall[1], CFrame = CFrame.new(wall[2]), Color = STONE, Material = Enum.Material.Marble, Parent = f })
	end
	local arch = deco("Entrance", Vector3.new(24, 4, 1), CFrame.new(cx, y + h + 2, b.maxZ), Theme.Colors.Purple, f)
	textSign(arch, Enum.NormalId.Back, "Museum Exhibits", Vector2.new(480, 80))

	-- The Curator desk just inside the entrance, facing it.
	local desk = part({
		Name = "CuratorDesk",
		Size = Vector3.new(8, 3, 2.4),
		CFrame = CFrame.new(layout.desk.x, y + 2.1, layout.desk.z),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		Parent = f,
	})
	deco("DeskTop", Vector3.new(8.4, 0.3, 2.8), CFrame.new(layout.desk.x, y + 3.75, layout.desk.z), Theme.Colors.Purple, f)
	deco("Ledger", Vector3.new(1.4, 0.2, 1), CFrame.new(layout.desk.x - 2, y + 4, layout.desk.z), STONE, f)
	deco(
		"Lamp",
		Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(layout.desk.x + 2.6, y + 4.3, layout.desk.z),
		Theme.Colors.Gold,
		f,
		Enum.PartType.Ball
	)
	local anchor = Instance.new("Attachment")
	anchor.Name = "PromptAnchor"
	anchor.Position = Vector3.new(0, 2, 0)
	anchor.Parent = desk
	local p = Instance.new("ProximityPrompt")
	p.Name = "ExhibitsPrompt"
	p.ActionText = "Exhibits"
	p.ObjectText = "Curator"
	p.HoldDuration = 0
	p.MaxActivationDistance = W.promptDistance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = anchor
	table.insert(connections, p.Triggered:Connect(openScreen))
	prompt = p

	for _, row in layout.rows do
		local set = Config.Exhibits.ById[row.set]
		local board = deco("Set_" .. row.set, Vector3.new(14, 1.6, 0.4), CFrame.new(row.x, y + 4.2, row.z), hex(set.color, "#6B5BD6"), f)
		textSign(board, Enum.NormalId.Back, set.name, Vector2.new(300, 36))
	end

	local items = {}
	for _, set in Logic.Sets(Config) do
		for _, item in Logic.Items(Config, set.id) :: any do
			items[set.id .. ":" .. item.id] = item
		end
	end
	local size = Vector3.new(W.pedestal[1], W.pedestal[2], W.pedestal[3])
	for i, ped in layout.pedestals do
		local base = part({
			Name = ped.line,
			Size = size,
			CFrame = CFrame.new(ped.x, ped.y + size.Y / 2 + 0.6, ped.z),
			Color = EMPTY,
			Material = Enum.Material.Marble,
			Parent = f,
		})
		local def = items[ped.line]
		local label = textSign(base, Enum.NormalId.Back, def.name, Vector2.new(200, 60))
		pedestals[i] = { part = base, label = label, set = ped.set, def = def, line = ped.line, state = "plate" }
	end
	f.Parent = workspace
	folder = f
end

-- A small Part display for one filled exhibit, standing on its pedestal.
local function buildDisplay(ped): Model
	local model = Instance.new("Model")
	model.Name = "Display"
	local top = ped.part.Position + Vector3.new(0, ped.part.Size.Y / 2, 0)
	local c1 = hex(ped.def.color, "#EDE3D3")
	local c2 = hex(ped.def.color2, "#3A2A1C")
	local at = CFrame.new(top)
	if ped.set == "fossils" then
		deco("Skull", Vector3.new(0.9, 0.9, 0.9), at * CFrame.new(0, 1.3, -0.5), c1, model, Enum.PartType.Ball)
		deco("Ribs", Vector3.new(0.7, 0.8, 1.4), at * CFrame.new(0, 0.9, 0.3), c1, model)
		deco("Stand", Vector3.new(0.2, 0.5, 0.2), at * CFrame.new(0, 0.25, 0), c2, model)
	elseif ped.set == "aquarium" then
		local tank = deco("Tank", Vector3.new(1.8, 1.4, 1.2), at * CFrame.new(0, 0.7, 0), Color3.fromHex("#9ED8F0"), model)
		tank.Transparency = 0.6
		deco("Fish", Vector3.new(0.9, 0.5, 0.35), at * CFrame.new(0, 0.75, 0), c1, model, Enum.PartType.Ball)
	elseif ped.set == "relics" then
		deco("Relic", Vector3.new(1, 1.1, 1), at * CFrame.new(0, 0.55, 0), c1, model)
		deco("Trim", Vector3.new(1.1, 0.2, 1.1), at * CFrame.new(0, 1.2, 0), c2, model)
	elseif ped.set == "honey" then
		local jar = deco(
			"Jar",
			Vector3.new(1.2, 0.9, 0.9),
			at * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
			c1,
			model,
			Enum.PartType.Cylinder
		)
		jar.Transparency = 0.15
		deco(
			"Lid",
			Vector3.new(0.2, 1, 1),
			at * CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
			WOOD,
			model,
			Enum.PartType.Cylinder
		)
	else
		deco("Globe", Vector3.new(1.2, 1.2, 1.2), at * CFrame.new(0, 0.8, 0), Color3.fromHex("#2B2250"), model, Enum.PartType.Ball)
		local star = deco("Star", Vector3.new(0.45, 0.45, 0.45), at * CFrame.new(0.3, 1.1, -0.45), c1, model, Enum.PartType.Ball)
		star.Material = Enum.Material.Neon
	end
	model.Parent = folder
	return model
end

local function apply(i: number, state: string)
	local ped = pedestals[i]
	-- "sign" and "plate" look the same here: the plate always shows the name.
	local want = if state == "model" then "model" else "plate"
	if ped.state == want then
		previous[i] = state
		return
	end
	if ped.display then
		ped.display:Destroy()
		ped.display = nil
	end
	if want == "model" then
		ped.display = buildDisplay(ped)
	end
	ped.state = want
	previous[i] = state
end

local function readFilled()
	local filled = ctx.Store:Get("profile.Exhibits.filled")
	for i, ped in pedestals do
		local mine = type(filled) == "table" and filled[ped.set]
		local on = type(mine) == "table" and mine[ped.def.id] == true
		if known[ped.line] ~= on then
			known[ped.line] = on
			ped.part.Color = if on then STONE else EMPTY
			ped.label.TextTransparency = if on then 0 else 0.4
			if not on and ped.display then
				ped.display:Destroy()
				ped.display = nil
				ped.state = "plate"
				previous[i] = "plate"
			end
		end
	end
end

local function step()
	local camera = workspace.CurrentCamera
	if not folder or not camera then
		return
	end
	local at = camera.CFrame.Position
	opts.max = if lowGraphics then W.lowModels else W.maxModels
	Museum.Plan(layout.pedestals, at.X, at.Z, known, opts, plan, scratch)
	for i = 1, #pedestals do
		apply(i, plan[i] or "plate")
	end
end

function CuratorWing.Init(context)
	ctx = context
end

function CuratorWing.Start()
	local built = false
	local acc = math.huge
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < W.updateEvery then
				return
			end
			acc = 0
			if not built then
				if not ctx.Store.Ready or ctx.Store:Get("global.TradingHub.mode") == "hub" then
					return
				end
				built = true
				layout = Logic.Layout(Config)
				buildWing()
				readFilled()
				table.insert(connections, ctx.Store:Observe("profile.Exhibits", readFilled))
				table.insert(
					connections,
					ctx.Store:Observe("profile.Settings", function(settings)
						lowGraphics = type(settings) == "table" and settings.lowGraphics == true
					end)
				)
			end
			step()
		end)
	)
end

function CuratorWing.Prompt(): ProximityPrompt?
	return prompt
end

function CuratorWing.Stats(): (number, number)
	local live = 0
	for _, ped in pedestals do
		if ped.display then
			live += 1
		end
	end
	return live, #pedestals
end

-- Not called by the kernel today; kept so the controller can be unplugged.
function CuratorWing.Destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(pedestals)
	table.clear(known)
	if folder then
		folder:Destroy()
		folder = nil
	end
	prompt = nil
end

return CuratorWing
