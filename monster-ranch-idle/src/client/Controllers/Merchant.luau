--[[
	Merchant controller (update 3.11 · Travelling Merchant): the caravan in the Market Square.
	The schedule is a pure function of time (Logic/Merchant.At), so this needs no server state:
	while a visit runs, a Part-built wagon with a striped awning, a counter and a merchant figure
	(built like the 3.10 tourist walker: no avatar loading, no assets) stands at
	Config.Merchant.World.position facing the fountain, with a "Trade · Travelling Merchant"
	prompt -> Router:Open("Merchant"). Between visits the caravan (and its prompt) is gone.

	Everything lives in Workspace.Merchant. Public (for specs):
	  Merchant.Caravan() -> Model?          the caravan now (nil while the merchant is away)
	  Merchant.Prompt() -> ProximityPrompt?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Merchant)

local Merchant = {
	Name = "Merchant",
	Dependencies = {},
}

local W = Config.Merchant.World
local POLL = 1

local ctx
local root: Folder? = nil
local caravan: Model? = nil
local prompt: ProximityPrompt? = nil
local connections = {}
local sinceCheck = math.huge

local function part(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: string,
	parent: Instance,
	shape: Enum.PartType?,
	mat: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Color = Color3.fromHex(color)
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- The caravan's frame: on the ground at the spot, its front (-z) facing the fountain.
local function baseFrame(): CFrame
	local x, z = W.position[1], W.position[3]
	local at = Vector3.new(x, Config.World.GroundY or 0, z)
	return CFrame.lookAt(at, Vector3.new(0, at.Y, 0))
end

local function buildFigure(base: CFrame, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "MerchantFigure"
	local torso = part("Torso", Vector3.new(2, 2, 1), base * CFrame.new(0, 3, 0), "#6B3FA0", model)
	part("LegL", Vector3.new(0.9, 2, 0.9), base * CFrame.new(-0.5, 1, 0), "#3A2D55", model)
	part("LegR", Vector3.new(0.9, 2, 0.9), base * CFrame.new(0.5, 1, 0), "#3A2D55", model)
	part("ArmL", Vector3.new(0.8, 1.9, 0.8), base * CFrame.new(-1.4, 3, 0), "#D9A77E", model)
	part("ArmR", Vector3.new(0.8, 1.9, 0.8), base * CFrame.new(1.4, 3, 0), "#D9A77E", model)
	part("Head", Vector3.new(1.4, 1.4, 1.4), base * CFrame.new(0, 4.7, 0), "#D9A77E", model, Enum.PartType.Ball)
	part("Beard", Vector3.new(1, 0.7, 0.4), base * CFrame.new(0, 4.25, -0.55), "#EDE7DD", model)
	part(
		"Hat",
		Vector3.new(0.3, 2.4, 2.4),
		base * CFrame.new(0, 5.35, 0) * CFrame.Angles(0, 0, math.rad(90)),
		"#F4C43A",
		model,
		Enum.PartType.Cylinder
	)
	part("HatTop", Vector3.new(1, 0.8, 1), base * CFrame.new(0, 5.8, 0), "#E5484D", model)
	model.PrimaryPart = torso
	model.Parent = parent
	return model
end

local function build(): Model
	assert(root, "Merchant root")
	local base = baseFrame()
	local model = Instance.new("Model")
	model.Name = "Caravan"
	-- The wagon behind the counter (+z = away from the fountain).
	local body = part("Wagon", Vector3.new(12, 5, 7), base * CFrame.new(0, 3.5, 4), "#8A5A2B", model, nil, Enum.Material.WoodPlanks)
	part("Roof", Vector3.new(13, 0.6, 8), base * CFrame.new(0, 7.8, 4), "#6B4424", model, nil, Enum.Material.Wood)
	for i, x in { -4.5, 4.5 } do
		for j, z in { 0.3, 7.7 } do
			-- A cylinder's axis is its X: turn it to run across the wagon.
			part(
				string.format("Wheel%d%d", i, j),
				Vector3.new(0.6, 3, 3),
				base * CFrame.new(x, 1.5, z) * CFrame.Angles(0, math.rad(90), 0),
				"#3A2A1C",
				model,
				Enum.PartType.Cylinder
			)
		end
	end
	-- The striped awning over the counter.
	local stripes = { "#E5484D", "#F4EBD9" }
	for i = 1, 6 do
		part(
			"Awning" .. i,
			Vector3.new(2, 0.3, 5),
			base * CFrame.new(-5 + (i - 1) * 2, 7.2, -1.2) * CFrame.Angles(math.rad(-18), 0, 0),
			stripes[(i - 1) % 2 + 1],
			model,
			nil,
			Enum.Material.Fabric
		)
	end
	part("PoleL", Vector3.new(0.4, 6.6, 0.4), base * CFrame.new(-5.8, 3.3, -3.4), "#6B4424", model)
	part("PoleR", Vector3.new(0.4, 6.6, 0.4), base * CFrame.new(5.8, 3.3, -3.4), "#6B4424", model)
	local counter =
		part("Counter", Vector3.new(10, 2.6, 2), base * CFrame.new(0, 1.3, -2.4), "#A0703D", model, nil, Enum.Material.WoodPlanks)
	part("Cloth", Vector3.new(10.2, 0.2, 2.2), base * CFrame.new(0, 2.7, -2.4), "#8B6AD8", model, nil, Enum.Material.Fabric)
	part("Jar", Vector3.new(0.9, 0.9, 0.9), base * CFrame.new(-3, 3.25, -2.4), "#F4C43A", model, Enum.PartType.Ball)
	part("Crate", Vector3.new(1.4, 1, 1.2), base * CFrame.new(3, 3.3, -2.4), "#C08A4E", model)
	buildFigure(base * CFrame.new(0, 0, -0.4) * CFrame.Angles(0, math.rad(180), 0), model)
	model.PrimaryPart = body

	local anchor = Instance.new("Attachment")
	anchor.Name = "PromptAnchor"
	anchor.Position = Vector3.new(0, 1.8, 0)
	anchor.Parent = counter
	local p = Instance.new("ProximityPrompt")
	p.Name = "MerchantPrompt"
	p.ActionText = "Trade"
	p.ObjectText = "Travelling Merchant"
	p.HoldDuration = 0
	p.MaxActivationDistance = W.promptDistance
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.Parent = anchor
	p.Triggered:Connect(function()
		if ctx.Router:Has("Merchant") then
			ctx.Router:Open("Merchant")
		end
	end)
	prompt = p
	model.Parent = root
	return model
end

local function sync()
	local present = Logic.At(ctx:Now()).present
	if present and not caravan then
		caravan = build()
	elseif not present and caravan then
		caravan:Destroy()
		caravan = nil
		prompt = nil
	end
end

-- Lifecycle --------------------------------------------------------------------------------

function Merchant.Init(context)
	ctx = context
end

function Merchant.Start()
	local folder = Instance.new("Folder")
	folder.Name = "Merchant"
	folder.Parent = workspace
	root = folder
	sinceCheck = math.huge
	sync()
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			sinceCheck += dt
			if sinceCheck >= POLL then
				sinceCheck = 0
				sync()
			end
		end)
	)
end

function Merchant.Destroy()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	if root then
		root:Destroy()
		root = nil
	end
	caravan = nil
	prompt = nil
end

function Merchant.Caravan(): Model?
	return caravan
end

function Merchant.Prompt(): ProximityPrompt?
	return prompt
end

return Merchant
