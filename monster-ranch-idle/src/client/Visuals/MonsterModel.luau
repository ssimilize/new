--[[
	MonsterModel: procedural placeholder 3D monsters. THE ART SWAP POINT.

		local model = MonsterModel.Build(appearance, { anchored = true })  -- opts.scale multiplies the size (mounts)
		model:PivotTo(CFrame.new(0, 3, 0))

	Contract (keep it when real models replace this file):
	  • returns a Model with PrimaryPart "Root" (invisible, anchored unless opts.anchored == false)
	  • every other part is welded to Root, CanCollide = false, CanQuery = false
	  • attachments on Root: "Head" (above the head, for name tags / effects), "Feet"
	  • attributes: Line, Form, Stage, Rarity, Variant, Rainbow (bool), Height (studs)
	  • Build must be cheap: ≤ 20 parts (+ ≤ 3 per worn accessory); no scripts inside
	  • appearance.acc { [slot] = accessoryId } draws Config.Accessories placeholders (1.5)
	  • particle effects (element aura, mutations, shiny / rainbow, epic+ ground glow) come from
	    Visuals/Vfx on BOTH paths; opts.vfx == false builds without them (ViewportMonster, since
	    particles do not render in a ViewportFrame; statues). The placeholder keeps only geometry
	    and PointLights for elements and mutations.
	To use authored models later: look up a model by appearance.form in
	ReplicatedStorage.Assets.Monsters (if present), clone it, and keep the contract above.
	3D monsters: a form with a rig module in Visuals/MeshMonsters and a published mesh and texture
	(Visuals/MeshMonsterAssets) is built by MeshMonster instead (a skinned mesh; MonsterAnimator
	plays its clips). A failed mesh build falls back to the placeholder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local MeshMonster = require(script.Parent.MeshMonster)
local Vfx = require(script.Parent.Vfx)

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

local function cylinder(model, root, name, size: Vector3, color, offset, material)
	return part(model, root, name, Enum.PartType.Cylinder, size, color, offset, material)
end

-- Accessories (update 1.5): placeholder shapes per Config.Accessories `shape`, placed by
-- slot on the body measured in Build (`d`). Cylinders run along X, so they are turned to
-- stand up (Z 90°) or face forward (Y 90°). Art replaces these with authored meshes later.
local UP = CFrame.Angles(0, 0, math.rad(90))
local FORWARD = CFrame.Angles(0, math.rad(90), 0)

local function addAccessory(model, root, def, d)
	local s, top, body = d.s, d.top, d.bodySize
	local c1 = Color3.fromHex(def.color)
	local c2 = Color3.fromHex(def.color2 or def.color)
	local name = "Acc_" .. def.slot
	local shape = def.shape
	local neckY = d.bodyY - body.Y * 0.18
	local front = -body.Z * 0.48
	local back = body.Z * 0.5
	if def.slot == "head" then
		if shape == "cap" or shape == "beanie" then
			ball(model, root, name, Vector3.new(s * 0.62, s * 0.3, s * 0.62), c1, CFrame.new(0, top - s * 0.02, 0))
			if shape == "cap" then
				ball(model, root, name .. "Brim", Vector3.new(s * 0.4, s * 0.06, s * 0.36), c2, CFrame.new(0, top - s * 0.06, -s * 0.3))
			else
				ball(model, root, name .. "Pom", Vector3.new(s * 0.16, s * 0.16, s * 0.16), c2, CFrame.new(0, top + s * 0.15, 0))
			end
		elseif shape == "tophat" or shape == "chef" then
			local h = if shape == "tophat" then s * 0.45 else s * 0.3
			cylinder(model, root, name, Vector3.new(h, s * 0.36, s * 0.36), c1, CFrame.new(0, top + h / 2, 0) * UP)
			if shape == "tophat" then
				cylinder(model, root, name .. "Brim", Vector3.new(s * 0.04, s * 0.56, s * 0.56), c1, CFrame.new(0, top + s * 0.02, 0) * UP)
				cylinder(model, root, name .. "Band", Vector3.new(s * 0.07, s * 0.37, s * 0.37), c2, CFrame.new(0, top + s * 0.08, 0) * UP)
			else
				ball(model, root, name .. "Puff", Vector3.new(s * 0.5, s * 0.3, s * 0.5), c1, CFrame.new(0, top + h + s * 0.08, 0))
			end
		elseif shape == "crown" then
			cylinder(
				model,
				root,
				name,
				Vector3.new(s * 0.16, s * 0.44, s * 0.44),
				c1,
				CFrame.new(0, top + s * 0.06, 0) * UP,
				Enum.Material.Metal
			)
			ball(
				model,
				root,
				name .. "Gem",
				Vector3.new(s * 0.1, s * 0.1, s * 0.06),
				c2,
				CFrame.new(0, top + s * 0.07, -s * 0.22),
				Enum.Material.Neon
			)
		elseif shape == "cone" or shape == "wizard" then
			local tall = if shape == "wizard" then s * 0.75 else s * 0.55
			ball(model, root, name, Vector3.new(s * 0.34, tall, s * 0.34), c1, CFrame.new(0, top + tall * 0.35, 0))
			if shape == "wizard" then
				cylinder(model, root, name .. "Brim", Vector3.new(s * 0.04, s * 0.7, s * 0.7), c1, CFrame.new(0, top, 0) * UP)
			end
			ball(
				model,
				root,
				name .. "Tip",
				Vector3.new(s * 0.12, s * 0.12, s * 0.12),
				c2,
				CFrame.new(0, top + tall * 0.82, 0),
				Enum.Material.Neon
			)
		elseif shape == "flowers" then
			for i = 0, 2 do
				local a = math.rad(i * 120)
				ball(
					model,
					root,
					name,
					Vector3.new(s * 0.16, s * 0.16, s * 0.16),
					if i == 1 then c2 else c1,
					CFrame.new(math.cos(a) * s * 0.2, top + s * 0.02, math.sin(a) * s * 0.2)
				)
			end
		elseif shape == "halo" then
			local halo = cylinder(
				model,
				root,
				name,
				Vector3.new(s * 0.05, s * 0.55, s * 0.55),
				c1,
				CFrame.new(0, top + s * 0.35, 0) * UP,
				Enum.Material.Neon
			)
			halo.Transparency = 0.2
		elseif shape == "ears" or shape == "horns" then
			for _, x in { -1, 1 } do
				local size = if shape == "ears" then Vector3.new(s * 0.14, s * 0.5, s * 0.1) else Vector3.new(s * 0.12, s * 0.26, s * 0.12)
				ball(model, root, name, size, c1, CFrame.new(x * s * 0.2, top + size.Y * 0.4, 0) * CFrame.Angles(0, 0, math.rad(-x * 15)))
			end
		elseif shape == "brim" then
			cylinder(model, root, name, Vector3.new(s * 0.04, s * 0.85, s * 0.85), c1, CFrame.new(0, top - s * 0.02, 0) * UP)
			ball(model, root, name .. "Top", Vector3.new(s * 0.42, s * 0.24, s * 0.42), c1, CFrame.new(0, top + s * 0.06, 0))
			cylinder(model, root, name .. "Band", Vector3.new(s * 0.06, s * 0.43, s * 0.43), c2, CFrame.new(0, top + s * 0.02, 0) * UP)
		elseif shape == "helmet" then
			ball(model, root, name, Vector3.new(body.X * 0.82, s * 0.4, body.Z * 0.82), c1, CFrame.new(0, top - s * 0.08, 0))
			block(model, root, name .. "Stripe", Vector3.new(s * 0.08, s * 0.12, body.Z * 0.7), c2, CFrame.new(0, top + s * 0.1, 0))
		elseif shape == "bubble" then
			local bubble = ball(
				model,
				root,
				name,
				Vector3.new(body.X * 1.05, body.Y * 0.8, body.Z * 1.05),
				c1,
				CFrame.new(0, top - body.Y * 0.2, 0),
				Enum.Material.Glass
			)
			bubble.Transparency = 0.6
		end
	elseif def.slot == "face" then
		local y, z = d.eyeY, d.eyeZ - s * 0.08
		if shape == "glasses" or shape == "shades" or shape == "goggles" then
			for _, x in { -0.22, 0.22 } do
				local lens = cylinder(model, root, name, Vector3.new(s * 0.04, s * 0.28, s * 0.28), c1, CFrame.new(x * s, y, z) * FORWARD)
				if shape == "glasses" then
					lens.Transparency = 0.5
				end
			end
			block(model, root, name .. "Bridge", Vector3.new(s * 0.16, s * 0.04, s * 0.04), c1, CFrame.new(0, y, z))
		elseif shape == "monocle" then
			local lens = cylinder(
				model,
				root,
				name,
				Vector3.new(s * 0.04, s * 0.3, s * 0.3),
				c1,
				CFrame.new(s * 0.22, y, z) * FORWARD,
				Enum.Material.Metal
			)
			lens.Transparency = 0.3
		elseif shape == "mask" then
			block(model, root, name, Vector3.new(body.X * 0.8, s * 0.18, s * 0.06), c1, CFrame.new(0, y, z + s * 0.02))
		elseif shape == "mustache" then
			for _, x in { -1, 1 } do
				ball(
					model,
					root,
					name,
					Vector3.new(s * 0.22, s * 0.08, s * 0.06),
					c1,
					CFrame.new(x * s * 0.1, y - s * 0.22, z) * CFrame.Angles(0, 0, math.rad(x * 12))
				)
			end
		elseif shape == "blush" then
			for _, x in { -0.34, 0.34 } do
				ball(model, root, name, Vector3.new(s * 0.14, s * 0.08, s * 0.03), c1, CFrame.new(x * s, y - s * 0.12, z + s * 0.04))
			end
		end
	elseif def.slot == "neck" then
		if shape == "scarf" or shape == "lei" then
			ball(model, root, name, Vector3.new(body.X * 0.98, s * 0.14, body.Z * 0.98), c1, CFrame.new(0, neckY, 0))
			if shape == "scarf" then
				block(
					model,
					root,
					name .. "Tail",
					Vector3.new(s * 0.14, s * 0.3, s * 0.05),
					c1,
					CFrame.new(s * 0.18, neckY - s * 0.15, front)
				)
			else
				ball(model, root, name .. "Bloom", Vector3.new(s * 0.14, s * 0.14, s * 0.14), c2, CFrame.new(0, neckY, front))
			end
		elseif shape == "bowtie" then
			for _, x in { -1, 1 } do
				ball(model, root, name, Vector3.new(s * 0.2, s * 0.14, s * 0.08), c1, CFrame.new(x * s * 0.09, neckY, front))
			end
		elseif shape == "medal" then
			cylinder(
				model,
				root,
				name,
				Vector3.new(s * 0.04, s * 0.2, s * 0.2),
				c1,
				CFrame.new(0, neckY - s * 0.1, front) * FORWARD,
				Enum.Material.Metal
			)
		elseif shape == "bell" then
			ball(
				model,
				root,
				name,
				Vector3.new(s * 0.16, s * 0.16, s * 0.16),
				c1,
				CFrame.new(0, neckY - s * 0.06, front),
				Enum.Material.Metal
			)
			ball(model, root, name .. "Collar", Vector3.new(body.X * 0.95, s * 0.06, body.Z * 0.95), c2, CFrame.new(0, neckY, 0))
		end
	elseif def.slot == "back" then
		if shape == "cape" then
			block(
				model,
				root,
				name,
				Vector3.new(body.X * 0.85, body.Y * 0.85, s * 0.04),
				c1,
				CFrame.new(0, d.bodyY - body.Y * 0.05, back) * CFrame.Angles(math.rad(-10), 0, 0)
			)
			if def.color2 then
				block(
					model,
					root,
					name .. "Trim",
					Vector3.new(body.X * 0.87, s * 0.06, s * 0.05),
					c2,
					CFrame.new(0, d.bodyY + body.Y * 0.36, back - s * 0.02)
				)
			end
		elseif shape == "wings" then
			for _, x in { -1, 1 } do
				ball(
					model,
					root,
					name,
					Vector3.new(s * 0.6, s * 0.4, s * 0.06),
					if x < 0 then c1 else c2,
					CFrame.new(x * s * 0.32, d.bodyY + s * 0.1, back) * CFrame.Angles(0, math.rad(x * 25), math.rad(x * 20))
				)
			end
		elseif shape == "pack" or shape == "jetpack" then
			block(model, root, name, Vector3.new(body.X * 0.55, body.Y * 0.55, s * 0.24), c1, CFrame.new(0, d.bodyY, back + s * 0.06))
			if shape == "jetpack" then
				for _, x in { -1, 1 } do
					cylinder(
						model,
						root,
						name .. "Jet",
						Vector3.new(s * 0.34, s * 0.14, s * 0.14),
						c2,
						CFrame.new(x * s * 0.16, d.bodyY - s * 0.2, back + s * 0.2) * UP,
						Enum.Material.Neon
					)
				end
			end
		elseif shape == "board" then
			ball(model, root, name, Vector3.new(s * 0.3, body.Y * 1.2, s * 0.06), c1, CFrame.new(0, d.bodyY + s * 0.1, back + s * 0.04))
		end
	end
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

-- Particle effects on a finished model; a failure here never costs the monster its body.
local function attachVfx(model: Model, appearance, options)
	if options.vfx == false then
		return
	end
	local ok, err = pcall(Vfx.AttachMonster, model, appearance)
	if not ok then
		warn("[MonsterModel] effects failed for " .. tostring(appearance.form) .. ": " .. tostring(err))
	end
end

function MonsterModel.Build(appearance, opts: { anchored: boolean?, scale: number?, vfx: boolean? }?)
	local options = opts or {}
	local s = BASE_SIZE * MonsterModel.ScaleFor(appearance) * (options.scale or 1)
	if MeshMonster.Has(appearance.form) then
		local ok, meshModel = pcall(MeshMonster.Build, appearance, s, options.anchored ~= false)
		if ok then
			attachVfx(meshModel, appearance, options)
			return meshModel
		end
		warn("[MonsterModel] mesh build failed for " .. tostring(appearance.form) .. ": " .. tostring(meshModel))
	end
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

	-- Element accent (geometry and lights; the particles are Vfx's element aura).
	if element == "ember" then
		ball(model, root, "Flame", Vector3.new(s * 0.3, s * 0.45, s * 0.3), accent, CFrame.new(0, top + s * 0.12, 0), Enum.Material.Neon)
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
	elseif element == "light" then
		-- Light (2.0): a small sun-crest and a warm glow.
		ball(model, root, "Crest", Vector3.new(s * 0.22, s * 0.22, s * 0.22), accent, CFrame.new(0, top + s * 0.16, 0), Enum.Material.Neon)
		for _, x in { -1, 1 } do
			ball(
				model,
				root,
				"Ray",
				Vector3.new(s * 0.08, s * 0.3, s * 0.08),
				accent,
				CFrame.new(x * s * 0.16, top + s * 0.1, 0) * CFrame.Angles(0, 0, math.rad(-x * 35)),
				Enum.Material.Neon
			)
		end
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromHex("#FFE9A8")
		glow.Brightness = 1.2
		glow.Range = s * 3
		glow.Parent = bodyPart
	elseif element == "void" then
		-- Void (2.0): a tiny rift orbiting the head.
		local rift = ball(
			model,
			root,
			"Rift",
			Vector3.new(s * 0.2, s * 0.2, s * 0.2),
			accent,
			CFrame.new(s * 0.35, top + s * 0.1, s * 0.1),
			Enum.Material.Neon
		)
		rift.Transparency = 0.15
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromHex("#5CE1E6")
		glow.Brightness = 0.8
		glow.Range = s * 2.5
		glow.Parent = bodyPart
	elseif element == "gloom" then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("#C9A8FF")
		light.Brightness = 1
		light.Range = s * 3
		light.Parent = bodyPart
	end

	-- Mutation geometry (their particles are Vfx's).
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
		end
	end
	-- Accessories (1.5): one placeholder per worn slot.
	if type(appearance.acc) == "table" then
		for _, id in appearance.acc do
			local def = Config.Accessories and Config.Accessories.Resolve(id) -- Workshop designs too (3.0)
			if def then
				addAccessory(model, root, def, { s = s, top = top, bodyY = bodyY, bodySize = bodySize, eyeY = eyeY, eyeZ = eyeZ })
			end
		end
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
	attachVfx(model, appearance, options)
	return model
end

return MonsterModel
