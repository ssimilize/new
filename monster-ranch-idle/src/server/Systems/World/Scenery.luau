--[[
	World/Scenery: puts the decoration on the map once the world is in the Workspace. Where each
	item goes is Logic/Scenery's pure, seeded layout (so Scenery.spec can check it offline); this
	file only turns it into MeshParts. Each kind's mesh (World/SceneryMeshes, made with Roblox's
	mesh generator) is built once through ctx.Services.CreateMeshPart, which yields, and cloned
	for every item. Everything goes into one Folder "Scenery" that is parented last, so clients
	receive it in one step.

	Solid kinds collide (boulders, bushes and logs by their hull); a tree does not collide
	itself but gets an invisible trunk post (`trunk` x size wide), so the canopy does not block
	a walk under it. Small kinds (grass, flowers, mushrooms, stones) neither collide nor cast
	shadows. A kind whose mesh fails to load is left out; the rest still appear.

	The wall: Boundary/Wall<i> placeholders are hidden and replaced by wall and pillar meshes
	along Logic/Scenery.wall's segments, only if both meshes loaded. Barrier<i> always stays.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Layout = require(Shared.Logic.Scenery)

local Scenery = {}

local function kindsById(Config)
	local byId = {}
	for _, kind in Config.World.Scenery.kinds do
		byId[kind.id] = kind
	end
	return byId
end

-- Builds the Scenery folder under `world` and returns how many items it placed.
function Scenery.world(
	world: Instance,
	Config,
	mode: string?,
	meshes,
	createMeshPart: (string) -> MeshPart?,
	log: (string, ...any) -> ()
): number
	local World = Config.World
	local byId = kindsById(Config)
	local templates: { [string]: MeshPart | false } = {}

	local function template(id: string): MeshPart?
		local cached = templates[id]
		if cached ~= nil then
			return cached or nil
		end
		local data = meshes[id]
		local part = data and createMeshPart(data.mesh)
		if not part then
			log("no mesh for scenery %s: left out", id)
			templates[id] = false
			return nil
		end
		part.TextureID = data.texture
		part.Anchored = true
		part.CanTouch = false
		local kind = byId[id]
		local solid = kind == nil or kind.solid == true
		part.CanCollide = solid and not (kind and kind.trunk)
		part.CanQuery = solid
		part.CastShadow = solid
		part.Name = id
		templates[id] = part
		return part
	end

	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	local placed = 0
	local groundY = World.GroundY

	for _, item in Layout.layout(Config, mode) do
		local t = template(item.kind)
		if t then
			local part = t:Clone()
			local scale = item.size / math.max(t.Size.X, t.Size.Y, t.Size.Z)
			part.Size = t.Size * scale
			-- Sink a touch so rounded bases do not hover over the grass.
			local y = groundY + part.Size.Y / 2 - part.Size.Y * 0.03
			part.CFrame = CFrame.new(item.x, y, item.z) * CFrame.Angles(0, item.yaw, 0)
			part.Parent = folder
			local kind = byId[item.kind]
			local inside = math.abs(item.x) < World.Boundary.half and math.abs(item.z) < World.Boundary.half
			if kind and kind.trunk and inside then
				local post = Instance.new("Part")
				post.Name = "Trunk"
				post.Shape = Enum.PartType.Cylinder
				post.Anchored = true
				post.CanTouch = false
				post.Transparency = 1
				post.CastShadow = false
				local width = item.size * kind.trunk
				post.Size = Vector3.new(item.size * 0.5, width, width)
				post.CFrame = CFrame.new(item.x, groundY + item.size * 0.25, item.z) * CFrame.Angles(0, 0, math.rad(90))
				post.Parent = part
			end
			placed += 1
		end
	end

	-- The wall: swap the placeholder boxes for stone wall and pillar meshes.
	local boundary = world:FindFirstChild("Boundary")
	local B = World.Boundary
	local wall, pillar = template("wall"), template("pillar")
	if boundary and B and wall and pillar then
		-- The wall mesh runs along its longest horizontal axis; turn it to run along local X.
		local wallTurn = if wall.Size.Z > wall.Size.X then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new()
		for _, seg in Layout.wall(World) do
			local part
			if seg.kind == "wall" then
				part = wall:Clone()
				local size = Vector3.new(seg.length + 0.6, B.height, B.thickness + 1)
				part.Size = if wall.Size.Z > wall.Size.X then Vector3.new(size.Z, size.Y, size.X) else size
				part.CFrame = CFrame.new(seg.x, groundY + B.height / 2, seg.z) * CFrame.Angles(0, seg.yaw, 0) * wallTurn
			else
				part = pillar:Clone()
				part.Size = Vector3.new(B.thickness * 1.8, B.height * 1.4, B.thickness * 1.8)
				part.CFrame = CFrame.new(seg.x, groundY + part.Size.Y / 2, seg.z) * CFrame.Angles(0, seg.yaw, 0)
			end
			part.Parent = folder
		end
		for _, child in boundary:GetChildren() do
			if child:IsA("BasePart") and child.Name:sub(1, 4) == "Wall" then
				child.Transparency = 1
				child.CastShadow = false
				child.CanCollide = false
			end
		end
	end

	for _, t in templates do
		if t then
			t:Destroy()
		end
	end
	folder.Parent = world
	return placed
end

return Scenery
