--[[
	Parts/PostcardView (glow-up X): draws a postcard from its data (Logic/Postcards card).

		local view = PostcardView.new(card, { Size = UDim2.fromOffset(560, 300), Parent = frame })
		view:Flip()  view:IsFront() -> boolean  view:Destroy()
		PostcardView.tile(card, { Size, Parent, LayoutOrder }) -> Frame   -- static album card

	The front is one ViewportFrame: a sky gradient behind it, the region's backdrop parts from
	Config.Postcards.Scenes, and the squad's real models (MonsterModel.Build) in a WorldModel so a
	skinned monster shows its pose. Each monster holds a clip from Config.Postcards.poses, looping
	while the card is shown (MeshMonster.Pose); placeholders simply stand. The stamp names the
	region and the line is "handwritten". The back lists the loot, the date and who sent it.
	Everything is built on demand and destroyed with the view: one live viewport at a time. The
	album's tiles are static (portrait + gradient), never viewports.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Logic.Format)
local Logic = require(Shared.Logic.Postcards)

local UI = script.Parent.Parent.Parent
local Theme = require(UI.Theme)
local Create = require(UI.Create)
local Anim = require(UI.Anim)
local MonsterIcon = require(UI.Components.MonsterIcon)
local Util = require(script.Parent.Util)

local Visuals = UI.Parent.Visuals
local MonsterModel = require(Visuals.MonsterModel)
local MeshMonster = require(Visuals.MeshMonster)

local New = Create.New
local C = Theme.Colors
local Cfg = Config.Postcards

local HAND = Enum.Font.IndieFlower
local SPACING = 3.8 -- studs between squad members
local PAPER = Color3.fromHex("#FFF4DC")

local PostcardView = {}
PostcardView.__index = PostcardView

local function hex(value: string?, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

local function shown(gui: Instance): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

function PostcardView.regionName(regionId: string): string
	local region = Config.Regions.ById[regionId]
	return if region then region.name else "Far away"
end

function PostcardView.lineText(card): string
	return string.format(Logic.LineText(card.line, Cfg), card.hero or "Your squad")
end

local function sky(scene, parent: Instance)
	local frame = New("Frame", {
		Name = "Sky",
		BackgroundColor3 = C.White,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}, { Create.Corner(Theme.Radius.Card) })
	New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(hex(scene.sky[1], C.Sky), hex(scene.sky[2], C.White)),
		Parent = frame,
	})
	return frame
end

local function stamp(card, scene, parent: Instance)
	local frame = New("Frame", {
		Name = "Stamp",
		BackgroundColor3 = PAPER,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(132, 62),
		Rotation = 5,
		ZIndex = 5,
		Parent = parent,
	}, { Create.Stroke(3, hex(scene.stamp, C.TextMuted)), Create.Padding(4, 6, 4, 6) })
	Create.Text({
		Name = "Region",
		Text = PostcardView.regionName(card.region),
		TextColor3 = hex(scene.stamp, C.TextMuted),
		Stroke = false,
		TextSize = Theme.TextSize.Small,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = frame,
	})
	return frame
end

-- The diorama: backdrop parts, the ground and the posed squad, framed by a fixed camera.
local function diorama(card, scene, parent: Instance)
	local vp = New("ViewportFrame", {
		Name = "Diorama",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.5, -1, 0.7),
		ZIndex = 2,
		Parent = parent,
	})
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local function part(shape: string, size: Vector3, cf: CFrame, color: Color3, material: string?)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Shape = if shape == "Ball" then Enum.PartType.Ball elseif shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
		p.Size = size
		p.CFrame = cf
		p.Color = color
		local found, mat = pcall(function()
			return (Enum.Material :: any)[material or "SmoothPlastic"]
		end)
		p.Material = if found and mat then mat else Enum.Material.SmoothPlastic
		p.Parent = world
		return p
	end
	part("Block", Vector3.new(80, 1, 60), CFrame.new(0, -0.5, 20), hex(scene.ground, C.Grass))
	for _, prop in scene.props do
		local rot = prop.rot or { 0, 0, 0 }
		local cf = CFrame.new(prop.pos[1], prop.pos[2], prop.pos[3]) * CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		part(prop.shape, Vector3.new(prop.size[1], prop.size[2], prop.size[3]), cf, hex(prop.color, C.White), prop.material)
	end

	local models = {}
	local count = #card.squad
	local width, height = 0, 0
	for i, slim in card.squad do
		local ap = Logic.Full(slim, Config.Species)
		local ok, model = pcall(MonsterModel.Build, ap, { anchored = true, vfx = false })
		if ok and model then
			local x = (i - (count + 1) / 2) * SPACING
			local yaw = math.rad((i - (count + 1) / 2) * -14 + 180)
			model:PivotTo(CFrame.new(x, 0, (i % 2) * -0.8) * CFrame.Angles(0, yaw, 0))
			model.Parent = world
			local _, size = model:GetBoundingBox()
			width = math.max(width, math.abs(x) * 2 + size.X)
			height = math.max(height, size.Y)
			local clip = Cfg.poses[(i - 1) % #Cfg.poses + 1]
			if not MeshMonster.HasClip(model, clip) then
				clip = "idle"
			end
			table.insert(models, { model = model, clip = clip, t = i * 0.37 })
		end
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = math.max(15, width * 0.95, height * 2.6)
	local look = Vector3.new(0, math.max(1.6, height * 0.45), 3)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, look.Y + distance * 0.12, -distance), look)
	camera.Parent = vp
	vp.CurrentCamera = camera
	return vp, models
