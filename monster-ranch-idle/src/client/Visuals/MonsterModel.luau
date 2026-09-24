--[[
	MonsterModel: procedural placeholder 3D monsters. THE ART SWAP POINT.

		local model = MonsterModel.Build(appearance, { anchored = true })
		model:PivotTo(CFrame.new(0, 3, 0))

	Contract (keep it when real models replace this file):
	  • returns a Model with PrimaryPart "Root" (invisible, anchored unless opts.anchored == false)
	  • every other part is welded to Root, CanCollide = false, CanQuery = false
	  • attachments on Root: "Head" (above the head, for name tags / effects), "Feet"
	  • attributes: Line, Form, Stage, Rarity, Variant, Rainbow (bool), Height (studs)
	  • Build must be cheap: ≤ 20 parts; no scripts inside
	To use authored models later: look up a model by appearance.form in
	ReplicatedStorage.Assets.Monsters (if present), clone it, and keep the contract above.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local MonsterModel = {}

local BASE_SIZE = 3 -- studs, adult of average weight
local INK = Color3.fromHex("#1D1D1D")

local function part(
	model: Model,
	root: BasePart,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	color: Color3,
	offset: CFrame,
	material: Enum.Material?
)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	if shape == Enum.PartType.Ball then
		-- Ball parts are always perfectly round; a sphere mesh on a block stretches to the
		-- part's size (eyes, wings, bellies) and lets the animator squash it via Scale.
		p.Shape = Enum.PartType.Block
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	else
		p.Shape = shape
	end
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Anchored = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function ball(model, root, name, size: Vector3, color, offset, material)
	return part(model, root, name, Enum.PartType.Ball, size, color, offset, material)
end

local function block(model, root, name, size: Vector3, color, offset, material)
	return part(model, root, name, Enum.PartType.Block, size, color, offset, material)
end

local function wedge(model, root, name, size: Vector3, color, offset)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch, p.Anchored, p.CastShadow = false, false, false, false, false
	p.CFrame = root.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function colorsFor(appearance)
	local element = appearance.elements and appearance.elements[1] or "sprout"
	local def = Config.Elements.ById[element]
	local body = Color3.fromHex(def.color)
	local belly = Color3.fromHex(def.light)
	local accent = Color3.fromHex(def.accent)
	if appearance.variant == 1 then
		body, belly, accent = Color3.fromHex("#F4C43A"), Color3.fromHex("#FFF1B3"), Color3.fromHex("#FFE38A")
	end
	for _, m in appearance.muts or {} do
		if m == "shadow" then
			body, belly = Color3.fromHex("#3A2D55"), Color3.fromHex("#6B5A8E")
		end
	end
	return element, body, belly, accent
end

-- Scale from stage and weight (cube root so heavy monsters are bigger, not absurd).
function MonsterModel.ScaleFor(appearance): number
	local stageScale = Config.Economy.Stages[appearance.stage or 1].scale
	local def = Config.Species.ById[appearance.line]
	local avg = def and def.weight or 1
	local w = appearance.weight or avg
	local weightScale = math.clamp((w / avg) ^ (1 / 3), 0.8, 1.3)
	return stageScale * weightScale
end

function MonsterModel.Build(appearance, opts: { anchored: boolean? }?)
	local options = opts or {}
	local s = BASE_SIZE * MonsterModel.ScaleFor(appearance)
	local element, body, belly, accent = colorsFor(appearance)
	local archetype = appearance.archetype or "blob"

	local model = Instance.new("Model")
	model.Name = appearance.name or appearance.form or "Monster"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(s, s, s)
	root.Transparency = 1
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Anchored = options.anchored ~= false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local floating = archetype == "sprite" or archetype == "moth"
	local lift = if floating then s * 0.25 else 0

	-- Body proportions per archetype.
	local bodySize = Vector3.new(s, s * 0.9, s)
	if archetype == "slug" then
		bodySize = Vector3.new(s * 0.8, s * 0.65, s * 1.4)
	elseif archetype == "golem" then
		bodySize = Vector3.new(s * 1.1, s, s)
	elseif archetype == "sprite" then
		bodySize = Vector3.new(s * 0.85, s * 0.85, s * 0.85)
	end
	local bodyY = bodySize.Y / 2 + lift
	local bodyPart
	if archetype == "golem" then
		bodyPart = block(model, root, "Body", bodySize, body, CFrame.new(0, bodyY, 0), Enum.Material.Slate)
	else
		bodyPart = ball(model, root, "Body", bodySize, body, CFrame.new(0, bodyY, 0))
	end
	ball(
		model,
		root,
		"Belly",
		Vector3.new(bodySize.X * 0.62, bodySize.Y * 0.55, bodySize.Z * 0.3),
		belly,
		CFrame.new(0, bodyY - bodySize.Y * 0.12, -bodySize.Z * 0.36)
	)

	-- Face (front is -Z).
	local eyeY = bodyY + bodySize.Y * 0.12
	local eyeZ = -bodySize.Z * 0.42
	for i, x in { -0.22, 0.22 } do
		local side = if i == 1 then "L" else "R"
		ball(model, root, "Eye" .. side, Vector3.new(s * 0.22, s * 0.26, s * 0.14), Color3.new(1, 1, 1), CFrame.new(x * s, eyeY, eyeZ))
		local pupilColor = INK
		local pupilMaterial = Enum.Material.SmoothPlastic
		for _, m in appearance.muts or {} do
			if m == "shadow" then
				pupilColor, pupilMaterial = Color3.fromHex("#FFD447"), Enum.Material.Neon
			end
		end
		ball(
			model,
			root,
			"Pupil" .. side,
			Vector3.new(s * 0.12, s * 0.14, s * 0.08),
			pupilColor,
			CFrame.new(x * s, eyeY - s * 0.02, eyeZ - s * 0.06),
			pupilMaterial
		)
	end

	-- Feet (grounded archetypes).
	if not floating and archetype ~= "slug" then
		for _, x in { -0.25, 0.25 } do
			ball(model, root, "Foot", Vector3.new(s * 0.3, s * 0.18, s * 0.36), body, CFrame.new(x * s, s * 0.08, -s * 0.05))
		end
	end

	-- Archetype extras.
	local top = bodyY + bodySize.Y / 2
	if archetype == "fox" then
		for _, x in { -0.28, 0.28 } do
			wedge(
				model,
				root,
				"Ear",
				Vector3.new(s * 0.08, s * 0.4, s * 0.3),
				body,
				CFrame.new(x * s, top, 0) * CFrame.Angles(0, math.rad(90), 0)
			)
		end
		ball(
			model,
			root,
			"Tail",
			Vector3.new(s * 0.3, s * 0.3, s * 0.8),
			accent,
			CFrame.new(0, bodyY, bodySize.Z * 0.55) * CFrame.Angles(math.rad(-30), 0, 0)
		)
	elseif archetype == "bunny" then
		for _, x in { -0.18, 0.18 } do
			ball(model, root, "Ear", Vector3.new(s * 0.18, s * 0.7, s * 0.14), body, CFrame.new(x * s, top + s * 0.25, 0))
		end
	elseif archetype == "moth" or archetype == "bug" then
		local wingColor = if archetype == "bug" then Color3.fromHex("#DFF3FF") else accent
		for _, x in { -1, 1 } do
			local wing = ball(
				model,
				root,
				"Wing",
				Vector3.new(s * 0.08, s * 0.8, s * 0.6),
				wingColor,
				CFrame.new(x * s * 0.55, bodyY + s * 0.1, s * 0.1) * CFrame.Angles(0, 0, math.rad(-x * 25))
			)
			wing.Transparency = if archetype == "bug" then 0.35 else 0
		end
		for _, x in { -0.15, 0.15 } do
			ball(model, root, "Antenna", Vector3.new(s * 0.05, s * 0.4, s * 0.05), INK, CFrame.new(x * s, top + s * 0.12, -s * 0.1))
		end
	elseif archetype == "golem" then
		for _, x in { -0.6, 0.6 } do
			block(
				model,
				root,
				"Shoulder",
				Vector3.new(s * 0.35, s * 0.35, s * 0.35),
				accent,
				CFrame.new(x * s, bodyY + s * 0.2, 0),
				Enum.Material.Slate
			)
		end
	elseif archetype == "slug" then
		for _, x in { -0.15, 0.15 } do
			ball(model, root, "Stalk", Vector3.new(s * 0.07, s * 0.35, s * 0.07), body, CFrame.new(x * s, top + s * 0.1, -bodySize.Z * 0.3))
		end
	elseif archetype == "sprite" then
		for i = 1, 3 do
			local wisp = ball(
				model,
				root,
				"Wisp",
				Vector3.new(s * 0.25, s * 0.25, s * 0.25) * (1 - i * 0.2),
				accent,
				CFrame.new(0, bodyY - s * 0.2 - i * s * 0.12, s * 0.2 * i),
				Enum.Material.Neon
			)
			wisp.Transparency = 0.2 + i * 0.15
		end
	end

	-- Element accent.
	if element == "ember" then
		local flame = ball(
			model,
			root,
			"Flame",
			Vector3.new(s * 0.3, s * 0.45, s * 0.3),
			accent,
			CFrame.new(0, top + s * 0.12, 0),
			Enum.Material.Neon
		)
		local fire = Instance.new("Fire")
		fire.Size = s * 1.2
		fire.Heat = 3
		fire.Color = Color3.fromHex("#FFB547")
		fire.SecondaryColor = Color3.fromHex("#F0663A")
		fire.Parent = flame
	elseif element == "tide" then
		for _, x in { -1, 1 } do
			ball(
				model,
				root,
				"Fin",
				Vector3.new(s * 0.1, s * 0.35, s * 0.45),
				accent,
				CFrame.new(x * bodySize.X * 0.5, bodyY, 0) * CFrame.Angles(0, 0, math.rad(x * 30))
			)
		end
	elseif element == "sprout" then
		for _, x in { -1, 1 } do
			ball(
				model,
				root,
				"Leaf",
				Vector3.new(s * 0.4, s * 0.08, s * 0.22),
				accent,
				CFrame.new(x * s * 0.16, top + s * 0.12, 0) * CFrame.Angles(0, 0, math.rad(-x * 25))
			)
		end
	elseif element == "spark" then
		for _, x in { -1, 1 } do
			wedge(
				model,
				root,
				"Bolt",
				Vector3.new(s * 0.06, s * 0.45, s * 0.2),
				accent,
				CFrame.new(x * s * 0.25, top + s * 0.1, 0) * CFrame.Angles(0, math.rad(90), math.rad(x * 20))
			).Material =
				Enum.Material.Neon
		end
	elseif element == "stone" then
		for _, x in { -1, 1 } do
			ball(
				model,
				root,
				"Horn",
				Vector3.new(s * 0.14, s * 0.4, s * 0.14),
				accent,
				CFrame.new(x * s * 0.22, top + s * 0.05, -s * 0.05) * CFrame.Angles(0, 0, math.rad(-x * 20))
			)
		end
	elseif element == "gloom" then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("#C9A8FF")
		light.Brightness = 1
		light.Range = s * 3
		light.Parent = bodyPart
	end

	-- Mutation effects.
	for _, m in appearance.muts or {} do
		if m == "frosted" or m == "frozen" then
			ball(
				model,
				root,
				"SnowCap",
				Vector3.new(bodySize.X * 0.8, s * 0.2, bodySize.Z * 0.8),
				Color3.new(1, 1, 1),
				CFrame.new(0, top - s * 0.05, 0)
			)
		elseif m == "soaked" then
			local drip = Instance.new("ParticleEmitter")
			drip.Color = ColorSequence.new(Color3.fromHex("#7CC7FF"))
			drip.Size = NumberSequence.new(s * 0.08)
			drip.Rate = 4
			drip.Lifetime = NumberRange.new(0.6)
			drip.Speed = NumberRange.new(0)
			drip.Acceleration = Vector3.new(0, -12, 0)
			drip.Parent = bodyPart
		elseif m == "charged" or m == "plasma" or m == "starstruck" or m == "prismatic" then
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = if m == "charged"
				then Color3.fromHex("#FFE14D")
				elseif m == "plasma" then Color3.fromHex("#C06BFF")
				elseif m == "starstruck" then Color3.fromHex("#FFD447")
				else Color3.fromHex("#FF7AC8")
			sparkles.Parent = bodyPart
		elseif m == "scorched" then
			local smoke = Instance.new("Smoke")
			smoke.Size = s * 0.4
			smoke.Opacity = 0.08
			smoke.RiseVelocity = 2
			smoke.Parent = bodyPart
		end
	end
	if appearance.variant == 1 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromHex("#FFF3B0")
		sparkles.Parent = bodyPart
	end

	local height = top + s * 0.3
	local head = Instance.new("Attachment")
	head.Name = "Head"
	head.Position = Vector3.new(0, height + 0.5, 0)
	head.Parent = root
	local feet = Instance.new("Attachment")
	feet.Name = "Feet"
	feet.Parent = root

	model:SetAttribute("Line", appearance.line)
	model:SetAttribute("Form", appearance.form)
	model:SetAttribute("Stage", appearance.stage)
	model:SetAttribute("Rarity", appearance.rarity)
	model:SetAttribute("Variant", appearance.variant or 0)
	model:SetAttribute("Rainbow", appearance.variant == 2)
	model:SetAttribute("Height", height)
	return model
end

return MonsterModel
