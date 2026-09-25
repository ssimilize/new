--[[
	Publishes monster meshes as Roblox Mesh assets, from Studio (Edit), through the Studio MCP's
	execute_luau. Each form's mesh.json (written by export_roblox.py next to its rig.blend) is
	fetched over HTTP from a local server, built as a skinned EditableMesh and published with
	AssetService:CreateAssetAsync. The skin weights and bones survive: the game builds a MeshPart
	from the asset and bends it with Bone instances (verified 2026-09-25 on Cindlet).

	Run it with its arguments set in front of this file's text:
		_G.MeshPublishArgs = { base = "http://127.0.0.1:38517/rigs/", forms = { "cindlet", "kindlefox" } }
	(base serves <form>/mesh.json).
	It returns JSON: { done, took, ids = { form = "rbxassetid://N" | "error: ..." } }. Record the ids
	with tools/blender/asset_ids.py --json.

	Publishing takes about two seconds a mesh and an execute_luau call times out, so the work runs in
	a spawned thread and this call waits for it with a 55 s deadline; ten forms a call fit easily. If
	it was still running, a later call reads _G.MeshPublish. The run leaves _G.MeshPublishRun(base,
	forms) behind, so the next chunk is one short call in the same Studio session.
]]

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local SEXTET = {}
for i = 1, #ALPHABET do
	SEXTET[string.byte(ALPHABET, i)] = i - 1
end

local function decode(text: string): buffer
	local clean = string.gsub(text, "[^%w%+/]", "")
	local n = #clean
	local out = buffer.create(n // 4 * 3 + (if n % 4 == 3 then 2 elseif n % 4 == 2 then 1 else 0))
	local o, i = 0, 1
	while i + 3 <= n do
		local a, b, c, d = string.byte(clean, i, i + 3)
		local v = SEXTET[a] * 262144 + SEXTET[b] * 4096 + SEXTET[c] * 64 + SEXTET[d]
		buffer.writeu8(out, o, v // 65536)
		buffer.writeu8(out, o + 1, v // 256 % 256)
		buffer.writeu8(out, o + 2, v % 256)
		o += 3
		i += 4
	end
	if n - i + 1 >= 2 then
		local a, b = string.byte(clean, i, i + 1)
		local v = SEXTET[a] * 262144 + SEXTET[b] * 4096
		if n - i + 1 == 3 then
			v += SEXTET[string.byte(clean, i + 2)] * 64
			buffer.writeu8(out, o + 1, v // 256 % 256)
		end
		buffer.writeu8(out, o, v // 65536)
	end
	return out
end

local function build(data): EditableMesh
	local pos, nor, uv = decode(data.positions), decode(data.normals), decode(data.uvs)
	local tris, skin = decode(data.tris), decode(data.skin)
	local em = AssetService:CreateEditableMesh()
	assert(em, "no EditableMesh budget left")
	local verts, normals, uvs = table.create(data.vertices), table.create(data.vertices), table.create(data.vertices)
	for i = 0, data.vertices - 1 do
		local o = i * 12
		verts[i + 1] = em:AddVertex(Vector3.new(buffer.readf32(pos, o), buffer.readf32(pos, o + 4), buffer.readf32(pos, o + 8)))
		normals[i + 1] = em:AddNormal(Vector3.new(buffer.readf32(nor, o), buffer.readf32(nor, o + 4), buffer.readf32(nor, o + 8)))
		uvs[i + 1] = em:AddUV(Vector2.new(buffer.readf32(uv, i * 8), buffer.readf32(uv, i * 8 + 4)))
	end
	for t = 0, data.triangles - 1 do
		local a = buffer.readu16(tris, t * 6) + 1
		local b = buffer.readu16(tris, t * 6 + 2) + 1
		local c = buffer.readu16(tris, t * 6 + 4) + 1
		local face = em:AddTriangle(verts[a], verts[b], verts[c])
		em:SetFaceNormals(face, { normals[a], normals[b], normals[c] })
		em:SetFaceUVs(face, { uvs[a], uvs[b], uvs[c] })
	end
	local bones = {}
	for i, bone in data.bones do
		local c = bone.cframe
		bones[i] = em:AddBone({ Name = bone.name, CFrame = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7]), Virtual = false })
	end
	for i = 0, data.vertices - 1 do
		local o = i * 8
		local ids, weights = {}, {}
		for j = 0, 3 do
			local w = buffer.readu8(skin, o + 4 + j)
			if w > 0 then
				table.insert(ids, bones[buffer.readu8(skin, o + j) + 1])
				table.insert(weights, w / 255)
			end
		end
		if #ids > 0 then
			em:SetVertexBones(verts[i + 1], ids)
			em:SetVertexBoneWeights(verts[i + 1], weights)
		end
	end
	return em
end

_G.MeshPublishRun = function(base: string, forms: { string }): string
	_G.MeshPublish = { done = false, ids = {}, started = os.clock() }
	local state = _G.MeshPublish
	task.spawn(function()
		for _, form in forms do
			local ok, result = pcall(function()
				local data = HttpService:JSONDecode(HttpService:GetAsync(base .. form .. "/mesh.json", true))
				local em = build(data)
				local status, assetId = AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {
					Name = form .. " (Monster Ranch Idle)",
					Description = "Monster Ranch Idle monster mesh: " .. form,
				})
				em:Destroy()
				assert(status == Enum.CreateAssetResult.Success, tostring(status))
				return "rbxassetid://" .. tostring(assetId)
			end)
			state.ids[form] = if ok then result else "error: " .. tostring(result)
		end
		state.took = os.clock() - state.started
		state.done = true
	end)
	local deadline = os.clock() + 55
	while not state.done and os.clock() < deadline do
		task.wait(0.25)
	end
	return HttpService:JSONEncode({ done = state.done, took = state.took, ids = state.ids })
end

local args = _G.MeshPublishArgs
return _G.MeshPublishRun(args.base, args.forms)