end

function PostcardView.new(card, props: { Size: UDim2?, Parent: Instance?, Position: UDim2?, AnchorPoint: Vector2? })
	local self = setmetatable({}, PostcardView)
	local scene = Cfg.Scene(card.region)
	self.card = card
	self._front = true

	local root = New("Frame", {
		Name = "Postcard",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(560, 300),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
	})
	self.Root = root

	-- Front --------------------------------------------------------------------------------
	local front = New("Frame", {
		Name = "Front",
		BackgroundColor3 = PAPER,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Parent = root,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(4, C.White) })
	sky(scene, front)
	local _, models = diorama(card, scene, front)
	self._models = models
	stamp(card, scene, front)
	if card.from then
		local tag = New("Frame", {
			Name = "From",
			BackgroundColor3 = C.Pink,
			Position = UDim2.fromOffset(62, 10), -- clear of the ★ button the card viewer puts in the corner
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 5,
			Parent = front,
		}, { Create.Round(), Create.Padding(2, 12, 2, 12) })
		Create.Text({
			Text = string.format("From %s", card.from),
			TextSize = Theme.TextSize.Small,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			ZIndex = 6,
			Parent = tag,
		})
	end
	local band = New("Frame", {
		Name = "Line",
		BackgroundColor3 = PAPER,
		BackgroundTransparency = 0.12,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 46),
		Rotation = -1,
		ZIndex = 5,
		Parent = front,
	}, { Create.Corner(8), Create.Padding(2, 10, 2, 10) })
	Create.Text({
		Name = "Handwriting",
		Text = PostcardView.lineText(card),
		Font = HAND,
		TextColor3 = C.Text,
		Stroke = false,
		TextSize = Theme.TextSize.Body + 4,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = band,
	})

	-- Back ---------------------------------------------------------------------------------
	local back = New("Frame", {
		Name = "Back",
		BackgroundColor3 = PAPER,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(4, C.White), Create.Padding(12, 16, 12, 16) })
	New("Frame", {
		Name = "Divider",
		BackgroundColor3 = C.Line,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, -1, 0, 6),
		Size = UDim2.new(0, 2, 1, -12),
		Parent = back,
	})
	local left = New("Frame", {
		Name = "Letter",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.5, -14, 1, 0),
		Parent = back,
	}, { Create.List("y", 6, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
	Util.text({
		Text = if card.from then string.format("From %s", card.from) else "Dear rancher,",
		Font = HAND,
		TextSize = Theme.TextSize.Body + 4,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = left,
	})
	Util.text({
		Text = PostcardView.lineText(card),
		Font = HAND,
		TextSize = Theme.TextSize.Body + 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 0, 96),
		LayoutOrder = 2,
		Parent = left,
	})
	Util.text({
		Text = string.format("%s · %s", PostcardView.regionName(card.region), Format.date(card.at or 0)),
		TextSize = Theme.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 3,
		Parent = left,
	})
	local right = New("Frame", {
		Name = "Loot",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 14, 0, 0),
		Size = UDim2.new(0.5, -14, 1, 0),
		Parent = back,
	}, { Create.List("y", 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top) })
	Util.text({
		Text = "We brought home",
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 0,
		Parent = right,
	})
	if #card.loot == 0 then
		Util.text({
			Text = "Just good memories",
			TextSize = Theme.TextSize.Small,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = right,
		})
	end
	for i, item in card.loot do
		Util.rewardRow({ item }, right, { LayoutOrder = i, IconSize = 26, TextSize = Theme.TextSize.Small })
	end
	self._back = back
	self._frontFrame = front

	-- The squad holds its pose while the card is shown.
	self._conn = RunService.RenderStepped:Connect(function(dt)
		if not self._front or not shown(front) then
			return
		end
		for _, m in self._models do
			m.t += dt
			MeshMonster.Pose(m.model, m.clip, m.t, true)
		end
	end)
	root.Destroying:Connect(function()
		self:_disconnect()
	end)
	if props.Parent then
		root.Parent = props.Parent
	end
	return self
