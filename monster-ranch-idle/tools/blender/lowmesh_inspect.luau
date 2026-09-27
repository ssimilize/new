--[[
	Reads a model file downloaded from Roblox (tools/blender/upload_lowmesh.py saves each upload's
	model as <out>/<form>/model.rbxm) and prints one JSON line: every MeshPart's mesh id (MeshContent), size (InitialSize) and
	the Bone names under it, so the uploader can record the mesh id and check the import kept the
	rig's scale and bones.

		lune run tools/blender/lowmesh_inspect.luau <model.rbxm>
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local path = process.args[1]
local instances = roblox.deserializeModel(fs.readFile(path))

local parts = {}
local function visit(inst)
	if inst.ClassName == "MeshPart" then
		local bones = {}
		for _, d in inst:GetDescendants() do
			if d.ClassName == "Bone" then
				table.insert(bones, d.Name)
			end
		end
		local size = inst.InitialSize -- the mesh's own size; MeshSize is not in the file
		table.insert(parts, {
			name = inst.Name,
			meshId = inst.MeshContent.Uri or "",
			meshSize = { size.X, size.Y, size.Z },
			bones = bones,
		})
	end
	for _, child in inst:GetChildren() do
		visit(child)
	end
end
for _, inst in instances do
	visit(inst)
end
print(serde.encode("json", { parts = parts }))
