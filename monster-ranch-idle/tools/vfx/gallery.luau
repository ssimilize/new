--[[
	Particle bake-off gallery (Edit-mode, run through execute_luau; not game code).

	Builds Workspace.VfxBakeoff: one row per method, one column per sprite, every cell the same
	emitter preset so only the texture differs. Rows sit on a grass strip under daylight, with a
	dark backing panel behind each row's right half so a sprite is judged on both.

	Loaded as ServerStorage.VfxGallery (a ModuleScript); require a clone and call it with rows where rows = { { name, textures = { [sprite] = id },
	tint = bool } }. tint = true colours a white sprite with the element colour; false shows the
	sprite's own colours (Color = white).
]]

local ORIGIN = Vector3.new(0, 600, -3000)
local COL = 14
local ROW = 12
local SPRITES = { "flame", "droplet", "leaf", "bolt", "star", "wisp" }
local TINT = {
	flame = Color3.fromHex("#FF8A3D"),
	droplet = Color3.fromHex("#4AA6F0"),
	leaf = Color3.fromHex("#62BF55"),
	bolt = Color3.fromHex("#F6CD3A"),
	star = Color3.fromHex("#FFE9A0"),
	wisp = Color3.fromHex("#9168D0"),
}

local function seq(points)
	local k = {}
	for _, p in points do
		table.insert(k, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(k)
end

-- One preset per sprite: how the game would use it as an ambient monster/landmark effect.
local PRESET = {
	flame = {
		Rate = 14, Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(2, 3.5),
		SpreadAngle = Vector2.new(12, 12), Acceleration = Vector3.new(0, 4, 0),
		Size = seq({ { 0, 1.1 }, { 0.6, 0.8 }, { 1, 0.1 } }),
		Transparency = seq({ { 0, 1 }, { 0.12, 0.05 }, { 0.7, 0.3 }, { 1, 1 } }),
		LightEmission = 0.25, LightInfluence = 0, Rotation = NumberRange.new(-10, 10),
	},
	droplet = {
		Rate = 6, Lifetime = NumberRange.new(0.8, 1.1), Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, -14, 0),
		Size = seq({ { 0, 0.5 }, { 1, 0.4 } }),
		Transparency = seq({ { 0, 1 }, { 0.1, 0 }, { 0.8, 0 }, { 1, 1 } }),
		LightEmission = 0.2, LightInfluence = 0.6,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	},
	leaf = {
		Rate = 4, Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, -1.2, 0), Drag = 0.6,
		Size = seq({ { 0, 0.6 }, { 1, 0.5 } }),
		Transparency = seq({ { 0, 1 }, { 0.1, 0 }, { 0.8, 0 }, { 1, 1 } }),
		LightEmission = 0, LightInfluence = 0.8,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
	},
	bolt = {
		Rate = 5, Lifetime = NumberRange.new(0.15, 0.25), Speed = NumberRange.new(0),
		Size = seq({ { 0, 1.4 }, { 1, 1.2 } }),
		Transparency = seq({ { 0, 0 }, { 0.5, 0.2 }, { 1, 1 } }),
		LightEmission = 0.3, LightInfluence = 0, Rotation = NumberRange.new(-40, 40),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	},
	star = {
		Rate = 6, Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(0.3, 0.8),
		SpreadAngle = Vector2.new(180, 180),
		Size = seq({ { 0, 0 }, { 0.3, 0.8 }, { 1, 0 } }),
		Transparency = seq({ { 0, 0 }, { 1, 0.2 } }),
		LightEmission = 0.3, LightInfluence = 0, Rotation = NumberRange.new(0, 45),
		RotSpeed = NumberRange.new(-30, 30),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	},
	wisp = {
		Rate = 5, Lifetime = NumberRange.new(1.8, 2.4), Speed = NumberRange.new(0.8, 1.4),
		SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(0, 0.6, 0), Drag = 0.4,
		Size = seq({ { 0, 0.8 }, { 1, 2.2 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.35 }, { 1, 1 } }),
		LightEmission = 0.15, LightInfluence = 0.3,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-25, 25),
	},
}