end

function PostcardView:_disconnect()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
end

function PostcardView:IsFront(): boolean
	return self._front
end

function PostcardView:Flip()
	self._front = not self._front
	self._frontFrame.Visible = self._front
	self._back.Visible = not self._front
	Anim.popIn(if self._front then self._frontFrame else self._back, 0.2)
end

function PostcardView:Destroy()
	self:_disconnect()
	self.Root:Destroy()
end

-- A static album card: the sky gradient, the hero's portrait, the stamp and a short line.
function PostcardView.tile(card, props: { Size: UDim2?, Parent: Instance?, LayoutOrder: number? })
	local scene = Cfg.Scene(card.region)
	local tile = New("Frame", {
		Name = "Tile_" .. tostring(card.id),
		BackgroundColor3 = PAPER,
		Size = props.Size or UDim2.fromOffset(230, 170),
		LayoutOrder = props.LayoutOrder or 0,
		ClipsDescendants = true,
		Parent = props.Parent,
	}, { Create.Corner(Theme.Radius.Card), Create.Stroke(3, C.White) })
	sky(scene, tile)
	New("Frame", {
		Name = "Ground",
		BackgroundColor3 = hex(scene.ground, C.Grass),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0.42, 0),
		Parent = tile,
	})
	for i, slim in card.squad do
		local icon = MonsterIcon.new(Logic.Full(slim, Config.Species), 74)
		icon.AnchorPoint = Vector2.new(0.5, 1)
		icon.Position = UDim2.new(0.5, (i - (#card.squad + 1) / 2) * 62, 1, -34)
		icon.ZIndex = 3
		icon.Parent = tile
	end
	local scale = New("Frame", {
		Name = "Stamp",
		BackgroundColor3 = PAPER,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(92, 30),
		Rotation = 5,
		ZIndex = 4,
		Parent = tile,
	}, { Create.Stroke(2, hex(scene.stamp, C.TextMuted)) })
	local region = Config.Regions.ById[card.region]
	Create.Text({
		Text = if region then region.short else "Far away",
		TextColor3 = hex(scene.stamp, C.TextMuted),
		Stroke = false,
		TextSize = Theme.TextSize.Small,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = scale,
	})
	local caption = if card.from then string.format("From %s", card.from) else Format.date(card.at or 0)
	local band = New("Frame", {
		Name = "Caption",
		BackgroundColor3 = PAPER,
		BackgroundTransparency = 0.1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 4,
		Parent = tile,
	})
	Create.Text({
		Text = caption,
		Font = HAND,
		TextColor3 = C.Text,
		Stroke = false,
		TextSize = Theme.TextSize.Body,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = band,
	})
	return tile
end

return PostcardView
