--[[
	BattleArena (glow-up V): the 3D battle stage in the world. Parts only (a floor disc, a ring of
	backdrop panels, a few themed props, two lights), the fighters built with MonsterModel.Build and
	driven by MonsterAnimator, and pooled effects: element bolts (Config/VfxSprites sprites on
	billboards), floating numbers, hit sparks (Visuals/Vfx bursts) and HP bars over heads.
	Parts/BattleStage drives it from a BattleReplay; the numbers are Config/BattleStage.

		local arena = BattleArena.new({ theme, units, placement, low, caps })  -- Logic/BattleStage
		arena:Build()                         the stage and every fighter (may yield: mesh loads)
		arena.center                          Vector3: the middle of the floor's top
		arena:Point(x, y, z) -> Vector3       stage space to world (allies at x < 0)
		arena:Get(key) -> view?               { key, unit, model, animator, home, pos, height, size }
		arena:Chest(key) -> Vector3
		arena:Attack(actor, target?)          attack clip + a lunge toward the target
		arena:Bolt(actor, target, seconds) -> drawn   an element bolt (false when capped)
		arena:Impact(target, hurt, spark)     hurt clip (flash) + a hit spark in the attacker's element
		arena:Spark(key, element?, burst?) -> drawn
		arena:Number(key, text, color, big, priority) -> drawn
		arena:SetBar(key, frac, shield, stunned) · arena:Faint(key) · arena:Cheer(key)
		arena:After(seconds, fn)              a timer on the arena's clock (speed-scaled, dropped by
		                                      ClearEffects / Destroy)
		arena:SetSpeed(k) · arena:ClearEffects() · arena:Counts() -> { bolts, numbers, sparks,
		                                      models, timers, limits = { bolts, numbers, sparks } }
		arena:Destroy()                       everything goes; the models go back to the pool
		BattleArena.Live() -> number          arenas not destroyed yet
		BattleArena.Pooled() -> number        parked monster models (reused by the next fight with
		                                      the same look for LINGER seconds, then destroyed)
		BattleArena.Flush()                   destroy the parked models now

	Everything lives in Workspace.BattleStage, far outside the map (Config.BattleStage.origin), and
	is gone after Destroy. Low quality: no lights, no auras on the fighters, no hit sparks, fewer
	bolts and numbers (Config.BattleStage.caps.low).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Sprites = require(Shared.Config.VfxSprites)
local Tuning = require(Shared.Config.BattleStage)
local Plan = require(Shared.Logic.BattleStage)

local MonsterModel = require(script.Parent.MonsterModel)
local MonsterAnimator = require(script.Parent.MonsterAnimator)
local Vfx = require(script.Parent.Vfx)

local UI = script.Parent.Parent.UI
local Theme = require(UI.Theme)

local BattleArena = {}
BattleArena.__index = BattleArena

local UP = Vector3.new(0, 1, 0)
local LINGER = 20 -- seconds a parked model waits for the next fight
local MAX_POOLED = 12
local NUMBER_RISE = 2.4
local NUMBER_SECONDS = 0.95
local LUNGE_SECONDS = 0.42

local liveArenas = 0

-- Model pool ------------------------------------------------------------------------------------

local parked: { [string]: { Model } } = {}
local parkedCount = 0
local flushToken = 0

local function serialize(value, out: { string })
	if type(value) == "table" then
		local keys = {}
		for k in value do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		table.insert(out, "{")
		for _, k in keys do
			table.insert(out, k .. "=")
			local v = value[k]
			if v == nil then
				v = value[tonumber(k) :: any]
			end
			serialize(v, out)
			table.insert(out, ",")
		end
		table.insert(out, "}")
	else
		table.insert(out, tostring(value))
	end
end

local function modelKey(appearance, scale: number, vfx: boolean): string
	local out = {}
	serialize(appearance, out)
	return table.concat(out) .. string.format("@%.2f", scale) .. (if vfx then "+fx" else "")
end

function BattleArena.Flush()
	for _, list in parked do
		for _, model in list do
			model:Destroy()
		end
	end
	table.clear(parked)
	parkedCount = 0
end

function BattleArena.Pooled(): number
	return parkedCount
end

function BattleArena.Live(): number
	return liveArenas
end

local function takeModel(key: string): Model?
	local list = parked[key]
	if list and #list > 0 then
		parkedCount -= 1
		return table.remove(list)
	end
	return nil
end

local function park(key: string, model: Model)
	-- Leftovers of the fight (the hurt flash) go; the next animator re-poses the rest.
	for _, child in model:GetChildren() do
		if child:IsA("Highlight") then
			child:Destroy()
		end
	end
	if parkedCount >= MAX_POOLED then
		model:Destroy()
		return
	end
	model.Parent = nil
	parked[key] = parked[key] or {}
	table.insert(parked[key], model)
	parkedCount += 1
	flushToken += 1
	local token = flushToken
	task.delay(LINGER, function()
		if token == flushToken and liveArenas == 0 then
			BattleArena.Flush()
		end
	end)
end

-- Parts -----------------------------------------------------------------------------------------

local function material(name: string?): Enum.Material
	local ok, value = pcall(function()
		return (Enum.Material :: any)[name or "SmoothPlastic"]
	end)
	return if ok and value then value else Enum.Material.SmoothPlastic
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function flatDisc(parent, name: string, center: Vector3, radius: number, thickness: number, color: Color3, mat)
	-- A Cylinder's axis is X: lay it on its side so the round face is the floor.
	return part(
		parent,
		name,
		Vector3.new(thickness, radius * 2, radius * 2),
		CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		mat,
		Enum.PartType.Cylinder
	)
end

local function shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

-- One prop: a small model of parts, its main part named "Main" (the mesh swap point).
local function buildProp(parent: Instance, def, base: CFrame)
	local model = Instance.new("Model")
	model.Name = "Prop_" .. def.kind
	local s = def.size or 4
	local color = Color3.fromHex(def.color or "#999999")
	local mat = material(def.material)
	local kind = def.kind
	local main
	if kind == "tree" then
		part(
			model,
			"Trunk",
			Vector3.new(s * 0.18, s * 0.6, s * 0.18),
			base * CFrame.new(0, s * 0.3, 0),
			Color3.fromHex("#7A5534"),
			Enum.Material.Wood
		)
		main = part(
			model,
			"Main",
			Vector3.new(s * 0.7, s * 0.6, s * 0.7),
			base * CFrame.new(0, s * 0.75, 0),
			color,
			material(def.material or "Grass"),
			Enum.PartType.Ball
		)
	elseif kind == "rock" then
		main = part(
			model,
			"Main",
			Vector3.new(s * 1.3, s, s * 1.1),
			base * CFrame.new(0, s * 0.35, 0) * CFrame.Angles(0.2, 0.7, 0.1),
			color,
			material(def.material or "Slate")
		)
	elseif kind == "crystal" then
		main = part(
			model,
			"Main",
			Vector3.new(s * 0.35, s, s * 0.35),
			base * CFrame.new(0, s * 0.5, 0) * CFrame.Angles(0.15, 0.6, 0.12),
			color,
			material(def.material or "Glass")
		)
		part(
			model,
			"Shard",
			Vector3.new(s * 0.22, s * 0.6, s * 0.22),
			base * CFrame.new(s * 0.3, s * 0.3, 0) * CFrame.Angles(0, 0.3, -0.35),
			color,
			material(def.material or "Glass")
		)
		main.Transparency = 0.15
	elseif kind == "pillar" then
		main = part(
			model,
			"Main",
			Vector3.new(s, s * 0.22, s * 0.22),
			base * CFrame.new(0, s * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			material(def.material or "Marble"),
			Enum.PartType.Cylinder
		)
		part(
			model,
			"Cap",
			Vector3.new(s * 0.34, s * 0.1, s * 0.34),
			base * CFrame.new(0, s + s * 0.05, 0),
			shade(color, -0.08),
			material(def.material or "Marble")
		)
	elseif kind == "coral" then
		main = part(model, "Main", Vector3.new(s * 0.2, s, s * 0.2), base * CFrame.new(0, s * 0.45, 0), color, mat)
		part(
			model,
			"Branch1",
			Vector3.new(s * 0.16, s * 0.6, s * 0.16),
			base * CFrame.new(s * 0.2, s * 0.55, 0) * CFrame.Angles(0, 0, -0.6),
			color,
			mat
		)
		part(
			model,
			"Branch2",
			Vector3.new(s * 0.16, s * 0.5, s * 0.16),
			base * CFrame.new(-s * 0.18, s * 0.5, 0.1) * CFrame.Angles(0.2, 0, 0.7),
			color,
			mat
		)
	elseif kind == "cactus" then
		main = part(
			model,
			"Main",
			Vector3.new(s, s * 0.28, s * 0.28),
			base * CFrame.new(0, s * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			mat,
			Enum.PartType.Cylinder
		)
		part(
			model,
			"Arm1",
			Vector3.new(s * 0.4, s * 0.18, s * 0.18),
			base * CFrame.new(s * 0.22, s * 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			mat,
			Enum.PartType.Cylinder
		)
		part(
			model,
			"Arm2",
			Vector3.new(s * 0.34, s * 0.18, s * 0.18),
			base * CFrame.new(-s * 0.22, s * 0.48, 0) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			mat,
			Enum.PartType.Cylinder
		)
	elseif kind == "spike" then
		main = part(
			model,
			"Main",
			Vector3.new(s * 0.3, s, s * 0.3),
			base * CFrame.new(0, s * 0.45, 0) * CFrame.Angles(0.12, 0.8, 0.1),
			color,
			mat
		)
		part(
			model,
			"Side",
			Vector3.new(s * 0.2, s * 0.6, s * 0.2),
			base * CFrame.new(s * 0.3, s * 0.28, 0.2) * CFrame.Angles(0, 0.3, -0.3),
			shade(color, 0.1),
			mat
		)
	elseif kind == "mushroom" then
		part(
			model,
			"Stem",
			Vector3.new(s * 0.5, s * 0.22, s * 0.22),
			base * CFrame.new(0, s * 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromHex("#F2E8D5"),
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		main =
			part(model, "Main", Vector3.new(s * 0.8, s * 0.35, s * 0.8), base * CFrame.new(0, s * 0.55, 0), color, mat, Enum.PartType.Ball)
	elseif kind == "torch" then
		part(
			model,
			"Pole",
			Vector3.new(s, s * 0.08, s * 0.08),
			base * CFrame.new(0, s * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromHex("#5A4331"),
			Enum.Material.Wood,
			Enum.PartType.Cylinder
		)
		main = part(
			model,
			"Main",
			Vector3.new(s * 0.2, s * 0.2, s * 0.2),
			base * CFrame.new(0, s + s * 0.08, 0),
			color,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
	elseif kind == "banner" then
		part(
			model,
			"Pole",
			Vector3.new(s, s * 0.06, s * 0.06),
			base * CFrame.new(0, s * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromHex("#6B5B4B"),
			Enum.Material.Wood,
			Enum.PartType.Cylinder
		)
		main = part(
			model,
			"Main",
			Vector3.new(s * 0.05, s * 0.45, s * 0.3),
			base * CFrame.new(0, s * 0.72, s * 0.15),
			color,
			Enum.Material.Fabric
		)
	else
		main = part(model, "Main", Vector3.new(s, s, s), base * CFrame.new(0, s * 0.5, 0), color, mat)
	end
	if type(def.mesh) == "string" and def.mesh ~= "" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = def.mesh
		mesh.Parent = main
	end
	model.PrimaryPart = main
	model.Parent = parent
	return model
end

-- The arena ---------------------------------------------------------------------------------------

function BattleArena.new(args)
	local self = setmetatable({}, BattleArena)
	self.theme = args.theme or Tuning.themes.default
	self.units = args.units or {}
	self.placement = args.placement or {}
	self.low = args.low == true
	local caps = args.caps or Plan.Caps(Tuning, self.low)
	self.limits = {
		bolts = Plan.Limiter(caps.bolts.live, caps.bolts.perSecond),
		numbers = Plan.Limiter(caps.numbers.live, caps.numbers.perSecond),
		sparks = Plan.Limiter(caps.sparks.live, caps.sparks.perSecond),
	}
	local o = Tuning.origin
	self.origin = CFrame.new(o[1], o[2], o[3])
	self.center = self.origin.Position
	self.views = {}
	self.order = {}
	self.bolts = {}
	self.numbers = {}
	self.lunges = {}
	self.timers = {}
	self.boltPool = {}
	self.numberPool = {}
	self.speed = 1
	self.alive = true
	liveArenas += 1
	return self
end

function BattleArena:Point(x: number, y: number, z: number): Vector3
	return self.center + Vector3.new(x, y, z)
end

function BattleArena:_buildStage()
	local folder = Instance.new("Folder")
	folder.Name = "BattleStage"
	folder.Parent = workspace
	self.folder = folder
	local theme = self.theme
	local floorCfg, wallCfg = Tuning.floor, Tuning.wall
	local floorColor = Color3.fromHex(theme.floor)
	local rimColor = Color3.fromHex(theme.rim)
	local wallColor = Color3.fromHex(theme.wall)
	local top = self.center
	flatDisc(
		folder,
		"Floor",
		top - UP * (floorCfg.thickness / 2),
		floorCfg.radius,
		floorCfg.thickness,
		floorColor,
		material(theme.floorMaterial)
	)
	flatDisc(
		folder,
		"Rim",
		top - UP * (floorCfg.thickness / 2 + 0.4),
		floorCfg.radius + floorCfg.rim,
		floorCfg.thickness,
		rimColor,
		Enum.Material.SmoothPlastic
	)
	flatDisc(
		folder,
		"Ground",
		top - UP * (floorCfg.thickness + 0.6),
		wallCfg.radius + 2,
		1,
		shade(rimColor, -0.25),
		Enum.Material.SmoothPlastic
	)
	for i = 1, wallCfg.panels do
		local angle = (i - 1) / wallCfg.panels * math.pi * 2
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local at = top + dir * wallCfg.radius + UP * (wallCfg.height / 2 - floorCfg.thickness)
		part(
			folder,
			"Wall",
			Vector3.new(wallCfg.width, wallCfg.height, 1),
			CFrame.new(at) * CFrame.Angles(0, angle, 0),
			if i % 2 == 0 then wallColor else shade(wallColor, 0.08),
			Enum.Material.SmoothPlastic
		)
	end
	for _, def in theme.props or {} do
		local angle = math.rad(def.at[1] + 90) -- 0 degrees = behind the enemies (+x)
		local base = CFrame.new(top + Vector3.new(math.sin(angle), 0, math.cos(angle)) * def.at[2]) * CFrame.Angles(0, angle, 0)
		buildProp(folder, def, base)
	end
	if not self.low then
		-- The stage brings its own light, so a night fight still reads.
		local lights = Tuning.lights
		for _, x in { -8, 8 } do
			local holder =
				part(folder, "Light", Vector3.new(0.2, 0.2, 0.2), CFrame.new(top + Vector3.new(x, lights.height, 6)), Color3.new(1, 1, 1))
			holder.Transparency = 1
			local light = Instance.new("PointLight")
			light.Brightness = lights.brightness
			light.Range = lights.range
			light.Shadows = false
			light.Parent = holder
		end
	end
end

local function hpColor(frac: number): Color3
	if frac > 0.5 then
		return Theme.Colors.Green
	elseif frac > 0.25 then
		return Theme.Colors.Orange
	end
	return Theme.Colors.Red
end

function BattleArena:_buildBar(view)
	local model = view.model
	local root = model.PrimaryPart
	local head = root and root:FindFirstChild("Head")
	local gui = Instance.new("BillboardGui")
	gui.Name = "Hp_" .. view.key
	gui.Adornee = if head then head else root
	local width = if view.boss then 6 else 3.6
	gui.Size = UDim2.new(width, 0, if view.boss then 0.8 else 0.55, 0)
	gui.StudsOffset = Vector3.new(0, if head then 0.9 else view.height + 0.9, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = self.folder
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BackgroundColor3 = Theme.Colors.Ink
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Colors.Green
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	corner:Clone().Parent = fill
	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.BackgroundColor3 = Theme.Colors.Blue
	shield.BorderSizePixel = 0
	shield.AnchorPoint = Vector2.new(0, 1)
	shield.Position = UDim2.fromScale(0, 1)
	shield.Size = UDim2.fromScale(1, 0.3)
	shield.Visible = false
	shield.Parent = back
	local stun = Instance.new("TextLabel")
	stun.Name = "Stun"
	stun.BackgroundTransparency = 1
	stun.Font = Theme.Fonts.Display
	stun.Text = "STUN"
	stun.TextScaled = true
	stun.TextColor3 = Theme.Colors.Gold
	stun.AnchorPoint = Vector2.new(0.5, 1)
	stun.Position = UDim2.fromScale(0.5, -0.1)
	stun.Size = UDim2.fromScale(0.6, 1.3)
	stun.Visible = false
	stun.Parent = gui
	view.bar = { gui = gui, fill = fill, shield = shield, stun = stun }
end

function BattleArena:_buildUnit(unit, spot)
	local appearance = unit.appearance
	if type(appearance) ~= "table" or not Config.Species.ById[appearance.line] then
		return nil
	end
	local natural = MonsterModel.ScaleFor(appearance)
	local size = Plan.Size(natural, spot.boss, Tuning)
	local vfx = not self.low
	local key = modelKey(appearance, size, vfx)
	local model = takeModel(key)
	if not model then
		local ok, built = pcall(MonsterModel.Build, appearance, { anchored = true, scale = size, vfx = vfx })
		if not ok or not built then
			warn("[BattleArena] could not build " .. tostring(appearance.form) .. ": " .. tostring(built))
			return nil
		end
		model = built
	end
	if not self.alive then
		park(key, model)
		return nil
	end
	local pos = self:Point(spot.x, 0, spot.z)
	-- Face the other side: allies look toward +x, enemies toward -x.
	local facing = if spot.side == "enemy" then -1 else 1
	local home = CFrame.lookAt(pos, pos + Vector3.new(facing, 0, 0))
	model.Parent = self.folder
	model:PivotTo(home)
	local animator = MonsterAnimator.new(model)
	animator:SetBase(home)
	animator:Play("idle")
	local height = tonumber(model:GetAttribute("Height")) or (3 * natural * size)
	local elements = appearance.elements
	local view = {
		key = unit.key,
		unit = unit,
		model = model,
		poolKey = key,
		animator = animator,
		home = home,
		pos = pos,
		height = height,
		size = size,
		boss = spot.boss,
		side = spot.side,
		element = if type(elements) == "table" then elements[1] else nil,
	}
	self:_buildBar(view)
	return view
end

function BattleArena:Build()
	self:_buildStage()
	for _, unit in self.units do
		if not self.alive then
			return
		end
		local spot = self.placement[unit.key]
		if spot then
			local view = self:_buildUnit(unit, spot)
			if view then
				self.views[unit.key] = view
				table.insert(self.order, view)
			end
		end
	end
	if self.alive then
		self.conn = RunService.Heartbeat:Connect(function()
			self:_update()
		end)
		self.last = os.clock()
	end
end

function BattleArena:Get(key: string?)
	return if key then self.views[key] else nil
end

function BattleArena:Chest(key: string?): Vector3
	local view = self:Get(key)
	if not view then
		return self.center + UP * 2
	end
	return view.pos + UP * (view.height * 0.55)
end

function BattleArena:SetSpeed(k: number)
	self.speed = math.max(0.1, k)
end

function BattleArena:After(seconds: number, fn: () -> ())
	table.insert(self.timers, { left = seconds, fn = fn })
end

function BattleArena:Attack(actor: string, target: string?)
	local view = self:Get(actor)
	if not view then
		return
	end
	view.animator:Play("attack")
	local goal = self:Get(target)
	if goal then
		local flat = Vector3.new(goal.pos.X - view.pos.X, 0, goal.pos.Z - view.pos.Z)
		if flat.Magnitude > 1e-3 then
			self.lunges[view.key] = { view = view, t = 0, dir = flat.Unit, dist = math.min(2.2, flat.Magnitude * 0.25) }
		end
	end
end

-- Pooled billboard carriers: an invisible anchored part with a BillboardGui on it.
local function carrier(folder: Instance, name: string, size: UDim2)
	local p = part(folder, name, Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(1, 1, 1))
	p.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = size
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.Parent = p
	return p, gui
end

function BattleArena:Bolt(actor: string, target: string, seconds: number): boolean
	local from, to = self:Get(actor), self:Get(target)
	if not (from and to and self.folder) then
		return false
	end
	if not self.limits.bolts:Take(os.clock()) then
		return false
	end
	local item = table.remove(self.boltPool)
	if not item then
		local p, gui = carrier(self.folder, "Bolt", UDim2.new(2.2, 0, 2.2, 0))
		local image = Instance.new("ImageLabel")
		image.Name = "Sprite"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = image
		item = { part = p, gui = gui, image = image }
	end
	local element = from.element
	local def = element and Config.Elements.ById[element]
	local color = if def then Color3.fromHex(def.color) else Theme.Colors.White
	local spriteName = element and Tuning.sprites[element]
	local sprite = spriteName and Sprites[spriteName]
	if sprite and sprite.color then
		item.image.Image = sprite.color
		item.image.ImageColor3 = Color3.new(1, 1, 1)
		item.image.BackgroundTransparency = 1
	else
		-- Not uploaded yet: a round blob in the element's colour.
		item.image.Image = ""
		item.image.BackgroundColor3 = color
		item.image.BackgroundTransparency = 0.1
	end
	local a, b = self:Chest(actor), self:Chest(target)
	item.from, item.to = a, b
	item.arc = 1 + (b - a).Magnitude * 0.08
	item.t, item.dur = 0, math.max(0.05, seconds)
	item.part.CFrame = CFrame.new(a)
	item.gui.Enabled = true
	table.insert(self.bolts, item)
	return true
end

function BattleArena:Spark(key: string, element: string?, burst: string?): boolean
	local view = self:Get(key)
	if not view or not self.limits.sparks:Take(os.clock()) then
		return false
	end
	local ok = pcall(Vfx.Burst, burst or "battleHit", self:Chest(key), { elements = if element then { element } else nil, scale = 0.75 })
	-- A spark lives about half a second; the live cap frees its slot then.
	self:After(0.5, function()
		self.limits.sparks:Done()
	end)
	return ok
end

function BattleArena:Impact(target: string, hurt: boolean, spark: string?)
	local view = self:Get(target)
	if not view then
		return
	end
	if hurt and view.animator:GetState() ~= "faint" then
		view.animator:Play("hurt")
	end
	if spark then
		self:Spark(target, spark)
	end
end

function BattleArena:Number(key: string, text: string, color: Color3, big: boolean?, priority: boolean?): boolean
	local view = self:Get(key)
	if not view or not self.folder then
		return false
	end
	local limits = self.limits.numbers
	if not limits:Take(os.clock(), priority) then
		if not priority or #self.numbers == 0 then
			return false
		end
		-- An important one takes the oldest number's place.
		self:_endNumber(1)
		if not limits:Take(os.clock(), true) then
			return false
		end
	end
	local item = table.remove(self.numberPool)
	if not item then
		local p, gui = carrier(self.folder, "Number", UDim2.new(6, 0, 1.5, 0))
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.BackgroundTransparency = 1
		label.Font = Theme.Fonts.Display
		label.TextScaled = true
		label.Size = UDim2.fromScale(1, 1)
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Colors.Ink
		stroke.Thickness = 2
		stroke.Parent = label
		item = { part = p, gui = gui, label = label, stroke = stroke }
	end
	local scale = (if big then 1.45 else 1) * (if view.boss then 1.3 else 1)
	item.gui.Size = UDim2.new(6 * scale, 0, 1.5 * scale, 0)
	item.label.Text = text
	item.label.TextColor3 = color
	item.label.TextTransparency = 0
	item.stroke.Transparency = 0
	item.base = view.pos + UP * (view.height + 1.6) + Vector3.new(0, 0, (math.random() - 0.5) * 1.4)
	item.t = 0
	item.part.CFrame = CFrame.new(item.base)
	item.gui.Enabled = true
	table.insert(self.numbers, item)
	return true
end

function BattleArena:_endNumber(index: number)
	local item = table.remove(self.numbers, index)
	if item then
		item.gui.Enabled = false
		table.insert(self.numberPool, item)
		self.limits.numbers:Done()
	end
end

function BattleArena:_endBolt(index: number)
	local item = table.remove(self.bolts, index)
	if item then
		item.gui.Enabled = false
		table.insert(self.boltPool, item)
		self.limits.bolts:Done()
	end
end

function BattleArena:SetBar(key: string, frac: number, shield: boolean?, stunned: boolean?)
	local view = self:Get(key)
	local bar = view and view.bar
	if not bar then
		return
	end
	local f = math.clamp(frac, 0, 1)
	bar.fill.Size = UDim2.fromScale(f, 1)
	bar.fill.BackgroundColor3 = hpColor(f)
	bar.shield.Visible = shield == true
	bar.stun.Visible = stunned == true
	bar.gui.Enabled = f > 0
end

function BattleArena:Faint(key: string)
	local view = self:Get(key)
	if view then
		self.lunges[key] = nil
		view.animator:SetBase(view.home)
		view.animator:Play("faint")
	end
end

function BattleArena:Cheer(key: string)
	local view = self:Get(key)
	if view then
		view.animator:Play("happy")
	end
end

function BattleArena:_update()
	if not self.alive then
		return
	end
	local now = os.clock()
	local dt = (now - (self.last or now)) * self.speed
	self.last = now
	for i = #self.timers, 1, -1 do
		local timer = self.timers[i]
		timer.left -= dt
		if timer.left <= 0 then
			table.remove(self.timers, i)
			local ok, err = pcall(timer.fn)
			if not ok then
				warn("[BattleArena] timer failed: " .. tostring(err))
			end
		end
	end
	for i = #self.bolts, 1, -1 do
		local bolt = self.bolts[i]
		bolt.t += dt
		local a = math.min(1, bolt.t / bolt.dur)
		bolt.part.CFrame = CFrame.new(bolt.from:Lerp(bolt.to, a) + UP * (bolt.arc * 4 * a * (1 - a)))
		if a >= 1 then
			self:_endBolt(i)
		end
	end
	for i = #self.numbers, 1, -1 do
		local item = self.numbers[i]
		item.t += dt
		local a = math.min(1, item.t / NUMBER_SECONDS)
		item.part.CFrame = CFrame.new(item.base + UP * (NUMBER_RISE * (1 - (1 - a) * (1 - a))))
		local fade = math.clamp((a - 0.6) / 0.4, 0, 1)
		item.label.TextTransparency = fade
		item.stroke.Transparency = fade
		if a >= 1 then
			self:_endNumber(i)
		end
	end
	for key, lunge in self.lunges do
		lunge.t += dt
		local a = math.min(1, lunge.t / LUNGE_SECONDS)
		local view = lunge.view
		view.animator:SetBase(view.home + lunge.dir * (lunge.dist * math.sin(math.pi * a)))
		if a >= 1 then
			view.animator:SetBase(view.home)
			self.lunges[key] = nil
		end
	end
end

function BattleArena:ClearEffects()
	table.clear(self.timers)
	for i = #self.bolts, 1, -1 do
		self:_endBolt(i)
	end
	for i = #self.numbers, 1, -1 do
		self:_endNumber(i)
	end
	for key, lunge in self.lunges do
		lunge.view.animator:SetBase(lunge.view.home)
		self.lunges[key] = nil
	end
	self.limits.sparks.alive = 0
end

function BattleArena:Counts()
	local models = 0
	for _ in self.views do
		models += 1
	end
	return {
		bolts = #self.bolts,
		numbers = #self.numbers,
		sparks = self.limits.sparks.alive,
		models = models,
		timers = #self.timers,
		limits = { bolts = self.limits.bolts, numbers = self.limits.numbers, sparks = self.limits.sparks },
	}
end

function BattleArena:Destroy()
	if not self.alive then
		return
	end
	self.alive = false
	liveArenas -= 1
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	table.clear(self.timers)
	table.clear(self.bolts)
	table.clear(self.numbers)
	table.clear(self.lunges)
	for _, view in self.order do
		view.animator:Destroy()
		if view.bar then
			view.bar.gui:Destroy()
		end
		park(view.poolKey, view.model)
	end
	table.clear(self.views)
	table.clear(self.order)
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
end

return BattleArena