local function part(name, size, cf, color, parent, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

local function scaled(v, k)
	if typeof(v) == "NumberSequence" then
		local out = {}
		for _, kp in v.Keypoints do
			table.insert(out, NumberSequenceKeypoint.new(kp.Time, kp.Value * k))
		end
		return NumberSequence.new(out)
	elseif typeof(v) == "NumberRange" then
		return NumberRange.new(v.Min * k, v.Max * k)
	end
	return v * k
end

-- scale (default 1) enlarges particles, their speeds and the grid for close-up judging.
local function Gallery(rows, scale)
	local k = scale or 1
	local COL, ROW = COL * k, ROW * k
	local old = workspace:FindFirstChild("VfxBakeoff")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "VfxBakeoff"
	root.Parent = workspace
	local width = COL * #SPRITES * 2
	for r, row in rows do
		local base = ORIGIN - Vector3.new(0, (r - 1) * ROW, 0)
		part("Grass" .. r, Vector3.new(width + 8, 1, 10 * k), CFrame.new(base + Vector3.new(width / 2 - COL / 2, -0.5, 0)),
			Color3.fromHex("#8FD16A"), root)
		-- dark half behind the second copy of each sprite
		part("Dark" .. r, Vector3.new(COL * #SPRITES, ROW, 1), CFrame.new(base + Vector3.new(COL * #SPRITES * 1.5 - COL / 2, ROW / 2 - 0.5, -5 * k)),
			Color3.fromHex("#23202E"), root)
		local label = Instance.new("BillboardGui")
		label.Size = UDim2.fromOffset(220, 40)
		label.StudsOffset = Vector3.new(0, 0, 0)
		label.AlwaysOnTop = true
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBold
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0
		t.Text = row.name
		t.Parent = label
		local anchor = part("Label" .. r, Vector3.new(1, 1, 1), CFrame.new(base + Vector3.new(-COL, 3, 0)), Color3.new(), root, 1)
		label.Parent = anchor
		for copy = 0, 1 do
			for c, sprite in SPRITES do
				local id = row.textures[sprite]
				if id then
					local x = (copy * #SPRITES + (c - 1)) * COL
					local holder = part(row.name .. "_" .. sprite .. "_" .. copy, Vector3.new(2, 2, 2) * k,
						CFrame.new(base + Vector3.new(x, 3 * k, 0)), Color3.new(), root, 1)
					local e = Instance.new("ParticleEmitter")
					e.Texture = id
					e.Color = ColorSequence.new(if row.tint then TINT[sprite] else Color3.new(1, 1, 1))
					e.EmissionDirection = Enum.NormalId.Top
					for key, v in PRESET[sprite] do
						if key == "Size" or key == "Speed" or key == "Acceleration" then
							v = scaled(v, k)
						end
						(e :: any)[key] = v
					end
					e.Parent = holder
				end
			end
		end
	end
	return #rows
end

local function label(text, cf, parent)
	local anchor = part("Label", Vector3.new(1, 1, 1), cf, Color3.new(), parent, 1)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(150, 28)
	gui.AlwaysOnTop = true
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0
	t.Text = text
	t.Parent = gui
	gui.Parent = anchor
end

-- One row per sprite, the methods side by side: rows as for Gallery; sprites = which to show.
-- Row s sits at ORIGIN.Y + 200 - (s - 1) * 10k; cell m at x = (m - 1) * 8k, all on light sky.
local function Compare(rows, sprites, scale)
	local k = scale or 3
	local old = workspace:FindFirstChild("VfxCompare")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "VfxCompare"
	root.Parent = workspace
	for si, sprite in sprites do
		local base = ORIGIN + Vector3.new(0, 200 - (si - 1) * 10 * k, 0)
		for m, row in rows do
			local id = row.textures[sprite]
			if id then
				local holder = part(row.name .. "_" .. sprite, Vector3.new(2, 2, 2) * k,
					CFrame.new(base + Vector3.new((m - 1) * 8 * k, 0, 0)), Color3.new(), root, 1)
				local e = Instance.new("ParticleEmitter")
				e.Texture = id
				e.Color = ColorSequence.new(if row.tint then TINT[sprite] else Color3.new(1, 1, 1))
				e.EmissionDirection = Enum.NormalId.Top
				for key, v in PRESET[sprite] do
					if key == "Size" or key == "Speed" or key == "Acceleration" then
						v = scaled(v, k)
					end
					(e :: any)[key] = v
				end
				e.Parent = holder
				if si == 1 then
					label(row.name, CFrame.new(base + Vector3.new((m - 1) * 8 * k, 4 * k, 0)), root)
				end
			end
		end
	end
	return root
end

return { Gallery = Gallery, Compare = Compare, Origin = ORIGIN }
