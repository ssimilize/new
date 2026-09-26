--[[
	PropMesh: generated prop meshes (tools/rbxgen, Roblox's own generator) swapped in for part-built
	visuals. Config/PropMeshes holds the published { mesh, texture } ids per prop.

		PropMesh.Replace(entry, parts, frame, parent) -> ()

	Everything is built from parts first, exactly as before; Replace then (deferred, so the rest of
	the model is built by then) loads the mesh - once per asset, cloned after, three tries - and,
	if the model still exists, fits it where `parts` are and hides them. Fit: in `frame`'s axes the
	parts' combined box is measured; the mesh is turned 90 degrees if its long side lies across the
	box's (plus `entry.turn` degrees), scaled so its largest side matches the box's largest (times
	`entry.scale`), centred on the box and stood on its bottom. Hidden parts keep their lights,
	prompts and attributes but stop colliding (no invisible walls where the mesh is not); the mesh
	does not collide either.

	The texture is fetched first: a prop whose texture does not load (a just-published image still
	in moderation fails to fetch) keeps its parts rather than showing a grey mesh. Where meshes
	cannot load (no AssetService.CreateMeshPartAsync, as in the Lune harness), nothing changes. PropMesh.SetSource(fn) lets specs hand in a MeshPart instead.
]]

local PropMesh = {}

local templates: { [string]: MeshPart | false } = {}
local loading: { [string]: boolean } = {}
local available: boolean? = nil
local source: ((entry: any) -> MeshPart)? = nil

local function valid(entry): boolean
	return type(entry) == "table" and type(entry.mesh) == "string" and entry.mesh ~= ""
end

function PropMesh.Available(): boolean
	if source then
		return true
	end
	if available == nil then
		available = pcall(function()
			assert(Content and Content.fromUri, "no Content")
			assert(game:GetService("AssetService").CreateMeshPartAsync, "no CreateMeshPartAsync")
		end)
	end
	return available == true
end

-- Tests: `fn(entry) -> MeshPart` instead of CreateMeshPartAsync (nil puts the real one back).
function PropMesh.SetSource(fn: ((entry: any) -> MeshPart)?)
	source = fn
	table.clear(templates)
end

-- Whether the texture fetches (true without one, or with a test source).
local function textureLoads(entry): boolean
	if source or not entry.texture or entry.texture == "" then
		return true
	end
	local fetched = false
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ entry.texture }, function(_id, status)
			fetched = status == Enum.AssetFetchStatus.Success
		end)
	end)
	return fetched
end

-- The prop's mesh at its generated size, made once; false after three failed tries or when its
-- texture does not load.
local function template(entry): MeshPart?
	local key = entry.mesh .. "|" .. (entry.texture or "")
	while loading[key] do
		task.wait()
	end
	local known = templates[key]
	if known ~= nil then
		return known or nil
	end
	loading[key] = true
	if not textureLoads(entry) then
		loading[key] = nil
		warn(string.format("[PropMesh] texture %s did not load; keeping the parts", tostring(entry.texture)))
		templates[key] = false
		return nil
	end
	local made: MeshPart? = nil
	local problem = nil
	for try = 1, 3 do
		local ok, result = pcall(function()
			if source then
				return source(entry)
			end
			return game:GetService("AssetService"):CreateMeshPartAsync(Content.fromUri(entry.mesh))
		end)
		if ok and result then
			made = result
			break
		end
		problem = result
		if try < 3 then
			task.wait(try)
		end
	end
	loading[key] = nil
	if not made then
		warn(string.format("[PropMesh] %s did not load: %s", entry.mesh, tostring(problem)))
		templates[key] = false
		return nil
	end
	local part = made :: MeshPart
	if entry.texture and entry.texture ~= "" then
		part.TextureID = entry.texture
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	templates[key] = part
	return part
end

-- The parts' combined box in `frame`'s axes: its centre (in frame space) and size.
local function boxOf(parts: { BasePart }, frame: CFrame): (Vector3?, Vector3?)
	local lo, hi = nil, nil
	for _, p in parts do
		local cf, half = frame:ToObjectSpace(p.CFrame), p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local c = cf * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
			end
		end
	end
	if not lo or not hi then
		return nil, nil
	end
	return (lo + hi) / 2, hi - lo
end

local function place(entry, parts: { BasePart }, frame: CFrame, parent: Instance)
	local centre, box = boxOf(parts, frame)
	if not centre or not box then
		return
	end
	local mesh = template(entry)
	if not mesh or parent.Parent == nil then
		return -- no mesh, or the model went while it loaded
	end
	for _, p in parts do
		if p.Parent == nil then
			return
		end
	end
	local size = mesh.Size
	local turn = math.rad(tonumber(entry.turn) or 0)
	if (box.X >= box.Z) ~= (size.X >= size.Z) and math.abs(size.X - size.Z) > 0.15 * math.max(size.X, size.Z) then
		turn += math.pi / 2
		size = Vector3.new(size.Z, size.Y, size.X)
	end
	local k = math.max(box.X, box.Y, box.Z) / math.max(size.X, size.Y, size.Z) * (tonumber(entry.scale) or 1)
	local copy = mesh:Clone()
	copy.Name = "PropMesh"
	copy.Size = mesh.Size * k
	local bottom = centre - Vector3.new(0, box.Y / 2, 0)
	copy.CFrame = frame * CFrame.new(bottom + Vector3.new(0, size.Y * k / 2, 0)) * CFrame.Angles(0, turn, 0)
	for _, p in parts do
		p.Transparency = 1
		p.CanCollide = false
		for _, d in p:GetChildren() do
			if d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
			end
		end
	end
	copy.Parent = parent
end

function PropMesh.Replace(entry, parts: { BasePart }, frame: CFrame, parent: Instance)
	if not valid(entry) or #parts == 0 or not PropMesh.Available() then
		return
	end
	task.defer(place, entry, table.clone(parts), frame, parent)
end

return PropMesh
