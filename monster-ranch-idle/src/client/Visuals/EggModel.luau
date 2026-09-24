--[[
	EggModel: procedural placeholder egg. Contract: Model with PrimaryPart "Root" (the shell),
	anchored unless opts.anchored == false, attribute EggType. Art swap: clone
	ReplicatedStorage.Assets.Eggs[eggType] when it exists.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local EggModel = {}

function EggModel.Build(eggType: string, opts: { anchored: boolean?, size: number? }?)
	local options = opts or {}
	local def = Config.Eggs.ById[eggType]
	local shellColor = Color3.fromHex(def and def.colors.shell or "#C9EDA8")
	local spotColor = Color3.fromHex(def and def.colors.spots or "#79C455")
	local size = options.size or 2

	local model = Instance.new("Model")
	model.Name = (def and def.name) or "Egg"

	local shell = Instance.new("Part")
	shell.Name = "Root"
	-- Block + sphere mesh: a Ball part cannot be stretched into an egg shape.
	shell.Size = Vector3.new(size, size * 1.3, size)
	local shellMesh = Instance.new("SpecialMesh")
	shellMesh.MeshType = Enum.MeshType.Sphere
	shellMesh.Parent = shell
	shell.Color = shellColor
	shell.Material = if def and def.pattern == "facets" then Enum.Material.Glass else Enum.Material.SmoothPlastic
	shell.Anchored = options.anchored ~= false
	shell.CanCollide = false
	shell.CanQuery = false
	shell.CanTouch = false
	shell.CFrame = CFrame.new()
	shell.Parent = model
	model.PrimaryPart = shell

	local spots = {
		Vector3.new(0.45, 0.2, -0.3),
		Vector3.new(-0.4, -0.15, -0.3),
		Vector3.new(0.1, 0.45, 0.4),
		Vector3.new(-0.2, -0.4, 0.45),
	}
	for i, dir in spots do
		local unit = dir.Unit
		local surface = Vector3.new(unit.X * size / 2, unit.Y * size * 0.65, unit.Z * size / 2)
		local spot = Instance.new("Part")
		spot.Name = "Spot" .. i
		spot.Size = Vector3.new(size * 0.3, size * 0.3, size * 0.1)
		local spotMesh = Instance.new("SpecialMesh")
		spotMesh.MeshType = Enum.MeshType.Sphere
		spotMesh.Parent = spot
		spot.Color = spotColor
		spot.Material = if def and def.pattern == "stars" then Enum.Material.Neon else Enum.Material.SmoothPlastic
		spot.CanCollide, spot.CanQuery, spot.CanTouch, spot.Anchored = false, false, false, false
		spot.CFrame = CFrame.lookAt(surface, surface * 2)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = shell
		weld.Part1 = spot
		weld.Parent = spot
		spot.Parent = model
	end
	if def and (def.id == "royal" or def.id == "starlit" or def.id == "stampede") then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = spotColor
		sparkles.Parent = shell
	end
	model:SetAttribute("EggType", eggType)
	return model
end

return EggModel
