--[[
	Visuals/PenDress (glow-up R): draws a pen plan (Logic/Pens.Plan) and the Feed Garden from
	Config.Pens pieces. Art swap point: a prop with a `mesh` id is drawn as one part holding a
	SpecialMesh instead of its pieces. Nothing here runs per frame.

	  PenDress.Paint(penModel, plan)                    restyles the server-built Floor, Rail* and
	                                                    Post* parts (material, colour, transparency)
	  PenDress.Restore(penModel)                        materials back to the built look (locked pens)
	  PenDress.Caps(parent, penModel, plan) -> { BasePart }            fence caps on the corner posts
	  PenDress.Entries(parent, area, entries, plan) -> { BasePart }    props / habitat at a pen's
	                                                    floor-top CFrame `area`
	  PenDress.Garden(parent, base, garden, now, detail) -> { BasePart }   frame, beds, crops, glow
	                                                    at the garden's floor-top CFrame `base`

	Every part is anchored and non-colliding, off for queries, touches and shadows. A prop's first
	part is its anchor and carries the attributes the monster packet reads:
	  PropId = propId, PenSpot = "food"|"water"|"shelter"|"bed" (when the prop is a spot),
	  Habitat = elementId (habitat props).
	Garden beds carry GardenBed = index, CropStage = 0..4 and Flavor (when planted).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logic = require(Shared.Logic.Pens)

local PenDress = {}

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local materialCache = {}
local function material(name: string?): Enum.Material
	local key = name or "SmoothPlastic"
	local cached = materialCache[key]
	if cached then
		return cached
	end
	local ok, value = pcall(function()
		return (Enum.Material :: any)[key]
	end)
	local result = if ok and value then value else Enum.Material.SmoothPlastic
	materialCache[key] = result
	return result
end

local function hex(value: string?, fallback: Color3): Color3
	if type(value) ~= "string" then
		return fallback
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else fallback
end

-- Colour for a piece: a hex string or a token from `palette` (fence, ground, element, accent, flavor).
local function pieceColor(value: string?, palette: { [string]: Color3 }): Color3
	if type(value) == "string" and palette[value] then
		return palette[value]
	end
	return hex(value, WHITE)
end

local function newPart(shape: string, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, alpha: number?)
	local part: BasePart
	if shape == "wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		if shape == "ball" then
			p.Shape = Enum.PartType.Ball
		elseif shape == "cyl" then
			p.Shape = Enum.PartType.Cylinder
		end
		part = p
	end
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = mat
	part.Transparency = alpha or 0
	return part
end

-- One piece at `origin` (a floor-top CFrame at the prop's spot).
local function buildPiece(piece, name: string, origin: CFrame, palette, parent: Instance): BasePart
	local s, a = piece.size, piece.at
	local r = piece.rot
	local cf = origin * CFrame.new(a[1], a[2], a[3])
	if r then
		cf *= CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	end
	local size = Vector3.new(s[1], s[2], s[3])
	if piece.shape == "cyl" then
		-- A Roblox cylinder lies along X; stand it up so size.Y is its height.
		size = Vector3.new(s[2], s[1], s[3])
		cf *= CFrame.Angles(0, 0, math.rad(90))
	end
	local part = newPart(piece.shape, name, size, cf, pieceColor(piece.color, palette), material(piece.mat), piece.alpha)
	part.Parent = parent
	return part
end

local function markAnchor(part: BasePart, e)
	part:SetAttribute("PropId", e.id)
	if e.spot then
		part:SetAttribute("PenSpot", e.spot)
	end
	if e.habitat then
		part:SetAttribute("Habitat", e.habitat)
	end
end

-- A mesh prop: one part sized to `meshSize` (or 4 studs) holding a SpecialMesh.
local function buildMesh(prop, e, origin: CFrame, parent: Instance): BasePart
	local s = prop.meshSize or { 4, 4, 4 }
	local size = Vector3.new(s[1], s[2], s[3])
	local part = newPart("block", e.id, size, origin * CFrame.new(0, size.Y / 2, 0), WHITE, Enum.Material.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = prop.mesh
	mesh.TextureId = prop.texture or ""
	if prop.meshScale then
		mesh.Scale = Vector3.new(prop.meshScale[1], prop.meshScale[2], prop.meshScale[3])
	end
	mesh.Parent = part
	part.Parent = parent
	return part
end

local function palette(plan): { [string]: Color3 }
	local theme = plan.themeDef or {}
	local element = plan.element and Config.Elements.ById[plan.element]
	return {
		fence = hex(theme.fence, WHITE),
		ground = hex(theme.ground, WHITE),
		element = hex(element and element.color, WHITE),
		accent = hex(element and element.accent, WHITE),
	}
end

-- Fence -------------------------------------------------------------------------------------

local function styleColor(style, base: Color3): Color3
	local c = base
	if style.color then
		c = base:Lerp(hex(style.color, base), style.mix or 1)
	end
	if style.darken then
		c = c:Lerp(BLACK, style.darken)
	end
	return c
end

local function set(part: BasePart, key: string, value: any)
	if (part :: any)[key] ~= value then
		(part :: any)[key] = value
	end
end

function PenDress.Paint(penModel: Instance, plan)
	local fence = plan.fence
	local base = hex(plan.themeDef and plan.themeDef.fence, WHITE)
	local railMat = if fence.themed and plan.look.rail then plan.look.rail else fence.rail.mat
	local railColor = styleColor(fence.rail, base)
	local postColor = styleColor(fence.post, base)
	for _, child in penModel:GetChildren() do
		if child:IsA("BasePart") then
			local name = child.Name
			if name == "Floor" then
				set(child, "Material", material(plan.look.floor))
			elseif string.sub(name, 1, 4) == "Rail" then
				set(child, "Material", material(railMat))
				set(child, "Color", railColor)
				set(child, "Transparency", fence.rail.alpha or 0)
			elseif string.sub(name, 1, 4) == "Post" then
				set(child, "Material", material(fence.post.mat))
				set(child, "Color", postColor)
				set(child, "Transparency", 0)
			end
		end
	end
end

function PenDress.Restore(penModel: Instance)
	for _, child in penModel:GetChildren() do
		if child:IsA("BasePart") then
			set(child, "Material", Enum.Material.SmoothPlastic)
		end
	end
end

function PenDress.Caps(parent: Instance, penModel: Instance, plan): { BasePart }
	local parts = {}
	local cap = plan.fence.cap
	if not cap or plan.detail == "far" then
		return parts
	end
	for _, post in penModel:GetChildren() do
		if post:IsA("BasePart") and string.sub(post.Name, 1, 4) == "Post" then
			local top = post.CFrame * CFrame.new(0, post.Size.Y / 2, 0)
			table.insert(parts, buildPiece(cap, "Cap_" .. post.Name, top, {}, parent))
		end
	end
	return parts
end

-- Props -------------------------------------------------------------------------------------

function PenDress.Entries(parent: Instance, area: CFrame, entries, plan): { BasePart }
	local parts = {}
	local colors = palette(plan)
	for _, e in entries do
		local prop = e.prop
		if prop then
			local origin = area * CFrame.new(e.x, 0, e.z)
			if prop.mesh ~= "" then
				local part = buildMesh(prop, e, origin, parent)
				markAnchor(part, e)
				table.insert(parts, part)
			else
				for i, piece in Logic.Pieces(prop, plan.detail) do
					local part = buildPiece(piece, if i == 1 then e.id else e.id .. "_" .. i, origin, colors, parent)
					if i == 1 then
						markAnchor(part, e)
					end
					table.insert(parts, part)
				end
			end
		end
	end
	return parts
end

-- Garden ------------------------------------------------------------------------------------

function PenDress.Garden(parent: Instance, base: CFrame, garden, now: number, detail: string): { BasePart }
	local G = Config.Pens.Garden
	local parts = {}
	if type(garden) ~= "table" or type(garden.plots) ~= "table" then
		return parts
	end
	local frame = buildPiece(G.frame, "GardenFrame", base, {}, parent)
	frame:SetAttribute("Garden", true)
	table.insert(parts, frame)
	local frameTop = G.frame.size[2]
	local bw, bh, bd = G.bed[1], G.bed[2], G.bed[3]
	local cols = G.columns
	local rows = math.max(1, math.ceil(#garden.plots / cols))
	local soilColor = hex(G.soil.color, WHITE)
	for i, plot in garden.plots do
		local col, row = (i - 1) % cols, (i - 1) // cols
		local x = (col - (cols - 1) / 2) * G.spacing[1]
		local z = (row - (math.max(rows, 2) - 1) / 2) * G.spacing[2]
		local bedCf = base * CFrame.new(x, frameTop, z)
		local stage = Logic.CropStage(Config, plot, now)
		local soil =
			newPart("block", "Bed" .. i, Vector3.new(bw, bh, bd), bedCf * CFrame.new(0, bh / 2, 0), soilColor, material(G.soil.mat))
		soil:SetAttribute("GardenBed", i)
		soil:SetAttribute("CropStage", stage)
		if type(plot.flavor) == "string" then
			soil:SetAttribute("Flavor", plot.flavor)
		end
		soil.Parent = parent
		table.insert(parts, soil)
		if stage > 0 then
			local look = G.stages[stage]
			local flavor = Config.Food.ById[plot.flavor]
			local fruitColor = hex(flavor and flavor.color, WHITE)
			local offsets = if detail == "far" then { 0 } else G.plants
			for j, dz in offsets do
				local s = look.size
				local plantCf = bedCf * CFrame.new(0, bh + s[2] / 2, dz)
				local plant = newPart(
					"ball",
					"Crop" .. i .. "_" .. j,
					Vector3.new(s[1], s[2], s[3]),
					plantCf,
					hex(look.color, WHITE),
					material(look.mat)
				)
				plant.Parent = parent
				table.insert(parts, plant)
				if stage == 4 and detail ~= "far" then
					local f = G.fruit.size
					local fruit = newPart(
						"ball",
						"Fruit" .. i .. "_" .. j,
						Vector3.new(f[1], f[2], f[3]),
						plantCf * CFrame.new(0, s[2] / 2, 0),
						fruitColor,
						material(G.fruit.mat)
					)
					fruit.Parent = parent
					table.insert(parts, fruit)
				end
			end
			if stage == 4 then
				local g = G.glow
				local glow = newPart(
					"block",
					"Ready" .. i,
					Vector3.new(bw + g.pad * 2, g.height, bd + g.pad * 2),
					bedCf * CFrame.new(0, g.height / 2, 0),
					hex(g.color, WHITE),
					material(g.mat),
					g.alpha
				)
				glow:SetAttribute("Ready", true)
				glow.Parent = parent
				table.insert(parts, glow)
			end
		end
	end
	return parts
end

return PenDress
