--[[
	Visuals/DecorModel (glow-up Z): builds one placed decor piece from Config/DecorArt parts.
	Art swap point: a piece whose Config.Decor `mesh` is not "" is drawn as one part holding a
	SpecialMesh (`texture`, sized `meshSize`) instead of its parts. Nothing here runs per frame.

	  DecorModel.Build(def, origin, detail, parent) -> Model, anchor, glow?
	      origin  ground-top CFrame of the piece (position and rotation)
	      detail  "full" | "far" (drops `small` parts)
	      anchor  the first part; attributes DecorId, and PenSpot = def.spot ("toy") when set
	      glow    the `glow` part of a light piece (where the night light sits), or nil
	  DecorModel.PartCount(def, detail) -> number

	Every part is anchored and non-colliding, off for touches and shadows. Parts stay queryable
	(CanQuery) so pen monsters can steer round them and placement mode can tap them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Art = require(Shared.Config.DecorArt)

local DecorModel = {}

local WHITE = Color3.new(1, 1, 1)

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

local function hex(value: string?): Color3
	if type(value) ~= "string" then
		return WHITE
	end
	local ok, color = pcall(Color3.fromHex, value)
	return if ok then color else WHITE
end

local function newPart(shape: string): BasePart
	if shape == "wedge" then
		return Instance.new("WedgePart")
	end
	local p = Instance.new("Part")
	if shape == "ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "cyl" then
		p.Shape = Enum.PartType.Cylinder
	end
	return p
end

local function finish(part: BasePart, name: string, size: Vector3, cf: CFrame, parent: Instance)
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
end

function DecorModel.PartCount(def, detail: string): number
	if def.mesh ~= nil and def.mesh ~= "" then
		return 1
	end
	local n = 0
	for _, piece in Art.Pieces(def) do
		if detail == "full" or not piece.small then
			n += 1
		end
	end
	return n
end

function DecorModel.Build(def, origin: CFrame, detail: string, parent: Instance): (Model, BasePart, BasePart?)
	local model = Instance.new("Model")
	model.Name = "Decor_" .. def.id
	local anchor: BasePart? = nil
	local glow: BasePart? = nil
	if def.mesh ~= nil and def.mesh ~= "" then
		local s = def.meshSize or { def.size[1], 3, def.size[2] }
		local size = Vector3.new(s[1], s[2], s[3])
		local part = newPart("block")
		finish(part, def.id, size, origin * CFrame.new(0, size.Y / 2, 0), model)
		part.Color = WHITE
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = def.mesh
		mesh.TextureId = def.texture or ""
		mesh.Parent = part
		anchor = part
		glow = if def.light then part else nil
	else
		for i, piece in Art.Pieces(def) do
			if i == 1 or detail == "full" or not piece.small then
				local s, a, r = piece.size, piece.at, piece.rot
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
				local part = newPart(piece.shape)
				finish(part, if i == 1 then def.id else def.id .. "_" .. i, size, cf, model)
				part.Color = hex(piece.color)
				part.Material = if piece.glow then Enum.Material.Neon else material(piece.mat)
				part.Transparency = piece.alpha or 0
				anchor = anchor or part
				if piece.glow and not glow then
					glow = part
				end
			end
		end
	end
	local root = anchor :: BasePart
	root:SetAttribute("DecorId", def.id)
	root:SetAttribute("PropId", def.id)
	if def.spot then
		root:SetAttribute("PenSpot", def.spot)
	end
	model.PrimaryPart = root
	model.Parent = parent
	return model, root, if def.light then glow else nil
end

return DecorModel
