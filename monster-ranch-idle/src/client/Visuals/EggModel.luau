--[[
	EggModel: the eggs. Contract: a Model with PrimaryPart "Root" (the shell, size x 1.3 size x size),
	anchored unless opts.anchored == false, attribute EggType.

	The art is the shared egg mesh (the Crystal Egg's faceted gem egg for eggs in EggAssets.shapes)
	with the egg's painted texture, plus a small ornament for a few eggs (tools/blender/eggs.py; ids in
	EggAssets). Each mesh is built once (AssetService:CreateMeshPartAsync, the way MeshMonster builds
	monsters) and cloned. An egg whose mesh or texture id is still empty, or a runtime without
	CreateMeshPartAsync (the Lune test mock), gets the procedural placeholder: a stretched sphere with
	four spots.

		EggModel.Has(eggType) -> boolean              the real art is published and loadable
		EggModel.Build(eggType, opts?) -> Model
		    opts.anchored   false = unanchored (default anchored)
		    opts.size       egg width in studs (default 2)
		    opts.tint       Color3: a plain shell in this colour with white paint over it (the Spring
		                    Bloom hunt's painted eggs) instead of the egg's texture
		    opts.vfx        false = no particles (ViewportFrames do not draw them)
		EggModel.SetCrack(model, stage)               0 = whole .. 3 = about to hatch (the hatch cinematic);
		                                              attribute CrackStage
		EggModel.SetReady(model, ready)               a gentle warm glow and rising twinkles while an
		                                              incubator egg is ready to hatch; attribute Ready
		EggModel.SetMeshLoader(loader?)               tests: replaces CreateMeshPartAsync (uri -> MeshPart);
		                                              nil restores it

	Sparkles are the game's particles (Visuals/Vfx, Config.Vfx.Eggs), not the old Sparkles instance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Assets = require(script.Parent.EggAssets)
local Vfx = require(script.Parent.Vfx)

local EggModel = {}

local HEIGHT = 1.3 -- the shell's height per unit of width (the mesh is 1 x 1.3 x 1)
local CRACK_SCALE = 1.03 -- the crack overlay sits just outside the shell (tools/blender/eggs.py CRACK_SCALE)
local PAINT_SCALE = 1.01
local CRACK_COLOR = Color3.fromHex("#2B2320")
local READY_COLOR = Color3.fromHex("#FFD98A")

type Loader = (uri: string) -> MeshPart

local templates: { [string]: MeshPart } = {}
local loading: { [string]: boolean } = {}
local failed: { [string]: boolean } = {}
local customLoader: Loader? = nil
local available: boolean? = nil

-- Looked up lazily: the Lune test mock has no AssetService, and there the placeholder is used.
local function isAvailable(): boolean
	if customLoader then
		return true
	end
	if available == nil then
		available = pcall(function()
			assert(Content and Content.fromUri, "no Content")
			assert(game:GetService("AssetService").CreateMeshPartAsync, "no CreateMeshPartAsync")
		end)
	end
	return available == true
end

local function set(id: any): boolean
	return type(id) == "string" and id ~= ""
end

local function shapeOf(eggType: string): string
	return (Assets.shapes :: any)[eggType] or "shell"
end

-- The mesh at its modelled size, made once per id and cloned. CreateMeshPartAsync yields, so a
-- second build of the same mesh waits for the first. nil when it cannot be made (the caller falls
-- back); a failed id is not retried every build.
local function template(uri: string): MeshPart?
	while loading[uri] do
		task.wait()
	end
	local found = templates[uri]
	if found or failed[uri] then
		return found
	end
	loading[uri] = true
	local ok, made = pcall(function(): MeshPart
		if customLoader then
			return customLoader(uri)
		end
		return game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri(uri))
	end)
	loading[uri] = nil
	if not ok or typeof(made) ~= "Instance" then
		failed[uri] = true
		warn("[EggModel] could not load egg mesh " .. uri .. ": " .. tostring(made))
		return nil
	end
	made.CanCollide = false
	made.CanQuery = false
	made.CanTouch = false
	made.CastShadow = true
	made.Anchored = false
	made.Material = Enum.Material.SmoothPlastic
	templates[uri] = made
	return made
end

local function quiet(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function weldTo(root: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

function EggModel.SetMeshLoader(loader: Loader?)
	customLoader = loader
	table.clear(templates)
	table.clear(failed)
end

function EggModel.Has(eggType: string?): boolean
	if type(eggType) ~= "string" then
		return false
	end
	local mesh = (Assets.meshes :: any)[shapeOf(eggType)]
	return set(mesh) and set((Assets.textures :: any)[eggType]) and isAvailable()
end

-- ─── Placeholder ─────────────────────────────────────────────────────────────────────

local SPOTS = {
	Vector3.new(0.45, 0.2, -0.3),
	Vector3.new(-0.4, -0.15, -0.3),
	Vector3.new(0.1, 0.45, 0.4),
	Vector3.new(-0.2, -0.4, 0.45),
}

local function placeholder(def, size: number, tint: Color3?): (Model, BasePart)
	local shellColor = tint or Color3.fromHex(def and def.colors.shell or "#C9EDA8")
	local spotColor = if tint then Color3.new(1, 1, 1) else Color3.fromHex(def and def.colors.spots or "#79C455")
	local model = Instance.new("Model")
	local shell = Instance.new("Part")
	shell.Name = "Root"
	-- Block + sphere mesh: a Ball part cannot be stretched into an egg shape.
	shell.Size = Vector3.new(size, size * HEIGHT, size)
	local shellMesh = Instance.new("SpecialMesh")
	shellMesh.MeshType = Enum.MeshType.Sphere
	shellMesh.Parent = shell
	shell.Color = shellColor
	shell.Material = if def and def.pattern == "facets" then Enum.Material.Glass else Enum.Material.SmoothPlastic
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CFrame = CFrame.new()
	shell.Parent = model
	for i, dir in SPOTS do
		local unit = dir.Unit
		local surface = Vector3.new(unit.X * size / 2, unit.Y * size * HEIGHT / 2, unit.Z * size / 2)
		local spot = Instance.new("Part")
		spot.Name = "Spot" .. i
		spot.Size = Vector3.new(size * 0.3, size * 0.3, size * 0.1)
		local spotMesh = Instance.new("SpecialMesh")
		spotMesh.MeshType = Enum.MeshType.Sphere
		spotMesh.Parent = spot
		spot.Color = spotColor
		spot.Material = if def and def.pattern == "stars" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		quiet(spot)
		spot.Anchored = false
		spot.CFrame = CFrame.lookAt(surface, surface * 2)
		weldTo(shell, spot)
		spot.Parent = model
	end
	return model, shell
end

-- ─── Mesh ────────────────────────────────────────────────────────────────────────────

local function overlay(root: BasePart, shape: string, name: string, textureId: string, scale: number): MeshPart?
	local base = template((Assets.meshes :: any)[shape])
	if not base then
		return nil
	end
	local part = base:Clone()
	part.Name = name
	part.Size = root.Size * scale
	part.TextureID = textureId
	part.CastShadow = false
	quiet(part)
	part.CFrame = root.CFrame
	weldTo(root, part)
	return part
end

local function meshEgg(eggType: string, size: number, tint: Color3?): (Model?, BasePart?)
	local shape = shapeOf(eggType)
	local base = template((Assets.meshes :: any)[shape])
	if not base then
		return nil, nil
	end
	local model = Instance.new("Model")
	local shell = base:Clone()
	shell.Name = "Root"
	shell.Size = Vector3.new(size, size * HEIGHT, size)
	shell.CFrame = CFrame.new()
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	if tint then
		shell.TextureID = ""
		shell.Color = tint
	else
		shell.TextureID = (Assets.textures :: any)[eggType]
	end
	if shape == "gem" then
		shell.Reflectance = 0.12
	end
	shell.Parent = model

	if tint and set(Assets.painted) then
		local paint = overlay(shell, shape, "Paint", Assets.painted, PAINT_SCALE)
		if paint then
			paint.Parent = model
		end
	end
	local ornament = (Assets.ornaments :: any)[eggType]
	if not tint and ornament and set(ornament.mesh) and set(ornament.texture) then
		local orn = template(ornament.mesh)
		if orn then
			local part = orn:Clone()
			part.Name = "Ornament"
			part.Size *= size
			part.TextureID = ornament.texture
			quiet(part)
			local o = ornament.offset
			part.CFrame = shell.CFrame * CFrame.new(o[1] * size, o[2] * size, o[3] * size)
			weldTo(shell, part)
			part.Parent = model
		end
	end
	model:SetAttribute("Mesh", true)
	return model, shell
end

-- ─── Public ──────────────────────────────────────────────────────────────────────────

function EggModel.Build(eggType: string, opts: { anchored: boolean?, size: number?, tint: Color3?, vfx: boolean? }?)
	local options = opts or {}
	local def = Config.Eggs.ById[eggType]
	local size = options.size or 2
	local tint = options.tint

	local model, root
	if EggModel.Has(eggType) or (tint and set((Assets.meshes :: any)[shapeOf(eggType)]) and isAvailable()) then
		model, root = meshEgg(eggType, size, tint)
	end
	if not model or not root then
		model, root = placeholder(def, size, tint)
	end
	model.Name = (def and def.name) or "Egg"
	root.Anchored = options.anchored ~= false
	model.PrimaryPart = root
	model:SetAttribute("EggType", eggType)
	model:SetAttribute("CrackStage", 0)
	model:SetAttribute("Ready", false)
	local effects = options.vfx ~= false and not tint
	model:SetAttribute("Vfx", effects)
	if effects then
		local ok, err = pcall(Vfx.AttachEgg, model, eggType, false)
		if not ok then
			warn("[EggModel] egg effects failed: " .. tostring(err))
		end
	end
	return model
end

-- The placeholder's crack: a zigzag of thin dark bars round the upper third, longer each stage.
local function placeholderCrack(model: Model, root: BasePart, stage: number): Instance
	local folder = Instance.new("Folder")
	folder.Name = "Crack"
	local size = root.Size.X
	local spans = { math.rad(50), math.rad(130), math.rad(360) }
	local teeth = ({ 4, 8, 16 })[stage]
	local span = spans[stage]
	local y0 = root.Size.Y * 0.16
	local function point(i: number): Vector3
		local a = -span / 2 + span * i / teeth
		local y = y0 + (if i % 2 == 0 then -1 else 1) * size * 0.05
		local ry = math.sqrt(math.max(0, 1 - (y / (root.Size.Y / 2)) ^ 2)) * size / 2 * 1.02
		return Vector3.new(math.sin(a) * ry, y, -math.cos(a) * ry)
	end
	for i = 0, teeth - 1 do
		local a, b = point(i), point(i + 1)
		local bar = Instance.new("Part")
		bar.Name = "Crack" .. (i + 1)
		bar.Size = Vector3.new(size * 0.035, size * 0.035, (b - a).Magnitude + size * 0.03)
		bar.Color = CRACK_COLOR
		bar.Material = Enum.Material.SmoothPlastic
		bar.CastShadow = false
		quiet(bar)
		bar.Anchored = false
		bar.CFrame = root.CFrame * CFrame.lookAt((a + b) / 2, b)
		weldTo(root, bar)
		bar.Parent = folder
	end
	folder.Parent = model
	return folder
end

function EggModel.SetCrack(model: Model, stage: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local n = math.clamp(math.floor(tonumber(stage) or 0), 0, 3)
	local old = model:FindFirstChild("Crack")
	if old then
		old:Destroy()
	end
	model:SetAttribute("CrackStage", n)
	if n == 0 then
		return
	end
	local eggType = model:GetAttribute("EggType")
	local id = Assets.cracks[n]
	if model:GetAttribute("Mesh") == true and set(id) then
		local part = overlay(root, shapeOf(tostring(eggType)), "Crack", id, CRACK_SCALE)
		if part then
			part.Parent = model
			return
		end
	end
	placeholderCrack(model, root, n)
end

function EggModel.SetReady(model: Model, ready: boolean)
	local root = model.PrimaryPart
	if not root then
		return
	end
	model:SetAttribute("Ready", ready == true)
	local light = root:FindFirstChild("ReadyGlow")
	if ready and not light then
		light = Instance.new("PointLight")
		light.Name = "ReadyGlow"
		light.Color = READY_COLOR
		light.Brightness = 1.6
		light.Range = root.Size.Y * 3.2
		light.Shadows = false
		light.Parent = root
	elseif not ready and light then
		light:Destroy()
	end
	local eggType = model:GetAttribute("EggType")
	if type(eggType) == "string" and model:GetAttribute("Vfx") ~= false then
		pcall(Vfx.AttachEgg, model, eggType, ready == true)
	end
end

return EggModel
